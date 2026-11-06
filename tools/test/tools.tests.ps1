#Requires -Version 7
<#
.SYNOPSIS
  Regression tests for the tools, run against a fake Deadlock install in a temp folder. Touches
  nothing real: no network, no Steam, no game files; the pak registry is redirected to the temp folder.
  Run:  pwsh -File tools\test\tools.tests.ps1      (exit code = number of failed checks)
#>
$ErrorActionPreference = 'Stop'
$tools = Split-Path $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ("dltools_test_" + [guid]::NewGuid().ToString('N'))
$root = Join-Path $work 'Deadlock'
$citadel = Join-Path $root 'game\citadel'
$env:DEADLOCK_MODDING_REGISTRY = Join-Path $work 'paks.json'   # before loading the helpers, which read it
$env:DEADLOCK_MODDING_HOME = Join-Path $work 'kithome'
. (Join-Path $tools 'deadlock-paths.ps1')
if ($script:PakRegistryPath -ne $env:DEADLOCK_MODDING_REGISTRY) { throw "registry not redirected; refusing to run" }
$script:failures = 0

function Check([string]$What, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok    $What" -ForegroundColor Green }
  else { Write-Host "  FAIL  $What $Detail" -ForegroundColor Red; $script:failures++ }
}

# Minimal VPK v1 writer. $Files: path -> string content. Paths in $Chunked go to pakNN_000.vpk.
function New-TestVpk([string]$Path, [hashtable]$Files, [string[]]$Chunked = @()) {
  $tree = New-Object IO.MemoryStream; $dirData = New-Object IO.MemoryStream; $chunk = New-Object IO.MemoryStream
  $w = New-Object IO.BinaryWriter($tree)
  function Z([string]$s) { $w.Write([Text.Encoding]::UTF8.GetBytes($s)); $w.Write([byte]0) }
  $groups = $Files.Keys | Group-Object { [IO.Path]::GetExtension($_).TrimStart('.') }
  foreach ($g in $groups) {
    Z $g.Name
    foreach ($d in ($g.Group | Group-Object { $p = [IO.Path]::GetDirectoryName($_).Replace('\', '/'); if ($p) { $p } else { ' ' } })) {
      Z $d.Name
      foreach ($file in $d.Group) {
        $bytes = $(if ($Files[$file] -is [byte[]]) { $Files[$file] } else { [Text.Encoding]::UTF8.GetBytes($Files[$file]) })
        $inChunk = $Chunked -contains $file
        $target = $(if ($inChunk) { $chunk } else { $dirData })
        Z ([IO.Path]::GetFileNameWithoutExtension($file))
        $w.Write([uint32]0); $w.Write([uint16]0); $w.Write([uint16]$(if ($inChunk) { 0 } else { 0x7FFF }))
        $w.Write([uint32]$target.Length); $w.Write([uint32]$bytes.Length); $w.Write([uint16]0xFFFF)
        $target.Write($bytes, 0, $bytes.Length)
      }
      Z ''
    }
    Z ''
  }
  Z ''
  $out = New-Object IO.MemoryStream; $ow = New-Object IO.BinaryWriter($out)
  $ow.Write([uint32]0x55AA1234); $ow.Write([uint32]1); $ow.Write([uint32]$tree.Length)
  $ow.Write($tree.ToArray()); $ow.Write($dirData.ToArray())
  New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
  [IO.File]::WriteAllBytes($Path, $out.ToArray())
  if ($chunk.Length) { [IO.File]::WriteAllBytes(($Path -replace '_dir\.vpk$', '_000.vpk'), $chunk.ToArray()) }
}

function Set-Build([int]$Build) { Set-Content (Join-Path $citadel 'steam.inf') "ClientVersion=$Build`r`nServerVersion=$Build" }

# A fake Source2Viewer-CLI: "decompiles" a layout by writing $env:FAKE_S2V_XML to the requested path.
$fakeS2v = Join-Path $work 'bin\fake-s2v.ps1'
New-Item -ItemType Directory -Force -Path (Split-Path $fakeS2v) | Out-Null
# Like S2V 20.1: a -f filter matching exactly one file makes -o that file's output path.
Set-Content $fakeS2v @'
$o = [array]::IndexOf($args, '-o')
if ([array]::IndexOf($args, '-f') -lt 0 -or [array]::IndexOf($args, '-d') -lt 0) { exit 1 }
if ($args[[array]::IndexOf($args, '-f') + 1] -match ',') { Copy-Item (Join-Path $env:FAKE_S2V_TREE '*') $args[$o + 1] -Recurse -Force; exit 0 }   # several filters: a folder of outputs
New-Item -ItemType Directory -Force -Path (Split-Path $args[$o + 1]) | Out-Null
[IO.File]::WriteAllText($args[$o + 1], $env:FAKE_S2V_XML)
exit 0
'@
$env:S2V_CLI = $fakeS2v
$xml6796 = "<root>`r`n`t<styles>`r`n`t`t<include src=`"s2r://panorama/styles/base.vcss`" />`r`n`t</styles>`r`n`t<CitadelOverlay class=`"HUDOverlay`" hittest=`"false`">`r`n`t`t<ToastManager id=`"ToastManager`" toastduration=`"5.0s`" />`r`n`t</CitadelOverlay>`r`n</root>`r`n"
$env:FAKE_S2V_XML = $xml6796

try {
  # Fake install: Valve-shaped gameinfo.gi (CRLF, tabs, comments with braces), steam.inf, pak01_dir.vpk.
  New-Item -ItemType Directory -Force -Path $citadel | Out-Null
  $gameinfo = @"
"GameInfo"
{
	game		"citadel"
	FileSystem
	{
		// comment { with braces }
		SearchPaths
		{
			// These are optional language paths. {
			Game_UILanguage		citadel_*LANGUAGE*
			Game_LowViolence	citadel_lv

			Game				citadel
			Game				core
		}
	}
	SceneSystem
	{
		SunLightShadowCascadeCount	3
	}
}
"@ -replace "`r?`n", "`r`n"
  [IO.File]::WriteAllText((Join-Path $citadel 'gameinfo.gi'), $gameinfo)
  Set-Build 6796
  New-TestVpk (Join-Path $citadel 'pak01_dir.vpk') @{
    'panorama/layout/citadel_hud_and_db_overlay.vxml_c' = 'LAYOUT'
    'sounds/ui/click.vsnd_c'                            = 'CLICK-SOUND'
    'sounds/ui/ui_shop_purchase_item_01.vsnd_c'         = 'KACHING'
    'sounds/ui/ui_menu_hover_01.vsnd_c'                 = 'HOVER1'
    'sounds/ui/ui_menu_activate.vsnd_c'                 = 'ACTIVATE'
  } -Chunked @('sounds/ui/click.vsnd_c')

  Write-Host "VPK reader"
  $entries = @(Read-VpkTree (Join-Path $citadel 'pak01_dir.vpk'))
  Check 'lists every file' ($entries.Count -eq 5)
  Check 'filter is a case-insensitive prefix' (@(Read-VpkTree (Join-Path $citadel 'pak01_dir.vpk') 'SOUNDS/UI/C').Count -eq 1)
  $click = $entries | Where-Object Path -eq 'sounds/ui/click.vsnd_c'
  Export-VpkFile $click (Join-Path $work 'click.vsnd_c')
  Check 'extracts from a numbered chunk' ([IO.File]::ReadAllText((Join-Path $work 'click.vsnd_c')) -eq 'CLICK-SOUND')

  Write-Host "VPK writer"
  $stage = Join-Path $work 'stage'
  New-Item -ItemType Directory -Force -Path (Join-Path $stage 'Sounds\UI'), (Join-Path $stage 'panorama') | Out-Null
  [IO.File]::WriteAllText((Join-Path $stage 'Sounds\UI\a.vsnd_c'), 'hello')
  [IO.File]::WriteAllText((Join-Path $stage 'panorama\b.vcss_c'), 'xyz')
  [IO.File]::WriteAllText((Join-Path $stage 'README.txt'), 'r')
  $packed = Join-Path $work 'pak64_dir.vpk'
  New-Vpk $stage $packed
  $back = @(Read-VpkTree $packed)
  Check 'round-trips paths (lowercased) and bytes' ((($back.Path | Sort-Object) -join ',') -eq 'panorama/b.vcss_c,readme.txt,sounds/ui/a.vsnd_c' -and [Text.Encoding]::ASCII.GetString([DeadlockModding.Vpk]::Extract(($back | Where-Object Path -eq 'sounds/ui/a.vsnd_c'))) -eq 'hello')
  Check 'CRC32 matches the standard (hello = 0x3610A686)' (($back | Where-Object Path -eq 'sounds/ui/a.vsnd_c').Crc -eq 0x3610A686)
  $b = [IO.File]::ReadAllBytes($packed); $ts = [BitConverter]::ToUInt32($b, 8); $fd = [BitConverter]::ToUInt32($b, 12); $o = 28 + $ts + $fd
  $md5 = [Security.Cryptography.MD5]::Create()
  $same = { param($x, $y) [Convert]::ToHexString($x) -eq [Convert]::ToHexString($y) }
  Check 'v2 header: no archive MD5s, 48-byte checksum section, no signature' ([BitConverter]::ToUInt32($b, 4) -eq 2 -and [BitConverter]::ToUInt32($b, 16) -eq 0 -and [BitConverter]::ToUInt32($b, 20) -eq 48 -and [BitConverter]::ToUInt32($b, 24) -eq 0 -and $b.Length -eq $o + 48)
  Check 'tree, archive-section and whole-file MD5s are valid' ((& $same $md5.ComputeHash($b, 28, $ts) $b[$o..($o + 15)]) -and (& $same $md5.ComputeHash([byte[]]@()) $b[($o + 16)..($o + 31)]) -and (& $same $md5.ComputeHash($b, 0, $o + 32) $b[($o + 32)..($o + 47)]))

  Write-Host "enable-addons.ps1"
  $gi = Join-Path $citadel 'gameinfo.gi'
  & (Join-Path $tools 'enable-addons.ps1') -GameInfo $gi -Check *> $null
  Check '-Check reports not mounted (exit 1)' ($LASTEXITCODE -eq 1)
  & (Join-Path $tools 'enable-addons.ps1') -GameInfo $gi *> $null
  $after = [IO.File]::ReadAllText($gi)
  Check 'mounts citadel/addons above Game citadel' ($after -match "Game\t+citadel/addons\r\n(.*\r\n){0,2}\t+Game\t+citadel\r\n")
  Check 'keeps CRLF line endings' (-not ($after -match "[^\r]\n"))
  Check 'leaves SceneSystem untouched' ($after.Contains("SceneSystem`r`n`t{`r`n`t`tSunLightShadowCascadeCount`t3"))
  & (Join-Path $tools 'enable-addons.ps1') -GameInfo $gi *> $null
  Check 'is idempotent' ([IO.File]::ReadAllText($gi) -eq $after)

  Write-Host "get-stock.ps1"
  $stock = Join-Path $work 'stock'
  & (Join-Path $tools 'get-stock.ps1') panorama/layout/citadel_hud_and_db_overlay.xml -Out $stock -Deadlock $root *> $null
  Check 'decompiles via Source2Viewer-CLI' ((Get-Content (Join-Path $stock 'panorama/layout/citadel_hud_and_db_overlay.xml') -Raw) -eq $xml6796)
  $rec = Get-Content (Join-Path $stock 'STOCK.json') -Raw | ConvertFrom-Json -AsHashtable
  Check 'records build and source' ($rec['panorama/layout/citadel_hud_and_db_overlay.xml'].build -eq 6796 -and $rec['panorama/layout/citadel_hud_and_db_overlay.xml'].source -eq 's2v')
  & (Join-Path $tools 'get-stock.ps1') sounds/ui/click.vsnd_c -Raw -Out $stock -Deadlock $root *> $null
  Check '-Raw copies compiled bytes' ([IO.File]::ReadAllText((Join-Path $stock 'sounds/ui/click.vsnd_c')) -eq 'CLICK-SOUND')
  & (Join-Path $tools 'get-stock.ps1') panorama/layout/missing.xml -Out $stock -Deadlock $root *> $null
  Check 'fails on files not in the build' ($LASTEXITCODE -eq 1)
  $listed = @(& (Join-Path $tools 'get-stock.ps1') -List panorama/ -Deadlock $root)
  Check '-List prints compiled paths' ($listed.Count -eq 1 -and $listed[0] -eq 'panorama/layout/citadel_hud_and_db_overlay.vxml_c')

  Write-Host "new-mod.ps1"
  $mods = Join-Path $work 'mods'
  & (Join-Path $tools 'new-mod.ps1') -Name hello -Dir $mods -Deadlock $root *> $null
  $hello = Join-Path $mods 'hello'
  $manifest = Get-Content (Join-Path $hello 'mod.json') -Raw | ConvertFrom-Json
  Check 'writes mod.json (pak 60, build 6796)' ($manifest.pak -eq 60 -and $manifest.gameBuild -eq 6796 -and $manifest.name -eq 'hello')
  $override = [IO.File]::ReadAllText((Join-Path $hello 'src/panorama/layout/citadel_hud_and_db_overlay.xml'))
  $expected = $xml6796.Replace("`t</styles>", "`t`t<include src=`"s2r://panorama/styles/hello.vcss_c`" />`r`n`t</styles>").Replace("`t</styles>`r`n", "`t</styles>`r`n`t<scripts>`r`n`t`t<include src=`"s2r://panorama/scripts/hello.vjs_c`" />`r`n`t</scripts>`r`n")
  Check 'override = stock + two includes' ($override -eq $expected)
  Check 'fills tokens in names and text' ((Test-Path (Join-Path $hello 'src/panorama/scripts/hello.js')) -and -not (Select-String -Path (Join-Path $hello '*'), (Join-Path $hello 'src/panorama/scripts/*') -Pattern '__(NAME|PAK|BUILD|HOOK)__' -Quiet))
  if (Get-Command node -ErrorAction SilentlyContinue) {
    Push-Location $hello; $null = node --test 2>&1; $nodeExit = $LASTEXITCODE; Pop-Location
    Check "starter's node tests pass" ($nodeExit -eq 0)
  }
  & (Join-Path $tools 'new-mod.ps1') -Name assets -Hook none -Dir $mods -Deadlock $root *> $null
  $m = Get-Content (Join-Path $mods 'assets/mod.json') -Raw | ConvertFrom-Json
  Check '-Hook none: empty kind, next free pak, no layout' ($m.kind -eq 'empty' -and $m.pak -eq 61 -and -not (Test-Path (Join-Path $mods 'assets/src/panorama')))

  Write-Host "new-mod.ps1 -Kind data + store.ps1"
  $dataMods = Join-Path $work 'datamods'
  $kitUrl = $(if ([IO.File]::ReadAllText((Join-Path $tools 'new-mod.ps1')) -match "(?m)^\`$KitStoreUrl = '([^']+)'") { $Matches[1] })
  $kitPage = [IO.File]::ReadAllText((Join-Path (Split-Path $tools) 'store/index.html'))
  Check 'the kit''s page address is one https constant in new-mod.ps1' ($kitUrl -match '^https://.+/$')
  Check 'the shared page carries the title store.ps1 looks for, and takes the namespace per request' ($kitPage.Contains('<title>Deadlock mod storage page</title>') -and $kitPage.Contains('"bad_ns"') -and -not $kitPage.Contains('NAMESPACE'))
  try { & (Join-Path $tools 'new-mod.ps1') -Name nostore -Kind data -Dir $dataMods -Deadlock $root *> $null; $msg = '' } catch { $msg = $_.Exception.Message }
  Check 'data: without -StoreUrl it stops and says what to ask (both choices and the warning)' ($msg -match '-StoreUrl kit' -and $msg -match 'own address' -and $msg -match 'no guarantee it stays online' -and $msg.Contains($kitUrl) -and -not (Test-Path (Join-Path $dataMods 'nostore')))
  try { & (Join-Path $tools 'new-mod.ps1') -Name plain -Kind data -StoreUrl http://example.com/ -Dir $dataMods -Deadlock $root *> $null; $msg = '' } catch { $msg = $_.Exception.Message }
  Check 'data: refuses an address that is not https' ($msg -match 'https' -and -not (Test-Path (Join-Path $dataMods 'plain')))

  & (Join-Path $tools 'new-mod.ps1') -Name notes -Kind data -StoreUrl kit -Dir $dataMods -Deadlock $root *> $null
  $notes = Join-Path $dataMods 'notes'
  $override = [IO.File]::ReadAllText((Join-Path $notes 'src/panorama/layout/citadel_hud_and_db_overlay.xml'))
  $order = @('notes_kvbridge', 'notes_store', 'notes') | ForEach-Object { $override.IndexOf("s2r://panorama/scripts/$_.vjs_c") }
  Check 'data: includes the storage client, the page address, then the feature script' ($order[0] -gt 0 -and $order[0] -lt $order[1] -and $order[1] -lt $order[2])
  Check 'data: the mod gets no store/ folder of its own' (-not (Test-Path (Join-Path $notes 'store')))
  $nm = Get-Content (Join-Path $notes 'mod.json') -Raw | ConvertFrom-Json
  $storeJs = [IO.File]::ReadAllText((Join-Path $notes 'src/panorama/scripts/notes_store.js'))
  $readme = [IO.File]::ReadAllText((Join-Path $notes 'README.md'))
  Check '-StoreUrl kit: the kit''s address lands in _store.js and mod.json' ($storeJs.Contains("var notesStoreUrl = '$kitUrl';") -and $nm.store.url -eq $kitUrl)
  Check '-StoreUrl kit: privacy names the address and who runs it; README carries the warning' ($nm.privacy.Contains($kitUrl) -and $nm.privacy -match 'author of deadlock-ai-mod-kit' -and $readme.Contains($kitUrl) -and $readme -match 'no guarantee it stays online')
  Check 'data: the feature passes its namespace to the bridge; no token is left' ([IO.File]::ReadAllText((Join-Path $notes 'src/panorama/scripts/notes.js')) -match "NS = 'notes\.v1'" -and -not (Select-String -Path (Join-Path $notes '*'), (Join-Path $notes 'src/panorama/scripts/*') -Pattern '__[A-Z_]+__' -Quiet))
  if (Get-Command node -ErrorAction SilentlyContinue) {
    Push-Location $notes; $null = node --test 2>&1; $nodeExit = $LASTEXITCODE; Pop-Location
    Check "data starter's node tests pass" ($nodeExit -eq 0)
  }
  & (Join-Path $tools 'new-mod.ps1') -Name mine -Kind data -StoreUrl https://testuser.github.io/mine-store -Dir $dataMods -Deadlock $root *> $null
  $mine = Join-Path $dataMods 'mine'
  $mm = Get-Content (Join-Path $mine 'mod.json') -Raw | ConvertFrom-Json
  $readme = [IO.File]::ReadAllText((Join-Path $mine 'README.md'))
  Check 'own address: lands verbatim (trailing slash added) in _store.js and mod.json' ($mm.store.url -eq 'https://testuser.github.io/mine-store/' -and [IO.File]::ReadAllText((Join-Path $mine 'src/panorama/scripts/mine_store.js')).Contains("var mineStoreUrl = 'https://testuser.github.io/mine-store/';"))
  Check 'own address: privacy says the maker runs it; README has no kit warning' ($mm.privacy -match "which this mod's maker runs" -and $readme -notmatch 'no guarantee' -and $readme -notmatch '(\r?\n){3}')

  $status = & (Join-Path $tools 'store.ps1') -Mod $notes -Offline *>&1 | Out-String
  Check 'store: status shows the address and that it is the kit''s page' ($LASTEXITCODE -eq 0 -and $status.Contains($kitUrl) -and $status -match "kit's hosted page")
  $status = & (Join-Path $tools 'store.ps1') -Mod $mine -Offline *>&1 | Out-String
  Check 'store: status shows an own address as the maker''s' ($status.Contains('https://testuser.github.io/mine-store/') -and $status -match "maker's own")

  # A fake GitHub CLI that keeps its state (signed in, repo, page, Pages) as files.
  $ghState = Join-Path $work 'gh'; New-Item -ItemType Directory -Force $ghState | Out-Null
  $env:FAKE_GH_STATE = $ghState
  $env:DEADLOCK_MODDING_GH = Join-Path $work 'bin\fake-gh.ps1'
  Set-Content $env:DEADLOCK_MODDING_GH @'
$s = $env:FAKE_GH_STATE; Add-Content (Join-Path $s 'calls.log') ($args -join ' ')
$a = $args -join ' '
function Has($f) { Test-Path (Join-Path $s $f) }
if ($a -eq 'auth status') { if (Has 'signed') { exit 0 } else { exit 1 } }
if ($a -eq 'api user --jq .login') { 'TestUser'; exit 0 }
if ($a -match '^api -X POST user/repos') { New-Item (Join-Path $s 'repo') | Out-Null; exit 0 }
if ($a -match '^api -X PUT .*/contents/index\.html') { $c = ($args | Where-Object { $_ -like 'content=*' }) -replace '^content=', ''; [IO.File]::WriteAllBytes((Join-Path $s 'content'), [Convert]::FromBase64String($c)); exit 0 }
if ($a -match '^api -X POST .*/pages') { New-Item (Join-Path $s 'pages') | Out-Null; exit 0 }
if ($a -match '^api repos/TestUser/[^/ ]+/contents/') { if (Has 'content') { '{"sha":"abc"}'; exit 0 } else { exit 1 } }
if ($a -match '^api repos/TestUser/[^/ ]+/pages$') { if (Has 'pages') { exit 0 } else { exit 1 } }
if ($a -match '^api repos/TestUser/[^/ ]+$') { if (Has 'repo') { '{"default_branch":"main"}'; exit 0 } else { exit 1 } }
exit 9
'@
  & (Join-Path $tools 'store.ps1') -Mod $mine -Publish -NoWait *> $null
  Check 'store: not signed in exits 2 and creates nothing' ($LASTEXITCODE -eq 2 -and -not (Test-Path (Join-Path $ghState 'repo')))
  New-Item (Join-Path $ghState 'signed') | Out-Null
  & (Join-Path $tools 'store.ps1') -Mod $mine -Publish -NoWait *> $null
  $mm = Get-Content (Join-Path $mine 'mod.json') -Raw | ConvertFrom-Json
  Check 'store: -Publish creates the repo in the mod''s address, uploads the kit''s page, turns on Pages' ((Test-Path (Join-Path $ghState 'repo')) -and (Test-Path (Join-Path $ghState 'pages')) -and [IO.File]::ReadAllText((Join-Path $ghState 'content')) -eq $kitPage -and (Get-Content (Join-Path $ghState 'calls.log')) -match 'name=mine-store')
  Check 'store: the mod keeps its address' ($mm.store.url -eq 'https://testuser.github.io/mine-store/' -and [IO.File]::ReadAllText((Join-Path $mine 'src/panorama/scripts/mine_store.js')).Contains("var mineStoreUrl = 'https://testuser.github.io/mine-store/';"))
  & (Join-Path $tools 'store.ps1') -Mod $mine -Publish -NoWait *> $null
  Check 'store: re-publishing updates the page in place (sends its sha)' ($LASTEXITCODE -eq 0 -and (Get-Content (Join-Path $ghState 'calls.log') | Where-Object { $_ -match 'PUT' } | Select-Object -Last 1) -match 'sha=abc')
  try { & (Join-Path $tools 'store.ps1') -Mod $mine -Publish -Repo other-store -NoWait *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'saved data stays' }
  Check 'store: refuses to move a mod to a different address' $threw
  try { & (Join-Path $tools 'store.ps1') -Mod $notes -Publish -NoWait *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'saved data stays' }
  Check 'store: refuses to move a mod off the kit''s page without -Force' ($threw -and (Get-Content (Join-Path $notes 'mod.json') -Raw | ConvertFrom-Json).store.url -eq $kitUrl)
  & (Join-Path $tools 'store.ps1') -Mod $notes -Publish -Force -NoWait *> $null
  $nm = Get-Content (Join-Path $notes 'mod.json') -Raw | ConvertFrom-Json
  $storeJs = [IO.File]::ReadAllText((Join-Path $notes 'src/panorama/scripts/notes_store.js'))
  Check 'store: -Force moves it, rewriting mod.json, privacy text and the mod''s script' ($nm.store.url -eq 'https://testuser.github.io/notes-store/' -and $nm.privacy -match 'testuser\.github\.io/notes-store' -and $nm.privacy -match "which this mod's maker runs" -and -not $nm.privacy.Contains($kitUrl) -and $storeJs -match "var notesStoreUrl = 'https://testuser\.github\.io/notes-store/';")
  Remove-Item Env:\DEADLOCK_MODDING_GH, Env:\FAKE_GH_STATE
  & (Join-Path $tools 'new-mod.ps1') -Name unpub -Kind data -StoreUrl kit -Dir $dataMods -Deadlock $root *> $null
  $um = Get-Content (Join-Path $dataMods 'unpub/mod.json') -Raw | ConvertFrom-Json; $um.store.url = ''
  $um | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $dataMods 'unpub/mod.json') -Encoding utf8
  try { & (Join-Path $tools 'export.ps1') -Mod (Join-Path $dataMods 'unpub') -Deadlock $root -NoBuild *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'no storage page address' }
  Check 'export refuses a data mod with no storage page address' $threw

  Write-Host "new-mod.ps1 -Kind sound + build.ps1 without a compiler"
  & (Join-Path $tools 'new-mod.ps1') -Name firstlight -Kind sound -Dir $mods -Deadlock $root *> $null
  $fl = Join-Path $mods 'firstlight'
  $hover = Join-Path $fl 'src/sounds/ui/ui_menu_hover_01.vsnd_c'
  Check 'copies the donor sound over every ui_menu_ sound' ((Test-Path $hover) -and [IO.File]::ReadAllText($hover) -eq 'KACHING' -and [IO.File]::ReadAllText((Join-Path $fl 'src/sounds/ui/ui_menu_activate.vsnd_c')) -eq 'KACHING' -and @(Get-ChildItem (Join-Path $fl 'src') -Recurse -File).Count -eq 2)
  New-Item -ItemType Directory -Force -Path (Join-Path $citadel 'addons') | Out-Null
  & (Join-Path $tools 'build.ps1') -Mod $fl -Deadlock $root -Csdk (Join-Path $work 'nocsdk') -Install *> $null
  $inst = Join-Path $citadel ('addons/pak{0:D2}_dir.vpk' -f (Get-Content (Join-Path $fl 'mod.json') -Raw | ConvertFrom-Json).pak)
  Check 'builds and installs with no CSDK, registering the pak' ((Test-Path $inst) -and @(Read-VpkTree $inst).Count -eq 2 -and (Get-PakRegistry)[(Split-Path $inst -Leaf)] -eq 'firstlight')
  try { & (Join-Path $tools 'build.ps1') -Mod $hello -Deadlock $root -Csdk (Join-Path $work 'nocsdk') *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'Reduced CSDK 12' }
  Check 'a UI mod without CSDK fails with a clear message' $threw
  Remove-Item $inst
  $reg = Get-PakRegistry; $reg.Remove((Split-Path $inst -Leaf)); Save-PakRegistry $reg

  Write-Host "build.ps1 mod.json copies"
  $cp = Join-Path $work 'cpmod'; New-Item -ItemType Directory -Force $cp | Out-Null
  '{ "name": "cpmod", "pak": 70, "gameBuild": 6796, "copies": { "sounds/hit_indicators/damage_send_lethal_01.vsnd_c": "sounds/ui/ui_shop_purchase_item_01.vsnd_c" } }' | Set-Content (Join-Path $cp 'mod.json')
  & (Join-Path $tools 'build.ps1') -Mod $cp -Deadlock $root -Csdk (Join-Path $work 'nocsdk') *> $null
  $e = @(Read-VpkTree (Join-Path $cp 'dist/pak70_dir.vpk'))
  Check 'packs the donor from the game under the target path, with no src folder' ($e.Count -eq 1 -and $e[0].Path -eq 'sounds/hit_indicators/damage_send_lethal_01.vsnd_c' -and [Text.Encoding]::ASCII.GetString([DeadlockModding.Vpk]::Extract($e[0])) -eq 'KACHING')
  '{ "name": "cpmod", "pak": 70, "copies": { "sounds/x.vsnd_c": "sounds/not_in_build.vsnd_c" } }' | Set-Content (Join-Path $cp 'mod.json')
  try { & (Join-Path $tools 'build.ps1') -Mod $cp -Deadlock $root *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'Donor not in this game build' }
  Check 'a donor missing from the build fails clearly' $threw

  Write-Host "build.ps1 models and textures (fake resourcecompiler)"
  # A real resourcecompiler.exe stand-in: a tiny C# launcher runs resourcecompiler.ps1 next to it. The script
  # writes <content path> -> <game path>_c, and fails a .vmdl whose referenced mesh wasn't staged.
  $rcDir = Join-Path $work 'fakecsdk\game\bin_cs2\win64'; New-Item -ItemType Directory -Force $rcDir | Out-Null
  $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  Set-Content (Join-Path $work 'rc.cs') 'using System.Diagnostics; using System.IO; using System.Linq; class P { static int Main(string[] a) { var s = Path.ChangeExtension(Process.GetCurrentProcess().MainModule.FileName, ".ps1"); var p = Process.Start(new ProcessStartInfo("pwsh", "-NoProfile -File \"" + s + "\" " + string.Join(" ", a.Select(x => "\"" + x + "\""))) { UseShellExecute = false }); p.WaitForExit(); return p.ExitCode; } }'
  & $csc /nologo "/out:$(Join-Path $rcDir 'resourcecompiler.exe')" (Join-Path $work 'rc.cs') | Out-Null
  Set-Content (Join-Path $rcDir 'resourcecompiler.ps1') @'
for ($i = 0; $i -lt $args.Count; $i++) {
  if ($args[$i] -ne '-i') { continue }
  $in = $args[++$i]; $root = $in -replace '(\\citadel_addons\\[^\\]+)\\.*$', '$1'
  foreach ($m in [regex]::Matches([IO.File]::ReadAllText($in), '"([^"]+\.(?:obj|fbx|dmx|dae))"')) { if (-not (Test-Path (Join-Path $root $m.Groups[1].Value))) { exit 1 } }
  $out = ($in -replace '\\content\\', '\game\') + '_c'
  New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
  Set-Content $out 'COMPILED'
  # A .vmdl gets mesh blocks (MVTX, MDAT) unless its mesh file says EMPTY, like an FBX the importer can't read.
  if ($in -match '\.vmdl$' -and -not ([regex]::Matches([IO.File]::ReadAllText($in), '"([^"]+\.(?:obj|fbx|dmx))"') | Where-Object { [IO.File]::ReadAllText((Join-Path $root $_.Groups[1].Value)) -match 'EMPTY' })) {
    [IO.File]::WriteAllBytes($out, [byte[]](0,0,0,0, 12,0, 0,0, 8,0,0,0, 2,0,0,0) + [Text.Encoding]::ASCII.GetBytes('MVTX') + (New-Object byte[] 8) + [Text.Encoding]::ASCII.GetBytes('MDAT') + (New-Object byte[] 8))
  }
  # A .vmat also writes a texture per png it names, and the materials/default texture it falls back on.
  if ($in -match '\.vmat$') {
    $g = $root -replace '\\content\\', '\game\'
    foreach ($p in [regex]::Matches([IO.File]::ReadAllText($in), '"([^"]+)\.png"')) { $t = Join-Path $g ($p.Groups[1].Value + '_png_0123abcd.vtex_c'); New-Item -ItemType Directory -Force (Split-Path $t) | Out-Null; Set-Content $t 'TEX' }
    New-Item -ItemType Directory -Force (Join-Path $g 'materials\default') | Out-Null; Set-Content (Join-Path $g 'materials\default\default_normal_tga_7be61377.vtex_c') 'DEFAULT'
  }
}
exit 0
'@
  $ms = Join-Path $work 'modelsrc'
  New-Item -ItemType Directory -Force (Join-Path $ms 'models/hideout'), (Join-Path $ms 'materials/mine') | Out-Null
  Set-Content (Join-Path $ms 'models/hideout/fortune_teller.vmdl') "{ _class = `"RenderMeshFile`" filename = `"models/hideout/cube.obj`" }"
  Set-Content (Join-Path $ms 'models/hideout/cube.obj') 'v 0 0 0'
  Set-Content (Join-Path $ms 'materials/mine/color.vtex') '"m_fileName" "string" "materials/mine/color.png"'
  Set-Content (Join-Path $ms 'materials/mine/color.png') 'PNG'
  Set-Content (Join-Path $ms 'materials/mine/orphan.png') 'PNG'
  Set-Content (Join-Path $ms 'STOCK.json') '{}'
  # A flipbook: the .vtex names a .mks frame list, which names the frame pngs.
  Set-Content (Join-Path $ms 'materials/mine/spin.vtex') '"m_fileName" "string" "materials/mine/spin.mks"'
  Set-Content (Join-Path $ms 'materials/mine/spin.mks') "sequence 0`nLOOP`nframe spin_f00.png 1`nframe spin_f01.png 1"
  Set-Content (Join-Path $ms 'materials/mine/spin_f00.png') 'PNG'
  Set-Content (Join-Path $ms 'materials/mine/spin_f01.png') 'PNG'
  $bw = & (Join-Path $tools 'build.ps1') -Src $ms -Name modeltest -Pak 71 -Out (Join-Path $work 'modelout') -Csdk (Join-Path $work 'fakecsdk') 3>&1 6>$null | Out-String
  $e = @(Read-VpkTree (Join-Path $work 'modelout/pak71_dir.vpk') -ErrorAction SilentlyContinue).Path | Sort-Object
  Check 'compiles a .vmdl with its staged mesh; the mesh and png ship only compiled; src/STOCK.json is skipped' (($e -join ',') -eq 'materials/mine/color.vtex_c,materials/mine/spin.vtex_c,models/hideout/fortune_teller.vmdl_c') ($e -join ',')
  Check 'no warning for a mesh or a png a .vtex names; warns for an unused png' ($bw -notmatch 'cube\.obj' -and $bw -notmatch 'color\.png' -and $bw -match 'Image not compiled.*orphan\.png')
  Check 'no warning for flipbook frames a .vtex names through a .mks' ($bw -notmatch 'spin_f0')
  Remove-Item (Join-Path $ms 'models/hideout/fortune_teller.vmdl'), (Join-Path $ms 'materials/mine/color.vtex'), (Join-Path $ms 'materials/mine/spin.vtex'), (Join-Path $ms 'STOCK.json')
  Set-Content (Join-Path $ms 'models/hideout/keep.vsnd_c') 'C'   # something to pack, nothing to compile
  $bw = & (Join-Path $tools 'build.ps1') -Src $ms -Name modeltest -Pak 71 -Out (Join-Path $work 'modelout') -Csdk (Join-Path $work 'fakecsdk') 3>&1 6>$null | Out-String
  Check 'a mesh with no .vmdl warns it is not shipped, not "Skipped"' ($bw -match 'Mesh not shipped: models\\hideout\\cube\.obj' -and $bw -notmatch 'Skipped.*cube')

  Write-Host "build.ps1 model checks (fake resourcecompiler)"
  $mg = Join-Path $work 'modelgen\src'; New-Item -ItemType Directory -Force (Join-Path $mg 'models/thing') | Out-Null
  Set-Content (Join-Path $mg 'models/thing/thing.vmdl') "{ _class = `"RenderMeshFile`" filename = `"models/thing/thing.fbx`" }"
  Set-Content (Join-Path $mg 'models/thing/thing.fbx') 'EMPTY'
  try { & (Join-Path $tools 'build.ps1') -Src $mg -Name gentest -Pak 72 -Out (Join-Path $work 'genout') -Csdk (Join-Path $work 'fakecsdk') -Deadlock $root *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'compiled with no mesh' }
  Check 'a .vmdl that compiled with no mesh stops the build' ($threw -and -not (Test-Path (Join-Path $work 'genout/pak72_dir.vpk')))
  & (Join-Path $tools 'build.ps1') -Src $mg -Name gentest -Pak 72 -Out (Join-Path $work 'genout') -Csdk (Join-Path $work 'fakecsdk') -Deadlock $root -AllowEmptyModel *> $null
  Check '-AllowEmptyModel ships it anyway' (Test-Path (Join-Path $work 'genout/pak72_dir.vpk'))
  Set-Content (Join-Path $mg 'models/thing/thing.fbx') 'MESH'
  Set-Content (Join-Path $mg 'models/thing/skin.vmat') "`"Layer0`" { `"TextureColor1`" `"models/thing/skin.png`" }"
  Set-Content (Join-Path $mg 'models/thing/skin.png') 'PNG'
  $other = Join-Path $work 'Deadlock2'   # a game that has the default texture and, by chance, our texture's path
  New-TestVpk (Join-Path $other 'game/citadel/pak01_dir.vpk') @{ 'materials/default/default_normal_tga_7be61377.vtex_c' = 'D'; 'models/thing/skin_png_0123abcd.vtex_c' = 'OLD' }
  $bw = & (Join-Path $tools 'build.ps1') -Src $mg -Name gentest -Pak 72 -Out (Join-Path $work 'genout') -Csdk (Join-Path $work 'fakecsdk') -Deadlock $other 6>&1 | Out-String
  $e = @(Read-VpkTree (Join-Path $work 'genout/pak72_dir.vpk')).Path | Sort-Object
  Check 'generated: ships the texture its own png made, not the default texture the game has' (($e -join ',') -eq ((@('models/thing/skin.vmat_c', 'models/thing/skin_png_0123abcd.vtex_c', 'models/thing/thing.vmdl_c') | Sort-Object) -join ',') -and $bw -match 'not shipped, the game has it: materials\\default') ($e -join ',')
  & (Join-Path $tools 'build.ps1') -Src $mg -Name gentest -Pak 72 -Out (Join-Path $work 'genout') -Csdk (Join-Path $work 'fakecsdk') -Deadlock (Join-Path $work 'nogame') *> $null
  Check 'generated, game not found: still leaves out materials/default' (-not (@(Read-VpkTree (Join-Path $work 'genout/pak72_dir.vpk')).Path -match '^materials/default/'))

  Write-Host "convert-model.ps1 and preview-model.ps1 (built-in readers, fake Blender)"
  Add-Type -AssemblyName System.Drawing
  $tiny = New-Object Drawing.Bitmap 3, 5; $tiny.SetPixel(0, 0, [Drawing.Color]::Red); $ms2 = New-Object IO.MemoryStream; $tiny.Save($ms2, [Drawing.Imaging.ImageFormat]::Png); $tiny.Dispose()
  $bin = New-Object IO.MemoryStream; $bwr = New-Object IO.BinaryWriter($bin)
  foreach ($x in 0, 0, 0, 1, 0, 0, 0, 1, 0) { $bwr.Write([single]$x) }       # a triangle, 1 m wide and 1 m tall (glTF: Y up)
  foreach ($x in 0, 1, 1, 1, 0, 0) { $bwr.Write([single]$x) }
  foreach ($x in 0, 1, 2) { $bwr.Write([uint16]$x) }
  $gltfText = @{ asset = @{ version = '2.0' }; scene = 0; scenes = @(@{ nodes = @(0) }); nodes = @(@{ mesh = 0; name = 'Body' })
    meshes = @(@{ primitives = @(@{ attributes = @{ POSITION = 0; TEXCOORD_0 = 1 }; indices = 2; material = 0 }) })
    materials = @(@{ name = 'Red Paint'; pbrMetallicRoughness = @{ baseColorTexture = @{ index = 0 } } }); textures = @(@{ source = 0 })
    images = @(@{ uri = 'data:image/png;base64,' + [Convert]::ToBase64String($ms2.ToArray()) })
    buffers = @(@{ byteLength = $bin.Length; uri = 'data:application/octet-stream;base64,' + [Convert]::ToBase64String($bin.ToArray()) })
    bufferViews = @(@{ buffer = 0; byteOffset = 0; byteLength = 36 }, @{ buffer = 0; byteOffset = 36; byteLength = 24 }, @{ buffer = 0; byteOffset = 60; byteLength = 6 })
    accessors = @(@{ bufferView = 0; componentType = 5126; count = 3; type = 'VEC3' }, @{ bufferView = 1; componentType = 5126; count = 3; type = 'VEC2' }, @{ bufferView = 2; componentType = 5123; count = 3; type = 'SCALAR' })
  } | ConvertTo-Json -Depth 8
  $cm = Join-Path $work 'cm'; New-Item -ItemType Directory -Force $cm | Out-Null
  Set-Content (Join-Path $cm 'tri.gltf') $gltfText
  $cOut = Join-Path $cm 'mod/src/models/x/thing'
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'tri.gltf') -Out $cOut -Name thing -Height 72 *> $null
  $obj = Get-Content (Join-Path $cOut 'thing.obj') -ErrorAction SilentlyContinue
  $ys = @($obj | Where-Object { $_ -match '^v ' } | ForEach-Object { [double]($_ -split ' ')[2] })
  Check 'gltf -> OBJ in inches, Y up, scaled to -Height' ($LASTEXITCODE -eq 0 -and ($ys | Measure-Object -Maximum).Maximum -gt 71.99 -and ($ys | Measure-Object -Maximum).Maximum -lt 72.01)
  Check 'usemtl is the full game path of a .vmat that names the colour png' (($obj -match '^usemtl ') -contains 'usemtl models/x/thing/thing_red_paint.vmat' -and (Get-Content (Join-Path $cOut 'thing_red_paint.vmat') -Raw) -match '"TextureColor1"\s+"models/x/thing/thing_red_paint_color\.png"')
  $vm = Get-Content (Join-Path $cOut 'thing_red_paint.vmat') -Raw -ErrorAction SilentlyContinue
  Check 'default vmat: pbr.vfx with NPR lighting, outline, status-effects proxy; constant non-metal and roughness; no glow' ($vm -match '"shader"\s+"pbr\.vfx"' -and $vm -match '"F_USE_NPR_LIGHTING"\s+"1"' -and $vm -match '"F_OVERRIDE_NPR_OUTLINE"\s+"1"' -and $vm -match '"F_USE_STATUS_EFFECTS_PROXY"\s+"1"' -and $vm -match '"g_flOverrideNprOutlineThickness"\s+"0\.05"' -and $vm -match '"TextureMetalness1"\s+"\[0\.0+ 0\.0+ 0\.0+ 0\.0+\]"' -and $vm -match '"TextureRoughness1"\s+"\[0\.7' -and $vm -notmatch 'F_SELF_ILLUM' -and $vm -notmatch 'DynamicParams') $vm
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'tri.gltf') -Out (Join-Path $cm 'mod/src/models/x/glow') -Name glow -Height 72 -Glow *> $null
  $vm = Get-Content (Join-Path $cm 'mod/src/models/x/glow/glow_red_paint.vmat') -Raw -ErrorAction SilentlyContinue
  Check '-Glow: NPR material plus the warm, even self-illum seen in-game' ($vm -match '"F_USE_NPR_LIGHTING"\s+"1"' -and $vm -match '"F_SELF_ILLUM"\s+"1"' -and $vm -match '"g_flSelfIllumScale1"\s+"0\.25"' -and $vm -match '"g_vSelfIllumTint1"\s+"\[0\.400000 0\.200000 0\.050000 0\.000000\]"' -and $vm -match '"TextureSelfIllumMask1"\s+"\[1\.0+ 1\.0+ 1\.0+ 0\.0+\]"') $vm
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'tri.gltf') -Out (Join-Path $cm 'mod/src/models/x/glow2') -Name g2 -Height 72 -Glow -GlowTint 0,0.5,1 *> $null
  Check '-GlowTint recolours the glow' ((Get-Content (Join-Path $cm 'mod/src/models/x/glow2/g2_red_paint.vmat') -Raw -ErrorAction SilentlyContinue) -match '"g_vSelfIllumTint1"\s+"\[0\.000000 0\.500000 1\.000000 0\.000000\]"')
  # A stock material as Source2Viewer-CLI decompiles it: flags, values, constant and file textures, compiled textures, DynamicParams.
  $fakeVmat = @'
"Layer0"
{
	"shader"	"pbr.vfx"
	"F_USE_NPR_LIGHTING"	"1"
	"F_SELF_ILLUM"	"1"
	"F_RIM_LIGHT"	"1"
	"g_flSelfIllumScale1"	"0"
	"g_vColorTint1"	"[0.500000 1.000000 1.000000 0.000000]"
	"TextureNprTramsissiveColor1"	"[0.070588 0.682353 0.925490 1.000000]"
	"TextureSelfIllumMask1"	"models/x/stock_glow_mask.png"
	"TextureColor1"	"models/x/stock_color.png"
	"TextureMetalness1"	"models/x/stock_metal.png"
	"TextureNormal1"	"models/x/stock_normal.png"
	"Compiled Textures"
	{
		"g_tColor"	"models/x/stock_color_png_1.vtex"
	}
	"DynamicParams"
	{
		"g_flSelfIllumScale1"	"return -.2*sin(3*time());"
		"g_vColorTint1"	"return 1;"
	}
}
'@
  Set-Content (Join-Path $cm 'stock.vmat') $fakeVmat
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'tri.gltf') -Out (Join-Path $cm 'mod/src/models/x/like') -Name like -Height 72 -LikeMaterial (Join-Path $cm 'stock.vmat') *> $null
  $vm = Get-Content (Join-Path $cm 'mod/src/models/x/like/like_red_paint.vmat') -Raw -ErrorAction SilentlyContinue
  Check '-LikeMaterial: copies the stock F_* flags, g_* values, constant textures and DynamicParams' ($vm -match '"F_USE_NPR_LIGHTING"\s+"1"' -and $vm -match '"F_RIM_LIGHT"\s+"1"' -and $vm -match '"g_vColorTint1"\s+"\[0\.5' -and $vm -match '"TextureNprTramsissiveColor1"\s+"\[0\.07' -and $vm -match '(?s)"DynamicParams"\s*\{\s*"g_flSelfIllumScale1"\s+"return -\.2\*sin\(3\*time\(\)\);".*"g_vColorTint1"') $vm
  Check '-LikeMaterial: drops stock texture files and compiled textures; colour is ours; metalness constant 0; masked glow off' ($vm -match '"TextureColor1"\s+"models/x/like/like_red_paint_color\.png"' -and $vm -notmatch 'stock_' -and $vm -notmatch 'Compiled Textures' -and $vm -notmatch 'TextureNormal1' -and $vm -match '"TextureMetalness1"\s+"\[0\.0+ 0\.0+ 0\.0+ 0\.0+\]"' -and $vm -match '"TextureSelfIllumMask1"\s+"\[0\.0+ 0\.0+ 0\.0+ 0\.0+\]"' -and $vm -notmatch '"F_USE_STATUS_EFFECTS_PROXY"') $vm
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'tri.gltf') -Out (Join-Path $cm 'mod/src/models/x/likeglow') -Name lg -Height 72 -LikeMaterial (Join-Path $cm 'stock.vmat') -Glow *> $null
  $vm = Get-Content (Join-Path $cm 'mod/src/models/x/likeglow/lg_red_paint.vmat') -Raw -ErrorAction SilentlyContinue
  Check '-LikeMaterial -Glow: the glow replaces the stock pulse (its DynamicParams entry goes, the rest stay)' ($vm -match '"g_flSelfIllumScale1"\s+"0\.25"' -and $vm -match '"TextureSelfIllumMask1"\s+"\[1\.0+' -and $vm -notmatch 'sin\(' -and $vm -match '"g_vColorTint1"\s+"return 1;"') $vm
  Set-Content (Join-Path $cm 'fit.obj') "v -1 0 0`nv 1 0 0`nv 0 20 0`nf 1 2 3"
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'tri.gltf') -Out (Join-Path $cm 'mod/src/models/x/likedef') -Name ld -Like (Join-Path $cm 'fit.obj') -LikeMaterial default *> $null
  $vm = Get-Content (Join-Path $cm 'mod/src/models/x/likedef/ld_red_paint.vmat') -Raw -ErrorAction SilentlyContinue
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'tri.gltf') -Out (Join-Path $cm 'mod/src/models/x/likecopy') -Name lc -Like (Join-Path $cm 'fit.obj') -CopyStockMaterial *> $null
  Check '-CopyStockMaterial with a source mesh as -Like (no stock material): the default NPR material' ($LASTEXITCODE -eq 0 -and (Get-Content (Join-Path $cm 'mod/src/models/x/likecopy/lc_red_paint.vmat') -Raw -ErrorAction SilentlyContinue) -match '"F_USE_STATUS_EFFECTS_PROXY"\s+"1"')
  Check '-LikeMaterial default: the default NPR material, nothing copied' ($LASTEXITCODE -eq 0 -and $vm -match '"F_USE_STATUS_EFFECTS_PROXY"\s+"1"' -and $vm -notmatch 'F_RIM_LIGHT') $vm
  Set-Content (Join-Path $cm 'other.vmat') "`"Layer0`"`n{`n`t`"shader`"`t`"csgo_unlitgeneric.vfx`"`n`t`"F_BLEND`"`t`"1`"`n}"
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'tri.gltf') -Out (Join-Path $cm 'mod/src/models/x/oth') -Name oth -Height 72 -LikeMaterial (Join-Path $cm 'other.vmat') *> $null
  $vm = Get-Content (Join-Path $cm 'mod/src/models/x/oth/oth_red_paint.vmat') -Raw -ErrorAction SilentlyContinue
  Check '-LikeMaterial with another shader: falls back to the default NPR material' ($vm -match '"shader"\s+"pbr\.vfx"' -and $vm -match '"F_USE_NPR_LIGHTING"\s+"1"' -and $vm -notmatch 'F_BLEND') $vm
  $png = $(if (Test-Path (Join-Path $cOut 'thing_red_paint_color.png')) { [Drawing.Image]::FromFile((Join-Path $cOut 'thing_red_paint_color.png')) })
  Check 'the embedded texture is written as a power-of-two png' ($png -and $png.Width -eq 4 -and $png.Height -eq 4); if ($png) { $png.Dispose() }
  # A Z-up OBJ: -UpAxis Z stands it up; -Like fits it to a stock model given as a file.
  Set-Content (Join-Path $cm 'zup.obj') "v 0 0 0`nv 2 0 0`nv 0 0 10`nf 1 2 3"
  Set-Content (Join-Path $cm 'stock.obj') "v -1 0 0`nv 1 0 0`nv 0 20 0`nf 1 2 3"         # Y up: 20 tall
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'zup.obj') -Out (Join-Path $cm 'zo') -GameDir models/x/zo -UpAxis Z -Like (Join-Path $cm 'stock.obj') *> $null
  $zo = @(Get-Content (Join-Path $cm 'zo/zup.obj') -ErrorAction SilentlyContinue | Where-Object { $_ -match '^v ' } | ForEach-Object { , [double[]](($_ -split ' ')[1..3]) })
  Check '-Like with a source mesh (no stock material): the default NPR material' ((Get-Content (Join-Path $cm 'zo/zup_default.vmat') -Raw -ErrorAction SilentlyContinue) -match '"F_USE_NPR_LIGHTING"\s+"1"')
  Check '-UpAxis Z stands a Z-up OBJ up; -Like matches the stock height and bottom' ($zo.Count -eq 3 -and ($zo | ForEach-Object { $_[1] } | Measure-Object -Maximum).Maximum -eq 20 -and ($zo | ForEach-Object { $_[1] } | Measure-Object -Minimum).Minimum -eq 0 -and $zo[2][0] -eq -2)
  try { & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'zup.obj') -Out (Join-Path $cm 'nosrc') *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match '-GameDir' }
  Check 'an -Out outside src without -GameDir is refused' $threw
  Set-Content (Join-Path $cm 'model.dae') '<COLLADA/>'
  $env:DEADLOCK_MODDING_BLENDER = Join-Path $work 'none\blender.exe'
  try { & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'model.dae') -Out $cOut *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'setup\.ps1 -Models' }
  Check '.dae without Blender: says it is optional and how to get it' $threw
  $env:DEADLOCK_MODDING_BLENDER = Join-Path $work 'bin\fake-blender.ps1'; $env:FAKE_BLENDER_GLTF = Join-Path $cm 'tri.gltf'; $env:FAKE_BLENDER_LOG = Join-Path $cm 'blender.log'
  Set-Content $env:DEADLOCK_MODDING_BLENDER 'Add-Content $env:FAKE_BLENDER_LOG ($args -join " "); Copy-Item $env:FAKE_BLENDER_GLTF $args[-1]; "CONVERT-OK 1 mesh object(s)"'
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'model.dae') -Out (Join-Path $cm 'mod/src/models/x/dae') -Name dae *> $null
  Check '.dae goes through Blender headless, then the same OBJ + vmat output' ($LASTEXITCODE -eq 0 -and (Get-Content $env:FAKE_BLENDER_LOG -Raw) -match '^-b --factory-startup .*--python \S+convert\.py -- \S+model\.dae \S+model\.gltf' -and (Test-Path (Join-Path $cm 'mod/src/models/x/dae/dae.obj')) -and (Test-Path (Join-Path $cm 'mod/src/models/x/dae/dae_red_paint.vmat')))
  Remove-Item Env:\FAKE_BLENDER_GLTF, Env:\FAKE_BLENDER_LOG
  $pv = & (Join-Path $tools 'preview-model.ps1') -Model (Join-Path $cm 'zup.obj') -Stock (Join-Path $cm 'stock.obj') -Out (Join-Path $cm 'p.png') 6>&1 | Out-String
  Check 'preview: draws a PNG, prints inch bounds, flags a lying-down mesh' ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $cm 'p.png')) -and $pv -match 'Z 0\.0\.\.20\.0' -and $pv -match 'WARN: orientation')
  $pv = & (Join-Path $tools 'preview-model.ps1') -Model (Join-Path $cm 'zo/zup.obj') -Stock (Join-Path $cm 'stock.obj') -Out (Join-Path $cm 'p2.png') 6>&1 | Out-String
  Check 'preview: no warnings once converted' ($LASTEXITCODE -eq 0 -and $pv -notmatch 'WARN')
  Set-Content (Join-Path $cm 'empty.obj') "v 0 0 0"
  & (Join-Path $tools 'preview-model.ps1') -Model (Join-Path $cm 'empty.obj') -NoStock -Out (Join-Path $cm 'p3.png') *> $null
  Check 'preview: a model with no mesh exits 1' ($LASTEXITCODE -eq 1)

  Write-Host "export.ps1"
  '{ "name": "cpmod", "pak": 70, "version": "1.2.0", "gameBuild": 6796, "author": "Tester", "copies": { "sounds/hit_indicators/damage_send_lethal_01.vsnd_c": "sounds/ui/ui_shop_purchase_item_01.vsnd_c" } }' | Set-Content (Join-Path $cp 'mod.json')
  $exp = (& (Join-Path $tools 'export.ps1') -Mod $cp -Deadlock $root 3>&1 6>&1 | Out-String)
  $zip = Join-Path $cp 'export/cpmod-1.2.0-b6796.zip'
  $names = $(if (Test-Path $zip) { Add-Type -AssemblyName System.IO.Compression.FileSystem; $z = [IO.Compression.ZipFile]::OpenRead($zip); @($z.Entries.FullName | Sort-Object); $z.Dispose() })
  Check 'exports a zip with the vpk, README.txt and LICENSE.txt' (($names -join ',') -eq 'LICENSE.txt,pak70_dir.vpk,README.txt') ($names -join ',')
  Check 'writes the GameBanana upload checklist next to it' (Test-Path (Join-Path $cp 'export/cpmod-gamebanana.md'))
  Check 'warns: not verified in-game, popular pak, no description' ($exp -match 'Not verified in-game' -and $exp -match 'pak70 is used by popular mods' -and $exp -match 'no "description"')
  $bad = Join-Path $work 'badmod'; New-Item -ItemType Directory -Force $bad | Out-Null
  '{ "name": "badmod", "pak": 45, "verified": 6796, "description": "x" }' | Set-Content (Join-Path $bad 'mod.json')
  New-TestVpk (Join-Path $bad 'dist/pak45_dir.vpk') @{ 'scripts/heroes.vdata_c' = 'H'; 'panorama/styles/x.css' = 'C' }
  try { & (Join-Path $tools 'export.ps1') -Mod $bad -Deadlock $root -NoBuild *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'Export stopped' }
  Check 'stops on core game data and raw source files' ($threw -and -not (Test-Path (Join-Path $bad 'export/badmod-0.1.0-b6796.zip')))

  Write-Host "mods.ps1"
  $addons = Join-Path $citadel 'addons'
  New-TestVpk (Join-Path $addons 'pak10_dir.vpk') @{ 'panorama/layout/a.vxml_c' = 'A10'; 'sounds/x.vsnd_c' = 'X' }
  New-TestVpk (Join-Path $addons 'pak20_dir.vpk') @{ 'panorama/layout/a.vxml_c' = 'A20' }
  New-TestVpk (Join-Path $addons 'pak30_dir.vpk') @{ 'models/m.vmdl_c' = 'M' } -Chunked @('models/m.vmdl_c')
  Save-PakRegistry @{ 'pak20_dir.vpk' = 'twenty' }
  $conflicts = (& (Join-Path $tools 'mods.ps1') conflicts -Deadlock $root 6>&1 | Out-String)
  Check 'conflicts: lower pak wins' ($conflicts -match 'panorama/layout/a\.vxml_c\s+pak10_dir\.vpk\s+pak20_dir\.vpk \(twenty\)')
  & (Join-Path $tools 'mods.ps1') disable 30 -Deadlock $root *> $null
  Check 'disable moves dir + chunks out of addons' (-not (Test-Path (Join-Path $addons 'pak30_000.vpk')) -and (Test-Path (Join-Path $citadel 'addons_disabled/pak30_000.vpk')))
  & (Join-Path $tools 'mods.ps1') enable pak30 -Deadlock $root *> $null
  Check 'enable moves them back' ((Test-Path (Join-Path $addons 'pak30_dir.vpk')) -and (Test-Path (Join-Path $addons 'pak30_000.vpk')))
  try { & (Join-Path $tools 'mods.ps1') remove twenty -Deadlock $root *> $null; $refused = $false } catch { $refused = $true }
  Check 'remove without -Yes refuses' ($refused -and (Test-Path (Join-Path $addons 'pak20_dir.vpk')))
  & (Join-Path $tools 'mods.ps1') remove twenty -Yes -Deadlock $root *> $null
  Check 'remove by mod name deletes it and its registry entry' (-not (Test-Path (Join-Path $addons 'pak20_dir.vpk')) -and -not (Get-PakRegistry).ContainsKey('pak20_dir.vpk'))

  Write-Host "new-mod.ps1 pak choice and hook warning"
  New-TestVpk (Join-Path $addons 'pak62_dir.vpk') @{ 'panorama/layout/citadel_hud_and_db_overlay.vxml_c' = 'OTHER' }
  $warn = & (Join-Path $tools 'new-mod.ps1') -Name third -Dir $mods -Deadlock $root 3>&1 6>$null | Out-String
  Check 'skips installed and sibling paks (60-62 taken -> 63)' ((Get-Content (Join-Path $mods 'third/mod.json') -Raw | ConvertFrom-Json).pak -eq 63)
  Check 'warns that a lower pak overrides the hook' ($warn -match 'pak62_dir\.vpk also overrides .* wins over this mod')
  Remove-Item (Join-Path $addons 'pak62_dir.vpk')

  if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "rebase.ps1"
    Set-Build 6800
    $env:FAKE_S2V_XML = $xml6796.Replace('toastduration="5.0s"', 'toastduration="3.0s"')
    & (Join-Path $tools 'rebase.ps1') -Mod $hello -Deadlock $root *> $null
    $merged = [IO.File]::ReadAllText((Join-Path $hello 'src/panorama/layout/citadel_hud_and_db_overlay.xml'))
    Check "merges Valve's change under the mod's includes" ($merged -eq $expected.Replace('toastduration="5.0s"', 'toastduration="3.0s"'))
    Check 'updates mod.json gameBuild' ((Get-Content (Join-Path $hello 'mod.json') -Raw | ConvertFrom-Json).gameBuild -eq 6800)
    Check 'keeps a backup outside src' (Test-Path (Join-Path $hello 'rebase-backup/panorama/layout/citadel_hud_and_db_overlay.xml'))

    Set-Build 6801
    $env:FAKE_S2V_XML = $xml6796.Replace('<include src="s2r://panorama/styles/base.vcss" />', '<include src="s2r://panorama/styles/base2.vcss" />')
    $o = Join-Path $hello 'src/panorama/layout/citadel_hud_and_db_overlay.xml'
    [IO.File]::WriteAllText($o, [IO.File]::ReadAllText($o).Replace('base.vcss', 'mine.vcss'))
    & (Join-Path $tools 'rebase.ps1') -Mod $hello -Deadlock $root *> $null
    Check 'conflict: exit 1 and markers left' ($LASTEXITCODE -eq 1 -and [IO.File]::ReadAllText($o).Contains('<<<<<<< your mod'))
    Check 'conflict: gameBuild unchanged' ((Get-Content (Join-Path $hello 'mod.json') -Raw | ConvertFrom-Json).gameBuild -eq 6800)
    & (Join-Path $tools 'rebase.ps1') -Mod $hello -Deadlock $root *> $null
    Check 're-run with unresolved markers still fails' ($LASTEXITCODE -eq 1)
  }

  Write-Host "doctor.ps1"
  $report = & (Join-Path $tools 'doctor.ps1') -Deadlock $root -Csdk (Join-Path $work 'nocsdk') -Offline 6>&1 | Out-String
  Check 'sees the mount and the missing CSDK' ($report -match 'mounts citadel/addons' -and $report -match 'CSDK 12 not found')

  Write-Host "mods.ps1 reset and enable-addons.ps1 -Disable"
  Save-PakRegistry @{ 'pak10_dir.vpk' = 'ten' }
  try { & (Join-Path $tools 'mods.ps1') reset -Deadlock $root *> $null; $refused = $false } catch { $refused = $true }
  Check 'reset without -Yes refuses' ($refused -and (Test-Path (Join-Path $addons 'pak10_dir.vpk')))
  & (Join-Path $tools 'mods.ps1') reset -Yes -Deadlock $root *> $null
  Check "reset removes the kit's paks, keeps others and the mount" (-not (Test-Path (Join-Path $addons 'pak10_dir.vpk')) -and (Test-Path (Join-Path $addons 'pak30_dir.vpk')) -and ([IO.File]::ReadAllText($gi) -match 'citadel/addons'))
  Remove-Item (Join-Path $addons 'pak30_*.vpk')
  & (Join-Path $tools 'mods.ps1') reset -Yes -Deadlock $root *> $null
  Check 'reset with no other mods restores Valve''s gameinfo.gi exactly' ([IO.File]::ReadAllText($gi) -eq [IO.File]::ReadAllText("$gi.pre-addons.bak"))
  & (Join-Path $tools 'enable-addons.ps1') -GameInfo $gi -Disable *> $null
  Check '-Disable when not mounted changes nothing' ([IO.File]::ReadAllText($gi) -eq [IO.File]::ReadAllText("$gi.pre-addons.bak"))

  Write-Host "setup.ps1"
  $kit = $env:DEADLOCK_MODDING_HOME
  $dl = Join-Path $work 'downloads'; New-Item -ItemType Directory -Force $dl | Out-Null
  $plan = & (Join-Path $tools 'setup.ps1') -DownloadsDir $dl 6>&1 | Out-String
  Check 'lists missing CSDK with its source and installs nothing' ($LASTEXITCODE -eq 0 -and $plan -match '\[csdk\] Reduced CSDK 12' -and $plan -match 'UNSIGNED' -and $plan -match 'setup\.ps1 -Approve .*csdk' -and -not (Test-Path (Join-Path $kit 'Reduced_CSDK_12')))
  & (Join-Path $tools 'setup.ps1') -DownloadsDir $dl -StrictExit *> $null
  Check '-StrictExit: a non-empty list exits 2 (waiting for the user''s yes)' ($LASTEXITCODE -eq 2)
  try { & (Join-Path $tools 'setup.ps1') -Approve bogus *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'Unknown id' }
  Check 'rejects unknown ids' $threw
  $quota = Join-Path $work 'quota.html'
  Set-Content $quota '<html><title>Google Drive - Quota exceeded</title>Too many users have viewed or downloaded this file recently.</html>'
  $env:DEADLOCK_MODDING_CSDK_URL = ([Uri]$quota).AbsoluteUri
  $out = & (Join-Path $tools 'setup.ps1') -Approve csdk -DownloadsDir $dl 6>&1 | Out-String
  Check "Drive's quota page -> exit 2, manual-download steps, no junk left" ($LASTEXITCODE -eq 2 -and $out -match 'download limit' -and $out -match 'deadlockmodding\.pages\.dev' -and -not (Test-Path (Join-Path $kit 'Reduced_CSDK_12.zip')))
  $fakeKit = Join-Path $work 'zipsrc'
  New-Item -ItemType Directory -Force (Join-Path $fakeKit 'Reduced_CSDK_12/game/bin_cs2/win64') | Out-Null
  Set-Content (Join-Path $fakeKit 'Reduced_CSDK_12/game/bin_cs2/win64/resourcecompiler.exe') 'RC'
  $zip = Join-Path $dl 'Reduced_CSDK_12.zip'
  Compress-Archive (Join-Path $fakeKit 'Reduced_CSDK_12') $zip
  & (Join-Path $tools 'setup.ps1') -Approve csdk -CsdkZip $zip -DownloadsDir $dl *> $null
  Check 'installs CSDK from a downloaded zip into the kit folder, keeps the user''s zip' ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $kit 'Reduced_CSDK_12/game/bin_cs2/win64/resourcecompiler.exe')) -and (Test-Path $zip) -and -not (Test-Path (Join-Path $kit 'csdk-unzip')))
  Check 'build and doctor find CSDK there by default' ((Find-Csdk) -eq (Join-Path $kit 'Reduced_CSDK_12'))
  $again = & (Join-Path $tools 'setup.ps1') -Approve csdk -DownloadsDir $dl 6>&1 | Out-String
  Check 'approved but present -> nothing to install' ($again -match 'already present')

  Write-Host "setup.ps1 -Media (optional yt-dlp and FFmpeg)"
  $env:DEADLOCK_MODDING_YTDLP = Join-Path $work 'none\yt-dlp.exe'; $env:DEADLOCK_MODDING_FFMPEG = Join-Path $work 'none\ffmpeg.exe'   # = not installed
  $plan = & (Join-Path $tools 'setup.ps1') -DownloadsDir $dl 6>&1 | Out-String
  Check 'media tools are not in the default list, only hinted' ($plan -notmatch '\[ytdlp\]' -and $plan -notmatch '-Approve .*ffmpeg' -and $plan -match 'setup\.ps1 -Media')
  $plan = & (Join-Path $tools 'setup.ps1') -Media -DownloadsDir $dl 6>&1 | Out-String
  Check '-Media lists both with source and unsigned notes' ($plan -match '\[ytdlp\] yt-dlp' -and $plan -match '\[ffmpeg\] FFmpeg' -and $plan -match 'yt-dlp/yt-dlp' -and $plan -match 'GyanD/codexffmpeg' -and $plan -match 'UNSIGNED single exe' -and $plan -match '-Approve .*ytdlp,ffmpeg')
  $rel = Join-Path $work 'releases'; New-Item -ItemType Directory -Force (Join-Path $rel 'ffsrc/ffmpeg-9.0.2-essentials_build/bin') | Out-Null
  Set-Content (Join-Path $rel 'yt-dlp.exe') 'YTDLP'
  Set-Content (Join-Path $rel 'ffsrc/ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe') 'FFMPEG'
  Compress-Archive (Join-Path $rel 'ffsrc/ffmpeg-9.0.2-essentials_build') (Join-Path $rel 'ffmpeg-9.0.2-essentials_build.zip')
  $relJson = { param($name, $hash) @{ tag_name = 't1'; assets = @(@{ name = $name; browser_download_url = ([Uri](Join-Path $rel $name)).AbsoluteUri; digest = "sha256:$hash" }) } | ConvertTo-Json -Depth 4 }
  $sha = { param($f) (Get-FileHash (Join-Path $rel $f) -Algorithm SHA256).Hash.ToLower() }
  Set-Content (Join-Path $rel 'yt.json') (& $relJson 'yt-dlp.exe' (& $sha 'yt-dlp.exe'))
  Set-Content (Join-Path $rel 'ff.json') (& $relJson 'ffmpeg-9.0.2-essentials_build.zip' (& $sha 'ffmpeg-9.0.2-essentials_build.zip'))
  $env:DEADLOCK_MODDING_YTDLP_API = ([Uri](Join-Path $rel 'yt.json')).AbsoluteUri; $env:DEADLOCK_MODDING_FFMPEG_API = ([Uri](Join-Path $rel 'ff.json')).AbsoluteUri
  & (Join-Path $tools 'setup.ps1') -Approve ytdlp, ffmpeg -DownloadsDir $dl *> $null
  $kb = Join-Path $kit 'bin'
  Check 'installs checksum-verified yt-dlp.exe and ffmpeg.exe into the kit bin, no leftovers' ($LASTEXITCODE -eq 0 -and (Get-Content (Join-Path $kb 'yt-dlp.exe')) -eq 'YTDLP' -and (Get-Content (Join-Path $kb 'ffmpeg.exe')) -eq 'FFMPEG' -and -not (Test-Path (Join-Path $kit 'ffmpeg.zip')) -and -not (Test-Path (Join-Path $kit 'ffmpeg-unzip')))
  Remove-Item (Join-Path $kb 'yt-dlp.exe')
  Set-Content (Join-Path $rel 'yt.json') (& $relJson 'yt-dlp.exe' ('0' * 64))
  & (Join-Path $tools 'setup.ps1') -Approve ytdlp -DownloadsDir $dl *> $null
  Check 'a checksum mismatch fails and installs nothing' ($LASTEXITCODE -eq 1 -and -not (Get-ChildItem $kb -Filter 'yt-dlp*'))
  Remove-Item Env:\DEADLOCK_MODDING_YTDLP_API, Env:\DEADLOCK_MODDING_FFMPEG_API

  Write-Host "setup.ps1 -Models (optional Blender)"
  $env:DEADLOCK_MODDING_BLENDER = Join-Path $work 'none\blender.exe'   # = not installed
  $plan = & (Join-Path $tools 'setup.ps1') -DownloadsDir $dl 6>&1 | Out-String
  Check 'Blender is not in the default list, only hinted' ($plan -notmatch '\[blender\]' -and $plan -match 'setup\.ps1 -Models')
  $plan = & (Join-Path $tools 'setup.ps1') -Models -DownloadsDir $dl 6>&1 | Out-String
  Check '-Models lists Blender 4.5 with its source and why it is pinned' ($plan -match '\[blender\] Blender 4\.5' -and $plan -match 'mirror\.blender\.org' -and $plan -match '5\.0 removed the \.dae importer' -and $plan -match '-Approve .*blender' -and $plan -notmatch '\[ytdlp\]')
  $mirror = Join-Path $work 'blendermirror'; New-Item -ItemType Directory -Force (Join-Path $rel 'bl/blender-4.5.10-windows-x64') | Out-Null
  Set-Content (Join-Path $rel 'bl/blender-4.5.10-windows-x64/blender.exe') 'BLENDER'
  New-Item -ItemType Directory -Force $mirror | Out-Null
  Compress-Archive (Join-Path $rel 'bl/blender-4.5.10-windows-x64') (Join-Path $mirror 'blender-4.5.10-windows-x64.zip')
  $bh = (Get-FileHash (Join-Path $mirror 'blender-4.5.10-windows-x64.zip') -Algorithm SHA256).Hash.ToLower()
  Set-Content (Join-Path $mirror 'blender-4.5.10.sha256') "$('1' * 64)  blender-4.5.10-linux-x64.tar.xz`n$bh  blender-4.5.10-windows-x64.zip"
  Set-Content (Join-Path $mirror 'blender-4.5.9.sha256') "$('0' * 64)  blender-4.5.9-windows-x64.zip"   # older: must not be picked
  $env:DEADLOCK_MODDING_BLENDER_MIRROR = ([Uri]($mirror + '\')).AbsoluteUri
  & (Join-Path $tools 'setup.ps1') -Approve blender -DownloadsDir $dl *> $null
  Check 'installs the newest 4.5.x, checksum-verified, into the kit folder; no leftovers' ($LASTEXITCODE -eq 0 -and (Get-Content (Join-Path $kit 'blender/blender.exe')) -eq 'BLENDER' -and -not (Test-Path (Join-Path $kit 'blender.zip')) -and -not (Test-Path (Join-Path $kit 'blender-unzip')))
  Remove-Item (Join-Path $kit 'blender') -Recurse
  Set-Content (Join-Path $mirror 'blender-4.5.10.sha256') "$('0' * 64)  blender-4.5.10-windows-x64.zip"
  & (Join-Path $tools 'setup.ps1') -Approve blender -DownloadsDir $dl *> $null
  Check 'a Blender checksum mismatch fails and installs nothing' ($LASTEXITCODE -eq 1 -and -not (Test-Path (Join-Path $kit 'blender')))
  $report = & (Join-Path $tools 'doctor.ps1') -Deadlock $root -Offline 6>&1 | Out-String
  Check 'doctor: Blender is an INFO line pointing at setup.ps1 -Models' ($report -match '\[INFO\] Blender not found: optional' -and $report -match 'setup\.ps1 -Models')
  Remove-Item Env:\DEADLOCK_MODDING_BLENDER_MIRROR, Env:\DEADLOCK_MODDING_BLENDER

  Write-Host "audio.ps1 (fake FFmpeg and yt-dlp)"
  $ffLog = Join-Path $work 'ff.log'; $env:FAKE_FF_LOG = $ffLog
  $env:DEADLOCK_MODDING_FFMPEG = Join-Path $work 'bin\fake-ffmpeg.ps1'; $env:DEADLOCK_MODDING_YTDLP = Join-Path $work 'bin\fake-ytdlp.ps1'
  # Writes a 44.1 kHz stereo WAV of $env:FAKE_FF_SECONDS (the input WAV's length, or the atrim length); "measures" -20 LUFS (a reference: -10).
  Set-Content $env:DEADLOCK_MODDING_FFMPEG @'
Add-Content $env:FAKE_FF_LOG ($args -join ' ')
$out = $args[-1]
if ($out -eq '-') { $i = $(if (($args -join ' ') -match 'ref\.wav') { '-10.0' } else { '-20.0' }); "{ `"input_i`" : `"$i`", `"input_tp`" : `"-6.0`" }"; exit 0 }
$secs = [double]$env:FAKE_FF_SECONDS
$in = $args[[array]::IndexOf($args, '-i') + 1]; if ($in -match '\.wav$') { $secs = [BitConverter]::ToUInt32([IO.File]::ReadAllBytes($in), 40) / (44100 * 4) }   # keeps the input's length
if (($args -join ' ') -match 'atrim=0:([\d.]+)') { $secs = [double]$Matches[1] }
$n = [int]($secs * 44100) * 4
$w = New-Object IO.BinaryWriter([IO.File]::Create($out))
$w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([uint32](36 + $n)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
$w.Write([uint32]16); $w.Write([uint16]1); $w.Write([uint16]2); $w.Write([uint32]44100); $w.Write([uint32](44100 * 4)); $w.Write([uint16]4); $w.Write([uint16]16)
$w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([uint32]$n); $w.Write((New-Object byte[] $n)); $w.Dispose()
exit 0
'@
  Set-Content $env:DEADLOCK_MODDING_YTDLP @'
Add-Content $env:FAKE_FF_LOG ('yt-dlp ' + ($args -join ' '))
$o = $args[[array]::IndexOf($args, '-o') + 1]; Set-Content ($o.Replace('%(ext)s', 'webm')) 'AUDIO'; exit 0
'@
  $audCat = Join-Path $work 'audcat'; New-Item -ItemType Directory -Force $audCat | Out-Null
  "event`tfile`tvsnd_files`tduration`nDamage.Send.Lethal`tsoundevents/hit.vsndevts`tsounds/hit_indicators/damage_send_lethal_01.vsnd_c,sounds/hit_indicators/damage_send_lethal_02.vsnd_c`t1.5" | Set-Content (Join-Path $audCat 'soundevents.tsv')
  $clip = Join-Path $work 'clip.mp3'; Set-Content $clip 'MP3'; $refWav = Join-Path $work 'ref.wav'; Set-Content $refWav 'REF'
  $env:FAKE_FF_SECONDS = '4'
  $wav = Join-Path $work 'aud\damage_send_lethal_01.wav'
  & (Join-Path $tools 'audio.ps1') $clip -Out $wav -Like sounds/hit_indicators/damage_send_lethal_01.vsnd_c -Catalog $audCat *> $null
  $hdr = $(if (Test-Path $wav) { [IO.File]::ReadAllBytes($wav) })
  $ff = Get-Content $ffLog -Raw
  Check 'file: cut to the stock length (catalog), 44.1 kHz, normalised to -16 LUFS' ($LASTEXITCODE -eq 0 -and $hdr -and [BitConverter]::ToUInt32($hdr, 24) -eq 44100 -and [BitConverter]::ToUInt32($hdr, 40) -eq [int](1.5 * 44100) * 4 -and $ff -match 'atrim=0:1\.5,afade=t=out' -and $ff -match '-ar 44100 -ac 2 -c:a pcm_s16le' -and $ff -match 'volume=4dB')
  Remove-Item $ffLog
  & (Join-Path $tools 'audio.ps1') 'https://example.com/watch?v=x' -Start 0:01 -End 0:02.5 -Like Damage.Send.Lethal -Catalog $audCat -NoTrim -Reference $refWav -Out $wav *> $null
  $ff = Get-Content $ffLog -Raw
  Check 'link: yt-dlp download, -Start/-End passed, -NoTrim keeps length, reference loudness capped at -1 dBFS peak' ($LASTEXITCODE -eq 0 -and $ff -match 'yt-dlp --no-playlist' -and $ff -match 'download\.webm -vn -ss 0:01 -to 0:02\.5' -and $ff -notmatch 'atrim' -and $ff -match 'volume=5dB' -and [BitConverter]::ToUInt32([IO.File]::ReadAllBytes($wav), 40) -eq 4 * 44100 * 4)
  try { & (Join-Path $tools 'audio.ps1') $clip -Out $wav -Start 5 -End 0:04 *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'must be after' }
  Check 'rejects -End before -Start' $threw
  $env:DEADLOCK_MODDING_FFMPEG = Join-Path $work 'none\ffmpeg.exe'
  try { & (Join-Path $tools 'audio.ps1') $clip -Out $wav *> $null; $threw = $false } catch { $threw = $_.Exception.Message -match 'setup\.ps1 -Media' }
  Check 'without FFmpeg: says it is optional and how to get it' $threw
  Remove-Item Env:\DEADLOCK_MODDING_YTDLP, Env:\DEADLOCK_MODDING_FFMPEG, Env:\FAKE_FF_LOG, Env:\FAKE_FF_SECONDS

  Write-Host "catalog.ps1"
  $env:FAKE_S2V_TREE = Join-Path $work 's2vtree'
  $fx = @{
    'soundevents/ui.vsndevts'        = "<!-- kv3 -->`n{`n`tUI.Click = `n`t{`n`t`tvsnd_files = `"sounds/ui/click.vsnd`"`n`t`tvsnd_duration = 0.2`n`t}`n`tUI.Hover = `n`t{`n`t`tvsnd_files = `n`t`t[`n`t`t`t`"sounds/ui/ui_menu_hover_01.vsnd`",`n`t`t`t`"sounds/ui/click.vsnd`",`n`t`t]`n`t}`n}`n"
    'scripts/heroes.vdata'           = "{`n`thero_base = `n`t{`n`t}`n`thero_orion = `n`t{`n`t`tm_HeroID = 17`n`t`tm_bDisabled = false`n`t`tm_strModelName = resource_name:`"models/heroes_staging/archer/archer.vmdl`"`n`t`tm_hGameSoundEventScript = resource_name:`"soundevents/hero/orion.vsndevts`"`n`t`tm_mapBoundAbilities = `n`t`t{`n`t`t`tESlot_Signature_1 = `"ability_charged_shot`"`n`t`t}`n`t}`n}`n"
    'panorama/layout/hud_minimap.xml' = "<!-- xml reconstructed -->`n<root>`n`t<styles>`n`t`t<include src=`"s2r://panorama/styles/hud_minimap.vcss`" />`n`t</styles>`n`t<Panel id=`"Minimap`">`n`t`t<Image id=`"MainImage`" />`n`t</Panel>`n</root>`n"
  }
  foreach ($k in $fx.Keys) { $f = Join-Path $env:FAKE_S2V_TREE $k; New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null; [IO.File]::WriteAllText($f, $fx[$k]) }
  $locDir = Join-Path $citadel 'resource/localization/citadel_gc_hero_names'; New-Item -ItemType Directory -Force $locDir | Out-Null
  Set-Content (Join-Path $locDir 'citadel_gc_hero_names_english.txt') "`"lang`"`n{`n`t`"Tokens`"`n`t{`n`t`t`"hero_orion:n`" `"Grey Talon`"`n`t}`n}"
  $cat = Join-Path $work 'catalog'
  & (Join-Path $tools 'catalog.ps1') -Deadlock $root -Out $cat *> $null
  $tsv = { param($n) @(Import-Csv (Join-Path $cat $n) -Delimiter "`t") }
  Check 'files.tsv lists every pak01 file' ((& $tsv 'files.tsv').Count -eq @(Read-VpkTree (Join-Path $citadel 'pak01_dir.vpk')).Count)
  $hover = (& $tsv 'soundevents.tsv') | Where-Object event -eq 'UI.Hover'
  Check 'soundevents: single-string and list vsnd_files, as .vsnd_c' ($hover.vsnd_files -eq 'sounds/ui/ui_menu_hover_01.vsnd_c,sounds/ui/click.vsnd_c' -and ((& $tsv 'soundevents.tsv') | Where-Object event -eq 'UI.Click').duration -eq '0.2')
  Check 'sounds: reverse map from file to events' (((& $tsv 'sounds.tsv') | Where-Object path -eq 'sounds/ui/click.vsnd_c').events -eq 'UI.Click,UI.Hover')
  $orion = (& $tsv 'heroes.tsv') | Where-Object codename -eq 'hero_orion'
  Check 'heroes: name, id, model folder, sound script, abilities; hero_base skipped' ($orion.name -eq 'Grey Talon' -and $orion.id -eq '17' -and $orion.model_folder -eq 'models/heroes_staging/archer' -and $orion.sound_script -eq 'soundevents/hero/orion.vsndevts' -and $orion.abilities -eq 'ability_charged_shot' -and (& $tsv 'heroes.tsv').Count -eq 1)
  $mm = (& $tsv 'ui.tsv') | Where-Object path -eq 'panorama/layout/hud_minimap.xml'
  Check 'ui: root panel, ids and style includes' ($mm.root -eq 'Panel' -and $mm.ids -eq 'Minimap,MainImage' -and $mm.styles -eq 'panorama/styles/hud_minimap.vcss')
  & (Join-Path $tools 'catalog.ps1') -Deadlock $root -Out $cat 6>$null | Out-Null
  Check 'skips a build already catalogued' ($LASTEXITCODE -eq 0)

  Write-Host "generate-docs.ps1 and doctor's generated/ check"
  $gb = Get-DeadlockBuild $root
  $gcat = Join-Path $env:DEADLOCK_MODDING_HOME "catalog\$gb"
  New-Item -ItemType Directory -Force $gcat | Out-Null
  $tsvs = @{
    'README.md'       = "# Deadlock build $gb catalog`n`nGenerated 2026-01-02 by catalog.ps1 from this PC's install.`n"
    'files.tsv'       = "path`tbytes`nsounds/ui/b.vsnd_c`t1048576`nsounds/ui/a.vsnd_c`t1048576`nsounds/vo/x/c.vsnd_c`t1048576`nmodels/x/m.vmdl_c`t10`npanorama/layout/hud.vxml_c`t5`nreadme.txt`t1`n"
    'soundevents.tsv' = "event`tfile`tvsnd_files`tduration`nUI.A`tsoundevents/ui.vsndevts`tsounds/ui/a.vsnd_c`t0.2`nUI.B`tsoundevents/ui.vsndevts`tsounds/ui/b.vsnd_c`t`n"
    'sounds.tsv'      = "path`tbytes`tevents`nsounds/ui/a.vsnd_c`t1048576`tUI.A`nsounds/ui/b.vsnd_c`t1048576`tUI.B`nsounds/vo/x/c.vsnd_c`t1048576`t`n"
    'heroes.tsv'      = "codename`tname`tid`tstate`tmodel`tmodel_folder`tsound_script`tvo_script`tabilities`nhero_orion`tGrey Talon`t17`t`tmodels/heroes_staging/archer/archer.vmdl`tmodels/heroes_staging/archer`tsoundevents/hero/orion.vsndevts`t`tability_a (A) | ability_b (B)`n"
    'ui.tsv'          = "path`troot`tids`tscripts`tstyles`npanorama/layout/hud.xml`tPanel`tMinimap,MainImage`t`tpanorama/styles/hud.vcss`n"
    'models.tsv'      = "path`taliases`tbytes`tanim`tskeleton`tmaterials`ttextures`tother`nmodels/x/m.vmdl_c`tbartender, hideout`t10`tclassic`tin model`t`t`t`n"
  }
  foreach ($k in $tsvs.Keys) { [IO.File]::WriteAllText((Join-Path $gcat $k), $tsvs[$k]) }
  $gen = Join-Path $work 'generated'
  & (Join-Path $tools 'generate-docs.ps1') -Deadlock $root -Out $gen *> $null
  $genNames = 'build.md', 'file-types.md', 'folders.md', 'heroes.md', 'ui-layouts.md', 'sounds.md', 'models.md'
  Check 'generate-docs: writes all seven files, never README.md (authored)' (@($genNames | Where-Object { Test-Path (Join-Path $gen $_) }).Count -eq 7 -and -not (Test-Path (Join-Path $gen 'README.md')))
  $heads = @($genNames | ForEach-Object { (Get-Content (Join-Path $gen $_) -TotalCount 1 -ErrorAction SilentlyContinue) })
  Check 'generate-docs: every header names the build and the catalog date' (@($heads | Where-Object { $_ -eq "<!-- GENERATED by tools/generate-docs.ps1 from Deadlock build $gb on 2026-01-02. Do not edit: regenerate. -->" }).Count -eq 7) ($heads -join ' / ')
  $first = @{}; foreach ($n in $genNames) { $first[$n] = [IO.File]::ReadAllBytes((Join-Path $gen $n)) }
  & (Join-Path $tools 'generate-docs.ps1') -Deadlock $root -Out $gen *> $null
  Check 'generate-docs: a second run is byte-identical' (@($genNames | Where-Object { [Convert]::ToBase64String($first[$_]) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $gen $_))) }).Count -eq 0)
  $ft = Get-Content (Join-Path $gen 'file-types.md') -Raw
  Check 'generate-docs: file-types counts, sizes, top folders, most common first' ($ft -match '\| `\.vsnd_c` \| 3 \| 3\.0 \| `sounds/ui` \(2\), `sounds/vo` \(1\) \| `sounds/ui/a\.vsnd_c` \|' -and $ft -match '\| `\.txt` \| 1 \|' -and $ft.IndexOf('.vsnd_c') -lt $ft.IndexOf('.vmdl_c')) $ft
  $hm = Get-Content (Join-Path $gen 'heroes.md') -Raw
  Check 'generate-docs: heroes escape the ability separator' ($hm -match 'ability_a \(A\) \\\| ability_b \(B\)')
  # build.md prints Valve's stock SearchPaths block either way, and says whether this PC mounts addons.
  $stockBlock = '(?s)```\n\t\tSearchPaths\n\t\t\{\n.*\t\t\tGame\t+citadel\n\t\t\tGame\t+core\n\t\t\}\n```'
  $bmStock = Get-Content (Join-Path $gen 'build.md') -Raw
  Check 'generate-docs: stock gameinfo.gi -> the stock block, "not mounted"' ($bmStock -match $stockBlock -and $bmStock -notmatch 'Game\t+citadel/addons' -and $bmStock -match 'does not have the kit''s `Game citadel/addons` line \(not mounted\)') $bmStock
  & (Join-Path $tools 'enable-addons.ps1') -GameInfo $gi *> $null
  $genM = Join-Path $work 'generated-mounted'
  & (Join-Path $tools 'generate-docs.ps1') -Deadlock $root -Out $genM *> $null
  $bmM = Get-Content (Join-Path $genM 'build.md') -Raw
  Check 'generate-docs: mounted gameinfo.gi -> the same stock block, "mounted"' (([IO.File]::ReadAllText($gi) -match 'citadel/addons') -and [regex]::Match($bmM, '(?s)```.*?```').Value -eq [regex]::Match($bmStock, '(?s)```.*?```').Value -and $bmM -match 'also has the kit''s `Game citadel/addons` line \(mounted\)') $bmM
  & (Join-Path $tools 'enable-addons.ps1') -GameInfo $gi -Disable *> $null
  $fakeGen = Join-Path $work 'fakegen'; New-Item -ItemType Directory -Force $fakeGen | Out-Null
  Set-Content (Join-Path $fakeGen 'README.md') "<!-- authored, ignored by the doctor: from Deadlock build 9999 -->"
  Set-Content (Join-Path $fakeGen 'build.md') "<!-- GENERATED by tools/generate-docs.ps1 from Deadlock build 1234 on 2026-01-01. Do not edit: regenerate. -->"
  $report = & (Join-Path $tools 'doctor.ps1') -Deadlock $root -Generated $fakeGen -Offline 6>&1 | Out-String
  Check 'doctor: warns when generated/ is for another build (read from build.md); the fix names setup.ps1 first' ($report -match "\[WARN\] generated/ describes build 1234, the game is build $gb" -and $report -match '-> Run setup\.ps1 .*generate-docs\.ps1.*catalog_refresh') $report
  Remove-Item (Join-Path $fakeGen 'build.md'); Set-Content (Join-Path $fakeGen 'heroes.md') "<!-- GENERATED by tools/generate-docs.ps1 from Deadlock build 1235 on 2026-01-01. Do not edit: regenerate. -->"
  $report = & (Join-Path $tools 'doctor.ps1') -Deadlock $root -Generated $fakeGen -Offline 6>&1 | Out-String
  Check 'doctor: without build.md, reads the build from another generated file, never README.md' ($report -match "\[WARN\] generated/ describes build 1235")
  $report = & (Join-Path $tools 'doctor.ps1') -Deadlock $root -Generated (Join-Path $work 'nogen') -Offline 6>&1 | Out-String
  Check 'doctor: warns when generated/ is missing' ($report -match "\[WARN\] generated/ is missing, the game is build $gb")
  $report = & (Join-Path $tools 'doctor.ps1') -Deadlock $root -Generated $gen -Offline 6>&1 | Out-String
  Check "doctor: OK when generated/ matches the game; no docs/ build warning" ($report -match "\[OK  \] generated/ describes build $gb" -and $report -notmatch 'last verified')

  Write-Host "setup.ps1 (root): doctor, the missing-tools list, generated/"
  $rootSetup = Join-Path (Split-Path $tools) 'setup.ps1'
  $kit = $env:DEADLOCK_MODDING_HOME
  $env:DEADLOCK_MODDING_GH = Join-Path $work 'bin\fake-gh.exe'; Set-Content $env:DEADLOCK_MODDING_GH 'GH'   # = installed, so the list is empty
  & (Join-Path $tools 'enable-addons.ps1') -GameInfo $gi *> $null   # mounted, so the doctor has no [FAIL]
  $giBefore = [IO.File]::ReadAllText($gi)
  $kitBefore = @(Get-ChildItem $kit -Recurse -File).Count
  $rgen = Join-Path $work 'rootgen'
  $out = & $rootSetup -Deadlock $root -Generated $rgen -Offline -DownloadsDir $dl 6>&1 | Out-String
  Check 'root setup, no args: doctor, list, builds generated/ (seven files, no README), exit 0' ($LASTEXITCODE -eq 0 -and $out -match 'Deadlock modding doctor' -and $out -match 'Nothing to install' -and $out -match "generated/ now describes build $gb" -and @(Get-ChildItem $rgen -File).Count -eq 7 -and -not (Test-Path (Join-Path $rgen 'README.md')) -and $out -match 'Ready:') $out
  Check 'root setup, no args: downloads nothing; the game and the kit folder are unchanged' ([IO.File]::ReadAllText($gi) -eq $giBefore -and @(Get-ChildItem $kit -Recurse -File).Count -eq $kitBefore)
  $out = & $rootSetup -Deadlock $root -Generated $rgen -Offline -DownloadsDir $dl 6>&1 | Out-String
  Check 'root setup: generated/ for this build is not rebuilt' ($LASTEXITCODE -eq 0 -and $out -match "generated/ already describes build $gb")
  Set-Content (Join-Path $rgen 'build.md') "<!-- GENERATED by tools/generate-docs.ps1 from Deadlock build 1234 on 2026-01-01. Do not edit: regenerate. -->"
  $out = & $rootSetup -Deadlock $root -Generated $rgen -Offline -DownloadsDir $dl -SkipData 6>&1 | Out-String
  Check 'root setup -SkipData: leaves a stale generated/ alone, exit 0' ($LASTEXITCODE -eq 0 -and $out -match 'Skipped \(-SkipData\)' -and (Get-GeneratedBuild $rgen) -eq 1234)
  $out = & $rootSetup -Deadlock $root -Generated $rgen -Offline -DownloadsDir $dl 6>&1 | Out-String
  Check 'root setup: generated/ for another build is rebuilt' ($LASTEXITCODE -eq 0 -and $out -match 'describes build 1234; reading' -and (Get-GeneratedBuild $rgen) -eq $gb)
  Rename-Item (Join-Path $kit 'Reduced_CSDK_12') 'csdk-away'
  $out = & $rootSetup -Deadlock $root -Generated $rgen -Offline -DownloadsDir $dl 6>&1 | Out-String
  Check 'root setup: a missing tool -> listed, nothing installed, exit 2 (waiting for the user)' ($LASTEXITCODE -eq 2 -and $out -match '\[csdk\] Reduced CSDK 12' -and $out -match 'Next: show the user the list' -and -not (Test-Path (Join-Path $kit 'Reduced_CSDK_12')))
  Rename-Item (Join-Path $kit 'csdk-away') 'Reduced_CSDK_12'
  $out = & $rootSetup -Approve bogus -Deadlock $root -Generated $rgen -Offline -DownloadsDir $dl 6>&1 | Out-String
  Check 'root setup -Approve bogus: refused, exit 1' ($LASTEXITCODE -eq 1 -and $out -match 'Unknown id' -and $out -match 'Setup stopped')
  $out = & $rootSetup -Approve csdk -Deadlock $root -Generated $rgen -Offline -DownloadsDir $dl 6>&1 | Out-String
  Check 'root setup -Approve: forwards to tools\setup.ps1, then carries on to the data step' ($LASTEXITCODE -eq 0 -and $out -match 'already present' -and $out -match "generated/ already describes build $gb")
  & (Join-Path $tools 'enable-addons.ps1') -GameInfo $gi -Disable *> $null
  Remove-Item $env:DEADLOCK_MODDING_GH; Remove-Item Env:\DEADLOCK_MODDING_GH

  Write-Host "catalog.ps1 models.tsv + get-stock.ps1 textures"
  # A compiled resource (*_c) as bytes for New-TestVpk: header, block table, blocks (sorted, RERL last).
  function New-TestResource([string[]]$Refs, [hashtable]$Blocks = @{}) {
    $types = @($Blocks.Keys | Sort-Object) + 'RERL'; $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter($ms)
    $w.Write([uint32]0); $w.Write([uint16]12); $w.Write([uint16]0); $w.Write([uint32]8); $w.Write([uint32]$types.Count)
    $pos = 16 + 12 * $types.Count
    $bodies = [System.Collections.Generic.List[byte[]]]::new()
    foreach ($t in $types) {
      if ($t -ne 'RERL') { $bodies.Add([byte[]]$Blocks[$t]) } else {
        $r = New-Object IO.MemoryStream; $rw = New-Object IO.BinaryWriter($r); $rw.Write([uint32]8); $rw.Write([uint32]$Refs.Count)
        $str = 8 + 16 * $Refs.Count
        for ($i = 0; $i -lt $Refs.Count; $i++) { $rw.Write([uint64]0); $rw.Write([int64]($str - (8 + 16 * $i + 8))); $str += $Refs[$i].Length + 1 }
        foreach ($s in $Refs) { $rw.Write([Text.Encoding]::ASCII.GetBytes($s)); $rw.Write([byte]0) }
        $bodies.Add($r.ToArray())
      }
    }
    for ($i = 0; $i -lt $types.Count; $i++) { $w.Write([Text.Encoding]::ASCII.GetBytes($types[$i])); $w.Write([uint32]($pos - (16 + 12 * $i + 4))); $w.Write([uint32]$bodies[$i].Length); $pos += $bodies[$i].Length }
    foreach ($b in $bodies) { $w.Write($b) }
    , $ms.ToArray()
  }
  # Texture DATA: version, flags (8 = no LOD), reflectivity, width, height, depth, format (28 = BGRA8888, 20 = BC7).
  function New-TexData([int]$Flags, [int]$W, [int]$H, [int]$Format) { $m = New-Object IO.MemoryStream; $b = New-Object IO.BinaryWriter($m); $b.Write([uint16]1); $b.Write([uint16]$Flags); $b.Write((New-Object byte[] 16)); $b.Write([uint16]$W); $b.Write([uint16]$H); $b.Write([uint16]1); $b.Write([byte]$Format); $b.Write([byte]1); , $m.ToArray() }
  $pakFiles = @{}; foreach ($e in Read-VpkTree (Join-Path $citadel 'pak01_dir.vpk')) { $pakFiles[$e.Path] = [DeadlockModding.Vpk]::Extract($e) }
  $pakFiles['models/hideout/fortune_teller.vmdl_c'] = New-TestResource @('models/hideout/materials/fortune_teller.vmat') @{ ANIM = [byte[]](1, 2); DATA = [byte[]](0) }
  $pakFiles['models/hideout/materials/fortune_teller.vmat_c'] = New-TestResource @('models/hideout/materials/ft_color_tga_1.vtex', 'shaders/x.vfx')
  $pakFiles['models/heroes_staging/archer/archer.vmdl_c'] = New-TestResource @('animgraphs/hero.vnmgraph+archer.vnmgraph', 'models/heroes_staging/archer/archer.vnmskel', 'models/heroes_staging/archer/archer.vmat') @{ DATA = [byte[]](0) }
  $pakFiles['panorama/images/items/icon_psd.vtex_c'] = New-TestResource @() @{ DATA = (New-TexData 8 100 100 28) }
  $pakFiles['materials/x/glow_vmat_g_tcolor_1.vtex_c'] = New-TestResource @() @{ DATA = (New-TexData 0 4 4 20) }
  $pakFiles['materials/x/real.vtex_c'] = New-TestResource @() @{ DATA = (New-TexData 0 4 4 20) }
  New-TestVpk (Join-Path $citadel 'pak01_dir.vpk') $pakFiles
  . (Join-Path $tools 'mesh.ps1')
  $env:FAKE_S2V_XML = $fakeVmat
  $sm = Get-StockMaterial -Model models/hideout/fortune_teller.vmdl_c -Deadlock $root -WorkDir (Join-Path $work 'smat')
  Check 'Get-StockMaterial: finds the material a stock model names (RERL) and decompiles it' ($sm.Path -eq 'models/hideout/materials/fortune_teller.vmat_c' -and (ConvertFrom-Vmat $sm.Text).Params['F_RIM_LIGHT'] -eq '1' -and -not $sm.Others) "$($sm.Path)"
  # convert-model -Like <stock game path>: the material is copied only on request.
  $meshS2v = Join-Path $work 'bin\fake-s2v-mesh.ps1'
  Set-Content $meshS2v @'
