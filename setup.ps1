<#
.SYNOPSIS
  First-run setup for the kit: check this PC, list (or, once approved, install) the tools it needs,
  and read the game's data into generated/. Runs on Windows PowerShell 5.1 too, so a fresh PC can start here.

.DESCRIPTION
  With no arguments it downloads nothing and changes nothing except the kit's own generated/ folder:
    1. Runs tools\doctor.ps1 and shows its report.
    2. Lists what this PC is missing (tools\setup.ps1): what each tool is, why, where it comes from,
       and the exact command to install it once the user has said yes.
    3. If PowerShell 7 and Source2Viewer-CLI are present and generated/ is missing or for another
       Deadlock build, runs tools\generate-docs.ps1 to rebuild it (1-2 minutes). Otherwise says what it needs first.
  It ends with one line: ready, or what to do next.

  -Approve <ids> installs those tools first (the ids are the ones step 2 lists), then runs the steps above.
  -Media, -Models and -CsdkZip are passed to tools\setup.ps1 unchanged. Downloads happen only with -Approve.
  The Deadlock install is only read, never changed.

  Exit code: 0 = every tool is in place and generated/ matches the game; 1 = something failed;
  2 = waiting for the user (approve the list, download CSDK by hand, fix a doctor [FAIL], open a new terminal).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup.ps1                   # check, list what's missing, build generated/
  powershell -ExecutionPolicy Bypass -File setup.ps1 -Approve csdk,s2v,pwsh
  pwsh -File setup.ps1 -Approve csdk -CsdkZip "$HOME\Downloads\Reduced_CSDK_12.zip"
  pwsh -File setup.ps1 -Media                                          # also list the optional sound tools
  pwsh -File setup.ps1 -SkipData -Offline                              # check and list only
#>
param(
  [string[]]$Approve,     # tool ids to install, after the user said yes to the list
  [switch]$Media,         # also list the optional sound tools (yt-dlp, FFmpeg)
  [switch]$Models,        # also list the optional model converter (Blender)
  [string]$CsdkZip,       # a Reduced_CSDK_12.zip the user downloaded by hand
  [string]$Deadlock,      # the Deadlock folder, if Steam's library list doesn't find it
  [switch]$SkipData,      # don't build generated/
  [switch]$Offline,       # doctor: don't compare gameinfo.gi with Valve's copy online
  [string]$Generated,     # the generated/ folder (default: next to this script); tests point it elsewhere
  [string]$DownloadsDir   # where to look for a hand-downloaded CSDK zip (default: your Downloads folder)
)
$ErrorActionPreference = 'Stop'
$tools = Join-Path $PSScriptRoot 'tools'
. (Join-Path $tools 'deadlock-paths.ps1')
if (-not $Generated) { $Generated = Join-Path $PSScriptRoot 'generated' }

# What to say on the last line. The first problem found in each group wins; failures come before waits.
$failed = $null; $toApprove = $null; $toFix = $null; $dataNeeds = $null
function Step([string]$Title) { Write-Host "`n=== $Title ===" -ForegroundColor Cyan }

$listArgs = @{}   # passed to tools\setup.ps1 unchanged
if ($Media) { $listArgs.Media = $true }
if ($Models) { $listArgs.Models = $true }
if ($DownloadsDir) { $listArgs.DownloadsDir = $DownloadsDir }

# 0. Install what the user approved.
if ($Approve) {
  Step "Installing: $($Approve -join ',')"
  $installArgs = $listArgs.Clone(); $installArgs.Approve = $Approve
  if ($CsdkZip) { $installArgs.CsdkZip = $CsdkZip }
  try {
    & (Join-Path $tools 'setup.ps1') @installArgs
    if ($LASTEXITCODE -eq 1) { $failed = 'an install failed (see above).' }
    elseif ($LASTEXITCODE -eq 2) { $toApprove = 'download CSDK by hand as described above, then run this again with -Approve csdk.' }
  }
  catch { Write-Host "  $($_.Exception.Message)" -ForegroundColor Red; $failed = 'the install was refused (see above).' }
}

