# 8. Policy and safety

## Valve's position

- **No published Deadlock mod policy.** Valve's changelogs never mention player mods, and no Valve staff statement permits or forbids them. Deadlock is still "coming soon / TBA" on Steam.
- **What Valve enforces technically:**
  - The PGI matchmaking guard on seven gameinfo.gi sections ([01](01-how-mods-load.md#the-matchmaking-guard-pgi-what-you-must-never-edit)). It deliberately leaves `FileSystem` alone.
  - `gameinfo_cannot_override` convars.
  - Tools mode blocks matchmaking.
  - Gameplay is server-authoritative: data and gameplay mods don't work in Valve matches.
- **Steam Subscriber Agreement** (updated 2026-09-10): personal non-commercial license; no modifications or derivative works "without Valve's prior written consent"; no cheats or unauthorized third-party software. Formally, mods are a tolerated grey zone, as in most Valve games.
- **Bans:** there are no confirmed bans for client-side cosmetic or UI mods (2026). The community splits on *information* mods (timers, rank lookups). Some guides class those as advantage mods, and GameBanana hosts several.

## Rules of thumb for a safe mod

1. **Show nothing the game hides.** Use the "could a player without the mod know this?" test (also GameBanana R-DL.824).
2. **Touch only `FileSystem → SearchPaths`** (and optionally `ConVars`) in gameinfo.gi.
3. **No memory reading, DLL injection, packet capture, input automation or overlay injection.** Companion apps should use only:
   - documented files (`console.log` via `-condebug`, Steam's own caches)
   - public web APIs (deadlock-api.com, Steam Web API)
   - a localhost server that the mod talks to through normal Panorama features ([04](04-persistence-and-io.md))
4. **Never log into Valve's game coordinator with the user's Steam session** from a third-party app.
5. **Never sell the mod.** Donations are fine on GameBanana. Paid mods drew community backlash and are against GameBanana's paywall rule.
6. **Keep personal data local.** Notes about identifiable players are personal data: no public lists, no sharing features that target people. Document exactly what leaves the machine.
7. Close CSDK and any `-tools` instance before queueing.

## When this changes

This page may no longer hold if Valve:

- announces official mod or Workshop support
- adds `FileSystem` to the PGI section list (watch `Citadel_StartMatchmaking_UnverifiedPGI` in GameTracking)
- removes the Panorama features bridges rely on (remote `Image` URLs, the `HTML` panel), the way `$.AsyncWebRequest` was removed
