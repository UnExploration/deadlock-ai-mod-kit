# Guide: UI (change or add)

**The user says:** "hide the minimap", "remove <HUD element>", "move / resize / recolour <HUD element>", "make the shop / build viewer look like X", "show something on screen", "add an overlay / a badge / a button".
**Kind:** Panorama UI mod (layouts `.xml`, styles `.css`, scripts `.js`). Building needs Reduced CSDK 12.

Adding new UI (§ 4) worked in-game. Changing existing UI (§ 3) is not tried in-game: have the user check it.

The game's UI is Panorama: layouts, a CSS dialect and JavaScript, with **C++ owning the panels**. C++ finds panels by ID. A layout override that drops or renames one crashes the game at launch. The topic is owned by [docs/03](../docs/03-panorama.md); this guide is the route through it.

**Crosshair:** first mention the in-game `citadel_crosshair_*` settings. For shape, colour or size, override the style `panorama/styles/ability_hud_elements/element_gun` (§ 3a). A custom drawn image is the reticle-texture route in [textures.md](textures.md), not this guide.

## 1. Tools this needs

| Tool | Needs |
|---|---|
| `build.ps1` (compiles `.xml`/`.css`/`.js`) | Reduced CSDK 12 |
| `new-mod.ps1 -Kind ui`, `get-stock.ps1` | Source2Viewer-CLI; without it, get-stock falls back to GameTracking, which refuses when its build differs from the installed one |
| `catalog.ps1` | Source2Viewer-CLI |

Run `doctor.ps1`. Missing tools: `setup.ps1`, show its list, one yes, `setup.ps1 -Approve <ids>` (Reduced CSDK 12 is unsigned: say so). On a PC where no UI mod built with these tools has been seen in-game, build the untouched starter first (`new-mod.ps1 -Name <name>`, then § 5) and have the user confirm the badge. That proves the pipeline before any feature work.

## 2. Find the layout and the panel

- **Generated list first:** [generated/ui-layouts.md](../generated/ui-layouts.md) lists every layout of the user's build with its root panel and panel IDs. For a search, the catalog's `ui.tsv` (`catalog.ps1` prints the folder; MCP `catalog_search` with table `ui`) has the same, one row per layout: `path`, `root` panel, panel `ids`, `scripts`, `styles`. Search by a panel ID or a word ("minimap", "shop", "build"). The `styles` column names the stylesheets that layout loads.
- **What C++ feeds a surface:** [docs/12-ui-hooks.md](../docs/12-ui-hooks.md) (players, top bar, ESC menu: dialog variables, global hook points, panel events). `get-stock.ps1 -List panorama/layout/` lists every layout.
- **Read the stock files:** `get-stock.ps1 -Out <tmp> <game path>`, for the layout and its stylesheets (`panorama/styles/<name>.css`). Search the `.css` for the panel's `#id` to find the rule that places or shows it.

Examples (look them up in the catalog for the installed build; they move):

| The user means | Layout | Panels | Stylesheet |
|---|---|---|---|
| Minimap | `panorama/layout/hud.xml` | `#minimap_persp` → `#minimap_container` → `#hud_minimap` | `panorama/styles/hud.css` (rule `#minimap_persp`) |
| Shop | `panorama/layout/citadel_hud_hero_shop.xml` (root `CitadelHudHeroShop`) | `#Shop`, `#MainPanel`, `#ShopModsSelectedBuild` | `citadel_hud_hero_shop.css` |
| Build tab in the shop | `panorama/layout/citadel_shop_mods_build.xml` (root `CitadelShopModsBuild`) | `#CategoryContainer`, `#ControlButtons` | `citadel_shop_mods_build.css` |

*Done when* you can name the layout file, the panel ID, and the stylesheet rule (or the C++-fed variables) for every surface you'll touch.

## 3. Change existing UI (hide, move, resize, recolour)

**Not tried in-game: have the user check it.**

### Pick the cheapest safe strategy

Every stock file you override is a whole-file conflict with other mods that replace it (the lower pak number wins) and a re-base after every patch that changes it. Go down this list and stop at the first that works:

1. **Style-only override.** Override the one stylesheet that holds the panel's rule and change values there. `visibility: collapse;` hides a panel and removes it from layout. No layout is touched, so no ID can go missing.
2. **One tiny hook.** Override a small layout only to add a `<scripts>` include; your script finds the panel at runtime and changes it. Use this when the stylesheet is crowded (below) or the change depends on game state.
3. **Markup hook.** Override the layout itself to add markup that C++ must fill. Only for data you can't get otherwise, and a few lines at most.
4. **Full rewrite** of a stock layout. Avoid: maximum conflicts, and it breaks on every big UI patch.

