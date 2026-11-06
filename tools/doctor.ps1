<#
.SYNOPSIS
  Check this PC is ready to make and test Deadlock mods, and say how to fix what isn't.
  Read-only: it changes nothing. Runs on Windows PowerShell 5.1 too, so it can tell you to get pwsh 7.

.DESCRIPTION
  Checks: PowerShell 7, the Deadlock install and build, whether the kit's generated/ folder (data read off
  the game by setup.ps1 / generate-docs.ps1) exists and is for that build, whether gameinfo.gi mounts addons, whether
  matchmaking-guarded gameinfo.gi sections differ from Valve's (compared with GameTracking's copy of
  the same build; skip with -Offline), Reduced CSDK 12, Source2Viewer-CLI, Node.js, git, Steam launch
  options, and installed mods. Optional tools (GitHub CLI, yt-dlp, ffmpeg, Blender) are INFO lines, never FAIL.
  Exit code = number of [FAIL] lines (0 = ready to build and test). The setup.ps1 at the kit's root runs
  this first, then lists missing tools and builds generated/.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File doctor.ps1
  pwsh -File doctor.ps1 -Csdk D:\Reduced_CSDK_12 -Offline
  (CSDK is looked for in -Csdk, $env:DEADLOCK_CSDK, %LOCALAPPDATA%\deadlock-modding\Reduced_CSDK_12, C:\Reduced_CSDK_12.)
#>
param(
  [string]$Csdk,
  [string]$Deadlock,
  [string]$Generated,   # the kit's generated/ folder (default: next to tools/); tests point it elsewhere
  [switch]$Offline
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

$script:fails = 0
function Report([ValidateSet('ok', 'warn', 'fail', 'info')] [string]$Status, [string]$What, [string]$Fix) {
  $color = @{ ok = 'Green'; warn = 'Yellow'; fail = 'Red'; info = 'Gray' }[$Status]
  Write-Host ('[{0,-4}] {1}' -f $Status.ToUpper(), $What) -ForegroundColor $color
  if ($Fix) { Write-Host "       -> $Fix" -ForegroundColor $color }
  if ($Status -eq 'fail') { $script:fails++ }
}

# Text of a top-level-ish KeyValues block "Name { ... }", comments stripped and whitespace collapsed. $null if absent.
function Get-KvBlock([string]$Text, [string]$Name) {
  $m = [regex]::Match($Text, '(?m)^[ \t]*"?' + [regex]::Escape($Name) + '"?[ \t]*(//[^\n]*)?\r?\n[ \t]*\{')
  if (-not $m.Success) { return $null }
  $i = $m.Index + $m.Length; $depth = 1; $sb = New-Object System.Text.StringBuilder
  while ($i -lt $Text.Length -and $depth -gt 0) {
    $c = $Text[$i]
    if ($c -eq '/' -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '/') { while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }; continue }
    if ($c -eq '"') { $j = $Text.IndexOf('"', $i + 1); if ($j -lt 0) { $j = $Text.Length - 1 }; [void]$sb.Append($Text.Substring($i, $j - $i + 1)); $i = $j + 1; continue }
    if ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth-- }
    if ($depth -gt 0) { [void]$sb.Append($c) }
    $i++
  }
  ($sb.ToString() -replace '\s+', ' ').Trim()
}

# Launch options per Steam account, from userdata\<id>\config\localconfig.vdf.
function Get-LaunchOptions {
  $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
  if (-not $steam) { return }
  Get-ChildItem (Join-Path $steam 'userdata') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $cfg = Join-Path $_.FullName 'config\localconfig.vdf'
    if (-not (Test-Path $cfg)) { return }
    $text = Get-Content $cfg -Raw
    foreach ($m in [regex]::Matches($text, '"1422450"\s*\{')) {
      $start = $m.Index + $m.Length; $depth = 1; $i = $start
      while ($i -lt $text.Length -and $depth -gt 0) { if ($text[$i] -eq '{') { $depth++ } elseif ($text[$i] -eq '}') { $depth-- }; $i++ }
      $opt = [regex]::Match($text.Substring($start, $i - $start), '"LaunchOptions"\s*"((?:[^"\\]|\\.)*)"')
      if ($opt.Success) { [pscustomobject]@{ Account = $_.Name; Options = $opt.Groups[1].Value }; break }
    }
  }
}

Write-Host "Deadlock modding doctor`n"

