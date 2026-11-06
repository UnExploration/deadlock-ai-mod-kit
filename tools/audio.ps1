#Requires -Version 7

<#
.SYNOPSIS
  Turn an audio file in any format, or the audio of a link (YouTube etc.), into the WAV a sound mod
  compiles from: 44.1 kHz, 16-bit stereo, cut to the part you want, about as long and loud as the
  game sound it replaces.

.DESCRIPTION
  Needs FFmpeg; a link also needs yt-dlp. Both are optional kit tools: setup.ps1 -Media lists them
  and installs them after the user's yes. Downloading a clip is the user's request; only use audio
  they may use (sharing a mod with someone else's clip on GameBanana needs the rights to it).

  Steps:
    1. A link is downloaded with yt-dlp (best audio, no playlists) into a temp folder.
    2. -Start/-End cut the clip (seconds, or m:ss / h:mm:ss[.ms]). The result is resampled to 44.1 kHz
       (Valve's own clips are 44.1 kHz), 16-bit, 2 channels.
    3. Length: -Like <stock sound> reads that sound's duration from the catalog (soundevents.tsv);
       -MaxSeconds sets it directly. A longer clip is cut to that length with a short fade-out
       (the game cuts long sounds off anyway). -NoTrim keeps it and only warns.
    4. Loudness: one plain volume change (no compression) to -Loudness LUFS (default -16), or to the
       loudness of -Reference <audio file> (e.g. the stock sound, decompiled), never above -1 dBFS
       peak. -NoNormalize skips it. Clips under about half a second can't be measured; left as they are.
  Writes -Out and prints its length and loudness. Exit code 0 = written.

.EXAMPLE
  pwsh -File audio.ps1 C:\Users\me\Downloads\bonk.mp3 -Out ..\mods\bonk\src\sounds\hit_indicators\damage_send_lethal_01.wav -Like sounds/hit_indicators/damage_send_lethal_01.vsnd_c
  pwsh -File audio.ps1 "https://www.youtube.com/watch?v=..." -Start 1:02.5 -End 1:04 -Out .\kill.wav -Like Damage.Send.Lethal
#>
param(
  [Parameter(Mandatory, Position = 0)] [string]$Source,
  [Parameter(Mandatory)] [string]$Out,
  [string]$Start,
  [string]$End,
  [string]$Like,
  [double]$MaxSeconds,
  [switch]$NoTrim,
  [double]$Loudness = -16,
  [string]$Reference,
  [switch]$NoNormalize,
  [string]$Catalog,
  [string]$Deadlock
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'deadlock-paths.ps1')
$inv = [Globalization.CultureInfo]::InvariantCulture

# "75", "1:15", "0:01:15.5" -> seconds.
function ConvertTo-Seconds([string]$Time) {
  if ($Time -notmatch '^\d+(:\d{1,2}){0,2}(\.\d+)?$') { throw "Can't read the time '$Time'. Use seconds (75.5) or m:ss / h:mm:ss (1:15.5)." }
  $s = 0.0
  foreach ($part in $Time.Split(':')) { $s = $s * 60 + [double]::Parse($part, $inv) }
  $s
}

# Seconds of PCM audio in a WAV file, from its header.
function Get-WavSeconds([string]$Path) {
  $r = New-Object IO.BinaryReader([IO.File]::OpenRead($Path))
  try {
    if ([Text.Encoding]::ASCII.GetString($r.ReadBytes(4)) -ne 'RIFF') { throw "$Path is not a WAV file." }
    [void]$r.ReadUInt32(); [void]$r.ReadBytes(4)
    $byteRate = 0
    while ($r.BaseStream.Position + 8 -le $r.BaseStream.Length) {
      $id = [Text.Encoding]::ASCII.GetString($r.ReadBytes(4)); $size = $r.ReadUInt32()
      if ($id -eq 'fmt ') { $fmt = $r.ReadBytes($size); $byteRate = [BitConverter]::ToUInt32($fmt, 8) }
      elseif ($id -eq 'data') { if (-not $byteRate) { break }; return $size / $byteRate }
      else { [void]$r.BaseStream.Seek($size + ($size % 2), 'Current') }
    }
    throw "$Path has no audio data FFmpeg could read."
  }
  finally { $r.Dispose() }
}

function Invoke-Ffmpeg([string[]]$FfArgs) {
  $o = & $script:ffmpeg -hide_banner -nostdin -y @FfArgs 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "FFmpeg failed (exit $LASTEXITCODE): $($o.Trim())" }
  $o
}

# Integrated loudness (LUFS) and true peak (dBTP) of a file, or $null when it's too short to measure.
function Measure-Loudness([string]$Path) {
  $o = & $script:ffmpeg -hide_banner -nostdin -nostats -i $Path -af 'loudnorm=print_format=json' -f null - 2>&1 | Out-String
  $i = [regex]::Match($o, '"input_i"\s*:\s*"([^"]+)"').Groups[1].Value
  $tp = [regex]::Match($o, '"input_tp"\s*:\s*"([^"]+)"').Groups[1].Value
  $iv = 0.0; $tv = 0.0
  if (-not [double]::TryParse($i, [Globalization.NumberStyles]::Float, $inv, [ref]$iv) -or [double]::IsInfinity($iv) -or $iv -lt -70) { return $null }
  if (-not [double]::TryParse($tp, [Globalization.NumberStyles]::Float, $inv, [ref]$tv)) { $tv = 0 }
  [pscustomobject]@{ I = $iv; TP = $tv }
}

# Duration (s) of a stock sound, by event name or game path, from the catalog's soundevents.tsv.
function Get-StockSeconds([string]$Name) {
  $dir = $Catalog
  if (-not $dir) {
    $base = Join-Path $script:KitHome 'catalog'
    try { $b = Get-DeadlockBuild $(if ($Deadlock) { $Deadlock } else { Find-DeadlockRoot }); if ($b) { $dir = Join-Path $base $b } } catch { }
    if (-not $dir -or -not (Test-Path $dir)) { $dir = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Where-Object Name -match '^\d+$' | Sort-Object { [int]$_.Name } | Select-Object -Last 1 -ExpandProperty FullName }
  }
  $tsv = $(if ($dir) { Join-Path $dir 'soundevents.tsv' })
  if (-not $tsv -or -not (Test-Path $tsv)) { throw "No catalog to read the length of '$Name' from. Run pwsh -File catalog.ps1 first, or pass -MaxSeconds." }
  $rows = @(Import-Csv $tsv -Delimiter "`t")
  if ($Name -match '[/\\]') {
    $p = ($Name.Replace('\', '/').ToLowerInvariant() -replace '\.(vsnd_c|vsnd|wav|mp3)$', '') + '.vsnd_c'
    $hits = @($rows | Where-Object { ($_.vsnd_files -split ',') -contains $p })
  }
  else { $hits = @($rows | Where-Object event -eq $Name) }
  if (-not $hits) { throw "'$Name' is not in $tsv. Search it by event name or sound path." }
  $d = @($hits | Where-Object { $_.duration } | ForEach-Object { [double]::Parse($_.duration, $inv) } | Sort-Object)
  if (-not $d) { Write-Warning "The catalog has no duration for '$Name' (events: $(($hits.event | Select-Object -First 3) -join ', ')); the length is not capped."; return $null }
  $d[-1]
}

$script:ffmpeg = Find-Ffmpeg
if (-not $script:ffmpeg) { throw "FFmpeg is not installed. It's optional: pwsh -File setup.ps1 -Media lists it; install after the user's yes." }
if ($Out -notmatch '\.wav$') { throw "-Out must end in .wav (the compiler takes .wav; the game path keeps the stock name, e.g. ...\damage_send_lethal_01.wav)." }
$cap = $(if ($MaxSeconds) { $MaxSeconds } elseif ($Like) { Get-StockSeconds $Like } else { $null })
$startS = $(if ($Start) { ConvertTo-Seconds $Start } else { 0 })
if ($End -and (ConvertTo-Seconds $End) -le $startS) { throw "-End ($End) must be after -Start ($Start)." }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('dl_audio_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  if ($Source -match '^https?://') {
    $ytdlp = Find-YtDlp
    if (-not $ytdlp) { throw "yt-dlp is not installed, so links can't be downloaded. It's optional: pwsh -File setup.ps1 -Media lists it; or ask the user for the audio file." }
    Write-Host "Downloading the audio of $Source ..."
    $o = & $ytdlp --no-playlist --no-progress -f 'bestaudio/best' -o (Join-Path $tmp 'download.%(ext)s') $Source 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "yt-dlp couldn't download $Source (exit $LASTEXITCODE): $($o.Trim())" }
    $in = Get-ChildItem $tmp -Filter 'download.*' -File | Where-Object Extension -ne '.part' | Select-Object -First 1 -ExpandProperty FullName
    if (-not $in) { throw "yt-dlp finished but saved no audio file: $($o.Trim())" }
  }
  else {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "No such file: $Source" }
    $in = (Resolve-Path -LiteralPath $Source).Path
  }

  # 1. Cut and resample.
  $cut = Join-Path $tmp 'cut.wav'
  $ffArgs = @('-i', $in, '-vn')
  if ($Start) { $ffArgs += '-ss', $Start }
  if ($End) { $ffArgs += '-to', $End }
  Invoke-Ffmpeg ($ffArgs + @('-ar', '44100', '-ac', '2', '-c:a', 'pcm_s16le', $cut)) | Out-Null
  $seconds = Get-WavSeconds $cut
  if ($seconds -le 0) { throw "The clip is empty. Check -Start/-End against the source's length." }

  # 2. Length.
  $work = $cut
  if ($cap -and $seconds -gt $cap + 0.05) {
    if ($NoTrim) { Write-Warning ("The clip is {0:0.00} s; the sound it replaces is {1:0.00} s. The game may cut it off." -f $seconds, $cap) }
    else {
      $fade = [Math]::Min(0.05, $cap / 4)
      $work = Join-Path $tmp 'trim.wav'
      $af = 'atrim=0:{0},afade=t=out:st={1}:d={2}' -f $cap.ToString($inv), ($cap - $fade).ToString($inv), $fade.ToString($inv)
      Invoke-Ffmpeg @('-i', $cut, '-af', $af, '-ar', '44100', '-ac', '2', '-c:a', 'pcm_s16le', $work) | Out-Null
      Write-Host ("Cut from {0:0.00} s to {1:0.00} s (the length of the sound it replaces), with a short fade-out." -f $seconds, $cap)
      $seconds = Get-WavSeconds $work
    }
  }

  # 3. Loudness.
  $level = $null
  New-Item -ItemType Directory -Force -Path (Split-Path ([IO.Path]::GetFullPath($Out))) | Out-Null
  if (-not $NoNormalize) {
    $target = $Loudness
    if ($Reference) {
      $ref = Measure-Loudness (Resolve-Path -LiteralPath $Reference).Path
      if ($ref) { $target = $ref.I; Write-Host ("Matching the loudness of {0}: {1:0.0} LUFS" -f (Split-Path $Reference -Leaf), $target) }
      else { Write-Warning "$Reference is too short to measure; using $Loudness LUFS." }
    }
    $m = Measure-Loudness $work
    if ($m) {
      $gain = [Math]::Min($target - $m.I, -1 - $m.TP)
      Invoke-Ffmpeg @('-i', $work, '-af', ('volume={0}dB' -f [Math]::Round($gain, 2).ToString($inv)), '-ar', '44100', '-ac', '2', '-c:a', 'pcm_s16le', $Out) | Out-Null
      $level = '{0:0.0} LUFS ({1:+0.0;-0.0} dB)' -f ($m.I + $gain), $gain
    }
    else { Write-Warning "The clip is too short to measure its loudness; left as it is." }
  }
  if (-not $level) { Copy-Item -LiteralPath $work $Out -Force }
  $msg = "Wrote $Out ({0:0.00} s, 44.1 kHz, 16-bit stereo{1})" -f (Get-WavSeconds $Out), $(if ($level) { ", $level" } else { '' })
  Write-Host $msg -ForegroundColor Green
}
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
