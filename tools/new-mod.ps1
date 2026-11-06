#Requires -Version 7

<#
.SYNOPSIS
  Create a new Deadlock mod from a starter that works as-is, builds with build.ps1 -Mod, and is
  ready to turn into your feature (docs/03-panorama.md, docs/09-asset-mods.md, docs/05-dev-loop.md).

.DESCRIPTION
  Makes <Dir>\<Name>\ (default .\mods\<Name> under the current folder) with mod.json, src\ and a README.
  -Kind ui (default): a UI mod. src\ holds a script, a style and the hooked layout; stock\ and test\ too.
    The starter shows a "<name> v0.1.0" badge on the main menu and HUD (needs Reduced CSDK 12 to build).
  -Kind sound: a sound mod that needs NO compiler. Every main-menu hover/click sound (sounds/ui/ui_menu_*)
    becomes the shop purchase sound, copied from your install. The quickest way to prove the pipeline.
  -Kind data: a UI mod that saves data (docs/04 pattern A): a note box on the main menu and HUD whose note
    survives restarts. Adds the storage client script and the address of the storage page it saves
    through; the mod's keys sit under its namespace <name>.v1 on that page.
    Needs -StoreUrl, which the user chooses once, before the mod is made: "kit" for the kit's hosted
    page (it comes with a warning: no guarantee it stays online), or their own https address
    (store.ps1 -Publish can host the kit's page on their GitHub). Without it, new-mod stops and says
    what to ask. The address is permanent: players' saved data stays with it.
  -Kind empty: just mod.json, README and an empty src\ (same as -Hook none).
  - Picks a free pak number (60-97, skipping installed paks, other mods in <Dir> and popular numbers)
    unless -Pak is given.
  - -Hook <layout> (default citadel_hud_and_db_overlay, present on the main menu and in matches)
    fetches that layout's stock file for your build with get-stock.ps1, and overrides it with two
    added lines: a <styles> include and a <scripts> include for this mod (-Kind ui only).
  - Warns if an installed pak already overrides the hook layout.

.EXAMPLE
  .\new-mod.ps1 -Name hello
  .\new-mod.ps1 -Name firstlight -Kind sound
  .\new-mod.ps1 -Name notepad -Kind data -StoreUrl kit
  .\new-mod.ps1 -Name notepad -Kind data -StoreUrl https://someone.github.io/notepad-store/
  .\new-mod.ps1 -Name killsound -Kind empty -Dir D:\mods
  .\new-mod.ps1 -Name escnotes -Hook hud_escape_menu -Pak 66
#>
param(
  [Parameter(Mandatory)] [ValidatePattern('^[a-z][a-z0-9_]{1,30}$')] [string]$Name,
  [ValidateRange(1, 99)] [int]$Pak,
  [ValidateSet('ui', 'data', 'sound', 'empty')] [string]$Kind = 'ui',
  [string]$Hook = 'citadel_hud_and_db_overlay',
  [string]$Dir = '.\mods',
  [string]$StoreUrl,
  [string]$Deadlock
)
$ErrorActionPreference = 'Stop'

# The kit's hosted storage page: one shared page (store/index.html at the kit's root, served by GitHub
# Pages, from the repo github.com/UnExploration/deadlock-mod-storage) that every -Kind data mod can save through. "-StoreUrl kit" means this address; store.ps1 reads it from here.
$KitStoreUrl = 'https://unexploration.github.io/deadlock-mod-storage/'
$StoreWarning = "The kit's storage page is run by the kit's author, free, with no guarantee it stays online. If it goes away, mods that use it stop saving until their maker hosts the page at an address of their own, and data players saved under the old address does not carry over."

if ($Kind -eq 'data' -and -not $StoreUrl) {
  throw @"
-Kind data needs -StoreUrl: the address of the storage page this mod saves through. Ask the user once, before making the mod, and pass their answer:
  1. The kit's page: -StoreUrl kit  ($KitStoreUrl). Free, nothing to set up. Tell them the warning: $StoreWarning
  2. Their own address: -StoreUrl https://<their address>/  On their own GitHub that is https://<their GitHub name>.github.io/$Name-store/, and store.ps1 -Publish then puts the kit's page there.
The choice is permanent: changing the address later loses access to everything players saved under the old one.
"@
}
if ($StoreUrl -and $Kind -ne 'data') { throw "-StoreUrl is only for -Kind data." }
$isKitStore = $false
if ($StoreUrl) {
  if ($StoreUrl -eq 'kit') { $StoreUrl = $KitStoreUrl }
  if ($StoreUrl -notmatch '^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~%!$&()*+,;=:@/-]*)?$') {
    throw "-StoreUrl must be ""kit"" or an https:// address with no spaces, quotes, ? or # (got: $StoreUrl). The game only loads https pages."
  }
  if (-not $StoreUrl.EndsWith('/')) { $StoreUrl += '/' }
  $isKitStore = $StoreUrl -eq $KitStoreUrl
}

. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')
if ($Hook -eq 'none' -and $Kind -eq 'ui') { $Kind = 'empty' }
if ($Hook -eq 'none' -and $Kind -eq 'data') { throw "-Kind data needs a hook layout." }

if (-not $Deadlock) { $Deadlock = Find-DeadlockRoot }
$build = Get-DeadlockBuild $Deadlock
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$modDir = Join-Path (Resolve-Path $Dir).Path $Name
if (Test-Path $modDir) { throw "$modDir already exists." }

# Pak numbers in use: installed (enabled or disabled), recorded by build.ps1, or claimed by sibling mods.
$used = [System.Collections.Generic.HashSet[int]]::new()
foreach ($d in @('addons', 'addons_disabled')) {
  Get-ChildItem (Join-Path $Deadlock "game\citadel\$d") -Filter 'pak*_dir.vpk' -ErrorAction SilentlyContinue |
    Where-Object Name -match '^pak(\d\d)_dir\.vpk$' | ForEach-Object { [void]$used.Add([int]$Matches[1]) }
}
(Get-PakRegistry).Keys | Where-Object { $_ -match '^pak(\d\d)_dir\.vpk$' } | ForEach-Object { [void]$used.Add([int]$Matches[1]) }
Get-ChildItem $Dir -Filter mod.json -Recurse -Depth 1 -ErrorAction SilentlyContinue | ForEach-Object {
  try { [void]$used.Add([int](Get-Content $_.FullName -Raw | ConvertFrom-Json).pak) } catch { }
}
if (-not $Pak) {
  $Pak = 60..97 | Where-Object { -not $used.Contains($_) -and $script:PopularPaks -notcontains $_ } | Select-Object -First 1
  if (-not $Pak) { throw "No free pak number in 60-97; pass -Pak." }
}
elseif ($used.Contains($Pak)) { Write-Warning "pak$('{0:D2}' -f $Pak) is already used by an installed mod or another mod in $Dir." }

# Copy the starter, renaming __NAME__ in paths and filling the tokens in text files.
$template = Join-Path $PSScriptRoot ('..\templates\' + @{ ui = 'starter'; data = 'starter-data'; sound = 'starter-sound'; empty = 'starter-empty' }[$Kind])
$tokens = @{ '__NAME__' = $Name; '__PAK__' = ('{0:D2}' -f $Pak); '__BUILD__' = "$build"; '__HOOK__' = "panorama/layout/$Hook.xml" }
if ($Kind -eq 'data') {
  $tokens['__STOREURL__'] = $StoreUrl
  $tokens['__STORE_OWNER__'] = $(if ($isKitStore) { "the kit's hosted page, run by the author of deadlock-ai-mod-kit" } else { 'your own address' })
  $tokens['__STORE_WARNING__'] = $(if ($isKitStore) { "**Warning:** $StoreWarning" } else { '' })
}
$utf8 = New-Object System.Text.UTF8Encoding $false
foreach ($file in Get-ChildItem $template -Recurse -File -Force) {
  $rel = [IO.Path]::GetRelativePath((Resolve-Path $template).Path, $file.FullName).Replace('__NAME__', $Name)
  $dest = Join-Path $modDir $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  $text = [IO.File]::ReadAllText($file.FullName)
  foreach ($t in $tokens.GetEnumerator()) { $text = $text.Replace($t.Key, $t.Value) }
  if ($file.Extension -eq '.md') { $text = $text -replace '(\r?\n){3,}', '$1$1' }   # an emptied token line leaves no gap
  [IO.File]::WriteAllText($dest, $text, $utf8)
}

$overrides = @()
New-Item -ItemType Directory -Force -Path (Join-Path $modDir 'src') | Out-Null
if ($Kind -in 'ui', 'data') {
  $layout = "panorama/layout/$Hook.xml"
  $stockDir = Join-Path $modDir 'stock'
  & (Join-Path $PSScriptRoot 'get-stock.ps1') $layout -Out $stockDir -Deadlock $Deadlock
  if ($LASTEXITCODE) { throw "Couldn't get the stock $layout (see above). Fix that, or re-run with -Hook none." }

  # Add this mod's style and script includes; everything else stays byte-identical to stock.
  $xml = [IO.File]::ReadAllText((Join-Path $stockDir $layout))
  $nl = $(if ($xml.Contains("`r`n")) { "`r`n" } else { "`n" })
  $styleInclude = "<include src=`"s2r://panorama/styles/$Name.vcss_c`" />"
  # data: the storage client and the page address load before the feature script that uses them.
  $scripts = $(if ($Kind -eq 'data') { @("${Name}_kvbridge", "${Name}_store", $Name) } else { @($Name) })
  $stylesEnd = [regex]::Match($xml, '(?m)^([ \t]*)</styles>')
  if (-not $stylesEnd.Success) { throw "$layout has no <styles> block; add the includes by hand (docs/03-panorama.md)." }
  $indent = $stylesEnd.Groups[1].Value
  $xml = $xml.Insert($stylesEnd.Index, "$indent`t$styleInclude$nl")
  $scriptsEnd = [regex]::Match($xml, '(?m)^[ \t]*</scripts>')
  $scriptLines = ($scripts | ForEach-Object { "$indent`t<include src=`"s2r://panorama/scripts/$_.vjs_c`" />$nl" }) -join ''
  if ($scriptsEnd.Success) { $xml = $xml.Insert($scriptsEnd.Index, $scriptLines) }
  else {
    $after = [regex]::Match($xml, '(?m)^[ \t]*</styles>[^\n]*\n')
    $xml = $xml.Insert($after.Index + $after.Length, "$indent<scripts>$nl$scriptLines$indent</scripts>$nl")
  }
  $dest = Join-Path $modDir "src/$layout"
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
  [IO.File]::WriteAllText($dest, $xml, $utf8)
  $overrides += $layout

  # Does an installed mod already replace this layout? Lower pak numbers win the whole file.
  $compiled = "panorama/layout/$Hook.vxml_c"
  Get-ChildItem (Join-Path $Deadlock 'game\citadel\addons') -Filter 'pak*_dir.vpk' -ErrorAction SilentlyContinue | ForEach-Object {
    if (Read-VpkTree $_.FullName $compiled | Where-Object Path -eq $compiled) {
      $n = [int]($_.Name -replace '\D', '')
      $who = $(if ($n -lt $Pak) { "and wins over this mod (lower number), so $Name won't load until one of you moves" } else { "and loses to this mod, so that mod's change to it will stop working" })
      Write-Warning "Installed $($_.Name) also overrides $compiled $who. Consider another -Hook (docs/12-ui-hooks.md)."
    }
  }
}
if ($Kind -eq 'data') {
  # The kit's storage client. The page is shared (the kit's store/index.html); the mod only carries its address.
  Copy-Item (Join-Path $PSScriptRoot '..\templates\kv-bridge\kvbridge.js') (Join-Path $modDir "src\panorama\scripts\${Name}_kvbridge.js")
}
elseif ($Kind -eq 'sound') {
  # One compiled game sound copied over every main-menu UI sound: same folder, as shipping sound mods do.
  $gameVpk = Get-GameVpk $Deadlock
  $donorPath = 'sounds/ui/ui_shop_purchase_item_01.vsnd_c'
  $donor = Read-VpkTree $gameVpk $donorPath | Where-Object Path -eq $donorPath
  $targets = @(Read-VpkTree $gameVpk 'sounds/ui/ui_menu_' | Where-Object Path -like '*.vsnd_c')
  if (-not $donor -or -not $targets) { throw "Build $build has no $donorPath or sounds/ui/ui_menu_* (a patch renamed them). Pick others with get-stock.ps1 -List sounds/ui/." }
  foreach ($t in $targets) { Export-VpkFile $donor (Join-Path $modDir "src\$($t.Path)") }
  Write-Host "  $($targets.Count) menu sounds -> $donorPath"
}

$manifest = [ordered]@{ name = $Name; kind = $Kind; pak = $Pak; version = '0.1.0'; gameBuild = $build; overrides = $overrides }
if ($Kind -eq 'data') {
  $manifest.store = [ordered]@{ url = $StoreUrl }
  # store.ps1 -Publish swaps these two phrases when a mod moves to its maker's own page: keep them in sync there.
  $runBy = $(if ($isKitStore) { "which the author of deadlock-ai-mod-kit runs (not this mod's maker)" } else { "which this mod's maker runs" })
  $manifest.privacy = "Saved on your PC, in Steam's built-in browser storage (under %LOCALAPPDATA%\Steam\htmlcache). When Deadlock starts, the mod loads its storage page once from $StoreUrl, $runBy; that host sees your IP address, but never your data, which is never sent anywhere. To wipe it: Steam > Settings > In Game > Delete Web Browser Data (this also clears other Steam web data)."
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $modDir 'mod.json') -Encoding utf8

Write-Host "`nCreated $modDir (pak$('{0:D2}' -f $Pak), game build $build)" -ForegroundColor Green
if ($Kind -eq 'data') {
  Write-Host "Storage page: $StoreUrl$(if ($isKitStore) { " (the kit's page)" } else { " (your own address)" })"
  if ($isKitStore) { Write-Host "  $StoreWarning" -ForegroundColor Yellow }
  else { Write-Host "  It must serve the kit's store/index.html before the mod can save (store.ps1 -Mod `"$modDir`" -Publish for your GitHub)." }
  Write-Host "Next:"
  Write-Host "  node --test `"$modDir\test\$Name.test.js`""
  Write-Host "  pwsh -File `"$PSScriptRoot\store.ps1`" -Mod `"$modDir`"     (does the page answer?)"
  Write-Host "  pwsh -File `"$PSScriptRoot\build.ps1`" -Mod `"$modDir`" -Install     (Deadlock closed)"
  Write-Host "Then start Deadlock: a note box shows on the main menu; type, press Enter, restart, and it's still there."
}
elseif ($Kind -eq 'ui') {
  Write-Host "Next (Deadlock closed):"
  Write-Host "  node --test `"$modDir\test\$Name.test.js`""
  Write-Host "  pwsh -File `"$PSScriptRoot\build.ps1`" -Mod `"$modDir`" -Install"
  Write-Host "Then start Deadlock: the badge shows on the main menu, and console.log has '[$Name] loaded'."
}
elseif ($Kind -eq 'sound') {
  Write-Host "Next (Deadlock closed; no compiler needed):"
  Write-Host "  pwsh -File `"$PSScriptRoot\build.ps1`" -Mod `"$modDir`" -Install"
  Write-Host "Then start Deadlock and hover over the main menu buttons: you should hear the shop purchase sound."
}
else { Write-Host "Put files under $modDir\src at their game paths (see the README), then build.ps1 -Mod." }
