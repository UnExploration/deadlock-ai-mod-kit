#Requires -Version 7

<#
.SYNOPSIS
  Render the installed Deadlock build's data as readable Markdown in the kit's generated/ folder.

.DESCRIPTION
  Reads the catalog of the installed build (%LOCALAPPDATA%\deadlock-modding\catalog\<build>\, running
  catalog.ps1 first if this build has none) plus gameinfo.gi and the loose localization files, and writes
  these seven files to generated/ (or -Out), then prints that folder. Read-only on the game. Never edit the
  output by hand: re-run this after every Deadlock patch (the setup.ps1 at the kit's root does it when
  generated/ is missing or for another build). The same catalog always gives byte-identical files
  (everything sorted; the only date is the catalog's). generated/README.md is authored; this never writes it.

    build.md        build number, Valve's stock SearchPaths block (kit lines taken out) and whether this PC mounts addons, PGIVersion, loose localization files
    file-types.md   every file extension in pak01: count, size, top folders, an example path
    folders.md      pak01 folder tree to depth 2 with file counts
    heroes.md       every hero: codename, name, id, state, model, sound scripts, abilities
    ui-layouts.md   every Panorama layout: root panel, panel ids, scripts, styles
    sounds.md       sound files per folder, events per .vsndevts file, how to search the rest
    models.md       models per folder with animation kinds, the plain-words alias index, how to search

.EXAMPLE
  pwsh -File generate-docs.ps1
  pwsh -File generate-docs.ps1 -Force          (rebuild the catalog first)
  pwsh -File generate-docs.ps1 -Out C:\temp\gen
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
if (-not $build) { throw "Can't read the build number from $Deadlock\game\citadel\steam.inf." }
if (-not $Out) { $Out = Join-Path (Split-Path $PSScriptRoot) 'generated' }
$catalog = Join-Path $script:KitHome "catalog\$build"

if ($Force -or -not ((Test-Path (Join-Path $catalog 'README.md')) -and (Test-Path (Join-Path $catalog 'models.tsv')))) {
  Write-Host "No catalog for build $build yet (or -Force): running catalog.ps1 (1-2 minutes)"
  $catArgs = @{ Deadlock = $Deadlock }; if ($Force) { $catArgs.Force = $true }
  & (Join-Path $PSScriptRoot 'catalog.ps1') @catArgs | Out-Null
  if (-not (Test-Path (Join-Path $catalog 'models.tsv'))) { throw "catalog.ps1 did not write $catalog." }
}

# The date of the catalog, not of this run, so the same catalog renders byte-identically on any day.
$readme = Join-Path $catalog 'README.md'
$dm = [regex]::Match([IO.File]::ReadAllText($readme), 'Generated (\d{4}-\d{2}-\d{2})')
$date = $(if ($dm.Success) { $dm.Groups[1].Value } else { (Get-Item (Join-Path $catalog 'files.tsv')).LastWriteTime.ToString('yyyy-MM-dd') })

$inv = [Globalization.CultureInfo]::InvariantCulture
$ord = [StringComparer]::Ordinal
function Fmt([string]$Format, [object[]]$Values) { [string]::Format($inv, $Format, $Values) }
function SortOrd([string[]]$Items) { $a = [string[]]@($Items); [Array]::Sort($a, $ord); $a }
# A table cell: no pipes or line breaks; empty shows as a dash.
function Cell($v) { $s = "$v" -replace '[\r\n\t]+', ' ' -replace '\|', '\|'; $(if ($s) { $s } else { '-' }) }
function Code($v) { $(if ("$v") { '`' + "$v" + '`' } else { '-' }) }
function MB([long]$Bytes) { Fmt '{0:0.0}' @($Bytes / 1MB) }

# Rows of a catalog TSV as hashtables (header = keys). Write-Tsv never quotes, so a plain split is exact.
function Read-Tsv([string]$Name) {
  $lines = [IO.File]::ReadAllLines((Join-Path $catalog $Name))
  $cols = $lines[0].Split("`t")
  $rows = [System.Collections.Generic.List[hashtable]]::new()
  for ($i = 1; $i -lt $lines.Length; $i++) {
    if (-not $lines[$i]) { continue }
    $f = $lines[$i].Split("`t"); $r = @{}
    for ($c = 0; $c -lt $cols.Length; $c++) { $r[$cols[$c]] = $(if ($c -lt $f.Length) { $f[$c] } else { '' }) }
    $rows.Add($r)
  }
  , $rows
}

# Count by key, returned as key -> count; and helpers to list keys by count desc, then name.
function Count-By($Items, [scriptblock]$Key) {
  $h = [System.Collections.Generic.Dictionary[string, long]]::new($ord)
  foreach ($i in $Items) { $k = & $Key $i; if ($null -eq $k) { continue }; $h[$k] = $(if ($h.ContainsKey($k)) { $h[$k] + 1 } else { 1 }) }
  , $h
}
function Keys-ByCount($Dict) { SortOrd $Dict.Keys | Sort-Object { - $Dict[$_] } -Stable }
# Items sorted by one string key, ordinally (the same order on every PC and locale).
function SortBy($Items, [string]$Key) { $a = @($Items); $k = [string[]]@($a | ForEach-Object { $_[$Key] }); [Array]::Sort($k, $a, [Collections.IComparer]$ord); $a }   # the cast picks the non-generic overload, which reorders $a in place

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
function Write-Doc([string]$Name, [string]$Title, [System.Collections.Generic.List[string]]$Body) {
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add("<!-- GENERATED by tools/generate-docs.ps1 from Deadlock build $build on $date. Do not edit: regenerate. -->")
  $lines.Add("Generated from Deadlock build $build on $date by ``tools/generate-docs.ps1``. Don't edit this file by hand: regenerate it ([README.md](README.md) says how).")
  $lines.Add('')
  $lines.Add("# $Title")
  $lines.Add('')
  $lines.AddRange($Body)
  while ($lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
  [IO.File]::WriteAllText((Join-Path $Out $Name), (($lines -join "`n") + "`n"), $utf8)
  Write-Host ("  {0,-14} {1} lines" -f $Name, ($lines.Count))
}
function New-Body { , [System.Collections.Generic.List[string]]::new() }
$catPath = "%LOCALAPPDATA%\deadlock-modding\catalog\$build\"

Write-Host "Rendering Deadlock build $build (catalog of $date) to $Out"
$files = Read-Tsv 'files.tsv'

# ---- build.md -------------------------------------------------------------------------------
$b = New-Body
$giPath = Join-Path $Deadlock 'game\citadel\gameinfo.gi'
$gi = [IO.File]::ReadAllText($giPath) -replace "`r`n", "`n"
$b.Add("- **Build:** $build (``game/citadel/steam.inf`` ClientVersion)")
$b.Add("- **Catalogued:** $date")
$pgi = [regex]::Match($gi, '(?m)^[ \t]*PGIVersion[^\n]*').Value.Trim()
$b.Add("- **PGIVersion line:** $(if ($pgi) { Code $pgi } else { 'not found in gameinfo.gi' })")
$b.Add('')
$b.Add('## gameinfo.gi SearchPaths')
$b.Add('')
$sp = [regex]::Match($gi, '(?m)^[ \t]*SearchPaths[ \t]*\n[ \t]*\{')
if ($sp.Success) {
  $i = $sp.Index + $sp.Length; $depth = 1
  while ($i -lt $gi.Length -and $depth -gt 0) {   # braces in // comments and "strings" don't count
    $ch = $gi[$i]
    if ($ch -eq '/' -and $i + 1 -lt $gi.Length -and $gi[$i + 1] -eq '/') { $j = $gi.IndexOf("`n", $i); $i = $(if ($j -lt 0) { $gi.Length } else { $j }); continue }
    if ($ch -eq '"') { $j = $gi.IndexOf('"', $i + 1); $i = $(if ($j -lt 0) { $gi.Length } else { $j + 1 }); continue }
    if ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth-- }
    $i++
  }
  $block = $gi.Substring($sp.Index, $i - $sp.Index)
  # Valve's stock block: take out exactly what enable-addons.ps1 adds (the same function its -Disable uses).
  $stock = Remove-AddonsMount ($block + "`n")
  $stock = $stock.Substring(0, $stock.Length - 1)
  $mounted = $stock -ne $block
  $b.Add("Valve's stock block: this PC's ``game/citadel/gameinfo.gi`` with the lines ``enable-addons.ps1`` adds taken out. That script mounts mods by adding ``Game citadel/addons`` above ``Game citadel``, plus ``Mod``/``Write`` lines for ``citadel`` and ``core`` when Valve's block has none.")
  $b.Add('')
  $b.Add('```')
  $b.AddRange([string[]]($stock -split "`n"))
  $b.Add('```')
  $b.Add('')
  $b.Add($(if ($mounted) { "This PC's gameinfo.gi also has the kit's ``Game citadel/addons`` line (mounted)." } else { "This PC's gameinfo.gi does not have the kit's ``Game citadel/addons`` line (not mounted)." }))
}
else { $b.Add('No `SearchPaths` block found in gameinfo.gi.') }
$b.Add('')
$b.Add('## Loose localization files')
$b.Add('')
$b.Add('Files under `game/citadel/resource/localization/` (outside the VPKs, so not in `files.tsv`). Text a mod can change lives here.')
$b.Add('')
$loc = Join-Path $Deadlock 'game\citadel\resource\localization'
$locFiles = @(if (Test-Path $loc) { Get-ChildItem $loc -Recurse -Filter '*.txt' -File })
if ($locFiles) {
  $byRel = @{}; foreach ($f in $locFiles) { $byRel[[IO.Path]::GetRelativePath($loc, $f.FullName).Replace('\', '/')] = $f.Length }
  $b.Add('| File | Bytes |'); $b.Add('|---|---:|')
  foreach ($k in (SortOrd $byRel.Keys)) { $b.Add("| $(Cell $k) | $($byRel[$k]) |") }
}
else { $b.Add('None found.') }
Write-Doc 'build.md' "Deadlock build $build" $b

# ---- file-types.md --------------------------------------------------------------------------
$types = @{}
foreach ($f in $files) {
  $p = $f.path; $slash = $p.LastIndexOf('/'); $name = $p.Substring($slash + 1); $dot = $name.LastIndexOf('.')
  $ext = $(if ($dot -gt 0) { $name.Substring($dot + 1) } else { '(none)' })
  $parts = $p.Split('/'); $folder = $(if ($parts.Length -ge 3) { "$($parts[0])/$($parts[1])" } elseif ($parts.Length -eq 2) { $parts[0] } else { '(root)' })
  if (-not $types[$ext]) { $types[$ext] = @{ Count = 0; Bytes = [long]0; Folders = [System.Collections.Generic.Dictionary[string, long]]::new($ord); Example = $p } }
  $t = $types[$ext]; $t.Count++; $t.Bytes += [long]$f.bytes
  $t.Folders[$folder] = $(if ($t.Folders.ContainsKey($folder)) { $t.Folders[$folder] + 1 } else { 1 })
  if ($ord.Compare($p, $t.Example) -lt 0) { $t.Example = $p }
}
$b = New-Body
$b.Add("Every file extension in ``pak01_dir.vpk`` ($($files.Count) files, $($types.Count) extensions), most common first. A mod replaces or adds files of these types at the paths the game reads. Top folders are the first two path levels, with how many of that type each holds; the example is the alphabetically first path.")
$b.Add('')
$b.Add('| Extension | Files | Total MB | Top folders | Example |'); $b.Add('|---|---:|---:|---|---|')
$extOrder = @(SortOrd $types.Keys | Sort-Object { - $types[$_].Count } -Stable)
foreach ($e in $extOrder) {
  $t = $types[$e]
  $top = (Keys-ByCount $t.Folders | Select-Object -First 3 | ForEach-Object { "``$_`` ($($t.Folders[$_]))" }) -join ', '
  $b.Add("| ``.$e`` | $($t.Count) | $(MB $t.Bytes) | $(Cell $top) | $(Code $t.Example) |")
}
Write-Doc 'file-types.md' 'File types in pak01' $b

# ---- folders.md -----------------------------------------------------------------------------
$top = [System.Collections.Generic.Dictionary[string, long]]::new($ord)
$second = [System.Collections.Generic.Dictionary[string, long]]::new($ord)
$rootFiles = 0
foreach ($f in $files) {
  $parts = $f.path.Split('/')
  if ($parts.Length -eq 1) { $rootFiles++; continue }
  $top[$parts[0]] = $(if ($top.ContainsKey($parts[0])) { $top[$parts[0]] + 1 } else { 1 })
  if ($parts.Length -ge 3) { $k = "$($parts[0])/$($parts[1])"; $second[$k] = $(if ($second.ContainsKey($k)) { $second[$k] + 1 } else { 1 }) }
}
$b = New-Body
$b.Add("Folders of ``pak01_dir.vpk`` to depth 2. Each count includes every file below that folder. Full list: ``files.tsv`` in the catalog ([README.md](README.md)).")
$b.Add('')
if ($rootFiles) { $b.Add("- (files at the top level): $rootFiles") }
foreach ($t in (SortOrd $top.Keys)) {
  $direct = $top[$t] - (@($second.Keys | Where-Object { $_.StartsWith("$t/") } | ForEach-Object { $second[$_] }) | Measure-Object -Sum).Sum
  $b.Add("- ``$t/``: $($top[$t])$(if ($direct) { " ($direct directly in it)" })")
  foreach ($s in (SortOrd @($second.Keys | Where-Object { $_.StartsWith("$t/") }))) { $b.Add("  - ``$s/``: $($second[$s])") }
}
Write-Doc 'folders.md' 'Folders in pak01' $b

# ---- heroes.md ------------------------------------------------------------------------------
$heroes = Read-Tsv 'heroes.tsv'
$b = New-Body
$b.Add("Every hero in ``scripts/heroes.vdata`` ($($heroes.Count)), including disabled and in-development ones. Codenames differ from display names. Abilities are slots 1-4 as ``codename (name)``.")
$b.Add('')
$hc = 'codename', 'name', 'id', 'state', 'model', 'model_folder', 'sound_script', 'vo_script', 'abilities'
$b.Add('| ' + ($hc -join ' | ') + ' |'); $b.Add('|' + ('---|' * $hc.Count))
foreach ($h in (SortBy $heroes 'codename')) {
  $b.Add('| ' + (($hc | ForEach-Object { if ($_ -in 'model', 'model_folder', 'sound_script', 'vo_script', 'codename') { Code $h[$_] } else { Cell $h[$_] } }) -join ' | ') + ' |')
}
Write-Doc 'heroes.md' 'Heroes' $b

# ---- ui-layouts.md --------------------------------------------------------------------------
$ui = @(SortBy (Read-Tsv 'ui.tsv') 'path')
$b = New-Body
$b.Add("Every Panorama layout ($($ui.Count)). ``path`` is the source name; the game file is the same path as ``.vxml_c``. ``ids`` are the panel ids a mod's CSS or script can target.")
$b.Add('')
$uiRow = { param($u) "| $(Code $u.path) | $(Cell $u.root) | $(Cell ($u.ids -replace ',', ', ')) | $(Cell ($u.scripts -replace ',', ', ')) | $(Cell ($u.styles -replace ',', ', ')) |" }
$uiHead = { $b.Add('| path | root | ids | scripts | styles |'); $b.Add('|---|---|---|---|---|') }
if ($ui.Count -le 2000) { & $uiHead; foreach ($u in $ui) { $b.Add((& $uiRow $u)) } }
else {
  $groups = [ordered]@{}
  foreach ($u in $ui) { $rest = $u.path -replace '^panorama/layout/', ''; $g = $(if ($rest.Contains('/')) { $rest.Split('/')[0] } else { '(top level)' }); if (-not $groups[$g]) { $groups[$g] = [System.Collections.Generic.List[object]]::new() }; $groups[$g].Add($u) }
  foreach ($g in (SortOrd @($groups.Keys))) { $b.Add("## $g"); $b.Add(''); & $uiHead; foreach ($u in $groups[$g]) { $b.Add((& $uiRow $u)) }; $b.Add('') }
}
Write-Doc 'ui-layouts.md' 'UI layouts' $b

# ---- sounds.md ------------------------------------------------------------------------------
$sounds = Read-Tsv 'sounds.tsv'
$events = Read-Tsv 'soundevents.tsv'
$d1 = Count-By $sounds { param($s) $p = $s.path.Split('/'); if ($p.Length -ge 3) { "$($p[0])/$($p[1])" } else { 'sounds' } }
$d2 = Count-By $sounds { param($s) $p = $s.path.Split('/'); if ($p.Length -ge 4) { "$($p[0])/$($p[1])/$($p[2])" } }
$perFile = Count-By $events { param($e) $e.file }
$noEvent = @($sounds | Where-Object { -not $_.events }).Count
$b = New-Body
$b.Add("$($sounds.Count) sound files (``.vsnd_c``) and $($events.Count) sound events in $($perFile.Count) ``.vsndevts`` files. $noEvent sound files are played by no event the catalog found. The full lists are too long for this page: search them (last section).")
$b.Add('')
$b.Add('## Sound files per folder')
$b.Add('')
$b.Add('| Folder | Files |'); $b.Add('|---|---:|')
foreach ($k in (SortOrd $d1.Keys)) { $b.Add("| ``$k/`` | $($d1[$k]) |") }
$b.Add('')
$b.Add('### One level deeper')
$b.Add('')
$b.Add('| Folder | Files |'); $b.Add('|---|---:|')
foreach ($k in (SortOrd $d2.Keys)) { $b.Add("| ``$k/`` | $($d2[$k]) |") }
$b.Add('')
$b.Add('## Events per .vsndevts file')
$b.Add('')
$b.Add('| File | Events |'); $b.Add('|---|---:|')
foreach ($k in (SortOrd $perFile.Keys)) { $b.Add("| ``$k`` | $($perFile[$k]) |") }
$b.Add('')
$b.Add('## How to search')
$b.Add('')
$b.Add('With the MCP tools:')
$b.Add('')
$b.Add('- An event by name: `catalog_search` with `table: "soundevents"`, `query: "lethal"`, `column: "event"`. Its `vsnd_files` are the files it picks from at random: replace all of them.')
$b.Add('- The events that play a file: `catalog_search` with `table: "sounds"`, `query: "damage_send_lethal"`, `column: "path"`.')
$b.Add('')
$b.Add("Without MCP (PowerShell; the catalog is ``$catPath``):")
$b.Add('')
$b.Add('```powershell')
$b.Add("Select-String -Path `"`$env:LOCALAPPDATA\deadlock-modding\catalog\$build\soundevents.tsv`" -Pattern '^[^\t]*lethal'")
$b.Add("Select-String -Path `"`$env:LOCALAPPDATA\deadlock-modding\catalog\$build\sounds.tsv`" -Pattern 'damage_send_lethal'")
$b.Add('```')
Write-Doc 'sounds.md' 'Sounds' $b

# ---- models.md ------------------------------------------------------------------------------
$models = Read-Tsv 'models.tsv'
$mf = @{}
foreach ($m in $models) {
  $p = $m.path.Split('/'); $k = $(if ($p.Length -ge 3) { "$($p[0])/$($p[1])" } else { 'models' })
  if (-not $mf[$k]) { $mf[$k] = @{ Count = 0; animgraph2 = 0; classic = 0; none = 0 } }
  $mf[$k].Count++; if ($mf[$k].ContainsKey($m.anim)) { $mf[$k][$m.anim]++ }
}
$aliased = @(SortBy @($models | Where-Object { $_.aliases }) 'path')
$b = New-Body
$b.Add("$($models.Count) models (``.vmdl_c``). Animation kind: **animgraph2** = hero-style AnimGraph 2 (separate ``.vnmskel`` skeleton); **classic** = animation clips inside the model; **none** = static.")
$b.Add('')
$b.Add('## Models per folder')
$b.Add('')
$b.Add('| Folder | Models | animgraph2 | classic | none |'); $b.Add('|---|---:|---:|---:|---:|')
foreach ($k in (SortOrd $mf.Keys)) { $v = $mf[$k]; $b.Add("| ``$k/`` | $($v.Count) | $($v.animgraph2) | $($v.classic) | $($v.none) |") }
$b.Add('')
$b.Add('## Alias index')
$b.Add('')
$b.Add("Plain-words names (what players call a thing) for the $($aliased.Count) models that have one, sorted by path. A starting point, not complete: also search path words.")
$b.Add('')
$b.Add('| Model | Aliases |'); $b.Add('|---|---|')
foreach ($m in $aliased) { $b.Add("| $(Code $m.path) | $(Cell $m.aliases) |") }
$b.Add('')
$b.Add('## How to search')
$b.Add('')
$b.Add('- By plain words: `catalog_search` with `table: "models"`, `query: "bartender"`, `column: "aliases"`; by path words: the same with `column: "path"`.')
$b.Add('- A model''s materials and textures (to recolour it) are the `materials` and `textures` columns of its row; get them with `get_stock`.')
$b.Add('')
$b.Add('```powershell')
$b.Add("Select-String -Path `"`$env:LOCALAPPDATA\deadlock-modding\catalog\$build\models.tsv`" -Pattern 'bartender'")
$b.Add('```')
Write-Doc 'models.md' 'Models' $b

Write-Host "Done:"
Write-Output $Out