# PowerShell
if ($PSVersionTable.PSVersion.Major -ge 7) { Report ok "PowerShell $($PSVersionTable.PSVersion)" }
elseif (Get-Command pwsh -ErrorAction SilentlyContinue) { Report warn "Running in Windows PowerShell $($PSVersionTable.PSVersion); pwsh 7 is installed" "Run the tools with pwsh, not powershell." }
else { Report fail "PowerShell 7 not installed (the build tools need it)" "winget install Microsoft.PowerShell" }

# Install and build
$root = $null
try { $root = $(if ($Deadlock) { $Deadlock } else { Find-DeadlockRoot }) } catch { }
if (-not $root -or -not (Test-Path (Join-Path $root 'game\citadel\gameinfo.gi'))) {
  Report fail "Deadlock install not found" "Install Deadlock through Steam, or pass -Deadlock '<library>\steamapps\common\Deadlock'."
}
else {
  $build = Get-DeadlockBuild $root
  Report ok "Deadlock at $root (build $build)"

  # generated/ (data rendered from the game files): each file's first line names the build it was read from.
  if (-not $Generated) { $Generated = Join-Path (Split-Path $PSScriptRoot) 'generated' }
  $genBuild = Get-GeneratedBuild $Generated
  if ($genBuild -eq $build) { Report ok "generated/ describes build $build" }
  else {
    $genWhat = $(if ($genBuild) { "describes build $genBuild" } else { 'is missing' })
    Report warn "generated/ $genWhat, the game is build $build" "Run setup.ps1 in the kit's root folder (or pwsh -File generate-docs.ps1, or the MCP catalog_refresh action; 1-2 minutes)"
  }
  if (Get-Process -Name deadlock -ErrorAction SilentlyContinue) { Report info "Deadlock is running (close it before installing mods; it locks its files)" }

  # gameinfo.gi
  $giPath = Join-Path $root 'game\citadel\gameinfo.gi'
  $gi = Get-Content $giPath -Raw
  $searchPaths = Get-KvBlock $gi 'SearchPaths'
  if ($searchPaths -match '(^| )Game citadel/addons( |$)') { Report ok "gameinfo.gi mounts citadel/addons" }
  else { Report fail "gameinfo.gi does not mount citadel/addons (mods won't load)" "With Deadlock closed: pwsh -File enable-addons.ps1" }

  $guarded = 'Engine2', 'MaterialSystem2', 'NetworkSystem', 'Particles', 'RenderSystem', 'SceneSystem', 'WorldRenderer'
  if ($Offline) { Report info "Skipped comparing guarded gameinfo.gi sections with Valve's (-Offline)" }
  else {
    try {
      $gtInf = (Invoke-WebRequest "$script:GameTrackingBase/steam.inf" -UseBasicParsing -TimeoutSec 15).Content
      $gtBuild = [int][regex]::Match($gtInf, '(?m)^ClientVersion=(\d+)').Groups[1].Value
      if ($gtBuild -ne $build) { Report info "Can't compare gameinfo.gi with Valve's: GameTracking is on build $gtBuild, you have $build" }
      else {
        $vanilla = (Invoke-WebRequest "$script:GameTrackingBase/gameinfo.gi" -UseBasicParsing -TimeoutSec 15).Content
        $changed = @($guarded | Where-Object { (Get-KvBlock $gi $_) -ne (Get-KvBlock $vanilla $_) })
        if ($changed) {
          Report warn "gameinfo.gi sections that matchmaking checks differ from Valve's: $($changed -join ', ')" "Usually a 'performance config'. If queueing fails with a gameinfo error: Steam > Deadlock > Properties > Installed Files > Verify, then re-run enable-addons.ps1 (docs/01-how-mods-load.md)."
        }
        else { Report ok "Matchmaking-guarded gameinfo.gi sections match Valve's build $build" }
      }
    }
    catch { Report info "Couldn't download Valve's gameinfo.gi from GameTracking to compare ($($_.Exception.Message))" }
  }

  # Game catalogs (sounds, heroes, UI) for this build
  $catalog = Join-Path $script:KitHome "catalog\$build"
  if (Test-Path (Join-Path $catalog 'README.md')) { Report ok "Game catalogs for build $build at $catalog" }
  else { Report warn "No game catalogs for build $build (searchable lists of sounds, heroes and UI panels)" "pwsh -File catalog.ps1 (needs Source2Viewer-CLI; 1-2 minutes)" }

  # Installed mods
  $addons = Join-Path $root 'game\citadel\addons'
  $paks = @(Get-ChildItem $addons -Filter 'pak*_dir.vpk' -File -ErrorAction SilentlyContinue)
  $registry = Get-PakRegistry
  $ours = @($paks | Where-Object { $registry.ContainsKey($_.Name) })
  Report info "$($paks.Count) mod pak(s) installed, $($ours.Count) built with these tools. Details: pwsh -File mods.ps1"
}

