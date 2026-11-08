# QuestMates — context handoff for another LLM

Read this first. It contains everything needed to continue working on this
addon without re-discovering it: target client, architecture, protocol,
quirks, tests, and open questions.

## What this is
A World of Warcraft addon for the private-server-style client **"WoW Forever"**:
lists the player's quest log, lets them select a quest and broadcast
"looking for mates"; peers running the addon answer; nearby players without
the addon can be mass-invited; a radar shows nearby players; a minimap button
toggles the window.

## Target client (verified in-game via `/qg probe`)
- Client **1.60.1, build 70790, interface 16001** → `.toc` uses `## Interface: 16001`.
- **Lua 5.1**. Locale **frFR** (UI is FR/EN via `GetLocale()`).
- **Mixed API surface**: old globals exist (`GetRealZoneText`, `JoinChannelByName`,
  `ChatFrame_AddMessageEventFilter`, `ChatFrame_RemoveChannel`, `GetChannelName`,
  `AcceptGroup`, `TargetUnit`) but `SendAddonMessage`, `RegisterAddonMessagePrefix`,
  `InviteByName`, `GetQuestLogTitle`, `GetPlayerMapPosition` are **nil**; modern
  namespaces exist: `C_ChatInfo.SendAddonMessage/RegisterAddonMessagePrefix`,
  `C_QuestLog.GetNumQuestLogEntries/GetInfo/IsComplete/IsQuestFlaggedCompleted`,
  `C_Map.*`, `C_PartyInfo.InviteUnit`, `C_NamePlate.GetNamePlates`, `ChatFrameUtil`.
- Quest log entries (`C_QuestLog.GetInfo`) expose `title`, `level`, `questID`,
  `isHeader`, ... but **no `isComplete` field** → completion via
  `C_QuestLog.IsComplete(questID)` / `IsQuestFlaggedCompleted(questID)`.
- `nameplateMaxDistance = 45`. `nameplateShowFriends` **cvar does not exist** on
  this client: the friendly-nameplate toggle is **`nameplateShowFriendlyPlayers`**
  (fallback `nameplateShowAll`); there is also a keybind (Ctrl+V / Ctrl+Shift+V).
- `InviteByName` is **nil**; invites go through `C_PartyInfo.InviteUnit`, which
  takes a **player name, not a unit token**. Nameplate **frames** don't expose
  unit tokens (`namePlateUnitToken`/`unit` are nil) → enumerate `nameplate1..40`
  unit tokens directly (`UnitExists`/`UnitIsPlayer`/`UnitName`).
- **Names**: this client keeps first name and surname apart. `UnitName(token)`
  returns only the first name; `UnitFullName(token)` returns `first, surname`.
  The invitable/displayed name is `"First Surname"`, so the addon resolves it
  with `QM_UnitFullName(token)` before calling `C_PartyInfo.InviteUnit(name)`.
- Hidden chat channel `QuestGroupSync` joins fine (`GetChannelName` → num=1).
- **Taint system active**: `SendChatMessage("/invite x")` does **not** execute a
  slash command (it sends literal chat text); it is no longer used. Direct
  `AcceptGroup()` is avoided (popup button is clicked instead). Invite order is
  `InviteByName` (if present) → `C_PartyInfo.InviteUnit(fullName)` → target (only
  if `TargetByName` exists) → `chat` prefill. Taint errors right after an invite
  mark that method as blocked for the session (`QM.blockedMethods`). A `chat`
  method prefills the chat box (`ChatFrame_OpenChat("/invite <fullName>")`, user
  presses Enter) as a guaranteed-working fallback.
- **Hidden frames don't get OnUpdate** on this client → the core event frame is
  kept visible at 1×1 px, alpha 0.

## Files
- `QuestMates/QuestMates.toc` — `Interface: 16001`, `SavedVariables: QuestMatesDB`,
  `IconTexture: Interface\AddOns\QuestMates\icon.tga`
- `QuestMates/QuestMates.lua` — core: compat shim (dual event style: old
  globals `event`/`arg1..arg9` vs modern varargs — one dispatcher handles both),
  capability detection (`X or C_Y.X`) everywhere, Lua 5.0/5.1-safe code
  (no `goto`/`select`/`ipairs`/`#`, `table.getn`, global string funcs),
  state, protocol, anti-spam, slash commands, selftest/probe/scan.
- `QuestMates/QuestMates_UI.lua` — window (movable, saved pos, border, drag
  forwarded from child frames), scrollable quest list (wheel + up/down buttons),
  responders panel (status + Invite), options checkboxes, invite counter,
  minimap button (icon + Q fallback, draggable around rim), radar window.
