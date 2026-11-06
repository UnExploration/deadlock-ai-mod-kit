'use strict';
// __NAME__: starter mod. Puts a small badge in the top-left corner of the main menu and the HUD, and
// logs "[__NAME__] loaded" so you can confirm it in console.log (docs/05-dev-loop.md).
// Replace the badge with your feature; keep the structure:
//   - pure logic in functions that don't touch $ (unit-tested in Node: test/__NAME__.test.js)
//   - init() is idempotent, because this script re-runs for every instance of the hooked layout.
(function () {
  const TAG = '[__NAME__]';
  const VERSION = '0.1.0';
  const ROOT_ID = '__NAME__Root';

  function badgeText(version) {
    return '__NAME__ v' + version;
  }

  function init() {
    const ctx = $.GetContextPanel();
    if (ctx.FindChildTraverse(ROOT_ID)) return;
    const root = $.CreatePanel('Panel', ctx, ROOT_ID, { class: '__NAME__-root', hittest: 'false' });
    $.CreatePanel('Label', root, '', { class: '__NAME__-label', text: badgeText(VERSION) });
    $.Msg(TAG + ' loaded in ' + ctx.paneltype + ' (v' + VERSION + ')');
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { badgeText, init };   // Node tests
  } else {
    try { init(); } catch (e) { $.Msg(TAG + ' init failed: ' + e); }
  }
})();
