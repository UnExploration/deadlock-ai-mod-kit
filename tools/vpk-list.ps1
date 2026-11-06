<#
.SYNOPSIS
  List the files inside a VPK (v1/v2) without any external tools. Use it before every release
  to confirm a mod ships exactly the paths you intend (docs/06-distribution.md).

.EXAMPLE
  .\vpk-list.ps1 .\dist\pak64_dir.vpk
  .\vpk-list.ps1 "...\game\citadel\pak01_dir.vpk" -Filter panorama/scripts/
#>
param(
  [Parameter(Mandatory)] [string]$Path,
  [string]$Filter = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

Read-VpkTree $Path $Filter | ForEach-Object { [pscustomobject]@{ Path = $_.Path; Bytes = $_.Bytes; InDirFile = $_.InDirFile } }
