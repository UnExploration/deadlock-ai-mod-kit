# 9. Asset mods: sounds, textures, materials, particles, models

Marks used here:
- **proven**: a shipping mod does it;
- **local**: checked against the game files;
- **guide**: a community guide says so;
- **desk**: compiled and inspected at the desk, not seen in-game;
- **untested**.

Paths, counts and codenames below are examples. Take the real ones from the user's build: [`../generated/`](../generated/README.md) summarizes it, and `catalog_search` searches the full tables.

**An asset mod replaces whole files at the paths the game already loads.** There's no patching: you ship a whole compiled file (`*_c`).

New files are fine **when a file you replace points to them**. For example:
- skins add 35–133 new hash-named textures and materials, which their replaced model or material points to;
- sound mods add new `.vsnd_c` names, which their replaced soundevents point to.

A new file nothing points to is never loaded. Loading, pak numbers and conflicts work as for UI mods ([01](01-how-mods-load.md)). GameBanana's biggest categories are skins (3,300+), then sounds (ability, VO, music, killsounds), HUD, and model replacements (mostly soul containers).

## What to replace

| Kind | Files | How to find the right one |
|---|---|---|
| **Sounds** | `sounds/**/<name>.vsnd_c` (tens of thousands, mostly VO: over 90,000, 80k of them VO. Per-folder counts: [`../generated/sounds.md`](../generated/sounds.md)) | Search `soundevents.tsv` and `sounds.tsv` from `catalog.ps1`: an event lists every file it picks from, and a file lists every event that plays it. `heroes.tsv` ([`../generated/heroes.md`](../generated/heroes.md)) gives each hero's sound script. Also `get-stock.ps1 -List sounds/<folder>/`. Hero folders use **sound codenames**, which can differ from the model's (for example: Grey Talon = `orion`, McGinnis = `forge`, Mo & Krill = `krill`, Ivy = `tengu`). In-game: `sv_cheats 1; snd_showstart 1` in a local map (`map dl_hideout`), then trigger the sound. Both commands are cheats |
| **Killsound** | `sounds/hit_indicators/damage_send_lethal_01..06.vsnd_c` (proven) | Replace **all six** variants; the game picks one at random. Trooper and denizen kills may fire a different event (a killsound author says they share this one; untested) |
| **UI sounds** | `sounds/ui/*.vsnd_c` | For example, from the stock soundevents (local):
- Hovering a main-menu, shop-mod or settings item plays `UI.MainMenu.Hover` / `UI.Shop.Mod.Hover` / `UI.Settings.Hover`, which pick from `ui_menu_hover_01..08`. Files 09–13 and `ui_menu_hover` are used by no event.
- The big play-menu buttons play `UI.PlayMenu.Activate` (`ui_menu_press_big_01..04`).
- Opening a page or closing a menu plays `ui_menu_open_swoop_01..07`.

