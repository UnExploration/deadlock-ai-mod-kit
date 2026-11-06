<#
.SYNOPSIS
  Install what this PC is missing for Deadlock modding, after the user has approved the list.
  Runs on Windows PowerShell 5.1 too, so it can install PowerShell 7.

.DESCRIPTION
  With no -Approve: prints what's missing (what it is, why, where from, where to, size, warnings)
  and the exact command to install it. Changes nothing. Show this list to the user and get one yes.

  With -Approve <ids>: installs only those ids that are missing. Ids:
    csdk   Reduced CSDK 12 (2.4 GB, unsigned community kit; compiles UI mods and your own audio/art)
           -> %LOCALAPPDATA%\deadlock-modding\Reduced_CSDK_12
    s2v    Source2Viewer-CLI (open source; decompiles game files) -> %LOCALAPPDATA%\deadlock-modding\bin
    node   Node.js LTS (winget; tests mod scripts, runs the MCP server)
    git    Git (winget; merges mods onto new game files after patches)
    pwsh   PowerShell 7 (winget; the build tools need it)
  Optional media tools, listed only with -Media (for sound mods made from a link or any audio file, audio.ps1):
    ytdlp  yt-dlp (open source, unsigned; downloads audio from a link) -> %LOCALAPPDATA%\deadlock-modding\bin
    ffmpeg FFmpeg essentials build by gyan.dev (open source, unsigned; converts audio to WAV) -> same bin folder
  Optional model converter, listed only with -Models (for a model swap from a .dae, .fbx or other 3D file, convert-model.ps1):
    blender Blender 4.5 LTS, portable (reads 3D files headless) -> %LOCALAPPDATA%\deadlock-modding\blender
  Optional, never in the list, installed only by name (-Approve gh):
    gh     GitHub CLI (winget; only to host your own storage page for mods that save data, store.ps1 -Publish)
  "all" approves every missing item in the list shown (media tools only with -Media, Blender only with -Models; never gh).
  Both media tools come from the latest GitHub release and are checked against its SHA-256. Blender comes from
  blender.org's own mirror (mirror.blender.org; download.blender.org refuses scripts), newest 4.5.x, checked
  against the SHA-256 list blender.org publishes beside it. It's pinned to 4.5 because 5.0 removed the .dae importer.

  Kit files live in %LOCALAPPDATA%\deadlock-modding (deleting that folder removes them). Node, git
  and PowerShell 7 are normal system programs, removed in Windows Settings > Apps.

  CSDK comes only from its official Google Drive link (never rehosted). Drive often refuses big
  downloads ("quota exceeded"). Then setup prints the official page; the user downloads
  Reduced_CSDK_12.zip in a browser, and re-running setup finds it in Downloads (or pass -CsdkZip).
  Exit code: 0 = done or nothing to do, 1 = something failed, 2 = waiting for the user's download.
  With -StrictExit the list also exits 2 when anything is missing (waiting for the user's yes); the
  setup.ps1 at the kit's root uses that. It runs this script for you, with the same -Approve, -Media,
  -Models and -CsdkZip, then builds generated/; prefer it from the root folder.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup.ps1                  # the list
  powershell -ExecutionPolicy Bypass -File setup.ps1 -Approve csdk,s2v,pwsh
  pwsh -File setup.ps1 -Approve csdk -CsdkZip "$HOME\Downloads\Reduced_CSDK_12.zip"
  pwsh -File setup.ps1 -Media                                         # the list, with the optional media tools
  pwsh -File setup.ps1 -Approve ytdlp,ffmpeg
  pwsh -File setup.ps1 -Models                                        # the list, with the optional Blender
  pwsh -File setup.ps1 -Approve blender
#>
param(
  [string[]]$Approve,
  [switch]$Media,
  [switch]$Models,
  [string]$CsdkZip,
  [string]$DownloadsDir = (Join-Path $env:USERPROFILE 'Downloads'),
  [switch]$StrictExit   # list mode: exit 2 (not 0) when anything is missing
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12   # Windows PowerShell 5.1 defaults can't reach GitHub   # Invoke-WebRequest is many times slower with the progress bar
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

$CsdkPage = 'https://deadlockmodding.pages.dev/modding-tools/csdk-12'
$CsdkUrl = $(if ($env:DEADLOCK_MODDING_CSDK_URL) { $env:DEADLOCK_MODDING_CSDK_URL } else { 'https://drive.usercontent.google.com/download?id=1-Z-4CszWQNudzwzs6e6abPsp5RGFOURS&export=download&confirm=t' })
$S2vApi = $(if ($env:DEADLOCK_MODDING_S2V_API) { $env:DEADLOCK_MODDING_S2V_API } else { 'https://api.github.com/repos/ValveResourceFormat/ValveResourceFormat/releases/latest' })
$YtDlpApi = $(if ($env:DEADLOCK_MODDING_YTDLP_API) { $env:DEADLOCK_MODDING_YTDLP_API } else { 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest' })
$FfmpegApi = $(if ($env:DEADLOCK_MODDING_FFMPEG_API) { $env:DEADLOCK_MODDING_FFMPEG_API } else { 'https://api.github.com/repos/GyanD/codexffmpeg/releases/latest' })
$BlenderMirror = $(if ($env:DEADLOCK_MODDING_BLENDER_MIRROR) { $env:DEADLOCK_MODDING_BLENDER_MIRROR } else { 'https://mirror.blender.org/release/Blender4.5/' })
$CsdkHome = Join-Path $script:KitHome 'Reduced_CSDK_12'
$KitBin = Join-Path $script:KitHome 'bin'

function Test-Csdk { Test-Path (Join-Path (Find-Csdk) 'game\bin_cs2\win64\resourcecompiler.exe') }
function Get-FreeGB([string]$Dir) {
  $drive = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Dir))
  [Math]::Floor((New-Object IO.DriveInfo $drive).AvailableFreeSpace / 1GB)
}
function Test-Zip([string]$File) {
  if (-not (Test-Path $File)) { return $false }
  $fs = [IO.File]::OpenRead($File)
  try { $b = New-Object byte[] 2; [void]$fs.Read($b, 0, 2); $b[0] -eq 0x50 -and $b[1] -eq 0x4B } finally { $fs.Dispose() }
}
function Invoke-Winget([string]$Id) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget not found. Install 'App Installer' from the Microsoft Store, or install $Id by hand." }
  & winget install --id $Id -e --source winget --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "winget install $Id failed (exit $LASTEXITCODE)" }
}

