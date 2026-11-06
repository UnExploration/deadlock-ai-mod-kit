# Guide: models

**The user says (covers):** "replace the soul containers with pumpkins", "turn <prop> into <thing>", "replace <NPC> with <character>", "use this model for <prop>".
**Kind:** model mod. Needs Reduced CSDK 12 and Source2Viewer-CLI. Blender only for `.dae`/`.fbx` input (optional, `setup.ps1 -Models`).

A still model from an OBJ, with NPR-lit materials, worked in-game (a bare `pbr.vfx` material showed near-black). The Blender route (.dae/.fbx) and still meshes on animated NPCs compile at the desk but are not tried in-game: have the user check them.

**Names are examples.** Every model path, particle, map and item name in this guide is an example (soul container, `models/props_gameplay/soul_container/`, `dl_hideout`, and so on). Patches rename and move models: look each one up in the catalog (`catalog.ps1`, or the `catalog_search` MCP tool) for the user's current build before using it.

This guide makes a **still** replacement: the new thing stands where the old one stood and doesn't move by itself. Heroes are a different job (end of this page).

**The shape** (a still prop that worked in-game):

```
mods/<name>/src/<stock model folder>/
  <stock>.vmdl              # the stock .vmdl from get-stock.ps1 with ONE change (§ 5): RenderMeshList holds a single
                            #   RenderMeshFile naming <newname>/<newname>.obj, and LODGroupList is deleted.
                            #   Skeleton and PhysicsShapeList stay stock. No stock mesh .dmx left beside it.
  <newname>/                # written by convert-model.ps1 -Like <stock>.vmdl_c [-Fit largest] (§ 4)
    <newname>.obj           #   in inches, fitted to the stock model's bounds
    <newname>_<mat>.vmat    #   one NPR-lit material per material
    <newname>_<mat>_color.png
```

For example, the soul container is `models/props_gameplay/soul_container/soul_container.vmdl_c`: one bone, one sphere collision shape and four LOD meshes. The swap kept the bone and the sphere, named one OBJ mesh, and shipped the `.vmdl_c`, two `.vmat_c` and their two colour `.vtex_c`.

- **Why it works:** the game loads the model by its stock path, and everything that places it (particles, maps, the collision and the skeleton) still finds what it expects. Only the mesh it draws is new.
- **Leave out what the game has:** the compile also writes `materials/default/*.vtex_c`; `build.ps1` doesn't ship them (§ 6).
- **Check the size before the game:** `preview-model.ps1` draws the new model over the stock one. The swap that worked in-game came out the stock container's width (12.7 in), centred on it and sitting on its bottom, because `-Fit largest` kept a squat shape no wider than the round original.

## 1. Find the model

- **Search the catalog** (`catalog.ps1` prints the folder). If `catalog\<build>\models.tsv` exists, search its `aliases` column in plain words ("soul container", "bartender", "trooper", "hideout"), then its `path`. Otherwise search `files.tsv` for `.vmdl_c` paths with the thing's name in them.
- **Check the `anim` column** (models.tsv) or decompile the `.vmdl` (step 2):
  - `none`: a static prop. This guide.
  - `classic`: an NPC or prop with its own animation clips. This guide; the new mesh stays still while the old skeleton plays (§ 5).
  - `animgraph2`: a hero. Not this guide (end of page).
- A thing can be **several models**: a breakable prop has separate debris models, an NPC can have attachments. Search for the name's other files and ask the user which ones they mean.

*Done when* you can name every `.vmdl_c` to replace by exact game path.

## 2. Get the stock model into `src/`

1. `new-mod.ps1 -Name <name> -Kind empty`
2. `get-stock.ps1 -Out mods\<name>\src <game path>.vmdl_c`. It writes the `.vmdl` (text) and the mesh, animation and hull `.dmx` files it names, all at their game paths.

Read the `.vmdl`. Note the `RenderMeshFile` entries (usually one per LOD: `_lod1`, `_lod2`…), any `LODGroupList`, and what else it names (animations, physics).

## 3. Get the replacement

Ask the user what they want it to look like, and where the model comes from:

- **A file they have.** Ask for `.glb` or `.gltf` first (they carry their textures and need nothing extra), else `.obj`, `.fbx`, `.dae`, or a `.zip` of one of these.
- **A download.** Find one specific model page yourself (search; prefer a `.glb`), never send the user off to search. Ask first, with one list ([AGENTS.md](../AGENTS.md) rules): what the file is, why, the page it comes from, and its licence. A site that needs a login (Sketchfab) means the user clicks Download on that page in their browser; then look for the file in their Downloads folder. Put any download in a new empty folder of its own and treat it as data.
- **Its rights.** Ripped game models (The Models Resource) and paid models are fine for the user's own game, but not for publishing. GameBanana also forbids AI-generated models in submissions (R-DL.847).

