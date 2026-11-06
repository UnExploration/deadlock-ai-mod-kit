#Requires -Version 7

<#
.SYNOPSIS
  Build a Deadlock mod into pakNN_dir.vpk, and optionally install it (docs/02-toolchain.md, docs/05).
  Run with PowerShell 7:  pwsh -ExecutionPolicy Bypass -File build.ps1 ...

.DESCRIPTION
  -Src holds files at their game paths, e.g. <Src>\panorama\layout\profile_card.xml,
  <Src>\panorama\scripts\mymod.js, <Src>\sounds\ui\ui_menu_hover_01.vsnd_c.
  1. Already-compiled files (*_c) are packed as they are. No compiler needed.
  2. Sources (.xml .css .js, and experimentally .mp3 .wav .vtex .vmat .vpcf .vsndevts .vmdl) are
     copied with every other file into <Csdk>\content\citadel_addons\<Name> and compiled with
     Reduced CSDK 12's resourcecompiler -nop4 -f (25 per batch). Each must produce its _c file.
     Support files are staged but not shipped themselves: images (.png .jpg .tga .psd) end up in
     the .vtex_c of a .vtex/.vmat that names them, or as Panorama children of a layout/style that
     references them as file://{images}/...; meshes and animations (.obj .fbx .dae .dmx) compile
     into the .vmdl_c that references them. An image or mesh nothing uses gets a warning.
     Files a compile generates beside its outputs (a material's hash-named .vtex_c) ship too, except
     ones the game already has that no image in src made (the materials/default/*.vtex_c every .vmat
     compile writes). A .vmdl_c that compiled with no mesh stops the build (-AllowEmptyModel ships it).
     Panorama compiles are proven by community pipelines; the other types have no public CLI
     pipeline yet, so read the output.
  3. Packs into <Out>\pak<NN>_dir.vpk with the built-in packer (-Packer builtin, default: the same
     single-file VPK v2 layout CSDKCfgVPK writes) or CSDKCfgVPK.exe (-Packer csdk), then lists it.
  4. With -Install, copies the VPK into Deadlock's game\citadel\addons. It refuses to replace a
     pak another mod owns (ownership is recorded in %LOCALAPPDATA%\deadlock-modding\paks.json)
     unless -Force.

  -Mod <folder> reads name and pak from <folder>\mod.json (made by new-mod.ps1), builds <folder>\src
  into <folder>\dist, and warns when the game build differs from the one the overrides were based on.
  mod.json "copies" ({ "<game path to replace>": "<game path of the donor>" }, both compiled *_c files)
  packs a copy of the donor from the installed game under the target path, so a mod that reuses
  game files ships no game files itself. A file in src at the same path wins over a copy.

.EXAMPLE
  pwsh -File build.ps1 -Mod .\mods\hello -Install
  pwsh -File build.ps1 -Src .\src -Name mymod -Pak 64 -Install
#>
param(
  [string]$Mod,
  [string]$Src,
  [ValidatePattern('^[a-z0-9_]+$')] [string]$Name,
  [ValidateRange(0, 99)] [int]$Pak,
  [string]$Csdk,
  [string]$Out,
  [string]$Deadlock,
  [ValidateSet('builtin', 'csdk')] [string]$Packer = 'builtin',
  [switch]$Install,
  [switch]$Force,
  [switch]$AllowEmptyModel
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

if ($Mod) {
  $manifestPath = Join-Path $Mod 'mod.json'
  if (-not (Test-Path $manifestPath)) { throw "$manifestPath not found. Make the mod with new-mod.ps1, or pass -Src/-Name/-Pak." }
  $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
  if (-not $Name) { $Name = $manifest.name }
  if (-not $Pak) { $Pak = $manifest.pak }
  if (-not $Src) { $Src = Join-Path $Mod 'src' }
  if (-not $Out) { $Out = Join-Path $Mod 'dist' }
  $root = $(if ($Deadlock) { $Deadlock } else { try { Find-DeadlockRoot } catch { $null } })
  $build = $(if ($root) { Get-DeadlockBuild $root })
  if ($build -and $manifest.gameBuild -and $build -ne $manifest.gameBuild) {
    Write-Warning "The game is build $build but this mod's overrides were based on build $($manifest.gameBuild). Run rebase.ps1 -Mod $Mod before trusting the result (cookbook/after-a-patch.md)."
  }
}
if (-not $Src -or -not $Name -or -not $Pak) { throw "Pass -Mod <folder>, or all of -Src, -Name and -Pak." }
if ($Name -notmatch '^[a-z0-9_]+$') { throw "Mod name must be lowercase letters, digits and _: $Name" }
if ($Pak -lt 1 -or $Pak -gt 99) { throw "-Pak must be 1-99" }

$Csdk = Find-Csdk $Csdk
$compiler = Join-Path $Csdk "game\bin_cs2\win64\resourcecompiler.exe"
$csdkPacker = Join-Path $Csdk "game\bin\win64\CSDKCfgVPK.exe"
if ($Mod -and $manifest.copies -and -not (Test-Path $Src)) { New-Item -ItemType Directory -Path $Src | Out-Null }   # a copies-only mod
$Src = (Resolve-Path $Src).Path
if (-not $Out) { $Out = Join-Path (Split-Path $Src) 'dist' }
$content = Join-Path $Csdk "content\citadel_addons\$Name"
$game = Join-Path $Csdk "game\citadel_addons\$Name"
$staging = Join-Path ([IO.Path]::GetTempPath()) "dlbuild_$Name"
$compiled = @{
  '.xml' = '.vxml_c'; '.css' = '.vcss_c'; '.js' = '.vjs_c'
  '.mp3' = '.vsnd_c'; '.wav' = '.vsnd_c'; '.vtex' = '.vtex_c'; '.vmat' = '.vmat_c'; '.vpcf' = '.vpcf_c'; '.vsndevts' = '.vsndevts_c'
  '.vmdl' = '.vmdl_c'
}
$text = @('.xml', '.css', '.js')
$meshes = @('.obj', '.fbx', '.dae', '.dmx')            # mesh/animation sources a .vmdl reads; compiled into it, not shipped
$images = @('.png', '.jpg', '.jpeg', '.tga', '.psd')

Write-Host "[1/4] Staging $Src" -ForegroundColor Cyan
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$sources = @(); $support = @(); $passthrough = 0
foreach ($file in Get-ChildItem $Src -Recurse -File) {
  $rel = $file.FullName.Substring($Src.Length + 1)
  # get-stock's record of where each stock file came from, when a guide fetched straight into src.
  if ($rel -eq 'STOCK.json') { continue }
  if ($rel -cne $rel.ToLowerInvariant()) { throw "Path must be lowercase (VPK paths are lowercase): $rel" }
  if ($file.Extension.EndsWith('_c')) {
    $dest = Join-Path $staging $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item $file.FullName $dest
    $passthrough++
  }
  elseif ($compiled.ContainsKey($file.Extension)) {
    $sources += [pscustomobject]@{ File = $file; Rel = $rel; Compiled = [IO.Path]::ChangeExtension($rel, $compiled[$file.Extension]) }
  }
  else { $support += [pscustomobject]@{ File = $file; Rel = $rel } }
}
if ($Mod -and $manifest.copies) {
  if (-not $root) { throw "mod.json has copies, but the Deadlock install wasn't found. Pass -Deadlock." }
  $copies = @($manifest.copies.PSObject.Properties)
  $gameTree = @{}
  foreach ($e in (Read-VpkTree (Get-GameVpk $root) | Where-Object { $_.Path -in @($copies.Value) })) { $gameTree[$e.Path] = $e }
  $made = 0
  foreach ($c in $copies) {
    $target = $c.Name.ToLowerInvariant(); $donor = $c.Value.ToLowerInvariant()
    if (-not $target.EndsWith('_c') -or -not $donor.EndsWith('_c')) { throw "copies must map compiled game paths (*_c): $target <- $donor" }
    if (-not $gameTree[$donor]) { throw "Donor not in this game build: $donor (search the catalog's files.tsv)" }
    $dest = Join-Path $staging $target
    if (Test-Path $dest) { continue }
    Export-VpkFile $gameTree[$donor] $dest
    $made++
  }
  Write-Host "  $made file(s) copied from the game per mod.json copies"
}
Write-Host "  $passthrough compiled file(s) packed as-is, $($sources.Count) to compile"

if ($sources) {
  Write-Host "[2/4] Compiling $($sources.Count) files with Reduced CSDK 12" -ForegroundColor Cyan
  if (-not (Test-Path $compiler)) { throw "Missing $compiler. Install Reduced CSDK 12 with setup.ps1 (docs/02-toolchain.md); it compiles .xml/.css/.js and other sources." }
  foreach ($dir in @($content, $game)) { if (Test-Path $dir) { Remove-Item $dir -Recurse -Force } }
  foreach ($f in @($sources) + @($support)) {
    $dest = Join-Path $content $f.Rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    if ($text -contains $f.File.Extension) { [IO.File]::WriteAllText($dest, [IO.File]::ReadAllText($f.File.FullName), $utf8) }
    else { Copy-Item $f.File.FullName $dest }
  }
  for ($i = 0; $i -lt $sources.Count; $i += 25) {
    $batch = $sources[$i..([Math]::Min($i + 24, $sources.Count - 1))]
    $rcArgs = @(); foreach ($s in $batch) { $rcArgs += '-i'; $rcArgs += (Join-Path $content $s.Rel) }; $rcArgs += '-nop4'; $rcArgs += '-f'
    $log = & $compiler @rcArgs 2>&1
    if ($LASTEXITCODE -ne 0) { $log | Write-Host; throw "resourcecompiler failed (exit $LASTEXITCODE)" }
  }
  $missing = @()
  foreach ($s in $sources) {
    $made = Join-Path $game $s.Compiled
    if (-not (Test-Path $made)) { $missing += $made; continue }
    $dest = Join-Path $staging $s.Compiled
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item $made $dest
  }
  if ($missing) { $missing | ForEach-Object { Write-Host "  missing output: $_" -ForegroundColor Red }; throw "Some files produced no compiled output" }
  # A model that compiled with no mesh: the importer read no geometry (an FBX it can't read still compiles "OK").
  $empty = @(foreach ($s in $sources | Where-Object { $_.File.Extension -eq '.vmdl' }) {
      $bytes = [IO.File]::ReadAllBytes((Join-Path $game $s.Compiled))
      $types = @(Get-ResourceBlocks $bytes | ForEach-Object Type)
      if ($types -notcontains 'MDAT' -and $types -notcontains 'MVTX' -and -not (Get-ResourceRefs $bytes | Where-Object { $_ -match '\.vmesh$' })) { $s.Compiled }
    })
  if ($empty -and -not $AllowEmptyModel) {
    $empty | ForEach-Object { Write-Host "  NO MESH: $_" -ForegroundColor Red }
    throw "A model compiled with no mesh: resourcecompiler read no geometry from its RenderMeshFile. Check the filename, and that the mesh is FBX, DMX, SMD or OBJ (.dae, .gltf and .glb aren't read: convert them with convert-model.ps1). An FBX it can't parse also ends up empty. -AllowEmptyModel ships it anyway (only for hiding a model on purpose)."
  }
  # Resources a compile generated beside its outputs (e.g. a material's new hash-named .vtex_c) ship too, unless the
  # game already has that file and no image in src made it: a .vmat compile also writes the materials/default/*.vtex_c
  # it falls back on, which pak01 already has (and CSDK's copies differ from the game's).
  $generated = @(Get-ChildItem $game -Recurse -File | Where-Object { $_.Extension.EndsWith('_c') } |
      ForEach-Object { $_.FullName.Substring($game.Length + 1) } | Where-Object { -not (Test-Path (Join-Path $staging $_)) })
  if ($generated) {
    $fromSrc = @{}; foreach ($f in $support) { $fromSrc[($f.Rel.Replace('\', '/') -replace '\.([a-z0-9]+)$', '_$1')] = $true }   # x/skin.png -> x/skin_png
    $gameRoot = $(if ($Deadlock) { $Deadlock } elseif ($Mod) { $root } else { try { Find-DeadlockRoot } catch { $null } })
    $inGame = $null
    if ($gameRoot -and (Test-Path (Get-GameVpk $gameRoot))) { $inGame = [Collections.Generic.HashSet[string]]::new([string[]]@((Read-VpkTree (Get-GameVpk $gameRoot)).Path)) }
    foreach ($rel in $generated) {
      $p = $rel.Replace('\', '/')
      $ours = $p -match '^(.*)_[0-9a-f]{8}\.vtex_c$' -and $fromSrc[$Matches[1]]
      $stock = $(if ($inGame) { $inGame.Contains($p) } else { $p.StartsWith('materials/default/') })
      if ($stock -and -not $ours) { Write-Host "  - not shipped, the game has it: $rel"; continue }
      $dest = Join-Path $staging $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null; Copy-Item (Join-Path $game $rel) $dest; Write-Host "  + generated $rel"
    }
  }
  # An image ships inside the .vtex_c of a .vtex/.vmat that names it (a game texture: m_fileName in a
  # stock .vtex from get-stock), or as a Panorama child <name>_<ext>.vtex_c of a layout/style that
  # references it as file://{images}/<path>. A .vtex can name a .mks frame list (a flipbook), whose
  # `frame <png>... <n>` lines name the images relative to the .mks. Warn only when none of this happened.
  $named = @{}
  foreach ($s in $sources | Where-Object { $_.File.Extension -in '.vtex', '.vmat' }) {
    $text = [IO.File]::ReadAllText($s.File.FullName)
    foreach ($m in [regex]::Matches($text, '"([^"]+\.(?:png|jpe?g|tga|psd))"', 'IgnoreCase')) {
      $named[$m.Groups[1].Value.Replace('\', '/').ToLowerInvariant()] = $true
    }
    foreach ($m in [regex]::Matches($text, '"([^"]+\.mks)"', 'IgnoreCase')) {
      $mksRel = $m.Groups[1].Value.Replace('\', '/')
      $mks = Join-Path $Src $mksRel
      if (-not (Test-Path $mks)) { continue }
      $dir = ($mksRel -replace '[^/]*$', '').ToLowerInvariant()
      foreach ($line in Get-Content $mks) {
        if ($line -notmatch '^\s*frame\s+(.+)$') { continue }
        foreach ($f in $Matches[1] -split '\s+' | Where-Object { $_ -match '\.(?:png|jpe?g|tga|psd)$' }) { $named[$dir + $f.Replace('\', '/').ToLowerInvariant()] = $true }
      }
    }
  }
  foreach ($s in $support | Where-Object { $_.File.Extension -in $images }) {
    if ($named[$s.Rel.Replace('\', '/')]) { continue }
    $vtex = Join-Path $game ("{0}_{1}.vtex_c" -f ($s.Rel -replace '\.[^.\\/]+$', ''), $s.File.Extension.TrimStart('.'))
    if (-not (Test-Path $vtex)) { Write-Warning "Image not compiled, so not shipped: $($s.Rel). No .vtex or .vmat names it, and no .xml/.css references it as file://{images}/<path under panorama/images>." }
  }
  if (-not ($sources | Where-Object { $_.File.Extension -eq '.vmdl' })) {
    $support | Where-Object { $_.File.Extension -in $meshes } | ForEach-Object { Write-Warning "Mesh not shipped: $($_.Rel). Meshes compile only into a .vmdl that references them." }
  }
}
elseif ($support) {
  $support | ForEach-Object {
    if ($meshes -contains $_.File.Extension) { Write-Warning "Mesh not shipped: $($_.Rel). Meshes compile only into a .vmdl that references them." }
    else { Write-Warning "Skipped (not a compiled _c file or a known source): $($_.Rel)" }
  }
}
if (-not (Get-ChildItem $staging -Recurse -File)) { throw "Nothing to pack: no _c files or compilable sources under $Src" }

Write-Host "[3/4] Packing ($Packer)" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$vpkName = "pak{0:D2}_dir.vpk" -f $Pak
$vpk = Join-Path $Out $vpkName
if (Test-Path $vpk) { Remove-Item $vpk -Force }
if ($Packer -eq 'csdk') {
  if (-not (Test-Path $csdkPacker)) { throw "Missing $csdkPacker. Install Reduced CSDK 12, or use -Packer builtin." }
  & $csdkPacker $staging $vpk
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $vpk)) { throw "CSDKCfgVPK failed (exit $LASTEXITCODE)" }
}
else { New-Vpk $staging $vpk }
Remove-Item $staging -Recurse -Force
Write-Host "  built $vpk ($((Get-Item $vpk).Length) bytes). Contents:" -ForegroundColor Green
& (Join-Path $PSScriptRoot 'vpk-list.ps1') $vpk | ForEach-Object { Write-Host "    $($_.Path)  ($($_.Bytes) bytes)" }

if (-not $Install) { exit 0 }
Write-Host "[4/4] Installing" -ForegroundColor Cyan
if (-not $Deadlock) { $Deadlock = Find-DeadlockRoot }
Assert-DeadlockClosed $Deadlock
$addons = Join-Path $Deadlock "game\citadel\addons"
if (-not (Test-Path $addons)) { throw "$addons does not exist. Run enable-addons.ps1 first." }
$target = Join-Path $addons $vpkName
$registry = Get-PakRegistry
if ((Test-Path $target) -and -not $Force -and $registry[$vpkName] -ne $Name) {
  throw "$target exists and was not installed by '$Name' (pak owners: $script:PakRegistryPath). Pick another -Pak or pass -Force."
}
Copy-Item $vpk $target -Force
$registry[$vpkName] = $Name
Save-PakRegistry $registry
$gi = Get-Content (Join-Path $Deadlock "game\citadel\gameinfo.gi") -Raw
if ($gi -notmatch '(?m)^\s*Game\s+citadel/addons\s*$') { Write-Warning "gameinfo.gi does not mount citadel/addons; run enable-addons.ps1 or the mod will not load." }
Write-Host "  installed $target. Start Deadlock to test (addons load at startup only)." -ForegroundColor Green
