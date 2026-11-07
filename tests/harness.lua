-- Headless test harness for QuestMates (WoW API stubs, Lua 5.1)
-- Run: lua5.1 /tmp/opencode/qmtest/harness.lua

-- WoW exposes string functions and time()/date() as globals
strfind = string.find
strsub  = string.sub
gsub    = string.gsub
strlower = string.lower
time = os.time
date = os.date

local sent, chatsent, filters, prefixes = {}, {}, {}, {}
local invited, accepted, joinedChannel, invitedUnit, targeted

local function mkfontstring(parent)
  local fs = { _text = "", _vis = true }
  return setmetatable(fs, { __index = {
    SetText = function(self, t) self._text = t end,
    GetText = function(self) return self._text end,
    SetPoint = function() end, SetWidth = function() end, SetFont = function() end,
    SetTextColor = function() end, SetJustifyH = function() end,
    Show = function(self) self._vis = true end,
    Hide = function(self) self._vis = false end,
  } })
end

local function mktexture()
  local t = { _vis = true }
  return setmetatable(t, { __index = {
    SetTexture = function() end, SetVertexColor = function() end,
    SetPoint = function() end, SetAllPoints = function() end,
    SetWidth = function(self, w) self._w = w end,
    SetHeight = function(self, h) self._h = h end,
    Show = function(self) self._vis = true end,
    Hide = function(self) self._vis = false end,
  } })
end

local function mkframe(name)
  local f = { name = name, scripts = {}, _w = 0, _h = 0, _x = 100, _y = 500, _vis = false }
  return setmetatable(f, { __index = {
    SetScript = function(self, n, fn) self.scripts[n] = fn end,
    GetScript = function(self, n) return self.scripts[n] end,
    RegisterEvent = function(self, ev) self["reg_" .. ev] = true end,
    UnregisterAllEvents = function() end,
    Hide = function(self) self._vis = false end,
    Show = function(self) self._vis = true end,
    IsVisible = function(self) return self._vis end,
    SetWidth = function(self, w) self._w = w end,
    SetHeight = function(self, h) self._h = h end,
    GetWidth = function(self) return self._w end,
    GetHeight = function(self) return self._h end,
    SetPoint = function(self, ...) self._pt = {...} end,
    ClearAllPoints = function() end,
    GetLeft = function(self) return self._x end,
    GetTop = function(self) return self._y end,
    SetMovable = function() end, EnableMouse = function() end, EnableMouseWheel = function() end,
    RegisterForDrag = function() end,
    StartMoving = function(self) self._moving = true end,
    StopMovingOrSizing = function(self) self._moving = false end,
    RegisterForClicks = function() end,
    CreateFontString = function(self) return mkfontstring(self) end,
    CreateTexture = function(self) return mktexture() end,
    SetFontString = function() end,
    Disable = function(self) self._dis = true end,
    Enable = function(self) self._dis = false end,
  } })
end

UIParent = mkframe("UIParent")
UIParent._w, UIParent._h = 1024, 768
UIParent.GetScale = function() return 1 end
Minimap = mkframe("Minimap")
Minimap._w, Minimap._h = 140, 140
Minimap._x, Minimap._y = 100, 500
GetCursorPosition = function() return 500, 500 end
function CreateFrame(type, name, parent)
  local f = mkframe(name)
  f.type, f.parent = type, parent
  return f
end

