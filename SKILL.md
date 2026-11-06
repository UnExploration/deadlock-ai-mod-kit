---
name: deadlock-modding
description: Make, install, share and maintain mods for Valve's Deadlock (Source 2, internal name "citadel"). Use when someone wants a Deadlock mod built or changed (HUD and menu changes, overlays, notes/trackers, sounds, textures, skins), or asks about Deadlock VPK addons (pakNN_dir.vpk), gameinfo.gi, Panorama in Deadlock, installed-mod conflicts, publishing Deadlock mods, or fixing mods after a Deadlock patch.
---

# Deadlock modding

You're turning someone's idea into a working Deadlock mod. They're often not programmers. They describe what they want and run the game; you do the engineering with the tools below, and hand them only the steps that need a human.

**Find the request in the [cookbook](cookbook/README.md) first.** A guide gives exact files, tool calls and in-game checks. This page is the general workflow behind every guide.

Facts every task depends on, from [docs/](docs/README.md), written against Deadlock as of October 2026 (what that means is the first paragraph of the [docs index](docs/README.md)). Runtime behaviour comes from mod authors' published in-game tests unless a doc says otherwise; each doc marks what's proven, inferred or untested.

- **No official mod support.** Mods are `pakNN_dir.vpk` files in `game/citadel/addons/`. They're mounted by one `Game citadel/addons` line in `gameinfo.gi` SearchPaths and **shadow whole files** of the base game. The lower pak number wins conflicts (community consensus and Deadlock Mod Manager's code; not independently tested).
- **The UI is Panorama, driven by C++.** Layouts are filled by C++ panel classes. Mod JS runs on top and can only *read the UI*: there's no game API, no storage, no `fetch`, no `setTimeout`.
- **Anything persistent or external** goes through a side channel, usually a hidden HTML panel plus your own HTTPS page.
- **Compiled `_c` files, plus a few loose types.** Published mods also ship `resource/localization/*.txt` and nested map `.vpk` files (not tested here). Sources (Panorama XML/CSS/JS, audio, textures…) compile with Reduced CSDK 12's `resourcecompiler`. Mods that only copy game files (many sound mods) need no compiler; `build.ps1` packs the VPK v2 itself.
- **Patches break mods often.** Game data (paths, panel IDs, names) lives in [generated/](generated/README.md), rewritten for each build by `setup.ps1` or `catalog_refresh`; after a patch, follow [cookbook/after-a-patch.md](cookbook/after-a-patch.md).

## Tools

In [tools/](tools/). They run in PowerShell 7 (`pwsh -File tools\<name>.ps1`); `doctor.ps1` and `setup.ps1` also run in Windows PowerShell 5.1. Each has full help: `Get-Help tools\<name>.ps1 -Full`.

