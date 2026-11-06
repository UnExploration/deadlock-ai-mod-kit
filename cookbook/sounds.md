# Guide: sounds

**The user says (covers):** "change my kill sound", "make kills play X", "change the hit / headshot sound", "make <hero>'s ult play this", "change the <item> sound to my clip", "replace this voice line", "change the menu music", "use the sound from this video", "use this clip / file".
**Kind:** sound mod. Route A (another game sound) needs no compiler. Route B (the user's own audio) needs Reduced CSDK 12 to compile the clip.

What worked in-game: the kill sound via a game-sound copy (route A), and the user's own audio on an ability sound (route B), from a WAV file and from a YouTube link (`audio.ps1 <url> -Like <event>`). Not tried in-game, so have the user check it: route B on the kill sound, MP3 sources (they compile at the desk), looping clips.

**Names are examples.** Every event name, file path and table row below is an example. Patches rename and move sounds: look each one up in the catalog (`catalog.ps1`, or the `catalog_search` MCP tool) for the user's current build before using it.

The clip replaces the stock **file**, not the event. `build.ps1` compiles `<stock path>.wav` into `<stock path>.vsnd_c`, and the game plays it wherever it played the original.

## 1. Find the event and all its files

Search the catalog (`catalog.ps1` prints the folder):
- `soundevents.tsv`: find the event, then read its `vsnd_files` column. **Replace every file listed.** The game picks among them at random, so any file you miss still plays sometimes.
- `sounds.tsv`: from a file, see which events play it. A file shared by several events changes all of them.
- `heroes.tsv`: a hero's name gives its `sound_script` (abilities, weapon) and `vo_script` (voice lines). Search `soundevents.tsv` for events from that file.

| Request | Where to look (patterns; confirm in the catalog) |
|---|---|
| Kill, hit, headshot | `Damage.Send*` events; files under `sounds/hit_indicators/` (table in [Worked examples](#worked-examples)) |
| Hero ability | events in the hero's `sound_script` (`soundevents/hero/<codename>.vsndevts`); files mostly under `sounds/abilities/`, also `sounds/player/` and `sounds/weapons/` |
| Item proc or active | events `Mods.*` and `Item.*` in `soundevents/mods/*.vsndevts`; files under `sounds/mods/` |
| Voice line | events in the hero's `vo_script`; files under `sounds/vo/<codename>/` |
| Music | events `Music.*`; files under `sounds/music/`. Main menu, for example: `Music.MainMenu` → `sounds/music/music_menu_lp.vsnd_c` |

Then read each stock file's format straight from the game, without extracting it (`setup.ps1` installs Source2Viewer-CLI to `%LOCALAPPDATA%\deadlock-modding\bin\`):

```powershell
Source2Viewer-CLI -i "<Deadlock>\game\citadel\pak01_dir.vpk" -f <stock path> -b CTRL
```

| Field | Means | Typical stock clips |
|---|---|---|
| `m_flDuration` | length in seconds | your clip's upper limit |
| `m_nRate`, `m_nChannels` | sample rate, channels | 44100, 2 (stereo) |
| `m_nLoopStart` | `-1` = plays once; `0` or more = loops from that sample frame | `*_lp` files and most music loop. The menu music loops from 57 s of 247 s |

To hear it, `get-stock.ps1 <path> -Raw -Out <tmp>`, then `Source2Viewer-CLI -i <tmp>\<path> -d` writes the audio next to it. That audio also gives the stock **peak** (its loudest sample), the level yours should stay at or under (§ 4.2).

*Done when* every file you'll replace is named by game path, with its length, channels, rate, peak and whether it loops. Your clip matches or undercuts each of them.

## 2. Ask where the sound comes from

Unless the user already gave a file or link, ask once, in one message:
- **Their own file or a link** (a video, a sound site): route B.
- **"Find one for me":** search for a free clip of exactly what they named (sound sites such as Pixabay or Freesound, which may need the user's login). List it for their yes: what it is, the page, its licence. Then route B.
- **A sound already in the game,** only if you found one that fits (say which, and that you can't hear it): route A, no compiler.

Don't pick for them: "a cash register cha-ching" means a classic cha-ching, not the nearest game sound.

## 3. Route A: use another game sound (no compiler)

**The shape:** the whole mod is a `copies` map in `mod.json`. Nothing goes in `src/`, and nothing is compiled.

```
mods/<name>/
  mod.json    "copies": { "<target path>_01.vsnd_c": "<donor path>.vsnd_c",
                          "<target path>_02.vsnd_c": "<donor path>.vsnd_c", … }
              # one entry per file the event can pick (§ 1), all pointing at the same donor
  src/        # empty: build.ps1 copies each donor out of the installed game into the target paths
```

- **Why it works:** a compiled `.vsnd_c` plays from any path, even when its embedded source name doesn't match. A donor from another folder works too (a `sounds/ui/` clip over the kill sound under `sounds/hit_indicators/` played on every hero kill in-game). The mod folder holds no game files, so there's nothing of Valve's to share.
- **Map every variant.** An event picks one of its numbered files at random each time (the kill sound picks one of six). A file you leave out keeps playing the old sound some of the time.
- **Files are shared between events.** Replacing a file changes every event that plays it: search `soundevents.tsv` for the target file's name and tell the user what else will change (the kill sound's files are also played by the last-hit events, so the new sound plays on last hits too).
- **Finding the donor the user named.** "The shop purchase sound" is a *what*: search `soundevents.tsv` for words from the name (event names like `UI.Shop.*`) and `sounds.tsv` for file names, then let the user audition the candidates (step 2 below) rather than picking by name alone; event names and file names don't always agree.
- **Length and loudness still apply.** A donor longer than the stock clip gets cut off, and a louder one is unfair (Pitfalls). Compare the `duration` column of both events in `soundevents.tsv` and say so when the donor is longer or louder; the user may accept it or pick another donor.

1. `new-mod.ps1 -Name <name> -Kind empty`
2. In `mods/<name>/mod.json`, add `copies` as above. Both sides are game paths of compiled `*_c` files from the catalog. To let the user audition donors first, `get-stock.ps1 <donor> -Raw -Out <tmp>` writes the compiled file, and Source2Viewer decompiles it to audio.
3. `build.ps1 -Mod mods\<name> -Install`, with Deadlock closed.

## 4. Route B: your own audio

Needs Reduced CSDK 12.

### 4.1 Get the clip

The source is the answer from [step 2](#2-ask-where-the-sound-comes-from); don't ask again. If it was "find one for me", search for a free clip of what they named and list it for their yes with its page and licence.

- **A file from the user:** ask for a WAV or MP3 (44.1 or 48 kHz). WAV is safer: it compiles without loss, and you can read and edit it in plain PowerShell.
- **A link:** run `doctor.ps1`; it reports `yt-dlp` and `ffmpeg` as optional tools (INFO when missing). If they're missing, `setup.ps1 -Media` lists them for the user's yes, then `setup.ps1 -Media -Approve ytdlp,ffmpeg`. Then `audio.ps1 <url> -Out <stock path>.wav -Like <event> [-Start m:ss -End m:ss]` fetches, cuts and converts it in one step. If the user says no, ask them to save the clip as a file.
- **Rights:** a clip from a video or song belongs to someone else. That's fine in the user's own game. If they later want to publish it, say that needs the owner's permission, and that GameBanana bans AI-generated voice and music ([docs/09 § Fair play](../docs/09-asset-mods.md#fair-play-and-publishing)).

Keep it about as short and as loud as the original: the original's length is the `duration` column in `soundevents.tsv`, and longer audio gets cut off.

### 4.2 Make the WAV

Target: **16-bit PCM WAV, 44.1 kHz, stereo, no longer than the stock clip, no louder than it.** Trim to the part the user wants; a short fade-out avoids a click at the end.

- **With the media tools:** `audio.ps1 <file or url> -Out <stock path>.wav -Like <event or sounds/... path>` converts to 44.1 kHz 16-bit stereo, cuts to the stock length from the catalog (50 ms fade-out; `-NoTrim` keeps the length), and sets the loudness to -16 LUFS (`-Reference <file>` matches another clip instead). `-Start`/`-End` pick the part of the clip.
- **Without them:** a WAV that is already 16-bit PCM at 44.1 or 48 kHz can be used as-is, and PowerShell can read its header (rate at byte 24, channels at 22) and scale or cut its samples. An MP3 can go in as-is too (`build.ps1` compiles `.mp3`); check its length after the build (step 4.3). Anything else (M4A, OGG, a long file to cut): ask the user to export a WAV from an editor such as Audacity, or offer the media tools.
- **Loudness without a meter:** scale the peak to about -6 dBFS, which sits under stock clips (the stock Healing Rite cast sound peaks at 0 dBFS and averages about -16 dB). The user confirms by ear in step 5.
- **A made-up tone or a quick test clip** (only when the user chose that in step 2, or to test the route before their clip arrives): `audio.ps1` converts a clip but doesn't make one, so write it in plain PowerShell. This writes a 1.4 s two-note chime, 44.1 kHz 16-bit stereo, peaking at about -6 dBFS (the length, format and level of a synthesised chime that played in-game):
  ```powershell
  $out = 'C:\full\path\to\mods\<name>\src\<stock path>.wav'          # full path: .NET ignores PowerShell's current folder
  $rate = 44100; $n = [int]($rate * 1.4); $peak = [Math]::Pow(10, -6 / 20)
  $w = New-Object IO.BinaryWriter ([IO.File]::Create($out)); $a = [Text.Encoding]::ASCII
  $w.Write($a.GetBytes('RIFF')); $w.Write([int](36 + $n * 4)); $w.Write($a.GetBytes('WAVEfmt '))
  $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]2); $w.Write([int]$rate); $w.Write([int]($rate * 4)); $w.Write([int16]4); $w.Write([int16]16)
  $w.Write($a.GetBytes('data')); $w.Write([int]($n * 4))
  for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $rate; $v = 0.0
    foreach ($note in @(@(0, 659.25), @(0.18, 987.77))) {            # start (s), pitch (Hz): E5 then B5
      $u = $t - $note[0]; if ($u -ge 0) { $v += 0.7 * [Math]::Sin(2 * [Math]::PI * $note[1] * $u) * [Math]::Exp(-4 * $u) * [Math]::Min(1, $u / 0.005) }
    }
    $s = [int16]($v * $peak * 32767 * [Math]::Min(1, ($n - $i) / 2205))   # 50 ms fade-out at the end
    $w.Write($s); $w.Write($s)                                        # left, right
  }
  $w.Close()
  ```

### 4.3 Place and build

**The shape:** your clip sits in `src/` at the stock file's path, with `.wav` (or `.mp3`) in place of `.vsnd_c`. No `copies`, no `overrides`.

```
mods/<name>/
  mod.json
  src/<stock path>.wav    # e.g. src/sounds/mods/armor/healing_rite/healingrite_cast.wav (example path)
                          # build.ps1 compiles it with Reduced CSDK 12 to <stock path>.vsnd_c
```

- **Why it works:** the game loads files by path, so a `.vsnd_c` at the stock path plays wherever the original did, from every event that names that file.
- **Several variants:** the same clip once per file from step 1 (six for the kill sound, `_01` to `_06`).

1. `new-mod.ps1 -Name <name> -Kind empty`
2. Put the clip in `src` as above, once per file from step 1.
3. `build.ps1 -Mod mods\<name>`. Its contents list must show each stock path ending in `.vsnd_c` and nothing else (six `.vsnd_c` for the kill sound, one for a single-file event).
4. Check each compiled clip: `Source2Viewer-CLI -i mods\<name>\dist\pak<NN>_dir.vpk -f <path> -b CTRL`. `m_flDuration` must be no longer than the stock clip's, `m_nRate` 44100 or 48000, and `m_nLoopStart` must match the stock's: `-1` for `-1`, `0` or more for a loop. A WAV compiles as `PCM16` with its samples unchanged (decompile it with `-d`: the samples equal the WAV's); an MP3 stays `MP3` (checked at the desk). *Done when* every replaced file passes.
5. `build.ps1 -Mod mods\<name> -Install`, with Deadlock closed.

## 5. Check in-game

- **The user checks:** "Start the sandbox or a bot match and trigger it (use the item / cast the ability / hear the line / kill a hero). Do you hear the new sound, every time? Trigger it a few more times. Is it about as loud as the sounds around it?"
- Old sound sometimes (some kills still play the old sound): a variant was missed.
- Old sound always, or silence, or no change at all: work through [docs/05 § Reading failures](../docs/05-dev-loop.md#reading-failures).
- Cut off early: the clip is longer than the stock one, or the event stops it. Trim it.

## Pitfalls

- **Longer than stock gets cut off.** Match the stock length; shorter is fine.
- **Louder than stock is unfair.** GameBanana's R-DL.824 bans louder or extended sounds on quiet abilities ([docs/09 § Fair play](../docs/09-asset-mods.md#fair-play-and-publishing)). Keep the level at or under the stock clip. Sounds much louder than the original count as unfair.
- **Loops need loop points.** A stock file with `m_nLoopStart` 0 or more loops; a plain WAV plays once and stops. Give the WAV a `smpl` chunk with one loop (start = the sample frame to restart from, 0 for the whole clip; end = the last frame): the compiler turns it into `m_nLoopStart`/`m_nLoopEnd` (checked at the desk; looping is not tried in-game, so have the user check it). Writing that chunk is about 15 lines of PowerShell.
- **Compiled clips carry no envelope curve.** Stock clips have `m_pEnvelopeAnalyzer` data; ours compile with `null`. What the game uses it for, if anything, is untested.
- **When a `.vsndevts` override is needed instead.** Replacing files can't change an event's volume or pitch, play the clip for only one of several events that share a file, or point an event at a new file name. Those need an override of the whole `soundevents/…vsndevts_c` file ([docs/09 § What to replace](../docs/09-asset-mods.md#what-to-replace)): it conflicts with every other mod shipping that file, and goes stale (new events go silent) after patches. Prefer file replacement; for volume alone, vpkmerge's `soundevents --set` is the lighter route (docs/09 § Routes, 3).
- Patches rename and move sounds often ([docs/09 § After a patch](../docs/09-asset-mods.md#after-a-patch)). After an update, run `catalog_refresh` (`generate-docs.ps1`) and re-check the event's files and paths.
- Another mod replacing the same files: the lower pak number wins (`mods.ps1 conflicts`).

## Worked examples

### Kill sound

Route A, worked in-game: a `copies` map sending all six lethal variants to one shop sound from `sounds/ui/` played on every hero kill. The table is an example; re-check it against the catalog for the user's build.

| Sound | Event (example) | Files |
|---|---|---|
| Hero kill | `Damage.Send.Lethal` | `sounds/hit_indicators/damage_send_lethal_01..06.vsnd_c` |
| Hit marker | `Damage.Send` | `sounds/hit_indicators/damage_send_default_01..06.vsnd_c` |
| Headshot / crit | `Damage.Send.Crit` | `sounds/hit_indicators/damage_send_crit_01..06.vsnd_c` |

- Replace all six lethal variants (`damage_send_lethal_01` to `_06`). Route A: one `copies` entry per variant (step 3). Route B: the same clip once per variant, six `.vsnd_c` built (step 4.3); the kill sound is just six target files instead of one. Route B for the kill sound compiles but isn't tried in-game.
- Check: "In a bot match or the sandbox, kill a hero. Do you hear the new sound? Kill a few more: is it the new sound every time?" Some kills still play the old sound: a variant was missed. Trooper and denizen kills may fire a different sound event; that isn't tried in-game, so if the user cares about those, have them check one.

### Ability sound

Route B, a WAV from a file, worked in-game: using the Healing Rite item played the new clip, at about the volume of other item sounds.

- Target: the Healing Rite cast sound. Its event (`Mods.Armor.Healing.Rite.Cast` in this example) has one file, so the mod is one WAV, `src/sounds/mods/armor/healing_rite/healingrite_cast.wav` (look up the event and its files for the user's item or ability).
- Stock vs new, read with Source2Viewer-CLI as in § 1: the stock clip is a 3.38 s stereo MP3 at 44.1 kHz, plays once (`m_nLoopStart = -1`), peaks at 0 dBFS and averages about -16 dB. The new one was 1.4 s, 44.1 kHz 16-bit stereo, no loop, peak -6 dBFS: shorter and quieter, so nothing was cut off or louder than stock.
- Desk check before the test: the VPK held the one `.vsnd_c`; `-b CTRL` read back `PCM16`, 44100 Hz, 2 channels, 1.4 s, no loop; decompiled, its samples equalled the WAV's.
- A clip from a YouTube link through `audio.ps1 <url> -Like <event>` also played in-game.