function Install-S2v {
  $release = Invoke-RestMethod $S2vApi -Headers @{ 'User-Agent' = 'deadlock-ai-mod-kit' }
  $asset = $release.assets | Where-Object name -eq 'cli-windows-x64.zip' | Select-Object -First 1
  if (-not $asset) { throw "Release $($release.tag_name) has no cli-windows-x64.zip" }
  $bin = Join-Path $script:KitHome 'bin'
  New-Item -ItemType Directory -Force -Path $bin | Out-Null
  $zip = Join-Path $script:KitHome 's2v-cli.zip'
  Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
  if ($asset.digest -match '^sha256:([0-9a-f]{64})$') {
    $got = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $Matches[1]) { Remove-Item $zip; throw "Source2Viewer-CLI download is corrupt (SHA-256 $got, expected $($Matches[1]))" }
  }
  Expand-Archive $zip -DestinationPath $bin -Force
  Remove-Item $zip
  if (-not (Test-Path (Join-Path $bin 'Source2Viewer-CLI.exe'))) { throw "Unzipped, but $bin\Source2Viewer-CLI.exe is missing (the release layout changed)." }
  Write-Host "  Source2Viewer-CLI $($release.tag_name) -> $bin" -ForegroundColor Green
}

# Downloads the asset matching $Pattern from a GitHub "latest release" API URL to $OutFile, checked
# against the SHA-256 GitHub publishes for it. Returns the release tag. (file:// URLs: local copies, for tests.)
function Save-Url([string]$Url, [string]$OutFile) {
  if ($Url -like 'file:*') { Copy-Item ([Uri]$Url).LocalPath $OutFile } else { Invoke-WebRequest $Url -OutFile $OutFile -UseBasicParsing }
}
function Save-GitHubAsset([string]$Api, [string]$Pattern, [string]$OutFile) {
  $json = Join-Path $script:KitHome 'release.json'
  New-Item -ItemType Directory -Force -Path $script:KitHome | Out-Null
  if ($Api -like 'file:*') { Save-Url $Api $json; $release = Get-Content $json -Raw | ConvertFrom-Json; Remove-Item $json }
  else { $release = Invoke-RestMethod $Api -Headers @{ 'User-Agent' = 'deadlock-ai-mod-kit' } }
  $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
  if (-not $asset) { throw "Release $($release.tag_name) has no file matching $Pattern (the release layout changed)." }
  if ($asset.digest -notmatch '^sha256:([0-9a-f]{64})$') { throw "Release $($release.tag_name) publishes no SHA-256 for $($asset.name); not installing an unchecked download." }
  $want = $Matches[1]
  Save-Url $asset.browser_download_url $OutFile
  $got = (Get-FileHash $OutFile -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $want) { Remove-Item $OutFile; throw "$($asset.name) download is corrupt (SHA-256 $got, expected $want)" }
  $release.tag_name
}