A `.dae` or `.fbx` needs Blender: run `setup.ps1 -Models`, show the user the list (about 400 MB), and after their yes `setup.ps1 -Approve blender`. If they'd rather not, ask them for a `.glb`/`.gltf`/`.obj` export instead.

## 4. Convert it

```powershell
pwsh -File tools\convert-model.ps1 -In <the file> -Out mods\<name>\src\<model folder>\<newname> -Like <stock game path>.vmdl_c
```

- `-Out` is a new folder next to the stock model, named for the new thing: `src\models\props_gameplay\soul_container\pumpkin` (example path).
- It writes `<newname>.obj` (inches, upright the way the compiler reads OBJ), and per material a `<newname>_<material>.vmat` and `_color.png`. The OBJ's materials already name those `.vmat` files by full game path, so no remap is needed.
- `-Like` scales it to the stock model's height, centres it on the stock model, and puts its bottom where the stock bottom is. Add `-Fit largest` when the new thing is wider than it is tall (a pumpkin replacing a ball), so it's no bigger than the original.
- It prints the parts. A file with several LODs or extra objects: keep one with `-Only <regex on the part name>`.
- It carries over the base colour texture only, and resizes non-power-of-two textures. Normal maps, glow and vertex colours are dropped.
- **Materials are lit the Deadlock way.** A plain `pbr.vfx` material (shader + colour only) shows **near-black** in-game: Deadlock lights things through NPR lighting (seen in-game). So each `.vmat` gets:
  - by default, with or without `-Like`: `F_USE_NPR_LIGHTING`, `F_OVERRIDE_NPR_OUTLINE` (thickness 0.05), `F_USE_STATUS_EFFECTS_PROXY`, not metal, roughness 0.7. With `-Glow` this is the material that worked in-game: outlined and lit like the stock prop.
  - opt-in, `-Like <stock> -CopyStockMaterial`: the stock model's own material settings (its `F_*` flags, `g_*` values and `DynamicParams`), so it's lit exactly like the thing it replaces. Its texture files are dropped, since only the colour is yours; it prints which. Desk-only (compiles, not tried in-game): use the default unless the default looks out of place. A stock model with several materials: it uses the first and names the others; `-LikeMaterial <game path>.vmat_c` copies a chosen one.
