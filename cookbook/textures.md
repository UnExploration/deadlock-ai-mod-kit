# Guide: images and textures

**The user says (covers):** "replace this icon with X", "put my picture on <item/ability> effect", "change the shop icon of <item>", "make <hero>'s <part> blue".
**Kind:** texture mod. Needs Reduced CSDK 12 and Source2Viewer-CLI.

Particle icons, still and animated (§ 4, flipbook), worked in-game. Model-texture recolors and shop/HUD icons compile at the desk but are not tried in-game: have the user check them.

**Names are examples.** Every game path, codename, hash and file size in this guide is an example. Hash-named textures and paths change with patches: look each one up in the catalog (`catalog.ps1`, or the `catalog_search` MCP tool) for the user's current build before using it.

Every texture swap is the same move: get the stock texture as a `.vtex` (compile settings) plus a png, put a new png of the **same size** in its place, and let `build.ps1` compile it back to the **same game path**.

| What the user sees | Game files (path patterns, examples) | Notes |
|---|---|---|
| Symbol floating over a hero (item/ability effects) | `materials/particle/**/<name>.vtex_c` | Usually white or grey, tinted by the particle (§ 3) |
| Item/ability icon in the shop and HUD | `panorama/images/**/<name>_psd.vtex_c` (items: `panorama/images/items/<category>/`, mods: `panorama/images/upgrades/`) | § 2 |
| Hero, weapon or prop colours | `models/**/materials/*_color_png_<8-hex>.vtex_c` | Hash-named; § 2 |

The symbol over the hero and the shop icon of the same item are **different files**: swapping one leaves the other as it was.

**The shape** (a particle icon that worked in-game):

```
mods/<name>/
  mod.json                  # kind empty: no copies, no overrides
  src/<stock path>.vtex     # the stock compile settings from get-stock.ps1 -Source s2v, UNCHANGED;
                            #   its m_fileName names the png beside it
  src/<stock path>.png      # your image: the stock png's width and height, 32-bit with alpha
                            # e.g. src/materials/particle/upgrades/healing_rite_symbol.png, 256×256 (example)
```

- **Why it works:** `build.ps1` compiles the pair with Reduced CSDK 12 to `<stock path>.vtex_c`. The untouched `.vtex` keeps the stock format, colour space and mip settings, so the game reads your file exactly as it read the original.
- **The proof it matched:** the compiled file is within about 1% of the stock file's size (§ 5). Same size and format in, same size out.

## 1. Find the files