function Install-YtDlp {
  New-Item -ItemType Directory -Force -Path $KitBin | Out-Null
  $tmp = Join-Path $KitBin 'yt-dlp.exe.download'
  $tag = Save-GitHubAsset $YtDlpApi '^yt-dlp\.exe$' $tmp
  Move-Item $tmp (Join-Path $KitBin 'yt-dlp.exe') -Force
  Write-Host "  yt-dlp $tag -> $KitBin" -ForegroundColor Green
}

function Install-Ffmpeg {
  New-Item -ItemType Directory -Force -Path $KitBin | Out-Null
  $zip = Join-Path $script:KitHome 'ffmpeg.zip'
  $tag = Save-GitHubAsset $FfmpegApi '^ffmpeg-.*-essentials_build\.zip$' $zip
  $extract = Join-Path $script:KitHome 'ffmpeg-unzip'
  if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
  try {
    Expand-Archive $zip -DestinationPath $extract -Force
    $exe = Get-ChildItem $extract -Recurse -Filter 'ffmpeg.exe' -File | Where-Object { $_.Directory.Name -eq 'bin' } | Select-Object -First 1
    if (-not $exe) { throw "The FFmpeg zip has no bin\ffmpeg.exe (the release layout changed)." }
    Copy-Item $exe.FullName (Join-Path $KitBin 'ffmpeg.exe') -Force
  }
  finally { Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item $zip -ErrorAction SilentlyContinue }
  Write-Host "  FFmpeg $tag -> $KitBin" -ForegroundColor Green
}

# Newest blender-4.5.N in the release folder: its SHA-256 list names the windows-x64 zip and its hash.
function Install-Blender {
  $base = $BlenderMirror.TrimEnd('/') + '/'
  New-Item -ItemType Directory -Force -Path $script:KitHome | Out-Null
  if ($base -like 'file:*') { $names = @(Get-ChildItem ([Uri]$base).LocalPath -File | ForEach-Object { $_.Name }) }
  else { $names = @([regex]::Matches((Invoke-WebRequest $base -UseBasicParsing -Headers @{ 'User-Agent' = 'deadlock-ai-mod-kit' }).Content, 'blender-\d+\.\d+\.\d+\.sha256') | ForEach-Object { $_.Value }) }
  $sumName = $names | Where-Object { $_ -match '^blender-\d+\.\d+\.\d+\.sha256$' } | Sort-Object { [version]($_ -replace '^blender-|\.sha256$', '') } | Select-Object -Last 1
  if (-not $sumName) { throw "No blender-<version>.sha256 list in $base (the mirror layout changed)." }
  $sumFile = Join-Path $script:KitHome 'blender.sha256'
  Save-Url "$base$sumName" $sumFile
  $line = Get-Content $sumFile | Where-Object { $_ -match '^([0-9a-f]{64})\s+\*?(blender-[\d.]+-windows-x64\.zip)$' } | Select-Object -First 1
  Remove-Item $sumFile
  if (-not $line) { throw "$sumName lists no windows-x64 zip; not installing an unchecked download." }
  [void]($line -match '^([0-9a-f]{64})\s+\*?(\S+)$'); $want = $Matches[1]; $zipName = $Matches[2]
  $zip = Join-Path $script:KitHome 'blender.zip'
  Write-Host "  Downloading $zipName (about 400 MB)..."
  Save-Url "$base$zipName" $zip
  $got = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $want) { Remove-Item $zip; throw "$zipName download is corrupt (SHA-256 $got, expected $want)" }
  $extract = Join-Path $script:KitHome 'blender-unzip'
  if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
  try {
    Write-Host "  Unzipping..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
    $exe = Get-ChildItem $extract -Recurse -Filter 'blender.exe' -File | Select-Object -First 1
    if (-not $exe) { throw "The Blender zip has no blender.exe (the release layout changed)." }
    $dest = Join-Path $script:KitHome 'blender'
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Move-Item $exe.Directory.FullName $dest
  }
  finally { Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item $zip -ErrorAction SilentlyContinue }
  Write-Host "  $($zipName -replace '-windows-x64\.zip$', '') -> $dest" -ForegroundColor Green
}

