#Requires -Version 7

<#
.SYNOPSIS
  Package a mod for sharing: a GameBanana-ready zip, plus an upload checklist (docs/06-distribution.md).
  Run with PowerShell 7:  pwsh -File export.ps1 -Mod <folder>

.DESCRIPTION
  1. Builds the mod (build.ps1 -Mod, no install) unless -NoBuild, then checks the VPK for what has
     broken shipping mods (docs/06-distribution.md): raw sources or build leftovers, a
     gameinfo.gi, core game data (scripts/*.vdata_c), image_compiler.vdata_c. Those stop the export.
  2. Warns when the mod isn't verified in-game on the installed build (mod.json "verified"), when
     its pak number is one popular mods use, or when mod.json has no "description".
  3. Writes <Out>\<name>-<version>-b<build>.zip with pakNN_dir.vpk, README.txt and LICENSE.txt, and
     <Out>\<name>-gamebanana.md: what to fill in on the upload page. The user uploads it themselves.

  mod.json fields used: name, pak, version, verified, description (what it does, in the author's
  words), author, license (default MIT), privacy (for mods that save data: what is stored and where).

.EXAMPLE
  pwsh -File export.ps1 -Mod .\mods\killsound
#>
param(
  [Parameter(Mandatory)] [string]$Mod,
  [string]$Out,
  [string]$Deadlock,
  [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

$manifestPath = Join-Path $Mod 'mod.json'
if (-not (Test-Path $manifestPath)) { throw "$manifestPath not found. Export works on mods made with new-mod.ps1." }
$m = Get-Content $manifestPath -Raw | ConvertFrom-Json
$version = $(if ($m.version) { $m.version } else { '0.1.0' })
$author = $(if ($m.author) { $m.author } else { '<your name>' })
$license = $(if ($m.license) { $m.license } else { 'MIT' })
if (-not $Out) { $Out = Join-Path $Mod 'export' }
$root = $(if ($Deadlock) { $Deadlock } else { try { Find-DeadlockRoot } catch { $null } })
$build = $(if ($root) { Get-DeadlockBuild $root } else { $m.gameBuild })

if ($m.store -and -not $m.store.url) { throw "This mod saves data but has no storage page address, so it would save nothing for players. Remake it with new-mod.ps1 -StoreUrl (kit, or the user's own address), or run store.ps1 -Mod $Mod -Publish for an own address; then rebuild and re-test." }
if (-not $NoBuild) {
  Write-Host "Building $($m.name)..." -ForegroundColor Cyan
  $buildArgs = @{ Mod = $Mod }; if ($root) { $buildArgs.Deadlock = $root }
  & (Join-Path $PSScriptRoot 'build.ps1') @buildArgs | Out-Null
}
$vpkName = "pak{0:D2}_dir.vpk" -f $m.pak
$vpk = Join-Path $Mod "dist\$vpkName"
if (-not (Test-Path $vpk)) { throw "No $vpk. Build the mod first (build.ps1 -Mod $Mod)." }

Write-Host "Checking $vpkName" -ForegroundColor Cyan
$entries = @(Read-VpkTree $vpk)
$errors = @(); $warnings = @()
foreach ($e in $entries) {
  $p = $e.Path
  if ($p -match '(^|/)gameinfo\.gi$') { $errors += "$p : never ship gameinfo.gi; it breaks every other mod and matchmaking" }
  elseif ($p -match '(^|/)node_modules/') { $errors += "$p : build leftover" }
  elseif ($p -match '(^|/)image_compiler\.vdata_c$') { $errors += "$p : compiler leftover that overrides a real game file" }
  elseif (-not $p.EndsWith('_c')) { $errors += "$p : not a compiled file, so the game ignores it (a leftover?)" }
  elseif ($p -match '^scripts/.+\.vdata_c$') { $errors += "$p : core game data; it breaks with every patch and can change gameplay" }
}
if ($errors) { $errors | ForEach-Object { Write-Host "  ERROR $_" -ForegroundColor Red }; throw "Export stopped: fix the files above in $Mod\src (or mod.json copies)." }

if ($null -eq $m.verified) { $warnings += "Not verified in-game yet. Test it (and set mod.json ""verified"": $build) before sharing." }
elseif ($build -and $m.verified -ne $build) { $warnings += "Verified on build $($m.verified), but the game is $build. Re-test before sharing." }
if ($script:PopularPaks -contains [int]$m.pak) { $warnings += "pak$($m.pak) is used by popular mods; players with those get a clash. Pick another with new-mod's numbering." }
if (-not $m.description) { $warnings += "mod.json has no ""description"". Write one sentence, in your own words, about what the mod does." }
if ($author -eq '<your name>') { $warnings += "mod.json has no ""author"": README.txt and LICENSE.txt say <your name>." }

# Which files replace game files, and which are new.
$replaced = @(); $added = @()
$gameVpk = $(if ($root) { try { Get-GameVpk $root } catch { $null } })
if ($gameVpk) {
  $game = @{}; foreach ($g in (Read-VpkTree $gameVpk)) { $game[$g.Path] = $true }
  foreach ($e in $entries) { if ($game[$e.Path]) { $replaced += $e.Path } else { $added += $e.Path } }
}
else { $added = @($entries.Path) }

$date = (Get-Date).ToString('yyyy-MM-dd')
$tested = $(if ($null -ne $m.verified) { "Tested in-game on Deadlock build $($m.verified)." } else { "Not yet tested in-game (built for Deadlock build $build)." })
$zipBuild = $(if ($null -ne $m.verified) { $m.verified } else { $build })
$what = $(if ($m.description) { $m.description } else { '<What the mod does, in your own words.>' })
$readme = @"
$($m.name) $version
$tested Packaged $date.
By $author.

WHAT IT DOES
$what

FILES IT CHANGES
$(if ($replaced) { "Replaces these game files (any other mod replacing them conflicts):`r`n" + (($replaced | ForEach-Object { "  $_" }) -join "`r`n") } else { 'Replaces no game files.' })
$(if ($added) { "Adds:`r`n" + (($added | ForEach-Object { "  $_" }) -join "`r`n") + "`r`n" })
INSTALL
With Deadlock Mod Manager or Grimoire: install from GameBanana with one click.
By hand:
  1. Copy $vpkName into Deadlock\game\citadel\addons\ (make the folder if it's missing).
     If that file name is taken, rename it to any free pakNN_dir.vpk. A lower number wins conflicts.
  2. Deadlock\game\citadel\gameinfo.gi must load addons. Mod managers do this for you. By hand:
     in its SearchPaths block, add these three lines directly above the first "Game citadel" line:
       Game              citadel/addons
       Mod               citadel
       Write             citadel
     Keep Valve's other lines as they are; don't paste a whole block from an old guide.
  3. Restart Deadlock.
$(if ($m.privacy) { "`r`nDATA AND PRIVACY`r`n$($m.privacy)`r`n" })
UNINSTALL
Delete $vpkName from the addons folder. To undo the gameinfo.gi edit: Steam > Deadlock >
Properties > Installed Files > Verify integrity of game files.

AFTER A DEADLOCK PATCH
If the game says "Unable to load layout file" or a feature is missing, remove this mod and check
for an update.

CREDITS
Made with assistance from an AI coding agent using deadlock-ai-mod-kit; reviewed and tested by $author.
License: $license (covers the author's own additions; modified Valve files remain Valve's).
"@
$year = (Get-Date).Year
$licenseText = $(if ($license -eq 'MIT') { @"
MIT License

Copyright (c) $year $author

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

This license covers only the author's own additions. Files modified from Deadlock remain Valve's.
"@ } else { "License: $license. Copyright (c) $year $author.`r`nThis covers only the author's own additions. Files modified from Deadlock remain Valve's." })

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$staging = Join-Path $Out '.staging'
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null
Copy-Item $vpk (Join-Path $staging $vpkName)
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $staging 'README.txt'), ($readme -replace "`r?`n", "`r`n"), $utf8)
[IO.File]::WriteAllText((Join-Path $staging 'LICENSE.txt'), ($licenseText -replace "`r?`n", "`r`n"), $utf8)
$zip = Join-Path $Out ("{0}-{1}-b{2}.zip" -f $m.name, $version, $zipBuild)
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip
Remove-Item $staging -Recurse -Force

$category = $(switch ($m.kind) { 'sound' { 'Sounds' } 'ui' { 'HUD' } default { '<pick the closest category>' } })
$guide = @"
# Uploading $($m.name) to GameBanana

The zip is ready: ``$(Split-Path $zip -Leaf)``. You upload it yourself: https://gamebanana.com/games/20948 → Add → Mod.

## Fill in

- **Name:** $($m.name)
- **Category:** $category
- **Description:** write it yourself, in your own words. GameBanana bans AI-written descriptions (rule R-DL.847). Say what it does, which screens it changes, and which game build you tested it on.
- **AI disclosure** (required for AI-assisted code), e.g.: "Code written with assistance from Claude (Anthropic), reviewed and tested by $author."
- **Screenshots:** at least 2 real in-game screenshots (rule R-DL.839). The first one is the thumbnail. No AI-made images.
- **Credits module:** you, plus anyone whose work you reused.
- **File:** upload the zip; give it a description and version $version.
- **Start private**, check the page, then publish.

## Before you submit

$(if ($warnings) { ($warnings | ForEach-Object { "- ⚠ $_" }) -join "`n" } else { '- No warnings.' })
- A largely AI-written mod is at the moderators' discretion. Ask in the GameBanana Deadlock Discord first (discord.gg/CaNPxMQeFN).
- No executables in the zip (this tool never adds any).
$(if ($replaced) { "- Conflicts: any mod that replaces these files: " + (($replaced | ForEach-Object { "``$_``" }) -join ', ') + '.' })

## Updating later

Edit → Media → upload the new zip at the top and archive the old one, then Add Update with the version and a changelog that names the game patch.
"@
$guidePath = Join-Path $Out "$($m.name)-gamebanana.md"
[IO.File]::WriteAllText($guidePath, $guide, $utf8)

foreach ($w in $warnings) { Write-Warning $w }
Write-Host "Exported $zip" -ForegroundColor Green
Write-Host "  contains $vpkName ($($entries.Count) files), README.txt, LICENSE.txt"
Write-Host "Upload steps: $guidePath"
