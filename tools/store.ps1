#Requires -Version 7

<#
.SYNOPSIS
  Storage page of a mod that saves data (new-mod.ps1 -Kind data): show which address the mod saves
  through and whether it answers, or host the kit's page on the mod maker's own GitHub, free
  (docs/04-persistence-and-io.md, pattern A). Players never need GitHub.

.DESCRIPTION
  Every -Kind data mod saves through one storage page, chosen when the mod was made (new-mod.ps1
  -StoreUrl): the kit's hosted page, or an address of the maker's own. The page is the same file in
  both cases, the kit's store/index.html; each mod's keys sit under its own namespace (<name>.v1).

  Without -Publish: shows the address in mod.json, whether it is the kit's page or the maker's own,
  whether it answers (fetches it and looks for the page's title; -Offline skips that), and the GitHub
  sign-in that -Publish needs. Changes nothing.

  With -Publish (self-hosting):
  1. Needs the GitHub CLI (setup.ps1 -Approve gh) and a one-time sign-in by the user: gh auth login
     (in Claude Code the user types: ! gh auth login). Exit 2 means "waiting for the sign-in".
  2. Creates the public repo <github user>/<Repo> if it's missing (default: the repo already in the
     mod's github.io address, else <mod name>-store), uploads the kit's store/index.html as index.html,
     and turns on GitHub Pages.
  3. Waits (up to 10 minutes; -NoWait skips) until https://<user>.github.io/<Repo>/ serves that page.
  4. Writes the address into mod.json (store.url, and the privacy text) and into
     src\panorama\scripts\<name>_store.js, which the mod reads. Rebuild the mod afterwards.
  Players' saved data stays with the address it was saved under. So -Publish refuses to switch a mod
  to a different address (including away from the kit's page) unless -Force, which is only safe
  before anyone has used the mod. Re-publishing to the same address (to update the page) is fine.

.EXAMPLE
  pwsh -File store.ps1 -Mod .\mods\notepad
  pwsh -File store.ps1 -Mod .\mods\notepad -Publish
#>
param(
  [Parameter(Mandatory)] [string]$Mod,
  [switch]$Publish,
  [ValidatePattern('^[A-Za-z0-9_.-]{1,100}$')] [string]$Repo,
  [switch]$NoWait,
  [switch]$Force,
  [switch]$Offline
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')

$manifestPath = Join-Path $Mod 'mod.json'
if (-not (Test-Path $manifestPath)) { throw "$manifestPath not found." }
$m = Get-Content $manifestPath -Raw | ConvertFrom-Json
if (-not ($m.PSObject.Properties.Name -contains 'store')) { throw "$($m.name) has no storage page: only mods made with new-mod.ps1 -Kind data save data." }
$current = $(if ($m.store -and $m.store.url) { [string]$m.store.url } else { '' })

# The kit's page address lives in one place, new-mod.ps1 ($KitStoreUrl).
$kitUrl = $(if ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'new-mod.ps1')) -match "(?m)^\`$KitStoreUrl = '([^']+)'") { $Matches[1] } else { throw "new-mod.ps1 has no `$KitStoreUrl line." })
$kitPage = Join-Path $PSScriptRoot '..\store\index.html'
$marker = '<title>Deadlock mod storage page</title>'   # the shared page carries this; store/index.html
# The privacy phrase new-mod.ps1 writes for each kind of host (keep in sync with new-mod.ps1).
$runByKit = "which the author of deadlock-ai-mod-kit runs (not this mod's maker)"
$runByOwn = "which this mod's maker runs"

function Test-PageLive([string]$Url) {
  try { (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15 -Headers @{ 'Cache-Control' = 'no-cache' }).Content.Contains($marker) } catch { $false }
}

$gh = Find-Gh
function Invoke-Gh { $out = & $gh @args 2>&1; [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Out = ($out | Out-String).Trim() } }

if (-not $Publish) {
  Write-Host "Storage for $($m.name)"
  if ($current) {
    Write-Host "  address:    $current"
    if ($current -eq $kitUrl) { Write-Host "  page:       the kit's hosted page (run by the kit's author; no guarantee it stays online)" }
    else { Write-Host "  page:       the maker's own address" }
    if ($Offline) { Write-Host "  answers:    not checked (-Offline)" }
    elseif (Test-PageLive $current) { Write-Host "  answers:    yes" -ForegroundColor Green }
    else { Write-Host "  answers:    NO (not published yet, still deploying, offline, or not the kit's store/index.html)" -ForegroundColor Yellow }
  }
  else { Write-Host "  address:    none. Make the mod again with new-mod.ps1 -StoreUrl, or host your own: store.ps1 -Mod $Mod -Publish" -ForegroundColor Yellow }
  if (-not $gh) { Write-Host "  GitHub CLI: missing (only for -Publish: setup.ps1 -Approve gh)" }
  elseif ((Invoke-Gh auth status).Ok) { Write-Host "  GitHub:     signed in (for -Publish)" }
  else { Write-Host "  GitHub:     not signed in (only for -Publish; the user runs: gh auth login)" }
  exit 0
}