**Crowded files** (many popular mods replace them, so expect conflicts): `panorama/styles/hud.vcss_c` (the most replaced), `citadel_hud_top_bar.{vxml,vcss}_c`, `citadel_hud_top_bar_player.vxml_c`, `citadel_base_styles.vcss_c`, `ability_hud_elements/element_gun.vcss_c`, `hud_ability_icon_passive.vcss_c`, `citadel_hud_hero_shop.{vxml,vcss}_c`, `hud_escape_menu.vxml_c`, `profile_card.vxml_c`, `hud.vxml_c`, `hud_paused.{vxml,vcss}_c`, `unit_status_v2.vcss_c`, `hud_abilities.vcss_c`, `hud_health.vcss_c`, `hud_health_container.vcss_c`, `objectives_map.vcss_c`, `citadel_db_page_profile.vxml_c`. QOL Lock's own page tells users to uninstall all other HUD and UI mods. If the user's other UI mods (QOL Lock, QoL Lite, HUDlock) replace the file you need, say so before building.

### 3a. Style-only override

1. `new-mod.ps1 -Name <name> -Kind empty`
2. `get-stock.ps1 -Out mods\<name>\stock panorama/styles/<file>.css`. This also records the build in `stock\STOCK.json`, which `rebase.ps1` needs.
3. Copy it to the same path under `mods\<name>\src\` and edit the copy. Add the path to `overrides` in `mod.json`.
   - **Change the value inside the existing rule.** Compiled Panorama may keep the *first* definition of a property, so a rule appended at the end of a stock file can do nothing. If you must add a rule, give it higher specificity than the stock one.
   - Keep every other rule and selector as it is.
   - Example, hide the minimap: in `hud.css`, add `visibility: collapse;` inside the `#minimap_persp { … }` rule.
