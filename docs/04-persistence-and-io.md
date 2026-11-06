# 4. Persistence and I/O: saving data and talking to the outside

**Deadlock Panorama has no storage and no network API.**
- `$.persistentStorage` and `localStorage` don't exist (`$.persistentStorage` is a Strata Source API, not Valve's).
- `$.AsyncWebRequest` logs `ERROR: AsyncWebRequest has been removed.`
- There's no `fetch`, no `GameInterfaceAPI`, and no way for JS to read a convar back.

Any mod that remembers something across restarts uses one of the side channels below.

**Default: pattern A.** Players install nothing beyond the mod, and neither does the maker: the kit hosts one shared storage page that any mod can use, or the maker hosts a copy of it at their own address. The data itself stays on the player's PC; the page only gives the game's hidden browser a storage origin, because Valve blocked local pages on 2026-10-01. Explain it that way when a user asks "why not just save a file?". Companion programs (B–D) work offline but make every player run an extra unsigned program.

## Pick a pattern

| | Pattern | Read back in-game | Survives restart | Needs | Status |
|---|---|---|---|---|---|
| **A** | **Hidden HTML panel → a static HTTPS page (the kit's shared page, or your own copy) → page `localStorage`** | ✅ live | ✅ | Internet at game start; a static HTTPS host | **Proven**: 5 shipping mods confirmed after the 2026-10-01 change. **Default choice** |
| B | Same page, which `fetch`es a **localhost companion** (`http://127.0.0.1:PORT`) | ✅ live | ✅ (real files) | A + a running companion | Shipping design (modlock); in-game confirmation pending |
| C | `Image.SetImage('http://127.0.0.1:PORT/…?data')`; companion replies with a PNG whose **width/height encode 2 bytes** | ✅ live, slow | ✅ (companion) | Running companion; **no internet** | Worked to Sept 2026 (Threat HUD); not re-verified after the 2026-10-01 change |
| D | `$.Msg(...)` → `console.log` (launch option `-condebug`) → companion tails the file | ❌ write-only | companion's files | `-condebug`, companion | Proven write path |
| E | Data **baked into the VPK** (generated JS) | ✅ read-only | ✅ | Rebuild per change | Proven (SteamNotes "personalized file") |
| F | **Export/import codes**: `CopyStringToClipboard` → user pastes into a `TextEntry` | ✅ manual | user keeps the code | Nothing | Always works. **Ship it as a backup with any pattern** |
| G | Localization file `resource/local_english.txt` (the client tries to load it; not shipped) + `$.Localize('#token')` | ✅ read-only | ✅ | Companion or manual edit + restart | **Unverified** |

Dead ends (don't try them): `file://`, `data:` and `javascript:` HTML-panel URLs (blocked since 2026-10-01), `panorama_dispatch_event` from cfg (developmentonly), convars and `setinfo` (write-only, and `setinfo` leaks to servers), `GameInterfaceAPI` (CS2-only).

## Pattern A in detail: the HTTPS bridge page

```
mod JS                                                   the storage page (Steam's Chromium, https origin)
panel.SetURL(PAGE + '#' + encodeURIComponent(JSON)) ──►  'hashchange' → read/write localStorage
$.RegisterEventHandler('HTMLTitle', panel, fn)      ◄──  document.title = PREFIX + JSON reply
```

- **Panel:** `$.CreatePanel('CitadelHTMLPanel', parent, id)` (Deadlock's class) or the generic `HTML`. It's a real Chromium (Steam CEF). Its only JS methods are `SetURL(url)` and `SetIgnoreCursor(bool)`. Keep it tiny (`2px`, `opacity: 0.01`, `hittest=false`). Whether a `collapse`d panel still loads is unverified, so don't rely on it.
- **Events** must be registered with `$.RegisterEventHandler(name, panel, fn)`; `SetPanelEvent` won't deliver them.
  - `HTMLTitle(panel, title)` is the data channel. It fires about **twice per navigation**, so dedupe by request ID.
  - `HTMLURLChanged(panel, url)` lets you detect `about:blank` rejections.
  - `HTMLFinishRequest(panel, url, title)` fires when a request finishes.
  - Registering `HTMLContentLoaded` **throws** during menu boot.
- **URL rule (since 2026-10-01, build 6728):** only `https://` loads; everything else becomes `about:blank`. The page must be **remotely hosted** (GitHub Pages works). There's no URL scheme for a page inside your VPK.
- **Only the first `SetURL` loads the page.** Later calls change only the `#fragment`: no reload, and **the fragment is never sent to the server**. The host sees one ordinary GET (IP, user agent).
- **Limits:**
  - Replies are capped at **4096 chars** of title and silently truncated, so budget for that.
  - Requests are proven to about 30 KB of URL. Keep writes ≤ ~3000 chars and chunk anything bigger.
  - About 4 messages per second is lossless.
  - `localStorage` is about 5 MB per origin.
- **Where the data lives:** in the `localStorage` of the page's **origin**, inside Steam's browser profile. That's most likely `%LOCALAPPDATA%\Steam\htmlcache\Default\Local Storage\leveldb`: the folder exists, and this is the standard Chromium layout, but no origin has been confirmed there. It survives game and PC restarts (proven by mod authors). It's probably shared by every Steam account on the PC (namespace by local account ID if that matters) and probably wiped by Steam's "Delete Web Browser Data".
- **The page's domain is the locker.** The browser files saved data under the domain the page is served from. Every page on the same domain opens the same locker; a page on another domain finds it empty. So a mod's address is chosen once, when the mod is made, and never changes: move it and every player's data stays behind in the old locker. The kit has no migration; export/import codes (F) are the only way a player can keep a copy.
- **Failure modes:** no internet at launch means no storage that session, so show "offline: session only" and never overwrite data you couldn't read. The host can disappear. Valve could add a host allowlist next.

### Trust and privacy rules for your page

The page's JavaScript can read everything stored under its origin, and whoever controls the host can change that JS at any time (GitHub Pages caches about 10 minutes).
- **A shared page is a shared locker.** Every mod that uses the kit's page stores into the same `localStorage`. The page keeps them apart by namespace (a mod can only touch keys under its own `<name>.v1/`), but whoever runs the page can read every mod's data, so the kit's page is a trust decision the user makes when choosing the address. A mod on its own address has its own locker, run by its maker.
- **Put data only in the `#fragment`, never the query string.** The query string reaches the server; one shipping notes mod sends note text there.
- No third-party scripts and no outbound requests. Add a CSP: `default-src 'none'; script-src 'unsafe-inline'`.
- Version the protocol, validate keys against a regex, size-limit values, and publish the page source next to the mod.
- Tell users in the README what's stored, where, and that the page load reveals their IP to the host.

### Ready-made implementation

**Use `new-mod.ps1 -Kind data -StoreUrl <kit or https address>`.** The [saved-data guide](../cookbook/saved-data.md) is the walkthrough. The parts:

- [`../store/index.html`](../store/index.html) is the one storage page every mod uses: the kit hosts it at `https://unexploration.github.io/deadlock-mod-storage/` (the repo [deadlock-mod-storage](https://github.com/UnExploration/deadlock-mod-storage) carries a copy of this file), and a maker who wants their own address serves a copy of the same file. Each request names the mod's namespace (`ns`, e.g. `notepad.v1`); the page checks it against a strict pattern, refuses anything else (`bad_ns`), and only lets the request touch keys under `<ns>/`. Ops: `hello` (echoes the protocol and the `ns`), `get`, `set`, `del`, `list`. It has size limits, a strict CSP, a fragment-only protocol, and no network access. Opened in a normal browser it explains itself.
- [`../templates/kv-bridge/kvbridge.js`](../templates/kv-bridge/kvbridge.js) is the Panorama client: `new KVBridge({ page, ns, prefix: 'KV1:', protocol: 2 })`. It sends `ns` with every request and only trusts a page whose `hello` answers with the same address, protocol and `ns`. It has a serial request queue, hello handshake with retry, per-request timeout, dedupe, and an offline state. `new-mod.ps1` copies it into the mod.

**Ask once, then never move.** The address is the user's choice, asked once before the mod is made: the kit's page, with its warning, or their own. The kit's storage page is run by the kit's author, free, with no guarantee it stays online. If it goes away, mods that use it stop saving until their maker hosts the page at an address of their own, and data players saved under the old address does not carry over. `new-mod.ps1` refuses `-Kind data` without `-StoreUrl`, and writes the address into `src/panorama/scripts/<name>_store.js` and `mod.json` (`store.url`).

**Hosting your own:** `store.ps1 -Mod <mod> -Publish` puts the kit's page on the maker's GitHub (`https://<user>.github.io/<mod>-store/`) and writes that address into the mod; it refuses to move a mod that already has a different address unless `-Force`. Without the kit's tools: the storage repo is a GitHub template; its README walks through **Use this template**, then Settings > Pages, in about two minutes. By hand: create a GitHub repo, put the kit's `store/index.html` at its root as `index.html`, enable Pages, and use the resulting `https://<user>.github.io/<repo>/` URL, with a trailing slash. Any static `https://` host works the same way.

## Pattern B: a companion behind the bridge page (real files on disk)

The page tries `fetch('http://127.0.0.1:<port>/…')` and falls back to `localStorage` when no companion answers.
- The page's CSP must allow it: `connect-src http://127.0.0.1:*`.
- The companion must answer CORS preflights with `Access-Control-Allow-Origin: <page origin>` **and** `Access-Control-Allow-Private-Network: true` (Chromium Private Network Access).
- Bind to `127.0.0.1` only, and reject requests whose `Origin` isn't your page.

Reference: `paralin/modlock` (`session/screens.go`, relay page `bridge.html`).

## Pattern C: localhost image transport (no internet)

Reference: `antonborndev/deadlock-threat-hud`. Read `threathud_local_host_client.js` and `PngDimensionTransport.cs`.
- JS creates `Image` panels (opacity 0.01) and calls `SetImage('http://127.0.0.1:28741/…?<request>')`, then polls until loaded.
- It decodes `Math.round(panel.contentwidth / panel.actualuiscale_x) - 16` (and the same for height) as 2 bytes.
- Payloads are chunked with a small header (magic, version, length, CRC-16).
- For display-only data, simply serve a rendered PNG (e.g. the note text as an image) and show it. There's nothing to decode.

## Pattern D: console log (write-only, offline)

Launch Deadlock with `-condebug`. The game then writes `game\citadel\console.log`, **truncated on every launch**. `$.Msg('MYMOD|' + payload)` appears there as `[PanoramaScript] MYMOD|…`, and a companion tails the file. The same log carries `Lobby <lobby> for Match <match_id> created/destroyed`, which a companion can use to tie events to a match.

## Getting data from outside the game (companion apps)

Useful for companion features. All of these are read-only and ToS-safe:
- **deadlock-api.com** (community, unofficial). Get the `match_id` from `console.log`, then:
  - `GET /v1/matches/{match_id}/live/url` (rate-limited, a few per hour)
  - stream `GET /v1/matches/demo/live/query` with `SELECT tick,"m_steamID","m_iszPlayerName","m_iTeamNum","m_PlayerDataGlobal__m_nHeroID" FROM CCitadelPlayerController` to get all 12 SteamID64s, names and heroes in-match. Deadlock Mod Manager v2 ships this.
- **Steam Web API** `ISteamUser/GetPlayerSummaries` turns IDs into current names and avatars (100 IDs per call; needs a key).
- **Steam's HTTP cache** (`Steam\appcache\httpcache`) holds match metadata (`*.meta.bz2`, a protobuf with 12 account IDs), but only for matches the client fetched details of.
- Not available: Game State Integration (Deadlock has none), and other players' SteamIDs via `status`.
- **Never** read game memory, inject DLLs, or log into Valve's game coordinator with the user's session ([08](08-policy-and-safety.md)).
