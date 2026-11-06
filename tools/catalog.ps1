#Requires -Version 7

<#
.SYNOPSIS
  Generate searchable catalogs of the installed Deadlock build: files, sounds, sound events, heroes, UI layouts, models.

.DESCRIPTION
  Writes tab-separated files (first line = column names) to %LOCALAPPDATA%\deadlock-modding\catalog\<build>\
  and prints that folder. Search them with grep/Select-String; open README.md there for what each holds.
  Needs Source2Viewer-CLI (setup.ps1 installs it). Takes 1-2 minutes; skips a build already
  catalogued unless -Force. Re-run after every Deadlock patch (the doctor says when it's missing).

    files.tsv        every file in pak01_dir.vpk: path, bytes
    soundevents.tsv  every sound event: event, its .vsndevts file, the .vsnd_c files it picks from, duration
    sounds.tsv       every .vsnd_c: path, bytes, the events that play it (empty = no event found)
    heroes.tsv       every hero: codename, display name, id, state, model, sound scripts, abilities 1-4
    ui.tsv           every Panorama layout: path, root panel, panel ids, script and style includes
    models.tsv       every .vmdl_c: plain-words aliases, animation kind, skeleton, materials, textures

.EXAMPLE
  pwsh -File catalog.ps1
  pwsh -File catalog.ps1 -Force
  Select-String -Path "$env:LOCALAPPDATA\deadlock-modding\catalog\*\soundevents.tsv" -Pattern 'Lethal'
#>
param(
  [string]$Deadlock,
  [string]$Out,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

if (-not $Deadlock) { $Deadlock = Find-DeadlockRoot }
$build = Get-DeadlockBuild $Deadlock
$pak = Join-Path $Deadlock 'game\citadel\pak01_dir.vpk'
if (-not $Out) { $Out = Join-Path $script:KitHome "catalog\$build" }
if ((Test-Path (Join-Path $Out 'README.md')) -and (Test-Path (Join-Path $Out 'models.tsv')) -and -not $Force) { Write-Host "Build $build is already catalogued (-Force to redo):"; Write-Output $Out; exit 0 }
$s2v = Find-Source2ViewerCli
if (-not $s2v) { throw "Source2Viewer-CLI not found. Install it with setup.ps1 -Approve s2v." }

$tmp = Join-Path ([IO.Path]::GetTempPath()) "dlcatalog_$build"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Out, $tmp | Out-Null

function Write-Tsv([string]$Name, [string[]]$Columns, $Rows) {
  $clean = { param($v) "$v" -replace '[\t\r\n]+', ' ' }
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add($Columns -join "`t")
  foreach ($r in $Rows) { $lines.Add((($Columns | ForEach-Object { & $clean $r.$_ }) -join "`t")) }
  [IO.File]::WriteAllLines((Join-Path $Out $Name), $lines)
  Write-Host ("  {0,-16} {1} rows" -f $Name, ($lines.Count - 1))
}

# Localization tokens ("key" "value") from the game's loose english files.
function Read-Tokens([string[]]$Files) {
  $t = @{}
  foreach ($f in $Files) {
    if (-not (Test-Path $f)) { continue }
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($f), '(?m)^\s*"([^"]+)"\s+"((?:[^"\\]|\\.)*)"')) { $t[$m.Groups[1].Value.ToLower()] = $m.Groups[2].Value }
  }
  $t
}

Write-Host "Cataloguing Deadlock build $build"
$tree = Read-VpkTree $pak
Write-Tsv 'files.tsv' @('path', 'bytes') ($tree | Sort-Object Path | ForEach-Object { [pscustomobject]@{ path = $_.Path; bytes = $_.Bytes } })

Write-Host "  decompiling sound events, hero data and layouts with Source2Viewer-CLI..."
& $s2v -i $pak -f 'soundevents/,scripts/heroes.vdata,panorama/layout/' -e 'vsndevts_c,vdata_c,vxml_c' -o $tmp -d --threads 8 | Out-Null