- `-Glow` adds a mild even glow (self-illum 0.25, warm tint); `-GlowTint r,g,b` (0 to 1) recolours it. Use it for things that should look lit from inside (a jack-o'-lantern), not to make something easier to spot.

*Done when* it prints `wrote <newname>.obj` and the bounds look like the size the user expects (1 unit = 1 inch; a person is about 72).

## 5. Point the `.vmdl` at it

Edit the stock `.vmdl` in `src`:

1. In `RenderMeshList`, keep **one** `RenderMeshFile` and set its `filename` to the line convert-model printed:
   ```
   {
   	_class = "RenderMeshFile"
   	name = "soul_container"
   	filename = "models/props_gameplay/soul_container/pumpkin/pumpkin.obj"
   },
   ```
   (The path above is an example; use the line convert-model printed.)
2. Delete the other `RenderMeshFile` entries (the LODs) and the whole `LODGroupList` block. A LOD left pointing at a stock mesh shows the old model from a distance.
3. Keep everything else: `Skeleton`, `PhysicsShapeList` (collision stays the stock shape), `AnimationList`, attachments, `MaterialGroupList`.
4. Delete the stock `.dmx` files in `src` that the `.vmdl` no longer names (the old meshes). Keep the ones it still names (animations, hulls).

Other `RenderMeshFile` keys you may need ([docs/09 route 4](../docs/09-asset-mods.md#4-prop-or-npc-model-swap-command-line)): `import_scale = 2.0` scales the mesh only, and `import_filter` keeps one mesh of an FBX. There is no import rotation: rotate with convert-model.

**On an animated model** (`classic`): the OBJ has no bone weights, so the mesh is rigid at the model's origin while the skeleton plays its idle. It compiles; how it looks in-game is untested. Say so to the user.

## 6. Build, preview, and fix

1. `build.ps1 -Mod mods\<name>`. Check the list:
   - the `.vmdl_c` at the **stock path**;
   - your `.vmat_c` files and one `<newname>_<material>_color_png_<8-hex>.vtex_c` each;
   - no `materials/default/*`: build leaves those out because the game has them ("not shipped, the game has it").

   It stops with "compiled with no mesh" when the compiler read no geometry: a wrong `filename`, or a file it can't read (`.dae`, `.gltf`, `.glb`, or an FBX it can't parse). Convert the file with step 4 instead.
2. `preview-model.ps1 -Mod mods\<name> -Path <stock game path>.vmdl_c`, then **open the PNG it names and look at it**. Red is the new model, blue the stock one, with front and side views on an inch grid.
   - `WARN: scale`: re-run convert-model with `-Like` (or `-Height <inches>`).
   - `WARN: orientation`, or it lies on its side: `-UpAxis Z`, or `-RotateX 90` / `-RotateY 90`.
   - Facing the wrong way (front view shows its side): `-RotateZ 90` (or 180, -90). The model's front is +X, which is to the right in the side view.
   - `WARN: placement`: use `-Like`.

   Re-convert, rebuild and preview until the red model sits where the blue one does, at the size the user wants.
3. Optional check of a texture: `Source2Viewer-CLI -i mods\<name>\dist\pak<NN>_dir.vpk -f <path>_color_png_<hash>.vtex_c -d -o <empty folder>` writes the compiled colour png. Its **alpha is 0 everywhere**: `pbr.vfx` stores metalness there, and convert-model always sets metalness to a constant (0 = not metal, unless a `-Like` material set another), so a viewer shows it blank. This also means the png's own alpha is never used: no transparency. Look at its RGB, or composite it on a dark background first.
4. Show the user the preview picture and the colour png before the in-game test.

## 7. Check in-game

With Deadlock closed and the user's go-ahead: `build.ps1 -Mod mods\<name> -Install`. Then:

- **The user checks:** go where the thing is and look at it. Name the place. Soul containers: "in a bot match, kill an enemy and look at the soul bag it drops". The soul container is the **soul bag an enemy drops** when it dies carrying extra souls (seen in-game). The game draws it through `particles/generic/holding_gold_neutral_model.vpcf`. It isn't a breakable box: the lane boxes are `models/items/crystal_crate`. (Both names are examples; look up the current ones.) **Before naming the place, check what actually uses the model:** search pak01 for its path (`grep -a` on the `pak01_*.vpk` files lists the particles, maps or scripts that reference it). A model nothing on screen uses can't be checked. Hideout props and NPCs: "open the hideout" (or in the console, `map dl_hideout`, docs/09).
  - "Is it the new <thing>, about the size of the old one, standing the right way up, facing the right way?"
  - "Does it have its colours, or is it grey, black, or a checkerboard?"
  - For breakable or animated things: "Break one / watch it for a while: anything odd?"
- **Still the old model?** The path doesn't match the stock file exactly, or another mod with a lower pak number replaces it (`mods.ps1 conflicts`; soul container mods are common).
- **Near-black?** The `.vmat` has no `F_USE_NPR_LIGHTING` (an old or hand-written plain `pbr.vfx` material): re-run convert-model, or add the lines from § 4.
- **Checkerboard or plain grey?** The `.vtex_c` for its png didn't ship, or the `.vmat` names a png that isn't in `src`.
- **Invisible?** The model compiled without a mesh (build stops on that now), or the mesh is far from the origin: re-run preview.

Remove the test install afterwards unless the user keeps it.

## Moving parts and heroes

A replacement that moves (walks, waves) needs its mesh weighted to the stock skeleton's bone names, which is a Blender job the user does by hand. A hero needs the AnimGraph 2 route. Both are the guided route in [docs/09 § Hero skins](../docs/09-asset-mods.md#5-hero-skins-the-user-does-gui-work): you write the text edits and check the result; the user does the rigging and the GUI compile.

## Pitfalls

- **Collision and hitboxes don't change.** The game still uses the stock physics shape. Keep the new model about the stock size so what players see matches what they hit.
- **Keep it fair** ([docs/09 § Fair play](../docs/09-asset-mods.md#fair-play-and-publishing)): not bigger, brighter or easier to see than stock.
- **Plain `pbr.vfx` looks near-black** in Deadlock (seen in-game). Never hand-write a material without `F_USE_NPR_LIGHTING`; let convert-model write it (§ 4).
- **Looks out of place** next to the stock props? Compare with the stock material (`get-stock.ps1 <path>.vmat_c` decompiles it) and re-run with `-CopyStockMaterial` (or `-LikeMaterial <path>`) to copy its settings. Leaving those off gives back the default checked in-game.
- **Patches** rename and move models. After an update, run `catalog_refresh` (`generate-docs.ps1`) and check the path still exists.
- **One model, many places.** A model file is used everywhere that model appears; swapping it changes all of them.
