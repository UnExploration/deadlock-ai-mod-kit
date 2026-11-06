// The kit's MCP tools: each is a thin wrapper over a PowerShell tool in tools/
// (or a direct file read), so the scripts stay the single source of behaviour and work without MCP.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');

const REPO = path.resolve(__dirname, '..');
const TOOLS = path.join(REPO, 'tools');
// kit_docs never serves these (user mods, dependencies, git internals).
const DOCS_DENY_FIRST = ['mods'];
const DOCS_DENY_ANY = ['node_modules', '.git'];
const MAX_OUTPUT = 40000;
const MIN = 60 * 1000;

// ---- running things ------------------------------------------------------------------------

function stripAnsi(s) { return s.replace(/\u001b\[[0-9;?]*[A-Za-z]/g, ''); }

function capOutput(s) {
  if (s.length <= MAX_OUTPUT) return s;
  return '[... ' + (s.length - MAX_OUTPUT) + ' earlier characters cut ...]\n' + s.slice(-MAX_OUTPUT);
}

function findOnPath(exe) {
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (dir && fs.existsSync(path.join(dir, exe))) return path.join(dir, exe);
  }
  return null;
}

// How PowerShell tools are started. DEADLOCK_MCP_RUNNER (a JSON array, e.g. ["node","fake.js"]) replaces
// it in tests. pwsh 7 runs everything; doctor and setup also run in Windows PowerShell 5.1, so a PC
// without pwsh can still check itself and install it.
function runnerFor(script) {
  if (process.env.DEADLOCK_MCP_RUNNER) return JSON.parse(process.env.DEADLOCK_MCP_RUNNER);
  const pwsh = findOnPath('pwsh.exe') || findOnPath('pwsh');
  if (pwsh) return [pwsh, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File'];
  if (script === 'doctor.ps1' || script === 'setup.ps1') return ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File'];
  return null;
}

function run(command, args, { cwd = REPO, timeoutMs = 5 * MIN } = {}) {
  return new Promise((resolve) => {
    let out = '';
    let child;
    const env = { ...process.env, NO_COLOR: '1' };
    delete env.NODE_TEST_CONTEXT;   // set when the server itself runs under node --test; it breaks a child node --test
    try {
      child = spawn(command, args, { cwd, windowsHide: true, env });
    } catch (e) {
      return resolve({ code: -1, out: 'Could not start ' + command + ': ' + e.message });
    }
    const timer = setTimeout(() => { out += '\n[stopped: took longer than ' + Math.round(timeoutMs / MIN) + ' minutes]'; child.kill(); }, timeoutMs);
    child.stdout.on('data', (d) => { out += d; });
    child.stderr.on('data', (d) => { out += d; });
    child.on('error', (e) => { clearTimeout(timer); resolve({ code: -1, out: out + '\nCould not start ' + command + ': ' + e.message }); });
    child.on('close', (code) => { clearTimeout(timer); resolve({ code: code === null ? -1 : code, out: capOutput(stripAnsi(out).trim()) }); });
  });
}

// script is a file in tools/, or in the repo root with opts.root (the first-run setup.ps1).
async function runTool(script, args = [], opts = {}) {
  const runner = runnerFor(script);
  if (!runner) return text('PowerShell 7 is missing, and ' + script + ' needs it. Call setup (no arguments) to list what to install, then setup with approve ["pwsh"] after the user says yes.', true);
  const [cmd, ...pre] = runner;
  const r = await run(cmd, [...pre, path.join(opts.root ? REPO : TOOLS, script), ...args], opts);
  const note = opts.exitNotes && opts.exitNotes[r.code];
  const body = (r.out || '(no output)') + '\n\n[exit code ' + r.code + (note ? ': ' + note : '') + ']';
  return text(body, r.code !== 0 && !note);
}

function text(s, isError = false) { return { content: [{ type: 'text', text: s }], isError }; }

// ---- helpers ---------------------------------------------------------------------------------

// A mod argument: a folder path, or a bare name in mods/.
function resolveMod(mod) {
  if (typeof mod !== 'string' || !mod.trim()) throw new Error('mod is required: a mod name (e.g. "my-mod") or a folder path.');
  if (/[\\/]/.test(mod) || path.isAbsolute(mod)) return path.resolve(REPO, mod);
  return path.join(REPO, 'mods', mod);
}

function requireModFolder(mod) {
  const dir = resolveMod(mod);
  if (!fs.existsSync(path.join(dir, 'mod.json'))) throw new Error('No mod.json in ' + dir + '. Create the mod with new_mod, or pass its folder path.');
  return dir;
}

// Deadlock folder, build and kit folder, from the same helper the scripts use. Cached per process.
let contextCache = null;
async function gameContext() {
  if (process.env.DEADLOCK_MCP_CONTEXT) return JSON.parse(process.env.DEADLOCK_MCP_CONTEXT);
  if (contextCache) return contextCache;
  const runner = runnerFor('context');
  if (!runner) throw new Error('PowerShell 7 is missing. Call setup to install it.');
  const ps = ". '" + path.join(TOOLS, 'deadlock-paths.ps1').replace(/'/g, "''") + "'; $r = Find-DeadlockRoot; " +
    "[pscustomobject]@{ root = $r; build = (Get-DeadlockBuild $r); kitHome = $script:KitHome } | ConvertTo-Json -Compress";
  const pre = runner.filter((a) => a !== '-File');
  const r = await run(runner[0], [...pre.slice(1), '-Command', ps], { timeoutMs: MIN });
  const line = r.out.split(/\r?\n/).find((l) => l.startsWith('{'));
  if (r.code !== 0 || !line) throw new Error('Could not find Deadlock: ' + r.out);
  contextCache = JSON.parse(line);
  return contextCache;
}

function parseTsv(file) {
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(Boolean);
  const header = lines.shift().split('\t');
  return { header, rows: lines.map((l) => l.split('\t')) };
}

const CATALOG_TABLES = ['files', 'soundevents', 'sounds', 'heroes', 'ui', 'models'];

// ---- the tools -------------------------------------------------------------------------------

const S = (properties, required = []) => ({ type: 'object', properties, required, additionalProperties: false });
const MOD = { type: 'string', description: 'Mod name (a folder in mods/) or a folder path.' };
const RO = { readOnlyHint: true, openWorldHint: false };

const tools = [
  {
    name: 'kit_docs',
    title: 'Read the kit\'s guides',
    description: 'Read deadlock-ai-mod-kit knowledge. No path: the cookbook router (find the row for the request\'s file type and follow its guide; start every mod here). path: a file in the kit, e.g. "cookbook/sounds.md", "SKILL.md", "docs/03-panorama.md". "generated/README.md" is the index of the data read off the installed game (heroes, UI layouts and panel IDs, file types, sounds, models): take paths, IDs and names from there. If generated/ holds only its README, call setup first: it builds the folder from the user\'s game. "docs/README.md" is the index of authored knowledge (how things work, what is proven).',
    inputSchema: S({ path: { type: 'string', description: 'Relative to the kit folder. Default: cookbook/README.md' } }),
    annotations: RO,
    async handler({ path: rel = 'cookbook/README.md' }) {
      const p = path.resolve(REPO, rel);
      if (!p.startsWith(REPO + path.sep)) return text('path must stay inside the kit folder.', true);
      const segs = path.relative(REPO, p).toLowerCase().split(path.sep);
      if (DOCS_DENY_FIRST.includes(segs[0]) || segs.some((x) => DOCS_DENY_ANY.includes(x))) return text('kit_docs does not read mods/, node_modules/ or .git/.', true);
      if (!fs.existsSync(p) || fs.statSync(p).isDirectory()) {
        const dir = fs.existsSync(p) ? p : path.dirname(p);
        const list = fs.existsSync(dir) ? fs.readdirSync(dir).join('\n') : '';
        return text('Not a file: ' + rel + (list ? '\nIn ' + path.relative(REPO, dir).replace(/\\/g, '/') + '/:\n' + list : ''), true);
      }
      return text(capOutput(fs.readFileSync(p, 'utf8')));
    },
  },
  {
    name: 'doctor',
    title: 'Check this PC',
    description: 'Read-only setup check: Deadlock install and build, whether generated/ is for that build, whether mods load (addons mount), CSDK, Source2Viewer, Node, git, GitHub CLI, launch options, installed mods. Run it first in every session. Every FAIL/WARN line says how to fix it. When generated/ is missing or for another build, call setup (it rebuilds it).',
    inputSchema: S({ offline: { type: 'boolean', description: 'Skip the online stock-file check.' } }),
    annotations: RO,
    handler: ({ offline }) => runTool('doctor.ps1', offline ? ['-Offline'] : [], { exitNotes: {} }),
  },
  {
    name: 'setup',
    title: 'First-run setup: check, list or install tools, build generated/',
    description: 'Runs setup.ps1 in the kit root. No approve: the doctor\'s check, then the list of what this PC is missing (what, why, where from, size, warnings), then builds generated/ from the user\'s game when it is missing or for another build (1-2 minutes; needs PowerShell 7 and Source2Viewer-CLI). Downloads nothing. Show the list to the user and get ONE yes. Then call again with approve = the ids they agreed to (or ["all"]); it installs them and builds generated/ in the same run. Reduced CSDK 12 is unsigned: say so. Exit 2 means waiting for the user (approve the list, a manual CSDK download, a doctor FAIL): relay its last line. skipData: skip building generated/. offline: skip the doctor\'s online gameinfo.gi comparison. media: also list the optional yt-dlp and FFmpeg (unsigned), needed only for a sound made from a link or an audio file (prepare_audio). models: also list the optional Blender 4.5 (about 400 MB), needed only to read a .dae, .fbx or other 3D file for a model swap (convert_model); .glb, .gltf and .obj need nothing.',
    inputSchema: S({
      approve: { type: 'array', items: { type: 'string', enum: ['all', 'pwsh', 'csdk', 's2v', 'node', 'git', 'gh', 'ytdlp', 'ffmpeg', 'blender'] }, description: 'Only after the user said yes to the list.' },
      media: { type: 'boolean', description: 'Include the optional media tools (ytdlp, ffmpeg) in the list and in "all".' },
      models: { type: 'boolean', description: 'Include the optional Blender (blender) in the list and in "all".' },
      csdkZip: { type: 'string', description: 'Path to a Reduced_CSDK_12.zip the user downloaded (default: found in Downloads).' },
      skipData: { type: 'boolean', description: 'Do not build generated/.' },
      offline: { type: 'boolean', description: 'Skip the doctor\'s online gameinfo.gi comparison.' },
    }),
    annotations: { openWorldHint: true },
    handler: ({ approve, media, models, csdkZip, skipData, offline }) => runTool('setup.ps1', [
      ...(approve && approve.length ? ['-Approve', approve.join(',')] : []),
      ...(media ? ['-Media'] : []),
      ...(models ? ['-Models'] : []),
      ...(csdkZip ? ['-CsdkZip', csdkZip] : []),
      ...(skipData ? ['-SkipData'] : []),
      ...(offline ? ['-Offline'] : []),
    ], { root: true, timeoutMs: 120 * MIN, exitNotes: { 2: 'waiting for the user (see the last line above)' } }),
  },
  {
    name: 'mount_addons',
    title: 'Turn mod loading on or off',
    description: 'check: whether gameinfo.gi loads mods. enable: add the 3 lines that load the addons folder (needed once, and again after Deadlock patches reset it). disable: remove exactly those lines. Deadlock must be closed to change it. Only change it after the user asked to install or test mods.',
    inputSchema: S({ action: { type: 'string', enum: ['check', 'enable', 'disable'] } }, ['action']),
    annotations: { destructiveHint: false, idempotentHint: true },
    handler: ({ action }) => runTool('enable-addons.ps1', action === 'check' ? ['-Check'] : action === 'disable' ? ['-Disable'] : [],
      { exitNotes: action === 'check' ? { 1: 'not mounted: mods will not load' } : {} }),
  },
  {
    name: 'new_mod',
    title: 'Create a mod from a starter',
    description: 'Creates mods/<name>/ from a starter that works as-is, with a free pak number. kind: "ui" (on-screen: a badge on the main menu and HUD), "data" (ui + saving data: a note box that survives restarts; needs storeUrl), "sound" (menu sounds swapped, no compiler), "empty" (put files in src/ yourself, or use mod.json "copies"). hook: the game layout to attach to (ui/data; see the catalog\'s ui table).',
    inputSchema: S({
      name: { type: 'string', pattern: '^[a-z][a-z0-9_]{1,30}$', description: 'lowercase letters, digits, _' },
      kind: { type: 'string', enum: ['ui', 'data', 'sound', 'empty'] },
      hook: { type: 'string', description: 'Layout name without folder or extension, e.g. "hud_escape_menu". Default citadel_hud_and_db_overlay.' },
      pak: { type: 'integer', minimum: 1, maximum: 99 },
      storeUrl: { type: 'string', description: 'Required for kind "data": the storage page the mod saves through, permanently. "kit" for the kit\'s hosted page, or the user\'s own https address. Ask the user first, once, and give them the warning: the kit\'s page is run by the kit\'s author with no guarantee it stays online. Without it, new_mod returns the exact question to ask.' },
    }, ['name']),
    annotations: { destructiveHint: false },
    handler: ({ name, kind, hook, pak, storeUrl }) => runTool('new-mod.ps1', ['-Name', name, '-Dir', path.join(REPO, 'mods'),
      ...(kind ? ['-Kind', kind] : []), ...(hook ? ['-Hook', hook] : []), ...(pak ? ['-Pak', String(pak)] : []),
      ...(storeUrl ? ['-StoreUrl', storeUrl] : [])]),
  },
  {
    name: 'catalog_search',
    title: 'Search the game\'s files',
    description: 'Search the catalog of the installed Deadlock build (built locally by catalog_refresh). Tables: files (every game file: path, bytes), soundevents (event -> the sound files it plays, duration), sounds (sound file -> events), heroes (codename, name, model, sound scripts, abilities), ui (layout file -> root panel, panel ids, scripts, styles), models (model file -> plain-words aliases such as hero names or \"hideout, bartender\", anim: animgraph2/classic/none, skeleton, materials, the textures those materials use). query is a case-insensitive regex matched against whole rows, or one column if column is set.',
    inputSchema: S({
      table: { type: 'string', enum: CATALOG_TABLES },
      query: { type: 'string' },
      column: { type: 'string' },
      limit: { type: 'integer', minimum: 1, maximum: 500 },
    }, ['table', 'query']),
    annotations: RO,
    async handler({ table, query, column, limit = 40 }) {
      const ctx = await gameContext();
      const dir = path.join(ctx.kitHome, 'catalog', String(ctx.build));
      const file = path.join(dir, table + '.tsv');
      if (!fs.existsSync(file)) return text('No catalog for build ' + ctx.build + ' yet. Call catalog_refresh first (1-2 minutes).', true);
      let re;
      try { re = new RegExp(query, 'i'); } catch (e) { return text('Bad regex: ' + e.message, true); }
      const { header, rows } = parseTsv(file);
      const col = column ? header.indexOf(column) : -1;
      if (column && col < 0) return text('No column "' + column + '" in ' + table + '. Columns: ' + header.join(', '), true);
      const hits = rows.filter((r) => re.test(col >= 0 ? (r[col] || '') : r.join('\t')));
      const shown = hits.slice(0, limit).map((r) => r.join('\t'));
      return text('build ' + ctx.build + ', ' + table + ': ' + hits.length + ' match(es)' + (hits.length > limit ? ', first ' + limit + ' shown' : '') + '\n' + header.join('\t') + '\n' + shown.join('\n'));
    },
  },
  {
    name: 'catalog_refresh',
    title: 'Refresh the game-file catalog and generated/',
    description: 'Refreshes both the searchable catalog of the installed build (catalog_search reads it) and the kit\'s generated/ folder (readable Markdown of the same data: build, gameinfo.gi, file types, folders, heroes, UI layouts, sounds, models). 1-2 minutes when the build has no catalog yet; needs Source2Viewer-CLI. setup already does this on first run; call it after every Deadlock patch (the doctor warns when generated/ is for another build), or with force to rebuild the catalog. Keeps an existing catalog unless force.',
    inputSchema: S({ force: { type: 'boolean' } }),
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true },
    handler: ({ force }) => runTool('generate-docs.ps1', force ? ['-Force'] : [], { timeoutMs: 20 * MIN }),
  },
  {
    name: 'get_stock',
    title: 'Get original game files',
    description: 'Original files of the installed build. paths: game paths of sources, e.g. "panorama/layout/hud_escape_menu.xml" (decompiled). raw: copy compiled bytes instead (e.g. a .vsnd_c to audition or reuse). list: print the game paths starting with this prefix instead.',
    inputSchema: S({
      paths: { type: 'array', items: { type: 'string' } },
      list: { type: 'string' },
      out: { type: 'string', description: 'Folder to write into (default: the repo\'s stock/).' },
      raw: { type: 'boolean' },
    }),
    annotations: { destructiveHint: false },
    handler: ({ paths = [], list, out, raw }) => runTool('get-stock.ps1', [...paths,
      ...(list ? ['-List', list] : []), ...(out ? ['-Out', path.resolve(REPO, out)] : []), ...(raw ? ['-Raw'] : [])], { timeoutMs: 10 * MIN }),
  },
  {
    name: 'prepare_audio',
    title: 'Turn a clip into a sound-mod WAV',
    description: 'For a sound mod made from the user\'s own audio: source is an audio file in any format, or a link (YouTube etc.) the user gave. Writes out (a .wav: 44.1 kHz, 16-bit stereo), cut to start..end, cut to the length of the stock sound "like" (event name or sound path, from the catalog) with a fade-out, and set to a sensible loudness (or that of reference). Needs FFmpeg, and yt-dlp for links: optional tools from setup with media: true. Only use audio the user may use.',
    inputSchema: S({
      source: { type: 'string', description: 'Audio file path, or an http(s) link.' },
      out: { type: 'string', description: 'The .wav to write, normally src/<game sound path>.wav in the mod folder.' },
      start: { type: 'string', description: 'Seconds or m:ss(.ms).' },
      end: { type: 'string', description: 'Seconds or m:ss(.ms).' },
      like: { type: 'string', description: 'The stock sound it replaces (event or sounds/... path); caps the length.' },
      maxSeconds: { type: 'number', minimum: 0.05 },
      noTrim: { type: 'boolean', description: 'Keep a clip longer than the stock sound (only warn).' },
      reference: { type: 'string', description: 'Audio file whose loudness to match.' },
      noNormalize: { type: 'boolean' },
    }, ['source', 'out']),
    annotations: { destructiveHint: false, openWorldHint: true },
    handler: ({ source, out, start, end, like, maxSeconds, noTrim, reference, noNormalize }) => runTool('audio.ps1', [
      /^https?:\/\//i.test(source) ? source : path.resolve(REPO, source), '-Out', path.resolve(REPO, out),
      ...(start ? ['-Start', start] : []), ...(end ? ['-End', end] : []), ...(like ? ['-Like', like] : []),
      ...(maxSeconds ? ['-MaxSeconds', String(maxSeconds)] : []), ...(noTrim ? ['-NoTrim'] : []),
      ...(reference ? ['-Reference', path.resolve(REPO, reference)] : []), ...(noNormalize ? ['-NoNormalize'] : []),
    ], { timeoutMs: 15 * MIN }),
  },
  {
    name: 'convert_model',
    title: 'Turn a 3D file into a model-swap mesh',
    description: 'For a model swap (guide cookbook/models.md): reads the user\'s or a downloaded 3D model (.glb/.gltf/.obj built in; .dae/.fbx/.blend/.ply/.stl need the optional Blender from setup with models: true; a .zip holding one model) and writes into out (a folder inside the mod\'s src at a game path, e.g. mods/<mod>/src/models/props_gameplay/soul_container/pumpkin) an OBJ in inches standing upright, plus one .vmat and colour .png per material. like: a stock model (game path) to fit to: same height, centred on it, same bottom. Materials get Deadlock\'s NPR lighting (checked in-game; plain pbr looks near-black); copyStockMaterial copies the like model\'s own material settings instead (not yet seen in-game). glow: a mild warm glow (glowTint to change its colour). Prints the RenderMeshFile line for the .vmdl. Check the result with preview_model. Only use models the user may use; downloads need their yes.',
    inputSchema: S({
      source: { type: 'string', description: 'The model file (or a .zip with one).' },
      out: { type: 'string', description: 'Folder inside the mod\'s src, at the game path the files should have.' },
      name: { type: 'string', pattern: '^[a-z0-9_]+$', description: 'Base name of the written files (default: from the file name).' },
      like: { type: 'string', description: 'Stock model to fit to, e.g. "models/props_gameplay/soul_container/soul_container.vmdl_c".' },
      fit: { type: 'string', enum: ['height', 'largest'], description: 'With like: match the height (default) or the largest side.' },
      copyStockMaterial: { type: 'boolean', description: 'With like: copy the stock model\'s first material settings instead of the default NPR material (not yet seen in-game).' },
      likeMaterial: { type: 'string', description: 'Copy this stock material\'s settings (game path, or a .vmat/.vmat_c file); implies copyStockMaterial.' },
      glow: { type: 'boolean', description: 'Add a mild, even self-illum glow (warm by default).' },
      glowTint: { type: 'array', items: { type: 'number', minimum: 0, maximum: 1 }, minItems: 3, maxItems: 3, description: 'With glow: its colour as [r, g, b], 0..1 (default [0.4, 0.2, 0.05]).' },
      height: { type: 'number', minimum: 0.1, description: 'Scale to this height in inches instead (a person is ~72).' },
      scale: { type: 'number', minimum: 0.000001, description: 'Multiply first (e.g. 0.01 for centimetres).' },
      upAxis: { type: 'string', enum: ['Y', 'Z'], description: 'Z when the file was made Z-up and comes out lying down.' },
      rotateX: { type: 'number' }, rotateY: { type: 'number' }, rotateZ: { type: 'number', description: 'Degrees about Source axes (Z = up).' },
      only: { type: 'string', description: 'Regex: keep only mesh parts whose name matches (drop LODs and extras).' },
      pick: { type: 'string', description: 'With a .zip holding several models: the file name to use.' },
    }, ['source', 'out']),
    annotations: { destructiveHint: false },
    handler: ({ source, out, name, like, fit, copyStockMaterial, likeMaterial, glow, glowTint, height, scale, upAxis, rotateX, rotateY, rotateZ, only, pick }) => runTool('convert-model.ps1', [
      '-In', path.resolve(REPO, source), '-Out', path.resolve(REPO, out),
      ...(name ? ['-Name', name] : []), ...(like ? ['-Like', like] : []), ...(fit ? ['-Fit', fit] : []),
      ...(height ? ['-Height', String(height)] : []), ...(scale ? ['-Scale', String(scale)] : []), ...(upAxis ? ['-UpAxis', upAxis] : []),
      ...(rotateX ? ['-RotateX', String(rotateX)] : []), ...(rotateY ? ['-RotateY', String(rotateY)] : []), ...(rotateZ ? ['-RotateZ', String(rotateZ)] : []),
      ...(only ? ['-Only', only] : []), ...(pick ? ['-Pick', pick] : []),
      ...(copyStockMaterial ? ['-CopyStockMaterial'] : []), ...(likeMaterial ? ['-LikeMaterial', likeMaterial] : []), ...(glow ? ['-Glow'] : []), ...(glowTint ? ['-GlowTint', glowTint.join(',')] : []),
    ], { timeoutMs: 15 * MIN }),
  },
  {
    name: 'preview_model',
    title: 'Picture a model next to the stock one',
    description: 'Before any in-game test of a model swap: draws the model as front and side wireframes over the stock model on an inch grid, prints both bounds in inches, and warns about likely scale, orientation and placement mistakes. Then open the PNG it names (read the image) and look. Give mod + path (the model inside the mod\'s built pak; build_mod first) or model (a .vmdl_c, .gltf, .glb or .obj file). Exit 1 = the model has no mesh.',
    inputSchema: S({
      mod: MOD,
      path: { type: 'string', description: 'Game path of the model, e.g. models/props_gameplay/soul_container/soul_container.vmdl_c. With mod, the stock model at this path is overlaid.' },
      model: { type: 'string', description: 'A model file instead of mod + path.' },
      stock: { type: 'string', description: 'Stock model to overlay (game path or file), when it differs from path.' },
      noStock: { type: 'boolean' },
      out: { type: 'string', description: 'PNG to write (default: the mod\'s dist/preview.png).' },
    }),
    annotations: { readOnlyHint: false, destructiveHint: false },
    handler: ({ mod, path: p, model, stock, noStock, out }) => runTool('preview-model.ps1', [
      ...(mod ? ['-Mod', requireModFolder(mod)] : []), ...(p ? ['-Path', p] : []), ...(model ? ['-Model', path.resolve(REPO, model)] : []),
      ...(stock ? ['-Stock', /[\\/]/.test(stock) && fs.existsSync(path.resolve(REPO, stock)) ? path.resolve(REPO, stock) : stock] : []),
      ...(noStock ? ['-NoStock'] : []), ...(out ? ['-Out', path.resolve(REPO, out)] : []),
    ], { timeoutMs: 10 * MIN, exitNotes: {} }),
  },
  {
    name: 'test_mod',
    title: 'Run a mod\'s unit tests',
    description: 'Runs node --test in the mod folder (its test/ files, with a mocked Panorama). Run after every script change, before building.',
    inputSchema: S({ mod: MOD }, ['mod']),
    annotations: RO,
    async handler({ mod }) {
      const dir = requireModFolder(mod);
      if (!fs.existsSync(path.join(dir, 'test'))) return text('This mod has no test/ folder.');
      const r = await run(process.execPath, ['--test'], { cwd: dir, timeoutMs: 5 * MIN });
      return text(r.out + '\n\n[exit code ' + r.code + ']', r.code !== 0);
    },
  },
  {
    name: 'build_mod',
    title: 'Build a mod',
    description: 'Compiles (UI sources need CSDK) and packs the mod into dist/pakNN_dir.vpk, then lists what it contains. Does not install: use install_mod for that.',
    inputSchema: S({ mod: MOD }, ['mod']),
    annotations: { destructiveHint: false },
    handler: ({ mod }) => runTool('build.ps1', ['-Mod', requireModFolder(mod)], { timeoutMs: 20 * MIN }),
  },
  {
    name: 'install_mod',
    title: 'Build and install a mod',
    description: 'Builds the mod and copies it into Deadlock\'s addons folder. Only after the user asked to install or test. Deadlock must be closed, and mod loading on (mount_addons). The user restarts Deadlock to see it. force: replace a pak another mod owns.',
    inputSchema: S({ mod: MOD, force: { type: 'boolean' } }, ['mod']),
    annotations: { destructiveHint: false },
    handler: ({ mod, force }) => runTool('build.ps1', ['-Mod', requireModFolder(mod), '-Install', ...(force ? ['-Force'] : [])], { timeoutMs: 20 * MIN }),
  },
  {
    name: 'uninstall_mod',
    title: 'Remove an installed mod',
    description: 'Deletes the mod\'s pak from Deadlock (enabled or disabled). Its source folder is kept. Remove everything that was installed only for a test, once the user has checked it. mod: the mod name, or a pak number/file name from list_mods.',
    inputSchema: S({ mod: { type: 'string' } }, ['mod']),
    annotations: { destructiveHint: true },
    handler: ({ mod }) => runTool('mods.ps1', ['remove', mod, '-Yes']),
  },
  {
    name: 'disable_mod',
    title: 'Turn an installed mod off or on',
    description: 'disable: moves the pak to addons_disabled (it stops loading; nothing is deleted). enable: moves it back. mod: name, pak number or file name.',
    inputSchema: S({ mod: { type: 'string' }, enable: { type: 'boolean', description: 'true to turn it back on' } }, ['mod']),
    annotations: { destructiveHint: false, idempotentHint: true },
    handler: ({ mod, enable }) => runTool('mods.ps1', [enable ? 'enable' : 'disable', mod]),
  },
  {
    name: 'list_mods',
    title: 'Installed mods and conflicts',
    description: 'list: every installed pak (enabled or disabled), which mod made it, what it changes, what shadows it. conflicts: files several mods replace, and which one wins (lower pak number). files: the files of one mod (needs mod).',
    inputSchema: S({ action: { type: 'string', enum: ['list', 'conflicts', 'files'] }, mod: { type: 'string' } }),
    annotations: RO,
    handler: ({ action = 'list', mod }) => runTool('mods.ps1', [action, ...(mod ? [mod] : [])]),
  },
  {
    name: 'reset_all',
    title: 'Undo everything',
    description: 'Removes every mod these tools installed and turns mod loading off, restoring Valve\'s gameinfo.gi lines. Mods from other sources are left alone. Only when the user asks to undo everything or their game is broken. Deadlock must be closed.',
    inputSchema: S({ confirm: { type: 'boolean', const: true, description: 'Must be true: the user asked for this.' } }, ['confirm']),
    annotations: { destructiveHint: true },
    handler: ({ confirm }) => confirm === true ? runTool('mods.ps1', ['reset', '-Yes']) : text('confirm must be true.', true),
  },
  {
    name: 'read_console_log',
    title: 'Read the game\'s log',
    description: 'Reads Deadlock\'s console.log (needs the -condebug launch option; doctor checks). Default: lines from mods ("[name] ..." from $.Msg), JS exceptions, layout/load errors. mod: only that mod\'s lines and errors. pattern: your own case-insensitive regex. Says when the log was written, so you know if it is from the user\'s last launch.',
    inputSchema: S({ mod: { type: 'string' }, pattern: { type: 'string' }, tail: { type: 'integer', minimum: 1, maximum: 2000 } }),
    annotations: RO,
    async handler({ mod, pattern, tail = 200 }) {
      const ctx = await gameContext();
      const file = path.join(ctx.root, 'game', 'citadel', 'console.log');
      if (!fs.existsSync(file)) return text('No console.log at ' + file + '. Ask the user to add -condebug to Deadlock\'s launch options (Steam > Deadlock > Properties), start the game once, and close it.', true);
      // Mod lines look like "[PanoramaScript] [mymod] ...": a lowercase tag right after an engine channel.
      const errors = /JS Exception|Uncaught|Unable to (load|find)|Failed to (load|parse)|failed to compile/i;
      const tag = mod ? new RegExp('\\[' + mod.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\]') : /\] \[[a-z][a-z0-9_]{1,30}\] /;
      let keep;
      try { const re = pattern && new RegExp(pattern, 'i'); keep = re ? (l) => re.test(l) : (l) => tag.test(l) || errors.test(l); } catch (e) { return text('Bad regex: ' + e.message, true); }
      const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(keep);
      const st = fs.statSync(file);
      return text('console.log, last written ' + st.mtime.toISOString() + ' (now ' + new Date().toISOString() + '). ' + lines.length + ' matching line(s)' + (lines.length > tail ? ', last ' + tail + ' shown' : '') + ':\n' + lines.slice(-tail).join('\n'));
    },
  },
  {
    name: 'rebase_mod',
    title: 'Update a mod after a patch',
    description: 'After a Deadlock patch: fetches the new original files the mod overrides and merges the mod\'s changes onto them. Then build, install and have the user re-test. Also re-run catalog_refresh and mount_addons enable (patches usually reset it).',
    inputSchema: S({ mod: MOD }, ['mod']),
    annotations: { destructiveHint: false },
    handler: ({ mod }) => runTool('rebase.ps1', ['-Mod', requireModFolder(mod)], { timeoutMs: 10 * MIN }),
  },
  {
    name: 'export_mod',
    title: 'Package a mod for GameBanana',
    description: 'Builds, checks the pak for files that break shipping mods, and writes export/<name>-<version>-b<build>.zip (pak, README.txt, LICENSE.txt) plus <name>-gamebanana.md, the upload checklist. Before exporting, put the user\'s own one-sentence description and name in mod.json ("description", "author"): GameBanana bans AI-written descriptions. The user uploads it themselves.',
    inputSchema: S({ mod: MOD }, ['mod']),
    annotations: { destructiveHint: false },
    handler: ({ mod }) => runTool('export.ps1', ['-Mod', requireModFolder(mod)], { timeoutMs: 20 * MIN }),
  },
  {
    name: 'storage',
    title: 'Storage page of a mod that saves data',
    description: 'For mods made with kind "data". No publish: status (the address the mod saves through, whether it is the kit\'s page or the maker\'s own, whether it answers, GitHub sign-in). publish: self-hosting; puts the kit\'s storage page on the user\'s GitHub (free, https://<user>.github.io/<mod>-store/ or the repo already in the mod\'s address) and writes that address into the mod; rebuild afterwards. Exit 2 = the user must sign in once: they type "! gh auth login" in Claude Code (or run gh auth login in a terminal). Saved data stays with the address it was saved under, so publish refuses to switch a mod to a different address (including off the kit\'s page).',
    inputSchema: S({ mod: MOD, publish: { type: 'boolean' } }, ['mod']),
    annotations: { openWorldHint: true },
    handler: ({ mod, publish }) => runTool('store.ps1', ['-Mod', requireModFolder(mod), ...(publish ? ['-Publish'] : [])],
      { timeoutMs: 15 * MIN, exitNotes: { 2: 'waiting for the user (see above)' } }),
  },
  {
    name: 'vpk_list',
    title: 'List the files in a pak',
    description: 'Lists the files inside a .vpk (a mod\'s dist/pakNN_dir.vpk, or one the user has).',
    inputSchema: S({ path: { type: 'string' }, filter: { type: 'string', description: 'Path prefix.' } }, ['path']),
    annotations: RO,
    handler: ({ path: p, filter }) => runTool('vpk-list.ps1', ['-Path', path.resolve(REPO, p), ...(filter ? ['-Filter', filter] : [])]),
  },
];

// Minimal JSON-schema check: required fields, types, enums, patterns, ranges. Returns an error or null.
function validate(schema, args) {
  if (args === null || typeof args !== 'object' || Array.isArray(args)) return 'arguments must be an object';
  for (const r of schema.required || []) if (args[r] === undefined) return 'missing "' + r + '"';
  for (const [k, v] of Object.entries(args)) {
    const p = schema.properties[k];
    if (!p) return 'unknown argument "' + k + '" (allowed: ' + Object.keys(schema.properties).join(', ') + ')';
    const type = Array.isArray(v) ? 'array' : Number.isInteger(v) ? 'integer' : typeof v;
    if (p.type === 'integer' ? type !== 'integer' : p.type === 'array' ? type !== 'array' : typeof v !== p.type) return '"' + k + '" must be ' + p.type;
    if (p.enum && !p.enum.includes(v)) return '"' + k + '" must be one of ' + p.enum.join(', ');
    if (p.const !== undefined && v !== p.const) return '"' + k + '" must be ' + JSON.stringify(p.const);
    if (p.pattern && !new RegExp(p.pattern).test(v)) return '"' + k + '" must match ' + p.pattern;
    if (p.minimum !== undefined && v < p.minimum) return '"' + k + '" must be >= ' + p.minimum;
    if (p.maximum !== undefined && v > p.maximum) return '"' + k + '" must be <= ' + p.maximum;
    if (p.type === 'array' && p.items && p.items.enum) for (const i of v) if (!p.items.enum.includes(i)) return '"' + k + '" items must be one of ' + p.items.enum.join(', ');
  }
  return null;
}

async function callTool(name, args = {}) {
  const t = tools.find((x) => x.name === name);
  if (!t) return text('Unknown tool: ' + name, true);
  const err = validate(t.inputSchema, args);
  if (err) return text('Invalid arguments for ' + name + ': ' + err, true);
  try { return await t.handler(args); } catch (e) { return text(e.message, true); }
}

module.exports = { tools, callTool, validate, resolveMod, REPO };
