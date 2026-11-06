#Requires -Version 7

<#
.SYNOPSIS
  Get the game's original ("stock") version of files, for the build you have installed. Every
  override must start from the stock file of the current build (docs/03-panorama.md, cookbook/after-a-patch.md).

.DESCRIPTION
  For each -Path (a game path such as panorama/layout/profile_card.xml; .vxml_c etc. also accepted):
    1. Checks the file exists in your install (game\citadel\pak01_dir.vpk).
    2. Gets the decompiled source:
       - s2v:          Source2Viewer-CLI decompiles it straight from your VPK (always your exact build).
                       Found via $env:S2V_CLI, in %LOCALAPPDATA%\deadlock-modding\bin (setup.ps1 puts it there), tools\bin\, or PATH.
       - gametracking: downloads it from SteamTracking/GameTracking-Deadlock on GitHub (Panorama,
                       scripts, configs; not models/textures/sounds). Refused when GameTracking's build
                       differs from yours, unless -AllowBuildMismatch.
       - auto (default): s2v if installed, else gametracking.
    3. Writes <Out>\<game path> and records { build, source } per path in <Out>\STOCK.json.
  A texture (.vtex_c) always comes out as <name>.vtex plus an editable image (.png; .exr for HDR) whose
  path the .vtex's m_fileName names, so editing the image and building recompiles the stock path. Most
  textures (Panorama images, materials' hash-named textures) had no .vtex; one is written for them, with the
  stock format, and colour space guessed from the name (normal/rough/mask maps linear, else sRGB).
  -Raw writes the compiled bytes (e.g. .vsnd_c, .vtex_c) from your VPK instead; no decompiling.
  -List <prefix> prints the compiled paths in your install that start with <prefix>, then exits.

.EXAMPLE
  .\get-stock.ps1 -List panorama/layout/hud_
  .\get-stock.ps1 panorama/layout/citadel_hud_and_db_overlay.xml -Out ..\mods\hello\stock
  .\get-stock.ps1 sounds/ui/ui_click.vsnd_c -Raw -Out .\stock
#>
param(
  [Parameter(Position = 0, ValueFromRemainingArguments)] [string[]]$Path,
  [string]$Out = '.\stock',
  [string]$List,
  [ValidateSet('auto', 's2v', 'gametracking')] [string]$Source = 'auto',
  [string]$Deadlock,
  [switch]$Raw,
  [switch]$AllowBuildMismatch
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

if (-not $Deadlock) { $Deadlock = Find-DeadlockRoot }
$build = Get-DeadlockBuild $Deadlock
$vpk = Get-GameVpk $Deadlock

if ($PSBoundParameters.ContainsKey('List')) {
  Read-VpkTree $vpk $List.Replace('\', '/') | ForEach-Object Path
  exit 0
}
if (-not $Path) { throw "Pass one or more game paths, or -List <prefix>." }

# Source extension <-> compiled extension. Panorama drops the leading v; other types just add _c.
# Valve's own scripts are compiled TypeScript (.vts_c); GameTracking stores them as .js.
$panorama = [ordered]@{ '.xml' = @('.vxml_c'); '.css' = @('.vcss_c'); '.js' = @('.vjs_c', '.vts_c'); '.ts' = @('.vts_c') }
function Get-CompiledCandidates([string]$p) {
  $ext = [IO.Path]::GetExtension($p)
  if ($ext.EndsWith('_c')) { return @($p) }
  if ($panorama.Contains($ext)) { return $panorama[$ext] | ForEach-Object { [IO.Path]::ChangeExtension($p, $_) } }
  return @("${p}_c")
}
function Get-SourcePath([string]$compiledPath) {
  $ext = [IO.Path]::GetExtension($compiledPath)
  foreach ($k in $panorama.Keys) { if ($panorama[$k] -contains $ext) { return [IO.Path]::ChangeExtension($compiledPath, $k) } }
  return $compiledPath -replace '_c$', ''
}

# Textures. S2V writes <name>.vtex + its image only when the game compiled the texture from a .vtex. Most
# textures (every Panorama image, the hash-named textures materials generate) were compiled straight from
# an image, so S2V writes just the image, under the .vtex name we asked for. Either way this leaves an
# editable image and a <name>.vtex whose m_fileName points at it, so the pair recompiles to the stock path.
$script:VtexFormats = @{ 1 = 'DXT1'; 2 = 'DXT5'; 4 = 'RGBA8888'; 10 = 'RGBA16161616F'; 19 = 'BC6H'; 20 = 'BC7'; 21 = 'ATI2N'; 27 = 'ATI1N'; 28 = 'BGRA8888' }
function Get-ImageExtension([byte[]]$b) {
  if ($b.Length -ge 4 -and $b[0] -eq 0x89 -and $b[1] -eq 0x50 -and $b[2] -eq 0x4E -and $b[3] -eq 0x47) { return '.png' }
  if ($b.Length -ge 4 -and $b[0] -eq 0x76 -and $b[1] -eq 0x2F -and $b[2] -eq 0x31 -and $b[3] -eq 0x01) { return '.exr' }
}
function New-VtexSource([string]$ImageGamePath, [string]$Format, [bool]$NoLod, [string]$ColorSpace, [string]$Mip = 'Box') {
  @"
<!-- dmx encoding keyvalues2_noids 1 format vtex 1 -->
"CDmeVtex"
{
    "m_inputTextureArray" "element_array"
    [
        "CDmeInputTexture"
        {
            "m_name" "string" "InputTexture0"
            "m_fileName" "string" "$ImageGamePath"
            "m_colorSpace" "string" "$ColorSpace"
            "m_typeString" "string" "2D"
            "m_imageProcessorArray" "element_array"
            [
                "CDmeImageProcessor"
                {
                    "m_algorithm" "string" "None"
                    "m_stringArg" "string" ""
                    "m_vFloat4Arg" "vector4" "0 0 0 0"
                }
            ]
        }
    ]
    "m_outputTypeString" "string" "2D"
    "m_outputFormat" "string" "$Format"
    "m_outputClearColor" "vector4" "0 0 0 0"
    "m_nOutputMinDimension" "int" "0"
    "m_nOutputMaxDimension" "int" "0"
    "m_textureOutputChannelArray" "element_array"
    [
        "CDmeTextureOutputChannel"
        {
            "m_inputTextureArray" "string_array" [ "InputTexture0" ]
            "m_srcChannels" "string" "rgba"
            "m_dstChannels" "string" "rgba"
            "m_mipAlgorithm" "CDmeImageProcessor"
            {
                "m_algorithm" "string" "$Mip"
                "m_stringArg" "string" ""
                "m_vFloat4Arg" "vector4" "0 0 0 0"
            }
            "m_outputColorSpace" "string" "$ColorSpace"
        }
    ]
    "m_vClamp" "vector3" "0 0 0"
    "m_bNoLod" "bool" "$([int]$NoLod)"
}
"@
}
# $Vtex: where the .vtex goes; $Made: the files this decompile wrote (already moved next to $Vtex).
function Complete-TextureSource([string]$Vtex, [string[]]$Made, $Entry, [string]$OutRoot) {
  $gamePath = { param($f) [IO.Path]::GetRelativePath($OutRoot, $f).Replace('\', '/') }
  $ext = Get-ImageExtension ([IO.File]::ReadAllBytes($Vtex))
  if ($ext) {
    $img = [IO.Path]::ChangeExtension($Vtex, $ext)
    Move-Item $Vtex $img -Force
    $compiled = [DeadlockModding.Vpk]::Extract($Entry)
    $data = Get-ResourceBlocks $compiled | Where-Object Type -eq 'DATA' | Select-Object -First 1
    $flags = [BitConverter]::ToUInt16($compiled, $data.Offset + 2)
    $fmtId = $compiled[$data.Offset + 26]
    $w = [BitConverter]::ToUInt16($compiled, $data.Offset + 20); $h = [BitConverter]::ToUInt16($compiled, $data.Offset + 22)
    $mip = $(if (($w -band ($w - 1)) -or ($h -band ($h - 1))) { 'None' } else { 'Box' })   # CSDK refuses to mip non-power-of-two sizes (Panorama images often are)
    if ($flags -band 0x70) { Write-Warning "$(& $gamePath $img) is a cube, volume or array texture; no .vtex written. Edit the image, then build a .vtex by hand."; return $img }
    $fmt = $script:VtexFormats[[int]$fmtId]
    if (-not $fmt) { $fmt = 'RGBA8888'; Write-Warning "Unknown texture format $fmtId; the .vtex uses RGBA8888." }
    $leaf = [IO.Path]::GetFileNameWithoutExtension($Vtex)
    $linear = $leaf -match 'normal|rough|mask|metal|height|_ao_|_ao$|_trans_' -and $leaf -notmatch '_tcolor_'
    [IO.File]::WriteAllText($Vtex, (New-VtexSource (& $gamePath $img) $fmt ([bool]($flags -band 8)) $(if ($linear) { 'linear' } else { 'srgb' }) $mip))
    return $img
  }
  # A real .vtex: make sure each m_fileName names an image that is actually here.
  $text = [IO.File]::ReadAllText($Vtex)
  $images = @($Made | Where-Object { $_ -ne $Vtex -and [IO.Path]::GetExtension($_) -in '.png', '.exr', '.tga', '.jpg', '.psd' })
  $names = @([regex]::Matches($text, '"m_fileName"\s+"string"\s+"([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
  $missing = @($names | Where-Object { $_ -and -not (Test-Path (Join-Path $OutRoot $_)) })
  if ($missing.Count -eq 1 -and $images.Count -eq 1) {
    $text = $text.Replace("""$($missing[0])""", """$(& $gamePath $images[0])""")
    [IO.File]::WriteAllText($Vtex, $text)
  }
  elseif ($missing) { Write-Warning "$(& $gamePath $Vtex) names images that weren't decompiled: $($missing -join ', ')" }
  if ($images) { $images[0] }
}

$script:gtBuild = $null
function Get-GameTrackingBuild {
  if ($null -eq $script:gtBuild) {
    $inf = (Invoke-WebRequest "$script:GameTrackingBase/steam.inf" -UseBasicParsing).Content
    $script:gtBuild = [int][regex]::Match($inf, '(?m)^ClientVersion=(\d+)').Groups[1].Value
  }
  $script:gtBuild
}

$s2v = Find-Source2ViewerCli
if ($Source -eq 'auto') { $Source = $(if ($s2v) { 's2v' } else { 'gametracking' }) }
if ($Source -eq 's2v' -and -not $s2v -and -not $Raw) { throw "Source2Viewer-CLI not found. Put Source2Viewer-CLI.exe in $PSScriptRoot\bin (docs/02-toolchain.md) or use -Source gametracking." }

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$recordPath = Join-Path $Out 'STOCK.json'
$record = [ordered]@{}
if (Test-Path $recordPath) { (Get-Content $recordPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $record[$_.Name] = $_.Value } }

$failed = 0
foreach ($requested in $Path) {
  $p = $requested.Replace('\', '/').ToLowerInvariant() -replace '^(game/)?(citadel/)?(pak01_dir/)?', ''
  $candidates = @(Get-CompiledCandidates $p)
  $compiled = $candidates[0]
  $entry = $null
  foreach ($c in $candidates) {
    $entry = Read-VpkTree $vpk $c | Where-Object Path -eq $c | Select-Object -First 1
    if ($entry) { $compiled = $c; break }
  }
  if (-not $entry) {
    Write-Host "[missing] $compiled is not in your build $build. It was renamed or removed by a patch; find the new name with -List." -ForegroundColor Red
    $failed++; continue
  }
  try {
    if ($Raw) {
      $dest = Join-Path $Out $compiled
      Export-VpkFile $entry $dest
      $how = 'raw'
    }
    elseif ($Source -eq 's2v') {
      $dest = Join-Path $Out (Get-SourcePath $compiled)
      $tmp = Join-Path ([IO.Path]::GetTempPath()) ("dlstock_" + [guid]::NewGuid().ToString('N'))
      try {
        # A -f that matches exactly one file makes -o that file's output path (S2V 20.1 docs). Decompiles
        # can write extra files next to it (a texture's image), so everything that lands in $tmp is kept.
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $log = & $s2v -i $vpk -f $compiled -o (Join-Path $tmp ([IO.Path]::GetFileName($dest))) -d 2>&1
        if ($LASTEXITCODE -ne 0) { $log | Write-Host; throw "Source2Viewer-CLI failed (exit $LASTEXITCODE)" }
        $made = @(Get-ChildItem $tmp -Recurse -File)
        if (-not $made) { $log | Write-Host; throw "Source2Viewer-CLI produced no file for $compiled" }
        $leaf = [IO.Path]::GetFileNameWithoutExtension($compiled)
        $primary = $made | Where-Object Name -eq ([IO.Path]::GetFileName($dest)) | Select-Object -First 1
        if (-not $primary) { $primary = $made | Where-Object { $_.BaseName -eq $leaf } | Select-Object -First 1 }
        if (-not $primary) { $primary = $made[0] }
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        $moved = @()
        foreach ($f in $made) {
          $target = Join-Path (Split-Path $dest) $f.Name
          if ($f.FullName -eq $primary.FullName) { $dest = $target }
          Move-Item $f.FullName $target -Force
          $moved += $target
        }
      } finally { if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force } }
      $how = 's2v'
      if ($compiled.EndsWith('.vtex_c')) {
        $img = Complete-TextureSource $dest $moved $entry $Out
        if ($img) { Write-Host "  image to edit: $([IO.Path]::GetRelativePath($Out, $img).Replace('\', '/')) (same size; the .vtex next to it compiles it back)" }
      }
    }
    else {
      $gt = Get-GameTrackingBuild
      if ($gt -ne $build -and -not $AllowBuildMismatch) {
        throw "GameTracking is on build $gt but you have $build. Install Source2Viewer-CLI, wait for GameTracking to update, or pass -AllowBuildMismatch."
      }
      $srcPath = Get-SourcePath $compiled
      $dest = Join-Path $Out $srcPath
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
      try { Invoke-WebRequest "$script:GameTrackingBase/pak01_dir/$srcPath" -OutFile $dest -UseBasicParsing }
      catch { throw "GameTracking has no $srcPath (it only tracks Panorama, scripts and configs). Use Source2Viewer-CLI or -Raw." }
      $how = "gametracking@$gt"
    }
    $key = [IO.Path]::GetRelativePath($Out, $dest).Replace('\', '/')
    $record[$key] = [ordered]@{ build = $build; source = $how }
    Write-Host "[ok] $key  (build $build, $how)" -ForegroundColor Green
  }
  catch { Write-Host "[failed] ${compiled}: $($_.Exception.Message)" -ForegroundColor Red; $failed++ }
}
$record | ConvertTo-Json | Set-Content $recordPath -Encoding utf8
exit $failed
