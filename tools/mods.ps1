#Requires -Version 7

<#
.SYNOPSIS
  See and manage the mods installed in Deadlock's game\citadel\addons (docs/01-how-mods-load.md).

.DESCRIPTION
  list (default)    Every pak: number, enabled/disabled, which mod installed it, size, what it changes,
                    and how many of its files are shadowed by a lower-numbered pak.
  files <mod>       The files inside one pak.
  conflicts         Every game file that more than one enabled pak replaces, and which pak wins
                    (the lowest number wins the whole file).
  disable <mod>     Move the pak (and its _000.. chunks) to game\citadel\addons_disabled (not mounted).
  enable <mod>      Move it back. Refuses if that pak number is taken in addons.
  remove <mod>      Delete the pak. Needs -Yes.
  reset             Delete every pak built with these tools (enabled or disabled), then unmount
                    citadel/addons in gameinfo.gi unless other mods are still installed. Needs -Yes.
  <mod> is a pak number (64), a file name (pak64_dir.vpk), or a mod name recorded by build.ps1.
  Changes need Deadlock closed; they take effect at the next launch.
  Paks installed by Deadlock Mod Manager are tracked by DMM too: manage those in DMM instead.

.EXAMPLE
  .\mods.ps1
  .\mods.ps1 conflicts
  .\mods.ps1 disable 64
  .\mods.ps1 remove hello -Yes
  .\mods.ps1 reset -Yes
