# __NAME__

A Deadlock mod that saves data. Made with deadlock-ai-mod-kit (`new-mod.ps1 -Kind data`), based on game build __BUILD__.

## What it does

A starter: a small note box in the top-left of the main menu and HUD. Type a note and press Enter; it's still there after a restart. Replace this section once it does something real.

## How saving works

Deadlock mods can't write files. This mod saves through a small web page that the game loads invisibly when it starts. The page keeps the data in Steam's browser storage on the player's own PC and never sends it anywhere. The browser files that data under the page's address, so the mod only finds what it saved for as long as it uses the same address.

**This mod's storage page:** __STOREURL__ (__STORE_OWNER__). It is written into `src/panorama/scripts/__NAME___store.js` and `mod.json` (`store.url`). This mod's data sits under the name `__NAME__.v1`; other mods using the same page can't see it.

__STORE_WARNING__

**Don't change the address later.** A different address starts empty: players lose access to everything they saved under the old one, and nothing carries it over.

**Hosting the page yourself:** `pwsh -File <kit>\tools\store.ps1 -Mod . -Publish` puts the kit's page on your GitHub account, free, at `https://<your GitHub name>.github.io/__NAME__-store/`, and writes that address into the mod. If the mod already uses a different address, it refuses unless you add `-Force`, which is only safe before anyone has used the mod. Players never deal with GitHub.

**Players need internet when the game starts.** Without it, the mod says so and saves nothing that session.

## Files

| Path | What |
|---|---|
| `mod.json` | Name, pak, version, the build the overrides were based on, overridden stock files, `store.url` (the storage page), and `privacy` (copied into the shared README) |
| `src/__HOOK__` | Override of a game layout: the stock file plus include lines for this mod's style and three scripts |
| `src/panorama/scripts/__NAME__.js` | The feature |
| `src/panorama/scripts/__NAME___kvbridge.js` | Storage client (copy of the kit's `templates/kv-bridge/kvbridge.js`; don't edit) |
| `src/panorama/scripts/__NAME___store.js` | The storage page's address |
| `stock/` | The untouched game files the overrides are based on; `rebase.ps1` uses them after a patch |
| `test/` | Node unit tests with a mocked Panorama `$`: `node --test` in this folder |

## Build and test (Deadlock closed)

```powershell
node --test
pwsh -File <kit>\tools\store.ps1 -Mod .               # shows the address and whether the page answers
pwsh -File <kit>\tools\build.ps1 -Mod . -Install
```

Start Deadlock. The note box shows on the main menu, and `console.log` has `[__NAME__] loaded` and `bridge ready`. Type a note, press Enter, restart: the note is still there.
