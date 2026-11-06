# Recipe: a mod that remembers things (notes, marks, settings)

**The user says:** "save notes about players", "remember X between games", "add a button that saves…", "keep my settings".
**Kind:** UI mod + storage (`new-mod.ps1 -Kind data`). Needs Reduced CSDK 12. A GitHub account only if the user hosts their own storage page.

## 0. Explain how saving works (users ask)

Say it plainly:
- Deadlock mods can't write files.
- They save through a small web page that the game loads invisibly when it starts.
- The data stays on the player's PC, in Steam's browser storage. The page sends nothing anywhere.
- The browser files that data under the page's address. Same address, same data; a different address starts empty.
- Players install only the mod. They need internet when the game starts.

The details and the alternatives are in [docs/04](../docs/04-persistence-and-io.md#pick-a-pattern).

## 1. Choose the address: ask once

Every saving mod needs a storage page address, chosen before the mod is made and kept for good. Ask the user this once, in these words or close to them:

> Your mod saves through a small storage page on the web. Use the kit's page, or an address of your own?
> - **The kit's page:** free, nothing to set up. The kit's storage page is run by the kit's author, free, with no guarantee it stays online. If it goes away, mods that use it stop saving until their maker hosts the page at an address of their own, and data players saved under the old address does not carry over.
> - **Your own address:** your own copy of the same page, for example on your GitHub account (free; you sign in once).

Then:
- **The kit's page:** `new_mod` with `storeUrl: "kit"` (`new-mod.ps1 -StoreUrl kit`).
- **Their own address:** `new_mod` with `storeUrl` set to that `https://` address. For their GitHub it is `https://<their GitHub name>.github.io/<name>-store/`; make the mod with that address, then host the page there (step 2).

`new-mod.ps1 -Kind data` without `-StoreUrl` stops and prints this question, so it can't be skipped.

**Changing the address later is not supported.** Players' saved data stays with the first address: a mod that moves starts empty for everyone, and nothing carries the old data over. `store.ps1 -Publish` refuses to move a mod unless `-Force`, which is only safe before anyone has used it.

## 2. Scaffold (and host your own page, if chosen)

```powershell
pwsh -File tools\new-mod.ps1 -Name <name> -Kind data -StoreUrl <kit or https address> [-Hook <layout>]
```

This gives you:
- `src/panorama/scripts/<name>_kvbridge.js`: the storage client; don't edit it.
- `src/panorama/scripts/<name>_store.js`: the page address, also in `mod.json` (`store.url`).
- `src/panorama/scripts/<name>.js`: a working note box that saves under the namespace `<name>.v1`. Adapt it.
- `README.md`: how saving works for this mod, its address, and the warning if it uses the kit's page.

Choose the hook layout for where the feature lives ([docs/03 § Choosing a hook](../docs/03-panorama.md#choosing-a-hook-strategy-decides-your-patch-burden), the catalog's `ui.tsv`). The default overlay shows on the main menu and the HUD.

**Own address on GitHub:** `pwsh -File tools\store.ps1 -Mod mods\<name> -Publish` puts the kit's page there.
1. **Missing GitHub CLI:** `setup.ps1 -Approve gh`, after the user's yes.
2. **Exit 2, "not signed in":** ask the user to sign in once. In Claude Code they type `! gh auth login`, pick GitHub.com, then the browser. Have them create a free account first if they don't have one.
3. Run it again. It creates `<user>/<name>-store`, turns on Pages and waits until the page answers (1–10 minutes).

**Own address without the GitHub CLI:** the user clicks **Use this template** on the storage repo (`github.com/UnExploration/deadlock-mod-storage`; its README has the two-minute steps, ending in Settings > Pages) and gives you the address `https://<their name>.github.io/<repo>/`. **Elsewhere:** the user serves the kit's `store/index.html` as `index.html` at that address, over `https://`.

Check any address with `store.ps1 -Mod mods\<name>`: it says which page the mod uses and whether it answers.

## 3. Design the data

- **Keys:** `<name>.v1/<id>`, one key per thing.
  - Per player: the 32-bit account ID as a string ([docs/03 § Reading player identity](../docs/03-panorama.md#reading-player-identity)).
  - Settings: `<name>.v1/settings`.
  - The part after `<name>.v1/` may use letters, digits and `_ . - /`, at most 96 characters. The page refuses keys outside the mod's own namespace.
- **Values:** a JSON string with a version field, e.g. `{"v":1,"note":"…","u":<ms>}`. Validate what you read back.
- **Limits** ([docs/04 § Pattern A](../docs/04-persistence-and-io.md#pattern-a-in-detail-the-https-bridge-page)):
  - about 3,500 characters per value;
  - replies are capped at 4,096 characters;
  - about 4 requests per second.

  Cap free text: notes at about 280 characters.
- **Offline is read-only.** If the storage never reached `ready`, or a read failed, show that it's offline and **never write**. Writing would overwrite data you couldn't see.
- **Backup:** offer export/import codes ([docs/04 pattern F](../docs/04-persistence-and-io.md#pick-a-pattern)): `$.DispatchEvent('CopyStringToClipboard', code, code)` and a paste box. It's the only way players can keep a copy of their data.
- **Privacy:** never `$.Msg` user text. `mod.json` `privacy` already says where data lives and who runs the page; adjust it if the mod stores more than notes.

## 4. Build, test, check in-game

1. `node --test` in the mod folder. Extend the tests with each piece of pure logic you add.
2. `build.ps1 -Mod mods\<name> -Install`, with Deadlock closed.
3. **The user checks:** "Type something and press Enter: it says *saved ✓*. Restart Deadlock: is it still there?"
4. Read `console.log`. Look for `[<name>] loaded`, `bridge ready` and no `JS Exception`. If you see `bridge offline`, check the page with `store.ps1 -Mod mods\<name>` and read the `bridge url` lines.

Storage from places not tried yet (inside a context menu, for example, or typing in one) may behave differently. If the mod depends on one, probe it first (SKILL.md step 7).

## Pitfalls

- **Players without internet at launch** get no storage that session. Say so in the UI, not just in the log.
- **Text boxes in the HUD** take clicks where they sit. Keep them out of the way during matches, or put the feature in a menu.
- **Never rename** the mod's namespace or change its page address after release, because players' data would be stranded. A new data format gets `v: 2` inside the value, read alongside v1.
- `export.ps1` refuses a data mod that has no storage page address.
