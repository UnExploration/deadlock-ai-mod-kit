<#
.SYNOPSIS
  Mount game\citadel\addons in Deadlock's gameinfo.gi (docs/01-how-mods-load.md).

.DESCRIPTION
  Rewrites ONLY the FileSystem -> SearchPaths { ... } block, inserting
      Game citadel/addons / Mod citadel / Write citadel   above   Game citadel
      Mod core / Write core                               above   Game core
  and leaves every other line (including the PGI-guarded sections) byte-identical.
  Idempotent: does nothing if citadel/addons is already mounted. Backs the file up to
  gameinfo.gi.pre-addons.bak first. That backup only matches the build it was taken on;
  after a patch, re-run this script on the new file instead of restoring an old backup.
  Re-run after any patch that resets gameinfo.gi. Keep this file next to deadlock-paths.ps1.

.EXAMPLE
  .\enable-addons.ps1                 # finds Deadlock through Steam's library list
  .\enable-addons.ps1 -GameInfo "D:\SteamLibrary\steamapps\common\Deadlock\game\citadel\gameinfo.gi"
  .\enable-addons.ps1 -Check          # report only, change nothing (exit 0 = mounted, 1 = not)
  .\enable-addons.ps1 -Disable        # remove exactly the lines this script added (mods reset uses it)
#>
param(
  [string]$GameInfo,
  [switch]$Check,
  [switch]$Disable
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

if (-not $GameInfo) { $GameInfo = Join-Path (Find-DeadlockRoot) 'game\citadel\gameinfo.gi' }
if (-not (Test-Path $GameInfo)) { throw "gameinfo.gi not found: $GameInfo" }
$text = [System.IO.File]::ReadAllText($GameInfo)
$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }

$start = [regex]::Match($text, '(?m)^[ \t]*SearchPaths[ \t]*\r?\n[ \t]*\{')
if (-not $start.Success) { throw "SearchPaths block not found. The file format changed; edit by hand (docs/01)." }
# The block ends at the first line that is only '}' (comments inside the block may contain braces).
$closeLine = [regex]::Match($text.Substring($start.Index + $start.Length), '(?m)^[ \t]*\}[ \t]*\r?$')
if (-not $closeLine.Success) { throw "End of SearchPaths block not found; edit by hand (docs/01)." }
$close = $start.Index + $start.Length + $closeLine.Index + $closeLine.Value.IndexOf('}')
$block = $text.Substring($start.Index, $close - $start.Index + 1)

function Write-GameInfo([string]$NewText) {
  if (Test-Path (Join-Path (Split-Path $GameInfo) 'pak01_dir.vpk')) { Assert-DeadlockClosed (Split-Path (Split-Path (Split-Path $GameInfo))) }   # a live install, not a copy
  if ((Get-Item $GameInfo).Attributes -band [IO.FileAttributes]::ReadOnly) { Set-ItemProperty $GameInfo -Name IsReadOnly -Value $false }
  [System.IO.File]::WriteAllText($GameInfo, $NewText, (New-Object System.Text.UTF8Encoding $false))
}

if ($Disable) {
  # The inverse of the insert below (Remove-AddonsMount in deadlock-paths.ps1; generate-docs.ps1 uses it too).
  $newBlock = Remove-AddonsMount $block
  if ($newBlock -eq $block) { Write-Host "citadel/addons is not mounted. Nothing to do." -ForegroundColor Green; exit 0 }
  Write-GameInfo ($text.Substring(0, $start.Index) + $newBlock + $text.Substring($close + 1))
  Write-Host "Unmounted citadel/addons: gameinfo.gi SearchPaths is back to Valve's lines. Mods in addons no longer load." -ForegroundColor Green
  exit 0
}

if ($block -match '(?m)^[ \t]*Game[ \t]+citadel/addons[ \t]*\r?$') {
  Write-Host "citadel/addons is already mounted. Nothing to do." -ForegroundColor Green
  exit 0
}
if ($Check) { Write-Host "citadel/addons is NOT mounted (mods will not load)." -ForegroundColor Yellow; exit 1 }

$gameCitadel = [regex]::Match($block, '(?m)^([ \t]*)Game([ \t]+)citadel[ \t]*\r?$')   # \r?: gameinfo.gi is CRLF
$gameCore = [regex]::Match($block, '(?m)^([ \t]*)Game([ \t]+)core[ \t]*\r?$')
if (-not $gameCitadel.Success -or -not $gameCore.Success) { throw "Expected 'Game citadel' and 'Game core' lines in SearchPaths; edit by hand (docs/01)." }

$indent = $gameCitadel.Groups[1].Value
$gap = $gameCitadel.Groups[2].Value
$hasMod = $block -match '(?m)^[ \t]*Mod[ \t]+'
$hasWrite = $block -match '(?m)^[ \t]*Write[ \t]+'

$beforeCitadel = "${indent}Game${gap}citadel/addons$nl"
if (-not $hasMod) { $beforeCitadel += "${indent}Mod${gap}citadel$nl" }
if (-not $hasWrite) { $beforeCitadel += "${indent}Write${gap}citadel$nl" }
$beforeCore = ""
if (-not $hasMod) { $beforeCore += "${indent}Mod${gap}core$nl" }
if (-not $hasWrite) { $beforeCore += "${indent}Write${gap}core$nl" }

# Insert bottom-up so the earlier match index stays valid.
$newBlock = $block.Insert($gameCore.Index, $beforeCore).Insert($gameCitadel.Index, $beforeCitadel)
$newText = $text.Substring(0, $start.Index) + $newBlock + $text.Substring($close + 1)

Copy-Item $GameInfo "$GameInfo.pre-addons.bak" -Force
Write-GameInfo $newText

$addons = Join-Path (Split-Path $GameInfo) 'addons'
if (-not (Test-Path $addons)) { New-Item -ItemType Directory -Path $addons | Out-Null }
Write-Host "Mounted citadel/addons. Backup: $GameInfo.pre-addons.bak  Addons folder: $addons" -ForegroundColor Green
