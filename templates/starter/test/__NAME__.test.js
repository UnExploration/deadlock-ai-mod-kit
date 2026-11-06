// Unit tests for __NAME__'s script, run in Node with a mocked Panorama `$`. Run `node --test` in the mod folder.
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SCRIPT = path.join(__dirname, '..', 'src', 'panorama', 'scripts', '__NAME__.js');
const SRC = fs.readFileSync(SCRIPT, 'utf8');

// Minimal fake panel tree: just what the script uses.
function makePanel(type, id, props = {}) {
  const panel = {
    paneltype: type, id, children: [], ...props,
    FindChildTraverse(want) {
      for (const c of this.children) { if (c.id === want) return c; const d = c.FindChildTraverse(want); if (d) return d; }
      return null;
    },
  };
  return panel;
}

// Runs the script the way Panorama does (no `module`), against a fresh context panel.
function runInGame(ctx, log = []) {
  const $ = {
    GetContextPanel: () => ctx,
    CreatePanel: (type, parent, id, props) => { const p = makePanel(type, id, props); parent.children.push(p); return p; },
    Msg: (...args) => log.push(args.join('')),
  };
  vm.runInNewContext(SRC, { $ });
  return log;
}

test('badge text names the mod and version', () => {
  const mod = { exports: {} };
  vm.runInNewContext(SRC, { module: mod, $: {} });
  assert.strictEqual(mod.exports.badgeText('1.2.3'), '__NAME__ v1.2.3');
});

test('creates the badge once and logs that it loaded', () => {
  const ctx = makePanel('CitadelOverlay', 'root');
  const log = runInGame(ctx);
  runInGame(ctx, log); // the script re-runs per layout instance; it must not duplicate the badge
  assert.strictEqual(ctx.children.length, 1);
  assert.match(ctx.children[0].children[0].text, /^__NAME__ v/);
  assert.deepStrictEqual(log, ['[__NAME__] loaded in CitadelOverlay (v0.1.0)']);
});
