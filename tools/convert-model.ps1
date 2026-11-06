#Requires -Version 7

<#
.SYNOPSIS
  Turn a downloaded or user-supplied 3D model into what a Deadlock model swap compiles from: an OBJ in
  inches, standing up the way resourcecompiler reads it, plus one .vmat and one colour .png per material
  (cookbook/models.md).

.DESCRIPTION
  -In: a .gltf, .glb or .obj (read built in, nothing to install), or a .dae, .fbx, .blend, .ply or .stl
  (read through Blender, an optional tool: setup.ps1 -Models). A .zip is unpacked into a temporary folder
  first; it must hold one model file (or name it with -Pick).

  -Out: the folder to write into, normally inside the mod's src at a game path, e.g.
  mods\<mod>\src\models\props_gameplay\soul_container\pumpkin. The game path of that folder is read from
  the part after \src\ (or pass -GameDir). Writes, with <n> = -Name (default: the file name):
    <n>.obj                   Y up, inches; each material's usemtl is the full game path of its .vmat
    <n>_<material>.vmat       pbr.vfx with NPR lighting (see Materials), TextureColor1 = the png below
    <n>_<material>_color.png  the material's base colour texture (a power-of-two size: resized if needed),
                              or a small flat-colour png when it has none
  Then prints the parts, materials, bounds in inches and the RenderMeshFile line for the .vmdl.

  Fitting it to the model it replaces:
    -Like <stock game path or file>  scale to the stock model's height, centre it on the stock model and put
                                     its bottom at the stock model's bottom (Source2Viewer-CLI reads the stock model).
                                     -Fit largest: match the largest side instead (a wide thing replacing a round one)
    -Height <inches>                 scale to this height instead (1 unit = 1 inch; a person is ~72)
    -Scale <factor>                  multiply first (e.g. 0.01 for a model made in centimetres)
    -UpAxis Z                        the file was made Z-up (common for OBJ from 3ds Max or Source tools):
                                     stand it up. glTF is always Y-up; Blender handles .dae/.fbx axes itself
    -RotateX/-RotateY/-RotateZ <deg> turn it about Source's axes afterwards (Z = up; RotateZ turns it to face another way)
    -Only <regex>                    keep only mesh parts whose name matches (drop LODs, collision, extras)
  Check the result with preview-model.ps1 before building.

  Materials. Deadlock lights things through NPR lighting: a plain pbr.vfx material shows near-black in-game
  (build 6821, 2026-10-27). Each .vmat gets, by default (with or without -Like), the material checked in-game
  (6821): F_USE_NPR_LIGHTING, F_OVERRIDE_NPR_OUTLINE (thickness 0.05), F_USE_STATUS_EFFECTS_PROXY, not
  metal, roughness 0.7. Opt-in, not yet seen in-game:
    -Like <stock model> -CopyStockMaterial   copy the stock model's own material settings, so it is lit like
                                     the original: its F_* flags, g_* values, constant Texture* values and
                                     DynamicParams. Its texture files are dropped (only the colour is yours);
                                     metalness and roughness become constants, and a glow masked by a texture is
                                     switched off. The first material the stock model names is used; it says if
                                     there are more.
    -LikeMaterial <game path, .vmat or .vmat_c>  copy this material's settings (implies -CopyStockMaterial;
                                     'default' = the default material)
    -Glow                            a mild, even glow over the whole model: self-illum 0.25, warm tint
                                     0.4,0.2,0.05 (the settings seen in-game, 6821). -GlowTint r,g,b (0..1) recolours it
  Metalness is always a constant (0 unless the stock material set another): pbr.vfx packs metalness into
  the colour texture's alpha, so the png's alpha is not used (no transparency).

  Textures other than base colour (normal, roughness, emissive) and vertex colours are not carried over
  from the file.
  Animation and bones are dropped: the result is a still mesh.

.EXAMPLE
  pwsh -File convert-model.ps1 -In C:\Users\me\Downloads\pumpkin.glb -Out mods\pumpkin\src\models\props_gameplay\soul_container\pumpkin -Like models/props_gameplay/soul_container/soul_container.vmdl_c
  pwsh -File convert-model.ps1 -In C:\work\lantern.glb -Out mods\l\src\models\hideout\lantern -Height 30 -Glow -GlowTint 0.5,0.4,0.1
  pwsh -File convert-model.ps1 -In C:\work\statue.zip -Out mods\x\src\models\hideout\statue -Height 80 -Only 'LOD0'