if (-not (Test-Path $kitPage)) { throw "The kit's storage page $kitPage is missing." }
if (-not $gh) { Write-Host "The GitHub CLI is missing. Install it with setup.ps1 -Approve gh (after the user's yes)." -ForegroundColor Yellow; exit 2 }
if (-not (Invoke-Gh auth status).Ok) {
  Write-Host "Not signed in to GitHub. The user signs in once (free account; a browser opens):" -ForegroundColor Yellow
  Write-Host "  gh auth login        (in Claude Code: type  ! gh auth login)"
  Write-Host "Then run store.ps1 -Publish again."
  exit 2
}
$login = (Invoke-Gh api user --jq .login).Out
if (-not $login) { throw "Couldn't read the GitHub user name (gh api user)." }
$login = $login.ToLowerInvariant()
if (-not $Repo) {
  # A mod made with -StoreUrl https://<login>.github.io/<repo>/ publishes to that repo.
  $Repo = $(if ($current -match "^https://$([regex]::Escape($login))\.github\.io/([A-Za-z0-9_.-]+)/$") { $Matches[1] } else { "$($m.name)-store" })
}
$url = "https://$login.github.io/$Repo/"
if ($current -and $current -ne $url -and -not $Force) {
  throw "This mod already saves through $current. Players' saved data stays with that address: moving to $url means they lose access to it, and nothing carries it over. Pass -Force only if nobody has used the mod yet."
}

Write-Host "Publishing the kit's storage page for $($m.name) as $login/$Repo" -ForegroundColor Cyan
$info = Invoke-Gh api "repos/$login/$Repo"
if (-not $info.Ok) {
  $made = Invoke-Gh api -X POST user/repos -f "name=$Repo" -f "description=Storage page for the Deadlock mod $($m.name) (no data is stored here)" -F private=false -F auto_init=true
  if (-not $made.Ok) { throw "Couldn't create $login/$Repo`: $($made.Out)" }
  Write-Host "  created $login/$Repo"
  $info = Invoke-Gh api "repos/$login/$Repo"
}
$branch = $(try { ($info.Out | ConvertFrom-Json).default_branch } catch { $null }); if (-not $branch) { $branch = 'main' }

$existing = Invoke-Gh api "repos/$login/$Repo/contents/index.html?ref=$branch"
$sha = $(if ($existing.Ok) { try { ($existing.Out | ConvertFrom-Json).sha } catch { $null } })
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($kitPage))
$putArgs = @('api', '-X', 'PUT', "repos/$login/$Repo/contents/index.html", '-f', "message=Storage page for $($m.name) $($m.version)", '-f', "content=$b64", '-f', "branch=$branch")
if ($sha) { $putArgs += @('-f', "sha=$sha") }
$put = Invoke-Gh @putArgs
if (-not $put.Ok) { throw "Couldn't upload index.html: $($put.Out)" }
Write-Host "  uploaded index.html"

if (-not (Invoke-Gh api "repos/$login/$Repo/pages").Ok) {
  $pages = Invoke-Gh api -X POST "repos/$login/$Repo/pages" -f "source[branch]=$branch" -f 'source[path]=/'
  if (-not $pages.Ok) { throw "Couldn't turn on GitHub Pages: $($pages.Out)" }
  Write-Host "  turned on GitHub Pages"
}

if (-not $NoWait) {
  Write-Host "  waiting for $url (GitHub takes 1-10 minutes)..."
  $deadline = (Get-Date).AddMinutes(10); $live = $false
  while ((Get-Date) -lt $deadline) { if (Test-PageLive $url) { $live = $true; break }; Start-Sleep -Seconds 15 }
  if (-not $live) { Write-Warning "$url doesn't answer yet. It's still saved; check later with store.ps1 -Mod $Mod." }
  else { Write-Host "  live" -ForegroundColor Green }
}

# Record the address where the mod and the export read it.
if (-not $m.store) { $m.store = [pscustomobject]@{ url = '' } }
$m.store.url = $url
if ($m.privacy) {
  $p = ([string]$m.privacy).Replace('<page address>', $url).Replace($runByKit, $runByOwn)
  if ($current) { $p = $p.Replace($current, $url) }
  $m.privacy = $p
}
$m | ConvertTo-Json -Depth 5 | Set-Content $manifestPath -Encoding utf8
$storeJs = Join-Path $Mod "src\panorama\scripts\$($m.name)_store.js"
$js = @"
// The address of the storage page this mod saves through (docs/04-persistence-and-io.md). Written by
// store.ps1 -Publish. Players' saved data stays with this address: changing it later means players lose
// access to what they saved.
var $($m.name)StoreUrl = '$url';
"@
New-Item -ItemType Directory -Force -Path (Split-Path $storeJs) | Out-Null
[IO.File]::WriteAllText($storeJs, $js, [Text.UTF8Encoding]::new($false))
Write-Host "Done: $($m.name) saves through $url. Rebuild the mod (build.ps1 -Mod $Mod) to use it." -ForegroundColor Green
