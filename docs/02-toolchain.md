# 2. Toolchain: read, compile, pack

Deadlock ships **no** `resourcecompiler.exe`, `vpk.exe` or `sdktools`. `game/bin/win64/` contains only `deadlock.exe` and `vconsole2.exe` (plus a `resourcecompiler.dll` you can't call directly). Valve has never released Deadlock workshop tools. Everything below is community tooling.

| Job | Tool | Notes |
|---|---|---|
| Get the stock file for **your** build, ready to override | [`../tools/get-stock.ps1`](../tools/get-stock.ps1) `<game path> -Out <mod>\stock` | Checks the file exists in your `pak01_dir.vpk`, then decompiles it with Source2Viewer-CLI (if in `toolsin\`) or downloads it from GameTracking when GameTracking is on your build. `-List <prefix>` lists paths; `-Raw` copies compiled bytes (sounds, textures). Records the build in `STOCK.json` |
| Read vanilla files without extracting | **GameTracking-Deadlock** (git) | Decompiled layouts, styles and scripts for every build |
| Extract/decompile from your install | **Source 2 Viewer** ≥ 20.1 (GUI + `Source2Viewer-CLI`) | Older versions fail on post-2026-09-29 resources |
| Compile `.xml/.css/.js` → `_c` | **Reduced CSDK 12** `resourcecompiler.exe` | Unofficial CS2-tools repack |
| Pack a VPK | [`../tools/build.ps1`](../tools/build.ps1)'s built-in packer (default), CSDK 12 `CSDKCfgVPK.exe` (`-Packer csdk`), S2V GUI, or Python `vpk` | VPK v2, single file. The built-in packer writes the layout every shipping mod VPK uses (checked on 11): all data in the dir file, CRC32 per entry, 48-byte MD5 section, no signature. Repacking two shipping mods gave the same entries and the same file size. Its VPKs load in-game |

## GameTracking-Deadlock: read game files without extracting

`https://github.com/SteamTracking/GameTracking-Deadlock` (moved from `SteamDatabase/…`; the old URL redirects). A bot commits each Steam build with the message `"<ClientVersion> | <n> files | …"`.

- `game/citadel/pak01_dir/panorama/{layout,styles,scripts}/`: **decompiled** XML/CSS/JS for every Panorama file
- `game/citadel/pak01_dir.txt`: every file in `pak01_dir.vpk` with CRC and size. Use it as a cheap "did the file I override change?" check
- `game/citadel/gameinfo.gi`, `steam.inf`, `resource/localization/*/*_english.txt`
- `game/**/bin/win64/*_strings.txt`: strings from the binaries (find console commands, panel events, JS API names)
- `DumpSource2/convars.txt`, `commands.txt`, `schemas/`; `Protobufs/*.proto`

Sparse-clone just the UI (fast, about 900 files):

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/SteamTracking/GameTracking-Deadlock.git gtd
cd gtd && git sparse-checkout set game/citadel/pak01_dir/panorama game/citadel/resource
```

Single files: `https://raw.githubusercontent.com/SteamTracking/GameTracking-Deadlock/master/game/citadel/pak01_dir/panorama/layout/hud_escape_menu.xml`

Build-to-build diffs and Atom feeds are covered in [after a patch § Tracking updates](../cookbook/after-a-patch.md#tracking-updates).

## Source 2 Viewer (ValveResourceFormat)

Download from `https://s2v.app/` or the GitHub releases of `ValveResourceFormat/ValveResourceFormat`. `cli-windows-x64.zip` contains `Source2Viewer-CLI.exe`. Use **20.1+** (2026-10-15). Always open the `_dir.vpk`, never a numbered chunk.

```powershell
$VPK = "C:\Program Files (x86)\Steam\steamapps\common\Deadlock\game\citadel\pak01_dir.vpk"
Source2Viewer-CLI -i $VPK --vpk_list -f "panorama/"                         # list (prefix match)
Source2Viewer-CLI -i $VPK -f "panorama/layout/,panorama/styles/,panorama/scripts/" -d -o C:\work\src   # decompile
Source2Viewer-CLI -i $VPK -f "panorama/layout/hud_escape_menu.vxml_c" -d -o C:\work\hud_escape_menu.xml
Source2Viewer-CLI -i .\pak64_dir.vpk -l          # list what YOUR vpk contains (do this before every release)
Source2Viewer-CLI -i .\pak64_dir.vpk --vpk_verify
```

- `-f` is a **prefix** match (`panorama/layout/` works, `escape` doesn't). Exit codes: 0 ok, 1 bad args, 2 a file failed (see `exceptions.txt`).
- `--vpk_create` (pack from the CLI) is on `master` since 2026-10-05 but **not in 20.1**. Use a dev build, or the GUI: File → Create VPK from folder.

### What compiled Panorama files contain (useful when debugging)

All `_c` files are Source 2 resource containers (block table: `RED2` metadata, `DATA`, …):

| File | Payload |
|---|---|
| `.vjs_c` / `.vts_c` | `DATA` = the JavaScript **as plain text** (plus an inline base64 source map for `.vts_c`) |
| `.vcss_c` | `DATA` = image refs + **minified CSS text**; `SrMa` = source map |
| `.vxml_c` | `DATA` is a few bytes. The layout lives in a `LaCo` block as a **compiled KV3 AST**. Not human-readable; you must decompile with S2V |

So hand-writing `.vxml_c` isn't practical, and you need a real compiler.

## Reduced CSDK 12: the compiler

"Community Source Development Kit 12" is an **unofficial, unsigned** repack of Valve's CS2 Workshop Tools plus Deadlock fixes, pinned to the 2025-08-19 Deadlock build. Its Panorama, texture and sound output still loads in today's game (our own in-game checks; community repos built with it were updated 2026-10-03/14/16). Models and animations are where the version gap shows.

1. **Install it with [`../tools/setup.ps1`](../tools/setup.ps1)** `-Approve csdk`, after the user says yes.
   - Setup downloads it only from the official Google Drive link on `https://deadlockmodding.pages.dev/modding-tools/csdk-12`. It's 2.4 GB, unsigned, and has no published checksum. Never rehost it.
   - It installs to `%LOCALAPPDATA%\deadlock-modding\Reduced_CSDK_12`. That's outside OneDrive (CSDK crashes there) and outside the game folder.
   - Drive often refuses big downloads with "quota exceeded", and that can last up to 24 hours. Setup then exits 2 and prints the page. The user downloads the zip in a browser, and setup installs it from Downloads on the next run.
   - The tools look for CSDK in `-Csdk`, then `$env:DEADLOCK_CSDK`, then the kit folder, then the community path `C:\Reduced_CSDK_12`.
2. **`csdkcfg.exe` isn't needed for building.** It's a GUI (addon list, Compile All Assets, Create VPK, Launch Tools) for people who want the Asset Browser. On a fresh install that never ran it, `build.ps1` compiled `.xml`, `.css`, `.js`, `.wav` and `.png` from the command line (Steam was running).
3. Sources go in `<CSDK>\content\citadel_addons\<addon>\panorama\{layout,scripts,styles,images}\…`. Addon names are lowercase with no spaces. `build.ps1` does this for you.
4. Compile from the CLI (verified in three community build scripts). [`../tools/build.ps1`](../tools/build.ps1) wraps all of this; run it with PowerShell 7 (`pwsh -ExecutionPolicy Bypass -File build.ps1 …`):

```bat
"C:\Reduced_CSDK_12\game\bin_cs2\win64\resourcecompiler.exe" -nop4 -f ^
  -i "C:\Reduced_CSDK_12\content\citadel_addons\mymod\panorama\layout\citadel_hud_and_db_overlay.xml" ^
  -i "C:\Reduced_CSDK_12\content\citadel_addons\mymod\panorama\scripts\mymod.js" ^
  -i "C:\Reduced_CSDK_12\content\citadel_addons\mymod\panorama\styles\mymod.css"
```

- Output lands in the mirrored game folder: `C:\Reduced_CSDK_12\game\citadel_addons\<addon>\panorama\…\*.vxml_c|vjs_c|vcss_c`.
- Batch up to about 25 `-i` inputs per call. Exit code 0 means success. Other flags: `-r` (recurse), `-v` (verbose).
- **Don't pass `-game …`** with the Reduced build. It fails with `Can't find 'game\citadel\gameinfo.gi'`, exit 2.
- Use `.js` → `.vjs_c`. Valve's own scripts are `.ts` → `.vts_c`, but CSDK 12's TypeScript support is unverified, and plain JS mods are proven (37-script mods are shipping).
- **Images** (`src/panorama/images/<mod>/x.png` → `panorama/images/<mod>/x_png.vtex_c`) compile only as children of a layout or style that references them as `file://{images}/<mod>/x.png`. `build.ps1` ships the result (whether the image shows in-game is untested). A game texture's image instead compiles through the `.vtex` that names it (`"m_fileName"`, as in a stock `.vtex` from `get-stock.ps1`) into that `.vtex_c`. `build.ps1` warns only about images neither uses. Stock images (`file://{images}/…`) and remote `https://` images need no compile.
- **Models** (`.vmdl` → `.vmdl_c`) compile from the CLI with no `-game`. The meshes and animations they reference (`.obj`, `.fbx`, `.dae`, `.dmx`) go next to them in `src` at the paths the `.vmdl` names. `build.ps1` stages them but doesn't ship them, because they compile into the `.vmdl_c`. A decompiled stock `.vmdl` compiled, and so did one whose `RenderMeshFile` pointed at a plain `.obj`. Its warning about a missing `default.vmat` is expected. A still model built this way shows in-game ([docs/09 route 4](09-asset-mods.md#4-prop-or-npc-model-swap-command-line)).
- The GUI equivalent: launch tools → Asset Browser → right-click → Recompile → Full.
- Alternatives:
  - **Dota 2 Workshop Tools:** several published Panorama mods were compiled with them (their files' headers say so), some updated 2026-10-17. They work for Panorama.
  - CS2 Workshop Tools' stock `resourcecompiler.exe`: unverified for Panorama, but used for skins and animations.

## Optional: audio from a link or any file (yt-dlp, FFmpeg)

For a sound mod made from the user's own clip ("make my kill sound this YouTube clip", an `.m4a` from their phone). Not needed for anything else, so `doctor.ps1` reports them as INFO, never FAIL, and `setup.ps1` lists them only with `-Media`.

- **Install** after the user's yes: `setup.ps1 -Media` lists them, `-Approve ytdlp,ffmpeg` installs them into `%LOCALAPPDATA%\deadlock-modding\bin` (copies already on PATH are used as they are).
  - **yt-dlp**: `yt-dlp.exe` from the latest release of `github.com/yt-dlp/yt-dlp` (~24 MB). Open source, **unsigned**; some antivirus tools flag it by mistake.
  - **FFmpeg**: the gyan.dev "essentials" build from the latest release of `github.com/GyanD/codexffmpeg` (~115 MB zip; only `ffmpeg.exe` is kept). Open source, **unsigned**.
  - Both are checked against the SHA-256 GitHub publishes for the file; setup refuses a file without one.
- **Convert** with [`../tools/audio.ps1`](../tools/audio.ps1) `<file or link> -Out <mod>\src\sounds\…\<stock name>.wav`:
  - Output is 44.1 kHz, 16-bit stereo WAV, the rate of Valve's own clips. `-Start`/`-End` (seconds or `m:ss.ms`) pick the part.
  - `-Like <event or sounds/… path>` reads that stock sound's `duration` from the catalog (`soundevents.tsv`) and cuts a longer clip to it with a 50 ms fade-out. The game cuts long sounds off anyway. `-NoTrim` keeps the length and only warns.
  - Loudness: one plain volume change (no compression) to -16 LUFS integrated, never above -1 dBFS peak, or to the loudness of `-Reference <audio file>`. Clips under about half a second can't be measured and are left as they are.
  - Only use audio the user may use. Publishing a mod with someone else's clip on GameBanana needs the rights to it.
- Verified (FFmpeg 2026-02-26 gyan.dev build already on the test PC): `audio.ps1` on generated tones wrote 44.1 kHz 16-bit stereo WAVs at the expected length and loudness. A clip fetched from a YouTube link, compiled and installed, played in-game. Not yet verified: setup downloading either tool.

## Packing the VPK

```bat
"C:\Reduced_CSDK_12\game\bin\win64\CSDKCfgVPK.exe" ^
  "C:\Reduced_CSDK_12\game\citadel_addons\mymod" ^
  "C:\Program Files (x86)\Steam\steamapps\common\Deadlock\game\citadel\addons\pak64_dir.vpk"
```

Check what you packed with [`../tools/vpk-list.ps1`](../tools/vpk-list.ps1) `pak64_dir.vpk` (no dependencies; `build.ps1` runs it for you).

Alternatives:

- **S2V GUI:** File → Create VPK from folder → Add existing folder → Save.
- **Python** (`pip install vpk`): `vpk -c <compiled folder> pak64_dir.vpk`. Writes a v2 single-file VPK. It doesn't lowercase paths for you, so make sure they already are.

Rules: the folder you pack must contain game folders (`panorama/…`) at its **top level**. Ship only the `_c` files you built or override. Never ship `scripts/*.vdata_c` from a UI mod; it breaks heroes after patches.

## Reference scripts to copy

Working, recently updated build pipelines (read them before writing your own):

- `antonborndev/deadlock-threat-hud` → `tools/build_mod.ps1` (PowerShell: compile + pack with Reduced CSDK)
- `mntbliss/Deadlock-QoL-HUD-Mod` → `build/compile.ts`
- `Predi-i/Deadlock-Mod-Compiler`, `Predi-i/Deadlock-UI-Mods` (hundreds of JS Panorama mods)
- `rszyma/deadlock-modbox` (patch-based UI mods, Linux/Nix CSDK)
