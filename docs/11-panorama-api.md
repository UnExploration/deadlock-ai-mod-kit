# 11. Panorama JS API in Deadlock

**Sources:**
- `panorama.dll`/`panoramauiclient.dll` strings (the method and doc strings compiled into the game);
- in-game probes published by mod authors (Predi-i 2026-08-23, Hanturaya 2026-08/10);
- shipping mods.

Status key: **✅ proven in-game** · **DLL**: present in the binary, untested · **❌ absent or removed**.
Dota/CS2 docs describe a much larger API; don't assume any of it exists here.

## Globals

✅ `$`, `panorama`, `JSON`, `Promise`, `globalThis` (plus standard JS built-ins: `Math`, `Date`, `Map`, `RegExp`, …).
❌ `fetch`, `XMLHttpRequest`, `WebSocket`, `localStorage`, `setTimeout`/`setInterval`, `atob`/`btoa`, `TextDecoder`, `window`, `document`, `navigator`, `Game`, `GameUI`, `Players`, `Entities`, `GameEvents`, `GameInterfaceAPI`, `SteamOverlayAPI`, `FriendsListAPI`, `MyPersonaAPI`, `$.persistentStorage`.

## `$` functions

| Function | Status | Notes |
|---|---|---|
| `$('#id')` / `$.FindChildInContext('#id')` | ✅ | ID selectors only; searches the current context |
| `$.GetContextPanel()` | ✅ | Root of the layout instance your script belongs to |
| `$.CreatePanel(type, parent, id, props?)` | ✅ | `props` is like XML attributes: `{ class: 'A B', text: '#tok', onactivate: "…" }`. Types proven: `Panel, Label, Image, TextEntry, Button, MoviePanel, CitadelHTMLPanel, HTML, CitadelUserName`. It throws for `HTMLPanel, WebPanel, CefPanel, CitadelWebPanel, SteamHTMLPanel` |
| `$.Msg(...)`, `$.Warning(...)`, `$.Assert(...)` | ✅ | Console as `[PanoramaScript] …`; also lands in `console.log` with `-condebug` |
| `$.Schedule(sec, fn)` → handle, `$.CancelScheduled(handle)` | ✅ | Your only timer |
| `$.DispatchEvent(name, ...args)`, `$.DispatchEventAsync(delay, name, ...)` | ✅ | Fire panel events (see the event table in [12-ui-hooks.md](12-ui-hooks.md#useful-panel-events-c-handlers-call-from-layouts-or-dispatchevent)) |
| `$.RegisterEventHandler(name, panel, fn)` | ✅ | Required for `HTMLTitle`/`HTMLURLChanged` |
| `$.RegisterForUnhandledEvent(name, fn)` → id, `$.UnregisterForUnhandledEvent(name, id)` | ✅ | e.g. `CitadelScoreboardToggle`, `CitadelPaused`, `CitadelOpenUpgradeShop` |
| `$.RegisterKeyBind(panelOrContext, 'key_m', fnOrEvent)` | ✅ | `''` for a global binding |
| `$.Localize('#token' \| '{d:var}', panel?)` | ✅ for tokens; **untested** for reading a panel's dialog variables via the panel argument | The DLL doc: "Optionally accepts a Panel argument for dialog variable values" |
| `$.CanLocalize(token)`, `$.LocalizePlural`, `$.Language()` | ✅/DLL | |
| `$.Each(arrayOrObj, fn)`, `$.HTMLEscape(s)` | ✅ | |
| `$.FrameTime()`, `$.MousePosition()`, `$.BImageFileExists(path)`, `$.LogChannel(name)`, `$.DbgIsReloadingScript()` | DLL | |
| `$.AsyncWebRequest` | ❌ | Logs `ERROR: AsyncWebRequest has been removed.` |

## Panel methods and properties (all panels)

From `panoramauiclient.dll`. Standard Panorama, ✅ widely used.

- **Classes:** `AddClass`, `AddClasses`, `RemoveClass`, `RemoveClasses`, `SetHasClass(cls, bool)`, `ToggleClass`, `SwitchClass(old, new)`, `TriggerClass`, `BHasClass`, `BAscendantHasClass`
- **Tree:** `GetParent`, `SetParent`, `GetChild(i)`, `GetChildCount`, `GetChildIndex`, `Children()`, `FindChild(id)`, `FindChildTraverse(id)`, `FindChildInLayoutFile(id)`, `FindPanelInThisOrParentLayoutFile`, `FindAncestor(id)`, `FindChildrenWithClassTraverse(cls)`, `FindChildrenWithAttributeTraverse`, `MoveChildBefore/After`, `RemoveAndDeleteChildren`, `DeleteAsync(sec)`, `IsValid()`
- **Layout loading:** `BLoadLayout(path, overrideExisting, partialLayout)`, `BLoadLayoutSnippet(name)`, `BHasLayoutSnippet`, `BGetSnippetNames`
- **Dialog variables (write-only):** `SetDialogVariable(name, str)`, `SetDialogVariableInt`, `SetDialogVariableTime`, `SetDialogVariableLocString`, `SetDialogVariableLocStringNested`. **There is no getter**; see [12-ui-hooks.md](12-ui-hooks.md) for reading them.
- **Attributes:** `SetAttributeString/Int/UInt32`, `GetAttributeString/Int/UInt32(name, default)`. Unknown XML attributes land here too.
- **Events:** `SetPanelEvent('onactivate' | 'oncontextmenu' | 'onmouseover' | 'onmouseout' | 'oncancel' | 'onfocus' | 'onblur' | 'oninputsubmit' | 'ontextentrychange' | …, fn)`, `ClearPanelEvent`
- **Focus and input:** `SetFocus`, `SetAcceptsInput`, `SetAcceptsFocus`, `BHasKeyFocus`, `BAcceptsInput`, `SetInputNamespace`, `SetDisableFocusOnMouseDown`
- **Scrolling:** `ScrollToTop/Bottom/LeftEdge/RightEdge`, `ScrollParentToMakePanelFit`, `ScrollToFitRegion`, `BCanSeeInParentScroll`
- **Misc:** `ApplyStyles`, `ClearPropertyFromCode`, `SetDraggable`, `PlayPanelSound`, `SetReadyForDisplay`, `Data()` (a per-panel JS object), `GetPositionWithinWindow`
- **Properties:** `id`, `paneltype`, `visible`, `enabled`, `checked`, `hittest`, `hittestchildren`, `tabindex`, `inputnamespace`, `defaultfocus`, `layoutfile`, `style` (camelCase CSS), `contentwidth/contentheight`, `actuallayoutwidth/height`, `actualxoffset/actualyoffset`, `actualuiscale_x/y`, `scrolloffset_x/y`, `desiredlayoutwidth/height`

## Panel-type specifics

| Type | Members |
|---|---|
| `Label` | `.text` (read/write), `SetLocString`, `SetAlreadyLocalizedText`; XML `html="true"`, `allowtextselection` |
| `TextEntry` | `.text`, `SetMaxChars`, `SelectAll`, `RaiseChangeEvents`; XML `maxchars`, `multiline`, `placeholder`, `undohistroy="enabled"` (Valve's spelling); events `oninputsubmit`, `ontextentrychange`, `ontextentrysubmit` |
| `Image` | `SetImage(url)`: `file://{images}/…`, `s2r://…`, and **remote `https://`** ✅ |
| `CitadelHTMLPanel` / `HTML` | `SetURL(url)` (**https only** since 2026-10-01), `SetIgnoreCursor(bool)`. Events: `HTMLTitle(panel, title)` (4096-char cap, fires ~2×), `HTMLURLChanged`, `HTMLFinishRequest`. `HTMLContentLoaded` throws at boot. See [04-persistence-and-io.md](04-persistence-and-io.md) |
| `CitadelUserName` | `.accountid` ✅ (getter on scoreboards; settable to show that account's current name). XML `accountid="local"` |
| `Slider`, `ToggleButton`, `DropDown` | Standard Panorama (`value`, `checked`, `GetSelected`, …) |

## Useful events to dispatch

`CitadelConCommand` (run a console command), `CopyStringToClipboard`, `ExternalBrowserGoToURL`, `SteamOverlayOpenURL`, `CitadelShowProfilePageForAccount` (Number account ID), `Activated` (panel, 'mouse'), `DismissAllContextMenus`, `SetInputFocus` (panel), `DropInputFocus`, `CitadelResumePlaying`, `UIShowTextTooltip`/`UIHideTextTooltip`, `PlaySoundEffect`.

Full list in-game: `dump_panorama_events`.