4. Panorama CSS is not web CSS: no `display`, flexbox or grid. Move with `x`/`y`, `margin`, `horizontal-align`/`vertical-align`; size with `width`/`height` (relative to a 1080p-high canvas); recolour with `background-color`, `color`, `wash-color`, `saturation`, `opacity`. The full dialect: [docs/03 § CSS dialect](../docs/03-panorama.md#css-dialect-differs-from-the-web).
5. Build (§ 5).

### 3b. One tiny hook (change it from a script)

1. `new-mod.ps1 -Name <name>` (or `-Hook <layout>`, the path under `panorama/layout/` without `.xml`). It gets the stock layout and adds only a style include and a script include. The default hook, `citadel_hud_and_db_overlay`, is loaded on the main menu and in matches. Other candidates: [docs/12 § Global hook points](../docs/12-ui-hooks.md#global-hook-points-load-your-script-everywhere). new-mod warns if an installed pak already overrides the hook.
2. In `src/panorama/scripts/<name>.js`, find the panel and set explicit style values (camelCase), for example `panel.style.visibility = 'collapse'`. Finding target panels at runtime from a small hook is the Shop Notes and Threat HUD pattern. Reaching a panel in another layout this way (walk up with `GetParent()`, then `FindChildTraverse('<id>')`) is untested in this kit.
3. C++ fills and recycles panels after your script starts. Poll with `$.Schedule(0.1, …)` until the panel exists, and keep the script idempotent: it re-runs for every instance of the hooked layout. Patterns: [docs/03 § JavaScript](../docs/03-panorama.md#javascript-youll-actually-write).
4. Build (§ 5).

### 3c. Overriding a layout (markup hook or more)

1. `get-stock.ps1 -Out mods\<name>\stock panorama/layout/<file>.xml`, copy it to `src\` at the same path, add it to `overrides` in `mod.json`.
2. **Keep every stock ID and every stock class.** Don't rename, remove or re-nest panels C++ looks up. Hide with `visibility: collapse` instead of deleting. Add your own panels with namespaced IDs and classes (`<name>_…`).
3. Keep the diff to a few lines. Diff `src` against `stock` before building and check every stock `id=` is still there.

## 4. Add new UI (overlay, badge, button)

**Worked in-game** with the untouched UI starter (`new-mod.ps1 -Kind ui`): the label showed on the main menu and in a match, and `console.log` had `[<name>] loaded` with no script errors.

1. `new-mod.ps1 -Name <name>`. This is the badge: a "<name> v0.1.0" label top-left on the main menu and in matches, and `[<name>] loaded` in the log. Add `-Hook <layout>` only when the UI belongs somewhere the default hook isn't loaded (for example `hud_escape_menu` for the ESC menu, a crowded file).
2. The only stock file is the hooked layout, with two added lines. Everything else is new and namespaced: `panorama/scripts/<name>.js`, `panorama/styles/<name>.css`, and any extra layouts under `panorama/layout/<name>/`. New files never conflict.
3. Build the UI from the script with `$.CreatePanel` (or `BLoadLayout`/`BLoadLayoutSnippet` for your own layouts). Keep the starter's structure: pure logic in functions tested by `node --test`, an idempotent `init()`, every log line prefixed `[<name>]`.
4. Buttons and text boxes: put clickable panels outside stock subtrees marked `hittestchildren="false"`; after a `TextEntry` submits, `$.DispatchEvent('DropInputFocus')`, or the player's keybinds stay captured. Saving anything between games: [saved-data](saved-data.md).
5. Build (§ 5).

## 5. Build and install

1. From the mod folder: `node --test`, then `node --check` on each `.js` in `src` one at a time ([docs/05 § The loop](../docs/05-dev-loop.md#the-loop)).
2. `build.ps1 -Mod mods\<name>`. Every `.xml`/`.css`/`.js` must produce its `_c` file (`.vxml_c`/`.vcss_c`/`.vjs_c`). It warns if the game build differs from `gameBuild` in `mod.json`: run `rebase.ps1 -Mod mods\<name>` first.
3. Run `mods.ps1 conflicts` and check that no lower-numbered pak replaces a file you override.
4. With Deadlock fully closed and the user's go-ahead: `build.ps1 -Mod mods\<name> -Install`.

No hot reload: the game reads mods at startup, so every change needs a full restart.

## 6. Check in-game

Batch every check into one list. The user needs `-condebug` in the launch options for the log.

- **Added UI:** "On the main menu, is <the thing> at <where>? Start a bot match: is it there too? <Click it / type in it>: does it <do X>, and do your keys work normally afterwards?"
- **Changed UI:** "Start a bot match. Is <element> <hidden / moved / the new colour>? Does the rest of the HUD look normal?"
- **Any change near the shop** (the shop, the build tab, items): "Open the shop and buy an item. Then open the build tab. Does everything open and work as before?"
- After the user closes the game, read the log: MCP `read_console_log` (`mod: <name>`), or `Select-String` on `game\citadel\console.log` for `[<name>]`, `JS Exception` and `Unable to`. Copy it before the next launch: the game truncates it.
- Remove what was only installed for the test (`mods.ps1 disable <name>`).

## 7. Reading failures

| What the user sees / the log says | Meaning | Fix |
|---|---|---|
| Game crashes at launch; `FATAL ERROR: Unable to find child '<id>'` | Your layout override lost an ID C++ needs, or is based on an older build | Deadlock closed: `mods.ps1 disable <name>` so the game starts again. Re-base on the current stock file (`rebase.ps1`) and restore every stock ID |
| `Unable to load layout file 'panorama/layout/…'` | A compiled layout is missing or broken | Check `build.ps1` produced the `.vxml_c`; rebuild |
| `JS Exception! *** Skipping rest of script ***` / `JS(<file>:<line>:<col>)` | Your script threw; the rest of it didn't run | Fix the line; wrap unknown APIs and events in `try/catch` |
| Nothing changed | Addons not mounted, a lower-numbered pak replaces the same file, wrong path, or the game wasn't fully restarted | `doctor.ps1`, `mods.ps1 conflicts`, `mods.ps1 files <pak>`. A style change that does nothing: the property was appended instead of edited in place (§ 3a) |
| Keybinds stop working after typing | Focus never released | `$.DispatchEvent('DropInputFocus')` |

The full table: [docs/05 § Reading failures](../docs/05-dev-loop.md#reading-failures).

## Pitfalls

- **Patches break overrides.** 109 builds touched Panorama in the year to 2026-10, and one patch changed 591 of 985 Panorama files. After an update: `rebase.ps1 -Mod mods\<name>`, then check that every panel ID your script looks up still exists in the new stock file, rebuild and retest ([after a patch § 3](after-a-patch.md#3-re-base-ui-overrides)). Run `catalog_refresh` (`generate-docs.ps1`) first, as [after a patch](after-a-patch.md) says.
- **Conflicts are whole-file.** Two mods that change the same layout or stylesheet can't be merged; the lower pak number wins and the other mod's change to that file is lost. Tell the user which of their mods it clashes with, in plain words.
- **Never ship a full stock copy you didn't change.** Every overridden file is a conflict and a re-base; only override what you edit.
- **Fair play:** client-side only. No UI that shows information the game hides from the player. Hiding, moving or restyling what the player already sees is fine ([docs/08](../docs/08-policy-and-safety.md)).
- **Explain in the user's terms:** "the game's HUD style file", not `hud.vcss_c`, unless they ask.
