// probe.js: answer "what does C++ put in this panel?" questions in a live Deadlock session.
// Include it from any hooked layout (or paste the body into the Panorama debugger's JS console),
// then read the [probe] lines in console.log (launch with -condebug). docs/05-dev-loop.md.
'use strict';

var Probe = (function () {
  var TAG = '[probe] ';
  function log(s) { $.Msg(TAG + s); }

  function safe(fn, fallback) { try { return fn(); } catch (e) { return fallback === undefined ? '<' + e + '>' : fallback; } }

  // Topmost ancestor of this script's context panel.
  function root() {
    var p = $.GetContextPanel();
    while (p && p.GetParent && p.GetParent()) p = p.GetParent();
    return p;
  }

  function describe(p) {
    var s = safe(function () { return p.paneltype; }) + '#' + safe(function () { return p.id; });
    var text = safe(function () { return p.text; }, undefined);
    if (typeof text === 'string' && text.length) s += ' text="' + text.slice(0, 60) + '"';
    var acct = safe(function () { return p.accountid; }, undefined);
    if (acct !== undefined && acct !== null && acct !== '') s += ' accountid=' + acct;
    if (!safe(function () { return p.visible; }, true)) s += ' (hidden)';
    return s;
  }

  // Print the subtree under `panel` (default: whole UI) to maxDepth.
  function dump(panel, maxDepth) {
    panel = panel || root();
    maxDepth = maxDepth === undefined ? 6 : maxDepth;
    (function walk(p, depth) {
      log(new Array(depth + 1).join('  ') + describe(p));
      if (depth >= maxDepth) return;
      var n = safe(function () { return p.GetChildCount(); }, 0);
      for (var i = 0; i < n; i++) {
        var child = safe(function () { return p.GetChild(i); }, null);
        if (child) walk(child, depth + 1);
      }
    })(panel, 0);
  }

  // Print the ancestor chain of `panel` up to the root (answers "which menu/screen am I inside?").
  function ancestors(panel) {
    var chain = [], p = panel;
    while (p) { chain.push(describe(p)); p = safe(function () { return p.GetParent(); }, null); }
    log('ancestors: ' + chain.join(' < '));
  }

  // Try reading dialog variables C++ set on `panel` (or its ancestors) via $.Localize's panel arg.
  function dialogVars(panel, names) {
    names.forEach(function (name) {
      ['s', 'd', 'i', 'i:r'].forEach(function (t) {
        var expr = '{' + t + ':' + name + '}';
        var v = safe(function () { return $.Localize(expr, panel); });
        if (v !== expr && v !== '') log(describe(panel) + ' ' + expr + ' => "' + v + '"');
      });
    });
  }

  // Try reading JS properties and XML attributes by name.
  function props(panel, names) {
    names.forEach(function (name) {
      var prop = safe(function () { return panel[name]; }, undefined);
      var attr = safe(function () { return panel.GetAttributeString(name, ''); }, '');
      if (prop !== undefined || attr) log(describe(panel) + ' .' + name + '=' + prop + ' attr=' + attr);
    });
  }

  // Which globals exist in this context?
  function globals() {
    ['GameUI', 'Game', 'Players', 'Entities', 'GameEvents', 'GameInterfaceAPI', 'fetch', 'localStorage',
     'setTimeout', 'atob', 'panorama'].forEach(function (g) {
      log('typeof ' + g + ' = ' + safe(function () { return typeof globalThis[g]; }));
    });
  }

  // Re-run fn every `sec` seconds while `until()` is false (C++ fills panels late).
  function poll(sec, fn, until, max) {
    var left = max || 100;
    (function tick() {
      try { if (until && until()) return; fn(); } catch (e) { log('poll error ' + e); }
      if (--left > 0) $.Schedule(sec, tick);
    })();
  }

  return { log: log, root: root, dump: dump, ancestors: ancestors, dialogVars: dialogVars, props: props, globals: globals, poll: poll,
           find: function (id) { return root().FindChildTraverse(id); } };
})();

// Example (uncomment in your hooked layout):
// Probe.globals();
// Probe.poll(1, function () {
//   var card = Probe.find('ProfileCard');
//   if (card) { Probe.dialogVars(card, ['account_id', 'player_name']); Probe.dump(card, 3); }
// }, null, 30);