DEFAULT_CHAT_FRAME = { msgs = {}, AddMessage = function(self, m) self.msgs[#self.msgs+1] = m; print("[chat] " .. tostring(m)) end }

local currentTarget
platesVisible = true
UnitName = function(u)
  if u == "player" then return "Tester" end
  if u == "target" then return currentTarget end
  if u == "nameplate1" or u == "plate1" then return "NearGuy" end
  if u == "nameplate2" or u == "plate2" then return "NearGal" end
  if u == "nameplate3" then return "HordeGuy" end
  return nil
end
UnitIsPlayer = function(u) return 1 end
UnitPlayerControlled = function(u) return 1 end
C_Map = {
  GetBestMapForUnit = function(u) return 12 end,
  GetPlayerMapPosition = function(map, u)
    if u == "player" then return { x = 0.50, y = 0.50 } end
    if u == "nameplate1" then return { x = 0.53, y = 0.52 } end
    if u == "nameplate2" then return { x = 0.40, y = 0.40 } end
    return { x = 0, y = 0 }
  end,
}
CheckInteractDistance = function(token, idx)
  if token == "nameplate1" and idx <= 3 then return 1 end
  return nil
end
UnitExists = function(t)
  if not platesVisible then return nil end
  if t == "nameplate1" or t == "nameplate2" or t == "nameplate3" then return 1 end
  return nil
end
UnitFactionGroup = function(t)
  if t == "nameplate3" then return "Horde" end
  return "Alliance"
end
C_NamePlate = { GetNamePlates = function()
  if not platesVisible then return {} end
  return { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = "nameplate2" }, { namePlateUnitToken = "nameplate3" } }
end }
ChatFrame_OpenChat = function(text) openedChat = text end
GetLocale = function() return "enUS" end
GetNumQuestLogEntries = function() return 3 end
-- index 3: same name as index 2 but different level, and marked complete
local QUESTS = { {"Defias Brotherhood", 11}, {"The Fargodeep Mine", 12}, {"The Fargodeep Mine", 13} }
function GetQuestLogTitle(i) local q = QUESTS[i]; return q[1], q[2], nil, false, false, (i == 3) end
GetRealZoneText = function() return "Elwynn Forest" end
SetMapToCurrentZone = function() end
GetPlayerMapPosition = function(u) return 0.52, 0.41 end
GetChannelName = function(name) if name == "QuestGroupSync" then return 7, name end return 0, nil end
JoinChannelByName = function(name) joinedChannel = name end
ChatFrame_RemoveChannel = function() end
function ChatFrame_AddMessageEventFilter(ev, fn) filters[ev] = fn end
function RegisterAddonMessagePrefix(p) prefixes[p] = true end
function SendAddonMessage(prefix, msg, dist, target) sent[#sent+1] = { prefix = prefix, msg = msg, dist = dist, target = target } end
function SendChatMessage(msg, typ, lang, target) chatsent[#chatsent+1] = { msg = msg, typ = typ, target = target } end
-- modern-style client: no InviteByName global, invite via C_PartyInfo.InviteUnit after targeting
C_PartyInfo = { InviteUnit = function(u) invitedUnit = u end }
TargetUnit = function(name) targeted = name; currentTarget = name; return true end
UnitGUID = function(u) return nil end
function AcceptGroup() accepted = true end
GetNumPartyMembers = function() return 0 end
SlashCmdList = {}
QuestMatesDB = nil

-- load the addon
-- Headless test harness for QuestMates (WoW API stubs, Lua 5.1).
-- Run from the repo root:  sh tests/run.sh     (or: lua5.1 tests/harness.lua [addonDir])
local ROOT = (arg and arg[1]) or "QuestMates"  -- addon folder, relative to the repo root
dofile(ROOT .. "/QuestMates.lua")
dofile(ROOT .. "/QuestMates_UI.lua")

local QM = QuestMates
local evf = QM.evf
local function fire(...) evf.scripts.OnEvent(evf, ...) end  -- modern varargs style
local pass, fail = 0, 0
local function check(cond, label)
  if cond then pass = pass + 1; print("PASS: " .. label)
  else fail = fail + 1; print("FAIL: " .. label) end
end

-- build UI directly (outside pcall) to surface any error
local ok, err = pcall(QuestMates_BuildUI)
check(ok, "QuestMates_BuildUI runs without error" .. (ok and "" or (": " .. tostring(err))))

-- 1. ADDON_LOADED (modern varargs dispatch)
fire("ADDON_LOADED", "QuestMates")
check(QM.UI and QM.UI.frame and QM.UI.frame._vis, "window created and visible")
check(prefixes["QG"], "addon prefix QG registered")
check(#QM.quests == 3, "quest log snapshot has 3 entries")
check(QM.quests[3].complete == true, "completed quest detected via 6th return value")

-- 2. PLAYER_LOGIN
fire("PLAYER_LOGIN")
check(joinedChannel == "QuestGroupSync", "hidden channel joined at login")
check(filters["CHAT_MSG_WHISPER"] ~= nil, "chat message filter registered")

-- 3. select + broadcast
QM_UI_Select(2)
check(QM.selected == 2, "quest 2 selected")
QM_BroadcastLFM()
check(#sent == 1 and sent[1].dist == "CHANNEL" and sent[1].target == "QuestGroupSync" and sent[1].prefix == "QG",
  "LFM broadcast on channel via SendAddonMessage")
check(strsub(sent[1].msg, 1, 6) == "QG_LFM", "LFM message starts with QG_LFM")
check(strfind(sent[1].msg, "The Fargodeep Mine", 1, true) ~= nil, "quest name in message")
check(strfind(sent[1].msg, "^12^", 1, true) ~= nil, "quest level in message")
check(strfind(sent[1].msg, "52.0^41.0", 1, true) ~= nil, "map coords in message")
local n1 = #sent
QM_BroadcastLFM()
check(#sent == n1, "immediate second broadcast blocked by anti-spam")

-- 4. incoming LFM from Buddy (CHAT_MSG_ADDON, modern style)
fire("CHAT_MSG_ADDON", "QG", "QG_LFM^Elwynn Forest^12^The Fargodeep Mine^^52.0^41.0", "CHANNEL", "Buddy")
check(#sent == 2 and sent[2].dist == "WHISPER" and sent[2].target == "Buddy", "HAVE whispered back to initiator")
check(strsub(sent[2].msg, 1, 7) == "QG_HAVE", "HAVE message format")

-- wrong zone / unknown quest / completed quest / wrong level => no reply
local n2 = #sent
fire("CHAT_MSG_ADDON", "QG", "QG_LFM^Durotar^12^The Fargodeep Mine^^^", "CHANNEL", "Buddy2")
check(#sent == n2, "LFM from wrong zone ignored")
fire("CHAT_MSG_ADDON", "QG", "QG_LFM^Elwynn Forest^20^Unknown Quest^^^", "CHANNEL", "Buddy3")
check(#sent == n2, "LFM for quest we don't have ignored")
fire("CHAT_MSG_ADDON", "QG", "QG_LFM^Elwynn Forest^13^The Fargodeep Mine^^^", "CHANNEL", "Buddy4")
check(#sent == n2, "same-name quest that is completed for us not answered")
fire("CHAT_MSG_ADDON", "QG", "QG_LFM^Elwynn Forest^99^The Fargodeep Mine^^^", "CHANNEL", "Buddy5")
check(#sent == n2, "same-name quest with mismatched level not answered")
-- non-protocol messages ignored
fire("CHAT_MSG_ADDON", "OTHER", "hello", "CHANNEL", "Buddy6")
fire("CHAT_MSG_CHANNEL", "just chatting", "Buddy6")
check(#sent == n2, "non-protocol messages ignored")

-- 5. incoming HAVE whisper -> responder added
fire("CHAT_MSG_WHISPER", "QG_HAVE^Elwynn Forest^12^The Fargodeep Mine^^50.0^40.0", "Buddy")
check(#QM.responders == 1 and QM.responders[1].name == "Buddy", "responder added on HAVE")
check(QM.UI.respRows[1]._vis and QM.UI.respRows[1]._resp ~= nil, "responder row rendered")
-- per-sender rate limit
local t0 = QM.responders[1].time
fire("CHAT_MSG_WHISPER", "QG_HAVE^Elwynn Forest^12^The Fargodeep Mine^^50.0^40.0", "Buddy")
check(#QM.responders == 1 and QM.responders[1].time == t0, "per-sender rate limit blocks repeated HAVE")

-- 6. invite methods (taint-safe ordering)
QM.db.prefs.inviteMethod = "auto"
QM_Invite("Buddy")
check(chatsent[#chatsent] and chatsent[#chatsent].msg == "/invite Buddy", "auto method: /invite slash first (no retargeting)")
QM.db.prefs.inviteMethod = "api"
QM_Invite("Buddy")
check(targeted == "Buddy" and invitedUnit == "target", "api method: TargetUnit + InviteUnit(\"target\")")
QM_Invite("NearGuy", true, "plate1")
check(invitedUnit == "plate1", "api method: invite by nameplate unit token, no retargeting")
local savedPI, savedTU = C_PartyInfo.InviteUnit, TargetUnit
C_PartyInfo.InviteUnit = nil
TargetUnit = nil
currentTarget = nil
QM_Invite("Pal")
check(chatsent[#chatsent] and chatsent[#chatsent].msg == "/invite Pal", "fallback with no API: /invite slash command")
C_PartyInfo.InviteUnit, TargetUnit = savedPI, savedTU
QM.db.prefs.inviteMethod = "slash"
QM_Invite("Pal")
check(chatsent[#chatsent] and chatsent[#chatsent].msg == "/invite Pal", "slash method always uses /invite")
-- auto WITH a token -> token API first (taint-safe), no slash
local nchats = #chatsent
QM.db.prefs.inviteMethod = "auto"
QM_Invite("NearGuy", true, "nameplate1")
check(invitedUnit == "nameplate1" and #chatsent == nchats, "auto method with token uses the unit-token API, not the slash")
-- taint right after a token invite -> method marked blocked -> next invite skips it
QM.blockedMethods = {}
QM.pendingInvite = nil
QM_Invite("NearGuy", true, "nameplate1")
fire("CHAT_MSG_SYSTEM", "Interface action failed because of an addon")
check(QM.blockedMethods.token == true, "taint after a token invite marks 'token' as blocked")
QM_Invite("NearGuy", true, "nameplate1")
check(chatsent[#chatsent] and chatsent[#chatsent].msg == "/invite NearGuy", "blocked method is skipped on the next invite (falls to slash)")
-- forced single method via /qg invitetry
QM.blockedMethods = {}
invitedUnit = nil
QM_Slash("invitetry NearGuy token")
check(invitedUnit == "nameplate1", "/qg invitetry <name> token forces the token method only")
local nc2 = #chatsent
QM_Slash("invitetry Pal slash")
check(chatsent[#chatsent] and chatsent[#chatsent].msg == "/invite Pal" and #chatsent == nc2 + 1, "/qg invitetry <name> slash forces the slash method only")
QM_Slash("invitetry Pal chat")
check(openedChat == "/invite Pal", "/qg invitetry <name> chat prefills the chat box with /invite")
-- opposite-faction nameplate is excluded from the nearby list
local nearNow = QM_NearbyPlayers()
local hordeFound = false
for i = 1, table.getn(nearNow) do
  if nearNow[i].name == "HordeGuy" then hordeFound = true end
end
check(table.getn(nearNow) == 2 and not hordeFound, "opposite-faction players are excluded from nearby invites")
-- joined-group confirmation on GROUP_ROSTER_UPDATE
GetNumPartyMembers = function() return 1 end
GetPartyMember = function(i) return "NearGuy" end
QM.nearbyInvited = { NearGuy = time() }
QM.joinedNoted = {}
fire("GROUP_ROSTER_UPDATE")
local joinedMsg = false
for i = 1, table.getn(DEFAULT_CHAT_FRAME.msgs) do
  if strfind(DEFAULT_CHAT_FRAME.msgs[i], "joined the group", 1, true) then joinedMsg = true end
end
check(joinedMsg, "GROUP_ROSTER_UPDATE reports a nearby-invited player who joined")
GetNumPartyMembers = function() return 0 end
GetPartyMember = nil
QM.nearbyInvited = {}  -- reset re-invite protection for the following tests
-- force flag: dedicated button queues nearby invites even with the pref off
QM.db.prefs.inviteNearby = false
QM.nearbyQueue = {}
QM_QueueNearbyInvites(true)
check(table.getn(QM.nearbyQueue) == 2, "dedicated button (force=true) queues nearby players without the pref")
check(QM.nearbyQueue[1].name == "NearGuy" and QM.nearbyQueue[1].token == "nameplate1", "queue entries carry name + unit token")
QM.nearbyQueue = {}
QM_QueueNearbyInvites(false)
check(table.getn(QM.nearbyQueue) == 0, "pref off + no force = no auto-queue")
QM.nearbyInvited = {}  -- reset the 120s re-invite protection for the next tests
-- default window position is centered (not 0,0 behind chat)
check(QM.UI.frame._pt and QM.UI.frame._pt[1] == "CENTER", "window centered by default")

-- 7. legacy event style (globals event/arg1..arg9, handler called with no args)
event = "CHAT_MSG_WHISPER"; arg1 = "QG_HAVE^Elwynn Forest^11^Defias Brotherhood^^^"; arg2 = "Pal"
evf.scripts.OnEvent()
check(#QM.responders == 2 and QM.responders[2].name == "Pal", "legacy-style (globals) event dispatch works")
event, arg1, arg2 = nil, nil, nil

-- 8. fallback to SendChatMessage when SendAddonMessage is unavailable
QM.SendAddonMessage = nil
QM.lastBroadcast = 0
QM_BroadcastLFM()
check(#chatsent >= 1 and chatsent[#chatsent].typ == "CHANNEL" and chatsent[#chatsent].target == "QuestGroupSync",
  "fallback: SendChatMessage on the hidden channel")
QM.SendAddonMessage = SendAddonMessage

-- 9. chat filters
check(filters["CHAT_MSG_WHISPER"]("QG_HAVE^Elwynn^12^X") == true, "filter hides protocol whispers")
check(filters["CHAT_MSG_WHISPER"]("hello there") == false, "filter keeps normal whispers")
arg1 = "QG_LFM^Elwynn^12^X"
check(filters["CHAT_MSG_CHANNEL"]() == true, "legacy-style filter reads global arg1")
arg1 = nil

-- 10. responder expiry
QM.responders[1].time = time() - 120
QM.db.prefs.expire = 60
QM_Tick()
check(#QM.responders == 1 and QM.responders[1].name == "Pal", "expired responder pruned, fresh one kept")

-- 11. auto-announce on zone change
QM.db.prefs.autoAnnounce = true
QM.lastBroadcast = 0
local nb = #sent + #chatsent
fire("ZONE_CHANGED_NEW_AREA")
check(#sent + #chatsent > nb, "auto-announce on zone change broadcasts LFM")
QM.db.prefs.autoAnnounce = false

-- 12. auto-accept invite from a known responder
QM.db.prefs.autoAccept = true
fire("PARTY_INVITE_REQUEST", "Pal")
check(accepted == true, "auto-accept invite from known responder (no popup -> direct AcceptGroup fallback)")
fire("PARTY_INVITE_REQUEST", "Stranger")
QM.db.prefs.autoAccept = false

-- 12b. taint-safe accept: click Blizzard's popup button instead of calling AcceptGroup directly
STATICPOPUP_NUMDIALOGS = 4
local popupClicked = false
_G["StaticPopup1"] = {
  which = "PARTY_INVITE",
  IsVisible = function() return true end,
  button1 = { Click = function() popupClicked = true end },
}
accepted = nil
QM.db.prefs.autoAccept = true
fire("PARTY_INVITE_REQUEST", "Pal")
check(popupClicked == true and accepted == nil, "auto-accept clicks the popup button (no direct AcceptGroup -> no taint)")
_G["StaticPopup1"].IsVisible = function() return false end
fire("PARTY_INVITE_REQUEST", "Pal")
check(accepted == true, "fallback: direct AcceptGroup when no popup is visible")
QM.db.prefs.autoAccept = false

-- 13. slash commands
QM_Slash("debug"); check(QM.debug == true, "/qg debug toggles")
QM_Slash("delay 30"); check(QM.db.prefs.minDelay == 30, "/qg delay sets preference")
QM_Slash("expire 45"); check(QM.db.prefs.expire == 45, "/qg expire sets preference")
QM_Slash("invitehow api"); check(QM.db.prefs.inviteMethod == "api", "/qg invitehow sets the invite method")
QM_Slash("invitehow auto"); check(QM.db.prefs.inviteMethod == "auto", "/qg invitehow back to auto")
QM_Slash(""); check(QM.UI.frame._vis == false, "/qg hides window")
QM_Slash(""); check(QM.UI.frame._vis == true, "/qg shows window")
QM_Slash("probe")
QM_Slash("quests")

-- 14. scrolling
local many = {}
for i = 1, 20 do many[i] = { title = "Quest " .. i, level = i } end
QM.quests = many
QM_UI_RefreshList()
QM_UI_Scroll(5);   check(QM.UI.listOffset == 5, "scroll down -> offset 5")
QM_UI_Scroll(-99); check(QM.UI.listOffset == 0, "scroll clamps at top")
QM_UI_Scroll(99);  check(QM.UI.listOffset == 20 - 9, "scroll clamps at bottom")
QM_UI_Select(20)
check(QM.UI.rows[9]._idx == 20 and QM.UI.rows[9]._hl._vis, "selected row highlighted at bottom of list")

-- 13b. nearby invites (players without the addon): broadcast queues nameplate players, tick invites them staggered
QM.db.prefs.inviteNearby = true
QM.db.prefs.inviteMethod = "api"
QM.stats.nearbyInvites = 0
QM.lastBroadcast = 0
QM_BroadcastLFM()  -- real (stubbed) send + queue nearby invites
check(table.getn(QM.nearbyQueue) == 2 and QM.nearbyQueue[1].name == "NearGuy" and QM.nearbyQueue[2].name == "NearGal",
  "broadcast with inviteNearby queues nearby nameplate players")
targeted, invitedUnit = nil, nil
QM.lastNearbyInvite = 0
evf.scripts.OnUpdate(evf, 0.6)  -- one tick -> one invite (staggered)
check(invitedUnit == "nameplate1" and table.getn(QM.nearbyQueue) == 1,
  "tick sends the first nearby invite (by unit token)")
QM.lastNearbyInvite = time() - 10
evf.scripts.OnUpdate(evf, 0.6)
check(invitedUnit == "nameplate2" and table.getn(QM.nearbyQueue) == 0, "next tick sends the next nearby invite after the delay")
QM.lastNearbyInvite = time()  -- just invited -> next tick must NOT invite again (staggering)
evf.scripts.OnUpdate(evf, 0.6)
check(invitedUnit == "nameplate2", "nearby invites are staggered by nearbyDelay")
-- invite counter
check(QM.stats.nearbyInvites == 2, "nearby invite counter counts sent invites (2)")
QM_UI_RefreshCount()
check(QM.UI.invCount and strfind(QM.UI.invCount._text, "2", 1, true) ~= nil, "counter label shows the count")
QM.db.prefs.showInviteCount = false
QM_UI_RefreshCount()
check(QM.UI.invCount._vis == false, "counter hidden when the option is off")
QM.db.prefs.showInviteCount = true
QM_UI_RefreshCount()
-- re-invite protection: same players are not queued again within nearbyExpire
QM_BroadcastLFM = QM_BroadcastLFM
QM.lastBroadcast = 0
QM_QueueNearbyInvites()
check(table.getn(QM.nearbyQueue) == 0, "players invited recently are not re-queued")
QM.db.prefs.inviteNearby = false
QM.db.prefs.inviteMethod = "auto"

-- 13c. friendly nameplates off -> button auto-enables the cvar, rescans next tick
local cvarSet
local cvars = { nameplateShowFriends = "0", nameplateMaxDistance = "45" }
GetCVar = function(n) return cvars[n] end
SetCVar = function(n, v) cvars[n] = tostring(v); cvarSet = n end
platesVisible = false  -- simulate friendly nameplates off (no nameplate tokens, no plate frames)
QM.nearbyQueue = {}
QM.pendingNearby = nil
QM_QueueNearbyInvites(true)
check(cvarSet == "nameplateShowFriends" and cvars.nameplateShowFriends == "1",
  "button auto-enables nameplateShowFriends when no player plates visible")
check(QM.pendingNearby ~= nil, "a rescan is scheduled for the next tick")
QM.pendingNearby = time() - 1  -- simulate 1+ s having passed (in-game this is real time)
currentTarget = nil  -- no target fallback, only nameplates
platesVisible = true  -- plates appear after enabling
QM.nearbyInvited = {}
evf.scripts.OnUpdate(evf, 0.6)
check(table.getn(QM.nearbyQueue) == 2 and QM.nearbyQueue[1].name == "NearGuy",
  "rescan after enabling nameplates queues the players")
QM.nearbyQueue = {}
QM.pendingNearby = nil
-- /qg scan diagnostic runs cleanly
check(pcall(QM_Slash, "scan"), "/qg scan runs without error")

-- 14b. in-game selftest command (as a player without a second account would run it)
local function countFails()
  local c = 0
  for i = 1, table.getn(DEFAULT_CHAT_FRAME.msgs) do
    if strfind(DEFAULT_CHAT_FRAME.msgs[i], "FAIL:", 1, true) then c = c + 1 end
  end
  return c
end
local f0 = countFails()
QM_Slash("selftest")
check(countFails() == f0, "/qg selftest reports no failures")

-- 15. position save
QM_UI_SavePos()
check(QM.db.pos.x == 100 and QM.db.pos.y == 500, "window position saved to SavedVariables")

-- 14c. taint system message -> hint printed
local nmsgs = table.getn(DEFAULT_CHAT_FRAME.msgs)
QM.pendingInvite = nil
fire("CHAT_MSG_SYSTEM", "Échec d'une action d'interface liée à un programme d'interface personnalisée")
local sawHint = false
for i = nmsgs + 1, table.getn(DEFAULT_CHAT_FRAME.msgs) do
  if strfind(DEFAULT_CHAT_FRAME.msgs[i], "taint", 1, true) then sawHint = true end
end
check(sawHint, "taint error message triggers the /qg invitehow hint")
fire("CHAT_MSG_SYSTEM", "Some unrelated system message")
local hints = 0
for i = nmsgs + 1, table.getn(DEFAULT_CHAT_FRAME.msgs) do
  if strfind(DEFAULT_CHAT_FRAME.msgs[i], "Action blocked by the client", 1, true) then hints = hints + 1 end
end
check(hints == 1, "normal system messages do not trigger the hint")

-- 15b. minimap button: click toggles window, drag updates saved angle
check(QM.UI.minimapBtn ~= nil, "minimap button created")
local vis0 = QM.UI.frame._vis
QM.UI.minimapBtn.scripts.OnClick()
check(QM.UI.frame._vis == (not vis0), "minimap button click toggles the window")
QM.UI.minimapBtn.scripts.OnClick()
check(QM.UI.frame._vis == vis0, "second click toggles back")
local ang0 = QM.db.minimapAngle
QM.UI.minimapBtn.scripts.OnDragStart()
QM.UI.minimapBtn.scripts.OnUpdate()
check(type(QM.db.minimapAngle) == "number" and QM.db.minimapAngle ~= ang0, "dragging the minimap button updates the saved angle")
QM.UI.minimapBtn.scripts.OnDragStop()
check(QM.UI.minimapBtn.scripts.OnUpdate == nil, "OnUpdate cleared after drag stop")

-- 15c. dragging from the quest-list area moves the window (child frames forward the drag)
QM.UI.list.scripts.OnDragStart()
check(QM.UI.frame._moving == true, "drag from the quest-list area starts moving the window")
QM.UI.list.scripts.OnDragStop()
check(QM.UI.frame._moving == false and QM.db.posSet == true, "drag stop ends the move and saves the position")

-- 15d. radar window: one dot per nearby player, title shows count, follows window/option
check(QM.UI.radar ~= nil, "radar window created")
QM_UI_RefreshRadar()
check(QM.UI.radarDots[1]._vis == true and QM.UI.radarDots[2]._vis == true and QM.UI.radarDots[3]._vis == false,
  "radar shows one dot per nearby player (2 players -> 2 dots)")
check(strfind(QM.UI.radarTitle._text, "2", 1, true) ~= nil, "radar title shows the player count")
QM_UI_Toggle()  -- hide main window
check(QM.UI.radar._vis == false, "radar hides with the main window")
QM_UI_Toggle()  -- show again
check(QM.UI.radar._vis == true, "radar shows with the main window")
QM.db.prefs.showRadar = false
QM_UI_SyncRadar()
check(QM.UI.radar._vis == false, "radar hidden when the option is off")
QM.db.prefs.showRadar = true
QM_UI_SyncRadar()

-- 16. OnUpdate drives the ticker (cooldown label + responder expiry) without any click
QM.responders = { { name = "OldDummy", time = time() - 3600 } }
QM.db.prefs.expire = 60
QM.lastBroadcast = time()
evf.scripts.OnUpdate(evf, 0.6)  -- simulate 0.6 s of OnUpdate on the event frame
check(table.getn(QM.responders) == 0, "OnUpdate tick prunes expired responders")
check(QM.UI.cd and strfind(QM.UI.cd._text, "wait", 1, true) ~= nil,
  "cooldown label updates via OnUpdate without clicking anything")

print(string.format("== %d passed, %d failed ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
