// Runs kvbridge.js against the real shared page script (store/index.html at the kit's root) with a
// mocked Panorama `$` and a simulated CEF page (fragment navigation, document.title -> HTMLTitle
// fired twice, shared localStorage). The page honours each request's namespace (ns) itself.
// No dependencies: `node --test` (from templates/kv-bridge).
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const ROOT = path.join(__dirname, '..');
const KIT = path.join(ROOT, '..', '..');
const PAGE = 'https://example.github.io/mymod-store/';
const NS = 'mymod.v1';
const PAGE_SRC = fs.readFileSync(path.join(KIT, 'store', 'index.html'), 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
const CLIENT_SRC = fs.readFileSync(path.join(ROOT, 'kvbridge.js'), 'utf8');
const MS_PER_SEC = 5; // Panorama seconds -> test milliseconds

function makeStorage(map = new Map()) {
  return {
    map,
    get length() { return map.size; },
    key: (n) => [...map.keys()][n] ?? null,
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => { map.set(k, String(v)); },
    removeItem: (k) => { map.delete(k); },
  };
}

// A fake CitadelHTMLPanel whose "browser" runs the store page script.
function makeHtmlPanel(storage, opts = {}) {
  const panel = { style: {}, handlers: {}, hittest: true, urls: [], dead: false };
  let page = null;
  const fire = (name, arg) => (panel.handlers[name] || []).forEach((fn) => fn(panel, arg));
  panel.IsValid = () => !panel.dead;
  panel.SetURL = (url) => {
    panel.urls.push(url);
    setImmediate(() => fire('HTMLURLChanged', url));   // worst case: CEF reports every navigation, fragment included
    const [base, hash = ''] = url.split('#');
    if (opts.blank || !/^https:\/\//i.test(base)) { setImmediate(() => fire('HTMLURLChanged', 'about:blank')); return; }
    if (page && page.base === base) {
      page.location.hash = '#' + hash;
      setImmediate(() => page.hashListeners.forEach((fn) => fn()));
      return;
    }
    const u = new URL(base);
    page = { base, hashListeners: [], location: { hash: '#' + hash, origin: opts.origin || u.origin, pathname: u.pathname } };
    const document = {};
    let title = '';
    Object.defineProperty(document, 'title', {
      get: () => title,
      set: (t) => { title = t; setImmediate(() => { fire('HTMLTitle', t); fire('HTMLTitle', t); }); },
    });
    const window = { addEventListener: (ev, fn) => { if (ev === 'hashchange') page.hashListeners.push(fn); } };
    setImmediate(() => vm.runInNewContext(PAGE_SRC, { location: page.location, localStorage: storage, document, window }));
  };
  return panel;
}

function loadClient(storage, panelOpts) {
  const created = [];
  const $ = {
    Schedule: (sec, fn) => setTimeout(fn, sec * MS_PER_SEC),
    CancelScheduled: (h) => clearTimeout(h),
    CreatePanel: (type, parent, id) => { assert.strictEqual(type, 'CitadelHTMLPanel'); const p = makeHtmlPanel(storage, panelOpts); p.id = id; created.push(p); return p; },
    RegisterEventHandler: (name, panel, fn) => { (panel.handlers[name] = panel.handlers[name] || []).push(fn); },
  };
  const ctx = { $, Date, JSON, String, encodeURIComponent };
  vm.runInNewContext(CLIENT_SRC + '\n;globalThis.KVBridge = KVBridge;', ctx);
  return { KVBridge: ctx.KVBridge, created };
}

const parent = { FindChildTraverse: () => null };
const settle = (b) => new Promise((r) => b.onSettled(r));
const call = (fn, ...args) => new Promise((r) => fn(...args, (...res) => r(res)));

async function connect(storage = makeStorage(), panelOpts, page = PAGE, ns = NS) {
  const { KVBridge, created } = loadClient(storage, panelOpts);
  const logs = [];
  const b = new KVBridge({ page, ns, prefix: 'KV1:', log: (s) => logs.push(s) });
  b.start(parent, 'TestBridge');
  return { b, state: await settle(b), created, storage, logs };
}

test('hello handshake reaches ready and hides the panel', async () => {
  const { state, created } = await connect();
  assert.strictEqual(state, 'ready');
  assert.strictEqual(created[0].style.width, '2px');
  assert.strictEqual(created[0].hittest, false);
});

test('set/get/del round trip, JSON helpers, and missing keys', async () => {
  const { b } = await connect();
  assert.deepStrictEqual(await call(b.set.bind(b), 'mymod.v1/123', 'hello'), [null]);
  assert.deepStrictEqual(await call(b.get.bind(b), 'mymod.v1/123'), [null, 'hello']);
  await call(b.setJSON.bind(b), 'mymod.v1/obj', { note: 'flames "lane"', n: 1 });
  assert.deepStrictEqual(await call(b.getJSON.bind(b), 'mymod.v1/obj'), [null, { note: 'flames "lane"', n: 1 }]);
  await call(b.del.bind(b), 'mymod.v1/123');
  assert.deepStrictEqual(await call(b.get.bind(b), 'mymod.v1/123'), [null, null]);
});

test('data survives a restart (new client + new page, same storage)', async () => {
  const storage = makeStorage();
  const first = await connect(storage);
  await call(first.b.set.bind(first.b), 'mymod.v1/89583706', 'remember me');
  const second = await connect(storage);
  assert.deepStrictEqual(await call(second.b.get.bind(second.b), 'mymod.v1/89583706'), [null, 'remember me']);
});

test('page rejects keys outside the namespace and oversized values', async () => {
  const { b } = await connect();
  assert.deepStrictEqual(await call(b.set.bind(b), 'other/1', 'x'), ['bad_key']);
  assert.deepStrictEqual(await call(b.set.bind(b), 'mymod.v1/big', 'x'.repeat(5000)), ['value_too_big']);
});

test('concurrent requests are serialized and each callback fires exactly once', async () => {
  const { b } = await connect();
  const seen = [];
  await Promise.all(Array.from({ length: 10 }, (_, n) => new Promise((r) => b.set(`mymod.v1/k${n}`, String(n), (e) => { seen.push(n); r(e); }))));
  assert.deepStrictEqual(seen, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  const [err, v] = await call(b.get.bind(b), 'mymod.v1/k7');
  assert.strictEqual(err, null);
  assert.strictEqual(v, '7');
});

test('list pages through many keys', async () => {
  const storage = makeStorage();
  for (let n = 0; n < 400; n++) storage.setItem(`mymod.v1/${String(n).padStart(10, '0')}`, '{}');
  storage.setItem('someoneelse/1', '{}');
  const { b } = await connect(storage);
  const [err, keys] = await call(b.list.bind(b), 'mymod.v1/');
  assert.strictEqual(err, null);
  assert.strictEqual(keys.length, 400);
});

test('non-https page or blocked panel ends offline and fails requests fast', async () => {
  const { b, state } = await connect(makeStorage(), { blank: true });
  assert.strictEqual(state, 'offline');
  assert.deepStrictEqual(await call(b.get.bind(b), 'mymod.v1/1'), ['offline', null]);
});

test('a page answering from a different address is not trusted', async () => {
  const { state } = await connect(makeStorage(), { origin: 'https://evil.example' });
  assert.strictEqual(state, 'offline');
});

test('logs never contain request fragments (user text)', async () => {
  const { b, logs } = await connect();
  await call(b.set.bind(b), 'mymod.v1/1', 'SECRET note text');
  await new Promise((r) => setImmediate(r));
  assert.ok(logs.some((l) => l.startsWith('bridge url ')), 'url changes are logged');
  assert.ok(!logs.some((l) => l.includes('SECRET') || l.includes('%22') || l.includes('#')), logs.join('\n'));
});

test('a throwing callback does not stall the queue', async () => {
  const { b, logs } = await connect();
  b.set('mymod.v1/a', '1', () => { throw new Error('boom'); });
  assert.deepStrictEqual(await call(b.get.bind(b), 'mymod.v1/a'), [null, '1']);
  assert.ok(logs.some((l) => l.includes('callback error')));
});

test('a destroyed panel fails requests and goes offline instead of calling SetURL', async () => {
  const { b, created } = await connect();
  created[0].dead = true;
  const before = created[0].urls.length;
  assert.deepStrictEqual(await call(b.get.bind(b), 'mymod.v1/1'), ['panel_gone', null]);
  assert.strictEqual(b.state, 'offline');
  assert.strictEqual(created[0].urls.length, before);
});

test('page address comparison ignores case', async () => {
  const { state } = await connect(makeStorage(), undefined, 'https://Example.GitHub.io/mymod-store/');
  assert.strictEqual(state, 'ready');
});

test('values are bounded by escaped size, so anything saved can be read back', async () => {
  const { b } = await connect();
  assert.deepStrictEqual(await call(b.set.bind(b), 'mymod.v1/q', '"'.repeat(2400)), ['value_too_big']);
  const ok = '"'.repeat(1700);                                   // escapes to ~3402 chars
  assert.deepStrictEqual(await call(b.set.bind(b), 'mymod.v1/q', ok), [null]);
  assert.deepStrictEqual(await call(b.get.bind(b), 'mymod.v1/q'), [null, ok]);
});

test('list ignores foreign keys under the prefix and always terminates', async () => {
  const storage = makeStorage();
  storage.setItem('mymod.v1/' + 'x'.repeat(5000), 'junk');     // too long for KEY_RE
  storage.setItem('mymod.v1/ok', '{}');
  const { b } = await connect(storage);
  const [err, keys] = await call(b.list.bind(b), 'mymod.v1/');
  assert.deepStrictEqual([err, [...keys]], [null, ['mymod.v1/ok']]);   // copy out of the vm realm
});

test('requests before start() fail fast', async () => {
  const { KVBridge } = loadClient(makeStorage());
  const b = new KVBridge({ page: PAGE, ns: NS, prefix: 'KV1:' });
  assert.deepStrictEqual(await call(b.get.bind(b), 'mymod.v1/1'), ['not_started', null]);
});

const decode = (url) => JSON.parse(decodeURIComponent(url.split('#')[1]));

test('every request carries the namespace, and hello speaks protocol 2', async () => {
  const { b, created } = await connect();
  await call(b.set.bind(b), 'mymod.v1/a', '1');
  const sent = created[0].urls.map(decode);
  assert.ok(sent.length >= 2);
  assert.ok(sent.every((m) => m.ns === NS), JSON.stringify(sent));
  assert.strictEqual(b.protocol, 2);
});

test('one page, two mods: each sees only its own keys', async () => {
  const storage = makeStorage();
  const a = await connect(storage, undefined, PAGE, 'alpha.v1');
  const z = await connect(storage, undefined, PAGE, 'zeta-mod.v2');
  assert.deepStrictEqual(await call(a.b.set.bind(a.b), 'alpha.v1/x', 'from alpha'), [null]);
  assert.deepStrictEqual(await call(z.b.set.bind(z.b), 'zeta-mod.v2/x', 'from zeta'), [null]);
  assert.deepStrictEqual(await call(z.b.get.bind(z.b), 'alpha.v1/x'), ['bad_key', null]);
  assert.deepStrictEqual(await call(z.b.set.bind(z.b), 'alpha.v1/x', 'overwrite'), ['bad_key']);
  assert.deepStrictEqual(await call(a.b.get.bind(a.b), 'alpha.v1/x'), [null, 'from alpha']);
  const [err, keys] = await call(z.b.list.bind(z.b), 'zeta-mod.v2/');
  assert.deepStrictEqual([err, [...keys]], [null, ['zeta-mod.v2/x']]);
  const [perr, pkeys] = await call(z.b.list.bind(z.b), 'alpha.v1/');
  assert.deepStrictEqual([perr, [...pkeys]], ['bad_prefix', []]);
});

test('the page rejects a bad namespace, and the bridge goes offline at once', async () => {
  for (const ns of ['MyMod.v1', 'mymod', 'mymod.v1/', '../x.v1', 'a'.repeat(41) + '.v1']) {
    const { state, created } = await connect(makeStorage(), undefined, PAGE, ns);
    assert.strictEqual(state, 'offline', ns);
    assert.strictEqual(created[0].urls.length, 1, ns + ': no hello retries after bad_ns');
  }
});

test('a bridge without a namespace settles offline without loading the page', async () => {
  const { KVBridge, created } = loadClient(makeStorage());
  const b = new KVBridge({ page: PAGE, prefix: 'KV1:' });
  b.start(parent, 'TestBridge');
  assert.strictEqual(await settle(b), 'offline');
  assert.strictEqual(created[0].urls.length, 0);
});

test('a page that answers for another namespace is not trusted', async () => {
  const { KVBridge } = loadClient(makeStorage());
  const panel = makeHtmlPanel(makeStorage());
  const realSetURL = panel.SetURL;
  // Rewrite each request's ns on its way to the page, so the page echoes a different namespace.
  panel.SetURL = (url) => { const m = decode(url); m.ns = 'other.v1'; realSetURL(url.split('#')[0] + '#' + encodeURIComponent(JSON.stringify(m))); };
  const b = new KVBridge({ page: PAGE, ns: NS, prefix: 'KV1:' });
  b.start({ FindChildTraverse: () => panel }, 'TestBridge');
  assert.strictEqual(await settle(b), 'offline');
});
