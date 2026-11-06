# 3. Panorama UI modding in Deadlock

Panorama is Source 2's UI system: XML layouts, a CSS dialect and JavaScript (V8). **Deadlock's UI logic is almost entirely C++.** The game ships hundreds of layouts and styles but only a **handful of scripts** (compiled TypeScript, `.vts_c`; for example, 442 layouts, 451 styles, 6 scripts; your build's counts are in [`../generated/file-types.md`](../generated/file-types.md)), and its custom panel classes (`CitadelHudEscapeMenu`, `CitadelPlayersList`, `CitadelProfileCard`, …) fill themselves from C++. A mod therefore adds its own JS on top of C++-driven panels. As of 2026-10, mod `.js` (`.vjs_c`) loads with no signature check; dozens of shipping mods rely on this.

API details: [11-panorama-api.md](11-panorama-api.md). What C++ feeds each player surface, and the hook points: [12-ui-hooks.md](12-ui-hooks.md). Every layout's panel IDs for the user's build: [`../generated/ui-layouts.md`](../generated/ui-layouts.md).

## Mental model

- A **layout** (`panorama/layout/x.xml` → `x.vxml_c`) instantiates a tree of panels. Its root element is often a C++ class (`<CitadelProfileCard>`). That class looks up children **by ID** and sets **dialog variables** (`{s:player_name}`, `{d:account_id}`) and classes on them.
- **C++ still owns the panels.** If your override renames or removes an ID that C++ looks for, the game crashes at load (`FATAL ERROR: Unable to find child '<id>'`). Keep every stock ID and class.
- **JS runs per layout instance.** `<scripts>` in a layout run when that layout loads, with `$.GetContextPanel()` = that instance's root. Every new context menu or card instance re-runs your script. Write scripts that are **idempotent**: check before creating, and reuse panels found by ID.
- **Deadlock exposes almost no game API to JS.** You get `$` and panel methods. There's no `Game`, `Players`, `GameUI`, `GameInterfaceAPI`, `fetch`, `localStorage` or `setTimeout`. Everything you know about a player comes from what C++ put into the panels: **read the UI, don't query the game.**

## Choosing a hook strategy (decides your patch burden)

Every overridden vanilla file is (a) a conflict with every other mod that overrides it (the lower pak number wins the whole file) and (b) a re-base after each patch. Rank your options:

1. **Add-only.** Your own new files under namespaced paths (`panorama/layout/<mod>/…`, `panorama/scripts/<mod>_*.js`, `panorama/styles/<mod>*.css`). There are zero conflicts, but nothing loads them on its own.
2. **One tiny hook.** Override the **smallest stable layout** that is loaded where you need it, adding only `<scripts><include src="s2r://panorama/scripts/<mod>.vjs_c"/></scripts>`. Your script then finds target panels at runtime and builds UI with `$.CreatePanel` / `BLoadLayout` / `BLoadLayoutSnippet`. This is the Shop Notes and Threat HUD pattern. Candidates are in [12-ui-hooks.md](12-ui-hooks.md#global-hook-points-load-your-script-everywhere).
3. **Markup hook.** Override a layout to add markup that **C++ must fill**, such as a hidden `<Label text="{i:r:account_id}"/>` inside `profile_card.xml`. JS can't create a C++ binding after the fact as reliably. Do this only when you need C++-supplied data, and keep the diff to a few lines.
4. **Full rewrite** of a stock layout (what most HUD mods do). Maximum conflicts, and it breaks every big UI patch. Avoid.

When you do override: start from the **current** decompiled stock file (GameTracking or S2V), make the minimal change, and keep the pristine copy plus a patch ([after a patch § Keep overrides as stock plus a diff](../cookbook/after-a-patch.md#keep-overrides-as-stock-plus-a-diff)).

## Layout XML

```xml
<root>
  <styles>
    <include src="s2r://panorama/styles/citadel_base_styles.vcss_c" />
    <include src="s2r://panorama/styles/mymod.vcss_c" />
  </styles>
  <scripts>
    <include src="s2r://panorama/scripts/mymod.vjs_c" />
  </scripts>
  <snippets>
    <snippet name="MyRow">
      <Panel class="MyRow"><Label id="MyText" text="{s:my_text}" /></Panel>
    </snippet>
  </snippets>
  <Panel class="MyRoot" hittest="false">
    <TextEntry id="MyEntry" maxchars="280" placeholder="Note…" oninputsubmit="" />
    <Button id="MySave" class="MyButton"><Label text="Save" /></Button>
  </Panel>
</root>
```

- Include paths: `s2r://panorama/…/x.vcss_c` / `.vjs_c`. Valve's decompiled files show `.vcss` / `.vts` without `_c`; mods use `_c`. Both are seen working.
- Inline `<script>…</script>` blocks also work (SteamNotes ships all its JS inline), but separate `.js` files diff and update better.
- Event attributes take either a **panel event** (`onactivate="CitadelResumePlaying()"`) or **inline JS** (`onactivate="$.GetContextPanel().ToggleClass('Open')"`). Stock layouts use both.
- Text: `text="#Token"` localizes. `{s:var}` / `{d:var}` / `{i:var}` / `{g:fmt:var}` substitute dialog variables from the panel **or its ancestors**. `{i:r:account_id}` is the form mods use to get the raw integer.
- `hittest="false"` makes a panel ignore the mouse; `hittestchildren="false"` does the same for its whole subtree. Stock list rows set this on `#MainContents`, so put your clickable controls outside such subtrees.

## CSS dialect (differs from the web)

- No `display`, flexbox or grid. Use `flow-children: right | down | right-wrap | down-wrap | none`, `horizontal-align`/`vertical-align`, `x`/`y`, `width: fit-children | fill-parent-flow(1) | 100%`.
- `visibility: collapse` removes a panel from layout (there's no `display: none`).
- Panorama extras: `wash-color`, `saturation`, `blur`, `background-blur`, `opacity-mask`, `img-shadow`, `pre-transform-scale`, `ui-scale`, `transition-*`, `sound`, `tooltip-position`, `context-menu-position`.
- Sizes are relative to a 1080p-height canvas.
- Compiled Panorama may keep the *first* definition of a property, so appending an override rule to a stock file can do nothing. Prefer your own namespaced classes and IDs, and higher specificity.
- From JS: `panel.style.backgroundColor = '#ff000080'` (camelCase). Set explicit values; clearing with `null` doesn't always restore the stock look.

## JavaScript you'll actually write

```js
'use strict';
const ctx = $.GetContextPanel();                         // this layout instance's root
if (!ctx.FindChildTraverse('MyModRoot')) {               // idempotent: script re-runs per instance
  const root = $.CreatePanel('Panel', ctx, 'MyModRoot', { class: 'MyModRoot', hittest: 'false' });
  const entry = $.CreatePanel('TextEntry', root, 'MyEntry', { maxchars: '280', placeholder: 'Note…' });
  const save = $.CreatePanel('Button', root, 'MySave', { class: 'MyButton' });
  $.CreatePanel('Label', save, '', { text: 'Save' });
  save.SetPanelEvent('onactivate', () => { $.Msg('[mymod] save ', entry.text); $.DispatchEvent('DropInputFocus'); });
}
// poll instead of setTimeout; C++ often fills panels a few frames after load
function waitFor(pred, cb, tries = 50) { if (pred()) return cb(); if (tries > 0) $.Schedule(0.1, () => waitFor(pred, cb, tries - 1)); }
```

- **Timing:** C++ fills dialog variables and children *after* your script starts. Poll with `$.Schedule(0.1, …)` until data appears, and keep polling while the panel is visible if C++ can **reuse** the panel for a different player.
- **Text input:** use `TextEntry` with `.text`, `maxchars`, `placeholder` and `oninputsubmit`. Call `entry.SetFocus()` to focus it. Always release focus afterwards with `$.DispatchEvent('DropInputFocus')`, or the player's keybinds stay captured.
- **Console commands:** `$.DispatchEvent('CitadelConCommand', 'cmd args')`. There's no return value; output goes to the console. `developmentonly`/`cheat` commands are refused.
- **Clipboard:** `$.DispatchEvent('CopyStringToClipboard', text, text)`. Valve's own usage passes a loc token as the second argument; mods pass the text twice.
- **Logging:** `$.Msg('[mymod] …')` prints `[PanoramaScript] [mymod] …` to the console (and `console.log` with `-condebug`). Prefix every line with a tag, because the console is noisy.
- **Guard unknown events and methods** with `try/catch`. One (low-reliability) mod note reports a client crash from dispatching an unknown event, so test new events offline first.
- Modern JS works (classes, arrow functions, `Map`, Promises, async/await). There's no `atob`/`btoa`/`TextDecoder`, and `String.prototype.normalize` may be missing.
- **Large integers:** a SteamID64 doesn't fit in a JS `Number`. Keep IDs as **strings** and key data by the 32-bit account ID.

## Reading player identity

| Need | Method | Status |
|---|---|---|
| Account ID of the player whose **profile card / context menu** is open | Override `profile_card.xml` and add `<Label id="MyAcct" text="{i:r:account_id}" style="visibility: collapse;"/>` inside `<CitadelProfileCard>`. JS reads `FindChildTraverse('MyAcct').text` and strips non-digits. `0` means bot | **Proven** (ShowRank, SteamNotes) |
| Same, with no override | `$.Localize('{d:account_id}', profileCardPanel)` | Untested; try it first |
| Account ID on post-game/scoreboard and party name panels | `CitadelUserName` panel → `.accountid` (fallback `GetAttributeString('accountid','')`) | **Proven** |
| Account IDs of ESC → Players rows | Rows only carry `{s:player_name}`. "Witness" them: dispatch `Activated` on a row's `#MainContents`, read the card that opens, then `DismissAllContextMenus`. Cache per match | **Proven**, clunky |
| Show a player's **current** name from an account ID | `$.CreatePanel('CitadelUserName', parent, id)` then set `.accountid` (Threat HUD), or `<CitadelUserName accountid="…"/>` | Proven / expected |
| Human-visible IDs for debugging | console `citadel_show_account_ids 1` | Release convar |

SteamID64 = account ID + 76561197960265728. Do the conversion with string arithmetic in JS if you ever need it.

Not tried in-game, with the fallback if it fails (a probe build, [`../templates/probe/probe.js`](../templates/probe/probe.js), answers each in one launch):
- Whether the hidden `{i:r:account_id}` label also fills in the Friends context menu, not only ESC → Players: if not, try `{d:account_id}`, or dump the card with `Probe.dump(card)`.
- Whether `CitadelContextMenuPlayer` is an ancestor of the card only in a context menu (not on hover or in the friends list): tell the two apart by the ancestor chain you observe.
- Whether a card's `#UserName` exposes the display name (`.text` or a child `Label`): if not, show the current name with `CitadelUserName`.
- Whether ESC → Players rows (`CitadelPlayersListEntry`) carry `account_id` in a dialog variable: if not, use the witness method above.

## Things that bite

- **Overrides go stale.** A patch that changes a stock layout you copied gives you a crash or missing features. Re-base after every patch that touches your files ([after a patch](../cookbook/after-a-patch.md)).
- **Context menus and cards are recreated or recycled**, and your state in them dies. Keep durable state in your storage ([04](04-persistence-and-io.md)) and treat panels as views. Untried: whether a storage bridge started from a panel in a context menu reaches `ready` and survives the menu closing when parented to the root (if not, read the `bridge url` log lines and try the `HTML` panel type), and whether a `TextEntry` or button inside a context menu takes typing and clicks without the menu closing (if not, put the editor in a panel parented to the ESC menu root).
- **Shared contexts:** scripts in different layout instances don't share JS globals in a way you can rely on. Share state through panels (e.g. a named panel under the top-level root found with `FindChildTraverse`, or panel attributes via `SetAttributeString`/`GetAttributeString`) or through your storage. Keep per-instance state in closures.
- **Big values:** whether a ~10 KB paste into a `TextEntry` with a large `maxchars`, or a 64 KB root attribute, works is untried. Split big values into chunks.
- **No hot reload in retail.** Fully restart Deadlock after every build ([05](05-dev-loop.md)).
- **Remote images:** `Image.SetImage('https://…')` works. Bridges and badges rely on it, and Valve could restrict it.
