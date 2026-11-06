# 5. Dev loop: build, install, test, debug

There's no hot reload in retail Deadlock: addons load **at startup only**, and the game locks its VPKs while running. One iteration means: close the game → build → install → launch → test → read the log.

## One-time setup

Start with the doctor. It's read-only, runs in Windows PowerShell 5.1 or pwsh 7, and prints a fix for every problem:

```powershell
powershell -ExecutionPolicy Bypass -File <skill>\tools\doctor.ps1
```

It checks everything below. Exit code = number of `[FAIL]` lines; 0 means ready to build and test.

1. **Mount addons:** close Deadlock, then run `pwsh -ExecutionPolicy Bypass -File enable-addons.ps1` ([`../tools/enable-addons.ps1`](../tools/enable-addons.ps1)).
   - It finds the install through Steam, edits only SearchPaths, is idempotent, and keeps `gameinfo.gi.pre-addons.bak`.
   - Re-run it after any patch that resets `gameinfo.gi`.
   - `-Check` reports without changing anything.
   - To undo everything on the game side: `mods.ps1 reset -Yes`. It deletes every pak these tools built and unmounts addons when no other mods remain.
2. **Tools:**
   - Run **[`../tools/setup.ps1`](../tools/setup.ps1)** (it also works in Windows PowerShell 5.1). With no arguments it only prints what's missing: what each item is, why it's needed, where it comes from, where it goes, its size, and warnings.
   - Show that list to the user and get **one yes**, then run `setup.ps1 -Approve <ids>`.
   - The items are PowerShell 7, Reduced CSDK 12 (unsigned), Source2Viewer-CLI, Node.js and git.
   - Kit files go in `%LOCALAPPDATA%\deadlock-modding\`, which is removed by deleting that folder.
   - Exit 2 means CSDK is waiting for the user to download it by hand ([02](02-toolchain.md#reduced-csdk-12-the-compiler)).
   - Without CSDK, only mods that copy compiled game files build. Without Source2Viewer-CLI, Panorama files still come from GameTracking.
3. **Launch options** (Steam → Deadlock → Properties → Launch Options):
   - **`-condebug`** writes `game\citadel\console.log` (truncated every launch). This is your log.
   - The in-game console: enable "Dev command console" in Settings. Guides bind it to **F7**; check the key in Settings. `vconsole2.exe` (in `game\bin\win64`) is the external console.
   - Only for deep UI inspection: `-dev -tools` enables the **Panorama debugger**. It shows the panel tree and CSS and has a JS console. With those flags, mod authors report F7 = debugger and F8 = VConsole. Older Dota docs say F6, and `panorama_toggledebugger_mode` sets how the key behaves. **Tools mode blocks matchmaking**, so remove it before queueing.

## Start a mod

```powershell
pwsh -File <skill>\tools\new-mod.ps1 -Name mymod            # UI mod hooked into the main menu + HUD overlay
pwsh -File <skill>\tools\new-mod.ps1 -Name mymod -Hook hud_escape_menu
pwsh -File <skill>\tools\new-mod.ps1 -Name firstlight -Kind sound  # sound mod, no compiler (docs/09)
pwsh -File <skill>\tools\new-mod.ps1 -Name myassets -Kind empty     # just mod.json + src/
```

It creates `mods/<name>/`:
- `mod.json`: name, a free pak number, version, `gameBuild`, overridden files.
- `src/`: game paths that go into the VPK. The hooked layout is the stock file plus two include lines.
- `stock/` + `STOCK.json`: the untouched files the overrides are based on, for [`rebase.ps1`](../cookbook/after-a-patch.md#3-re-base-ui-overrides).
- `test/`: Node tests with a mocked `$`.

**Mods that reuse game sounds** can list `"copies": { "<target>": "<donor>" }` in `mod.json` instead of shipping files: `build.ps1` copies each donor out of the installed game at build time ([cookbook/sounds](../cookbook/sounds.md)).

**The starters build and run as-is.**
- The UI starter shows a "mymod v0.1.0" badge and logs `[mymod] loaded`.
- The sound starter makes main-menu hover and click sounds play the shop purchase sound, and needs no compiler.

Build one once before changing anything. If it shows up (or is heard) in-game, the whole pipeline works on this PC.

## The loop

```powershell
# from the mod folder, in pwsh; Deadlock must be closed
node --test
Get-ChildItem .\src -Recurse -Filter *.js | ForEach-Object { node --check $_.FullName; if ($LASTEXITCODE) { throw "syntax error in $($_.Name)" } }
pwsh -File <skill>\tools\build.ps1 -Mod . -Install
Start-Process "steam://run/1422450"
# ...test...  then close the game and read the log:
Select-String -Path "<Deadlock>\game\citadel\console.log" -Pattern '\[mymod\]|JS Exception|Unable to'
```

- The `node --check` line catches syntax errors for free. Pass files one at a time: `node --check` with several files checks only the first, and PowerShell doesn't expand `*.js` for native commands.
- `mod.json` fixes the **pak number**, so every build replaces your own file. `build.ps1` refuses to overwrite a pak another mod name installed.
- **Copy `console.log` before relaunching.** It's truncated on start.
- See what's installed and what conflicts with what: `pwsh -File <skill>\tools\mods.ps1` (`list`, `conflicts`, `files <pak>`, `disable`/`enable`/`remove <pak|name>`).

## Where to test

| Feature needs | Test in |
|---|---|
| Any UI, no other players | Hideout (main menu), or a bot match (bots have account ID `0`) |
| Real account IDs (profile cards) | ESC → **Friends** tab → click a friend. The profile card carries their real `account_id` with no match needed |
| Real players in a match | A private lobby with a friend, then real matches last |
| Post-game screens | A short bot match played to the end |

Before queueing real matchmaking: no `-tools`, CSDK closed, and only SearchPaths/ConVars changed in `gameinfo.gi`.

## Answering "what does the game give me here?" with the probe

[`../templates/probe/probe.js`](../templates/probe/probe.js) logs panel trees, dialog variables (via `$.Localize('{d:x}', panel)`), properties and attributes, and which globals exist. Include it next to your script in a hooked layout and call it from a `Probe.poll(…)`. You can also paste its body into the Panorama debugger's JS console. Every question in [12-ui-hooks.md](12-ui-hooks.md) marked "runtime test" is answered this way, with one launch per batch of questions.

Release-mode console helpers:
- `dump_panorama_events` lists every Panorama event.
- `dump_panorama_css_properties`.
- `citadel_show_account_ids 1` shows account IDs on tooltips.
- `addons` / `path` show what's mounted.
- `con_filter_enable 1; con_filter_text mymod` filters the console.

## Reading failures

| Symptom | Meaning | Fix |
|---|---|---|
| Nothing changed | gameinfo not mounting addons; wrong file name (`pakNN_dir.vpk`); a lower-numbered mod overrides the same file; path in the VPK not lowercase or not mirroring the game path; game not fully restarted | `doctor.ps1`; `mods.ps1 conflicts` (a lower pak replacing the same file wins); `mods.ps1 files <pak>` |
| `FATAL ERROR: Unable to find child '<id>'` at launch | Your layout override removed or renamed an ID C++ needs (or is based on an old build) | Re-base on the current stock file and keep all stock IDs |
| `Unable to load layout file 'panorama/layout/…'` | Missing or broken compiled layout | Check the compile output exists; recompile |
| `JS Exception! *** Skipping rest of script ***` / `JS(<file>:<line>:<col>)` | Uncaught JS error. The rest of that script didn't run | Fix it; wrap calls into unknown APIs and events in `try/catch` |
| `ERROR: AsyncWebRequest has been removed.` | You called `$.AsyncWebRequest` | Use a bridge ([04](04-persistence-and-io.md)) |
| `Addons cannot add ui scripts` / `Addons cannot add layouts` | Files are mounted through the engine *addon* system, not a `Game` search path | Mount via SearchPaths ([01](01-how-mods-load.md)) |
| `Failed to parse KeyValues` / gameinfo errors | Broken gameinfo.gi edit | Verify game files (restores Valve's current file), then re-run `enable-addons.ps1`. Restore `gameinfo.gi.pre-addons.bak` only if no patch landed since it was made |
| "Unable to enter matchmaking… gameinfo.gi" | A guarded gameinfo section was edited, or Tools mode is on | [01](01-how-mods-load.md#the-matchmaking-guard-pgi-what-you-must-never-edit) |
| Typing in your TextEntry triggers abilities afterwards | Focus never released | `$.DispatchEvent('DropInputFocus')` after submit or blur |

## Testing logic outside the game

Panorama JS is plain V8, so keep logic in pure functions and test them with Node. Mock `$` (`Schedule` → `setTimeout`, `CreatePanel` → plain objects). [`../templates/kv-bridge/test/kvbridge.test.js`](../templates/kv-bridge/test/kvbridge.test.js) shows the pattern, including simulating the HTML panel and its page.
