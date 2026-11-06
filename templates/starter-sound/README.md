# __NAME__

A Deadlock sound mod. Made with deadlock-ai-mod-kit (`new-mod.ps1 -Kind sound`), based on game build __BUILD__.

## What it does

A starter that needs **no compiler**: every main-menu hover and click sound (`sounds/ui/ui_menu_*`) plays the shop "purchase item" sound instead. If you hear the purchase sound when you hover over menu buttons, the whole pipeline works on this PC: packing, installing, mounting and loading.

It works because a compiled sound (`.vsnd_c`) can be copied to another sound's path and still play. Published killsound mods rely on this (the kit's docs/09-asset-mods.md).

## Files

| Path | What |
|---|---|
| `mod.json` | Name, pak number, version, and the game build the files came from |
| `src/sounds/ui/*.vsnd_c` | Compiled game sounds at the paths they replace. Packed as-is |
| `dist/` | Build output (`pak__PAK___dir.vpk`); not committed |

## Make it yours

- **Another game sound:** `get-stock.ps1 <sound path> -Raw -Out <tmp>`, then copy it over the files in `src/`.
- **Your own audio:** see the kit's cookbook/sounds.md § 4. That route needs Reduced CSDK 12, or a donor-patch tool.
- **Different targets:** put files at other `sounds/...` paths. `get-stock.ps1 -List sounds/` lists them all. Numbered variants (`_01`…`_13`) are picked at random, so replace every variant.

## Build and test (Deadlock closed)

```powershell
pwsh -File <kit>\tools\build.ps1 -Mod . -Install
```

Start Deadlock and hover over the main menu buttons.

## Install (for players)

1. Make sure `gameinfo.gi` mounts addons (Deadlock Mod Manager does this, or see the skill's `enable-addons.ps1`).
2. Copy `pak__PAK___dir.vpk` into `Deadlock\game\citadel\addons\`. If that name is taken, rename it to any free `pakNN_dir.vpk`.
3. Restart Deadlock.
