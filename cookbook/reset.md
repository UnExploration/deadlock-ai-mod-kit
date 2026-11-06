# Guide: turn mods off or undo everything

**The user says:** "undo everything", "my game is broken", "turn mods off", "remove my mod", "the game crashes on start", "I want vanilla Deadlock back".
**Kind:** any mod. Background: [docs/01](../docs/01-how-mods-load.md), [docs/05 § Reading failures](../docs/05-dev-loop.md#reading-failures).

This guide uses existing tools; it hasn't been walked end to end in-game.

Go from least to most drastic and stop at the first step that fixes it. Steps 1-4 change the game folder: do one only when the user asked for it, and say what it does first. They need **Deadlock fully closed** and take effect at the next launch. `mods.ps1` means `pwsh -File tools\mods.ps1`.

## 0. Read, change nothing

Always first when something is "broken".

- `doctor` (or `powershell -ExecutionPolicy Bypass -File tools\doctor.ps1`): game found, `gameinfo.gi` mounts addons, which mods are installed.
- `list_mods` (`mods.ps1 list`): every pak, enabled or disabled, which mod made it, what it changes. Action `conflicts` (`mods.ps1 conflicts`): files two mods both replace; the lower pak number wins.
- `read_console_log` (`mod` narrows to one mod), or `Select-String` on `game\citadel\console.log`. It needs `-condebug` in the launch options (`doctor` checks) and is overwritten on every launch, so copy it before the user relaunches. Look for:
  - `Failed to parse KeyValues`: broken `gameinfo.gi` (step 5);
  - `Unable to find child` / `Unable to load layout file`: a UI mod out of date ([after a patch](after-a-patch.md));
  - `JS Exception`: that mod's script.
- Every mod stopped at once after an update? `mount_addons` action `check` (`enable-addons.ps1 -Check`). "Not mounted" means a patch reset `gameinfo.gi`: [after a patch](after-a-patch.md) step 4, not a reset.

## 1. Turn one mod off (keeps it)

- MCP: `disable_mod` (`mod`: name, pak number or file name). Script: `mods.ps1 disable <mod>`.

Moves its pak to `game\citadel\addons_disabled`; nothing is deleted. Back on: `disable_mod` with `enable: true` (`mods.ps1 enable <mod>`; it refuses if another enabled mod now has that pak number). To find which mod causes a crash: disable one, the user launches, repeat.

## 2. Remove one mod

- MCP: `uninstall_mod`. Script: `mods.ps1 remove <mod> -Yes` (without `-Yes` it refuses).

Deletes that pak, enabled or disabled. The source folder `mods/<name>/` stays, so `install_mod` puts it back. Tell the user, so they don't think their work is lost.

## 3. Turn mod loading off, keep the mods

- MCP: `mount_addons` action `disable`. Script: `pwsh -File tools\enable-addons.ps1 -Disable`.

Removes exactly the lines the kit added to `gameinfo.gi`. The paks stay on disk but nothing loads. Back on: action `enable`.

## 4. Reset: undo everything the kit installed

Only when the user says "undo everything" or the game is still broken. Say plainly first: it deletes every mod made with the kit from the game.

- MCP: `reset_all` with `confirm: true`. Script: `mods.ps1 reset -Yes` (without `-Yes` it stops and lists what it would delete).

It:
- deletes every pak built with these tools, enabled or disabled (the kit records them in `%LOCALAPPDATA%\deadlock-modding\paks.json`);
- then unmounts `citadel/addons` in `gameinfo.gi` (Valve's lines back), **unless other mods are still installed**;
- leaves `mods/` (the sources) alone, so any mod can be installed again.

It does **not**:
- touch paks it didn't build (Deadlock Mod Manager, other tools, hand-copied). They stay installed, `citadel/addons` stays mounted, and it prints their names. DMM tracks its own paks, so remove those in DMM. Otherwise, if the user asks, `mods.ps1 remove <pak number> -Yes`, then run reset again to unmount;
- change any other game file, the launch options, or the user's settings.

## 5. Steam "Verify integrity of game files"

Suggest it when the kit's tools can't fix things; the user runs it: Steam > Deadlock > Properties > Installed Files > Verify integrity of game files. Cases:
- `Failed to parse KeyValues` or other `gameinfo.gi` errors, or `enable-addons.ps1` says it can't find the SearchPaths block (reset can't unmount a file it can't parse);
- the game still crashes on start with no mods installed;
- "Unable to enter matchmaking" after `gameinfo.gi` sections other than SearchPaths were edited ([docs/01](../docs/01-how-mods-load.md#the-matchmaking-guard-pgi-what-you-must-never-edit)).

Verify restores Valve's `gameinfo.gi`, which also switches mods off. To use mods again: `mount_addons` `enable`. Don't paste `gameinfo.gi.pre-addons.bak` back unless no patch landed since it was made.

## Pitfalls

- "Crashes on start": suspect the newest mod, or an old UI mod after a patch (step 0), before the game files.
- A removed mod still shows in-game: the game wasn't fully closed, or another pak replaces the same file (`conflicts`).
- After an in-game test, `uninstall_mod` only what was installed for it; don't reset everything.
