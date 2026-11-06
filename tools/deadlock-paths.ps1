# Shared helpers for the build scripts (dot-source this file).

# Deadlock install root (the folder that contains game\), found through Steam's library list.
function Find-DeadlockRoot {
  $steamRoots = @(
    (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath,
    "${env:ProgramFiles(x86)}\Steam",
    "$env:ProgramFiles\Steam"
  ) | Where-Object { $_ } | ForEach-Object { $_ -replace '/', '\' } | Select-Object -Unique
  foreach ($steam in $steamRoots) {
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    $libraries = @($steam)
    if (Test-Path $vdf) {
      $libraries += [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }
    }
    foreach ($lib in ($libraries | Select-Object -Unique)) {
      $root = Join-Path $lib 'steamapps\common\Deadlock'
      if (Test-Path (Join-Path $root 'game\citadel\gameinfo.gi')) { return $root }
    }
  }
  throw "Deadlock install not found. Pass -Deadlock '<...>\steamapps\common\Deadlock'."
}

# Throws if Deadlock is running from $Root (any Deadlock, when $Root is not given): it locks its files.
function Assert-DeadlockClosed([string]$Root) {
  $running = @(Get-Process -Name deadlock -ErrorAction SilentlyContinue)
  if ($Root) {
    $full = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $running = @($running | Where-Object { -not $_.Path -or $_.Path.StartsWith($full, [StringComparison]::OrdinalIgnoreCase) })
  }
  if ($running) { throw "Deadlock is running. Close it fully first (it locks its files)." }
}

# Build number of the installed game (game\citadel\steam.inf ClientVersion).
function Get-DeadlockBuild([string]$Root) {
  $inf = Join-Path $Root 'game\citadel\steam.inf'
  if (-not (Test-Path $inf)) { return $null }
  $m = [regex]::Match((Get-Content $inf -Raw), '(?m)^ClientVersion=(\d+)')
  if ($m.Success) { [int]$m.Groups[1].Value } else { $null }
}

# A gameinfo.gi SearchPaths block without the lines enable-addons.ps1 adds: the addons line, the Mod/Write
# citadel pair right after it, and the Mod/Write core pair right before Game core. Anything else is left alone.
# enable-addons.ps1 -Disable writes this back; generate-docs.ps1 prints it as Valve's stock block.
function Remove-AddonsMount([string]$Block) {
  $l = '[ \t]*{0}[ \t]+{1}[ \t]*\r?\n'
  $out = $Block -replace ('(?m)^' + ($l -f 'Game', 'citadel/addons') + '(' + ($l -f 'Mod', 'citadel') + ($l -f 'Write', 'citadel') + ')?'), ''
  $out -replace ('(?m)^' + ($l -f 'Mod', 'core') + ($l -f 'Write', 'core') + '(?=[ \t]*Game[ \t]+core[ \t]*\r?$)'), ''
}

# Build that the kit's generated/ folder was rendered from: the header line every generated file starts with
# ("... from Deadlock build N on DATE ..."), read from build.md, else any other .md in the folder (README.md
# is authored, not generated). $null when the folder is missing or holds no generated file.
function Get-GeneratedBuild([string]$Folder) {
  if (-not $Folder -or -not (Test-Path $Folder)) { return $null }
  $files = @(Join-Path $Folder 'build.md') + @(Get-ChildItem $Folder -Filter '*.md' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'README.md' -and $_.Name -ne 'build.md' } | Sort-Object Name | ForEach-Object { $_.FullName })
  foreach ($f in $files) {
    if (-not (Test-Path $f)) { continue }
    $m = [regex]::Match(((Get-Content $f -TotalCount 1) -join ''), 'from Deadlock build (\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
  }
  $null
}

# Everything the kit installs or records lives here; deleting it removes the kit's tools (not mods in the game).
$script:KitHome = $(if ($env:DEADLOCK_MODDING_HOME) { $env:DEADLOCK_MODDING_HOME } else { Join-Path $env:LOCALAPPDATA 'deadlock-modding' })

# Which mod installed which pak: <KitHome>\paks.json ({ "pak64_dir.vpk": "mymod" }).
$script:PakRegistryPath = $(if ($env:DEADLOCK_MODDING_REGISTRY) { $env:DEADLOCK_MODDING_REGISTRY } else { Join-Path $script:KitHome 'paks.json' })

# Reduced CSDK 12 folder: -Csdk, $env:DEADLOCK_CSDK, <KitHome>\Reduced_CSDK_12, then the community path C:\Reduced_CSDK_12.
# Returns the first that has resourcecompiler.exe, else the first candidate (so errors name a real path).
function Find-Csdk([string]$Csdk) {
  if ($Csdk) { return $Csdk }
  $candidates = @($env:DEADLOCK_CSDK, (Join-Path $script:KitHome 'Reduced_CSDK_12'), 'C:\Reduced_CSDK_12') | Where-Object { $_ }
  $found = $candidates | Where-Object { Test-Path (Join-Path $_ 'game\bin_cs2\win64\resourcecompiler.exe') } | Select-Object -First 1
  if ($found) { $found } else { $candidates[0] }
}
function Get-PakRegistry {
  $registry = @{}
  if (Test-Path $script:PakRegistryPath) {
    (Get-Content $script:PakRegistryPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $registry[$_.Name] = $_.Value }
  }
  $registry
}
function Save-PakRegistry([hashtable]$Registry) {
  New-Item -ItemType Directory -Force -Path (Split-Path $script:PakRegistryPath) | Out-Null
  $Registry | ConvertTo-Json | Set-Content -Path $script:PakRegistryPath -Encoding utf8
}

# Source2Viewer-CLI.exe: $env:S2V_CLI, <KitHome>\bin, tools\bin next to these scripts, or PATH. $null if absent.
function Find-Source2ViewerCli {
  $candidates = @($env:S2V_CLI, (Join-Path $script:KitHome 'bin\Source2Viewer-CLI.exe'), (Join-Path $PSScriptRoot 'bin\Source2Viewer-CLI.exe'))
  $onPath = Get-Command 'Source2Viewer-CLI' -ErrorAction SilentlyContinue
  if ($onPath) { $candidates += $onPath.Source }
  $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

# GitHub CLI (store.ps1). $env:DEADLOCK_MODDING_GH overrides it (tests use a fake).
function Find-Gh {
  if ($env:DEADLOCK_MODDING_GH) { if (Test-Path $env:DEADLOCK_MODDING_GH) { return $env:DEADLOCK_MODDING_GH } else { return $null } }
  $c = Get-Command gh -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $p = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'
  if (Test-Path $p) { return $p }
  $null
}

# Optional media tools (audio.ps1): yt-dlp downloads audio from a link, ffmpeg converts it.
# $env:DEADLOCK_MODDING_YTDLP / _FFMPEG override them (tests use fakes); then <KitHome>\bin, then PATH. $null if absent.
function Find-KitExe([string]$Override, [string]$Exe) {
  if ($Override) { if (Test-Path $Override) { return $Override } else { return $null } }
  $p = Join-Path $script:KitHome "bin\$Exe.exe"
  if (Test-Path $p) { return $p }
  $c = Get-Command $Exe -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $null
}
function Find-YtDlp { Find-KitExe $env:DEADLOCK_MODDING_YTDLP 'yt-dlp' }
function Find-Ffmpeg { Find-KitExe $env:DEADLOCK_MODDING_FFMPEG 'ffmpeg' }

# Optional model converter (convert-model.ps1): Blender, run headless. $env:DEADLOCK_MODDING_BLENDER overrides it
# (tests use a fake); then <KitHome>\blender (setup.ps1 -Models), an installed Blender 4.x (4.5 is the last with a
# .dae importer, so the newest 4.x wins over 5.x), then PATH. $null if absent.
function Find-Blender {
  if ($env:DEADLOCK_MODDING_BLENDER) { if (Test-Path $env:DEADLOCK_MODDING_BLENDER) { return $env:DEADLOCK_MODDING_BLENDER } else { return $null } }
  $p = Join-Path $script:KitHome 'blender\blender.exe'
  if (Test-Path $p) { return $p }
  $installed = @(Get-ChildItem (Join-Path $env:ProgramFiles 'Blender Foundation') -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'blender.exe') } |
    Sort-Object @{ Expression = { $_.Name -match 'Blender 4\.' }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $true })
  if ($installed.Count -gt 0) { return (Join-Path $installed[0].FullName 'blender.exe') }
  $c = Get-Command blender -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $null
}

# GameTracking-Deadlock: Valve's files, decompiled, per build (raw GitHub URLs under game/citadel).
$script:GameTrackingBase = 'https://raw.githubusercontent.com/SteamTracking/GameTracking-Deadlock/master/game/citadel'

# Pak numbers popular community mods use (late 2026); avoid them for your own mods.
$script:PopularPaks = @(1, 2, 3, 4, 5, 6, 7, 9, 22, 57, 70, 71, 80, 98)

# Fast VPK (v1/v2) directory reader and raw file extractor, compiled once per session.
if (-not ('DeadlockModding.Vpk' -as [type])) {
  Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.IO; using System.Text;
namespace DeadlockModding {
  public class VpkEntry { public string Path; public string VpkPath; public long DataStart; public uint Crc; public ushort Archive; public uint Offset; public uint Length; public byte[] Preload;
    public long Bytes { get { return Length + Preload.Length; } } public bool InDirFile { get { return Archive == 0x7FFF; } } }
  public static class Vpk {
    public static List<VpkEntry> Read(string dirPath, string filter, out long dataStart) {
      var list = new List<VpkEntry>();
      using (var r = new BinaryReader(File.OpenRead(dirPath))) {
        if (r.ReadUInt32() != 0x55AA1234) throw new InvalidDataException("Not a VPK: " + dirPath);
        uint version = r.ReadUInt32(); uint treeSize = r.ReadUInt32();
        int header = version == 2 ? 28 : 12; if (version == 2) r.ReadBytes(16);
        byte[] tree = r.ReadBytes((int)treeSize); dataStart = header + treeSize;
        int p = 0;
        Func<string> cstr = () => { int s = p; while (tree[p] != 0) p++; string v = Encoding.UTF8.GetString(tree, s, p - s); p++; return v; };
        string ext;
        while ((ext = cstr()) != "") { string dir;
          while ((dir = cstr()) != "") { string name;
            while ((name = cstr()) != "") {
              var e = new VpkEntry(); e.Crc = BitConverter.ToUInt32(tree, p); ushort pre = BitConverter.ToUInt16(tree, p + 4);
              e.Archive = BitConverter.ToUInt16(tree, p + 6); e.Offset = BitConverter.ToUInt32(tree, p + 8); e.Length = BitConverter.ToUInt32(tree, p + 12);
              e.VpkPath = dirPath; p += 18; e.Preload = new byte[pre]; Array.Copy(tree, p, e.Preload, 0, pre); p += pre;
              e.Path = (dir.Trim() == "" ? "" : dir + "/") + name + (ext.Trim() == "" ? "" : "." + ext);
              if (filter == null || e.Path.StartsWith(filter, StringComparison.OrdinalIgnoreCase)) list.Add(e);
            } } }
      }
      foreach (var e in list) e.DataStart = dataStart;
      return list;
    }
    public static byte[] Extract(VpkEntry e) { string dirPath = e.VpkPath; long dataStart = e.DataStart;
      var data = new byte[e.Bytes]; Array.Copy(e.Preload, data, e.Preload.Length);
      if (e.Length == 0) return data;
      string file = e.InDirFile ? dirPath : dirPath.Substring(0, dirPath.Length - "dir.vpk".Length) + e.Archive.ToString("000") + ".vpk";
      using (var f = File.OpenRead(file)) { f.Seek((e.InDirFile ? dataStart : 0) + e.Offset, SeekOrigin.Begin);
        int read = 0; while (read < e.Length) { int n = f.Read(data, e.Preload.Length + read, (int)e.Length - read); if (n <= 0) throw new EndOfStreamException(file); read += n; } }
      return data;
    }
    // Writes a single-file VPK v2 exactly like the community packers (CSDKCfgVPK): all data in the
    // _dir file, CRC32 per entry, no preload, no archive MD5s, 48-byte "other MD5" section
    // (tree, archive-MD5 section, whole file), no signature. paths[i] is the in-VPK path of files[i].
    public static void Write(string outPath, string[] paths, string[] files) {
      var groups = new SortedDictionary<string, SortedDictionary<string, List<int>>>(StringComparer.Ordinal);
      for (int i = 0; i < paths.Length; i++) {
        string p = paths[i]; int slash = p.LastIndexOf('/'); string dir = slash < 0 ? " " : p.Substring(0, slash);
        string leaf = p.Substring(slash + 1); int dot = leaf.LastIndexOf('.'); string ext = dot < 0 ? " " : leaf.Substring(dot + 1);
        if (!groups.ContainsKey(ext)) groups[ext] = new SortedDictionary<string, List<int>>(StringComparer.Ordinal);
        if (!groups[ext].ContainsKey(dir)) groups[ext][dir] = new List<int>();
        groups[ext][dir].Add(i);
      }
      var tree = new MemoryStream(); var tw = new BinaryWriter(tree); var data = new MemoryStream();
      Action<string> z = s => { tw.Write(Encoding.UTF8.GetBytes(s)); tw.Write((byte)0); };
      foreach (var eg in groups) { z(eg.Key);
        foreach (var dg in eg.Value) { z(dg.Key);
          foreach (int i in dg.Value) {
            string leaf = paths[i].Substring(paths[i].LastIndexOf('/') + 1); int dot = leaf.LastIndexOf('.');
            byte[] bytes = File.ReadAllBytes(files[i]);
            z(dot < 0 ? leaf : leaf.Substring(0, dot));
            tw.Write(Crc32(bytes)); tw.Write((ushort)0); tw.Write((ushort)0x7FFF);
            tw.Write((uint)data.Length); tw.Write((uint)bytes.Length); tw.Write((ushort)0xFFFF);
            data.Write(bytes, 0, bytes.Length);
          } z(""); } z(""); }
      z("");
      byte[] t = tree.ToArray(), d = data.ToArray();
      var o = new MemoryStream(); var w = new BinaryWriter(o);
      w.Write(0x55AA1234u); w.Write(2u); w.Write((uint)t.Length); w.Write((uint)d.Length); w.Write(0u); w.Write(48u); w.Write(0u);
      w.Write(t); w.Write(d);
      using (var md5 = System.Security.Cryptography.MD5.Create()) {
        w.Write(md5.ComputeHash(t)); w.Write(md5.ComputeHash(new byte[0])); w.Flush();
        byte[] sofar = o.ToArray(); w.Write(md5.ComputeHash(sofar));
      }
      File.WriteAllBytes(outPath, o.ToArray());
    }
    static uint[] crcTable;
    public static uint Crc32(byte[] b) {
      if (crcTable == null) { crcTable = new uint[256]; for (uint n = 0; n < 256; n++) { uint c = n; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1; crcTable[n] = c; } }
      uint crc = 0xFFFFFFFF; foreach (byte x in b) crc = crcTable[(crc ^ x) & 0xFF] ^ (crc >> 8); return crc ^ 0xFFFFFFFF;
    }
  }
}
'@
}

# Compiled Source 2 resources (*_c): block table and external references, read without decompiling.
# Layout as in ValveResourceFormat (Resource.cs, ResourceExtRefList.cs).
if (-not ('DeadlockModding.Resource' -as [type])) {
  Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Text;
namespace DeadlockModding {
  public class ResourceBlock { public string Type; public int Offset; public int Size; }
  public static class Resource {
    public static List<ResourceBlock> Blocks(byte[] b) {
      var list = new List<ResourceBlock>();
      if (b.Length < 16) return list;
      int start = 8 + (int)BitConverter.ToUInt32(b, 8); uint count = BitConverter.ToUInt32(b, 12);
      for (int i = 0; i < count && start + i * 12 + 12 <= b.Length; i++) {
        int p = start + i * 12;
        list.Add(new ResourceBlock { Type = Encoding.ASCII.GetString(b, p, 4), Offset = p + 4 + (int)BitConverter.ToUInt32(b, p + 4), Size = (int)BitConverter.ToUInt32(b, p + 8) });
      }
      return list;
    }
    // Paths in the RERL block (source names, e.g. "materials/x.vmat"; the game file adds _c).
    public static List<string> Refs(byte[] b) {
      var refs = new List<string>();
      foreach (var blk in Blocks(b)) {
        if (blk.Type != "RERL" || blk.Size < 8) continue;
        int p = blk.Offset + (int)BitConverter.ToUInt32(b, blk.Offset); uint n = BitConverter.ToUInt32(b, blk.Offset + 4);
        for (int i = 0; i < n; i++, p += 16) {
          int s = p + 8 + (int)BitConverter.ToInt64(b, p + 8), e = s;
          while (e < b.Length && b[e] != 0) e++;
          refs.Add(Encoding.UTF8.GetString(b, s, e - s));
        }
      }
      return refs;
    }
  }
}
'@
}

# Block types (e.g. RERL, DATA, ANIM) and external references of a compiled resource's bytes.
function Get-ResourceBlocks([byte[]]$Bytes) { [DeadlockModding.Resource]::Blocks($Bytes) }
function Get-ResourceRefs([byte[]]$Bytes) { [DeadlockModding.Resource]::Refs($Bytes) }

# Entries (Path, Bytes, InDirFile, ...) of a VPK whose path starts with $Filter (case-insensitive).
function Read-VpkTree([string]$Path, [string]$Filter = '') {
  $dataStart = [long]0
  [DeadlockModding.Vpk]::Read((Resolve-Path $Path).Path, $Filter, [ref]$dataStart)
}

# Write one entry's raw (compiled) bytes to $Destination.
function Export-VpkFile($Entry, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path (Split-Path $Destination) | Out-Null
  [System.IO.File]::WriteAllBytes($Destination, [DeadlockModding.Vpk]::Extract($Entry))
}

# Pack every file under $Staging into a single-file VPK v2 at $Out (paths lowercased, forward slashes).
function New-Vpk([string]$Staging, [string]$Out) {
  $base = (Resolve-Path $Staging).Path.TrimEnd('\') + '\'
  $files = @(Get-ChildItem $Staging -Recurse -File)
  if (-not $files) { throw "Nothing to pack in $Staging" }
  $paths = $files | ForEach-Object { $_.FullName.Substring($base.Length).Replace('\', '/').ToLowerInvariant() }
  [DeadlockModding.Vpk]::Write([IO.Path]::GetFullPath($Out), [string[]]$paths, [string[]]($files.FullName))
}

# The game's main content VPK.
function Get-GameVpk([string]$Root) { Join-Path $Root 'game\citadel\pak01_dir.vpk' }
