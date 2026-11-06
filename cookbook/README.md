# Cookbook

Start here for any mod request. Every Deadlock mod is a pack file (`pakNN_dir.vpk`) in the game's addons folder. It does one of two things:
- **replaces** a game file at a path the game already reads, or
- **adds** a new file that a replaced file points to. A new file nothing points to is never loaded.

There is nothing else: no code injection, no memory reading. So route every request by **the type of file it changes**, then follow that row's guide.

## The method (every row)

The full workflow, with *done when* for each step, is [SKILL.md § Workflow](../SKILL.md#workflow-someone-wants-a-mod). In short:

**File names:** you edit and write source files (`.css`, `.xml`, `.js`, `.wav`/`.mp3`, `.png`…) at the game path of the file they replace; `build` compiles them to the game's names (`.vcss_c`, `.vxml_c`, `.vjs_c`, `.vsnd_c`, `.vtex_c`). The tables below use the compiled names (what the catalog lists); in `src` use the source name.

1. **Find the file** in the data read off the user's build: [generated/](../generated/README.md) first (UI layouts and panel IDs, heroes, file types, folders), then `catalog_search` (MCP) or `catalog.ps1` for single paths and sound events. Names, paths and codenames change with patches. Take them from there, not from any doc (the names in the guides are examples).
2. **Get the original:** `get_stock` / `get-stock.ps1`.
3. **Make the new file** from it, as the guide says.
4. **Build:** `build_mod` / `build.ps1`.
5. **Install** only when the user asked to install or test, with Deadlock closed: `install_mod` / `build.ps1 -Install`.
6. **The user checks in-game.** Batch every check into one checklist. Afterwards read the game log: `read_console_log`.
7. **Remove test installs** (`uninstall_mod` / `mods.ps1 remove`) once checked.

## By file type

The rows cover the file types in [generated/file-types.md](../generated/file-types.md), which lists every extension in the user's build with its count, folders and an example path. An extension missing from this table is found there: it belongs to the "Other types" row.

| File type | Requests that land here | Guide | Status |
|---|---|---|---|
| **Sounds** (`.vsnd_c`; routing in `.vsndevts_c`) | "change my kill sound", "change the hit / headshot sound", "make <hero>'s ult play this", "replace this voice line", "change the menu / shop music", "use the sound from this video" | [sounds.md](sounds.md) | Kill sound from another game sound: worked in-game. Own audio on an ability sound (WAV file, or a clip from a YouTube link): worked in-game. Own audio on the kill sound: compiles, not tried in-game. MP3 sources: desk only |
| **Images and textures** (`.vtex_c`) | "replace this icon with X", "change the shop icon of <item>", "new hero portraits", "put my picture on <ability> effect", "make <hero>'s <part> blue", "crosshair as an image" | [textures.md](textures.md) | worked in-game for particle icons, still and animated. Model-texture recolours and shop/HUD icons: compile at the desk, not tried in-game |
| **Models and materials** (`.vmdl_c`, `.vmat_c`) | "replace the soul orbs with pumpkins", "turn <prop> into <thing>", "replace <NPC> / the troopers with <character>", "use this downloaded model" | [models.md](models.md) | worked in-game for still models from OBJ. The Blender route (.dae/.fbx) and still meshes on animated NPCs: desk only |
| **UI, change existing** (layouts `.vxml_c`, styles `.vcss_c`; stock scripts are `.vts_c`) | "hide the minimap", "remove <HUD element>", "move / resize / recolour <HUD element>", "make the shop / build viewer look like X", "change my crosshair's shape or colour" | [ui.md § 3](ui.md#3-change-existing-ui-hide-move-resize-recolour) | draft, not tried in-game |
| **UI, add new** (new layouts, styles, `.vjs_c` scripts, hooked into a stock layout) | "show something on screen", "add an overlay / a badge", "add a button / a menu" | [ui.md § 4](ui.md#4-add-new-ui-overlay-badge-button) | worked in-game |
| **Saved data** (UI mod + storage) | "save notes about players", "mark a player", "remember X between games", "keep my settings" | [saved-data.md](saved-data.md) | draft |
| **Particles** (`.vpcf_c`) | "recolour <hero>'s ability effects", "remove clutter effects", "change the effect when X happens" | [docs/09 § What to replace](../docs/09-asset-mods.md#what-to-replace) | docs only, untested |
| **Text and localization** (`resource/localization/*.txt`) | "rename <item>", "change the description of <ability>", "change the hero's name in the menu" | none | not tried in-game. These are loose files in the game folder, not inside the game's paks, so they aren't in the catalog's `files.tsv`; [generated/build.md](../generated/build.md) lists them. Published mods ship them inside a VPK at the same path and expect that to override the loose file; that is untested here, so treat it as [no row fits](#no-row-fits) |
| **Hero skins** (hero model `.vmdl_c` and its materials) | "make a skin for <hero>", "replace <hero>'s model" | [docs/09 § Hero skins](../docs/09-asset-mods.md#5-hero-skins-the-user-does-gui-work) | docs only: guided. The user does the Blender and CSDK GUI steps; you write the text edits and check the result. Replacing or adding hero **animations** (`.vnmclip_c`, `.vnmskel_c`) is **not supported** (see below) |
| **Game data** (`.vdata_c`, `.vpulse_c`, maps) | "more stamina", "change <hero>'s stats / damage / cooldowns", "add a new hero", "a custom map" | none | **not supported**. See below. Names, descriptions and other text are the Text row, not this one |
| **Other types** (`.vcd_c`, `.vpost_c`, `.vsmart_c`, `.vsnap_c`, …: the rest of [generated/file-types.md](../generated/file-types.md)) | anything else | none | unknown. Look the extension up in [generated/file-types.md](../generated/file-types.md) for where it lives and an example path, then see [no row fits](#no-row-fits) |

**Game data means stats and behaviour** (damage, stamina, cooldowns, new heroes, maps). Renaming an ability or item, or rewriting its description, is only text: use the Text row.

**Game data, what to tell the user:** "Stats, abilities, heroes and maps are decided by Valve's servers. Changing those files only works in a local practice game, can block matchmaking, and breaks with every patch, so this kit doesn't make them." Offer what *is* possible: a visual or sound change, or a UI change that shows information the player already has.

**"It's only for bot / practice games":** the answer is the same. The kit still doesn't build game-data mods (they break with every patch and can block matchmaking). Say so plainly, then offer the fair alternatives above.

**Never ship** `scripts/*.vdata_c`, `.vnmskel_c` or `.vnmclip_c` inside a skin: they break other heroes and mods after patches ([docs/09](../docs/09-asset-mods.md#what-to-replace)).

**Crosshair, which row?** First mention the in-game `citadel_crosshair_*` settings: many players only need those ([docs/09](../docs/09-asset-mods.md#what-to-replace)). For a change of shape, colour or size, use the UI style route on `panorama/styles/ability_hud_elements/element_gun` (what published crosshair mods do), [ui.md § 3](ui.md#3-change-existing-ui-hide-move-resize-recolour). Use the image route (reticle textures, one set per hero, [textures.md](textures.md)) only for a custom drawn image.

## Managing mods

| The user says… | Guide | Status |
|---|---|---|
| "share my mod", "upload it to GameBanana", "make a zip for my friend" | [export.md](export.md) | draft |
| "the game updated", "my mod broke after the update", "update my mod" | [after-a-patch.md](after-a-patch.md): first `catalog_refresh` | draft |
| "undo everything", "my game is broken", "turn mods off", "remove my mod", "I want vanilla Deadlock back" | [reset.md](reset.md) | draft |
| "my mods clash", "only one of my mods works", "is this compatible with <mod>?" | `list_mods` with `conflicts` / `mods.ps1 conflicts`: lists every file several mods replace and which one wins (the lower pak number). Background: [docs/01 § VPK naming](../docs/01-how-mods-load.md#vpk-naming-priority-and-limits) | tool tested against fakes |

## Not possible

**A mod can't make the character do something** (emotes, animations on a key press, moves): UI scripts can only change the UI, and there's no game API ([SKILL.md](../SKILL.md)). Offer the UI alternative: a key-bound on-screen effect ([ui.md § 4](ui.md#4-add-new-ui-overlay-badge-button)).

A cosmetic UI response to the player's own key press (a sound, a pop-up, an on-screen effect) is fine. Anything that reads game memory, injects code, automates input (macros, aim help, auto-actions), reveals what the game hides (enemies through walls or fog, hidden cooldowns, other players' private data), or changes gameplay in real matches. Say plainly that the kit won't make it, and why: it's unfair to other players and risks the user's account. Then offer the fair version: notes the player writes, a UI change that shows only what they can already see, or a cosmetic change that keeps sizes, brightness and loudness close to the original. Details: [docs/08](../docs/08-policy-and-safety.md).

## No row fits

The request lands on a file type no guide covers, or you can't tell which type:

1. Find the file: [generated/file-types.md](../generated/file-types.md) shows which folders hold the extension, and [generated/folders.md](../generated/folders.md) the folder tree; then search the catalog's `files` table (`catalog_search` with `table: files`) by path words or extension.
2. Tell the user plainly: "This kind of mod is untested in this kit. I'll try the smallest possible change first."
3. Prove the smallest change (one file, one obvious difference) in **one** in-game check before building the whole mod. Read the log afterwards.
4. Then build the mod from [SKILL.md](../SKILL.md). If it worked, say so in a line and offer to write it up as a guide; write it only if the user asks.

## Status legend

- **worked in-game**: seen working in-game.
- **draft** / **not tried in-game**: written, not seen in-game; have the user check it.
- **docs only**: knowledge in the docs, no step-by-step guide.
- **not supported**: the kit won't make it; the row says what to tell the user.
