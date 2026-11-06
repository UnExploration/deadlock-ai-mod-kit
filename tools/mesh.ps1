# Shared mesh helpers for preview-model.ps1 and convert-model.ps1 (dot-source this file; PowerShell 7).
#
# Every mesh is held in Source 2 model space: inches, Z up. Readers convert on the way in:
#   glTF/GLB (metres, Y up):         Source (x, y, z) = 39.37 * (gx, -gz, gy)
#   OBJ, as resourcecompiler reads it (file units = inches, Y up): Source (x, y, z) = (ox, -oz, oy)
# UVs are kept with V pointing up (OBJ convention); glTF V is flipped on the way in.
# Source2Viewer-CLI's glTF export of a compiled .vmdl_c follows the glTF convention, so compiled models
# and source meshes land in the same space and can be overlaid.

if (-not ('DeadlockModding.MeshPart' -as [type])) {
  Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Globalization; using System.IO; using System.Text;
namespace DeadlockModding {
  public class MeshPart {
    public string Name = ""; public string Material = "default";
    public List<float> Pos = new List<float>();   // x,y,z per vertex (Source inches, Z up)
    public List<float> Nrm = new List<float>();   // optional, same count as Pos
    public List<float> Uv = new List<float>();    // optional, u,v per vertex (V up)
    public List<int> Idx = new List<int>();       // triangles
    public int VertexCount { get { return Pos.Count / 3; } }
  }
  public static class MeshIO {
    static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
    // Reads a glTF accessor into floats (ncomp per element). compType: 5120 byte, 5121 ubyte, 5122 short, 5123 ushort, 5125 uint, 5126 float.
    public static float[] ReadFloats(byte[] buf, int offset, int stride, int count, int ncomp, int compType, bool normalized) {
      int size = compType == 5126 || compType == 5125 ? 4 : compType == 5122 || compType == 5123 ? 2 : 1;
      if (stride <= 0) stride = size * ncomp;
      var r = new float[count * ncomp];
      for (int i = 0; i < count; i++) for (int j = 0; j < ncomp; j++) {
        int o = offset + i * stride + j * size; float v;
        switch (compType) {
          case 5126: v = BitConverter.ToSingle(buf, o); break;
          case 5125: v = BitConverter.ToUInt32(buf, o); break;
          case 5123: v = BitConverter.ToUInt16(buf, o); if (normalized) v /= 65535f; break;
          case 5122: v = BitConverter.ToInt16(buf, o); if (normalized) v = Math.Max(v / 32767f, -1f); break;
          case 5121: v = buf[o]; if (normalized) v /= 255f; break;
          case 5120: v = (sbyte)buf[o]; if (normalized) v = Math.Max(v / 127f, -1f); break;
          default: throw new InvalidDataException("Unsupported accessor component type " + compType);
        }
        r[i * ncomp + j] = v;
      }
      return r;
    }
    public static int[] ReadIndices(byte[] buf, int offset, int count, int compType) {
      var r = new int[count];
      for (int i = 0; i < count; i++)
        r[i] = compType == 5125 ? (int)BitConverter.ToUInt32(buf, offset + 4 * i) : compType == 5123 ? BitConverter.ToUInt16(buf, offset + 2 * i) : buf[offset + i];
      return r;
    }
    // Adds a glTF primitive to a part: positions/normals through the column-major node matrix m, then glTF -> Source inches.
    public static void AddGltf(MeshPart part, float[] pos, float[] nrm, float[] uv, int[] idx, double[] m) {
      const double k = 39.37007874;
      int baseV = part.VertexCount, n = pos.Length / 3;
      for (int i = 0; i < n; i++) {
        double x = pos[3 * i], y = pos[3 * i + 1], z = pos[3 * i + 2];
        double gx = m[0] * x + m[4] * y + m[8] * z + m[12], gy = m[1] * x + m[5] * y + m[9] * z + m[13], gz = m[2] * x + m[6] * y + m[10] * z + m[14];
        part.Pos.Add((float)(gx * k)); part.Pos.Add((float)(-gz * k)); part.Pos.Add((float)(gy * k));
        if (nrm != null) {
          double a = nrm[3 * i], b = nrm[3 * i + 1], c = nrm[3 * i + 2];
          double nx = m[0] * a + m[4] * b + m[8] * c, ny = m[1] * a + m[5] * b + m[9] * c, nz = m[2] * a + m[6] * b + m[10] * c;
          double l = Math.Sqrt(nx * nx + ny * ny + nz * nz); if (l < 1e-12) l = 1;
          part.Nrm.Add((float)(nx / l)); part.Nrm.Add((float)(-nz / l)); part.Nrm.Add((float)(ny / l));
        }
        if (uv != null) { part.Uv.Add(uv[2 * i]); part.Uv.Add(1f - uv[2 * i + 1]); }
      }
      if (idx == null) { idx = new int[n]; for (int i = 0; i < n; i++) idx[i] = i; }
      for (int i = 0; i + 2 < idx.Length; i += 3) { part.Idx.Add(baseV + idx[i]); part.Idx.Add(baseV + idx[i + 1]); part.Idx.Add(baseV + idx[i + 2]); }
    }
    // OBJ as resourcecompiler reads it: units = inches, Y up. One part per usemtl (in order of first use).
    public static List<MeshPart> ReadObj(string path) {
      var v = new List<float>(); var vt = new List<float>(); var vn = new List<float>();
      var parts = new Dictionary<string, MeshPart>(); var order = new List<MeshPart>();
      var maps = new Dictionary<string, Dictionary<string, int>>();
      string mat = "default"; string obj = "";
      foreach (var raw in File.ReadLines(path)) {
        var line = raw.Trim(); if (line.Length == 0 || line[0] == '#') continue;
        var t = line.Split((char[])null, StringSplitOptions.RemoveEmptyEntries);
        switch (t[0]) {
          case "v": v.Add(F(t[1])); v.Add(F(t[2])); v.Add(F(t[3])); break;
          case "vt": vt.Add(F(t[1])); vt.Add(t.Length > 2 ? F(t[2]) : 0f); break;
          case "vn": vn.Add(F(t[1])); vn.Add(F(t[2])); vn.Add(F(t[3])); break;
          case "o": case "g": if (t.Length > 1) obj = t[1]; break;
          case "usemtl": mat = t.Length > 1 ? line.Substring(6).Trim() : "default"; break;
          case "f": {
            MeshPart p;
            if (!parts.TryGetValue(mat, out p)) { p = new MeshPart { Name = obj, Material = mat }; parts[mat] = p; order.Add(p); maps[mat] = new Dictionary<string, int>(); }
            var map = maps[mat]; var corners = new List<int>();
            for (int i = 1; i < t.Length; i++) {
              int idx;
              if (!map.TryGetValue(t[i], out idx)) {
                var s = t[i].Split('/');
                int pi = Ref(s[0], v.Count / 3);
                idx = p.VertexCount; map[t[i]] = idx;
                p.Pos.Add(v[3 * pi]); p.Pos.Add(-v[3 * pi + 2]); p.Pos.Add(v[3 * pi + 1]);
                if (s.Length > 1 && s[1].Length > 0) { int ti = Ref(s[1], vt.Count / 2); p.Uv.Add(vt[2 * ti]); p.Uv.Add(vt[2 * ti + 1]); }
                if (s.Length > 2 && s[2].Length > 0) { int ni = Ref(s[2], vn.Count / 3); p.Nrm.Add(vn[3 * ni]); p.Nrm.Add(-vn[3 * ni + 2]); p.Nrm.Add(vn[3 * ni + 1]); }
              }
              corners.Add(idx);
            }
            for (int i = 1; i + 1 < corners.Count; i++) { p.Idx.Add(corners[0]); p.Idx.Add(corners[i]); p.Idx.Add(corners[i + 1]); }
            break;
          }
        }
      }
      foreach (var p in order) { if (p.Uv.Count != p.Pos.Count / 3 * 2) p.Uv.Clear(); if (p.Nrm.Count != p.Pos.Count) p.Nrm.Clear(); }
      return order;
    }
    static float F(string s) { return float.Parse(s, NumberStyles.Float, Inv); }
    static int Ref(string s, int count) { int i = int.Parse(s, Inv); return i < 0 ? count + i : i - 1; }
    // Writes parts as an OBJ resourcecompiler reads correctly: Source (x, y, z) -> OBJ (x, z, -y), inches. usemtl = materialNames[i].
    public static void WriteObj(string path, IList<MeshPart> parts, IList<string> materialNames, string header) {
      var sb = new StringBuilder(); sb.Append(header);
      int vb = 1, tb = 1, nb = 1;
      for (int p = 0; p < parts.Count; p++) {
        var m = parts[p]; int n = m.VertexCount; bool hasUv = m.Uv.Count == 2 * n, hasN = m.Nrm.Count == 3 * n;
        sb.Append("o ").Append(string.IsNullOrEmpty(m.Name) ? "part" + p : m.Name.Replace(' ', '_')).Append('\n');
        for (int i = 0; i < n; i++) sb.Append("v ").Append(G(m.Pos[3 * i])).Append(' ').Append(G(m.Pos[3 * i + 2])).Append(' ').Append(G(-m.Pos[3 * i + 1])).Append('\n');
        if (hasUv) for (int i = 0; i < n; i++) sb.Append("vt ").Append(G(m.Uv[2 * i])).Append(' ').Append(G(m.Uv[2 * i + 1])).Append('\n');
        if (hasN) for (int i = 0; i < n; i++) sb.Append("vn ").Append(G(m.Nrm[3 * i])).Append(' ').Append(G(m.Nrm[3 * i + 2])).Append(' ').Append(G(-m.Nrm[3 * i + 1])).Append('\n');
        sb.Append("usemtl ").Append(materialNames[p]).Append('\n');
        for (int i = 0; i + 2 < m.Idx.Count; i += 3) {
          sb.Append('f');
          for (int k = 0; k < 3; k++) {
            int ix = m.Idx[i + k];
            sb.Append(' ').Append(vb + ix);
            if (hasUv || hasN) sb.Append('/'); if (hasUv) sb.Append(tb + ix); if (hasN) sb.Append('/').Append(nb + ix);
          }
          sb.Append('\n');
        }
        vb += n; if (hasUv) tb += n; if (hasN) nb += n;
      }
      File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
    }
    static string G(float f) { return f.ToString("0.#####", Inv); }
    // x' = s * x + t, per axis (uniform s).
    public static void ScaleShift(MeshPart p, double s, double tx, double ty, double tz) {
      for (int i = 0; i < p.Pos.Count; i += 3) { p.Pos[i] = (float)(p.Pos[i] * s + tx); p.Pos[i + 1] = (float)(p.Pos[i + 1] * s + ty); p.Pos[i + 2] = (float)(p.Pos[i + 2] * s + tz); }
    }
    // Rotate about Z (yaw, degrees) and/or turn a Z-forward/lying model upright: axis 0 = X, 2 = Z.
    public static void Rotate(MeshPart p, int axis, double degrees) {
      double c = Math.Cos(degrees * Math.PI / 180), s = Math.Sin(degrees * Math.PI / 180);
      foreach (var L in new[] { p.Pos, p.Nrm }) for (int i = 0; i + 2 < L.Count; i += 3) {
        double x = L[i], y = L[i + 1], z = L[i + 2];
        if (axis == 2) { L[i] = (float)(c * x - s * y); L[i + 1] = (float)(s * x + c * y); }
        else if (axis == 0) { L[i + 1] = (float)(c * y - s * z); L[i + 2] = (float)(s * y + c * z); }
        else { L[i] = (float)(c * x + s * z); L[i + 2] = (float)(-s * x + c * z); }
      }
    }
    public static double[] Bounds(IList<MeshPart> parts) {
      var b = new double[] { double.MaxValue, double.MaxValue, double.MaxValue, double.MinValue, double.MinValue, double.MinValue };
      foreach (var p in parts) for (int i = 0; i < p.Pos.Count; i++) { int a = i % 3; if (p.Pos[i] < b[a]) b[a] = p.Pos[i]; if (p.Pos[i] > b[a + 3]) b[a + 3] = p.Pos[i]; }
      return b;
    }
    // Wireframe into a BGRA pixel buffer (w x h): screen x = ox + sx * pos[ah], screen y = oy - scale * pos[av].
    public static void Wire(byte[] px, int w, int h, IList<MeshPart> parts, int ah, double sx, int av, double scale, double ox, double oy, byte r, byte g, byte b, byte a) {
      foreach (var p in parts) for (int i = 0; i + 2 < p.Idx.Count; i += 3)
        for (int k = 0; k < 3; k++) {
          int i0 = p.Idx[i + k], i1 = p.Idx[i + (k + 1) % 3];
          Line(px, w, h, ox + sx * p.Pos[3 * i0 + ah], oy - scale * p.Pos[3 * i0 + av], ox + sx * p.Pos[3 * i1 + ah], oy - scale * p.Pos[3 * i1 + av], r, g, b, a);
        }
    }
    static void Line(byte[] px, int w, int h, double x0, double y0, double x1, double y1, byte r, byte g, byte b, byte a) {
      double dx = x1 - x0, dy = y1 - y0; int n = (int)Math.Ceiling(Math.Max(Math.Abs(dx), Math.Abs(dy))); if (n < 1) n = 1; if (n > 4 * (w + h)) return;
      for (int i = 0; i <= n; i++) {
        int x = (int)Math.Round(x0 + dx * i / n), y = (int)Math.Round(y0 + dy * i / n);
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        int o = 4 * (y * w + x);
        px[o] = (byte)((px[o] * (255 - a) + b * a) / 255); px[o + 1] = (byte)((px[o + 1] * (255 - a) + g * a) / 255); px[o + 2] = (byte)((px[o + 2] * (255 - a) + r * a) / 255);
      }
    }
  }
}
'@
}

