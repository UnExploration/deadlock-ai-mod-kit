# Generated game data

This folder holds data read off the Deadlock install on this PC: file paths, UI layouts and panel IDs, heroes, sounds, models. It is built here, from your own game, so it always matches the build you play. The kit does not ship it.

**Build or rebuild it** (first run, and after every Deadlock patch), any of:

- `setup.ps1` in the kit's root folder (builds it when it is missing or for another build)
- `pwsh -File tools/generate-docs.ps1` (`-Force` rebuilds the catalog first)
- the MCP `catalog_refresh` action

Needs PowerShell 7 and Source2Viewer-CLI; 1-2 minutes. The first line of each file names the build and the date it was read from, and `tools/doctor.ps1` warns when that is not the installed build.

**Never edit these files by hand.** The next rebuild overwrites them. Authored knowledge (how mods load, what was proven in-game) is in `docs/`.

## Files

| File | What it holds |
|---|---|
| `build.md` | Build number, Valve's stock `SearchPaths` block of `gameinfo.gi` (and whether this PC mounts addons), the `PGIVersion` line, the loose localization files |
| `file-types.md` | Every file extension in pak01: count, size, top folders, an example path |
| `folders.md` | pak01 folder tree to depth 2 with file counts |
| `heroes.md` | Every hero: codename, name, id, state, model, sound scripts, abilities |
| `ui-layouts.md` | Every Panorama layout: root panel, panel IDs, scripts, styles |
| `sounds.md` | Sound files per folder, events per `.vsndevts` file, how to search them |
| `models.md` | Models per folder with animation kinds, the plain-words alias index, how to search |

## The full tables

These pages are summaries. The full tables (one row per file, sound event, hero, UI layout or model) are on this PC at `%LOCALAPPDATA%\deadlock-modding\catalog\<build>\`: `files.tsv`, `soundevents.tsv`, `sounds.tsv`, `heroes.tsv`, `ui.tsv`, `models.tsv`, and a `README.md` naming their columns. Search them with the MCP `catalog_search` action (`table`, `query`, optional `column`), or:

```powershell
Select-String -Path "$env:LOCALAPPDATA\deadlock-modding\catalog\<build>\ui.tsv" -Pattern 'minimap'
```
