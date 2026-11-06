# Recipe: share a mod (GameBanana zip)

**The user says:** "share my mod", "upload it to GameBanana", "make a zip for my friend".
**Kind:** any mod made with `new-mod.ps1`.

`export.ps1` is tested against fakes. Installing by hand from its zip is not tried in-game: before the user shares it, have them install it once from the zip and check it.

## 1. Before exporting

- **The mod must be verified in-game on the current build.** If `mod.json` `"verified"` isn't the installed build, run a test session first, then set it.
- **Ask the user, in plain words:**
  - the name to credit (`"author"`);
  - one sentence, in their own words, saying what the mod does (`"description"`).

  GameBanana bans AI-written descriptions, so write down what they say, not your own version.
- **Mods that save data:** add `"privacy"` to `mod.json`. It must say what is stored, where (docs/04), what goes over the network, and how to wipe it.
- The license defaults to MIT. Set `"license"` only if the user wants another.

## 2. Export

```powershell
pwsh -File tools\export.ps1 -Mod mods\<name>
```

It builds the mod, then checks the VPK. It stops on:
- raw sources and build leftovers;
- a `gameinfo.gi`;
- core game data (`scripts/*.vdata_c`).

Fix those in `src` or `mod.json`. Read every warning out to the user.

Output, in `mods/<name>/export/`:
- `<name>-<version>-b<build>.zip`: `pakNN_dir.vpk`, `README.txt` (install, uninstall, conflicts, credits, AI disclosure) and `LICENSE.txt`.
- `<name>-gamebanana.md`: the upload page's fields, rules and warnings. Walk the user through it.

## 3. The user uploads

The user uploads it themselves (the kit never posts). The steps are in the `-gamebanana.md` file:
- 2+ real screenshots;
- a description in their own words;
- the AI disclosure line;
- start private.

Suggest asking a moderator in the GameBanana Deadlock Discord first: largely AI-written mods are at staff discretion ([docs/06 § Rules](../docs/06-distribution.md#rules-that-bite-deadlock-section-as-of-2026-10)).

## Pitfalls

- **After every Deadlock patch:** re-test, bump `"verified"`, bump `"version"`, export again. On GameBanana, replace the file and archive the old one.
- **Pak number warning:** popular mods use the same number, so players who have them get clashes. Change `"pak"` in `mod.json` to a free number before the first release; afterwards the number should stay put.