# Sound events: top-level "Name =" blocks; vsnd_files is a string or a list of strings.
$events = [System.Collections.Generic.List[object]]::new()
$byFile = @{}
foreach ($f in Get-ChildItem (Join-Path $tmp 'soundevents') -Recurse -Filter '*.vsndevts' -File) {
  $rel = 'soundevents/' + [IO.Path]::GetRelativePath((Join-Path $tmp 'soundevents'), $f.FullName).Replace('\', '/')
  $text = [IO.File]::ReadAllText($f.FullName)
  $heads = [regex]::Matches($text, '(?m)^\t([^\s=]+)\s*=\s*$')
  for ($i = 0; $i -lt $heads.Count; $i++) {
    $end = $(if ($i + 1 -lt $heads.Count) { $heads[$i + 1].Index } else { $text.Length })
    $body = $text.Substring($heads[$i].Index, $end - $heads[$i].Index)
    $name = $heads[$i].Groups[1].Value
    $files = @([regex]::Matches($body, '"(sounds/[^"]+?\.vsnd)"') | ForEach-Object { $_.Groups[1].Value + '_c' } | Select-Object -Unique)
    $dur = [regex]::Match($body, 'vsnd_duration\s*=\s*([\d.]+)').Groups[1].Value
    $events.Add([pscustomobject]@{ event = $name; file = $rel; vsnd_files = $files -join ','; duration = $dur })
    foreach ($v in $files) { if (-not $byFile[$v]) { $byFile[$v] = [System.Collections.Generic.List[string]]::new() }; $byFile[$v].Add($name) }
  }
}
Write-Tsv 'soundevents.tsv' @('event', 'file', 'vsnd_files', 'duration') ($events | Sort-Object event)
Write-Tsv 'sounds.tsv' @('path', 'bytes', 'events') ($tree | Where-Object { $_.Path.EndsWith('.vsnd_c') } | Sort-Object Path | ForEach-Object {
    [pscustomobject]@{ path = $_.Path; bytes = $_.Bytes; events = $(if ($byFile[$_.Path]) { ($byFile[$_.Path] | Select-Object -Unique) -join ',' }) } })

# Heroes: top-level hero_* blocks of scripts/heroes.vdata, names from localization.
$loc = Join-Path $Deadlock 'game\citadel\resource\localization'
$tokens = Read-Tokens @((Join-Path $loc 'citadel_gc_hero_names\citadel_gc_hero_names_english.txt'), (Join-Path $loc 'citadel_heroes\citadel_heroes_english.txt'), (Join-Path $loc 'citadel_gc\citadel_gc_english.txt'))
$vdata = [IO.File]::ReadAllText((Join-Path $tmp 'scripts\heroes.vdata'))
$heads = [regex]::Matches($vdata, '(?m)^\t(hero_\w+)\s*=\s*$')
$heroes = for ($i = 0; $i -lt $heads.Count; $i++) {
  $end = $(if ($i + 1 -lt $heads.Count) { $heads[$i + 1].Index } else { $vdata.Length })
  $b = $vdata.Substring($heads[$i].Index, $end - $heads[$i].Index)
  $code = $heads[$i].Groups[1].Value
  if ($code -eq 'hero_base') { continue }
  $get = { param($k) [regex]::Match($b, "(?m)^\t\t$k\s*=\s*(?:\w+:)?""?([^""\r\n]*)""?").Groups[1].Value.Trim() }
  $state = @()
  if ((& $get 'm_bDisabled') -eq 'true') { $state += 'disabled' }
  if ((& $get 'm_bInDevelopment') -eq 'true') { $state += 'in-development' }
  if ((& $get 'm_bPlayerSelectable') -eq 'false') { $state += 'not-selectable' }
  $abilities = 1..4 | ForEach-Object {
    $a = [regex]::Match($b, "ESlot_Signature_$_\s*=\s*""([^""]+)""").Groups[1].Value
    if ($a) { $n = $tokens[$a.ToLower()]; if ($n) { "$a ($n)" } else { $a } }
  }
  $model = & $get 'm_strModelName'
  [pscustomobject]@{
    codename = $code
    name = $(foreach ($k in "${code}:n", $code) { if ($tokens[$k]) { $tokens[$k]; break } })
    id = & $get 'm_HeroID'
    state = $state -join ','
    model = $model
    model_folder = $(if ($model) { ($model -split '/')[0..2] -join '/' })
    sound_script = & $get 'm_hGameSoundEventScript'
    vo_script = & $get 'm_hGeneratedVOEventScript'
    abilities = $abilities -join ' | '
  }
}
Write-Tsv 'heroes.tsv' @('codename', 'name', 'id', 'state', 'model', 'model_folder', 'sound_script', 'vo_script', 'abilities') $heroes

# UI layouts: root panel, ids, includes.
$layoutDir = Join-Path $tmp 'panorama\layout'
$ui = foreach ($f in Get-ChildItem $layoutDir -Recurse -Filter '*.xml' -File) {
  $x = [IO.File]::ReadAllText($f.FullName)
  $body = $x -replace '(?s)<!--.*?-->', ''
  $afterIncludes = $body -replace '(?s)<(styles|scripts|snippets)>.*?</\1>', ''
  [pscustomobject]@{
    path = 'panorama/layout/' + [IO.Path]::GetRelativePath($layoutDir, $f.FullName).Replace('\', '/')
    root = [regex]::Match($afterIncludes, '<root>\s*<(\w+)').Groups[1].Value
    ids = (@([regex]::Matches($body, '\bid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique) -join ',')
    scripts = (@([regex]::Matches($body, '<include\s+src="([^"]+\.(?:js|vjs|ts|vts))"') | ForEach-Object { $_.Groups[1].Value -replace '^s2r://', '' }) -join ',')
    styles = (@([regex]::Matches($body, '<include\s+src="([^"]+\.(?:css|vcss))"') | ForEach-Object { $_.Groups[1].Value -replace '^s2r://', '' }) -join ',')
  }
}
Write-Tsv 'ui.tsv' @('path', 'root', 'ids', 'scripts', 'styles') ($ui | Sort-Object path)

# Models: read each .vmdl_c's reference list (RERL) and block types straight from the VPK, no decompile
# (a few seconds for every model). Materials' own RERLs give the textures.
$byPath = @{}; foreach ($e in $tree) { $byPath[$e.Path] = $e }
$refCache = @{}
$refsOf = { param($p) if (-not $refCache.ContainsKey($p)) { $refCache[$p] = $(if ($byPath[$p]) { @(Get-ResourceRefs ([DeadlockModding.Vpk]::Extract($byPath[$p]))) } else { @() }) }; $refCache[$p] }
# Plain-words names for search: what players and GameBanana call things, keyed by path patterns.
$aliasRules = [ordered]@{
  '^models/hideout/'                           = 'hideout'
  'fortune_teller'                             = 'fortune teller, oracle, seer, psychic'
  'hideout_bartender'                          = 'bartender'
  'hideout_ghost_(\w+)'                        = 'hideout ghost NPC $1'
  'hideout_item_urn|idol_urn|golden_idol|powerup_idol/powerup_idol' = 'idol, urn, soul urn'
  'soul_container'                             = 'soul container, soul bag, dropped souls, soul orb'
  'item_container_breakable|items/item_crate|items/crystal_crate|wooden_crate' = 'breakable crate, box'
  'gold_crate'                                 = 'gold crate'
  'neutral_vault'                              = 'vault'
  'sinners_sacrifice'                          = "sinner's sacrifice"
  'props_gameplay/rejuv'                       = 'rejuvenator, rejuv crystal'
  'powerup_tomes|powerup/'                     = 'powerup, tome'
  'gun_shop|props_gameplay/shop/'              = 'shop'
  'zip_tower|zipline'                          = 'zipline'
  'trooper'                                    = 'trooper, creep, minion, lane unit'
  'medic_'                                     = 'medic trooper'
  '(^|/|_)amber'                               = 'amber team'
  '(^|/|_)sapphire'                            = 'sapphire team'
  'boss_tier_01'                               = 'guardian, tier 1 objective'
  'boss_tier_02'                               = 'walker, tier 2 objective'
  'npc/patron'                                 = 'patron, final objective'
  'npc/shrine|core_shrine'                     = 'shrine'
  'npc/midboss'                                = 'mid boss, midboss'
  'npc_units/neutral_|npc/neutral'             = 'neutral creep, jungle camp, denizen'
  'mimic'                                      = 'mimic'
  '^models/weapons/'                           = 'weapon, gun'
  '/piece_?\d+|/cracked_|_gibs?\b|/lowerbody_|/upperbody_|/torso_piece' = 'breakage piece'
}
$heroFolders = foreach ($h in $heroes) {
  $code = $h.codename -replace '^hero_', ''
  [pscustomobject]@{ Folder = $h.model_folder; Code = $code; Label = "$(if ($h.name) { $h.name } else { $code }) hero ($($h.codename))" }
}
$models = foreach ($m in $tree | Where-Object { $_.Path.EndsWith('.vmdl_c') }) {
  $bytes = [DeadlockModding.Vpk]::Extract($m)
  $refs = @(Get-ResourceRefs $bytes); $refCache[$m.Path] = $refs
  $blocks = @(Get-ResourceBlocks $bytes | ForEach-Object Type)
  $mats = @($refs | Where-Object { $_.EndsWith('.vmat') })
  $textures = @($mats | ForEach-Object { & $refsOf "${_}_c" } | Where-Object { $_.EndsWith('.vtex') } | ForEach-Object { "${_}_c" } | Select-Object -Unique)
  $graphs = @($refs | Where-Object { $_ -match '\.vnmgraph' })
  $skel = @($refs | Where-Object { $_.EndsWith('.vnmskel') } | ForEach-Object { "${_}_c" })
  $classic = $blocks -contains 'ANIM' -or $blocks -contains 'AGRP'
  $p = $m.Path
  $aliases = [System.Collections.Generic.List[string]]::new()
  foreach ($r in $aliasRules.Keys) { $hit = [regex]::Match($p, $r); if ($hit.Success) { $aliases.Add(($aliasRules[$r] -replace '\$1', ($hit.Groups[1].Value -replace '_', ' '))) } }
  foreach ($h in $heroFolders) {
    if (($h.Folder -and $p.StartsWith("$($h.Folder)/")) -or $p -match "^models/heroes_\w+/$([regex]::Escape($h.Code))(_[^/]*)?/") { $aliases.Add($h.Label); break }
    if ($p -match "/hideout_ghost_$([regex]::Escape($h.Code))\.vmdl_c$") { $aliases.Add("ghost of $($h.Label)"); break }   # hideout ghosts of heroes
  }
  [pscustomobject]@{
    path = $p
    aliases = ($aliases | Select-Object -Unique) -join ', '
    bytes = $m.Bytes
    anim = $(if ($graphs) { 'animgraph2' } elseif ($classic) { 'classic' } else { 'none' })
    skeleton = $(if ($skel) { $skel -join ',' } elseif ($classic) { 'in model' })
    materials = ($mats | ForEach-Object { "${_}_c" }) -join ','
    textures = $textures -join ','
    other = (@($refs | Where-Object { -not $_.EndsWith('.vmat') -and -not $_.EndsWith('.vnmskel') }) -join ',')
  }
}
Write-Tsv 'models.tsv' @('path', 'aliases', 'bytes', 'anim', 'skeleton', 'materials', 'textures', 'other') ($models | Sort-Object path)

@"
# Deadlock build $build catalog

Generated $(Get-Date -Format 'yyyy-MM-dd') by catalog.ps1 from this PC's install. Tab-separated; first line = column names.
Regenerate after a patch: ``pwsh -File catalog.ps1`` (a new build gets a new folder).

| File | One row per | Columns |
|---|---|---|
| files.tsv | file in pak01_dir.vpk | path, bytes |
| soundevents.tsv | sound event | event, file (.vsndevts that defines it), vsnd_files (comma list of .vsnd_c it picks from at random), duration (s) |
| sounds.tsv | .vsnd_c file | path, bytes, events (comma list; empty = played by no event found, e.g. referenced from code or unused) |
| heroes.tsv | hero (incl. disabled/in-development ones) | codename, name, id, state, model, model_folder, sound_script, vo_script, abilities (slot 1-4: codename (name)) |
| ui.tsv | Panorama layout | path (source name; the game file is .vxml_c), root panel type, ids, scripts, styles |
| models.tsv | .vmdl_c file | path, aliases (plain words: hero name, "hideout", "bartender", "trooper", "soul container", "breakage piece"…; a starting point, not complete), bytes, anim (animgraph2 = hero-style AnimGraph 2; classic = AnimFile clips inside the model, recompilable from a decompile; none = static), skeleton (.vnmskel, or "in model" for classic), materials (.vmat_c), textures (.vtex_c those materials use), other (other references: sub-models, particles, animgraphs, sound data) |

Codenames differ from display names (hero_orion = Grey Talon). A mod replaces files by path: find the
event or panel here, then the files it uses. A sound event's files are random variants: replace all of them.
Models: search aliases and path words ("fortune_teller", "hideout"); then get-stock.ps1 the textures to edit.
"@ | Set-Content (Join-Path $Out 'README.md') -Encoding utf8

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Done:"
Write-Output $Out
