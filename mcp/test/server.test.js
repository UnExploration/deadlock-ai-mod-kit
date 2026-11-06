// Drives the real server over stdio, with a fake PowerShell (DEADLOCK_MCP_RUNNER) that reports which
// tool script and arguments it got, and a fake game folder (DEADLOCK_MCP_CONTEXT). Touches nothing real.
// Run: node --test   (in mcp/)
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const SERVER = path.join(__dirname, '..', 'server.js');
const REPO = path.resolve(__dirname, '..', '..');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dmk-mcp-'));
const fakeRunner = path.join(tmp, 'fake-pwsh.js');
fs.writeFileSync(fakeRunner, `
const path = require('path');
const [script, ...args] = process.argv.slice(2);
console.log('RAN ' + JSON.stringify({ script: path.basename(script), args }));
console.log('DIR ' + path.dirname(script));
process.exit(Number(process.env.FAKE_EXIT || 0));
`);
const game = path.join(tmp, 'Deadlock');
const kitHome = path.join(tmp, 'kit');
fs.mkdirSync(path.join(game, 'game', 'citadel'), { recursive: true });
fs.mkdirSync(path.join(kitHome, 'catalog', '6801'), { recursive: true });
fs.writeFileSync(path.join(kitHome, 'catalog', '6801', 'soundevents.tsv'),
  'event\tfile\tvsnd_files\tduration\nDamage.Send.Lethal\tsoundevents/damage.vsndevts\tsounds/hit_indicators/damage_send_lethal_01.vsnd_c\t1.55\nUI.MainMenu.Hover\tsoundevents/ui.vsndevts\tsounds/ui/ui_menu_hover_01.vsnd_c\t0.2\n');
fs.writeFileSync(path.join(game, 'game', 'citadel', 'console.log'),
  'noise line\n[PanoramaScript] [badge] loaded in CitadelOverlay (v0.1.0)\nmore noise\n[PanoramaScript] JS Exception: TypeError x\n[PanoramaScript] [other] hi\n');
const modDir = path.join(tmp, 'mymod');
fs.mkdirSync(path.join(modDir, 'test'), { recursive: true });
fs.writeFileSync(path.join(modDir, 'mod.json'), '{"name":"mymod","pak":60}');
fs.writeFileSync(path.join(modDir, 'test', 'a.test.js'), "require('node:test')('ok', () => {});");

function startServer(env = {}) {
  const child = spawn(process.execPath, [SERVER], {
    env: { ...process.env, DEADLOCK_MCP_RUNNER: JSON.stringify([process.execPath, fakeRunner]), DEADLOCK_MCP_CONTEXT: JSON.stringify({ root: game, build: 6801, kitHome }), ...env },
    stdio: ['pipe', 'pipe', 'inherit'],
  });
  const waiting = new Map();
  let buf = '', seq = 0;
  child.stdout.on('data', (d) => {
    buf += d;
    let n;
    while ((n = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, n); buf = buf.slice(n + 1);
      const msg = JSON.parse(line);
      if (waiting.has(msg.id)) { waiting.get(msg.id)(msg); waiting.delete(msg.id); }
    }
  });
  const request = (method, params) => new Promise((resolve) => {
    const id = ++seq;
    waiting.set(id, resolve);
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
  const call = async (name, args) => (await request('tools/call', { name, arguments: args })).result;
  const ran = (result) => JSON.parse(result.content[0].text.match(/^RAN (.*)$/m)[1]);
  return { child, request, call, ran, notify: (method) => child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method }) + '\n') };
}

const s = startServer();
test.after(() => { s.child.stdin.end(); fs.rmSync(tmp, { recursive: true, force: true }); });

test('initialize: negotiates the protocol, names the server, gives instructions', async () => {
  const r = (await s.request('initialize', { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 't', version: '1' } })).result;
  assert.strictEqual(r.protocolVersion, '2025-03-26');
  assert.strictEqual(r.serverInfo.name, 'deadlock-ai-mod-kit');
  assert.ok(r.capabilities.tools);
  assert.match(r.instructions, /cookbook/);
  // The two layers of knowledge and the refresh rule (AGENTS.md § Two kinds of knowledge).
  assert.ok(r.instructions.includes('generated/ (kit_docs path "generated/README.md")'), 'instructions name generated/');
  assert.ok(r.instructions.includes('docs/ (kit_docs path "docs/README.md")'), 'instructions name docs/');
  assert.ok(r.instructions.includes('run setup or catalog_refresh first; never edit generated/ by hand'), 'instructions give the refresh rule');
  s.notify('notifications/initialized');
  const r2 = (await s.request('initialize', { protocolVersion: '1999-01-01' })).result;
  assert.strictEqual(r2.protocolVersion, '2025-06-18');
});