# 4x4 column-major helpers for glTF node transforms.
function Get-GltfNodeMatrix($Node) {
  if ($Node.matrix) { return [double[]]@($Node.matrix) }
  $t = $(if ($Node.translation) { @($Node.translation) } else { @(0, 0, 0) })
  $q = $(if ($Node.rotation) { @($Node.rotation) } else { @(0, 0, 0, 1) })
  $s = $(if ($Node.scale) { @($Node.scale) } else { @(1, 1, 1) })
  $x = [double]$q[0]; $y = [double]$q[1]; $z = [double]$q[2]; $w = [double]$q[3]
  [double[]]@(
    ((1 - 2 * ($y * $y + $z * $z)) * $s[0]), ((2 * ($x * $y + $z * $w)) * $s[0]), ((2 * ($x * $z - $y * $w)) * $s[0]), 0,
    ((2 * ($x * $y - $z * $w)) * $s[1]), ((1 - 2 * ($x * $x + $z * $z)) * $s[1]), ((2 * ($y * $z + $x * $w)) * $s[1]), 0,
    ((2 * ($x * $z + $y * $w)) * $s[2]), ((2 * ($y * $z - $x * $w)) * $s[2]), ((1 - 2 * ($x * $x + $y * $y)) * $s[2]), 0,
    $t[0], $t[1], $t[2], 1)
}
function Join-Matrix([double[]]$A, [double[]]$B) {   # A * B
  $r = New-Object double[] 16
  for ($c = 0; $c -lt 4; $c++) { for ($row = 0; $row -lt 4; $row++) { $v = 0.0; for ($k = 0; $k -lt 4; $k++) { $v += $A[$k * 4 + $row] * $B[$c * 4 + $k] }; $r[$c * 4 + $row] = $v } }
  , $r
}

