# __NAME__

A Deadlock mod. Made with deadlock-ai-mod-kit (`new-mod.ps1 -Kind empty`), based on game build __BUILD__.

## What it does

Nothing yet. Put files in `src/` at their game paths:
- compiled files (`*_c`) are packed as they are;
- sources (`.xml`, `.css`, `.js`, and experimentally `.mp3`, `.wav`, `.vtex`, `.vmat`, `.vpcf`, `.vsndevts`) are compiled with Reduced CSDK 12.

See the kit's cookbook/ for the guide for each kind of file, and docs/03-panorama.md (UI) or docs/09-asset-mods.md (sounds, textures, models, particles). A mod that only copies game files needs no `src/` at all: a `copies` map in `mod.json` (cookbook/sounds.md § 3).

## Build and test (Deadlock closed)

```powershell
pwsh -File <kit>\tools\build.ps1 -Mod . -Install
```
