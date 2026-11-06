#Requires -Version 7

<#
.SYNOPSIS
  After a Deadlock patch, carry a mod's changes over to the new stock files (cookbook/after-a-patch.md).

.DESCRIPTION
  For every file in <Mod>\stock\STOCK.json that was taken from an older build:
    1. Gets the stock file of your current build (get-stock.ps1, same source as before).
    2. Unchanged by the patch: just records the new build.
       Changed: 3-way merges (git merge-file) your override in <Mod>\src with old stock -> new stock,
       so Valve's changes and yours both land. The previous override is kept in <Mod>\rebase-backup\.
       Conflicts are left as <<<<<<< / >>>>>>> markers in the override for you to resolve.
       Raw (compiled) stock files can't be merged: they're reported so you can redo that change.
       Gone from the game: reported; find the new name with get-stock.ps1 -List.
    3. When every file is current and no override has conflict markers, sets mod.json gameBuild.
  Re-run it after resolving conflicts. Then build, restart Deadlock and test.

.EXAMPLE
  .\rebase.ps1 -Mod ..\mods\hello
#>
param(
  [Parameter(Mandatory)] [string]$Mod,
  [string]$Deadlock
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is needed for 3-way merges: winget install Git.Git" }
$Mod = (Resolve-Path $Mod).Path
$manifestPath = Join-Path $Mod 'mod.json'
$stockDir = Join-Path $Mod 'stock'
$recordPath = Join-Path $stockDir 'STOCK.json'
if (-not (Test-Path $recordPath)) { throw "$recordPath not found: this mod has no recorded stock files (made without new-mod.ps1/get-stock.ps1?)." }
if (-not $Deadlock) { $Deadlock = Find-DeadlockRoot }
$build = Get-DeadlockBuild $Deadlock
$record = Get-Content $recordPath -Raw | ConvertFrom-Json -AsHashtable
$getStock = Join-Path $PSScriptRoot 'get-stock.ps1'
$problems = 0

foreach ($path in @($record.Keys)) {
  $info = $record[$path]
  if ($info.build -eq $build) { Write-Host "[current]  $path"; continue }
  $raw = ($info.source -eq 'raw')
  $source = $(if ($info.source -like 'gametracking*') { 'gametracking' } elseif ($info.source -eq 's2v') { 's2v' } else { 'auto' })
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("dlrebase_" + [guid]::NewGuid().ToString('N'))
  try {
    $stockArgs = @{ Path = @($path); Out = $tmp; Deadlock = $Deadlock; Source = $source }
    if ($raw) { $stockArgs.Raw = $true }
    & $getStock @stockArgs | Out-Null
    $newStock = Join-Path $tmp $path
    if ($LASTEXITCODE -or -not (Test-Path $newStock)) {
      Write-Host "[gone]     $path is not in build $build. Find its new name: get-stock.ps1 -List <folder>/, then move your change by hand." -ForegroundColor Red
      $problems++; continue
    }
    $oldStock = Join-Path $stockDir $path
    $override = Join-Path $Mod "src\$path"
    $same = $(if ($raw) { (Get-FileHash $oldStock).Hash -eq (Get-FileHash $newStock).Hash }
      else { ([IO.File]::ReadAllText($oldStock) -replace "`r`n", "`n") -eq ([IO.File]::ReadAllText($newStock) -replace "`r`n", "`n") })
    if ($same) {
      Write-Host "[same]     $path didn't change in build $build" -ForegroundColor Green
    }
    elseif ($raw) {
      Write-Host "[changed]  $path changed in build $build. It's a compiled file, so redo your replacement against the new one (now in stock\)." -ForegroundColor Yellow
      $problems++
    }
    elseif (-not (Test-Path $override)) {
      Write-Host "[changed]  $path changed in build $build; no override in src\, so only the stock copy was updated." -ForegroundColor Yellow
    }
    else {
      $backup = Join-Path $Mod "rebase-backup\$path"
      New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
      Copy-Item $override $backup -Force
      $merged = & git merge-file -p -L 'your mod' -L "stock $($info.build)" -L "stock $build" $override $oldStock $newStock
      $conflicts = $LASTEXITCODE
      if ($conflicts -lt 0) { throw "git merge-file failed on $path" }
      $nl = $(if ([IO.File]::ReadAllText($newStock).Contains("`r`n")) { "`r`n" } else { "`n" })
      [IO.File]::WriteAllText($override, (($merged -join $nl) + $nl), (New-Object System.Text.UTF8Encoding $false))
      if ($conflicts) {
        Write-Host "[conflict] $path : $conflicts conflict(s). Resolve the <<<<<<< markers in src\$path, then re-run." -ForegroundColor Red
        $problems++
      }
      else { Write-Host "[merged]   $path : Valve's changes merged under yours (old override in rebase-backup\)" -ForegroundColor Green }
    }
    Copy-Item $newStock $oldStock -Force
    $record[$path] = [ordered]@{ build = $build; source = $info.source }
  }
  finally { if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force } }
}
$record | ConvertTo-Json | Set-Content $recordPath -Encoding utf8

# Conflict markers left from an earlier run (this run's conflicts are already counted).
$markers = @(Get-ChildItem (Join-Path $Mod 'src') -Recurse -File -ErrorAction SilentlyContinue | Select-String -Pattern '^(<<<<<<<|>>>>>>>) ' -List)
if ($markers -and -not $problems) { $markers | ForEach-Object { Write-Host "[markers]  unresolved conflict markers in $($_.Path)" -ForegroundColor Red }; $problems = $markers.Count }

if ($problems) { Write-Host "`n$problems file(s) need attention. mod.json still says the old build." -ForegroundColor Red; exit 1 }
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json -AsHashtable
$manifest.gameBuild = $build
$manifest | ConvertTo-Json | Set-Content $manifestPath -Encoding utf8
Write-Host "`nRebased onto build $build. Now: build.ps1 -Mod `"$Mod`" -Install, restart Deadlock, and test." -ForegroundColor Green
