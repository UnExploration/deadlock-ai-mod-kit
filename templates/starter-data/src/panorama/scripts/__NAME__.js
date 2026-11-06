'use strict';
// __NAME__: starter for a mod that saves data. Puts a small note box in the top-left of the main menu
// and HUD; the note is saved and is still there after a restart (docs/04-persistence-and-io.md, pattern A).
// Storage comes from two scripts the layout includes first:
//   __NAME___kvbridge.js  the storage client (KVBridge), a copy of the kit's templates/kv-bridge
//   __NAME___store.js     the storage page's address (__NAME__StoreUrl), chosen when the mod was made
// Replace the note box with your feature; keep the structure:
//   - pure logic in functions that don't touch $ (unit-tested in Node: test/__NAME__.test.js)
//   - init() is idempotent, because this script re-runs for every instance of the hooked layout
//   - never overwrite data you couldn't read (offline means read-only)
(function () {
  const TAG = '[__NAME__]';
  const ROOT_ID = '__NAME__Root';
  const NS = '__NAME__.v1';            // this mod's namespace on the shared storage page
  const KEY = NS + '/note';
  const MAX_NOTE = 200;

  function log(s) { $.Msg(TAG + ' ' + s); }   // never log the note itself

  function normalizeNote(s) {
    return String(s).replace(/[\u0000-\u001F\u007F]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, MAX_NOTE);
  }

  function storeUrl() {
    return typeof __NAME__StoreUrl === 'string' ? __NAME__StoreUrl : '';
  }

  function init() {
    const ctx = $.GetContextPanel();
    if (ctx.FindChildTraverse(ROOT_ID)) return;
    const root = $.CreatePanel('Panel', ctx, ROOT_ID, { class: '__NAME__-root' });
    const entry = $.CreatePanel('TextEntry', root, '__NAME__Note', { class: '__NAME__-entry', maxchars: String(MAX_NOTE), placeholder: 'Type a note, then Enter' });
    const status = $.CreatePanel('Label', root, '', { class: '__NAME__-status', text: 'loading…' });
    log('loaded in ' + ctx.paneltype);

    if (!storeUrl()) {
      status.text = 'no storage page address (see the README)';
      log('no storage page address');
      return;
    }
    const bridge = new KVBridge({ page: storeUrl(), ns: NS, prefix: 'KV1:', protocol: 2, log: log });
    let canSave = false;
    bridge.start(root, '__NAME__Store');
    bridge.onSettled(function (state) {
      if (state !== 'ready') { status.text = 'offline: notes are not saved this session'; return; }
      bridge.get(KEY, function (err, value) {
        if (err) { status.text = 'error: ' + err; return; }
        entry.text = value || '';
        canSave = true;
        status.text = value ? 'saved note loaded' : 'no note yet';
        log('read ok (' + (value ? 'note' : 'empty') + ')');
      });
    });
    entry.SetPanelEvent('oninputsubmit', function () {
      try { $.DispatchEvent('DropInputFocus'); } catch (e) {}
      if (!canSave) { status.text = 'not saved: storage not ready'; return; }
      const note = normalizeNote(entry.text);
      const done = function (err) {
        status.text = err ? 'error: ' + err : (note ? 'saved ✓' : 'note cleared (an empty note deletes the saved one)');
        log(err ? 'save failed ' + err : (note ? 'saved' : 'cleared'));
      };
      if (note) bridge.set(KEY, note, done); else bridge.del(KEY, done);
    });
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { normalizeNote, init };   // Node tests
  } else {
    try { init(); } catch (e) { $.Msg(TAG + ' init failed: ' + e); }
  }
})();
