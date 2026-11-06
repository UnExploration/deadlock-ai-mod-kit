# 12. UI hooks: what C++ feeds the player surfaces

Where players appear in Deadlock's UI, what the C++ panel feeds each layout, how to read it, and where to hook your script. Paths are relative to `panorama/layout/` (decompiled `.xml` in GameTracking; compiled `.vxml_c` in the VPK). After a patch, check them against the new build ([after a patch](../cookbook/after-a-patch.md)).

**Panel IDs are not listed here.** Every layout's root panel, panel IDs, scripts and styles for the user's build are in [`../generated/ui-layouts.md`](../generated/ui-layouts.md), and `catalog_search` with table `ui` searches them. This page covers what that listing can't show: which dialog variables C++ sets, and which panels C++ fills at runtime.

Notation: `{s:x}` string, `{d:x}` integer, `{i:x}` int, `{g:fmt:x}` formatted, `{t:…}` time. These are **dialog variables** set by C++ on the panel (children inherit them). JS can *set* them but has no getter. To read one:
- **Proven:** override the layout to add a hidden `<Label text="{i:r:x}"/>` and read its `.text`.
- **Untested:** `$.Localize('{d:x}', panel)`.

See [03-panorama.md](03-panorama.md#reading-player-identity).

## In a match: ESC menu → Players tab

`hud_escape_menu.xml` (C++ class `CitadelHudEscapeMenu`) has a Friends tab and a Players tab. The Players tab holds a **`<CitadelPlayersList>`**, which C++ fills.

| Layout | C++ class | Fed by C++ | Notes |
|---|---|---|---|
| `players_list.xml` | `CitadelPlayersList` | snippets `Team` (`{s:team_relationship}`, `{s:team_name}`) and `LocalTeamControls` | C++ (`CCitadel_UI_PlayersList::UpdateDirtyPanel`) builds one Team per side and fills it with entries |
| `players_list_entry.xml` | **`CitadelPlayersListEntry`** (one per player) | `{s:player_name}`; a `CitadelHeroBadge`; mute buttons call `CitadelPlayerListEntrySetMuted( true/false )` | The row's `#MainContents` has `hittestchildren="false"`, so controls inside it take no clicks. It is unknown whether an `account_id` dialog variable is set here (runtime test) |

Clicking an entry opens the **player context menu**:

| Layout | C++ class | Fed by C++ | Notes |
|---|---|---|---|
| `citadel_ui_context_menu_player.xml` | **`CitadelContextMenuPlayer`** | a `CitadelProfileCard`, then the menu options | C++ instantiates snippets: `AddFriend`, `ViewProfile`, `Report`, `Commend`, `AudioVolume` (Slider), `InviteToParty`, `SpectateGame`, … Also used for friends and party members |
| `profile_card.xml` | **`CitadelProfileCard`** | **`{d:account_id}`** (shown by the card's `#AccountID` label as `"Account ID: {d:account_id}"`), `CitadelAvatarImage` (its own layout `avatar_image.xml` loads inside the card), `CitadelUserName` (name and nickname), `CitadelHeroImage`, `{g:citadel_hero_name:HeroName}` | `#AccountID` is `visibility: collapse` unless an ancestor has class `ShowAccountID`. Presumably that class is toggled by the convar `citadel_show_account_ids` ("When set, account IDs will be shown on player tooltips"); unverified. Mods read the ID with a hidden `{i:r:account_id}` label (proven) |

## In a match: HUD top bar (always visible)

| Layout | C++ class | Fed by C++ |
|---|---|---|
| `citadel_hud_top_bar.xml` | `CitadelHudTopBar` | teams of `CitadelHudTopBarPlayer` |
| `citadel_hud_top_bar_player.xml` | `CitadelHudTopBarPlayer` | `{s:player_name}`, `{s:hero_name}`, `{i:kills}`, `{i:deaths}`, `{i:assists}`, `{d:hero_level}`, `{d:respawn_time}`, `{s:gold}`, `{i:player_level}`, `{i:objective_damage}`; hover → `CitadelTopDownScoreboardPlayerHovered()` |
| `citadel_hud_top_bar_player_details.xml` | details tooltip | `{s:stat_max_health}`, `{s:stat_bullet_resist}`, `{s:stat_tech_resist}` |
| `team_status_player.xml` | `Label` | `{s:name}` |

## After a match

| Layout | Notes |
|---|---|
| `post_game/citadel_db_post_game_scoreboard_new.xml` | Per-player rows: `{g:citadel_hero_name:hero_id}`, K/D/A, `net_worth`, `player_dmg`, `obj_dmg`, `player_healing`; `CommendPlayerButton` |
| `post_game/citadel_db_post_game_player_context_menu.xml` | Right-click menu on post-game rows |
| `post_game/*.xml` scripts (`.vts`) | C++ hands JSON to JS (e.g. `GetTestingProgressDataJSON` shape: `all_players[].account_id`, `hero_id`, `team`, `player_slot`). This is Valve's own example of account IDs reaching JS |

## Identity panels you can create yourself

- **`<CitadelUserName accountid="…"/>`** renders an account's **current** persona name. Valve uses `accountid="local"` (`citadel_db_page_ranked_season.xml`). Setting a numeric account ID is the expected generalization (runtime test).
- `<CitadelAvatarImage/>` shows a Steam avatar. It's set by C++ in profile cards, chat and friends. Its JS/XML account property name is unverified.

## Global hook points (load your script everywhere)

Override a **small, rarely changed root layout** and add one `<scripts>` include. The script then finds and decorates vanilla panels at runtime.

| Layout | Present | Precedent |
|---|---|---|
| `citadel_hud_and_db_overlay.xml` (`CitadelOverlay`) | HUD **and** dashboard | Threat HUD adds `<include src="s2r://panorama/scripts/threathud_match_context_reporter.vjs_c"/>`; the kit's UI starter hooks here and shows in-game |
| `base_hud.xml` | in-match HUD | Threat HUD |
| `hud_escape_menu.xml` | ESC menu | SteamNotes, HP Colors, QOL Lock (contested) |

The most-overridden files in the ecosystem (avoid if you can): `citadel_hud_top_bar`, `hud_escape_menu`, `players_list_entry`, `profile_card`, `post_game/citadel_db_post_game_scoreboard_new` (QOL Lock, SteamNotes, Deadlock Ranks, HP Colors). The longer list of crowded Panorama files is in [ui.md § 3](../cookbook/ui.md#pick-the-cheapest-safe-strategy).

## Useful panel events (C++ handlers; call from layouts or `$.DispatchEvent`)

From layouts and `client.dll` strings. Arguments are shown as used by Valve.

| Event | Use |
|---|---|
| `CitadelConCommand( 'cmd' )` | Run a console command (stock ESC menu: `'unstick'`; mods use `spec_target`, `closecaption`, …). No return value; `developmentonly`/`cheat` commands are refused |
| `CopyStringToClipboard( text, #token )` | Put text on the clipboard |
| `ViewSteamProfile`, `AddSteamFriend`, `IgnoreSteamUser`, `SteamChatWithFriend` | Steam actions |
| `CitadelSpectateAccountID`, `CitadelPartyInviteFriendAccountID`, `CitadelPartyKickAccountID` | Take account IDs |
| `UIShowTextTooltip( #token )` / `UIHideTextTooltip()` (also `CitadelUIShowTextTooltip( '#token' )`) | Tooltips |
| `CitadelResumePlaying()` | Close the ESC menu |
| `PlayUISoundEvent` | UI sound |

`panorama_dispatch_event "<event string>"` can fire these from the console, but it's `developmentonly`: it works only in `-dev`/tools sessions, never in retail play.
