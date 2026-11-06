# Guide: after a Deadlock patch

**The user says:** "my mod broke after the update", "update my mod", "the game updated", "my mods stopped working".
**Kind:** any mod. Asset files: [docs/09 § After a patch](../docs/09-asset-mods.md#after-a-patch).

This guide uses existing tools; it hasn't been walked end to end in-game. Deadlock patches constantly: in the year to 2026-10, 109 builds touched Panorama, and City Never Sleeps (2026-09-29) changed 591 of 985 Panorama files and broke most HUD mods. Re-basing is routine.

A patch can break a mod four ways: `gameinfo.gi` is reset (every mod silently stops), a file the mod replaces changed (a merge is needed), a file moved or was renamed (the mod does nothing), or the engine's resource format changed. Work through the steps in order. Steps that change the game folder need the user's ask to install or test (AGENTS.md), and Deadlock closed.

## What breaking looks like

| What changed | What the user sees, or the log says | Fix |
|---|---|---|
| `gameinfo.gi` replaced (Valve changed it 14 times in 2026; Steam's "Verify integrity" also does it) | **Every** mod silently stops loading | Step 4: re-apply the SearchPaths edit **to the new file**. Never paste an old backup over it: that reverts the guarded sections and `PGIVersion` and can block matchmaking |
| A stock layout the mod overrides changed | `FATAL ERROR: Unable to find child '<id>'` (a panel ID renamed or removed), `Unable to load layout file 'panorama/layout/…'`, missing menu items, or the change has no effect | Step 3: re-base, re-applying only the mod's diff |
| A file the mod replaces moved or was renamed | The stock version shows; the mod does nothing, with no error | Step 2: find the new path |
| Resource format bump (engine update) | Source 2 Viewer can't read the game's files | Update it (≥ 20.1 for builds after 2026-09-29) |
| The mod ships `scripts/*.vdata_c` | New heroes stay locked; KV3 parse errors | Take the file out of the mod |

## 1. Refresh the game data

Everything after this step reads the new build, so do it first. It only reads the game.

**First, keep the old data:** copy `generated\` to a folder outside the kit. `generated/` is built on this PC from the user's game and git doesn't track it, so this copy is the only record of the previous build for step 2.

- MCP: `catalog_refresh`. Script: `pwsh -File tools\generate-docs.ps1` (runs `catalog.ps1` for a build with no catalog yet: 1-2 minutes; `-Force` redoes it).

It rewrites [generated/](../generated/README.md) for the new build and builds the catalog that `catalog_search` reads. Then run `doctor` (or `powershell -ExecutionPolicy Bypass -File tools\doctor.ps1`): it prints the build, says whether mod loading is still on, and should now report `generated/ describes build N`. Compare the build with the mod's `mod.json`: `"verified"` (last build tested in-game) and `"gameBuild"` (build the overrides are based on). The game's own build is `ClientVersion=` in `game/citadel/steam.inf`.

## 2. See what the patch changed

`generated/` is plain text written the same way every time, so a diff shows what the patch changed in the game data the mod depends on. From the kit folder:

```powershell
git diff --no-index --stat <copy from step 1> generated
git diff --no-index --word-diff <copy from step 1>\ui-layouts.md generated\ui-layouts.md
```

The diff is against the user's copy from step 1, which may be several patches old: look only at the rows the mod uses. No copy (the data was refreshed before one was saved): skip the diff and check each path the mod uses directly, as below.

- **UI mods:** find each layout the mod overrides or hooks in `ui-layouts.md`. A panel ID the mod's CSS or JS uses that disappeared, or a layout row that vanished, breaks the mod.
- **Sound, texture and model mods:** patches move and rename these files ([docs/09](../docs/09-asset-mods.md#after-a-patch)), and a replacement whose path vanished does nothing and gives no error. List what the mod replaces (`list_mods` action `files`, or `mods.ps1 files <mod>`, plus `mod.json` `copies` targets and donors) and check each path with `catalog_search` table `files`, or list a folder with `get_stock` `list` (`pwsh -File tools\get-stock.ps1 -List <folder>/`). For sound mods re-read the event's `vsnd_files` column (`catalog_search` table `soundevents`): the file list can change. `heroes.md` and `models.md` in the diff show renamed heroes and models.
- **Moved or renamed:** move the file in `src` (or fix `copies`) to the new path. Redo whole-file overrides (soundevents, materials) against the new stock file.

No changed row touches the mod: the patch probably didn't touch its base. Still do steps 3 to 5.

## 3. Re-base UI overrides

For a mod that has `stock/STOCK.json` (Panorama overrides made with `new_mod`):

- MCP: `rebase_mod`. Script: `pwsh -File tools\rebase.ps1 -Mod mods\<name>` (needs git).

Per file it reports `[current]` (and records the new build), merges Valve's changes with the user's, or flags `[gone]` (find the new name with `get-stock.ps1 -List <folder>/`). The old override is kept in `rebase-backup\`. Conflict markers (`<<<<<<< your mod` / `>>>>>>> stock <build>`): resolve them, re-run. Raw compiled files (sounds, textures) can't be merged: it says the stock file changed, so redo that replacement (step 2). It sets `mod.json` `gameBuild` only when every file is current and no markers remain.

A clean merge isn't a working mod: check that every panel ID the mod's JS looks up still exists in the new stock file (and in `generated/ui-layouts.md`).

No `stock/STOCK.json` (sound, copies or model mods): skip this step. An older mod with layout overrides but no `stock/`: fetch its stock files first ([Keep overrides as stock plus a diff](#keep-overrides-as-stock-plus-a-diff)).

## 4. Turn mod loading back on

Patches usually reset `gameinfo.gi`, and then **no mod loads**. The doctor in step 1 said whether that happened.

- MCP: `mount_addons` action `check`, then `enable` if it says not mounted.
- Script: `pwsh -File tools\enable-addons.ps1 -Check` (exit 1 = not mounted), then `pwsh -File tools\enable-addons.ps1`.

It edits the new file in place and backs it up first. Never paste an old `gameinfo.gi` backup over it: that reverts the guarded sections and `PGIVersion` and can block matchmaking ([docs/01](../docs/01-how-mods-load.md)). If that was the only problem, the mod works at the next launch.

## 5. Rebuild, install, and the user checks

Deadlock closed, user has asked to test:

- MCP: `install_mod`. Script: `pwsh -File tools\build.ps1 -Mod mods\<name> -Install`.

`build.ps1` warns while `gameBuild` is behind the installed game. The user **fully restarts** Deadlock and checks the mod the way its recipe says (one checklist for all their mods). Afterwards `read_console_log` (`mod` for one mod) for `Unable to find child`, `Unable to load layout file`, `JS Exception`. Failures: [docs/05 § Reading failures](../docs/05-dev-loop.md#reading-failures).

Before the user queues for a real match: the kit's tools closed, and `gameinfo.gi` differs from stock only in SearchPaths (and ConVars, if a mod set any).

## 6. Record it, and re-export if shared

- Once it works in-game: set `mod.json` `"verified"` to the new build and bump `"version"` ([Versioning](#versioning)).
- If the user shared it on GameBanana: `export_mod` (`pwsh -File tools\export.ps1 -Mod mods\<name>`), then follow [export](export.md). Tell them to replace the file there and archive the old one, so players can roll back. Publish an update that names the new build **even when nothing changed**: it clears mod managers' "outdated" warnings.
- `uninstall_mod` anything installed only for the test.

## Keep overrides as stock plus a diff

A mod that overrides a stock file keeps the **stock file of the build it was based on** next to its edited copy. After a patch, a 3-way merge (old stock → new stock, applied under the mod's edits) carries Valve's changes and the user's forward. A plain copied layout silently drops whatever Valve added since. `new_mod` lays mods out this way:

```
mods/<mod>/mod.json                                     # "gameBuild": the build the overrides are based on
mods/<mod>/stock/panorama/layout/players_list_entry.xml # stock copy (get-stock.ps1)
mods/<mod>/stock/STOCK.json                             # build + source of each stock file
mods/<mod>/src/panorama/layout/players_list_entry.xml   # the edited version
```

For an older mod without `stock/`: `get-stock.ps1 <game path> -Out mods\<mod>\stock`, from the build the override was based on if you can find it (GameTracking history, below), otherwise the current one.

The smaller the diff, the easier the merge and the fewer clashes with other mods. Prefer *adding* namespaced files and touching stock files at one small hook point ([docs/03](../docs/03-panorama.md#choosing-a-hook-strategy-decides-your-patch-burden)).

## Tracking updates

- **The installed build:** `game/citadel/steam.inf` → `ClientVersion=`. Record it with every release.
- **Steam news RSS:** `https://store.steampowered.com/feeds/news/app/1422450/`. Official changelog: `https://forums.playdeadlock.com/forums/changelog.10/`.
- **GameTracking-Deadlock Atom feeds** (the best signal):
  - all builds: `https://github.com/SteamTracking/GameTracking-Deadlock/commits/master.atom`
  - Panorama only: `https://github.com/SteamTracking/GameTracking-Deadlock/commits/master/game/citadel/pak01_dir/panorama.atom`
- **Mod managers:** Deadlock Mod Manager and Grimoire flag mods "not updated since <patch>".
- **"Update available" in-game, but Steam offers none:** `console.log` says `Version out of date (GC wants <N>, we are <M>)`. Valve's servers are already on a newer build; Steam offers it minutes later (restarting Steam forces the check). Mods don't cause this. Patches can land several times a day.

## Diffing builds with GameTracking

To see exactly what changed in a file between two builds (needs git; reads GitHub, not the game):

```bash
git clone --filter=blob:none https://github.com/SteamTracking/GameTracking-Deadlock.git && cd GameTracking-Deadlock
git log --oneline --grep='^6711 ' -1                       # commit for a ClientVersion
git log --oneline -- game/citadel/pak01_dir/panorama/layout/players_list_entry.xml
git diff <old>..<new> --stat -- game/citadel/pak01_dir/panorama/
# did any compiled file the mod overrides change? (CRC lines)
git diff <old>..<new> -- game/citadel/pak01_dir.txt | grep -E 'panorama/layout/(players_list_entry|profile_card|hud_escape_menu)\.vxml_c'
```

The last command, run for every stock path the mod overrides, is the earliest warning that a re-base is due. `pak01_dir.txt` also shows where a moved file went.

## Versioning

- SemVer plus the build: `1.2.0 (ClientVersion 6796)`.
- Patch bump = "re-based on the new build, no feature change". That covers most UI-mod updates.
- Keep a `CHANGELOG.md`: Keep-a-Changelog sections map onto GameBanana's update categories.
- Archive old files on GameBanana instead of deleting them, so users can roll back. If the mod's saved-data format changes, migrate forward and leave the old data readable.

## Pitfalls

- **All mods dead at once:** `gameinfo.gi` (step 4), not the mods. Steam's "Verify integrity" also resets it.
- **"Update available" in-game but Steam offers none:** Valve's servers are ahead; Steam offers it within minutes. Mods don't cause it ([Tracking updates](#tracking-updates)).
- **Source 2 Viewer can't read files after a patch:** the resource format changed, so step 1 fails; update it (`setup`, which needs the user's yes).
- **A mod that ships `scripts/*.vdata_c`** can lock new heroes after a patch. Take it out of the mod.
- **Nothing changes and nothing errors:** the path vanished (step 2), or a lower-numbered pak wins (`list_mods` action `conflicts`).
- **Never edit `generated/` by hand** to make it match: refresh it (step 1).