#>
param(
  [Parameter(Mandatory)] [string]$In,
  [Parameter(Mandatory)] [string]$Out,
  [ValidatePattern('^[a-z0-9_]+$')] [string]$Name,
  [string]$GameDir,
  [string]$Like,
  [string]$LikeMaterial,
  [switch]$CopyStockMaterial,
  [switch]$Glow,
  [ValidateCount(3, 3)] [ValidateRange(0, 1)] [double[]]$GlowTint,
  [double]$Height,
  [ValidateSet('height', 'largest')] [string]$Fit = 'height',
  [double]$Scale = 1.0,
  [ValidateSet('Y', 'Z')] [string]$UpAxis = 'Y',
  [double]$RotateX, [double]$RotateY, [double]$RotateZ,
  [string]$Only,
  [string]$Pick,
  [ValidateSet('auto', 'builtin', 'blender')] [string]$Via = 'auto',
  [ValidateRange(64, 4096)] [int]$MaxTexture = 2048,
  [string]$Deadlock
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')
. (Join-Path $PSScriptRoot 'mesh.ps1')
Add-Type -AssemblyName System.Drawing

$work = Join-Path ([IO.Path]::GetTempPath()) ("dlconvert_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
$builtin = @('.gltf', '.glb', '.obj')
$viaBlender = @('.dae', '.fbx', '.blend', '.ply', '.stl')

# Blender, headless: import anything it reads, export glTF (Y up, metres) for the built-in reader.
$blenderScript = @'
import bpy, sys, os
argv = sys.argv[sys.argv.index('--') + 1:]
src, dst = argv[0], argv[1]
def fail(msg):
    print('CONVERT-ERROR: ' + msg); sys.exit(3)
bpy.ops.wm.read_factory_settings(use_empty=True)
ext = os.path.splitext(src)[1].lower()
if ext == '.dae':
    if not hasattr(bpy.ops.wm, 'collada_import'):
        fail('This Blender (%s) has no COLLADA (.dae) importer: Blender 5.0 removed it. Use Blender 4.5 LTS (setup.ps1 -Models installs it).' % bpy.app.version_string)
    bpy.ops.wm.collada_import(filepath=src, import_units=True)
elif ext == '.fbx':
    bpy.ops.import_scene.fbx(filepath=src)
elif ext in ('.gltf', '.glb'):
    bpy.ops.import_scene.gltf(filepath=src)
elif ext == '.obj':
    bpy.ops.wm.obj_import(filepath=src)
elif ext == '.ply':
    bpy.ops.wm.ply_import(filepath=src)
elif ext == '.stl':
    bpy.ops.wm.stl_import(filepath=src)
elif ext == '.blend':
    bpy.ops.wm.open_mainfile(filepath=src)
else:
    fail('Blender route does not read ' + ext)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
if not meshes:
    fail('the file has no mesh objects')
for img in bpy.data.images:
    if img.source == 'FILE' and img.packed_file is None and not os.path.exists(bpy.path.abspath(img.filepath)):
        print('CONVERT-NOTE: texture not found: ' + img.filepath)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLTF_SEPARATE', export_apply=True, export_animations=False,
                          export_skins=False, export_morph=False, export_cameras=False, export_lights=False)
print('CONVERT-OK %d mesh object(s)' % len(meshes))
'@

function ConvertTo-Slug([string]$s) {
  $s = ($s.ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_')
  if (-not $s) { 'mat' } else { $s }
}
function Save-ColorPng([byte[]]$Image, [double[]]$Color, [string]$Path, [int]$Max) {
  if ($Image) {
    $src = [Drawing.Bitmap]::new([IO.MemoryStream]::new($Image))
    $pot = { param($n) $p = 1; while ($p * 2 -le [Math]::Min($n, $Max)) { $p *= 2 }; if ($p -lt $n -and $p * 2 -le $Max -and ($n - $p) -ge ($p * 2 - $n)) { $p *= 2 }; $p }
    $w = & $pot $src.Width; $h = & $pot $src.Height
    $bmp = [Drawing.Bitmap]::new($w, $h, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp); $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($src, [Drawing.Rectangle]::new(0, 0, $w, $h)); $g.Dispose()
    $note = $(if ($w -ne $src.Width -or $h -ne $src.Height) { "resized $($src.Width)x$($src.Height) -> ${w}x$h (power of two)" } else { "${w}x$h" })
    $src.Dispose(); $bmp.Save($Path, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    return $note
  }
  $c = 0..2 | ForEach-Object { [int][Math]::Round(255 * [Math]::Pow([Math]::Min(1, [Math]::Max(0, [double]$Color[$_])), 1 / 2.2)) }   # glTF factors are linear
  $bmp = [Drawing.Bitmap]::new(4, 4); $g = [Drawing.Graphics]::FromImage($bmp); $g.Clear([Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2])); $g.Dispose()
  $bmp.Save($Path, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  "no texture: flat colour $($c -join ',')"
}

try {
  if (-not (Test-Path -LiteralPath $In)) { throw "Not found: $In" }
  $In = (Resolve-Path -LiteralPath $In).Path
  if ([IO.Path]::GetExtension($In) -eq '.zip') {
    $unz = Join-Path $work 'zip'; Expand-Archive -LiteralPath $In -DestinationPath $unz
    $cands = @(Get-ChildItem $unz -Recurse -File | Where-Object { $_.Extension.ToLowerInvariant() -in ($builtin + $viaBlender) })
    if ($Pick) { $cands = @($cands | Where-Object { $_.Name -like $Pick }) }
    if ($cands.Count -ne 1) { throw "The zip holds $($cands.Count) model file(s)$(if ($Pick) { " matching '$Pick'" }): $(($cands | ForEach-Object { $_.FullName.Substring($unz.Length + 1) }) -join ', '). Pass -Pick <file name>." }
    $In = $cands[0].FullName
    Write-Host "from the zip: $($cands[0].FullName.Substring($unz.Length + 1))"
  }
  $ext = [IO.Path]::GetExtension($In).ToLowerInvariant()
  if ($ext -notin ($builtin + $viaBlender)) { throw "Can't read $ext. Supported: $(($builtin + $viaBlender) -join ' '). Ask for the model as .glb, .gltf, .fbx, .dae or .obj." }
  if (-not $Name) { $Name = ConvertTo-Slug ([IO.Path]::GetFileNameWithoutExtension($In)) }
  if (-not $GameDir) {
    $full = [IO.Path]::GetFullPath($Out)
    $m = [regex]::Match($full, '\\src\\(.+)$')
    if (-not $m.Success) { throw "-Out isn't inside a mod's src folder, so the game path is unknown. Pass -GameDir <game path of -Out>, e.g. models/props_gameplay/soul_container/pumpkin." }
    $GameDir = $m.Groups[1].Value
  }
  $GameDir = $GameDir.Replace('\', '/').Trim('/').ToLowerInvariant()
  if ($GameDir -notmatch '^[a-z0-9_/]+$') { throw "Game path must be lowercase letters, digits, _ and /: $GameDir" }

  # ---- read -----------------------------------------------------------------------------------
  $read = $In
  if ($Via -eq 'blender' -or ($Via -eq 'auto' -and $ext -in $viaBlender)) {
    $blender = Find-Blender
    if (-not $blender) { throw "Reading $ext needs Blender, an optional download (about 400 MB). Ask the user, then: setup.ps1 -Models (lists it), setup.ps1 -Approve blender. Or ask them for the model as .glb, .gltf or .obj, which need nothing extra." }
    $py = Join-Path $work 'convert.py'; [IO.File]::WriteAllText($py, $blenderScript)
    $read = Join-Path $work 'blender\model.gltf'; New-Item -ItemType Directory -Force (Split-Path $read) | Out-Null
    Write-Host "Blender: reading $([IO.Path]::GetFileName($In))..."
    $bArgs = @('-b', '--factory-startup', '--python-exit-code', '1', '--python', $py, '--', $In, $read)   # splatted, so '--' reaches Blender
    $log = & $blender @bArgs 2>&1
    $err = $log | ForEach-Object { if ("$_" -match 'CONVERT-ERROR: (.*)') { $Matches[1] } } | Select-Object -First 1
    if ($err) { throw "Blender: $err" }
    $log | ForEach-Object { if ("$_" -match 'CONVERT-NOTE: (.*)') { Write-Host "  note: $($Matches[1])" -ForegroundColor Yellow } }
    if (-not (Test-Path $read)) { throw "Blender wrote no model (exit $LASTEXITCODE). Its last lines:`n$(($log | Select-Object -Last 15) -join "`n")" }
  }
  elseif ($ext -notin $builtin) { throw "-Via builtin reads only $($builtin -join ' ')." }
  $model = Read-MeshFile $read
  foreach ($n in @($model.Notes)) { if ($n) { Write-Host "  note: $n" -ForegroundColor Yellow } }
  $parts = @($model.Parts | Where-Object { $_.Idx.Count -gt 0 })
  if ($Only) {
    $skipped = @($parts | Where-Object { $_.Name -notmatch $Only })
    $parts = @($parts | Where-Object { $_.Name -match $Only })
    if ($skipped) { Write-Host "  dropped by -Only: $(($skipped | ForEach-Object Name | Select-Object -Unique) -join ', ')" }
  }
  if (-not $parts) { throw "No mesh left to write$(if ($Only) { " after -Only '$Only'" }). Parts in the file: $((@($model.Parts) | ForEach-Object Name | Select-Object -Unique) -join ', ')" }

  # ---- orient, scale, place ---------------------------------------------------------------------
  foreach ($p in $parts) {
    if ($UpAxis -eq 'Z') { [DeadlockModding.MeshIO]::Rotate($p, 0, -90) }
    if ($RotateX) { [DeadlockModding.MeshIO]::Rotate($p, 0, $RotateX) }
    if ($RotateY) { [DeadlockModding.MeshIO]::Rotate($p, 1, $RotateY) }
    if ($RotateZ) { [DeadlockModding.MeshIO]::Rotate($p, 2, $RotateZ) }
    if ($Scale -ne 1.0) { [DeadlockModding.MeshIO]::ScaleShift($p, $Scale, 0, 0, 0) }
  }
  $b = Get-MeshBounds $parts
  if ($Like) {
    if (Test-Path -LiteralPath $Like) {
      $lp = (Resolve-Path -LiteralPath $Like).Path
      $stock = $(if ($lp -match '\.vmdl_c$') { Read-CompiledModel -File $lp -WorkDir $work } else { Read-MeshFile $lp })
    }
    else {
      $sp = $Like.Replace('\', '/').ToLowerInvariant(); if (-not $sp.EndsWith('_c')) { $sp += '_c' }
      $root = $(if ($Deadlock) { $Deadlock } else { Find-DeadlockRoot })
      $stock = Read-CompiledModel -Vpk (Get-GameVpk $root) -GamePath $sp -WorkDir $work
    }
    $sb = Get-MeshBounds $stock.Parts
    if (-not $sb) { throw "The -Like model has no mesh to fit to." }
    $largest = { param($x) ($x.Size | Measure-Object -Maximum).Maximum }
    if ($Height) { $target = $Height; $s = $Height / [Math]::Max(0.0001, $b.Size[2]) }
    elseif ($Fit -eq 'largest') { $target = (& $largest $sb) * $b.Size[2] / [Math]::Max(0.0001, (& $largest $b)); $s = (& $largest $sb) / [Math]::Max(0.0001, (& $largest $b)) }
    else { $target = $sb.Size[2]; $s = $target / [Math]::Max(0.0001, $b.Size[2]) }
    foreach ($p in $parts) { [DeadlockModding.MeshIO]::ScaleShift($p, $s, ($sb.Center[0] - $s * $b.Center[0]), ($sb.Center[1] - $s * $b.Center[1]), ($sb.Min[2] - $s * $b.Min[2])) }
    Write-Host ("fitted to {0}: height {1:0.0} in, centred on it, bottom at Z {2:0.0} (scale x{3:0.####})" -f $Like, $target, $sb.Min[2], $s)
  }
  elseif ($Height) {
    $s = $Height / [Math]::Max(0.0001, $b.Size[2])
    foreach ($p in $parts) { [DeadlockModding.MeshIO]::ScaleShift($p, $s, 0, 0, 0) }
    Write-Host ("scaled to height {0:0.0} in (x{1:0.####}), about the file's origin" -f $Height, $s)
  }
  $b = Get-MeshBounds $parts

  # ---- materials: the in-game-checked NPR default, or (opt-in) the stock material's lighting settings ----
  $stockMat = $null
  if ($LikeMaterial -eq 'default') { $LikeMaterial = $null; $CopyStockMaterial = $false }
  if ($LikeMaterial -or ($CopyStockMaterial -and $Like)) {
    try {
      $sm = Get-StockMaterial -Model $Like -Material $LikeMaterial -Deadlock $Deadlock -WorkDir $work
      if ($sm) {
        $stockMat = ConvertFrom-Vmat $sm.Text
        Write-Host "materials: lit like the stock $($sm.Path)"
        if ($sm.Others) { Write-Host "  the stock model also names $($sm.Others -join ', '); pick another with -LikeMaterial" }
      }
    }
    catch { Write-Warning "Couldn't read the stock material ($($_.Exception.Message)). Writing the default NPR material instead." }
  }
  $matNotes = @{}

  # ---- write ----------------------------------------------------------------------------------
  New-Item -ItemType Directory -Force $Out | Out-Null
  $Out = (Resolve-Path $Out).Path
  $usemtl = @(); $done = @{}
  foreach ($p in $parts) {
    $slug = "${Name}_$(ConvertTo-Slug $p.Material)"
    $vmat = "$GameDir/$slug.vmat"; $usemtl += $vmat
    if ($done[$slug]) { continue }
    $done[$slug] = $true
    $mat = $model.Materials[$p.Material]
    $png = "${slug}_color.png"
    $note = Save-ColorPng $mat.Image ([double[]]$mat.Color) (Join-Path $Out $png) $MaxTexture
    $vm = New-ModelVmat "$GameDir/$png" $stockMat -Glow:$Glow -GlowTint $GlowTint
    [IO.File]::WriteAllText((Join-Path $Out "$slug.vmat"), $vm.Text, [Text.UTF8Encoding]::new($false))
    foreach ($n in $vm.Notes) { $matNotes[$n] = $true }
    Write-Host "  material '$($p.Material)' -> $slug.vmat + $png ($note)"
  }
  foreach ($n in $matNotes.Keys) { Write-Host "  note: $n" -ForegroundColor Yellow }
  $list = [Collections.Generic.List[DeadlockModding.MeshPart]]::new(); foreach ($p in $parts) { $list.Add($p) }
  $objPath = Join-Path $Out "$Name.obj"
  [DeadlockModding.MeshIO]::WriteObj($objPath, $list, [string[]]$usemtl, "# $Name, from $([IO.Path]::GetFileName($In)) by convert-model.ps1. Y up, 1 unit = 1 inch.`n")
  $inv = [Globalization.CultureInfo]::InvariantCulture
  $tris = ($parts | ForEach-Object { $_.Idx.Count / 3 } | Measure-Object -Sum).Sum
  Write-Host "parts:"
  foreach ($p in $parts) { Write-Host ("  {0}  material '{1}'  {2} vertices, {3} triangles{4}" -f $p.Name, $p.Material, $p.VertexCount, ($p.Idx.Count / 3), $(if (-not $p.Uv.Count) { '  (no UVs: textures will not map)' } else { '' })) }
  Write-Host ("bounds (Source inches, Z up): X {0:0.0}..{1:0.0}  Y {2:0.0}..{3:0.0}  Z {4:0.0}..{5:0.0}; size {6:0.0} x {7:0.0} x {8:0.0}" -f $b.Min[0], $b.Max[0], $b.Min[1], $b.Max[1], $b.Min[2], $b.Max[2], $b.Size[0], $b.Size[1], $b.Size[2])
  if ($tris -gt 60000) { Write-Host "  note: $tris triangles is heavy for a prop; stock props are mostly under 20,000." -ForegroundColor Yellow }
  Write-Host "wrote $objPath" -ForegroundColor Green
  Write-Host "In the .vmdl's RenderMeshFile:  filename = `"$GameDir/$Name.obj`""
  exit 0
}
finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