| Tool | Does |
|---|---|
| `doctor.ps1` | Read-only setup check: install, build, addons mount, guarded gameinfo sections, CSDK, Source2Viewer-CLI, Node, git, launch options, installed mods. Prints a fix per problem; exit code = number of failures |
| `tools/setup.ps1` | The download step behind the root `setup.ps1`: installs what's missing (PowerShell 7, Reduced CSDK 12, Source2Viewer-CLI, Node.js, git). No arguments: prints the list to show the user. `-Approve <ids>` after their yes. Exit 2 = CSDK waits for a manual download. `-Media` adds the optional yt-dlp and FFmpeg (only for sounds from a link or an audio file); `-Models` adds the optional Blender 4.5 (only for a model swap from a .dae, .fbx or other 3D file) |
| `audio.ps1` | `<file or link> -Out <x.wav>`: any audio, or a link's audio, to a 44.1 kHz WAV for a sound mod. `-Start`/`-End` cut it; `-Like <stock sound>` cuts it to that sound's length (from the catalog); loudness evened out (`-Reference <file>` to match one). Needs FFmpeg (and yt-dlp for links) |
| `convert-model.ps1` | `-In <3D file> -Out <folder in the mod's src>`: a model (.glb/.gltf/.obj built in; .dae/.fbx/… through Blender) to the OBJ, `.vmat`s and colour pngs a model swap compiles from, in inches and upright. `-Like <stock model>` fits it to the model it replaces. Materials are NPR-lit, the setup checked in-game (plain `pbr.vfx` shows near-black); `-Glow` adds a glow; `-CopyStockMaterial` copies the stock material's settings instead (untested in-game) |
| `preview-model.ps1` | `-Mod <folder> -Path <model game path>` (or `-Model <file>`): front and side wireframes over the stock model on an inch grid, as a PNG to look at, plus bounds and scale/orientation/placement warnings. Use before every in-game model test. Exit 1 = no mesh |
| `enable-addons.ps1` | Mounts `citadel/addons` in `gameinfo.gi` (SearchPaths only; idempotent; `-Check`) |
| `new-mod.ps1` | Creates `mods/<name>/` from a starter that works as-is, with a free pak number. `-Kind ui` (default): stock hook layout + two includes, script, style, tests. `-Kind data`: a UI mod that saves data (storage client, note-box starter); needs `-StoreUrl` (`kit` for the kit's hosted page, or the user's own `https://` address), asked once, never changed later. `-Kind sound`: menu sounds swapped, **no compiler needed**. `-Kind empty` |
| `store.ps1` | For `-Kind data` mods. No `-Publish`: status (which address, the kit's page or the user's own, whether it answers). `-Publish`: hosts the kit's storage page on the user's own GitHub (one-time `gh auth login` by the user) for a mod made with their own address |
| `catalog.ps1` | Searchable lists of the installed build in `%LOCALAPPDATA%\deadlock-modding\catalog\<build>\`: every file, every sound event and the files it plays, every hero (codename ↔ name ↔ model ↔ sound script ↔ abilities), every UI layout with its panel IDs, every model (plain-words aliases, materials, the textures they use, AnimGraph 2 or classic). **Search these before guessing a path** |
| `generate-docs.ps1` | Renders the catalog as readable Markdown in [generated/](generated/README.md) (build, stock `gameinfo.gi` block, file types, folders, heroes, UI layouts, sound and model summaries). Runs `catalog.ps1` first when the build has none. Run after every patch; the doctor warns when `generated/` is for another build. Never edit its output by hand |
| `get-stock.ps1` | Stock (original) game files for the **installed** build. `-List <prefix>` lists paths; `-Raw` copies compiled bytes. A texture comes out as an editable `.png` plus a `.vtex` that compiles it back to the stock path |
| `build.ps1` | Compiles sources (needs CSDK), packs `*_c` files as-is, packs and installs (`-Mod <folder> -Install`). Stops on a model that compiled with no mesh |
| `mods.ps1` | `list`, `conflicts`, `files`, `disable`, `enable`, `remove` for installed mods; `reset -Yes` removes every pak these tools built and unmounts addons |
| `rebase.ps1` | After a patch: 3-way merges the mod's changes onto the new stock files |
| `export.ps1` | `-Mod <folder>`: builds, checks the VPK for files that break shipping mods, and writes a GameBanana-ready zip (VPK, README.txt, LICENSE.txt) plus an upload checklist. Reads `description`, `author`, `license`, `privacy` from mod.json |
| `vpk-list.ps1` | Lists a VPK's files |

Their regression tests: `pwsh -File tools\test\tools.tests.ps1`. These run against a fake install and touch nothing real.

## Ground rules

- **Check the build first:** `doctor.ps1` prints it and warns when `generated/` describes another build: then run `setup.ps1` in the repo root (MCP `setup`, or `catalog_refresh`) before anything else. Layouts, IDs, paths and gameinfo lines come from `generated/` and the catalog, never from a doc's example. The docs are usually still right about mechanisms after a patch; if the game contradicts them, trust the game.
- **Touch the game install only through the tools.** That means `enable-addons.ps1`, `build.ps1 -Install` and `mods.ps1`, and only after the user has asked to install or test. Edit only `FileSystem → SearchPaths` (and optionally `ConVars`) in `gameinfo.gi`; seven other sections are matchmaking-guarded.
- **Downloads are the user's call.** `setup.ps1`'s list says what each download is for, where it comes from and how big it is. Show it and get one yes before `-Approve`. Reduced CSDK 12 is unsigned: say so.
- **Base every override on the stock file of the installed build** (`get-stock.ps1`, which `new-mod.ps1` runs for you). Keep the diff minimal.
- **Stay client-side and honest:** no memory reading, injection, input automation, or information the game hides ([docs/08](docs/08-policy-and-safety.md)). Notes and settings the player authored are fine. When an idea crosses the line, say so and offer the fair version.
- **Verify by running.** Unknown runtime behaviour is answered with a probe build and `console.log`, not by assuming Dota/CS2 APIs exist.

## Workflow: someone wants a mod

1. **Setup.** Run `doctor.ps1` (MCP `doctor`). If tools are missing, or `generated/` is missing or for another build, run `setup.ps1` in the repo root (MCP `setup`) with no arguments: it lists what's missing and builds `generated/` once PowerShell 7 and Source2Viewer-CLI are in place. Show the user the list, and after one yes run `setup.ps1 -Approve <ids>`. *Done when* the doctor exits 0 with every tool the planned mod needs, or the only things left are ones the user must do themselves (a manual CSDK download, a Steam setting) and you've given them the exact steps.
2. **Pin the idea.** Restate it as acceptance checks the user can see in-game ("ESC → Players → click a player: a Note button appears; the note is still there after a restart"). Say which kind of mod it is: UI (Panorama), assets (sounds, textures, models), or both. Search GameBanana Deadlock (game 20948) for mods that already do it. *Done when* the user agrees with the checks, and you can name the closest existing mod and how this one differs.
3. **Prove the pipeline, then scaffold.** On a PC that has never loaded a mod made with these tools, build an **untouched** starter and have the user confirm it in-game.
   - `new-mod.ps1 -Name firstlight -Kind sound` needs no compiler: menu hover sounds become the shop purchase sound.
   - For UI mods, also build the untouched `-Kind ui` starter once CSDK is installed: a badge on the main menu.

   The starter proves that the game mounts and loads mods made here; the first build of the real mod proves the compile route for its file type, because `build.ps1` stops when a source didn't produce its `_c` file.

   Then run `new-mod.ps1 -Name <name>` with the `-Kind`/`-Hook` the plan needs. *Done when* a starter has been seen or heard in-game on this PC (now or before). If it isn't, fix that before writing any feature: see "Reading failures" in [docs/05](docs/05-dev-loop.md#reading-failures).
4. **Locate.** Take every path, panel ID and name from the user's build, in this order:
   1. **[generated/](generated/README.md)**: `ui-layouts.md` lists every layout with its root panel and panel IDs, `heroes.md` maps a hero's name to its codenames, model and sound scripts, `file-types.md` and `folders.md` show where each kind of file lives, `sounds.md` and `models.md` summarise and say how to search.
   2. **The catalog** for anything finer (`catalog_search` / `catalog.ps1`; its README explains the columns): `files` for every path, `soundevents`/`sounds` for a sound and its random variants, `ui` to find a layout by panel ID, `models` for a model by what the user calls it ("the bartender in the hideout" is `models/hideout/hideout_bartender.vmdl_c`) with its materials and textures. Model aliases are a start, not complete: also search path words.
   3. **The stock file** (`get-stock.ps1 -List <folder>/`, then fetch it) to confirm the exact markup or bytes you'll override.

   - UI: the layout file and panel IDs come from `generated/ui-layouts.md`, confirmed in the stock file; what C++ feeds each surface and how to read it is in [docs/12-ui-hooks.md](docs/12-ui-hooks.md). *Done when* every surface you'll touch is named as layout file + panel ID + the dialog variables or properties C++ feeds it.
   - Assets: the route is in [docs/09-asset-mods.md](docs/09-asset-mods.md). *Done when* every file you'll replace is named by exact game path, all its random variants included, and you've picked a route (copy, CSDK compile, or a GUI hand-off).
   - For an asset-only mod, skip steps 5–7.
5. **Choose the hook.** Follow the ranking in [docs/03-panorama.md](docs/03-panorama.md#choosing-a-hook-strategy-decides-your-patch-burden). *Done when* you have the list of vanilla files you'll override, each justified, and none that a runtime injection could avoid. Fetch any extra ones into `stock/` with `get-stock.ps1 -Out <mod>\stock` and copy them to `src/`.
6. **Plan data.** Pick a pattern from [docs/04-persistence-and-io.md](docs/04-persistence-and-io.md) for each thing that must persist or come from outside. *Done when* every piece of state has a pattern and an offline behaviour.
7. **Probe the unknowns.** Use [templates/probe/probe.js](templates/probe/probe.js) and [docs/05-dev-loop.md](docs/05-dev-loop.md). Batch all questions into one launch. *Done when* every runtime assumption from steps 4–6 has a logged in-game answer.
8. **Build.**
   - Keep logic in pure functions, tested with `node --test` (the starter shows the pattern).
   - Start from [templates/kv-bridge/](templates/kv-bridge/) when you need storage.
   - Run `build.ps1 -Mod <dir> -Install`.

   *Done when* every acceptance check passes **after a full game restart**, and `console.log` shows no `JS Exception` from your scripts.
9. **Hand over.** Tell the user what changed, how to turn it off (`mods.ps1 disable <name>`), and what to do after the next patch (`rebase.ps1`). Offer to package it for sharing: the [export guide](cookbook/export.md).


## Working with the user

- **You can't see the game; they can.** Each launch costs them minutes, so run the unit tests and syntax checks before asking for one. Then ask for one specific observation ("Is there a yellow badge top-left on the main menu?"). Once they've closed the game, read `game\citadel\console.log` yourself (it needs the `-condebug` launch option).
- **Close before install.** Deadlock locks its files, so ask them to fully close it before any build with `-Install`. The tools refuse while it runs.
- **Explain in their terms.** "The game's ESC menu file", not "`hud_escape_menu.vxml_c`", unless they ask.

## Where to look

Two layers. [generated/](generated/README.md) is what is in the user's game right now, built on the user's PC from the installed build by `setup.ps1`: take paths, IDs and names from there. [docs/](docs/README.md) is how things work and what has been proven, written against Deadlock as of October 2026.

| Situation | Read |
|---|---|
| Any request: the guide for its file type | [cookbook/README.md](cookbook/README.md) |
| First run, tools missing, `generated/` missing or for another build | [setup.ps1](setup.ps1) in the repo root (MCP `setup`): checks, lists downloads, `-Approve <ids>` after the user's yes, builds `generated/` |
| The starter mods `new-mod.ps1` copies (`starter*/`), the storage client (`kv-bridge/`), the in-game probe (`probe/`) | [templates/](templates/) |
| What `generated/` holds and how it is built on the user's PC | [generated/README.md](generated/README.md) |
| Which build `generated/` describes, the stock `gameinfo.gi` SearchPaths block, loose localization files | [generated/build.md](generated/build.md) |
| Every file extension in the game, where each kind lives, the folder tree | [generated/file-types.md](generated/file-types.md), [generated/folders.md](generated/folders.md) |
| A UI layout's file, root panel and panel IDs | [generated/ui-layouts.md](generated/ui-layouts.md), then `catalog_search` table `ui` |
| A hero's codename, model, sound scripts, abilities | [generated/heroes.md](generated/heroes.md) |
| Sound folders and events, model folders and aliases, and how to search them | [generated/sounds.md](generated/sounds.md), [generated/models.md](generated/models.md) |
| What each docs chapter covers | [docs/README.md](docs/README.md) |
| Mods don't load, installing mods, gameinfo.gi, pak numbers, matchmaking blocked | [docs/01-how-mods-load.md](docs/01-how-mods-load.md) |
| Reading game files, decompiling, compiling, packing a VPK | [docs/02-toolchain.md](docs/02-toolchain.md) |
| Writing layouts, CSS or JS; hooking UI; reading account IDs | [docs/03-panorama.md](docs/03-panorama.md), [docs/11-panorama-api.md](docs/11-panorama-api.md), [docs/12-ui-hooks.md](docs/12-ui-hooks.md) |
| Saving data, talking to a companion app, external data (deadlock-api, console.log) | [docs/04-persistence-and-io.md](docs/04-persistence-and-io.md) |
| Setup, the build/test loop, debugging, reading error messages | [docs/05-dev-loop.md](docs/05-dev-loop.md) |
| Sounds, killsounds, music, textures, materials, particles, models/skins, crosshairs | [docs/09-asset-mods.md](docs/09-asset-mods.md) |
| Packaging, GameBanana, mod managers, licensing, site rules, pak numbers, crowded files | [docs/06-distribution.md](docs/06-distribution.md), crowded UI files in [cookbook/ui.md § 3](cookbook/ui.md#pick-the-cheapest-safe-strategy) |
| A Deadlock patch landed; re-basing overrides; tracking updates; versioning | [cookbook/after-a-patch.md](cookbook/after-a-patch.md) (refresh `generated/` first) |
| "Is this allowed / bannable / safe?" | [docs/08-policy-and-safety.md](docs/08-policy-and-safety.md) |

## Keeping this skill true

When you verify something new, or find a fact here contradicted, fix it in the **one** doc that owns it. Game data that is wrong or stale is fixed by regenerating `generated/`, never by editing it.