# Returns $true when installed, $false when the user must download the zip themselves.
function Install-Csdk {
  $zip = $CsdkZip
  $ours = $false
  if (-not $zip) {
    $zip = Get-ChildItem $DownloadsDir -Filter 'Reduced_CSDK_12*.zip' -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Length -gt 1GB -and (Test-Zip $_.FullName) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if ($zip) { Write-Host "  Using $zip" }
  }
  if (-not $zip) {
    if ((Get-FreeGB $script:KitHome) -lt 10) { throw "Less than 10 GB free on $([IO.Path]::GetPathRoot($script:KitHome)). CSDK needs about 2.4 GB to download plus room to unzip." }
    New-Item -ItemType Directory -Force -Path $script:KitHome | Out-Null
    $zip = Join-Path $script:KitHome 'Reduced_CSDK_12.zip'
    $ours = $true
    Write-Host "  Downloading Reduced CSDK 12 (2.4 GB) from its official Google Drive link..."
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    try {
      if ($curl) { & $curl.Source -L -s -S -f -o $zip $CsdkUrl; if ($LASTEXITCODE -ne 0) { throw "curl exit $LASTEXITCODE" } }
      else { Invoke-WebRequest $CsdkUrl -OutFile $zip -UseBasicParsing }
    }
    catch { Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Yellow }
    if (-not (Test-Zip $zip)) {
      $why = 'the download did not complete'
      if ((Test-Path $zip) -and ((Get-Content $zip -TotalCount 40 -ErrorAction SilentlyContinue) -join ' ') -match 'Quota exceeded|Too many users') { $why = "Google Drive's download limit was hit (it resets within 24 hours)" }
      Remove-Item $zip -ErrorAction SilentlyContinue
      Write-Host "  Couldn't download CSDK automatically: $why." -ForegroundColor Yellow
      Write-Host "  -> Open $CsdkPage in your browser, use its download link (Google Drive), and save Reduced_CSDK_12.zip to $DownloadsDir." -ForegroundColor Yellow
      Write-Host "     Then run setup again with -Approve csdk; it finds the zip there. If Drive says 'quota exceeded' in the browser too, try again later." -ForegroundColor Yellow
      return $false
    }
  }
  if (-not (Test-Zip $zip)) { throw "$zip is not a zip file." }
  $extract = Join-Path $script:KitHome 'csdk-unzip'
  if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
  Write-Host "  Unzipping (this takes a few minutes)..."
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
  $compiler = Get-ChildItem $extract -Recurse -Filter 'resourcecompiler.exe' -File | Where-Object { $_.FullName -match '\\game\\bin_cs2\\win64\\resourcecompiler\.exe$' } | Select-Object -First 1
  if (-not $compiler) { Remove-Item $extract -Recurse -Force; throw "$zip doesn't contain game\bin_cs2\win64\resourcecompiler.exe. Is it Reduced CSDK 12?" }
  $kitRoot = $compiler.Directory.Parent.Parent.Parent.FullName   # <root>\game\bin_cs2\win64
  if (Test-Path $CsdkHome) { Remove-Item $CsdkHome -Recurse -Force }
  Move-Item $kitRoot $CsdkHome
  Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
  if ($ours) { Remove-Item $zip }
  Write-Host "  Reduced CSDK 12 -> $CsdkHome" -ForegroundColor Green
  $true
}