test('tools/list: every tool has a description, an object schema and annotations', async () => {
  const { tools } = (await s.request('tools/list', {})).result;
  const names = tools.map((t) => t.name).sort();
  assert.deepStrictEqual(names, ['build_mod', 'catalog_refresh', 'catalog_search', 'convert_model', 'disable_mod', 'doctor', 'export_mod', 'get_stock', 'install_mod',
    'kit_docs', 'list_mods', 'mount_addons', 'new_mod', 'prepare_audio', 'preview_model', 'read_console_log', 'rebase_mod', 'reset_all', 'setup', 'storage', 'test_mod', 'uninstall_mod', 'vpk_list']);
  for (const t of tools) {
    assert.ok(t.description.length > 40, t.name);
    assert.strictEqual(t.inputSchema.type, 'object', t.name);
    assert.ok(t.annotations, t.name);
  }
});

test('unknown methods get a JSON-RPC error; bad arguments a tool error', async () => {
  assert.strictEqual((await s.request('nope/nope', {})).error.code, -32601);
  const r = await s.call('new_mod', { name: 'Bad Name' });
  assert.ok(r.isError);
  assert.match(r.content[0].text, /must match/);
  assert.match((await s.call('mount_addons', { action: 'explode' })).content[0].text, /must be one of/);
  assert.match((await s.call('doctor', { extra: 1 })).content[0].text, /unknown argument/);
  assert.ok((await s.call('reset_all', { confirm: false })).isError);
});

