# 6. Distribution: packaging, publishing, installing

## Where Deadlock mods live

- **GameBanana is the channel** (game id `20948`, `https://gamebanana.com/games/20948`). Every mod manager's catalog comes from it.
- There is **no Steam Workshop** for Deadlock and **no Nexus section**.
- **GitHub** is for source, issues and tagged releases. Link a release as a GameBanana *Alternate File Source*. No manager installs from GitHub.
- UI mods go in category **HUD** (QoL mods: *Quality of Life/Fixes*).
- **Sounds are a separate GameBanana section** (`gamebanana.com/sounds/<id>`), not a Mod category. When looking for an existing sound mod, search that section too.

## Mod managers (what users actually install with)

| Manager | Notes |
|---|---|
| **Deadlock Mod Manager (DMM)**: `github.com/deadlock-mod-manager/deadlock-mod-manager`, `deadlockmods.app` | The only installer GameBanana registers for Deadlock 1-click. Deep link: `deadlock-mod-manager:https://gamebanana.com/mmdl/<fileId>,Mod,<modId>`. |
| **Grimoire**: `github.com/Slush97/grimoire` | Strong #2. Can merge VPKs; has its own `gb1click://` |
| Simple DMM, HELLCAT, gameinfo "patchers" | Minor |

What managers do for you, so you don't have to:

- They find every `*.vpk` anywhere in your archive (multiple VPKs become selectable *variants*).
- They rename the file to the lowest free `pakNN_dir.vpk`.
- They manage the gameinfo.gi edit (DMM wraps it in `// Deadlock Mod Manager - Start/End` and keeps `gameinfo.gi.bak`).
- They shard past 99 VPKs and show conflicts. The rule they use is "the mod with the lowest (shard, pak number) wins every file it shares".

**Author obligations for manager compatibility:**

1. Host the file **on GameBanana**. That's what enables 1-click and update detection.
2. Put one `.vpk` per variant in a zip.
3. Update by **replacing** the installed file and archiving the old one. DMM tracks the specific file a user installed, so a newly added optional file doesn't trigger "update available".
4. Declare dependencies under *Requirements*.

## Packaging

```
mymod-1.0.0-b6801.zip    # export.ps1 -Mod mods\mymod makes exactly this
├── pak64_dir.vpk     # single-file VPK v2; avoid the numbers popular mods use
├── README.txt
└── LICENSE.txt
```

- **Namespace every new file** (`panorama/layout/mymod/…`, `panorama/scripts/mymod_*.js`, `panorama/images/mymod/…`). Only overridden vanilla files should share names with the game.
- **Override as few vanilla files as possible.** Each one is a guaranteed conflict and a file to re-base after every patch (see [03-panorama.md](03-panorama.md) for hooking strategies).
- No executables in the archive. An executable makes GameBanana require open source (rule R-DL.872) and triggers AV analysis. Ship a companion app separately, open source.
- **Before every upload, list the VPK** (`tools/vpk-list.ps1 pak64_dir.vpk` or `Source2Viewer-CLI -i pak64_dir.vpk -l`). Popular mods have shipped stray build leftovers that override real paths, and junk that loads as nothing but costs size: `readme.txt`, `panorama/image_compiler.vdata_c` (a CSDK build artifact), raw `.css`/`.js`/`.xml`/`.png`, `desktop.ini`, whole `node_modules`. Pack only the game paths you mean to ship.
- **Name the file `pakNN_dir.vpk`.** Names like `catlock.vpk` or `pak01_dir-1.vpk` don't mount until a mod manager or the user renames them.
- **Variants are one VPK per choice at the same pak number** (colours, volume levels, a build compatible with a big HUD mod); the user installs one. A small **add-on** VPK at a *lower* number than the main one overrides some of its files.
- **Pak number:** there's no registry. 01–03 and 98 are crowded. If you must *win* a contested file, you need a low number and must say so. Otherwise pick a mid number and say "rename to any free number; lower wins conflicts". Collisions between published mods are common. When your mod must sit above or below another, say so in words in the README ("use a lower number than QOL Lock").

### README.txt template

1. Name, version, **game build tested** (`steam.inf` ClientVersion) and date
2. What it does; which screens and files it changes
3. Install with DMM/Grimoire (1-click) **and** manually (addons folder, file name, the gameinfo lines from [01](01-how-mods-load.md), "don't paste old blocks")
4. Compatibility: known conflicts and the required load order
5. **Data and privacy:** where data is stored, what goes over the network, how to export, back up and wipe it
6. Uninstall: delete the VPK; optionally Verify files to restore gameinfo.gi; how to wipe stored data
7. After a Deadlock patch: "If you see *Unable to load layout file* or *Unable to find child*, disable this mod and check for an update"
8. Credits, **AI-assistance disclosure**, license, links

## Publishing on GameBanana

1. Make an account. Join the **GB Deadlock Discord** (`discord.gg/CaNPxMQeFN`) for moderator questions.
2. Deadlock page → **Add → Mod**. Fill in:
   - **Main:** name, category HUD, body text
   - **Ownership:** Credits module (credit reused code and techniques here, not just in the body), license and checklist
   - **Media:** **2+ real in-game screenshots** (rule R-DL.839); the first image is the thumbnail
   - **Files:** each file gets a description and version. Keep variant descriptions stable, e.g. "Standalone" vs "QOL-compatible"
   - **Submitter Instructions:** shown on the download page; good for load-order steps
3. Start **private**, check the page, then publish. Files are AV-scanned. Staff may withhold a submission with a rule code.
4. **Updates:** Edit → Media → upload the new file at the top and archive the old one. Then **Add Update** with the version and a categorized changelog (`Addition`, `Improvement`, `Adjustment`, `Tweak`, `Optimization`, `Bugfix`, `Removal`), and name the game patch ("Rebuilt for the 2026-10-16 update").

## Rules that bite (Deadlock section, as of 2026-10)

| Rule | Gist |
|---|---|
| **R-DL.824 Unfair advantage** | No info a non-modded player "cannot possibly acquire" (timers, unspent souls, seeing through fog, …). Making existing HUD more readable is fine. Notes the user wrote themselves are user-acquired info; SteamNotes and Deadlock Ranks are approved. |
| **R-DL.847 No AI-generated content** | Bans AI renders, screenshots, **"UI changes"**, textures and **"vibe code"**. **The sole exception is AI-assisted coding**, which must follow the site's AI addendum: disclose it and **name the tool** ("written with assistance from Claude (Anthropic), reviewed and tested by <author>"). Write the description and changelog yourself, use real screenshots, and own the code. The boundary is staff discretion, so **ask a moderator before submitting a largely AI-written mod.** |
| R-DL.839 | 2+ in-game screenshots |
| R-DL.872 | Executables must be open source |
| R-DL.825 | Respect the licenses of mods you borrow from; you need proof of permission |
| Site: Credits, Duplication, Harassment | Credit in the Credits module. Don't cross-post sections. Never ship content that targets identifiable players |

## Licensing

- Your VPK contains **modified copies of Valve layouts**. You can only license *your* additions. Say so.
- Prefer a permissive code license (MIT/Apache-2.0) and permissive GameBanana checklist answers. UI mods break every few weeks, and an ND license stops others from posting fixes if you go inactive.
- A "compatible build" that reuses another mod's version of a shared layout **needs that author's permission**, even under a permissive-looking license.
