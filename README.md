# QuestMates

WoW addon for **WoW Forever** (client 1.60.1, build 70790, `Interface: 16001`).
Lists the quests in your quest log; select one and broadcast "looking for
mates" — nearby players who also run QuestMates and have the same quest
answer, and you can invite them to a group with one click. Players **without**
the addon can be mass-invited from your surroundings, and a radar shows who is
around you.

## Features

- Quest log window: click a quest to select it, scrollable list, completed
  quests marked
- **Find mates**: broadcast `QG_LFM` on the hidden `QuestGroupSync` channel;
  peers with the same quest (matched by name + level + questID, same zone)
  whisper back `QG_HAVE`; they appear in the responders panel with an
  **Invite** button and a status (in group / wrong zone / ready)
- **Invite nearby**: dedicated button invites players around you (nameplates,
  ≤ `nameplateMaxDistance`, same faction only), staggered, capped, with an
  on-screen counter of sent invites
- **Radar window**: green dots for nearby players, direction from map coords,
  distance rings, live count in the title
- **Minimap button** (custom `icon.tga`): click to show/hide the window, drag
  around the rim. The window starts closed at login — open it with `/qg` or the
  minimap button
- Options: auto-announce on zone change, auto-accept invites from responders
  (clicks Blizzard's popup button — taint-safe), auto nearby-invite after each
  LFM, invite counter, radar on/off — all saved in `SavedVariables`
- Anti-spam: min delay between broadcasts, responder expiry, per-sender rate
  limits; protocol traffic is hidden from chat windows
- FR/EN localization (`frFR` client supported)
- Name-based invite chain (`C_PartyInfo.InviteUnit("First Surname")`, with the
  full name resolved from the nameplate token), auto-detects taint-blocked
  methods, plus a `chat` fallback that prefills `/invite <name>` for you to
  confirm with Enter. `SendChatMessage("/invite ...")` is not a working path:
  it sends literal chat text, not a slash command.

## Install

Copy the `QuestMates/` folder into `<WoW>\Interface\Addons\`, then
`/console reloadui`. Enable *Interface > Help > Display Lua errors* while
testing. In-game: `/qg` opens the window.

## Usage / slash commands

- `/qg` — toggle the window · `/qg lfm` — broadcast · `/qg show|hide`
- Diagnostics: `/qg probe` (API dump) · `/qg selftest` (in-game self-test,
  no second account needed) · `/qg scan` (nameplate/nearby diagnostic) ·
  `/qg debug` (wire + click trace) · `/qg eventtest` + `/say` (event style)
- Options: `/qg nearby on|off` · `/qg invitehow auto|slash|api|chat` ·
  `/qg invitetest <name>` · `/qg invitetry <name> token|slash|target|chat` ·
  `/qg radar` · `/qg delay <s>` · `/qg expire <s>` · `/qg quests`

## Testing

- **Headless** (no game needed): `sh tests/run.sh` — 95 checks with a stubbed
  WoW API (needs `lua5.1` / `luajit` / `lua`).
- **In-game, no second account**: `/qg selftest` prints PASS/FAIL lines;
  inject fake protocol messages with
  `/script QuestMates_HandleMessage("QG_HAVE^<zone>^^<quest>^^","Dummy","WHISPER")`.
- **With a peer**: second client on the same account (if the server allows
  dual login) or any player with the addon — same zone, select a shared quest
  on A, click **Chercher des partenaires**, B gets the whisper, B shows in A's
  panel, click **Inviter**.

## Development

- No Ace, no dependencies; `QuestMates.lua` (core) + `QuestMates_UI.lua` (UI),
  plain `CreateFrame` widgets, Lua 5.0/5.1-safe syntax, dual old/modern event
  dispatch, every API capability-detected with fallbacks.
- See **CONTEXT.md** for the full handoff: client facts, protocol spec, quirks,
  open questions.

## License

MIT — see `LICENSE`.