# Build tools
$Csdk = Find-Csdk $Csdk
$compiler = Join-Path $Csdk 'game\bin_cs2\win64\resourcecompiler.exe'
$packer = Join-Path $Csdk 'game\bin\win64\CSDKCfgVPK.exe'
if ((Test-Path $compiler) -and (Test-Path $packer)) {
  Report ok "Reduced CSDK 12 at $Csdk"
  if ($Csdk -match 'OneDrive' -or ($root -and $Csdk.StartsWith($root, 'OrdinalIgnoreCase'))) { Report warn "CSDK is under OneDrive or the game folder" "Reinstall it with setup.ps1, which puts it in $script:KitHome (docs/02-toolchain.md)." }
  if (-not (Test-Path (Join-Path $Csdk 'game\citadel'))) { Report warn "CSDK has no game\citadel folder; csdkcfg.exe may never have been run" "Run $Csdk\csdkcfg.exe once (docs/02-toolchain.md)." }
}
else { Report warn "Reduced CSDK 12 not found at $Csdk (needed to compile UI mods and your own audio/art; sound-copy mods build without it)" "pwsh -File setup.ps1 (lists what it installs and asks first). Or pass -Csdk <folder>." }

$s2v = Find-Source2ViewerCli
if ($s2v) { Report ok "Source2Viewer-CLI at $s2v" }
else { Report warn "Source2Viewer-CLI not found (needed for stock models/sounds/textures; Panorama files come from GameTracking without it)" "pwsh -File setup.ps1 (installs it to $script:KitHome\bin)" }

foreach ($tool in @(
    @{ Name = 'node'; Why = 'syntax checks and unit tests for mod scripts'; Fix = 'winget install OpenJS.NodeJS.LTS' },
    @{ Name = 'git'; Why = 'rebase.ps1 merges your changes onto new stock files after a patch'; Fix = 'winget install Git.Git' })) {
  $cmd = Get-Command $tool.Name -ErrorAction SilentlyContinue
  if ($cmd) { Report ok "$($tool.Name) found" } else { Report warn "$($tool.Name) not found ($($tool.Why))" $tool.Fix }
}
if (Find-Gh) { Report ok "GitHub CLI found (optional; only to host your own storage page with store.ps1 -Publish; sign-in is checked there)" }
else { Report info "GitHub CLI not found: optional, only needed to host your own storage page (store.ps1 -Publish); mods use the kit's hosted page by default" "pwsh -File setup.ps1 -Approve gh" }
foreach ($media in @(
    @{ Name = 'yt-dlp'; Path = (Find-YtDlp); Why = 'downloads a sound from a link (YouTube etc.) for audio.ps1' },
    @{ Name = 'ffmpeg'; Path = (Find-Ffmpeg); Why = 'converts any audio file to the WAV a sound mod compiles from (audio.ps1)' })) {
  if ($media.Path) { Report ok "$($media.Name) found (optional; $($media.Why))" }
  else { Report info "$($media.Name) not found: optional, only $($media.Why)" "pwsh -File setup.ps1 -Media (lists it and asks first)" }
}
$blender = Find-Blender
if ($blender) { Report ok "Blender found at $blender (optional; convert-model.ps1 reads .dae/.fbx with it)" }
else { Report info "Blender not found: optional, only to read .dae, .fbx and other 3D files for a model swap (.glb, .gltf and .obj need nothing)" "pwsh -File setup.ps1 -Models (lists it and asks first)" }

# Launch options
$launch = @(Get-LaunchOptions)
if (-not $launch) { Report warn "Deadlock has no launch options, so there's no console.log to debug with" "Steam > Deadlock > Properties > Launch Options: add -condebug" }
foreach ($l in $launch) {
  $o = $l.Options
  if ($o -match '(^|\s)-condebug(\s|$)') { Report ok "Steam account $($l.Account): launch options include -condebug (console.log is written)" }
  else { Report warn "Steam account $($l.Account): no -condebug launch option, so there's no console.log to debug with" "Steam > Deadlock > Properties > Launch Options: add -condebug" }
  if ($o -match '(^|\s)-(tools|dev)(\s|$)') { Report warn "Steam account $($l.Account): launch options include -dev/-tools, which block matchmaking" "Remove them before queueing." }
}

Write-Host ""
if ($script:fails) { Write-Host "$($script:fails) problem(s) to fix before you can build and test mods." -ForegroundColor Red }
else { Write-Host "Ready to build and test mods." -ForegroundColor Green }
exit $script:fails