if (-not $failed -and -not $toApprove) {
  # 1. The doctor's full check.
  Step 'Checking this PC (doctor)'
  $doctorArgs = @{}
  if ($Deadlock) { $doctorArgs.Deadlock = $Deadlock }
  if ($Offline) { $doctorArgs.Offline = $true }
  $doctorArgs.Generated = $Generated
  & (Join-Path $tools 'doctor.ps1') @doctorArgs
  if ($LASTEXITCODE -gt 0) { $toFix = "fix the doctor's [FAIL] lines above." }

  # 2. What's missing. Lists only; tools\setup.ps1 exits 2 here when the list isn't empty.
  Step 'Tools this PC is missing'
  & (Join-Path $tools 'setup.ps1') @listArgs -StrictExit
  if ($LASTEXITCODE -eq 2) { $toApprove = 'show the user the list above; once they say yes, run setup.ps1 -Approve with the ids it names.' }

  # 3. generated/: data read off the installed game, for this build.
  Step 'Game data (generated/)'
  $root = $null
  try { $root = $(if ($Deadlock) { $Deadlock } else { Find-DeadlockRoot }) } catch { }
  if ($SkipData) { Write-Host 'Skipped (-SkipData).' }
  elseif (-not $root -or -not (Get-DeadlockBuild $root)) {
    Write-Host 'Deadlock was not found, so there is no game data to read.' -ForegroundColor Red
    $failed = "install Deadlock through Steam, or pass -Deadlock '<library>\steamapps\common\Deadlock'."
  }
  else {
    $build = Get-DeadlockBuild $root
    $genBuild = Get-GeneratedBuild $Generated
    $pwsh = $(if ($PSVersionTable.PSVersion.Major -ge 7) { (Get-Process -Id $PID).Path } else { (Get-Command pwsh -ErrorAction SilentlyContinue).Source })
    $hasCatalog = Test-Path (Join-Path $script:KitHome "catalog\$build\models.tsv")
    if ($genBuild -eq $build) { Write-Host "generated/ already describes build $build." -ForegroundColor Green }
    elseif (-not $pwsh) {
      Write-Host 'generated/ needs PowerShell 7 to build, and it is not installed (or this terminal was opened before it was).' -ForegroundColor Yellow
      $dataNeeds = 'install PowerShell 7 (setup.ps1 -Approve pwsh), open a new terminal, and run setup.ps1 again.'
    }
    elseif (-not (Find-Source2ViewerCli) -and -not $hasCatalog) {
      Write-Host 'generated/ needs Source2Viewer-CLI to read the game files, and it is not installed.' -ForegroundColor Yellow
      $dataNeeds = 'install Source2Viewer-CLI (setup.ps1 -Approve s2v), then run setup.ps1 again.'
    }
    else {
      $was = $(if ($genBuild) { "describes build $genBuild" } else { 'has no game data yet' })
      Write-Host "generated/ $was; reading Deadlock build $build into it (1-2 minutes, read-only on the game)..."
      $genArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $tools 'generate-docs.ps1'), '-Out', $Generated)
      if ($Deadlock) { $genArgs += @('-Deadlock', $Deadlock) }
      & $pwsh @genArgs | ForEach-Object { Write-Host "  $_" }
      if ($LASTEXITCODE -ne 0 -or (Get-GeneratedBuild $Generated) -ne $build) {
        Write-Host 'generate-docs.ps1 did not finish (see above).' -ForegroundColor Red
        $failed = 'building generated/ failed (see above).'
      }
      else { Write-Host "generated/ now describes build $build." -ForegroundColor Green }
    }
  }
}

Write-Host ''
if ($failed) { Write-Host "Setup stopped: $failed" -ForegroundColor Red; exit 1 }
$next = @($toApprove, $toFix, $dataNeeds) | Where-Object { $_ } | Select-Object -First 1
if ($next) { Write-Host "Next: $next" -ForegroundColor Yellow; exit 2 }
if ($SkipData) { Write-Host 'Ready: every tool is in place (generated/ was not checked: -SkipData).' -ForegroundColor Green }
else { Write-Host 'Ready: every tool is in place and generated/ matches the game. Make a mod.' -ForegroundColor Green }
exit 0