test('each action runs the right tool with the right arguments', async () => {
  const cases = [
    ['doctor', { offline: true }, 'doctor.ps1', ['-Offline']],
    ['setup', {}, 'setup.ps1', []],
    ['setup', { approve: ['csdk', 's2v'] }, 'setup.ps1', ['-Approve', 'csdk,s2v']],
    ['setup', { media: true }, 'setup.ps1', ['-Media']],
    ['setup', { models: true }, 'setup.ps1', ['-Models']],
    ['setup', { approve: ['blender'] }, 'setup.ps1', ['-Approve', 'blender']],
    ['setup', { skipData: true, offline: true }, 'setup.ps1', ['-SkipData', '-Offline']],
    ['convert_model', { source: 'dl/pumpkin.glb', out: 'mods/p/src/models/x/pumpkin', like: 'models/x/box.vmdl_c', fit: 'largest', copyStockMaterial: true, upAxis: 'Z', rotateZ: 90 }, 'convert-model.ps1',
      ['-In', path.join(REPO, 'dl', 'pumpkin.glb'), '-Out', path.join(REPO, 'mods', 'p', 'src', 'models', 'x', 'pumpkin'), '-Like', 'models/x/box.vmdl_c', '-Fit', 'largest', '-UpAxis', 'Z', '-RotateZ', '90', '-CopyStockMaterial']],
    ['convert_model', { source: 'a.obj', out: 'mods/p/src/models/x/a', likeMaterial: 'models/x/box.vmat_c', glow: true, glowTint: [1, 0.5, 0] }, 'convert-model.ps1',
      ['-In', path.join(REPO, 'a.obj'), '-Out', path.join(REPO, 'mods', 'p', 'src', 'models', 'x', 'a'), '-LikeMaterial', 'models/x/box.vmat_c', '-Glow', '-GlowTint', '1,0.5,0']],
    ['preview_model', { mod: modDir, path: 'models/x/box.vmdl_c' }, 'preview-model.ps1', ['-Mod', modDir, '-Path', 'models/x/box.vmdl_c']],
    ['preview_model', { model: 'mods/p/src/models/x/pumpkin/pumpkin.obj', stock: 'models/x/box.vmdl_c', noStock: false }, 'preview-model.ps1',
      ['-Model', path.join(REPO, 'mods', 'p', 'src', 'models', 'x', 'pumpkin', 'pumpkin.obj'), '-Stock', 'models/x/box.vmdl_c']],
    ['prepare_audio', { source: 'https://youtu.be/x', out: 'mods/k/src/a.wav', start: '1:02', like: 'Damage.Send.Lethal' }, 'audio.ps1',
      ['https://youtu.be/x', '-Out', path.join(REPO, 'mods', 'k', 'src', 'a.wav'), '-Start', '1:02', '-Like', 'Damage.Send.Lethal']],
    ['mount_addons', { action: 'enable' }, 'enable-addons.ps1', []],
    ['mount_addons', { action: 'disable' }, 'enable-addons.ps1', ['-Disable']],
    ['new_mod', { name: 'notes', kind: 'data', pak: 66, storeUrl: 'kit' }, 'new-mod.ps1', ['-Name', 'notes', '-Dir', path.join(REPO, 'mods'), '-Kind', 'data', '-Pak', '66', '-StoreUrl', 'kit']],
    ['new_mod', { name: 'notes', kind: 'data', storeUrl: 'https://someone.github.io/notes-store/' }, 'new-mod.ps1', ['-Name', 'notes', '-Dir', path.join(REPO, 'mods'), '-Kind', 'data', '-StoreUrl', 'https://someone.github.io/notes-store/']],
    ['storage', { mod: modDir }, 'store.ps1', ['-Mod', modDir]],
    ['catalog_refresh', { force: true }, 'generate-docs.ps1', ['-Force']],
    ['catalog_refresh', {}, 'generate-docs.ps1', []],
    ['get_stock', { paths: ['panorama/layout/a.xml'], raw: true }, 'get-stock.ps1', ['panorama/layout/a.xml', '-Raw']],
    ['build_mod', { mod: modDir }, 'build.ps1', ['-Mod', modDir]],
    ['install_mod', { mod: modDir }, 'build.ps1', ['-Mod', modDir, '-Install']],
    ['uninstall_mod', { mod: 'mymod' }, 'mods.ps1', ['remove', 'mymod', '-Yes']],
    ['disable_mod', { mod: 'mymod' }, 'mods.ps1', ['disable', 'mymod']],
    ['disable_mod', { mod: '61', enable: true }, 'mods.ps1', ['enable', '61']],
    ['list_mods', { action: 'conflicts' }, 'mods.ps1', ['conflicts']],
    ['reset_all', { confirm: true }, 'mods.ps1', ['reset', '-Yes']],
    ['rebase_mod', { mod: modDir }, 'rebase.ps1', ['-Mod', modDir]],
    ['export_mod', { mod: modDir }, 'export.ps1', ['-Mod', modDir]],
    ['storage', { mod: modDir, publish: true }, 'store.ps1', ['-Mod', modDir, '-Publish']],
  ];
  for (const [name, args, script, expected] of cases) {
    const r = await s.call(name, args);
    assert.ok(!r.isError, name + ': ' + r.content[0].text);
    assert.deepStrictEqual(s.ran(r), { script, args: expected }, name);
  }
});

test('a bare mod name is a folder in mods/; a missing mod is a clear error', async () => {
  const mods = path.join(REPO, 'mods');
  const hadMods = fs.existsSync(mods);
  const name = 'dmk-mcp-test-' + process.pid;
  const dir = path.join(mods, name);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'mod.json'), '{"name":"x","pak":60}');
  try {
    const r = await s.call('build_mod', { mod: name });
    assert.deepStrictEqual(s.ran(r).args, ['-Mod', dir]);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
    if (!hadMods) fs.rmSync(mods, { recursive: true, force: true });
  }
  const missing = await s.call('build_mod', { mod: 'does_not_exist' });
  assert.ok(missing.isError);
  assert.match(missing.content[0].text, /new_mod/);
  assert.ok(missing.content[0].text.includes(path.join(REPO, 'mods', 'does_not_exist')));
});

test('setup runs the root setup.ps1; the other tools run from tools/', async () => {
  const dir = (r) => r.content[0].text.match(/^DIR (.*)$/m)[1];
  assert.strictEqual(path.resolve(dir(await s.call('setup', {}))), REPO);
  assert.strictEqual(path.resolve(dir(await s.call('doctor', {}))), path.join(REPO, 'tools'));
});

