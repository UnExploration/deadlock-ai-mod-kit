# __NAME__

A Deadlock mod. Made with deadlock-ai-mod-kit (`new-mod.ps1`), based on game build __BUILD__.

## What it does

A starter: a small "__NAME__ v0.1.0" badge in the top-left of the main menu and HUD. Replace this section once it does something real.

## Files

| Path | What |
|---|---|
| `mod.json` | Name, pak number, version, the game build the overrides were based on, and which stock files are overridden |
| `src/` | Everything that goes into the VPK, at game paths. Compiled by `build.ps1` |
| `src/__HOOK__` | Override of a game layout: the stock file plus two include lines that load this mod's script and style |
| `stock/` | The untouched game files the overrides are based on, with `STOCK.json` recording the build. `rebase.ps1` uses them after a patch |
| `test/` | Node unit tests with a mocked Panorama `$`: run `node --test` in this folder |
| `dist/` | Build output (`pak__PAK___dir.vpk`); not committed |

## Build and test (Deadlock closed)

```powershell
node --test
pwsh -File <kit>\tools\build.ps1 -Mod . -Install
```

Start Deadlock. The badge shows on the main menu, and with `-condebug` in the launch options, `game\citadel\console.log` has a `[__NAME__] loaded` line.

After a Deadlock patch: `pwsh -File <kit>\tools\rebase.ps1 -Mod .` then build and test again.

## Install (for players)

1. Make sure `gameinfo.gi` mounts addons (Deadlock Mod Manager does this, or see the skill's `enable-addons.ps1`).
2. Copy `pak__PAK___dir.vpk` into `Deadlock\game\citadel\addons\`. If that name is taken, rename it to any free `pakNN_dir.vpk`.
3. Restart Deadlock.