# Reads a .gltf, .glb or .obj into @{ Parts = MeshPart[]; Materials = @{ name = @{ Image = byte[] or $null; Ext = 'png'; Color = r,g,b,a } }; Notes = string[] }.
function Read-MeshFile([string]$Path) {
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($ext -eq '.obj') {
    $parts = [DeadlockModding.MeshIO]::ReadObj($Path)
    $mats = @{}; $notes = @()
    $mtl = Select-String -Path $Path -Pattern '^\s*mtllib\s+(.+)$' | Select-Object -First 1
    $mtlFile = $(if ($mtl) { Join-Path (Split-Path $Path) $mtl.Matches[0].Groups[1].Value.Trim() })
    $cur = $null; $info = @{}
    if ($mtlFile -and (Test-Path -LiteralPath $mtlFile)) {
      foreach ($l in Get-Content -LiteralPath $mtlFile) {
        if ($l -match '^\s*newmtl\s+(.+)$') { $cur = $Matches[1].Trim(); $info[$cur] = @{ Color = @(1, 1, 1, 1) } }
        elseif ($cur -and $l -match '^\s*map_Kd\s+(?:-\S+\s+\S+\s+)*(.+)$') { $info[$cur].Map = Join-Path (Split-Path $mtlFile) $Matches[1].Trim() }
        elseif ($cur -and $l -match '^\s*Kd\s+([\d.eE+-]+)\s+([\d.eE+-]+)\s+([\d.eE+-]+)') { $info[$cur].Color = @([double]$Matches[1], [double]$Matches[2], [double]$Matches[3], 1) }
      }
    }
    foreach ($p in $parts) {
      $i = $info[$p.Material]; $m = @{ Image = $null; Ext = $null; Color = @(1, 1, 1, 1) }
      if ($i) { $m.Color = $i.Color; if ($i.Map -and (Test-Path -LiteralPath $i.Map)) { $m.Image = [IO.File]::ReadAllBytes($i.Map); $m.Ext = [IO.Path]::GetExtension($i.Map).TrimStart('.').ToLowerInvariant() } elseif ($i.Map) { $notes += "texture not found: $($i.Map)" } }
      $mats[$p.Material] = $m
    }
    return @{ Parts = @($parts); Materials = $mats; Notes = $notes }
  }
  if ($ext -notin '.gltf', '.glb') { throw "Read-MeshFile reads .gltf, .glb and .obj, not $ext." }
  $dir = Split-Path ([IO.Path]::GetFullPath($Path))
  $bytes = [IO.File]::ReadAllBytes($Path); $bin = $null
  if ($ext -eq '.glb') {
    if ([BitConverter]::ToUInt32($bytes, 0) -ne 0x46546C67) { throw "Not a GLB file: $Path" }
    $p = 12; $json = $null
    while ($p + 8 -le $bytes.Length) {
      $len = [BitConverter]::ToInt32($bytes, $p); $type = [BitConverter]::ToUInt32($bytes, $p + 4)
      if ($type -eq 0x4E4F534A) { $json = [Text.Encoding]::UTF8.GetString($bytes, $p + 8, $len) }
      elseif ($type -eq 0x004E4942) { $bin = New-Object byte[] $len; [Array]::Copy($bytes, $p + 8, $bin, 0, $len) }
      $p += 8 + $len
    }
    $g = $json | ConvertFrom-Json
  }
  else { $g = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json }
  foreach ($e in @($g.extensionsRequired)) { if ($e -match 'draco|meshopt|KHR_mesh_quantization') { throw "This glTF uses $e compression, which the built-in reader can't read. Convert it with Blender: convert-model.ps1 -Via blender." } }
  $buffers = @(foreach ($b in @($g.buffers)) {
      if (-not $b.uri) { , $bin }
      elseif ($b.uri -match '^data:[^,]*;base64,(.*)$') { , [Convert]::FromBase64String($Matches[1]) }
      else { , [IO.File]::ReadAllBytes((Join-Path $dir ([Uri]::UnescapeDataString($b.uri)))) }
    })
  $view = {
    param($i) $bv = $g.bufferViews[$i]
    @{ Buf = $buffers[[int]$bv.buffer]; Offset = [int]$bv.byteOffset; Stride = [int]$bv.byteStride; Length = [int]$bv.byteLength }
  }
  $read = {
    param($i, [switch]$Indices)
    $a = $g.accessors[$i]
    if ($a.sparse) { throw "Sparse glTF accessors aren't supported; convert with -Via blender." }
    $n = @{ SCALAR = 1; VEC2 = 2; VEC3 = 3; VEC4 = 4 }[$a.type]
    if ($null -eq $a.bufferView) { return , (New-Object float[] ($a.count * $n)) }
    $v = & $view $a.bufferView
    $off = $v.Offset + [int]$a.byteOffset
    if ($Indices) { , [DeadlockModding.MeshIO]::ReadIndices($v.Buf, $off, [int]$a.count, [int]$a.componentType) }
    else { , [DeadlockModding.MeshIO]::ReadFloats($v.Buf, $off, $v.Stride, [int]$a.count, $n, [int]$a.componentType, [bool]$a.normalized) }
  }
  # Materials and their base colour image.
  $mats = @{}; $matNames = @{}; $notes = @()
  $gm = @($g.materials)
  for ($i = 0; $i -lt $gm.Count; $i++) {
    $m = $gm[$i]; $name = $(if ($m.name) { $m.name } else { "material$i" })
    if ($matNames.Values -contains $name) { $name = "$name$i" }
    $matNames[$i] = $name
    $pbr = $m.pbrMetallicRoughness; $sg = $m.extensions.KHR_materials_pbrSpecularGlossiness
    $tex = $(if ($pbr.baseColorTexture) { $pbr.baseColorTexture.index } elseif ($sg.diffuseTexture) { $sg.diffuseTexture.index })
    $color = $(if ($pbr.baseColorFactor) { @($pbr.baseColorFactor) } elseif ($sg.diffuseFactor) { @($sg.diffuseFactor) } else { @(1, 1, 1, 1) })
    $entry = @{ Image = $null; Ext = $null; Color = $color }
    if ($null -ne $tex) {
      $img = $g.images[$g.textures[$tex].source]
      if ($null -ne $img.bufferView) {
        $v = & $view $img.bufferView; $data = New-Object byte[] $v.Length; [Array]::Copy($v.Buf, $v.Offset, $data, 0, $v.Length)
        $entry.Image = $data; $entry.Ext = $(if ($img.mimeType -match 'jpe?g') { 'jpg' } else { 'png' })
      }
      elseif ($img.uri -match '^data:image/(\w+);base64,(.*)$') { $entry.Image = [Convert]::FromBase64String($Matches[2]); $entry.Ext = $(if ($Matches[1] -match 'jpe?g') { 'jpg' } else { $Matches[1] }) }
      elseif ($img.uri) {
        $f = Join-Path $dir ([Uri]::UnescapeDataString($img.uri))
        if (Test-Path -LiteralPath $f) { $entry.Image = [IO.File]::ReadAllBytes($f); $entry.Ext = [IO.Path]::GetExtension($f).TrimStart('.').ToLowerInvariant() }
        else { $notes += "texture not found: $f" }
      }
    }
    $mats[$name] = $entry
  }
  # Walk the scene: every mesh node, with its world matrix. One part per primitive, merged per (node, material).
  $parts = [Collections.Generic.List[DeadlockModding.MeshPart]]::new()
  $identity = [double[]]@(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
  $sceneIndex = $(if ($null -ne $g.scene) { [int]$g.scene } else { 0 })
  $roots = $(if ($g.scenes) { @($g.scenes[$sceneIndex].nodes) } else { 0..(@($g.nodes).Count - 1) })
  $stack = [Collections.Generic.Stack[object]]::new()
  foreach ($r in $roots) { $stack.Push(@([int]$r, $identity)) }
  while ($stack.Count) {
    $item = $stack.Pop(); $node = $g.nodes[$item[0]]
    $world = Join-Matrix $item[1] (Get-GltfNodeMatrix $node)
    foreach ($c in @($node.children)) { if ($null -ne $c) { $stack.Push(@([int]$c, $world)) } }
    if ($null -eq $node.mesh) { continue }
    $mesh = $g.meshes[[int]$node.mesh]
    $nodeName = $(if ($node.name) { $node.name } elseif ($mesh.name) { $mesh.name } else { "mesh$($node.mesh)" })
    foreach ($pr in @($mesh.primitives)) {
      if ($null -ne $pr.mode -and $pr.mode -ne 4) { $notes += "skipped a non-triangle primitive in $nodeName"; continue }
      $matName = $(if ($null -ne $pr.material) { $matNames[[int]$pr.material] } else { 'default' })
      if (-not $mats[$matName]) { $mats[$matName] = @{ Image = $null; Ext = $null; Color = @(1, 1, 1, 1) } }
      $part = $parts | Where-Object { $_.Name -eq $nodeName -and $_.Material -eq $matName } | Select-Object -First 1
      if (-not $part) { $part = [DeadlockModding.MeshPart]::new(); $part.Name = $nodeName; $part.Material = $matName; $parts.Add($part) }
      $pos = & $read $pr.attributes.POSITION
      $nrm = $(if ($null -ne $pr.attributes.NORMAL) { & $read $pr.attributes.NORMAL })
      $uv = $(if ($null -ne $pr.attributes.TEXCOORD_0) { & $read $pr.attributes.TEXCOORD_0 })
      $idx = $(if ($null -ne $pr.indices) { & $read $pr.indices -Indices })
      if (($part.Nrm.Count -eq 0 -and $part.VertexCount -gt 0) -and $nrm) { $nrm = $null }   # keep attribute sets consistent per part
      if (($part.Uv.Count -eq 0 -and $part.VertexCount -gt 0) -and $uv) { $uv = $null }
      [DeadlockModding.MeshIO]::AddGltf($part, $pos, $nrm, $uv, $idx, $world)
      if ($part.Nrm.Count -ne $part.Pos.Count) { $part.Nrm.Clear() }
      if ($part.Uv.Count -ne $part.VertexCount * 2) { $part.Uv.Clear() }
    }
  }
  @{ Parts = @($parts); Materials = $mats; Notes = $notes }
}

# Bounds of parts: @{ Min = x,y,z; Max = x,y,z; Size = w,d,h; Center = x,y,z } in inches, or $null when empty.
function Get-MeshBounds($Parts) {
  $list = [Collections.Generic.List[DeadlockModding.MeshPart]]::new(); foreach ($p in @($Parts)) { if ($p) { $list.Add($p) } }
  if (-not ($list | Where-Object { $_.Pos.Count })) { return $null }
  $b = [DeadlockModding.MeshIO]::Bounds($list)
  @{ Min = @($b[0], $b[1], $b[2]); Max = @($b[3], $b[4], $b[5]); Size = @(($b[3] - $b[0]), ($b[4] - $b[1]), ($b[5] - $b[2])); Center = @((($b[0] + $b[3]) / 2), (($b[1] + $b[4]) / 2), (($b[2] + $b[5]) / 2)) }
}

# A compiled model (.vmdl_c file, or a game path inside a .vpk) exported to glTF with Source2Viewer-CLI, then read.
# Returns the Read-MeshFile result (Parts empty when the model has no mesh).
function Read-CompiledModel([string]$File, [string]$Vpk, [string]$GamePath, [string]$WorkDir) {
  $s2v = Find-Source2ViewerCli
  if (-not $s2v) { throw "Source2Viewer-CLI not found. Install it with setup.ps1 (-Approve s2v)." }
  $dir = Join-Path $WorkDir ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $dir | Out-Null
  if ($File) { $log = & $s2v -i $File -d --gltf_export_format gltf -o (Join-Path $dir 'model.gltf') 2>&1 }
  else { $log = & $s2v -i $Vpk -f $GamePath -d --gltf_export_format gltf -o $dir 2>&1 }
  $gltf = Get-ChildItem $dir -Recurse -Filter '*.gltf' -File | Where-Object { $_.Name -notmatch '_physics\.gltf$' } | Select-Object -First 1
  if (-not $gltf) { throw "Source2Viewer-CLI exported no model from $(if ($File) { $File } else { "$Vpk : $GamePath" }). Its output:`n$($log -join "`n")" }
  $g = Get-Content $gltf.FullName -Raw | ConvertFrom-Json
  if (-not $g.meshes) { return @{ Parts = @(); Materials = @{}; Notes = @('the compiled model has no mesh') } }
  Read-MeshFile $gltf.FullName
}

# ---- materials ---------------------------------------------------------------------------------------
# Deadlock lights its world through NPR (painted-look) lighting. A pbr.vfx material without
# F_USE_NPR_LIGHTING showed near-black in-game; with these settings (+ the glow below) it looked right next to
# stock props (soul container swap, build 6821, 2026-10-27). NPR lighting, the outline, the status-effects
# proxy (hit flashes), not metal, roughness 0.7.
$script:VmatNpr = [ordered]@{
  'F_USE_NPR_LIGHTING' = '1'; 'F_OVERRIDE_NPR_OUTLINE' = '1'; 'F_USE_STATUS_EFFECTS_PROXY' = '1'
  'g_flOverrideNprOutlineThickness' = '0.05'
}
# -Glow: an even self-illum over the whole model, tint * scale (default: the warm glow seen in-game, 6821).
$script:VmatGlowTint = @(0.4, 0.2, 0.05)

# Reads a .vmat (text: hand-written, or decompiled by Source2Viewer-CLI) into its shader, its top-level
# "key" "value" pairs (Params) and its DynamicParams (Dynamic). Other blocks ("Compiled Textures", ...) are skipped.
function ConvertFrom-Vmat([string]$Text) {
  $clean = ($Text -split "`r?`n" | ForEach-Object { $_ -replace '^\s*//.*$', '' }) -join "`n"
  $params = [ordered]@{}; $dyn = [ordered]@{}; $stack = [Collections.Generic.List[string]]::new(); $pending = $null
  foreach ($m in [regex]::Matches($clean, '"([^"]*)"|([{}])')) {
    if ($m.Groups[2].Success) {
      if ($m.Value -eq '{') { $stack.Add([string]$pending); $pending = $null }
      elseif ($stack.Count) { $stack.RemoveAt($stack.Count - 1); $pending = $null }
      continue
    }
    if ($null -eq $pending) { $pending = $m.Groups[1].Value; continue }
    if ($stack.Count -eq 1) { $params[$pending] = $m.Groups[1].Value }
    elseif ($stack.Count -eq 2 -and $stack[1] -eq 'DynamicParams') { $dyn[$pending] = $m.Groups[1].Value }
    $pending = $null
  }
  $shader = $params['shader']; $params.Remove('shader')
  @{ Shader = $shader; Params = $params; Dynamic = $dyn }
}

# The text of a .vmat for a converted model: pbr.vfx, the colour png, and either the NPR defaults above or,
# with -Stock (ConvertFrom-Vmat of the stock model's material), the stock F_* flags, g_* values, constant
# Texture* values and DynamicParams. Stock texture paths are dropped (the user has no source files for
# them); metalness, roughness and a texture-masked glow get constant stand-ins. -Glow adds a mild even
# glow (-GlowTint r,g,b in 0..1). Returns @{ Text; Notes }.
function New-ModelVmat([string]$ColorPath, $Stock, [switch]$Glow, [double[]]$GlowTint) {
  $p = [ordered]@{}; $dyn = [ordered]@{}; $notes = [Collections.Generic.List[string]]::new(); $dropped = @()
  if ($Stock -and $Stock.Shader -and $Stock.Shader -ne 'pbr.vfx') { $notes.Add("the stock material uses $($Stock.Shader), not pbr.vfx: its settings were not copied"); $Stock = $null }
  if ($Stock) {
    foreach ($k in $Stock.Params.Keys) {
      $v = [string]$Stock.Params[$k]
      if ($k -match '^(F_|g_)') { $p[$k] = $v }
      elseif ($k -match '^Texture' -and $k -ne 'TextureColor1') { if ($v -match '^\s*\[') { $p[$k] = $v } else { $dropped += $k } }
    }
    foreach ($k in $Stock.Dynamic.Keys) { $dyn[$k] = $Stock.Dynamic[$k] }
    if ($dropped -contains 'TextureSelfIllumMask1' -and $p['F_SELF_ILLUM'] -eq '1' -and -not $Glow) {
      $p['TextureSelfIllumMask1'] = '[0.000000 0.000000 0.000000 0.000000]'
      $notes.Add('the stock glow is masked by a texture you do not have: glow left off (add -Glow for an even glow)')
    }
  }
  else { foreach ($k in $script:VmatNpr.Keys) { $p[$k] = $script:VmatNpr[$k] } }
  # pbr.vfx packs metalness into the colour texture's alpha. A constant keeps it from reading the png's
  # alpha (often 255, fully metal, which renders dark) and keeps the result non-metal unless the stock said otherwise.
  if ([string]$p['TextureMetalness1'] -notmatch '^\s*\[') { $p['TextureMetalness1'] = '[0.000000 0.000000 0.000000 0.000000]' }
  if ([string]$p['TextureRoughness1'] -notmatch '^\s*\[') { $p['TextureRoughness1'] = '[0.700000 0.700000 0.700000 0.000000]' }
  $dropped = @($dropped | Where-Object { $_ -notin 'TextureMetalness1', 'TextureRoughness1', 'TextureSelfIllumMask1' })
  if ($dropped) { $notes.Add("stock textures left at the shader's defaults (you don't have their files): $($dropped -join ', ')") }
  if ($Glow) {
    $t = $(if ($GlowTint) { $GlowTint } else { $script:VmatGlowTint })
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $glowSet = [ordered]@{ 'F_SELF_ILLUM' = '1'; 'g_flSelfIllumScale1' = '0.25'
      'g_vSelfIllumTint1' = '[' + (($t[0..2] + 0 | ForEach-Object { ([double]$_).ToString('0.000000', $inv) }) -join ' ') + ']'
      'TextureSelfIllumMask1' = '[1.000000 1.000000 1.000000 0.000000]' }
    foreach ($k in $glowSet.Keys) { $p[$k] = $glowSet[$k]; $dyn.Remove($k) }
  }
  $p['TextureColor1'] = $ColorPath
  $i = 0
  $keys = @($p.Keys | ForEach-Object {
      $g = $(if ($_ -match '^F_') { 0 } elseif ($_ -match '^g_') { 1 } elseif ($_ -eq 'TextureColor1') { 3 } else { 2 })
      [pscustomobject]@{ K = $_; G = $g; I = $i++ } } | Sort-Object G, I | ForEach-Object K)
  $sb = [Text.StringBuilder]::new("`"Layer0`"`r`n{`r`n`t`"shader`"`t`"pbr.vfx`"`r`n")
  foreach ($k in $keys) { [void]$sb.Append("`t`"$k`"`t`"$($p[$k])`"`r`n") }
  if ($dyn.Count) {
    [void]$sb.Append("`t`"DynamicParams`"`r`n`t{`r`n")
    foreach ($k in $dyn.Keys) { [void]$sb.Append("`t`t`"$k`"`t`"$($dyn[$k])`"`r`n") }
    [void]$sb.Append("`t}`r`n")
  }
  [void]$sb.Append("}`r`n")
  @{ Text = $sb.ToString(); Notes = @($notes) }
}

# The decompiled .vmat of the material a stock model uses, for New-ModelVmat. -Material (a game path, or a
# .vmat or .vmat_c file) wins; else the first material -Model (a game path or .vmdl_c file) references.
# Returns @{ Path; Text; Others } ($null when -Model is a source mesh such as .obj, or -Material is
# 'default'). Throws when it can't.
function Get-StockMaterial([string]$Model, [string]$Material, [string]$Deadlock, [string]$WorkDir) {
  if ($Material -eq 'default') { return $null }
  $file = $null; $path = $null; $others = @(); $vpk = $null
  $gameVpk = { Get-GameVpk $(if ($Deadlock) { $Deadlock } else { Find-DeadlockRoot }) }
  $norm = { param($s) $s = $s.Replace('\', '/').ToLowerInvariant(); if (-not $s.EndsWith('_c')) { $s += '_c' }; $s }
  if ($Material) {
    if (Test-Path -LiteralPath $Material) {
      $file = (Resolve-Path -LiteralPath $Material).Path
      if ($file -notmatch '_c$') { return @{ Path = $Material; Text = [IO.File]::ReadAllText($file); Others = @() } }
      $path = $Material
    }
    else { $path = & $norm $Material }
  }
  elseif ($Model) {
    if (Test-Path -LiteralPath $Model) {
      if ($Model -notmatch '\.vmdl_c$') { return $null }
      $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Model).Path)
    }
    else {
      $sp = & $norm $Model; $vpk = & $gameVpk
      $entry = Read-VpkTree $vpk $sp | Where-Object { $_.Path -eq $sp } | Select-Object -First 1
      if (-not $entry) { throw "$sp is not in $vpk" }
      $bytes = [DeadlockModding.Vpk]::Extract($entry)
    }
    $mats = @(Get-ResourceRefs $bytes | Where-Object { $_ -match '\.vmat$' })
    if (-not $mats) { throw "the stock model names no material" }
    $path = "$($mats[0])_c"; $others = @($mats | Select-Object -Skip 1)
  }
  else { return $null }
  $s2v = Find-Source2ViewerCli
  if (-not $s2v) { throw "Source2Viewer-CLI not found (setup.ps1 -Approve s2v)" }
  $dir = Join-Path $WorkDir ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $dir | Out-Null
  $o = Join-Path $dir 'stock.vmat'
  if ($file) { $log = & $s2v -i $file -d -o $o 2>&1 }
  else { if (-not $vpk) { $vpk = & $gameVpk }; $log = & $s2v -i $vpk -f $path -d -o $o 2>&1 }
  $got = $(if (Test-Path -LiteralPath $o -PathType Leaf) { $o } else { Get-ChildItem $dir -Recurse -Filter '*.vmat' -File | Select-Object -First 1 -ExpandProperty FullName })
  if (-not $got) { throw "Source2Viewer-CLI did not decompile $path. Its output: $($log -join ' ')" }
  @{ Path = $path; Text = [IO.File]::ReadAllText($got); Others = $others }
}