$items = @(
  [pscustomobject]@{ Id = 'pwsh'; Name = 'PowerShell 7'; Missing = -not (Get-Command pwsh -ErrorAction SilentlyContinue)
    Why = 'the build tools need it'; From = 'Microsoft, via winget (Microsoft.PowerShell)'; To = 'Program Files (a normal Windows app)'; Size = '~110 MB'; Note = 'may show a Windows admin prompt'
    Install = { Invoke-Winget 'Microsoft.PowerShell'; $true } }
  [pscustomobject]@{ Id = 'csdk'; Name = 'Reduced CSDK 12'; Missing = -not (Test-Csdk)
    Why = 'compiles UI mods and your own sounds/art (mods that only reuse game files work without it)'; From = "the official Google Drive link on $CsdkPage"; To = $CsdkHome; Size = '2.4 GB download, ~10 GB free space needed'
    Note = "UNSIGNED: a community kit made from Valve's CS2 Workshop Tools; Windows SmartScreen may warn about it. No checksum is published"
    Install = { Install-Csdk } }
  [pscustomobject]@{ Id = 's2v'; Name = 'Source2Viewer-CLI'; Missing = -not (Find-Source2ViewerCli)
    Why = 'decompiles game files (models, textures, sounds, layouts)'; From = 'github.com/ValveResourceFormat (open source, checksum-verified)'; To = (Join-Path $script:KitHome 'bin'); Size = '~53 MB'; Note = ''
    Install = { Install-S2v; $true } }
  [pscustomobject]@{ Id = 'node'; Name = 'Node.js LTS'; Missing = -not (Get-Command node -ErrorAction SilentlyContinue)
    Why = "tests mod scripts and runs the kit's MCP server"; From = 'OpenJS Foundation, via winget (OpenJS.NodeJS.LTS)'; To = 'Program Files (a normal Windows app)'; Size = '~30 MB'; Note = 'may show a Windows admin prompt'
    Install = { Invoke-Winget 'OpenJS.NodeJS.LTS'; $true } }
  [pscustomobject]@{ Id = 'git'; Name = 'Git'; Missing = -not (Get-Command git -ErrorAction SilentlyContinue)
    Why = 'merges your mod onto new game files after a Deadlock patch'; From = 'git-scm.com, via winget (Git.Git)'; To = 'Program Files (a normal Windows app)'; Size = '~60 MB'; Note = 'may show a Windows admin prompt'
    Install = { Invoke-Winget 'Git.Git'; $true } }
  [pscustomobject]@{ Id = 'gh'; Name = 'GitHub CLI'; Missing = -not (Find-Gh); Optional = 'hosting'
    Why = 'only needed to host your own storage page (store.ps1 -Publish); mods that save data use the kit''s hosted page by default, and players never need it'; From = 'GitHub, via winget (GitHub.cli)'; To = 'Program Files (a normal Windows app)'; Size = '~40 MB'; Note = 'publishing also needs a free GitHub account; you sign in once with: gh auth login'
    Install = { Invoke-Winget 'GitHub.cli'; $true } }
  [pscustomobject]@{ Id = 'ytdlp'; Name = 'yt-dlp'; Optional = 'media'; Missing = -not (Find-YtDlp)
    Why = 'optional: downloads the audio of a link (YouTube etc.) the user wants as a sound (audio.ps1)'; From = 'github.com/yt-dlp/yt-dlp, latest release (open source, checksum-verified)'; To = $KitBin; Size = '~24 MB'
    Note = 'UNSIGNED single exe; some antivirus tools flag it by mistake. Only download clips the user may use'
    Install = { Install-YtDlp; $true } }
  [pscustomobject]@{ Id = 'ffmpeg'; Name = 'FFmpeg'; Optional = 'media'; Missing = -not (Find-Ffmpeg)
    Why = 'optional: converts, trims and evens out the loudness of any audio file into the WAV a sound mod compiles from (audio.ps1)'; From = 'gyan.dev essentials build, github.com/GyanD/codexffmpeg latest release (open source, checksum-verified)'; To = $KitBin; Size = '~115 MB download, ~100 MB installed'
    Note = 'UNSIGNED; only ffmpeg.exe is kept'
    Install = { Install-Ffmpeg; $true } }
  [pscustomobject]@{ Id = 'blender'; Name = 'Blender 4.5 LTS (portable)'; Optional = 'models'; Missing = -not (Find-Blender)
    Why = 'optional: reads .dae, .fbx and other 3D files for a model swap (convert-model.ps1). Models as .glb, .gltf or .obj need nothing extra'; From = "mirror.blender.org (blender.org's own download server), newest 4.5 LTS release, checked against blender.org's published SHA-256 list"; To = (Join-Path $script:KitHome 'blender'); Size = '~400 MB download, over 1 GB unpacked'
    Note = "Pinned to 4.5: Blender 5.0 removed the .dae importer. Portable: nothing is installed system-wide; delete the folder to remove it"
    Install = { Install-Blender; $true } }
)
$named = @($Approve | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() })
$groups = @{ media = [bool]$Media; models = [bool]$Models }
$missing = @($items | Where-Object { $_.Missing -and (-not $_.Optional -or $groups[$_.Optional] -or $named -contains $_.Id) })
$optionalHint = @($items | Where-Object { $_.Missing -and $_.Optional -and -not $groups[$_.Optional] })
function Write-OptionalHint {
  $media = @($optionalHint | Where-Object { $_.Optional -eq 'media' }); $model = @($optionalHint | Where-Object { $_.Optional -eq 'models' })
  if ($media) { Write-Host "Optional, for sound mods made from a link or any audio file: $(($media | ForEach-Object Name) -join ', '). To list them: setup.ps1 -Media" }
  if ($model) { Write-Host "Optional, for model swaps from a .dae, .fbx or other 3D file: $(($model | ForEach-Object Name) -join ', '). To list it: setup.ps1 -Models" }
  if ($optionalHint | Where-Object { $_.Optional -eq 'hosting' }) { Write-Host "Optional, only to host your own storage page for mods that save data (store.ps1 -Publish): GitHub CLI. To install it: setup.ps1 -Approve gh" }
}