test('exit codes: failures are errors; "waiting for the user" and "not mounted" are not', async () => {
  const f = startServer({ FAKE_EXIT: '2' });
  try {
    assert.match((await f.call('setup', { approve: ['csdk'] })).content[0].text, /waiting for the user/);
    assert.ok(!(await f.call('setup', { approve: ['csdk'] })).isError);
    assert.ok((await f.call('build_mod', { mod: modDir })).isError);
  } finally { f.child.stdin.end(); }
  const g = startServer({ FAKE_EXIT: '1' });
  try {
    const r = await g.call('mount_addons', { action: 'check' });
    assert.ok(!r.isError);
    assert.match(r.content[0].text, /not mounted/);
  } finally { g.child.stdin.end(); }
});

test('catalog_search filters rows of the current build', async () => {
  const r = await s.call('catalog_search', { table: 'soundevents', query: 'lethal' });
  assert.match(r.content[0].text, /build 6801, soundevents: 1 match/);
  assert.match(r.content[0].text, /damage_send_lethal_01/);
  assert.doesNotMatch(r.content[0].text, /hover/);
  assert.ok((await s.call('catalog_search', { table: 'heroes', query: 'x' })).isError, 'missing table says to refresh');
  assert.match((await s.call('catalog_search', { table: 'soundevents', query: 'x', column: 'nope' })).content[0].text, /Columns: event/);
});

test('catalog_search finds a model by its plain-words alias', async () => {
  fs.writeFileSync(path.join(kitHome, 'catalog', '6801', 'models.tsv'),
    'path\taliases\tbytes\tanim\tskeleton\tmaterials\ttextures\tother\nmodels/hideout/fortune_teller.vmdl_c\thideout, fortune teller, oracle\t1\tclassic\tin model\tm.vmat_c\tt.vtex_c\t\nmodels/npc/trooper/trooper.vmdl_c\ttrooper\t1\tclassic\tin model\t\t\t\n');
  const r = await s.call('catalog_search', { table: 'models', query: 'oracle', column: 'aliases' });
  assert.match(r.content[0].text, /models: 1 match/);
  assert.match(r.content[0].text, /fortune_teller\.vmdl_c.*t\.vtex_c/);
});

test('read_console_log: mod lines and errors by default, one mod on request', async () => {
  const all = (await s.call('read_console_log', {})).content[0].text;
  assert.match(all, /\[badge\] loaded/);
  assert.match(all, /JS Exception/);
  assert.doesNotMatch(all, /noise/);
  const one = (await s.call('read_console_log', { mod: 'badge' })).content[0].text;
  assert.match(one, /\[badge\]/);
  assert.doesNotMatch(one, /\[other\]/);
  assert.match(one, /JS Exception/);
});

test('kit_docs reads the cookbook and refuses paths outside the kit', async () => {
  assert.match((await s.call('kit_docs', {})).content[0].text, /# Cookbook/);
  assert.match((await s.call('kit_docs', { path: 'cookbook/sounds.md' })).content[0].text, /Damage\.Send\.Lethal/);
  assert.ok((await s.call('kit_docs', { path: '../../AGENTS.md' })).isError);
  assert.match((await s.call('kit_docs', { path: 'cookbook/nope.md' })).content[0].text, /sounds\.md/);
});

test('kit_docs reads from the kit root and refuses mods, node_modules and anything outside', async () => {
  const skill = await s.call('kit_docs', { path: 'SKILL.md' });
  assert.ok(!skill.isError, skill.content[0].text);
  assert.match(skill.content[0].text, /^---\s+name: deadlock-modding/);
  assert.ok((await s.call('kit_docs', { path: '../WORKPLAN.md' })).isError);
  assert.ok((await s.call('kit_docs', { path: 'mods/x' })).isError);
  assert.ok((await s.call('kit_docs', { path: 'mcp/node_modules/x' })).isError);
  assert.ok((await s.call('kit_docs', { path: '.git/config' })).isError);
});

test('test_mod runs the mod\'s node tests', async () => {
  const r = await s.call('test_mod', { mod: modDir });
  assert.ok(!r.isError, r.content[0].text);
  assert.match(r.content[0].text, /pass 1/);
});