- `QuestMates/icon.tga` — 64×64 32-bit TGA minimap icon (hand-written header,
  bottom-left origin, 8 alpha bits).
- `tests/harness.lua` + `tests/run.sh` — headless WoW-API-stub test suite
  (**95 checks**, run `sh tests/run.sh`; needs lua5.1/luajit/lua).
- `README.md`, `CONTEXT.md`, `LICENSE`, `.gitignore`.

## Protocol (hidden channel `QuestGroupSync`, prefix `QG`)
`^`-separated, `^` stripped from names; fields: cmd, zone, level, questName,
questID, x, y (id/coords may be empty):
- `QG_LFM^zone^level^questName^questID^x^y` on the channel (SendAddonMessage
  "CHANNEL", fallback `SendChatMessage(msg,"CHANNEL",nil,name)`)
- `QG_HAVE^...` whispered back to the initiator (SendAddonMessage "WHISPER",
  fallback SendChatMessage "WHISPER")
Receiving LFM: answer only if zone matches and quest (name+level/id) is in our
log and not completed. Anti-spam: ≥15 s between broadcasts (pref `minDelay`),
responders expire after 60 s (`expire`), per-sender+per-cmd rate limit
(3 s LFM / 1 s HAVE). All protocol traffic is filtered from chat windows
(`ChatFrame_AddMessageEventFilter` or `ChatFrame_OnEvent` hook fallback).
Quest matching uses name+level+questID (same-name quests).

## Features / slash commands
Window `/qg` (toggle; also minimap button). Quest list click-select, scroll.
Buttons: **Chercher des partenaires** (LFM broadcast) and **Inviter les proches**
(nearby mass-invite). Options: auto-announce on zone change, auto-accept invites
from responders (popup-click), auto nearby-invite after LFM, invite counter,
radar on/off. Radar: players within nameplate range (≤`nameplateMaxDistance`),
dots by map-coord direction + `CheckInteractDistance` rings. Nearby invites:
nameplate tokens + target/mouseover, **same-faction only**, max 5/broadcast,
2 s stagger, no re-invite within 120 s, skipped when party full.
Slash: `/qg lfm|probe|selftest|scan|debug|nearby on|off|invitehow auto|slash|api|chat|
invitetest <n>|invitetry <n> <method>|radar|delay <s>|expire <s>|quests|eventtest`.
SavedVariables `QuestMatesDB`: pos, radarPos, minimapAngle, prefs{...}.

## Testing
- Headless: `sh tests/run.sh` → 95 checks (protocol, anti-spam, invite methods,
  taint-blocked marking, nearby queue/stagger/faction, radar, drag, minimap,
  selftest isolation...).
- In-game without a second account: `/qg selftest` (23 checks, injects fake
  protocol messages as "DummyPeer", never sends real invites), `/qg probe`
  (API dump), `/qg scan` (nameplate/cvar diagnostic), `/qg debug` (wire log),
  `/script QuestMates_HandleMessage("QG_HAVE^<zone>^^<quest>^^","Dummy","WHISPER")`.
- Real round trip: second client on same account if the server allows dual
  login, or any peer with the addon.

## Open questions / next steps
1. **Which invite method actually delivers on this client?** A debug log showed
   the old token path (`C_PartyInfo.InviteUnit("nameplate1")`) "succeeding"
   silently while nothing was sent. The code now resolves the full name and
   calls `C_PartyInfo.InviteUnit("First Surname")`. Verify with
   `/qg invitetry <friend> token|target|chat` with a friend watching for the
   popup. If the API still fails, `chat` (prefill + Enter) always works.
2. Two-account end-to-end LFM→HAVE→invite round trip still untested with a peer.
3. If the minimap icon ever shows a square again: the button must carry **no
   square background texture at all** (the round icon.tga is the button). Hover
   feedback is a round glow (ADD-blended copy of icon.tga, alpha 0→0.35) —
   don't re-add any square bg, not even a hover-only one.

## Conventions
- No Ace, no external deps, one addon folder, commented Lua, Lua 5.0/5.1-safe.
- Always `pcall` client API calls and capability-detect (`if X then ... else ...`).
- New UI widgets: plain `CreateFrame` + `Interface\Tooltips\UI-Tooltip-Background`
  + `Fonts\FRIZQT__.TTF` (no XML templates).
- Every event handler wrapped so one bad handler can't break others.