if (-not $Approve) {
  if (-not $missing) { Write-Host "Nothing to install: every tool is present. Run doctor.ps1 for the full check." -ForegroundColor Green; Write-OptionalHint; exit 0 }
  Write-Host "This PC is missing $($missing.Count) item(s). Nothing is installed until the user approves:`n"
  foreach ($i in $missing) {
    Write-Host "[$($i.Id)] $($i.Name)" -ForegroundColor Cyan
    Write-Host "    why:   $($i.Why)"
    Write-Host "    from:  $($i.From)"
    Write-Host "    to:    $($i.To)"
    Write-Host "    size:  $($i.Size)"
    if ($i.Note) { Write-Host "    note:  $($i.Note)" -ForegroundColor Yellow }
  }
  Write-Host "`nKit files go in $($script:KitHome); delete that folder to remove them."
  Write-Host "To install after the user says yes:`n  setup.ps1 -Approve $(($missing | ForEach-Object Id) -join ',')"
  Write-OptionalHint
  exit $(if ($StrictExit) { 2 } else { 0 })
}

$ids = @($Approve | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
$unknown = @($ids | Where-Object { $_ -ne 'all' -and $_ -notin $items.Id })
if ($unknown) { throw "Unknown id(s): $($unknown -join ', '). Use: $($items.Id -join ', '), all" }
$todo = @($missing | Where-Object { $ids -contains 'all' -or $ids -contains $_.Id })
if (-not $todo) { Write-Host "Nothing to install: the approved items are already present." -ForegroundColor Green; exit 0 }

$failed = 0; $waiting = 0
foreach ($i in $todo) {
  Write-Host "Installing $($i.Name)..." -ForegroundColor Cyan
  try { if (-not (& $i.Install)) { $waiting++ } }
  catch { $failed++; Write-Host "  $($i.Name) failed: $($_.Exception.Message)" -ForegroundColor Red }
}
Write-Host ""
if ($failed) { Write-Host "$failed item(s) failed (see above)." -ForegroundColor Red; exit 1 }
if ($waiting) { Write-Host "Waiting for the CSDK download (see above). Everything else is installed." -ForegroundColor Yellow; exit 2 }
Write-Host "Done. Open a new terminal if you installed Node, git or PowerShell 7 (so PATH updates), then run doctor.ps1." -ForegroundColor Green
if ($todo.Id -contains 'ffmpeg') { Write-Host "Next: pwsh -File audio.ps1 <file or link> -Out <wav> turns a clip into a sound-mod WAV." }
if ($todo.Id -contains 'blender') { Write-Host "Next: pwsh -File convert-model.ps1 -In <model file> -Out <mod src folder> turns a 3D file into what a model swap compiles from." }
if ($todo.Id -contains 's2v') { Write-Host "Next: setup.ps1 in the kit's root folder (or pwsh -File generate-docs.ps1) reads the game data into generated/ (1-2 minutes)." }
exit 0
