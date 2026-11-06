#Requires -Version 7

<#
.SYNOPSIS
  Draw a model as front and side wireframes on a 12-inch grid, over the stock model, and print its bounds
  in inches: check scale, orientation and placement before anyone tests in-game (cookbook/models.md).

.DESCRIPTION
  The model to check, one of:
    -Mod <folder> -Path <game path>    the model inside the mod's built dist\pakNN_dir.vpk (after build.ps1 -Mod)
    -Vpk <pak> -Path <game path>       the model inside any VPK
    -Model <file>                      a compiled .vmdl_c, or a mesh: .gltf/.glb, or .obj read the way
                                       resourcecompiler reads it (inches, Y up; -ImportScale = the vmdl's import_scale)
  The stock model to overlay: -Stock <game path or file>. With -Path, the stock model at that same path is
  overlaid by default (from the installed game's pak01); -NoStock turns that off.

  Writes a PNG (default <Mod>\dist\preview.png, else %TEMP%\preview-<name>.png): the new model in red, the
  stock one in blue, the floor (Z = 0) as a thick black line, the origin axes in grey. Front = seen from +X
  (Y to the right), side = seen from -Y (X, the model's forward, to the right). Open the PNG and look at it.
  Prints both models' bounds, their size ratio and offsets, and a WARN for a likely scale, orientation or
  placement mistake. Compiled models are read through Source2Viewer-CLI's glTF export.

  Exit code: 0 = drawn, 1 = the model has no mesh (the compile read no geometry) or couldn't be read.

.EXAMPLE
  pwsh -File preview-model.ps1 -Mod ..\mods\soul-swap -Path models/props_gameplay/soul_container/soul_container.vmdl_c
  pwsh -File preview-model.ps1 -Model C:\work\pumpkin.obj -Stock models/props_gameplay/soul_container/soul_container.vmdl_c
  pwsh -File preview-model.ps1 -Model C:\work\built.vmdl_c -NoStock -Out C:\work\look.png
#>
param(
  [string]$Model,
  [string]$Mod,
  [string]$Vpk,
  [string]$Path,
  [string]$Stock,
  [switch]$NoStock,
  [double]$ImportScale = 1.0,
  [string]$Out,
  [ValidateRange(200, 2000)] [int]$Size = 480,
  [string]$Deadlock
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')
. (Join-Path $PSScriptRoot 'mesh.ps1')

$work = Join-Path ([IO.Path]::GetTempPath()) ("dlpreview_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
$gameVpk = { $r = $(if ($Deadlock) { $Deadlock } else { Find-DeadlockRoot }); Get-GameVpk $r }

function Read-Any([string]$File, [string]$InVpk, [string]$GamePath, [double]$Scale = 1.0) {
  if ($File) {
    if (-not (Test-Path -LiteralPath $File)) { throw "Not found: $File" }
    $ext = [IO.Path]::GetExtension($File).ToLowerInvariant()
    if ($ext -eq '.vmdl_c') { return Read-CompiledModel -File (Resolve-Path -LiteralPath $File).Path -WorkDir $work }
    $m = Read-MeshFile (Resolve-Path -LiteralPath $File).Path
    if ($Scale -ne 1.0) { foreach ($p in $m.Parts) { [DeadlockModding.MeshIO]::ScaleShift($p, $Scale, 0, 0, 0) } }
    return $m
  }
  Read-CompiledModel -Vpk $InVpk -GamePath $GamePath -WorkDir $work
}
function Format-Bounds($b) {
  if (-not $b) { return '(no mesh)' }
  $f = { param($v) $v.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) }
  "X $(& $f $b.Min[0])..$(& $f $b.Max[0])  Y $(& $f $b.Min[1])..$(& $f $b.Max[1])  Z $(& $f $b.Min[2])..$(& $f $b.Max[2])  size $(& $f $b.Size[0]) x $(& $f $b.Size[1]) x $(& $f $b.Size[2]) in (X x Y x Z)"
}

try {
  if ($Path) { $Path = $Path.Replace('\', '/').ToLowerInvariant(); if (-not $Path.EndsWith('_c')) { $Path += '_c' } }
  if ($Mod) {
    if (-not $Path) { throw "-Mod needs -Path <game path of the model>, e.g. models/props_gameplay/soul_container/soul_container.vmdl_c" }
    $manifest = Get-Content (Join-Path $Mod 'mod.json') -Raw | ConvertFrom-Json
    $Vpk = Join-Path $Mod ("dist\pak{0:D2}_dir.vpk" -f [int]$manifest.pak)
    if (-not (Test-Path $Vpk)) { throw "$Vpk not found. Build the mod first: build.ps1 -Mod $Mod" }
    if (-not $Out) { $Out = Join-Path $Mod 'dist\preview.png' }
  }
  if (-not $Model -and -not ($Vpk -and $Path)) { throw "Pass -Model <file>, or -Mod/-Vpk with -Path <game path>." }
  $label = $(if ($Model) { Split-Path $Model -Leaf } else { "$Path in $(Split-Path $Vpk -Leaf)" })
  $new = Read-Any -File $Model -InVpk $Vpk -GamePath $Path -Scale $ImportScale
  $newB = Get-MeshBounds $new.Parts

  $old = $null; $oldB = $null; $oldLabel = $null
  if (-not $NoStock -and ($Stock -or $Path)) {
    $sp = $(if ($Stock) { $Stock } else { $Path })
    if (Test-Path -LiteralPath $sp) { $old = Read-Any -File $sp; $oldLabel = Split-Path $sp -Leaf }
    else {
      $sp = $sp.Replace('\', '/').ToLowerInvariant(); if (-not $sp.EndsWith('_c')) { $sp += '_c' }
      $old = Read-Any -InVpk (& $gameVpk) -GamePath $sp; $oldLabel = "stock $sp"
    }
    $oldB = Get-MeshBounds $old.Parts
  }

  $tris = { param($m) ($m.Parts | ForEach-Object { $_.Idx.Count / 3 } | Measure-Object -Sum).Sum }
  Write-Host "new    $label"
  Write-Host "       $(@($new.Parts).Count) mesh part(s), $(& $tris $new) triangles, materials: $((@($new.Parts.Material) | Select-Object -Unique) -join ', ')"
  Write-Host "       $(Format-Bounds $newB)"
  if ($old) { Write-Host "stock  $oldLabel"; Write-Host "       $(Format-Bounds $oldB)" }
  foreach ($n in @($new.Notes)) { if ($n) { Write-Host "  note: $n" -ForegroundColor Yellow } }
  if (-not $newB) {
    Write-Host "FAIL: the model has no mesh. The compile read no geometry from the mesh file (an FBX the importer can't read still compiles 'OK', empty). Check RenderMeshFile's filename and the file's format (docs/09 route 4)." -ForegroundColor Red
    exit 1
  }
  $inv = [Globalization.CultureInfo]::InvariantCulture
  if ($oldB) {
    $ratio = 0..2 | ForEach-Object { if ($oldB.Size[$_] -gt 0.01) { $newB.Size[$_] / $oldB.Size[$_] } else { 0 } }
    $off = 0..2 | ForEach-Object { $newB.Center[$_] - $oldB.Center[$_] }
    Write-Host ("compare  size new/stock: X {0:0.00}  Y {1:0.00}  Z {2:0.00};  centre offset {3:0.0}, {4:0.0}, {5:0.0} in;  bottom {6:0.0} in vs stock {7:0.0}" -f $ratio[0], $ratio[1], $ratio[2], $off[0], $off[1], $off[2], $newB.Min[2], $oldB.Min[2])
    $big = ($newB.Size | Measure-Object -Maximum).Maximum / [Math]::Max(0.01, ($oldB.Size | Measure-Object -Maximum).Maximum)
    if ($big -gt 3 -or $big -lt 0.33) { Write-Host ("WARN: scale: the new model's largest side is {0:0.##}x the stock model's. Fix with import_scale on the RenderMeshFile, or convert-model.ps1 -Height/-Like." -f $big) -ForegroundColor Yellow }
    $aspect = { param($b) $b.Size[2] / [Math]::Max(0.01, [Math]::Max($b.Size[0], $b.Size[1])) }   # height / width
    $ar = (& $aspect $newB) / [Math]::Max(0.01, (& $aspect $oldB))
    if ($ar -lt 0.4 -or $ar -gt 2.5) { Write-Host ("WARN: orientation: height-to-width is {0:0.##}x the stock model's. If it should stand like the stock one, it is lying down (or standing on end): a Z-up mesh read as Y-up lies down. convert-model.ps1 -UpAxis Z, or -RotateX 90 / -RotateY 90." -f $ar) -ForegroundColor Yellow }
    $span = [Math]::Max(($oldB.Size | Measure-Object -Maximum).Maximum, 1)
    if ([Math]::Abs($off[0]) -gt 0.25 * $span -or [Math]::Abs($off[1]) -gt 0.25 * $span -or [Math]::Abs($newB.Min[2] - $oldB.Min[2]) -gt 0.25 * $span) { Write-Host "WARN: placement: the new model is off the stock model's position (centre or bottom differ by more than a quarter of its size). convert-model.ps1 -Like <stock> lines it up." -ForegroundColor Yellow }
  }

  # ---- draw -----------------------------------------------------------------------------------
  Add-Type -AssemblyName System.Drawing
  $all = @($newB) + @($(if ($oldB) { $oldB }))
  $lo = 0..2 | ForEach-Object { $i = $_; [Math]::Min(0, ($all | ForEach-Object { $_.Min[$i] } | Measure-Object -Minimum).Minimum) }
  $hi = 0..2 | ForEach-Object { $i = $_; [Math]::Max(0, ($all | ForEach-Object { $_.Max[$i] } | Measure-Object -Maximum).Maximum) }
  $extent = [Math]::Max(1, (0..2 | ForEach-Object { $hi[$_] - $lo[$_] } | Measure-Object -Maximum).Maximum) * 1.15
  $scale = $Size / $extent
  $c = 0..2 | ForEach-Object { ($lo[$_] + $hi[$_]) / 2 }
  $head = 40; $W = 2 * $Size; $H = $Size + $head
  $bmp = [Drawing.Bitmap]::new($W, $H, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gr = [Drawing.Graphics]::FromImage($bmp); $gr.Clear([Drawing.Color]::White)
  $step = 12; while ($step * $scale -lt 14) { $step *= 2 }
  while ($step -gt 3 -and $extent / $step -lt 4) { $step /= 2 }   # small props: 6 or 3 in, so the grid still measures
  $gridPen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(225, 225, 225)); $axisPen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(150, 150, 150)); $floorPen = [Drawing.Pen]::new([Drawing.Color]::Black, 2)
  $font = [Drawing.Font]::new('Arial', 9); $small = [Drawing.Font]::new('Arial', 7)
  $panels = @(@{ Left = 0; Axis = 1; Title = 'FRONT, seen from +X: Y right, Z up' }, @{ Left = $Size; Axis = 0; Title = "SIDE, seen from -Y: X (the model's forward) right, Z up" })
  $oy = $head + $Size / 2 + $scale * $c[2]
  foreach ($p in $panels) {
    $p.Ox = $p.Left + $Size / 2 - $scale * $c[$p.Axis]
    $gr.SetClip([Drawing.Rectangle]::new($p.Left, $head, $Size, $Size))
    for ($v = [Math]::Floor(($c[$p.Axis] - $extent) / $step) * $step; $v -le $c[$p.Axis] + $extent; $v += $step) { $x = $p.Ox + $scale * $v; $gr.DrawLine($(if ($v -eq 0) { $axisPen } else { $gridPen }), [float]$x, [float]$head, [float]$x, [float]$H) }
    for ($v = [Math]::Floor(($c[2] - $extent) / $step) * $step; $v -le $c[2] + $extent; $v += $step) {
      $y = $oy - $scale * $v; if ($v -ne 0) { $gr.DrawLine($gridPen, [float]$p.Left, [float]$y, [float]($p.Left + $Size), [float]$y) }
      $gr.DrawString(("{0} in" -f $v), $small, [Drawing.Brushes]::Gray, [float]($p.Left + 2), [float]($y - 10))
    }
    $gr.DrawLine($floorPen, [float]$p.Left, [float]$oy, [float]($p.Left + $Size), [float]$oy)
    $gr.ResetClip()
  }
  $gr.DrawLine([Drawing.Pen]::new([Drawing.Color]::Black), [float]$Size, [float]$head, [float]$Size, [float]$H)
  $rect = [Drawing.Rectangle]::new(0, 0, $W, $H)
  $data = $bmp.LockBits($rect, 'ReadWrite', [Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $px = [byte[]]::new($data.Stride * $H)
  [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $px.Length)
  $draw = { param($m, $r, $g, $b, $a)
    $list = [Collections.Generic.List[DeadlockModding.MeshPart]]::new(); foreach ($q in $m.Parts) { $list.Add($q) }
    foreach ($p in $panels) { [DeadlockModding.MeshIO]::Wire($px, $W, $H, $list, $p.Axis, $scale, 2, $scale, $p.Ox, $oy, $r, $g, $b, $a) } }
  if ($oldB) { & $draw $old 30 90 255 70 }
  & $draw $new 225 25 25 110
  [Runtime.InteropServices.Marshal]::Copy($px, 0, $data.Scan0, $px.Length)
  $bmp.UnlockBits($data)
  $gr.FillRectangle([Drawing.Brushes]::White, 0, 0, $W, $head)
  $gr.DrawString("RED = new ($label)" + $(if ($oldB) { "    BLUE = $oldLabel" } else { '' }), $font, [Drawing.Brushes]::Black, 4, 4)
  $gr.DrawString("grid $step in    black line = floor (Z = 0)    grey lines = origin", $font, [Drawing.Brushes]::DimGray, 4, 20)
  foreach ($p in $panels) { $gr.DrawString($p.Title, $font, [Drawing.Brushes]::Black, [float]($p.Left + 40), [float]($head + 2)) }
  if (-not $Out) { $Out = Join-Path ([IO.Path]::GetTempPath()) ("preview-{0}.png" -f [IO.Path]::GetFileNameWithoutExtension(($label -split ' ')[0])) }
  $Out = [IO.Path]::GetFullPath($Out)
  New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
  $bmp.Save($Out, [Drawing.Imaging.ImageFormat]::Png); $gr.Dispose(); $bmp.Dispose()
  Write-Host "wrote $Out" -ForegroundColor Green
  exit 0
}
finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
