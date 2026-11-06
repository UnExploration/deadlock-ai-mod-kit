# Docs: what the kit knows about Deadlock modding

Written against Deadlock as of October 2026. How mods load and what the game accepts rarely change between patches. Every path, ID and name comes from [`../generated/`](../generated/README.md) or the catalog, which are built from the installed game, so those never go stale. Anything not described here has not been tried.

This folder is **authored knowledge**: things nobody can read off the installed game. It comes from two kinds of source:
- **third-party:** GameTracking-Deadlock, Valve's posts and changelogs, GameBanana's rules, mod authors' published probes and code, Source 2 Viewer and CSDK behaviour;
- **our own checks:** in-game tests and desk compiles run while building the kit.

It is **never regenerated on the user's PC**.

**Its sibling, [`../generated/`](../generated/README.md), is the other half.** It holds Markdown rendered from the user's installed game: the build number, the stock `gameinfo.gi` block, file types, folders, heroes, every UI layout with its panel IDs, and sound and model summaries. `setup.ps1` in the repo root (or `catalog_refresh`, or `generate-docs.ps1`) writes it from the user's game, and rewrites it after every patch. Read `generated/` for *what is in the game right now* (paths, names, IDs, counts); read these docs for *how things work* and *what has been proven*. The full tables behind `generated/` are searched with `catalog_search`.

## The rule

If a tool can read a fact off the install, it is not written here. A doc points at `generated/` or the catalog instead, and may keep one example. Treat any path, name or count in these docs as an example; take the real one from the user's build. If something in-game contradicts a chapter, trust the game and tell the user.

**History keeps its own dates inline.** "City Never Sleeps (2026-09-29) changed 591 of 985 Panorama files", "only `https://` loads since 2026-10-01": these are about a moment, not a current value.

## Chapters

Surviving a game patch is a cookbook guide, not a chapter: [cookbook/after-a-patch.md](../cookbook/after-a-patch.md).

| Chapter | What it answers |
|---|---|
| [01 How mods load](01-how-mods-load.md) | How the game finds mod files, the `gameinfo.gi` edit, what never to edit (matchmaking guard), pak naming and priority |
| [02 Toolchain](02-toolchain.md) | Reading, decompiling, compiling and packing: GameTracking, Source 2 Viewer, Reduced CSDK 12, the VPK packer, optional audio tools |
| [03 Panorama](03-panorama.md) | How UI mods work: layouts, CSS, JS, hook strategies, reading player identity |
| [04 Persistence and I/O](04-persistence-and-io.md) | Saving data across restarts (the HTTPS bridge page and alternatives), outside data sources |
| [05 Dev loop](05-dev-loop.md) | Setup, build, install, test, read the log, decode error messages |
| [06 Distribution](06-distribution.md) | Packaging, GameBanana, mod managers, site rules, licensing |
| [08 Policy and safety](08-policy-and-safety.md) | Valve's position, bans, fair play, what a safe mod does |
| [09 Asset mods](09-asset-mods.md) | Sounds, textures, materials, particles, models: what to replace and which route works |
| [11 Panorama JS API](11-panorama-api.md) | Which `$` functions, panel methods and panel types exist in Deadlock, with proven/untested status |
| [12 UI hooks](12-ui-hooks.md) | What C++ feeds each player-related surface (dialog variables), how to read it, global hook points, useful panel events |