- **By name, in `files.tsv`** (`catalog.ps1` prints the folder). Search for the item's or hero's **codename**, which often differs from its display name: Healing Rite is `upgrade_health_stimpak`, so its files are `stimpak_*` and `healing_rite_*` (example; look the codename up for the current build). Item codenames are in the game's own `game\citadel\resource\localization\citadel_gc_mod_names\citadel_gc_mod_names_english.txt` (read it, don't change it); hero codenames are in `heroes.tsv`.
- **From the particle to its textures:** `get-stock.ps1 -Out <tmp> particles/<path>.vpcf_c`, then search the `.vpcf` for `m_hTexture`. A particle often uses several textures (noise, glow); the icon is the one named like the item or ability. **Go by what the particle names, not by a file name that looks right:** Healing Rite's particles draw `healing_rite_symbol.vtex`, and the similarly named `stimpak_icon.vtex_c` (a syringe) is used by neither of them.
- **Model textures:** `models.tsv` in the catalog lists every model with plain-word aliases ("soul container", "the oracle"), its materials and the textures they use. Search it by what the user calls the thing, or by a texture name to find which models use it.
- **From a texture to the particles that use it:** the catalog doesn't cover particles. Decompile the particles named like the item and search each for the texture.
- **In-game:** in a local map, `sv_cheats 1; dumpparticlelist` after using the ability lists the particles playing ([docs/09](../docs/09-asset-mods.md#what-to-replace)). Only offer this when the files don't make it obvious; it needs the user at the console.

*Done when* you can name each `.vtex_c` to replace by exact game path, and you've looked at its stock png and agree with the user that it's the one they mean.

## 2. Get the stock texture into `src/`

1. `new-mod.ps1 -Name <name> -Kind empty`
2. `get-stock.ps1 -Out mods\<name>\src -Source s2v <game path>.vtex_c` (add `-AllowBuildMismatch` if it refuses). 

`get-stock.ps1` always writes a pair: `<name>.vtex` (compile settings) and `<name>.png`, with the `.vtex`'s `m_fileName` naming the png. Textures the game compiled straight from an image (shop/HUD icons, hash-named model textures) have no stock `.vtex`, so get-stock writes one with the stock format, colour space and mip settings read from the stock file. Leave the `.vtex` as it is and overwrite the png (§ 4). Note its width, height, and whether it has transparency.

- **Hash-named model textures** (example: `archer_bow_color_png_b68c2251.vtex_c`; the hash changes with the file): the compiled file takes the `.vtex`'s name, so **keep the hash in both names**; a different name is a new file nothing loads. Recolor only colour maps (`_color_`); normal, roughness and mask maps hold data, not colour.
- **Shop and HUD icons** (`*_psd.vtex_c`): keep the `_psd` name. They're odd sizes like 200×200, so their `.vtex` has mips set to `None`; don't change it, because mipmaps fail with "This game does not have non-power-of-two texture support enabled!".
- **HDR textures** come out as `.exr` instead of `.png`. Edit them only if you have a tool that writes EXR.

These compiled back to their stock paths at the desk (a 200×200 item icon, a particle icon, a 4096² model colour map); none is tried in-game yet.

## 3. Grey sprite or coloured? Check the tint

Many particle icons are white or grey on transparent, and the particle colours them. Example (look up the current files): Healing Rite's hand is pure white; its particle `particles/upgrades/stimpak_heal_buff_icon.vpcf` has `m_ConstantColor = [ 31, 238, 138, 255 ]`, so it shows green. In the decompiled `.vpcf`, look for `m_ConstantColor`, `C_OP_ColorInterpolate` or `m_LiteralColor`.

- **Stock png white/grey and the particle sets a colour:** make the new image white/grey too (`$grey = $true` below). It shows in the game's colour; a coloured image gets multiplied by the tint and turns muddy.
- **Stock png already coloured:** keep yours coloured.

Tell the user which case it is, in their terms: "the game paints this symbol green, so your picture will show as a green silhouette."

## 4. Make the image

Match the stock png: **same width and height, transparent background, similar amount of drawn area**. The png must be 32-bit with alpha. Where the image comes from:

- **A file the user gives you.** Fit it with the snippet below.
- **A download.** Ask first, saying what and from where ([AGENTS.md](../AGENTS.md) rules). Prefer images the user has the right to use.
- **You draw it.** System.Drawing in PowerShell draws shapes, text and paths with transparency ([draw a shape](#draw-a-shape) below). An SVG needs a rasteriser already on the PC (for example headless Edge or Chrome with a transparent background; untested here).

**Fit an image into the stock size**, centred, with transparent padding. Works in Windows PowerShell 5.1 and PowerShell 7. Use full paths: .NET doesn't follow PowerShell's current folder.

```powershell
$in     = 'C:\full\path\to\users-picture.png'                    # any png/jpg; transparency is kept
$stock  = 'C:\full\path\to\mods\<name>\src\<game path>.png'      # the stock png from step 2
$out    = $stock                                                 # overwrite it in place
$margin = 0.08                                                   # empty border, as a share of each side
$grey   = $false                                                 # $true for tinted sprites (step 3)

Add-Type -AssemblyName System.Drawing
$ref = [Drawing.Image]::FromFile($stock); $size = $ref.Size; $ref.Dispose()
$img = [Drawing.Image]::FromFile($in)
$scale = [Math]::Min($size.Width * (1 - 2 * $margin) / $img.Width, $size.Height * (1 - 2 * $margin) / $img.Height)
$fitW = [int]($img.Width * $scale); $fitH = [int]($img.Height * $scale)
$bmp = New-Object Drawing.Bitmap $size.Width, $size.Height, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.Clear([Drawing.Color]::Transparent)
$g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
$attr = New-Object Drawing.Imaging.ImageAttributes
if ($grey) {   # brightness into R=G=B, alpha untouched: the particle's colour then tints it
  $m = New-Object Drawing.Imaging.ColorMatrix
  foreach ($row in 0..2) { foreach ($col in 0..2) { $m[$row, $col] = @(0.299, 0.587, 0.114)[$row] } }
  $attr.SetColorMatrix($m)
}
$dest = New-Object Drawing.Rectangle ([int](($size.Width - $fitW) / 2)), ([int](($size.Height - $fitH) / 2)), $fitW, $fitH
$g.DrawImage($img, $dest, 0, 0, $img.Width, $img.Height, [Drawing.GraphicsUnit]::Pixel, $attr)
$img.Dispose()
$bmp.Save($out, [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
```

A photo with a solid background stays a solid square: cut the subject out first, or use a picture with transparency. In greyscale, dark colours come out dim; a light picture tints best.

### Draw a shape

When the user wants something simple drawn (a heart, a ring, a letter), System.Drawing writes a transparent png with no download and no one else's art. This draws a white heart with a plus, the image that worked in-game over a tinted particle; the coordinates are for 256×256, so scale them to the stock size.

```powershell
$out = 'C:\full\path\to\mods\<name>\src\<game path>.png'       # overwrite the stock png; full path
Add-Type -AssemblyName System.Drawing
$bmp = New-Object Drawing.Bitmap 256, 256, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)   # the stock png's size
$g = [Drawing.Graphics]::FromImage($bmp); $g.Clear([Drawing.Color]::Transparent); $g.SmoothingMode = 'AntiAlias'
$heart = New-Object Drawing.Drawing2D.GraphicsPath                # four Bezier curves, notch at the top, point at the bottom
$heart.AddBezier(128, 78, 100, 20, 22, 40, 34, 112); $heart.AddBezier(34, 112, 44, 160, 100, 196, 128, 228)
$heart.AddBezier(128, 228, 156, 196, 212, 160, 222, 112); $heart.AddBezier(222, 112, 234, 40, 156, 20, 128, 78)
$g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(110, 255, 255, 255))), $heart)   # half-transparent fill
$pen = New-Object Drawing.Pen ([Drawing.Color]::White), 7; $pen.LineJoin = 'Round'; $g.DrawPath($pen, $heart)   # outline
$plus = New-Object Drawing.Pen ([Drawing.Color]::White), 14; $plus.StartCap = 'Round'; $plus.EndCap = 'Round'
$g.DrawLine($plus, 128, 108, 128, 176); $g.DrawLine($plus, 94, 142, 162, 142)                         # the plus
$bmp.Save($out, [Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
```

White, because that particle tints its icon (§ 3); use colours only for an untinted one. Other shapes: `FillEllipse`, `DrawString` (text), `AddPolygon`. Keep the drawn area close to the stock image's: this heart covers a little less than the stock hand did, which read as the same size in-game.

**Recolor a model texture** (§ 2) by rotating its hue. Don't redraw it with the snippet above: model textures often store a mask in alpha, with colour under fully transparent pixels, and drawing throws that colour away. This edits the colour bytes in place and never touches alpha. It takes about 15–25 s for 1024×1024.

```powershell
$png = 'C:\full\path\to\mods\<name>\src\<game path>_png_<hash>.png'
$deg = 120                                                       # hue shift in degrees: 120 turns green to blue

Add-Type -AssemblyName System.Drawing
$bmp = [Drawing.Bitmap]::new([IO.MemoryStream]::new([IO.File]::ReadAllBytes($png)))   # no file lock: saves back in place
$rect = [Drawing.Rectangle]::new(0, 0, $bmp.Width, $bmp.Height)
$data = $bmp.LockBits($rect, 'ReadWrite', [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$px = [byte[]]::new($data.Stride * $bmp.Height)
[Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $px.Length)
$c = [Math]::Cos($deg * [Math]::PI / 180); $s = [Math]::Sin($deg * [Math]::PI / 180)
$m = @(                                     # hue rotation, the same matrix as SVG feColorMatrix hueRotate
  (0.213 + $c * 0.787 - $s * 0.213), (0.715 - $c * 0.715 - $s * 0.715), (0.072 - $c * 0.072 + $s * 0.928),
  (0.213 - $c * 0.213 + $s * 0.143), (0.715 + $c * 0.285 + $s * 0.140), (0.072 - $c * 0.072 - $s * 0.283),
  (0.213 - $c * 0.213 - $s * 0.787), (0.715 - $c * 0.715 + $s * 0.715), (0.072 + $c * 0.928 + $s * 0.072))
for ($i = 0; $i -lt $px.Length; $i += 4) {  # bytes are B, G, R, A. Alpha is never touched
  $b = $px[$i]; $g = $px[$i + 1]; $r = $px[$i + 2]
  $px[$i + 2] = [Math]::Min(255, [Math]::Max(0, [int]($m[0] * $r + $m[1] * $g + $m[2] * $b)))
  $px[$i + 1] = [Math]::Min(255, [Math]::Max(0, [int]($m[3] * $r + $m[4] * $g + $m[5] * $b)))
  $px[$i]     = [Math]::Min(255, [Math]::Max(0, [int]($m[6] * $r + $m[7] * $g + $m[8] * $b)))
}
[Runtime.InteropServices.Marshal]::Copy($px, 0, $data.Scan0, $px.Length)
$bmp.UnlockBits($data)
$bmp.Save($png, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
```

Show the user the result before building. Read the png yourself, or composite it onto a dark background first: white-on-transparent looks blank in most viewers.

### Animated particle icon (flipbook)

"Make it spin", "use this GIF": a particle sprite can play frames, like a flipbook (worked in-game: a 35-frame spinning sprite over the hero).

1. **Frames:** `ffmpeg -i <in.gif> -vsync 0 <frames dir>\f%02d.png` (frames from a GIF keep its transparency). Fit every frame the same way, square and with transparent padding: use the drawn area common to all frames as the crop, so the object turns in place instead of jumping. A sprite is drawn square, so a tall frame gets squashed unless you pad it. 128×128 per frame is plenty for a small icon. Apply the grey step (§ 3) here if the particle tints.
2. **Frame list:** next to the `.vtex`, write `<name>.mks`, with the frames' file names relative to it:
   ```
   sequence 0
   LOOP
   frame frame_00.png 1
   frame frame_01.png 1
   ```
   In the `.vtex`, set `m_fileName` to the `.mks` instead of the png. The compiler packs the frames into one atlas with sequence data (35 frames of 128² became a 1024×512 texture). Stock sheets work the same way: `get-stock.ps1` on `materials/particle/numbers/numbers.vtex_c` (example path) writes an `.mks` and its pngs.
3. **Make the particle play it:** `get-stock.ps1` the `.vpcf` that names the texture, and in its `C_OP_RenderSprites` block for that texture add:
   ```
   m_nAnimationType = "ANIMATION_TYPE_FIXED_RATE"
   m_flAnimationRate = 16.67
   m_bAnimateInFPS = true
   ```
   The rate is frames per second (a GIF's rate is in `ffprobe`'s `r_frame_rate`). Put the `.vpcf` in `src/` at its stock path.
4. **How long it stays on screen** is the particle's lifetime: the `C_INIT_InitFloat` with `m_nOutputField = 1`. Fades and scale curves in stock icons usually run on `PF_TYPE_PARTICLE_AGE_NORMALIZED`, so a longer lifetime stretches them evenly (1.2 s → 2.1 s looked right in-game). Matching the lifetime to one full loop of the frames reads well.
5. Check after building: decompile the `.vtex_c` (§ 5.2). It must write back an `.mks` with your frame count. `build.ps1` reads the `.mks`, so the frame pngs don't trigger its "Image not compiled" warning; one that does isn't listed in the `.mks`.

## 5. Build and check the output

1. `build.ps1 -Mod mods\<name>`. It must list `<game path>.vtex_c` at the **stock path**, with the stock name (hash included).
   - Its size should be within about 1% of the stock file's `bytes` in `files.tsv` (example: 89,508 vs 89,632 for a 256×256 icon). Far off means a different size or format.
   - An older `build.ps1` warns "Image not compiled, so not shipped" for a png that a `.vtex` names. That warning is false; the `.vtex_c` in the list is what ships.
2. Decompile what you built into an empty folder that already exists, and look at the png it writes:
   `Source2Viewer-CLI.exe -i mods\<name>\dist\pak<NN>_dir.vpk -f <game path>.vtex_c -o <empty folder> -d`
3. With Deadlock closed and the user's go-ahead: `build.ps1 -Mod mods\<name> -Install`.

## 6. Check in-game

- **The user checks:** "In the sandbox or a bot match, <do the thing that shows it>. Do you see <the new image>, about the same size as before, in <colour>?" For a particle icon, name the action: "buy Healing Rite and use it on yourself; look above your hero" (example item).
- **Still the old image?** The path or hashed name doesn't match the stock file exactly, or another mod with a lower pak number replaces it (`mods.ps1 conflicts`).
- **Checkerboard or black square?** The compile went wrong. Decompile the built file (step 5.2) and compare its size and format with the stock one.
- **Wrong colour?** The particle tints it (§ 3).

## Pitfalls

- **Keep it fair:** same size and about the same brightness and drawn area as the stock image. Nothing that makes enemies, abilities or effects easier to see than stock ([docs/09 § Fair play](../docs/09-asset-mods.md#fair-play-and-publishing)).
- **Publishing:** GameBanana forbids AI-generated textures (R-DL.847). An image you drew for the user counts. For a mod they'll upload, they should supply the picture themselves.
- Patches rename and rehash textures. After an update, run `catalog_refresh` (`generate-docs.ps1`) and check that each path still exists in `files.tsv`, hash included.
- A texture is shared by every particle, material or panel that names it. Swapping it changes all of them; say so when the decompiles show more than one user.