The catalog has the rest. Events played from code can't be seen there; `snd_showstart` shows those |
| **Music** | `sounds/music/**`. Menu music is `Music.MainMenu` → `sounds/music/music_menu_lp.vsnd_c` (247 s, loops from 57 s). `sounds/music/menu/curio_music*.vsnd_c` is the shop (`Music.Shop`, `Music.Shop.Secret`). Also `match_intro/*`, stingers (example, desk) | Music loops; keep a looping donor. Whether an event that lists several music files picks one at random or layers them is untested: replace them all |
| **Sound routing** (volume, pitch, which files an event plays) | `soundevents/hero/<codename>.vsndevts_c`, `soundevents/vo/…`, `soundevents/ui.vsndevts_c` | Decompile with Source2Viewer-CLI `-d`. **Whole-file override**: it conflicts with any other mod shipping that file, and goes stale (new events go silent) after patches. One soundevents file serves many heroes or the whole world, so a trimmed or outdated copy can silence other heroes' lines |
| **Textures** | `**/<name>_<srcext>_<8-hex>.vtex_c` (model textures are hash-named); UI textures have no hash | Open the model in Source 2 Viewer → References. Materials don't always sit next to their model |
| **Materials** | `**.vmat_c` (heroes use `pbr.vfx`; tint `g_vColorTint1`, glow `g_flSelfIllumScale1`) | Same |
| **Particles** | `particles/abilities/<codename>/*.vpcf_c`, `particles/weapon_fx/…` | `sv_cheats 1; dumpparticlelist` after using the ability |
| **Models** | `models/heroes_{wip,staging}/<codename>/<name>.vmdl_c`; soul container `models/props_gameplay/soul_container/soul_container.vmdl_c` (local; one guide's `props/gameplay` path is wrong) | Hero codenames and model folders for the user's build: [`../generated/heroes.md`](../generated/heroes.md) (also the DivineSkins wiki "Hero names and file paths"). Props and NPCs: `get-stock.ps1 -List models/<folder>/`; a decompiled `.vmdl` with `AnimFile` entries and no `AnimGraph2List` can be swapped from the CLI (route 4) |
| **Crosshair** | Panorama, not assets: `panorama/styles/ability_hud_elements/element_gun.vcss_c`, or `panorama/images/hud/crosshair/reticle{center,pip}_<codename>_psd.vtex_c` (proven) | Many players only need the `citadel_crosshair_*` settings |
| **Cursor** | Loose files in `game/citadel/resource/cursors/*.bmp`. Shipping cursor mods overwrite these in the install, which this skill doesn't do. Whether an addon VPK can override them is **untested**. Published mods ship `resource/localization/*.txt`, also loose files, inside VPKs, which suggests loose files can be overridden; also untested here | — |

**Never ship** `scripts/*.vdata_c`, `.vnmskel_c` or `.vnmclip_c` from a skin. They break other heroes and mods after patches.

## Routes, from easiest

### 1. Copy a compiled game file (no compiler) — proven for sounds

A compiled `.vsnd_c` can be copied to another sound's path and still play. A shipping killsound mod ships one clip under six names, and its embedded source name doesn't match its path. It's proven within one folder, and across folders too: a `sounds/ui/` clip copied over the kill sound played on every hero kill in-game.

```powershell
pwsh -File tools\new-mod.ps1 -Name firstlight -Kind sound      # menu hover/click sounds -> shop purchase sound
pwsh -File tools\get-stock.ps1 sounds/hit_indicators/damage_send_crit_01.vsnd_c -Raw -Out $env:TEMP\donor
# copy the donor to each target path under mods\<name>\src\sounds\..., then:
pwsh -File tools\build.ps1 -Mod mods\<name> -Install            # packs *_c files as-is: no CSDK needed
```

`new-mod.ps1 -Kind sound` is also **the fastest proof that a PC's pipeline works**: no compiler, and the result is audible on the main menu.

### 2. Your own audio, art or effects with Reduced CSDK 12

Put sources in `mods/<name>/src` at their game paths; `build.ps1` compiles them. Panorama CLI compiles are proven. For these types **no public script compiles from the command line** (every guide uses the CSDK GUI), so `build.ps1`'s support is **untested**. Read its output, and confirm in-game.

| Source | Becomes | Notes |
|---|---|---|
| `.mp3` / `.wav` | `.vsnd_c` | Guide: [sounds](../cookbook/sounds.md). Valve's own sources are 44.1 kHz MP3 (local, 299/300 sampled clips); 48 kHz works (proven). Match the original's length and loudness: long audio is cut off. A `.wav` compile plays in-game. Desk: `.wav` compiles to lossless PCM16; `.mp3` compiles from the CLI and stays MP3 (`lame_enc.dll` ships in Reduced CSDK 12); a WAV `smpl` chunk sets `m_nLoopStart`/`m_nLoopEnd`. Our compiles have `m_pEnvelopeAnalyzer = null` where stock has a curve. Read any clip's rate, length and loop with `Source2Viewer-CLI -i <game>\pak01_dir.vpk -f <path> -b CTRL` (also works on a mod VPK) |
| `.vtex` + image | `.vtex_c` | Guide: [textures](../cookbook/textures.md). Get the stock texture with `get-stock.ps1`, which always writes a `.vtex` + png pair; then edit the png at the **same size**, keep alpha, and paint only `color` maps. The output keeps the hashed name, so it replaces in place. A particle-icon texture made this way shows in-game; the rest is desk: Source2Viewer-CLI `-d` alone writes a `.vtex` only for textures the game compiled from one. Hash-named model textures and Panorama `_psd` icons come out as an image only (PNG, or EXR for HDR), so get-stock writes their `.vtex` from the stock file's format and no-LOD flag. A 200×200 icon, a particle icon and a 4096² model colour map compiled back to their stock paths. Non-power-of-two sizes need mip algorithm `None`; `Box` fails with "non-power-of-two texture support". **Recolor by editing pixel bytes** (`LockBits`), never by redrawing: GDI+ `DrawImage` drops RGB under alpha-0 pixels, and model textures often use alpha as a mask (78% of the bow) |
| `.vmat` | `.vmat_c` + new hash-named `.vtex_c` | Ship the textures the compile made for **your** images, or you get a checkerboard. `build.ps1` leaves out the `materials/default/*.vtex_c` it also writes: the game has them, and CSDK's copies differ in size (desk). A `.vmat` with a new png shows in-game in the model swap. Details under route 4 |
| `.vpcf` | `.vpcf_c` | A decompiled stock `vpcf63` file compiles **unchanged** (an item-effect particle under `particles/upgrades/`, desk). CSDK 12 writes it as `vpcf61`; decompiling the result gives the same text except that header line. No header edit needed. An edited stock particle compiled this way plays in-game ([textures § Animated particle icon](../cookbook/textures.md#animated-particle-icon-flipbook)) |
| `.vsndevts` | `.vsndevts_c` | Whole-file override; see the table above |

### 3. Third-party compiler-free tools (ask the user first)

These are open source (MIT), and each is a single small project, so treat them as fragile. They're third-party downloads, so they need the user's OK.
- **vpkmerge** (`github.com/Slush97/vpkmerge`, v0.23.2, 2026-10-19):
  - `texture <path> --from-vpk <pak01> --hue <deg> --encode-vpk out.vpk` (recolor);
  - `soundevents <path> --from-vpk <pak01> --set "Event/volume=0.5"` (verified in-game by its author; whether the `volume` unit is linear or dB is untested);
  - `recolor-hero --hero <codename>` (hero VFX).
- **Deadlock Mod Manager's** `vpkmanager` crate: makes a `.vsnd_c` from a donor clip plus your MP3, and recolors textures and particles. It's Rust and has no CLI.

Don't decode and re-encode `.vpcf_c` with a generic KV3 tool. The engine depends on value flags that naive round trips lose (DMM's code comments).

### 4. Prop or NPC model swap (command line)

Guide: [models](../cookbook/models.md). For models with no AnimGraph 2 (static props, and NPCs with a classic `Skeleton` + `AnimFile` list; `models.tsv`'s `anim` column says `classic`), the whole swap runs from the CLI. The soul-container swap is **verified in-game**. A still mesh on an animated hideout NPC also showed in-game; how it looked while the idle played wasn't checked.

1. `get-stock.ps1 -Out mods\<mod>\src <model>.vmdl_c` gives the `.vmdl` plus its mesh, animation and hull `.dmx` files at their game paths.
2. `convert-model.ps1` turns the replacement into an OBJ (inches, upright), one `.vmat` (NPR-lit, see **Materials** below) and one colour png per material. Point `RenderMeshFile.filename` at the OBJ. Keep the `Skeleton`, `AnimationList` and `PhysicsShapeList`: a desk-tested hideout NPC still had all 55 bones and both animations, compiled with no warnings, and kept the stock collision hull.
3. `build.ps1 -Mod` compiles the `.vmdl` with the rest of `src` (no `-game` argument needed; the soul-container example built this way). It ships the `.vmdl_c`, your `.vmat_c` and your hash-named `.vtex_c`, and stops when the model compiled with no mesh.
4. `preview-model.ps1` draws it over the stock model before any in-game test (below).

Calling `resourcecompiler` by hand works too: `& "$csdk\game\bin_cs2\win64\resourcecompiler.exe" -nop4 -f -i "$csdk\content\citadel_addons\<mod>\<path>.vmdl"`, output under `game\citadel_addons\<mod>\`. Only `bin_cs2` works; `bin\` and `bin_tools\` abort with a schema mismatch.

**Mesh formats.** `RenderMeshFile` reads **FBX, DMX, SMD and OBJ** only. `.dae` fails ("Unknown/unsupported geometry/model format"); `.gltf`/`.glb` aren't in the list either. `convert-model.ps1` reads `.gltf`/`.glb`/`.obj` itself and `.dae`/`.fbx` through Blender 4.5 (`setup.ps1 -Models`; Blender 5.0 removed the `.dae` importer). A stock model exported by Source2Viewer to `.glb`, converted, compiled and exported again lands exactly on the stock model (soul container), so the axis and inch conversions are right.
- **OBJ** works and is the easiest to write or fix with a script. `.mtl` files and `map_Kd` textures are **ignored**.
- **FBX** works (binary FBX from a real exporter). An FBX the importer can't read compiles **"OK" with an empty model** and no warning, so always check the output has a mesh.
- An FBX with LOD meshes imports them all, stacked. Keep one with `import_filter = { exclude_by_default = true exception_list = [ "<mesh name>" ] }` on the `RenderMeshFile`.

**Materials.** The mesh's material name becomes a vmat path:
- OBJ `usemtl foo` → `foo.vmat`; FBX material `Foo_Mat` → `foo_mat.vmat` (lowercased). The compile warns `referencing missing material 'foo.vmat'`.
- Fix it either way: write the full path in the mesh (`usemtl models/hideout/materials/my_skin.vmat` works), or remap in the vmdl:
  ```
  _class = "DefaultMaterialGroup"
  name = "default"
  remaps = [ { _class = "BaseMaterialRemap" from = "foo.vmat" to = "models/hideout/materials/my_skin.vmat" }, ]
  ```
- **Use NPR lighting.** A minimal `pbr.vfx` material (shader + `TextureColor1`) compiles but shows **near-black** in-game: Deadlock lights things through NPR lighting (soul container swap). This one looked right next to the stock props (same swap, in-game; constants in `[ ]` need no texture file):
  ```
  "Layer0"
  {
  	"shader"	"pbr.vfx"
  	"F_USE_NPR_LIGHTING"	"1"
  	"F_OVERRIDE_NPR_OUTLINE"	"1"
  	"F_USE_STATUS_EFFECTS_PROXY"	"1"
  	"g_flOverrideNprOutlineThickness"	"0.05"
  	"TextureMetalness1"	"[0.000000 0.000000 0.000000 0.000000]"
  	"TextureRoughness1"	"[0.700000 0.700000 0.700000 0.000000]"
  	"TextureColor1"	"models/hideout/materials/my_skin_color.png"
  }
  ```
  That is convert-model's default; it tested with a glow added (`F_SELF_ILLUM 1`, `g_flSelfIllumScale1 0.25`, `g_vSelfIllumTint1 [0.4 0.2 0.05 0]`, `TextureSelfIllumMask1 [1 1 1 0]`: convert-model `-Glow`). It produces `my_skin.vmat_c`, `my_skin_color_png_<8-hex>.vtex_c` (the hash stayed the same across recompiles) and one small `my_skin_vmat_g_t<name>_<hex>.vtex_c` per constant (ship them; build does). It also writes `materials/default/*_tga_*.vtex_c`, which the game has: `build.ps1` leaves them out.
- **Stock materials** set more: the soul container's has NPR lighting, outline, status-effects proxy and a pulsing self-illum (`DynamicParams`), and dozens of `g_*` values; NPC materials can also use translucency and jitter. `convert-model -Like <stock> -CopyStockMaterial` (opt-in; the default is the material above) copies a stock model's `F_*`, `g_*`, constant `Texture*` values and `DynamicParams`, drops its texture files, and keeps metalness and roughness constant (desk-only, compiles). Copy a texture-based setting by hand only with a texture you made.
- The compiled colour texture keeps **metalness in its alpha** when `TextureMetalness1` is set: stock `soul_container_color_png_*.vtex_c` has alpha 255 (its metalness map), ours 0 (constant `[0 0 0 0]`). So the png's own alpha is not used (no transparency), and a metalness map or flag without a constant could make the model read as metal. Decompiled, ours looks blank in an image viewer; its RGB is right (desk).
- Remaps whose `from` material is no longer in the mesh are dropped (an NPC's alternate skin group then changes nothing).

**Still meshes on an animated model.** An unskinned mesh (OBJ has no weights) compiles fine in place of the skinned one. It's rigid: no joints or weights. It should stay put at the model origin while the skeleton plays its idle. It shows in-game (a hideout NPC); whether it stays put while the idle plays, and whether the game still finds the sequences it calls by name, is **untested**. Moving parts need a mesh skinned to the stock bone names (FBX/DMX from Blender), which is the guided route.

**Scale and orientation.** 1 unit = 1 inch; a standing human is about 72 units.
- OBJ is read as **Y-up** and turned to Source Z-up: OBJ `(x, y, z)` → Source `(x, -z, y)`. A Z-up OBJ ends up lying down. Most downloaded OBJs are Y-up already.
- `RenderMeshFile` takes `import_scale = 2.0` (verified; scales the mesh only). There is **no import rotation**: rotate the vertices in the file with a script. `ModelModifier_ScaleAndMirror` (`model_scale`, `mirror_x/y/z`) exists but scales the whole model, skeleton included.
- FBX units vary by exporter: a Unity sample FBX came in at about 100× too big. Always check the bounds.

**Check before the user tests in-game** with `preview-model.ps1` (front and side wireframes over the stock model, bounds in inches, warnings). It works from Source2Viewer-CLI's glTF export, which you can also run yourself:

```powershell
Source2Viewer-CLI -i <mod>\<model>.vmdl_c -d --gltf_export_format gltf -o C:\work\check\m.gltf     # -d is required
```

- The export is in **metres, Y-up**: glTF `Y` = Source `Z` (height), glTF `X` = Source `X`. Read `accessors[...].min/max` of each mesh's `POSITION`. No `meshes` in the file means the import failed.
- Straight from a pak: `Source2Viewer-CLI -i <pak>_dir.vpk -f <game path>.vmdl_c -d --gltf_export_format gltf -o <folder>` writes `<folder>\<game path>.gltf` (plus `_physics.gltf`).
- `Source2Viewer-CLI -i <file>.vmdl_c -b RERL` lists the materials the model loads; `-d -o <file>.vmdl` decompiles it, to count bones and animations.

### 5. Hero skins (the user does GUI work)

A hero model swap (AnimGraph 2) can't be automated from the command line today:
1. Decompile with Source 2 Viewer ≥ 20.0.
2. Rig to the hero's own skeleton in Blender and export DMX.
3. Rebuild in CSDK 12 ModelDoc, after deleting the `AnimGraph2List`/`NmSkeletonList` blocks.
4. Do the final compile in **CS2 Workshop Tools**, adding the AnimGraph 2 and skeleton references. A skin re-released on 2026-10-20 was compiled this way (proven).

Copy the original's camera attachments, `CitadelUnitStatusSettings_t`, and the sound binding, which is **`TaggedSoundSettings_t` since 2026-10-16**. Guides that still say `CitadelTaggedSoundSettings_t` are outdated: the game no longer reads that name, and skins lose footsteps. Guide the user through DivineSkins' 4-part guide; you can write the text edits and check the result. Props and NPCs without AnimGraph 2 (the soul container has one bone and one material) use route 4.

## After a patch

- Patches move and rename assets constantly:
  - From build 6701 to 6796, about 17k sound paths were removed and 30k added.
  - 145 of about 150 soundevents files changed by build 6779.
  - The 2026-10-16 patch moved every hero's camera attachments.
- A replacement whose path vanished silently does nothing. For raw files, `rebase.ps1` can only report that the stock file changed. Re-list with `get-stock.ps1 -List`, move your files, and redo whole-file overrides (soundevents, materials) against the new stock.

## Fair play and publishing

- Keep sizes, brightness and loudness close to the original. Change no cameras or hitboxes.
- GameBanana's R-DL.824 lists these as unfair:
  - skins meant to increase visibility;
  - louder or extended sound effects on quiet abilities;
  - anything visible through veils or fog.

  Hit detection is very likely server-side, from "lag compensated hitboxes" strings in `client.dll` (an inference), so model edits change only what the player sees, which is why visibility is the line.
- GameBanana R-DL.847 forbids AI-generated textures, models, voice and music in submissions. That matters only if the user publishes there; it doesn't limit what they make for themselves.
