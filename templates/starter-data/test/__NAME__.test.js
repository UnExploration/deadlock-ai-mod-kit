// Unit tests for __NAME__'s script, run in Node with a mocked Panorama `$` and a fake storage client.
// Run `node --test` in the mod folder. The real storage client has its own tests in the kit (templates/kv-bridge).
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SCRIPT = path.join(__dirname, '..', 'src', 'panorama', 'scripts', '__NAME__.js');
const SRC = fs.readFileSync(SCRIPT, 'utf8');

function makePanel(type, id, props = {}) {
  return {
    paneltype: type, id, children: [], events: {}, ...props,
    FindChildTraverse(want) {
      for (const c of this.children) { if (c.id === want) return c; const d = c.FindChildTraverse(want); if (d) return d; }
      return null;
    },
    SetPanelEvent(name, fn) { this.events[name] = fn; },
  };
}

// A storage client that answers at once from a Map, or settles 'offline'.
function fakeBridge(store, state = 'ready', made = []) {
  return class {
    constructor(opts) { made.push(opts); }
    start() {}
    onSettled(cb) { cb(state); }
    get(k, cb) { cb(null, store.has(k) ? store.get(k) : null); }
    set(k, v, cb) { store.set(k, v); cb(null); }
    del(k, cb) { store.delete(k); cb(null); }
  };
}

function runInGame({ url = 'https://example.github.io/__NAME__-store/', store = new Map(), state = 'ready' } = {}) {
  const made = [];
  const ctx = makePanel('CitadelOverlay', 'root');
  const log = [];
  const $ = {
    GetContextPanel: () => ctx,
    CreatePanel: (type, parent, id, props) => { const p = makePanel(type, id, props); parent.children.push(p); return p; },
    Msg: (...a) => log.push(a.join('')),
    DispatchEvent: () => {},
  };
  vm.runInNewContext(SRC, { $, KVBridge: fakeBridge(store, state, made), __NAME__StoreUrl: url });
  const root = ctx.children[0];
  return { ctx, root, entry: root.children[0], status: root.children[1], store, log, made };
}

test('normalizeNote trims, collapses whitespace and strips control characters', () => {
  const mod = { exports: {} };
  vm.runInNewContext(SRC, { module: mod, $: {} });
  assert.strictEqual(mod.exports.normalizeNote('  a\n\tb   c\u0007 '), 'a b c');
  assert.strictEqual(mod.exports.normalizeNote('x'.repeat(500)).length, 200);
});

test('loads the saved note, and Enter saves a new one', () => {
  const g = runInGame({ store: new Map([['__NAME__.v1/note', 'old note']]) });
  assert.strictEqual(g.entry.text, 'old note');
  g.entry.text = '  new   note ';
  g.entry.events.oninputsubmit();
  assert.strictEqual(g.store.get('__NAME__.v1/note'), 'new note');
  assert.strictEqual(g.status.text, 'saved ✓');
  assert.ok(!g.log.some((l) => l.includes('note ') && l.includes('new')), 'never logs the note text');
});

test('an empty note deletes the saved one', () => {
  const g = runInGame({ store: new Map([['__NAME__.v1/note', 'old']]) });
  g.entry.text = '   ';
  g.entry.events.oninputsubmit();
  assert.ok(!g.store.has('__NAME__.v1/note'));
  assert.match(g.status.text, /note cleared/);
});

test('offline: says so and never writes', () => {
  const g = runInGame({ state: 'offline' });
  g.entry.text = 'hello';
  g.entry.events.oninputsubmit();
  assert.match(g.status.text, /not saved/);
  assert.strictEqual(g.store.size, 0);
});

test('talks to the storage page under its own namespace', () => {
  const g = runInGame();
  assert.strictEqual(g.made.length, 1);
  assert.strictEqual(g.made[0].ns, '__NAME__.v1');
  assert.strictEqual(g.made[0].page, 'https://example.github.io/__NAME__-store/');
  assert.strictEqual(g.made[0].protocol, 2);
});

test('no storage page address: says so and starts no bridge', () => {
  const g = runInGame({ url: '' });
  assert.match(g.status.text, /no storage page address/);
  assert.strictEqual(g.made.length, 0);
});
