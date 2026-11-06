# 1. How Deadlock mods load

Deadlock (internal name **citadel**, AppID 1422450) has **no official mod support**: no Workshop, no Valve tools, no `-mods` flag. Mods work by adding a folder to the Source 2 filesystem search path.

## The mechanism in one paragraph

`game/citadel/gameinfo.gi` → `FileSystem → SearchPaths` lists folders. The engine mounts them top to bottom, and **the first folder that has a file wins**. Mounting a folder also mounts every `pakNN_dir.vpk` directly inside it. Add `Game citadel/addons` *above* `Game citadel` and any file in `citadel/addons/pakNN_dir.vpk` shadows the same path in the base game's `citadel/pak01_dir.vpk`. A mod is a VPK of **whole replacement files and/or brand-new files** at their exact in-game paths.

## The gameinfo.gi edit

The stock block for the user's build is in [`../generated/build.md`](../generated/build.md), read off the install. `enable-addons.ps1` makes the edit for you; this is what it does.

Change **only** the `SearchPaths { … }` block. Keep Valve's language lines (`Game_UILanguage`, `Game_LowViolence`) as they are, then:
- add `Game citadel/addons` directly above `Game citadel`;
- add `Mod citadel` and `Write citadel` right after the addons line, and `Mod core` and `Write core` above `Game core`.

That's what Deadlock Mod Manager writes. For example, an edited block looks like this:

```
SearchPaths
{
    Game_UILanguage   citadel_*LANGUAGE*
    Game_LowViolence  citadel_lv
    Game              citadel/addons
    Mod               citadel
    Write             citadel
    Game              citadel
    Mod               core
    Write             core
    Game              core
}
```

- `Mod`/`Write` lines: Valve's own comment in the file says that with no `Mod`/`Write` key, the *first* `Game` path becomes MOD / DEFAULT_WRITE_PATH. Without them, `citadel/addons` would become the write path.
- Keep CRLF line endings, balanced braces (a typo gives `Failed to parse KeyValues` at launch) and the two `UserSettingsPathID` lines below the block.
- Create the folder `game/citadel/addons/` (it doesn't exist by default).
- **Copy Valve's current lines; never paste a block from an old guide.** `Game_Language` was renamed `Game_UILanguage` on 2026-09-29, and `Game_LowViolence` was added 2026-01-22. Lines like `AddonRoot`, `OfficialAddonRoot` and `AddonConfig` were never in Deadlock's file (they're CS2 leftovers).

## The matchmaking guard ("PGI"): what you must never edit

Since 2026-03-26, `gameinfo.gi` carries a `PGIVersion` hash. The client refuses to queue with the string `Citadel_StartMatchmaking_UnverifiedPGI`:

> "Unable to enter matchmaking while any party member is running Tools-mode, or has unsupported changes to the following sections of their 'gameinfo.gi': **Engine2, MaterialSystem2, NetworkSystem, Particles, RenderSystem, SceneSystem, WorldRenderer**"

- `FileSystem` (where SearchPaths lives) and `ConVars` are **not** guarded, so the addons edit is matchmaking-safe.
- Since 2026-09-29, convars flagged `gameinfo_cannot_override` are ignored when set from gameinfo.gi (124 convars carried the flag at build 6779). Valve is tightening this file over time.
- Running anything in Tools mode (`-tools`, CSDK's `bin_server`) blocks matchmaking. Close tools before queueing.
- "Performance config" tools often rewrite `SceneSystem`/`RenderSystem`. That trips the guard. The fix: Steam → Verify integrity, then re-apply only the SearchPaths edit.
- Watch the wording of `Citadel_StartMatchmaking_UnverifiedPGI` in [GameTracking](02-toolchain.md#gametracking-deadlock-read-game-files-without-extracting). If `FileSystem` ever joins the list, the addons method stops working for matchmaking.

## VPK naming, priority and limits

| Rule | Detail |
|---|---|
| Name | `pak` + **exactly two digits** + `_dir.vpk`: `pak01_dir.vpk` … `pak99_dir.vpk`. `pak00`, `pak1`, `pak100` and arbitrary names are **not** mounted. Gaps are fine. |
| Location | **Directly** inside `citadel/addons/`. Subfolders are ignored unless they get their own `Game` line, which is how mod managers implement profiles and overflow shards (`citadel/addons2`, …). |
| Priority | **Lower number wins**, whole file at a time. `pak01` beats `pak05` for any path both contain. Across folders, the earlier SearchPaths line wins. (Sources: community guides and Deadlock Mod Manager's conflict code; one search snippet disagreed. A 5-minute test with two VPKs overriding the same file settles it for your build.) `tools/mods.ps1 conflicts` lists every file that more than one installed mod replaces. |
| Granularity | Whole files only. Two mods that each edit part of the same file conflict; load order can't merge them. |
| Count | 99 per mounted folder. |
| Format | VPK **v2**, normally a single file (data inside `_dir.vpk`). Paths are lowercase with forward slashes and mirror the game path exactly. Only compiled `_c` resources load. A raw `.xml/.css/.js/.png` inside a VPK does nothing. |
| Multi-chunk | Only for > 2 GiB: `pakNN_dir.vpk` + `pakNN_000.vpk`…, renumbered together. |
| When read | **At startup only.** Deadlock holds VPKs open, so close the game fully before replacing one. Rejoining a match doesn't reload the UI. |

Language folders (`Game_UILanguage citadel_<lang>`) mount *before* addons, so a localized file in a language folder beats a mod for non-English clients.

## Search paths vs. the engine "addon" system

Source 2 also has a separate **addon** system (Workshop/UGC addons). `panorama.dll` restricts content from it: `"Addons cannot add layouts."`, `"Addons can only add layouts in the %s subdirectory."`, `"Addons cannot add ui scripts."`. Deadlock leaves that system unconfigured. Search-path mods are treated as first-party content, which is why they can add layouts and scripts. If you ever see those errors in the console, your files are being mounted through the wrong mechanism.

## Verify what is mounted

- Console `addons`: lists current addon info.
- Console `path` (standard Source 2): prints search paths.
- Fastest sanity check: does `gameinfo.gi` still contain `citadel/addons`? Steam rewrites the file whenever Valve changes it (14 times in 2026) and on Verify, and **all mods silently stop loading**. See [after a patch § 4](../cookbook/after-a-patch.md#4-turn-mod-loading-back-on).