#>
param(
  [Parameter(Position = 0)] [ValidateSet('list', 'files', 'conflicts', 'disable', 'enable', 'remove', 'reset')] [string]$Action = 'list',
  [Parameter(Position = 1)] [string]$Mod,
  [string]$Deadlock,
  [switch]$Yes
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

if (-not $Deadlock) { $Deadlock = Find-DeadlockRoot }
$addons = Join-Path $Deadlock 'game\citadel\addons'
$disabledDir = Join-Path $Deadlock 'game\citadel\addons_disabled'
$registry = Get-PakRegistry

function Get-Paks {
  foreach ($dir in @($addons, $disabledDir)) {
    if (-not (Test-Path $dir)) { continue }
    Get-ChildItem $dir -Filter 'pak*_dir.vpk' -File | Where-Object Name -match '^pak(\d\d)_dir\.vpk$' | ForEach-Object {
      $n = [int]$Matches[1]
      $chunks = @(Get-ChildItem $dir -File | Where-Object Name -match ('^pak{0:D2}_\d\d\d\.vpk$' -f $n))
      [pscustomobject]@{
        Number  = $n
        Name    = $_.Name
        Enabled = ($dir -eq $addons)
        Owner   = $registry[$_.Name]
        Files   = @($_) + $chunks
        Bytes   = ($_.Length + ($chunks | Measure-Object Length -Sum).Sum)
        Entries = @(Read-VpkTree $_.FullName)
      }
    }
  }
}

function Resolve-Mod($paks) {
  if (-not $Mod) { throw "Name the mod: a pak number, pakNN_dir.vpk, or a mod name." }
  $hit = $paks | Where-Object { $_.Name -eq $Mod -or $_.Owner -eq $Mod -or ($Mod -match '^(pak)?(\d{1,2})$' -and $_.Number -eq [int]$Matches[2]) }
  if (-not $hit) { throw "No installed pak matches '$Mod'. Run .\mods.ps1 list." }
  if (@($hit).Count -gt 1) { throw "'$Mod' matches several paks ($((@($hit) | ForEach-Object Name) -join ', ')); use the pak number." }
  $hit
}

function Get-Summary($entries) {
  # e.g. "panorama 12, sounds 3" from the top-level folders of the pak's files
  ($entries | Group-Object { ($_.Path -split '/')[0] } | Sort-Object Count -Descending | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', '
}

function Get-Conflicts($paks) {
  $byPath = @{}
  foreach ($pak in ($paks | Where-Object Enabled | Sort-Object Number)) {
    foreach ($e in $pak.Entries) {
      if (-not $byPath.ContainsKey($e.Path)) { $byPath[$e.Path] = [System.Collections.Generic.List[object]]::new() }
      $byPath[$e.Path].Add($pak)
    }
  }
  $byPath.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } | ForEach-Object {
    [pscustomobject]@{ Path = $_.Key; Winner = $_.Value[0]; Losers = @($_.Value | Select-Object -Skip 1) }
  } | Sort-Object Path
}

function Label($pak) { "$($pak.Name)$(if ($pak.Owner) { " ($($pak.Owner))" })" }

$paks = @(Get-Paks | Sort-Object Number)

switch ($Action) {
  'list' {
    if (-not (Test-Path $addons)) { Write-Host "No addons folder: mods are not set up. Run enable-addons.ps1 (docs/01)." -ForegroundColor Yellow }
    if (-not $paks) { Write-Host "No mods installed."; break }
    $conflicts = @(Get-Conflicts $paks)
    $paks | ForEach-Object {
      $pak = $_
      $lost = @($conflicts | Where-Object { $_.Losers -contains $pak }).Count
      [pscustomobject]@{
        Pak      = '{0:D2}' -f $pak.Number
        State    = $(if ($pak.Enabled) { 'enabled' } else { 'disabled' })
        Mod      = $(if ($pak.Owner) { $pak.Owner } else { '?' })
        MB       = [Math]::Round($pak.Bytes / 1MB, 1)
        Changes  = Get-Summary $pak.Entries
        Shadowed = $(if ($lost) { "$lost of $($pak.Entries.Count) files" } else { '' })
      }
    } | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
    if ($conflicts) { Write-Host "`n$($conflicts.Count) game files are replaced by more than one mod. See: .\mods.ps1 conflicts" -ForegroundColor Yellow }
    if ((Get-Content (Join-Path $Deadlock 'game\citadel\gameinfo.gi') -Raw) -notmatch '(?m)^\s*Game\s+citadel/addons\s*$') {
      Write-Host "gameinfo.gi does not mount citadel/addons, so none of these load. Run enable-addons.ps1." -ForegroundColor Yellow
    }
  }
  'files' {
    $pak = Resolve-Mod $paks
    $pak.Entries | ForEach-Object { [pscustomobject]@{ Path = $_.Path; Bytes = $_.Bytes } } | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
  }
  'conflicts' {
    $conflicts = @(Get-Conflicts $paks)
    if (-not $conflicts) { Write-Host "No conflicts between enabled mods."; break }
    $conflicts | ForEach-Object { [pscustomobject]@{ File = $_.Path; Wins = Label $_.Winner; Ignored = ($_.Losers | ForEach-Object { Label $_ }) -join ', ' } } | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
    Write-Host "`nTo let a different mod win, give it a lower pak number (rename every pakNN_ file of the set together)." -ForegroundColor Cyan
  }
  'reset' {
    Assert-DeadlockClosed $Deadlock
    $ours = @($paks | Where-Object Owner)
    $others = @($paks | Where-Object { -not $_.Owner })
    if (-not $Yes) { throw "Reset deletes $($ours.Count) pak(s) built with these tools$(if ($ours) { " ($(($ours | ForEach-Object { Label $_ }) -join ', '))" }) and unmounts addons if no other mods remain. Re-run with -Yes." }
    foreach ($pak in $ours) { $pak.Files | Remove-Item -Force; $registry.Remove($pak.Name); Write-Host "Removed $(Label $pak)." }
    Save-PakRegistry $registry
    if ((Test-Path $disabledDir) -and -not (Get-ChildItem $disabledDir -Force)) { Remove-Item $disabledDir }
    if ($others) {
      Write-Host "Kept citadel/addons mounted: $($others.Count) other mod(s) are installed ($(($others | ForEach-Object Name) -join ', ')). Remove them in Deadlock Mod Manager or with .\mods.ps1 remove <pak> -Yes, then reset again." -ForegroundColor Yellow
    }
    else { & (Join-Path $PSScriptRoot 'enable-addons.ps1') -GameInfo (Join-Path $Deadlock 'game\citadel\gameinfo.gi') -Disable }
    Write-Host "Reset done. Steam > Deadlock > Properties > Installed Files > Verify restores every other game file." -ForegroundColor Green
  }
  { $_ -in 'disable', 'enable', 'remove' } {
    Assert-DeadlockClosed $Deadlock
    $pak = Resolve-Mod $paks
    if ($Action -eq 'remove') {
      if (-not $Yes) { throw "Removing deletes $($pak.Files.Name -join ', '). Re-run with -Yes, or use disable to keep it." }
      $pak.Files | Remove-Item -Force
      if ($registry.ContainsKey($pak.Name)) { $registry.Remove($pak.Name); Save-PakRegistry $registry }
      Write-Host "Removed $(Label $pak)." -ForegroundColor Green
      break
    }
    $wantEnabled = ($Action -eq 'enable')
    if ($pak.Enabled -eq $wantEnabled) { Write-Host "$(Label $pak) is already $($Action)d."; break }
    $dest = $(if ($wantEnabled) { $addons } else { $disabledDir })
    if ($wantEnabled -and (Test-Path (Join-Path $addons $pak.Name))) { throw "$($pak.Name) is taken by another enabled mod. Disable that one first." }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $pak.Files | Move-Item -Destination $dest
    Write-Host "$(Label $pak) $($Action)d. Takes effect next time Deadlock starts." -ForegroundColor Green
  }
}