$o = $args[[array]::IndexOf($args, '-o') + 1]
if ($o -match '\.vmat$') { New-Item -ItemType Directory -Force -Path (Split-Path $o) | Out-Null; [IO.File]::WriteAllText($o, $env:FAKE_S2V_XML) }
elseif ($o -match '\.gltf$') { Copy-Item $env:FAKE_S2V_GLTF $o }
else { New-Item -ItemType Directory -Force -Path $o | Out-Null; Copy-Item $env:FAKE_S2V_GLTF (Join-Path $o 'model.gltf') }
'@
  $env:S2V_CLI = $meshS2v; $env:FAKE_S2V_GLTF = Join-Path $cm 'tri.gltf'
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'tri.gltf') -Out (Join-Path $cm 'mod/src/models/hideout/a') -Name a -Like models/hideout/fortune_teller.vmdl_c -Deadlock $root *> $null
  $va = Get-Content (Join-Path $cm 'mod/src/models/hideout/a/a_red_paint.vmat') -Raw -ErrorAction SilentlyContinue
  & (Join-Path $tools 'convert-model.ps1') -In (Join-Path $cm 'tri.gltf') -Out (Join-Path $cm 'mod/src/models/hideout/b') -Name b -Like models/hideout/fortune_teller.vmdl_c -CopyStockMaterial -Deadlock $root *> $null
  $vb = Get-Content (Join-Path $cm 'mod/src/models/hideout/b/b_red_paint.vmat') -Raw -ErrorAction SilentlyContinue
  $env:S2V_CLI = $fakeS2v; Remove-Item Env:\FAKE_S2V_GLTF
  Check '-Like <stock model>: fits, but keeps the in-game-checked NPR default material' ($va -match '"F_USE_STATUS_EFFECTS_PROXY"\s+"1"' -and $va -notmatch 'F_RIM_LIGHT') $va
  Check '-Like <stock model> -CopyStockMaterial: copies the stock material it names' ($vb -match '"F_RIM_LIGHT"\s+"1"' -and $vb -notmatch 'F_USE_STATUS_EFFECTS_PROXY') $vb
  Check 'Get-StockMaterial -Material default: none, even for a stock model' ($null -eq (Get-StockMaterial -Model models/hideout/fortune_teller.vmdl_c -Material default -Deadlock $root -WorkDir (Join-Path $work 'smat')))
  $env:FAKE_S2V_XML = $xml6796
  $cat2 = Join-Path $work 'catalog2'
  & (Join-Path $tools 'catalog.ps1') -Deadlock $root -Out $cat2 *> $null
  $mt = @(Import-Csv (Join-Path $cat2 'models.tsv') -Delimiter "`t")
  $ft = $mt | Where-Object path -eq 'models/hideout/fortune_teller.vmdl_c'
  Check 'models: material, its textures, classic animation, plain-words alias' ($ft.materials -eq 'models/hideout/materials/fortune_teller.vmat_c' -and $ft.textures -eq 'models/hideout/materials/ft_color_tga_1.vtex_c' -and $ft.anim -eq 'classic' -and $ft.aliases -match 'oracle' -and $ft.aliases -match 'hideout')
  $ar = $mt | Where-Object path -eq 'models/heroes_staging/archer/archer.vmdl_c'
  Check 'models: AnimGraph 2 hero model with skeleton, named from heroes.tsv' ($ar.anim -eq 'animgraph2' -and $ar.skeleton -eq 'models/heroes_staging/archer/archer.vnmskel_c' -and $ar.aliases -match 'Grey Talon' -and $mt.Count -eq 2)
  $imgS2v = Join-Path $work 'bin\fake-s2v-img.ps1'
  Set-Content $imgS2v @'
$o = $args[[array]::IndexOf($args, '-o') + 1]
New-Item -ItemType Directory -Force -Path (Split-Path $o) | Out-Null
$png = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3)
if ($args[[array]::IndexOf($args, '-f') + 1] -match 'real') {   # a texture compiled from a .vtex: .vtex + image, m_fileName stale
  [IO.File]::WriteAllText($o, '"CDmeVtex" { "m_fileName" "string" "materials/x/real_source.tga" }')
  [IO.File]::WriteAllBytes([IO.Path]::ChangeExtension($o, '.png'), $png)
} else { [IO.File]::WriteAllBytes($o, $png) }                    # compiled straight from an image: S2V writes only the image
'@
  $env:S2V_CLI = $imgS2v
  $tstock = Join-Path $work 'texstock'
  & (Join-Path $tools 'get-stock.ps1') panorama/images/items/icon_psd.vtex_c materials/x/glow_vmat_g_tcolor_1.vtex_c materials/x/real.vtex_c -Out $tstock -Deadlock $root *> $null
  $env:S2V_CLI = $fakeS2v
  $iv = Get-Content (Join-Path $tstock 'panorama/images/items/icon_psd.vtex') -Raw -ErrorAction SilentlyContinue
  Check 'get-stock: image-only texture -> .png + DMX .vtex naming it (stock format, no mips when not power of two)' ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $tstock 'panorama/images/items/icon_psd.png')) -and $iv -match '^<!-- dmx' -and $iv -match '"m_fileName" "string" "panorama/images/items/icon_psd.png"' -and $iv -match '"m_outputFormat" "string" "BGRA8888"' -and $iv -match '"m_bNoLod" "bool" "1"' -and $iv -match '"m_mipAlgorithm" "CDmeImageProcessor"\s*\{\s*"m_algorithm" "string" "None"')
  $gv = Get-Content (Join-Path $tstock 'materials/x/glow_vmat_g_tcolor_1.vtex') -Raw -ErrorAction SilentlyContinue
  Check 'get-stock: material texture -> BC7, Box mips, sRGB' ($gv -match '"m_outputFormat" "string" "BC7"' -and $gv -match '"m_algorithm" "string" "Box"' -and $gv -match '"m_colorSpace" "string" "srgb"' -and [IO.File]::ReadAllBytes((Join-Path $tstock 'materials/x/glow_vmat_g_tcolor_1.png'))[1] -eq 0x50)
  Check 'get-stock: a decompiled .vtex points m_fileName at the image beside it' ((Get-Content (Join-Path $tstock 'materials/x/real.vtex') -Raw) -match '"m_fileName" "string" "materials/x/real.png"')
}
finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item Env:\DEADLOCK_MODDING_REGISTRY, Env:\DEADLOCK_MODDING_HOME, Env:\DEADLOCK_MODDING_CSDK_URL, Env:\FAKE_S2V_TREE, Env:\S2V_CLI, Env:\FAKE_S2V_XML -ErrorAction SilentlyContinue
}

Write-Host ""
if ($script:failures) { Write-Host "$($script:failures) check(s) failed." -ForegroundColor Red } else { Write-Host "All checks passed." -ForegroundColor Green }
exit $script:failures
