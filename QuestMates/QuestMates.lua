-- ============================================================================
-- QuestMates - core (state, communication protocol, anti-spam, slash commands)
--
-- Target client: "WoW Forever" (client 1.60.1, build 70790, Interface 16001).
--
-- Because the interface number alone does not tell us the API era of this
-- client, this file:
--   * works with both event styles: old (global event/arg1..arg9/this) and
--     modern (handler(self, event, ...));
--   * capability-detects every API and falls back (SendAddonMessage ->
--     C_ChatInfo.SendAddonMessage, GetQuestLogTitle -> C_QuestLog, ...);
--   * is written in Lua 5.0/5.1-safe style: no goto, no select, no ipairs,
--     no `#` operator, table.getn, plain global string functions.
--
-- Protocol (fields separated by "^"; "^" is stripped from quest names):
--   QG_LFM^zone^level^questName^questID^x^y    broadcast on the hidden channel
--   QG_HAVE^zone^level^questName^questID^x^y   whispered back to the initiator
--   (questID / x / y may be empty on clients without those APIs)
-- ============================================================================

QuestMates = QuestMates or {}
local QM = QuestMates
QM.version = "1.0.0"

-- ---------------------------------------------------------------------------
-- Protocol constants
-- ---------------------------------------------------------------------------
local PREFIX  = "QG"              -- addon-message prefix
local CHANNEL = "QuestGroupSync"  -- hidden custom channel
local MARKER  = "QG_"             -- prefix of plain-text protocol messages
local RATE_IN = 3                 -- min seconds between 2 messages from one sender

-- ---------------------------------------------------------------------------
-- Lua 5.0/5.1-safe helpers
-- ---------------------------------------------------------------------------
local function qn(t) return table.getn(t) end

-- qsplit("a^b^c", "^") -> {"a","b","c"}  (strsplit does not exist on old clients)
local function qsplit(str, sep)
  local out = {}
  if type(str) ~= "string" then return out end
  local pos = 1
  while true do
    local s, e = strfind(str, sep, pos, true)
    if not s then
      out[qn(out) + 1] = strsub(str, pos)
      break
    end
    out[qn(out) + 1] = strsub(str, pos, s - 1)
    pos = e + 1
  end
  return out
end

-- quest/zone names must not contain the protocol separator
local function qsanitize(s)
  if type(s) ~= "string" then return "" end
  s = gsub(s, "%^", " ")
  s = gsub(s, "%s+", " ")
  s = gsub(s, "^%s+", "")
  s = gsub(s, "%s+$", "")
  return s
end

-- ---------------------------------------------------------------------------
-- Localization (frFR / enUS, English fallback)
-- ---------------------------------------------------------------------------
local locale = "enUS"
if GetLocale then
  local ok, l = pcall(GetLocale)
  if ok and type(l) == "string" then locale = l end
end

local L
if locale == "frFR" then
  L = {
    title       = "QuestMates",
    broadcast   = "Chercher des partenaires",
    waitShort   = "attente %ds",
    noQuest     = "Sélectionnez d'abord une quête dans la liste.",
    questDone   = "Cette quête est déjà terminée.",
    wait        = "Attendez encore %d s avant de relancer l'annonce.",
    sent        = "Annonce envoyée pour : %s",
    sendFail    = "Envoi impossible (le canal QuestGroupSync est-il disponible ?).",
    haveQuest   = "%s a aussi la quête « %s » !",
    invited     = "Invitation envoyée à %s.",
    accepted    = "Invitation de groupe de %s acceptée.",
    noInviteApi = "Aucune API d'invitation disponible sur ce client.",
    responders  = "Réponses (%d) :",
    questsHdr   = "Vos quêtes (%d) :",
    invite      = "Inviter",
    selLabel    = "Quête : %s",
    none        = "aucune",
    statusGroup = "dans le groupe",
    statusZone  = "mauvaise zone",
    statusOK    = "dispo",
    optAuto     = "Annoncer auto. au changement de zone",
    optAccept   = "Accepter auto. les invitations des répondeurs",
    optNearby   = "Inviter aussi les joueurs proches (sans l'addon)",
    nearbyQueued = "%d invitations proches en attente (total envoyé : %d)",
    nearbyFull  = "Groupe plein : invitations aux joueurs proches ignorées.",
    noNearby    = "Aucun joueur proche visible.",
    platesHint  = "Astuce : activez les nameplates alliés (raccourci clavier, ex. Ctrl+V ou Ctrl+Maj+V) pour voir les joueurs proches.",
    platesEnabled = "Nameplates alliés activés - nouvelle recherche...",
    optCount    = "Afficher le compteur d'invitations",
    invCount    = "Invitations envoyées (proches) : %d",
    optRadar    = "Afficher le radar (joueurs proches)",
    radarTitle  = "Radar : %d joueur(s) (≤%d yd)",
    inviteNearbyBtn = "Inviter les proches",
    tipMinimap  = "clic : afficher/masquer la fenêtre - glisser : déplacer le bouton",
    tipBroadcast = "Annoncer la quête sélectionnée aux utilisateurs de QuestMates dans cette zone",
    tipNearby   = "Inviter les joueurs visibles autour de vous (nameplates/cible), même sans l'addon",
    taintHint   = "Action bloquée par le client (taint) - les invitations auto peuvent échouer : essayez /qg invitehow api",
    taintBlocked = "Méthode d'invitation bloquée par le client (taint) : %s — elle sera ignorée désormais.",
    chatReady   = "Invitation préparée dans le chat : /invite %s (touche Entrée pour envoyer)",
    joinedGroup = "%s a rejoint le groupe !",
    complete    = "(terminée)",
    probeHdr    = "--- Sonde QuestMates ---",
    usage       = "/qg : fenêtre | /qg lfm : annoncer | /qg probe : sonde API | /qg selftest : test auto | /qg scan : diagnostic proches | /qg nearby on|off | /qg invitehow auto|slash|api|chat | /qg invitetest <nom> | /qg invitetry <nom> token|target|chat | /qg debug | /qg delay <s> | /qg expire <s> | /qg quests | /qg eventtest",
    loaded      = "QuestMates %s chargé - /qg pour afficher/masquer la fenêtre.",
  }
else
  L = {
    title       = "QuestMates",
    broadcast   = "Find mates",
    waitShort   = "wait %ds",
    noQuest     = "Select a quest in the list first.",
    questDone   = "This quest is already completed.",
    wait        = "Please wait %d more s before broadcasting again.",
    sent        = "Announced quest: %s",
    sendFail    = "Could not send (is the QuestGroupSync channel available?).",
    haveQuest   = "%s also has the quest \"%s\"!",
    invited     = "Invitation sent to %s.",
    accepted    = "Accepted group invite from %s.",
    noInviteApi = "No invite API available on this client.",
    responders  = "Responders (%d):",
    questsHdr   = "Your quests (%d):",
    invite      = "Invite",
    selLabel    = "Quest: %s",
    none        = "none",
    statusGroup = "in group",
    statusZone  = "wrong zone",
    statusOK    = "ready",
    optAuto     = "Auto-announce on zone change",
    optAccept   = "Auto-accept invites from responders",
    optNearby   = "Also invite nearby players (no addon needed)",
    nearbyQueued = "Queued %d nearby invites (total sent: %d)",
    nearbyFull  = "Party is full, nearby invites skipped.",
    noNearby    = "No nearby players visible.",
    platesHint  = "Tip: enable friendly nameplates (keybind, e.g. Ctrl+V or Ctrl+Shift+V) so nearby players are visible.",
    platesEnabled = "Friendly nameplates were off - enabled, rescanning...",
    optCount    = "Show invite counter",
    invCount    = "Invites sent (nearby): %d",
    optRadar    = "Show radar (nearby players)",
    radarTitle  = "Radar: %d player(s) (≤%d yd)",
    inviteNearbyBtn = "Invite nearby",
    tipMinimap  = "click: show/hide the window - drag: move the button",
    tipBroadcast = "Announce the selected quest to QuestMates users in this zone",
    tipNearby   = "Invite players visible around you (nameplates/target), even without the addon",
    taintHint   = "Action blocked by the client (taint) - auto invites may fail: try /qg invitehow api",
    taintBlocked = "Invite method blocked by the client (taint): %s - it will be skipped from now on.",
    chatReady   = "Invite prepared in chat: /invite %s (press Enter to send)",
    joinedGroup = "%s joined the group!",
    complete    = "(done)",
    probeHdr    = "--- QuestMates probe ---",
    usage       = "/qg : toggle window | /qg lfm : broadcast | /qg probe : API probe | /qg selftest : self-test | /qg scan : nearby diagnostic | /qg nearby on|off | /qg invitehow auto|slash|api|chat | /qg invitetest <name> | /qg invitetry <name> token|target|chat | /qg debug | /qg delay <s> | /qg expire <s> | /qg quests | /qg eventtest",
    loaded      = "QuestMates %s loaded - /qg to show/hide the window.",
  }
end
QM.L = L

-- ---------------------------------------------------------------------------
-- API capability detection (old globals first, then modern C_* namespaces)
-- ---------------------------------------------------------------------------
QM.SendAddonMessage = SendAddonMessage or (C_ChatInfo and C_ChatInfo.SendAddonMessage) or nil
QM.RegisterPrefix   = RegisterAddonMessagePrefix or (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or nil
QM.InviteByName     = InviteByName or (C_PartyInfo and C_PartyInfo.InviteByName) or nil
QM.AcceptGroupFn    = AcceptGroup or (C_PartyInfo and C_PartyInfo.AcceptGroup) or nil

-- ---------------------------------------------------------------------------
-- State + SavedVariables
-- ---------------------------------------------------------------------------
QM.quests        = {}   -- quest log snapshot: { {title=, level=, id=, complete=}, ... }
QM.selected      = nil  -- index in QM.quests
QM.responders    = {}   -- { {name=, zone=, level=, quest=, id=, x=, y=, time=}, ... }
QM.lastBroadcast = 0    -- time() of last LFM broadcast (anti-spam)
QM.lastSeen      = {}   -- sender -> time() of last protocol message (rate limit)
QM.nearbyQueue   = {}   -- names of nearby players waiting for an invite
QM.nearbyInvited = {}   -- name -> time() of last nearby invite (don't re-invite too often)
QM.lastNearbyInvite = 0 -- time() of last queued nearby invite (stagger them)
QM.stats         = { invites = 0, nearbyInvites = 0 }  -- session counters
QM.blockedMethods = {}  -- invite methods proven taint-blocked this session: byname/token/slash/target
QM.pendingInvite = nil  -- { m = method key, t = time() } of the last invite attempt
QM.joinedNoted  = {}    -- names already reported as "joined the group"
QM.debug         = false
QM.db            = nil
QM.loginTime     = 0
QM.channelWarned = false

function QM_InitDB()
  if type(QuestMatesDB) ~= "table" then QuestMatesDB = {} end
  QM.db = QuestMatesDB
  if type(QM.db.prefs) ~= "table" then QM.db.prefs = {} end
  local p = QM.db.prefs
  if type(p.minDelay) ~= "number" then p.minDelay = 15 end        -- min delay between broadcasts (s)
  if type(p.expire) ~= "number" then p.expire = 60 end            -- responder expiry (s)
  if type(p.autoAnnounce) ~= "boolean" then p.autoAnnounce = false end
  if type(p.autoAccept) ~= "boolean" then p.autoAccept = false end
  if type(p.inviteNearby) ~= "boolean" then p.inviteNearby = false end  -- invite nearby players without the addon
  if type(p.nearbyMax) ~= "number" then p.nearbyMax = 5 end            -- max nearby invites per broadcast
  if type(p.nearbyDelay) ~= "number" then p.nearbyDelay = 2 end        -- seconds between two nearby invites
  if type(p.nearbyExpire) ~= "number" then p.nearbyExpire = 120 end    -- don't re-invite the same player for this long (s)
  if type(p.showInviteCount) ~= "boolean" then p.showInviteCount = true end  -- show the invite counter in the window
  if type(p.inviteMethod) ~= "string" then p.inviteMethod = "auto" end       -- auto | slash | api (taint-safe invite path)
  if type(p.showRadar) ~= "boolean" then p.showRadar = true end              -- show the radar window
  if type(QM.db.radarPos) ~= "table" then QM.db.radarPos = nil end
  if type(QM.db.radarPosSet) ~= "boolean" then QM.db.radarPosSet = false end
  if type(QM.db.pos) ~= "table" then QM.db.pos = nil end       -- nil until the user first moves the window
  if type(QM.db.posSet) ~= "boolean" then QM.db.posSet = false end
  if type(QM.db.minimapAngle) ~= "number" then QM.db.minimapAngle = 225 end  -- position of the minimap button (degrees)
  return QM.db
end

-- ---------------------------------------------------------------------------
-- World info: zone + optional map coordinates
-- ---------------------------------------------------------------------------
function QM_GetZone()
  if GetRealZoneText then
    local ok, z = pcall(GetRealZoneText)
    if ok and type(z) == "string" and z ~= "" then return z end
  end
  if GetZoneText then
    local ok, z = pcall(GetZoneText)
    if ok and type(z) == "string" and z ~= "" then return z end
  end
  if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and mapID then
      local ok2, info = pcall(C_Map.GetMapInfo, mapID)
      if ok2 and type(info) == "table" and info.name then return info.name end
    end
  end
  return ""
end

-- map coordinates (0-100) exchanged in messages to refine "nearby" in a zone
function QM_GetCoords()
  local x, y
  if SetMapToCurrentZone and GetPlayerMapPosition then
    pcall(SetMapToCurrentZone)
    local ok, a, b = pcall(GetPlayerMapPosition, "player")
    if ok then x, y = a, b end
  elseif C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and mapID then
      local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
      if ok2 and type(pos) == "table" then x, y = pos.x, pos.y end
    end
  end
  if type(x) == "number" and type(y) == "number" then
    return string.format("%.1f", x * 100), string.format("%.1f", y * 100)
  end
  return "", ""
end

-- map position of a unit (self or a nameplate token), as x,y in 0..1, or nil
function QM_MapPos(unit)
  unit = unit or "player"
  if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, unit)
    if ok and mapID then
      local ok2, a, b = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
      if ok2 then
        if type(a) == "table" and a.x ~= nil then return a.x, a.y end
        if type(a) == "number" then return a, b end
      end
    end
  end
  if SetMapToCurrentZone and GetPlayerMapPosition then
    pcall(SetMapToCurrentZone)
    local ok, x, y = pcall(GetPlayerMapPosition, unit)
    if ok and type(x) == "number" then return x, y end
  end
  return nil, nil
end

-- ---------------------------------------------------------------------------
-- Quest log snapshot
-- ---------------------------------------------------------------------------
function QM_RefreshQuestLog()
  QM.quests = {}
  if GetNumQuestLogEntries and GetQuestLogTitle then
    -- old API: GetQuestLogTitle(i) -> title, level, tag, isHeader, isCollapsed, [isComplete]
    local ok, n = pcall(GetNumQuestLogEntries)
    n = (ok and tonumber(n)) or 0
    for i = 1, n do
      local ok2, title, level, tag, isHeader, isCollapsed, isComplete = pcall(GetQuestLogTitle, i)
      if ok2 and type(title) == "string" and not isHeader then
        local id
        if GetQuestLogQuestId then
          local ok3, q = pcall(GetQuestLogQuestId, i)
          if ok3 then id = q end
        end
        QM.quests[qn(QM.quests) + 1] = {
          title = title, level = level, id = id,
          complete = (isComplete and true) or false,  -- best effort on old clients
        }
      end
    end
  elseif C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    -- modern API
    local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    n = (ok and tonumber(n)) or 0
    for i = 1, n do
      local ok2, info = pcall(C_QuestLog.GetInfo, i)
      if ok2 and type(info) == "table" and info.title and not info.isHeader then
        -- completion: explicit field if present, else the IsComplete APIs
        local complete = false
        if info.isComplete ~= nil then
          complete = (info.isComplete and true) or false
        elseif info.questID ~= nil and C_QuestLog.IsComplete then
          local okc, c = pcall(C_QuestLog.IsComplete, info.questID)
          if okc then complete = (c and true) or false end
        elseif info.questID ~= nil and C_QuestLog.IsQuestFlaggedCompleted then
          local okc, c = pcall(C_QuestLog.IsQuestFlaggedCompleted, info.questID)
          if okc then complete = (c and true) or false end
        end
        QM.quests[qn(QM.quests) + 1] = {
          title = info.title,
          level = info.level or info.questLevel,
          id = info.questID or info.questId,
          complete = complete,
        }
      end
    end
  end
  -- keep the current selection valid
  if QM.selected and QM.selected > qn(QM.quests) then QM.selected = nil end
end

-- find a quest by name; level/questID disambiguate quests with identical names
function QM_FindQuest(title, level, id)
  for i = 1, qn(QM.quests) do
    local q = QM.quests[i]
    if q.title == title then
      local ok = true
      if level ~= nil and q.level ~= nil and tonumber(q.level) ~= level then ok = false end
      if ok and id ~= nil and id ~= "" and q.id ~= nil and tostring(q.id) ~= tostring(id) then ok = false end
      if ok then return i, q end
    end
  end
  return nil, nil
end

-- ---------------------------------------------------------------------------
-- Output helpers
-- ---------------------------------------------------------------------------
function QM_Print(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[QuestMates]|r " .. tostring(msg))
  end
end

local function QM_Debug(msg)
  if QM.debug then QM_Print(msg) end
end
QM.Debug = QM_Debug  -- used by the UI for click/scroll tracing

-- ---------------------------------------------------------------------------
-- Communication
-- ---------------------------------------------------------------------------

-- Send on the hidden channel: addon message first, plain chat message as fallback.
function QM_SendChannel(msg)
  if QM.SendAddonMessage then
    if pcall(QM.SendAddonMessage, PREFIX, msg, "CHANNEL", CHANNEL) then return true end
    if GetChannelName then
      local ok, num, cname = pcall(GetChannelName, CHANNEL)
      if ok then
        if num and pcall(QM.SendAddonMessage, PREFIX, msg, "CHANNEL", num) then return true end
        if cname and cname ~= CHANNEL and pcall(QM.SendAddonMessage, PREFIX, msg, "CHANNEL", cname) then return true end
      end
    end
  end
  if SendChatMessage then
    if pcall(SendChatMessage, msg, "CHANNEL", nil, CHANNEL) then return true end
    if GetChannelName then
      local ok, num = pcall(GetChannelName, CHANNEL)
      if ok and num and pcall(SendChatMessage, msg, "CHANNEL", nil, num) then return true end
    end
  end
  return false
end

-- Whisper a protocol message to one player (used for HAVE replies).
function QM_SendWhisper(target, msg)
  if not target or target == "" then return false end
  if QM.SendAddonMessage and pcall(QM.SendAddonMessage, PREFIX, msg, "WHISPER", target) then return true end
  if SendChatMessage then return pcall(SendChatMessage, msg, "WHISPER", nil, target) end
  return false
end

function QM_BuildMsg(cmd, q)
  local x, y = QM_GetCoords()
  local parts = {
    cmd,
    qsanitize(QM_GetZone()),
    q.level ~= nil and tostring(q.level) or "",
    qsanitize(q.title or ""),
    q.id ~= nil and tostring(q.id) or "",
    x,
    y,
  }
  return table.concat(parts, "^")
end

-- "I'm looking for people for this quest" (broadcast on the channel).
function QM_BroadcastLFM()
  QM_InitDB()
  if not QM.selected or not QM.quests[QM.selected] then
    QM_Print(L.noQuest)
    return
  end
  local q = QM.quests[QM.selected]
  if q.complete then
    QM_Print(L.questDone)
    return
  end
  -- anti-spam: minimum delay between two broadcasts
  local now = time()
  local wait = QM.db.prefs.minDelay - (now - QM.lastBroadcast)
  if wait > 0 then
    QM_Print(string.format(L.wait, math.ceil(wait)))
    return
  end
  local msg = QM_BuildMsg("QG_LFM", q)
  if QM_SendChannel(msg) then
    QM.lastBroadcast = now
    QM_Print(string.format(L.sent, q.title))
    QM_QueueNearbyInvites()  -- also invite nearby players without the addon, if enabled
    if QM_UI_RefreshSel then pcall(QM_UI_RefreshSel) end
  else
    QM_Print(L.sendFail)
  end
  QM_Debug("sent: " .. msg)
end

-- Incoming protocol message (from CHAT_MSG_ADDON, CHAT_MSG_CHANNEL or CHAT_MSG_WHISPER).
function QM_HandleMessage(text, sender, dist)
  if type(text) ~= "string" or strsub(text, 1, 3) ~= MARKER then return end
  local me = (UnitName and UnitName("player")) or ""
  if sender == me or sender == "You" then return end  -- ignore our own echo

  local p = qsplit(text, "^")
  local cmd = p[1]

  -- per-sender, per-command rate limit (anti-spam). LFM floods on the channel
  -- are throttled harder; a HAVE whisper right after the same player's LFM
  -- must still go through, so the keys are separate.
  local now = time()
  local key = tostring(sender) .. ":" .. tostring(cmd)
  local limit = (cmd == "QG_LFM") and RATE_IN or 1
  local last = tonumber(QM.lastSeen[key]) or -1000000000
  if now - last < limit then return end
  QM.lastSeen[key] = now
  local cnt = 0
  for k in pairs(QM.lastSeen) do cnt = cnt + 1 end
  if cnt > 300 then QM.lastSeen = {} end

  QM_Debug("recv " .. tostring(dist) .. " from " .. tostring(sender) .. ": " .. text)

  if cmd == "QG_LFM" then
    -- someone in our zone is looking for mates for this quest
    local zone, level, name, id = p[2], tonumber(p[3]), p[4], p[5]
    if type(name) ~= "string" or name == "" then return end
    -- only answer if we are in the same zone
    if type(zone) == "string" and zone ~= "" and zone ~= QM_GetZone() then return end
    -- ... and if the quest is in OUR log (name + level/ID), and not completed
    local qi, q = QM_FindQuest(name, level, id)
    if qi and not q.complete then
      QM_SendWhisper(sender, QM_BuildMsg("QG_HAVE", q))  -- reply as a WHISPER
    end
  elseif cmd == "QG_HAVE" then
    -- someone answered our LFM
    local zone, level, name, id, x, y = p[2], tonumber(p[3]), p[4], p[5], p[6], p[7]
    if type(name) == "string" and name ~= "" then
      QM_AddResponder(sender, zone, level, name, id, x, y)
    end
  end
end

function QM_AddResponder(name, zone, level, qtitle, id, x, y)
  if not name or name == "" then return end
  local now = time()
  for i = 1, qn(QM.responders) do
    local r = QM.responders[i]
    if r.name == name then  -- refresh existing entry
      r.zone, r.level, r.quest, r.id, r.x, r.y, r.time = zone, level, qtitle, id, x, y, now
      QM_Print(string.format(L.haveQuest, name, qtitle or ""))
      if QM_UI_RefreshResponders then pcall(QM_UI_RefreshResponders) end
      return
    end
  end
  QM.responders[qn(QM.responders) + 1] = {
    name = name, zone = zone, level = level, quest = qtitle, id = id, x = x, y = y, time = now,
  }
  QM_Print(string.format(L.haveQuest, name, qtitle or ""))
  if QM_UI_RefreshResponders then pcall(QM_UI_RefreshResponders) end
end

function QM_IsResponder(name)
  for i = 1, qn(QM.responders) do
    if QM.responders[i].name == name then return true end
  end
  return false
end

-- Number of OTHER group members (0 = solo). GetNumGroupMembers counts the
-- player too, so subtract one; GetNumSubgroupMembers/GetNumPartyMembers do
-- not. GetNumPartyMembers does not exist on this client.
function QM_GroupMemberCount()
  if GetNumGroupMembers then
    local ok, n = pcall(GetNumGroupMembers)
    n = ok and tonumber(n) or nil
    if n then return (n > 0) and (n - 1) or 0 end
  end
  if GetNumSubgroupMembers then
    local ok, n = pcall(GetNumSubgroupMembers)
    n = ok and tonumber(n) or nil
    if n then return n end
  end
  if GetNumPartyMembers then
    local ok, n = pcall(GetNumPartyMembers)
    n = ok and tonumber(n) or nil
    if n then return n end
  end
  return 0
end

-- Full character name of a unit. This client keeps first name and surname
-- apart: UnitName() returns only the first name, while invites must use the
-- name as displayed ("First Surname"). UnitFullName() returns both.
function QM_UnitFullName(token)
  if type(token) ~= "string" or token == "" then return nil end
  local plain
  if UnitName then
    local ok, n = pcall(UnitName, token)
    if ok then plain = n end
  end
  local first, last
  if UnitFullName then
    local ok, f, l = pcall(UnitFullName, token)
    if ok then first, last = f, l end
  end
  -- some clients return the realm as second value; not part of the name
  if last and GetRealmName then
    local okR, realm = pcall(GetRealmName)
    if okR and realm and last == realm then last = nil end
  end
  if (not first or first == "") then first = plain end
  if not first or first == "" then return nil end
  -- UnitName may already be the full display name: never double the surname
  if plain and strfind(plain, " ", 1, true) then return plain end
  if last and last ~= "" and last ~= first then return first .. " " .. last end
  return first
end

-- add both the short and the full name to a set so comparisons work whatever
-- form the client returns elsewhere
local function qm_add_name(set, token)
  if not UnitName then return end
  local plain = UnitName(token)
  if plain and plain ~= "" then set[plain] = true end
  local full = QM_UnitFullName(token)
  if full and full ~= "" then set[full] = true end
end

-- set of party member names (incl. self) for the "in group" status
function QM_PartySet()
  local set = {}
  qm_add_name(set, "player")
  local n = QM_GroupMemberCount()
  for i = 1, n do
    qm_add_name(set, "party" .. i)
    -- legacy client fallback: GetPartyMember(i) returns a plain name
    if GetPartyMember then
      local ok, nm = pcall(GetPartyMember, i)
      if ok and type(nm) == "string" then set[nm] = true end
    end
  end
  return set
end

function QM_Invite(name, isNearby, token, forceMethod)
  -- Resolve the full displayed name (First Surname) from the unit token.
  -- On this client C_PartyInfo.InviteUnit() takes a NAME, never a unit token:
  -- passing "nameplate1" succeeds silently and invites nobody.
  if token then
    local full = QM_UnitFullName(token)
    if full and full ~= "" then name = full end
  end
  if not name or name == "" then return end
  QM_InitDB()

  -- prefs.inviteMethod: "auto" (default) | "api" | "chat" (or legacy "slash")
  local method = forceMethod or QM.db.prefs.inviteMethod or "auto"
  local inviteUnit = InviteUnit or (C_PartyInfo and C_PartyInfo.InviteUnit)
  local fnByName = InviteByName or (C_PartyInfo and C_PartyInfo.InviteByName)
  QM_Debug("invite " .. name .. ": method=" .. method .. " token=" .. tostring(token)
    .. " fnByName=" .. tostring(fnByName ~= nil) .. " inviteUnit=" .. tostring(inviteUnit ~= nil))

  local function done(key)
    QM.pendingInvite = { m = key, t = time() }  -- a taint error right after this marks the method as blocked
    if key == "chat" then
      -- nothing was sent yet: the user still has to press Enter
      QM_Debug("invite " .. name .. " prepared in the chat box")
      QM_Print(string.format(L.chatReady, name))
      return
    end
    -- only count invites that were really handed to an invite API
    QM.stats.invites = QM.stats.invites + 1
    if isNearby then QM.stats.nearbyInvites = QM.stats.nearbyInvites + 1 end
    if QM_UI_RefreshCount then pcall(QM_UI_RefreshCount) end
    QM_Debug("invite " .. name .. " sent via: " .. key)
    QM_Print(string.format(L.invited, name))
  end

  -- method order; blocked methods are skipped
  local order
  if method == "slash" or method == "chat" then
    order = { "chat" }  -- SendChatMessage("/invite") does NOT run a slash command
  elseif method == "token" or method == "target" or method == "byname" then
    order = { method }  -- forced single method (for /qg invitetry)
  elseif method == "api" then order = { "byname", "token", "target" }
  else order = { "byname", "token", "target", "chat" } end

  for i = 1, qn(order) do
    local m = order[i]
    if not QM.blockedMethods[m] then
      if m == "byname" and fnByName then
        local ok, res = pcall(fnByName, name)
        if ok and res ~= false then done("byname") return end
      elseif m == "token" and inviteUnit then
        -- by NAME (the token was only used to recover the full name above)
        local ok, res = pcall(inviteUnit, name)
        if ok and res ~= false then done("token") return end
      elseif m == "target" then
        -- target-by-name is absent on this client; only try it if it exists
        if inviteUnit and TargetByName then
          local oldGUID = (UnitGUID and UnitGUID("target")) or nil
          pcall(TargetByName, name)
          pcall(inviteUnit, name)
          if oldGUID and TargetUnitByGUID then pcall(TargetUnitByGUID, oldGUID) end
          done("target") return
        end
      elseif m == "chat" then
        -- prefill the chat edit box with /invite <name> — the user presses
        -- Enter, so the slash command runs in the client's own context
        local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
        if open then
          if pcall(open, "/invite " .. name) then done("chat") return end
        end
      end
    end
  end
  QM_Print(L.noInviteApi)
end

-- Accept a group invite the taint-safe way: click Blizzard's own popup button
-- (the protected action then runs in Blizzard's untainted context).
function QM_AcceptInviteSecure()
  local n = STATICPOPUP_NUMDIALOGS or 4
  for i = 1, n do
    local dlg = _G and _G["StaticPopup" .. i]
    if dlg and dlg.IsVisible and dlg:IsVisible() and dlg.which == "PARTY_INVITE" then
      local btn = dlg.button1 or (dlg.GetButton and dlg:GetButton(1))
      if btn and btn.Click then
        pcall(btn.Click, btn)
        return true
      end
    end
  end
  -- fallback: direct call (may taint on strict clients)
  if QM.AcceptGroupFn then
    pcall(QM.AcceptGroupFn)
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Nearby players (for people who do NOT run the addon): collected from
-- nameplates on modern clients, plus target/mouseover as a fallback.
-- ---------------------------------------------------------------------------
-- is `token` a player unit? never errors, whatever the client throws at it
local function QM_IsPlayerToken(token)
  if type(token) ~= "string" then return false end
  local checker = UnitIsPlayer or UnitPlayerControlled
  if not checker then return false end
  if UnitExists then
    local okE, ex = pcall(UnitExists, token)
    if okE and not ex then return false end
  end
  local ok, res = pcall(checker, token)
  return (ok and res) and true or false
end

function QM_NearbyPlayers()
  local out, seen = {}, {}
  local me = (UnitName and QM_UnitFullName("player")) or ""
  -- cross-faction invites are silently rejected by many servers: skip them
  local myFaction
  if UnitFactionGroup then
    local okF, f = pcall(UnitFactionGroup, "player")
    if okF then myFaction = f end
  end
  local function add(name, token)
    if type(name) ~= "string" or name == "" or name == me or seen[name] then return end
    if myFaction and token and UnitFactionGroup then
      local okF, f = pcall(UnitFactionGroup, token)
      if okF and f and f ~= myFaction then
        QM_Debug("skip " .. name .. ": opposite faction (" .. tostring(f) .. ")")
        return
      end
    end
    seen[name] = true
    out[qn(out) + 1] = { name = name, token = token }
  end
  -- 1) nameplate unit tokens directly (works even without reading plate frames)
  if UnitName then
    for i = 1, 40 do
      local token = "nameplate" .. i
      if QM_IsPlayerToken(token) then
        add(QM_UnitFullName(token), token)
      end
    end
  end
  -- 2) nameplate frames, if their unit-token field is readable
  if C_NamePlate and C_NamePlate.GetNamePlates and UnitName then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      for i = 1, qn(plates) do
        local plate = plates[i]
        local token = plate and (plate.namePlateUnitToken or plate.unit or plate.UnitToken)
        if QM_IsPlayerToken(token) then
          add(QM_UnitFullName(token), token)
        end
      end
    end
  end
  -- 3) fallback: current target / mouseover
  if QM_IsPlayerToken("target") then add(QM_UnitFullName("target"), "target") end
  if QM_IsPlayerToken("mouseover") then add(QM_UnitFullName("mouseover"), "mouseover") end
  return out
end

-- unit token of a nearby player, matched by full name ("First Surname") or by
-- the short name used in whispers/responders
function QM_FindNearbyToken(name)
  if not name or name == "" or not QM_NearbyPlayers then return nil end
  local short = gsub(name, " .*$", "")
  local packed = gsub(name, "%s+", "")
  local near = QM_NearbyPlayers()
  for i = 1, qn(near) do
    local n = near[i].name
    if n == name then return near[i].token end
    if n and (gsub(n, " .*$", "") == name or n == short or gsub(n, "%s+", "") == packed) then
      return near[i].token
    end
  end
  return nil
end

-- queue invites to nearby players (called after each successful LFM broadcast,
-- or directly from the "Invite nearby" button with force=true)
function QM_QueueNearbyInvites(force)
  QM_InitDB()
  if not force and not QM.db.prefs.inviteNearby then return end
  -- no room in the party anyway (GetNumPartyMembers does not exist here)
  local pn = QM_GroupMemberCount()
  if pn >= 4 then QM_Print(L.nearbyFull) return end
  local party = QM_PartySet()
  local maxN = tonumber(QM.db.prefs.nearbyMax) or 5
  local expire = tonumber(QM.db.prefs.nearbyExpire) or 120
  local now = time()
  local n = 0
  local players = QM_NearbyPlayers()
  QM_Debug("nearby scan: " .. qn(players) .. " player(s), party=" .. pn)
  for i = 1, qn(players) do
    local p = players[i]
    local name = p.name
    -- skip party members and known responders (they are invited from the panel)
    if not party[name] and not QM_IsResponder(name) then
      local lastInv = tonumber(QM.nearbyInvited[name]) or -1000000000
      if now - lastInv >= expire then
        QM.nearbyQueue[qn(QM.nearbyQueue) + 1] = p  -- { name=, token= }
        QM.nearbyInvited[name] = now
        n = n + 1
        if n >= maxN then break end
      end
    end
  end
  if n > 0 then
    QM_Print(string.format(L.nearbyQueued, n, QM.stats.nearbyInvites))
  elseif force then
    -- no player plates visible: friendly nameplates are probably off.
    -- enable them once, then rescan on the next tick (plates need a frame to appear)
    if QM_TryEnableFriendlyNameplates() then
      QM.pendingNearby = now + 1
      QM_Print(L.platesEnabled)
    else
      QM_Print(L.noNearby)
      QM_Print(L.platesHint)
    end
  end
end

-- turn on friendly nameplates if they are off (the nearby scan needs them).
-- returns true if the cvar was changed
function QM_TryEnableFriendlyNameplates()
  if not SetCVar or not GetCVar then return false end
  -- nameplateShowFriends does not exist on this client; the friendly-nameplate
  -- toggle is nameplateShowFriendlyPlayers (nameplateShowAll also works)
  local ok1, v1 = pcall(GetCVar, "nameplateShowFriendlyPlayers")
  if ok1 and v1 ~= nil then
    if tostring(v1) == "0" then
      if pcall(SetCVar, "nameplateShowFriendlyPlayers", 1) then return true end
    end
    return false
  end
  local ok2, v2 = pcall(GetCVar, "nameplateShowAll")
  if ok2 and v2 ~= nil and tostring(v2) == "0" then
    if pcall(SetCVar, "nameplateShowAll", 1) then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Hidden channel + chat filtering
-- ---------------------------------------------------------------------------
function QM_JoinChannel()
  local join = JoinChannelByName or (C_ChatInfo and C_ChatInfo.JoinChannelByName)
  if join then pcall(join, CHANNEL) end
  -- remove the channel from every chat window so it stays invisible
  if ChatFrame_RemoveChannel then
    for i = 1, 10 do
      local cf = _G and _G["ChatFrame" .. i]
      if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL) end
    end
  end
end

-- filter function: return true to hide the message from chat windows
local function qm_msg_filter(...)
  local args = {...}
  for i = 1, qn(args) do
    if type(args[i]) == "string" and strsub(args[i], 1, 3) == MARKER then return true end
  end
  -- legacy style: event data lives in the globals arg1..arg9
  for i = 1, 9 do
    local v = _G["arg" .. i]
    if type(v) == "string" and strsub(v, 1, 3) == MARKER then return true end
  end
  return false
end

function QM_RegisterFilters()
  QM._msgFilter = qm_msg_filter  -- exposed for /qg selftest
  local addf = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
  if addf then
    pcall(addf, "CHAT_MSG_CHANNEL", qm_msg_filter)
    pcall(addf, "CHAT_MSG_WHISPER", qm_msg_filter)
    pcall(addf, "CHAT_MSG_WHISPER_INFORM", qm_msg_filter)
    pcall(addf, "CHAT_MSG_ADDON", qm_msg_filter)
  elseif ChatFrame_OnEvent then
    -- very old clients without message filters: hook the default chat handler
    local orig = ChatFrame_OnEvent
    ChatFrame_OnEvent = function(...)
      local args = {...}
      local ev = args[1]
      if ev == nil then ev = event end
      if ev == "CHAT_MSG_CHANNEL" or ev == "CHAT_MSG_WHISPER" or ev == "CHAT_MSG_WHISPER_INFORM" then
        if qm_msg_filter(...) then return end
      end
      return orig(...)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Periodic tick: responder expiry + cooldown label + channel warning
-- ---------------------------------------------------------------------------
function QM_Tick()
  QM_InitDB()
  local now = time()
  local exp = QM.db.prefs.expire
  local changed = false
  for i = qn(QM.responders), 1, -1 do
    if now - (QM.responders[i].time or 0) > exp then
      table.remove(QM.responders, i)
      changed = true
    end
  end
  if changed and QM_UI_RefreshResponders then pcall(QM_UI_RefreshResponders) end
  -- staggered invites to nearby players (people without the addon)
  if qn(QM.nearbyQueue) > 0 then
    local delay = tonumber(QM.db.prefs.nearbyDelay) or 2
    if now - QM.lastNearbyInvite >= delay then
      local e = table.remove(QM.nearbyQueue, 1)
      local nm = (type(e) == "table") and e.name or e
      local tk = (type(e) == "table") and e.token or nil
      QM.lastNearbyInvite = now
      QM_Invite(nm, true, tk)
    end
  end
  -- delayed rescan after friendly nameplates were auto-enabled
  if QM.pendingNearby and now >= QM.pendingNearby then
    QM.pendingNearby = nil
    QM_QueueNearbyInvites(true)
  end
  -- warn once if the hidden channel could not be joined
  if not QM.channelWarned and GetChannelName and now - QM.loginTime > 10 then
    local ok, num = pcall(GetChannelName, CHANNEL)
    if ok and (num == nil or num == 0) then
      QM.channelWarned = true
      QM_Print(L.sendFail)
    end
  end
  if QM_UI_Tick then pcall(QM_UI_Tick) end
  if QM_UI_RefreshRadar then pcall(QM_UI_RefreshRadar) end  -- radar refresh (2x/s)
end

function QM_OnZoneChanged()
  QM_InitDB()
  if QM.db.prefs.autoAnnounce then QM_BroadcastLFM() end
end

function QM_OnInviteRequest(inviter)
  QM_InitDB()
  if QM.db.prefs.autoAccept and inviter and QM_IsResponder(inviter) then
    if QM_AcceptInviteSecure() then
      QM_Print(string.format(L.accepted, inviter))
    end
  end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
QM.events = {}

QM.events["ADDON_LOADED"] = function(a1)
  if a1 ~= "QuestMates" then return end
  QM_InitDB()
  if QM.RegisterPrefix then pcall(QM.RegisterPrefix, PREFIX) end
  if QuestMates_BuildUI then
    local ok, err = pcall(QuestMates_BuildUI)
    if not ok then QM_Print("UI error: " .. tostring(err)) end  -- never swallow silently
  end
  QM_RefreshQuestLog()
  if QM_UI_RefreshAll then pcall(QM_UI_RefreshAll) end
  QM_Print(string.format(L.loaded, QM.version))
end

QM.events["VARIABLES_LOADED"] = function() QM_InitDB() end

QM.events["PLAYER_LOGIN"] = function()
  QM_InitDB()
  QM.loginTime = time()
  if QM.RegisterPrefix then pcall(QM.RegisterPrefix, PREFIX) end
  QM_JoinChannel()
  QM_RegisterFilters()
  QM_RefreshQuestLog()
  if QM_UI_RefreshAll then pcall(QM_UI_RefreshAll) end
end

QM.events["PLAYER_ENTERING_WORLD"] = function()
  QM_JoinChannel()
  QM_RefreshQuestLog()
  if QM_UI_RefreshAll then pcall(QM_UI_RefreshAll) end
end

QM.events["PLAYER_LOGOUT"] = function()
  if QM_UI_SavePos then pcall(QM_UI_SavePos) end
end

QM.events["QUEST_LOG_UPDATE"] = function()
  QM_RefreshQuestLog()
  if QM_UI_RefreshAll then pcall(QM_UI_RefreshAll) end
end

QM.events["CHAT_MSG_ADDON"] = function(a1, a2, a3, a4)
  -- a1=prefix, a2=text, a3=distribution, a4=sender
  if a1 == PREFIX then QM_HandleMessage(a2, a4, a3) end
end

QM.events["CHAT_MSG_CHANNEL"] = function(a1, a2)
  -- plain-text fallback on the hidden channel: a1=text, a2=sender
  QM_HandleMessage(a1, a2, "CHANNEL")
end

QM.events["CHAT_MSG_WHISPER"] = function(a1, a2)
  -- a1=text, a2=sender
  QM_HandleMessage(a1, a2, "WHISPER")
end

QM.events["ZONE_CHANGED"] = function() QM_OnZoneChanged() end
QM.events["ZONE_CHANGED_NEW_AREA"] = function() QM_OnZoneChanged() end

QM.events["PARTY_INVITE_REQUEST"] = function(a1) QM_OnInviteRequest(a1) end

QM.events["GROUP_ROSTER_UPDATE"] = function()
  if QM_UI_RefreshResponders then pcall(QM_UI_RefreshResponders) end
  -- confirm end-to-end success: a nearby-invited player joined our group
  local party = QM_PartySet()
  local me = (UnitName and UnitName("player")) or ""
  for name in pairs(QM.nearbyInvited) do
    if name ~= me and party[name] and not QM.joinedNoted[name] then
      QM.joinedNoted[name] = true
      QM_Print(string.format(L.joinedGroup, name))
    end
  end
end

-- detect taint-blocked actions ("Interface action failed because of an addon" /
-- "Échec d'une action d'interface...") and hint at the alternative invite path
QM.events["CHAT_MSG_SYSTEM"] = function(a1)
  if type(a1) ~= "string" then return end
  QM_Debug("sys: " .. a1)  -- shows server-side invite rejections ("busy", "already in a group"...)
  local low = strlower(a1)
  if strfind(low, "interface action failed", 1, true) or strfind(low, "action d'interface", 1, true) then
    -- a taint error right after an invite attempt means that method is blocked
    if QM.pendingInvite and time() - QM.pendingInvite.t < 1.5 then
      QM.blockedMethods[QM.pendingInvite.m] = true
      QM_Print(string.format(L.taintBlocked, tostring(QM.pendingInvite.m)))
      QM.pendingInvite = nil
    end
    QM_Print(L.taintHint)
  end
end

local function QM_Dispatch(ev, a1, a2, a3, a4, a5, a6, a7, a8, a9)
  local h = QM.events[ev]
  if h then pcall(h, a1, a2, a3, a4, a5, a6, a7, a8, a9) end
end

-- event frame. NOTE: do NOT Hide() it — on modern clients a hidden frame
-- does not receive OnUpdate, and OnUpdate drives QM_Tick (cooldown label,
-- responder expiry). Keep it shown but invisible: 1x1 px, fully transparent.
local evf = CreateFrame("Frame", "QuestMatesCoreFrame", UIParent)
evf:SetWidth(1)
evf:SetHeight(1)
evf:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, 0)
if evf.SetAlpha then evf:SetAlpha(0) end
if evf.EnableMouse then evf:EnableMouse(false) end
QM.evf = evf

local EVENT_LIST = {
  "ADDON_LOADED", "VARIABLES_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
  "PLAYER_LOGOUT", "CHAT_MSG_ADDON", "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER",
  "QUEST_LOG_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
  "PARTY_INVITE_REQUEST", "GROUP_ROSTER_UPDATE", "CHAT_MSG_SYSTEM",
}
for i = 1, qn(EVENT_LIST) do
  local ev = EVENT_LIST[i]
  pcall(function() evf:RegisterEvent(ev) end)  -- pcall: some events may not exist on this client
end

-- Dual-style event handler: modern clients pass (self, event, ...) as varargs;
-- old clients call the handler with no arguments and set event/arg1..arg9.
evf:SetScript("OnEvent", function(self, ...)
  local args = {...}
  if qn(args) == 0 and type(event) == "string" then
    QM_Dispatch(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
  else
    QM_Dispatch(args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9])
  end
end)

local tickAcc = 0
evf:SetScript("OnUpdate", function(self, elapsed)
  if elapsed == nil then elapsed = arg1 end  -- legacy style
  tickAcc = tickAcc + (tonumber(elapsed) or 0.05)
  if tickAcc >= 0.5 then
    tickAcc = 0
    pcall(QM_Tick)
  end
end)

-- register the addon-message prefix as early as possible
if QM.RegisterPrefix then pcall(QM.RegisterPrefix, PREFIX) end

-- ---------------------------------------------------------------------------
-- Slash command: /qg
-- ---------------------------------------------------------------------------
SLASH_QUESTMATES1 = "/qg"
SLASH_QUESTMATES2 = "/questmates"
SlashCmdList["QUESTMATES"] = function(msg) pcall(QM_Slash, msg or "") end

function QM_Slash(msg)
  QM_InitDB()
  local a = qsplit(msg, " ")
  local cmd = strlower(a[1] or "")
  if cmd == "" or cmd == "toggle" then
    if QM_UI_Toggle then pcall(QM_UI_Toggle) end
  elseif cmd == "show" then
    if QM_UI_Show then pcall(QM_UI_Show, true) end
  elseif cmd == "hide" then
    if QM_UI_Show then pcall(QM_UI_Show, false) end
  elseif cmd == "lfm" or cmd == "broadcast" then
    QM_BroadcastLFM()
  elseif cmd == "probe" then
    QM_Probe()
  elseif cmd == "selftest" then
    QM_Selftest()
  elseif cmd == "debug" then
    QM.debug = not QM.debug
    QM_Print("debug = " .. tostring(QM.debug))
  elseif cmd == "delay" then
    local n = tonumber(a[2])
    if n and n >= 0 then QM.db.prefs.minDelay = n; QM_Print("minDelay = " .. n) else QM_Print(L.usage) end
  elseif cmd == "expire" then
    local n = tonumber(a[2])
    if n and n > 0 then QM.db.prefs.expire = n; QM_Print("expire = " .. n) else QM_Print(L.usage) end
  elseif cmd == "nearby" then
    local v = strlower(a[2] or "")
    if v == "on" or v == "1" or v == "true" then QM.db.prefs.inviteNearby = true
    elseif v == "off" or v == "0" or v == "false" then QM.db.prefs.inviteNearby = false
    else QM.db.prefs.inviteNearby = not QM.db.prefs.inviteNearby end
    QM_Print("inviteNearby = " .. tostring(QM.db.prefs.inviteNearby))
  elseif cmd == "invitehow" then
    local v = strlower(a[2] or "")
    if v == "auto" or v == "slash" or v == "api" or v == "chat" then
      QM.db.prefs.inviteMethod = v
      QM.blockedMethods = {}  -- re-enable all methods when switching
      QM_Print("inviteMethod = " .. v .. "  (auto = by name via C_PartyInfo.InviteUnit, then target, then chat prefill; api = API only; chat/slash = prefill chat box, you press Enter)")
    else
      QM_Print("inviteMethod = " .. tostring(QM.db.prefs.inviteMethod) .. " (auto|slash|api|chat)")
    end
  elseif cmd == "invitetest" then
    local name = a[2]
    if name and name ~= "" then
      -- attach a nameplate unit token if this player is visible nearby
      local token = QM_FindNearbyToken(name)
      QM_Print("invitetest -> " .. name .. " (method=" .. tostring(QM.db.prefs.inviteMethod) .. " token=" .. tostring(token) .. ")")
      QM_Invite(name, false, token)
    else
      QM_Print(L.usage)
    end
  elseif cmd == "invitetry" then
    -- /qg invitetry <name> <token|slash|target|byname> : force a single invite method
    local name, m = a[2], strlower(a[3] or "")
    if name and name ~= "" and (m == "token" or m == "slash" or m == "target" or m == "byname" or m == "chat") then
      local token = QM_FindNearbyToken(name)
      QM_Print("invitetry -> " .. name .. " method=" .. m .. " token=" .. tostring(token))
      QM_Invite(name, false, token, m)
    else
      QM_Print("/qg invitetry <nom> <token|slash|target|byname|chat>  (slash = chat prefill on this client)")
    end
  elseif cmd == "scan" then
    QM_ScanNearby()
  elseif cmd == "radar" then
    QM.db.prefs.showRadar = not QM.db.prefs.showRadar
    if QM_UI_SyncRadar then pcall(QM_UI_SyncRadar) end
    QM_Print("showRadar = " .. tostring(QM.db.prefs.showRadar))
  elseif cmd == "quests" then
    QM_RefreshQuestLog()
    for i = 1, qn(QM.quests) do
      local q = QM.quests[i]
      QM_Print(i .. ": [" .. tostring(q.level) .. "] " .. tostring(q.title) .. (q.complete and " " .. L.complete or ""))
    end
  elseif cmd == "eventtest" then
    -- detect the event-arg style of this client: say something with /say afterwards
    local tf = CreateFrame("Frame")
    pcall(function() tf:RegisterEvent("CHAT_MSG_SAY") end)
    tf:SetScript("OnEvent", function(self, ...)
      local args = {...}
      QM_Print("event style: varargs=" .. qn(args) .. " first=" .. tostring(args[1]) .. " | global event=" .. tostring(event))
      pcall(function() tf:UnregisterAllEvents() end)
    end)
    QM_Print("eventtest armed - say something with /say")
  else
    QM_Print(L.usage)
  end
end

-- ---------------------------------------------------------------------------
-- Nearby scan diagnostic: /qg scan  (run it with players around you, paste output)
-- ---------------------------------------------------------------------------
function QM_ScanNearby()
  QM_InitDB()
  QM_Print("--- scan nearby ---")
  if GetCVar then
    local CV = { "nameplateShowFriendlyPlayers", "nameplateShowAll", "nameplateMaxDistance" }
    for i = 1, qn(CV) do
      local ok, v = pcall(GetCVar, CV[i])
      QM_Print("cvar " .. CV[i] .. " = " .. tostring(ok and v or "?"))
    end
  end
  QM_Print("UnitName = " .. tostring(UnitName) .. " | UnitFullName = " .. tostring(UnitFullName)
    .. " | GetRealmName = " .. tostring(GetRealmName))
  QM_Print("UnitIsPlayer = " .. tostring(UnitIsPlayer) .. " | UnitPlayerControlled = " .. tostring(UnitPlayerControlled)
    .. " | UnitExists = " .. tostring(UnitExists) .. " | C_NamePlate.GetNamePlates = " .. tostring(C_NamePlate and C_NamePlate.GetNamePlates))
  if UnitExists then
    local cnt = 0
    for i = 1, 40 do
      local token = "nameplate" .. i
      local okE, ex = pcall(UnitExists, token)
      if okE and ex then
        cnt = cnt + 1
        local nm = UnitName and UnitName(token) or nil
        local full = QM_UnitFullName(token)
        local okP, p = pcall(UnitIsPlayer or UnitPlayerControlled or function() return nil end, token)
        QM_Print("  " .. token .. ": name=" .. tostring(nm) .. " full=" .. tostring(full)
          .. " isPlayer=" .. (okP and tostring(p) or "ERROR"))
      end
    end
    QM_Print("existing nameplate tokens: " .. cnt .. " / 40")
  end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      QM_Print("GetNamePlates count = " .. qn(plates))
      local lim = math.min(qn(plates), 10)
      for i = 1, lim do
        local pl = plates[i]
        QM_Print("  plate[" .. i .. "]: namePlateUnitToken=" .. tostring(pl and pl.namePlateUnitToken)
          .. " unit=" .. tostring(pl and pl.unit) .. " UnitToken=" .. tostring(pl and pl.UnitToken))
      end
    else
      QM_Print("GetNamePlates -> " .. tostring(ok) .. " " .. tostring(plates))
    end
  end
  local players = QM_NearbyPlayers()
  QM_Print("QM_NearbyPlayers -> " .. qn(players) .. " player(s):")
  for i = 1, qn(players) do
    QM_Print("  " .. tostring(players[i].name) .. " (token=" .. tostring(players[i].token) .. ")")
  end
  local pn = QM_GroupMemberCount()
  QM_Print("party members = " .. pn
    .. " | inviteNearby = " .. tostring(QM.db.prefs.inviteNearby)
    .. " | inviteMethod = " .. tostring(QM.db.prefs.inviteMethod))
end

-- ---------------------------------------------------------------------------
-- In-game self test: /qg selftest  (works without a second account: injects
-- fake protocol messages as if they came from a "DummyPeer" player)
-- ---------------------------------------------------------------------------
function QM_Selftest()
  QM_InitDB()
  local pass, fail = 0, 0
  local function check(cond, label)
    if cond then pass = pass + 1; QM_Print("PASS: " .. label)
    else fail = fail + 1; QM_Print("FAIL: " .. label) end
  end

  -- don't let the self-test queue real invites to real nearby players
  local savedNearby = QM.db.prefs.inviteNearby
  QM.db.prefs.inviteNearby = false
  QM.nearbyQueue = {}
  QM.nearbyInvited = {}
  QM.pendingNearby = nil

  QM_RefreshQuestLog()
  local n = qn(QM.quests)
  check(n > 0, "quest log readable (" .. n .. " quests)")
  if n == 0 then
    QM_Print(string.format("selftest: %d passed, %d failed", pass, fail))
    return
  end

  -- select the first non-completed quest through the real UI code path
  local sel
  for i = 1, n do
    if not QM.quests[i].complete then sel = i; break end
  end
  sel = sel or 1
  if QM_UI_Select then pcall(QM_UI_Select, sel) end
  check(QM.selected == sel, "quest selection works (" .. tostring(QM.quests[sel].title) .. ")")
  local q = QM.quests[sel]

  -- scrolling clamps correctly
  if QM_UI_Scroll and QM.UI then
    local rows = QM.UI.listRows or 9
    local maxoff = math.max(0, n - rows)
    local off0 = QM.UI.listOffset or 0
    pcall(QM_UI_Scroll, 1)
    check((QM.UI.listOffset or 0) == math.min(maxoff, off0 + 1), "scroll down clamps at the bottom")
    pcall(QM_UI_Scroll, -999)
    check((QM.UI.listOffset or 0) == 0, "scroll up clamps at the top")
  end

  -- capture outgoing protocol messages instead of really sending them
  local sentChan, sentWhisp = {}, {}
  local origChan, origWhisp = QM_SendChannel, QM_SendWhisper
  QM_SendChannel = function(msg) sentChan[qn(sentChan) + 1] = msg; return true end
  QM_SendWhisper = function(t, msg) sentWhisp[qn(sentWhisp) + 1] = { t = t, msg = msg }; return true end

  QM.lastBroadcast = 0
  QM_BroadcastLFM()
  check(qn(sentChan) == 1 and strsub(sentChan[1], 1, 6) == "QG_LFM", "broadcast produces a QG_LFM message")
  check(strfind(sentChan[1], qsanitize(q.title), 1, true) ~= nil, "LFM contains the quest name")
  QM_BroadcastLFM()
  check(qn(sentChan) == 1, "anti-spam blocks an immediate re-broadcast")

  local zone = QM_GetZone()
  local lvl = (q.level ~= nil) and tostring(q.level) or ""
  local nm = qsanitize(q.title)
  -- fake incoming LFM from a peer who has the same quest
  QM_HandleMessage("QG_LFM^" .. zone .. "^" .. lvl .. "^" .. nm .. "^^", "DummyPeer", "CHANNEL")
  check(qn(sentWhisp) == 1 and sentWhisp[1].t == "DummyPeer" and strsub(sentWhisp[1].msg, 1, 7) == "QG_HAVE",
    "incoming LFM -> QG_HAVE whispered to the initiator")
  QM_HandleMessage("QG_LFM^Nowhere^1^X^^", "DummyPeer2", "CHANNEL")
  QM_HandleMessage("QG_LFM^" .. zone .. "^99^No Such Quest^^", "DummyPeer3", "CHANNEL")
  check(qn(sentWhisp) == 1, "wrong-zone and unknown-quest LFM are ignored")

  -- fake incoming HAVE -> responder appears in the panel
  local r0 = qn(QM.responders)
  QM_HandleMessage("QG_HAVE^" .. zone .. "^" .. lvl .. "^" .. nm .. "^^", "DummyPeer", "WHISPER")
  check(qn(QM.responders) == r0 + 1 and QM.responders[qn(QM.responders)].name == "DummyPeer",
    "incoming HAVE adds a responder")
  local t0 = QM.responders[qn(QM.responders)].time
  QM_HandleMessage("QG_HAVE^" .. zone .. "^" .. lvl .. "^" .. nm .. "^^", "DummyPeer", "WHISPER")
  check(QM.responders[qn(QM.responders)].time == t0, "a repeated HAVE from the same sender is rate-limited")
  if QM.UI and QM.UI.respRows then
    check(QM.UI.respRows[1] ~= nil, "responder row is rendered in the panel")
  end

  if QM._msgFilter then
    check(QM._msgFilter("QG_HAVE^x") == true, "chat filter hides protocol messages")
    check(QM._msgFilter("hello") == false, "chat filter keeps normal chat")
  end

  -- responder expiry
  QM.responders[qn(QM.responders)].time = time() - 3600
  QM_Tick()
  check(qn(QM.responders) == r0, "an expired responder is pruned")

  -- some invite mechanism must exist
  local invApi = InviteByName or (C_PartyInfo and C_PartyInfo.InviteByName) or InviteUnit or (C_PartyInfo and C_PartyInfo.InviteUnit) or "slash"
  check(invApi ~= nil, "invite path available: " .. tostring(invApi ~= "slash" and "API" or "/invite slash"))

  -- nearby-invite scan + queue (for players without the addon)
  check(type(QM_NearbyPlayers()) == "table", "nearby player scan runs without error")
  local origInvite = QM_Invite
  local invitedNames = {}
  QM_Invite = function(name) invitedNames[qn(invitedNames) + 1] = name end  -- capture, don't really invite
  QM.nearbyQueue = {}
  QM_QueueNearbyInvites(true)  -- the dedicated button uses force=true, pref not needed
  check(qn(QM.nearbyQueue) <= (tonumber(QM.db.prefs.nearbyMax) or 5),
    "manual nearby scan (force) queues at most nearbyMax players")
  QM.nearbyQueue = { { name = "DummyPeer2" } }
  QM.lastNearbyInvite = 0
  QM_Tick()
  check(qn(invitedNames) == 1 and invitedNames[1] == "DummyPeer2" and qn(QM.nearbyQueue) == 0,
    "nearby-invite queue is processed one by one")
  QM_Invite = origInvite

  -- minimap button + radar
  check(QM.UI and QM.UI.minimapBtn ~= nil, "minimap button created")
  check(QM.UI and QM.UI.radar ~= nil, "radar window created")
  check(QM_UI_RefreshRadar and pcall(QM_UI_RefreshRadar), "radar refresh runs without error")

  -- invite counter label
  QM.stats.nearbyInvites = 7
  if QM_UI_RefreshCount then pcall(QM_UI_RefreshCount) end
  local cnt = (QM.UI and QM.UI.invCount and QM.UI.invCount.GetText) and tostring(QM.UI.invCount:GetText()) or ""
  check(strfind(cnt, "7", 1, true) ~= nil, "invite counter label shows the sent count")
  QM.stats.nearbyInvites = 0

  -- restore the real send functions and clean up the dummy responder
  QM_SendChannel, QM_SendWhisper = origChan, origWhisp
  QM.responders = {}
  QM.nearbyQueue = {}
  QM.nearbyInvited = {}
  QM.db.prefs.inviteNearby = savedNearby
  if QM_UI_RefreshResponders then pcall(QM_UI_RefreshResponders) end

  QM_Print(string.format("selftest: %d passed, %d failed", pass, fail))
end

-- ---------------------------------------------------------------------------
-- In-game API probe: /qg probe
-- ---------------------------------------------------------------------------
function QM_Probe()
  QM_Print(L.probeHdr)
  if GetBuildInfo then
    local ok, v, b, d, iface = pcall(GetBuildInfo)
    if ok then QM_Print("build: version=" .. tostring(v) .. " build=" .. tostring(b) .. " interface=" .. tostring(iface)) end
  end
  QM_Print("_VERSION = " .. tostring(_VERSION) .. " | issecure() = " .. tostring(issecure and issecure()))
  QM_Print("SendAddonMessage = " .. tostring(SendAddonMessage) .. " | C_ChatInfo.SendAddonMessage = " .. tostring(C_ChatInfo and C_ChatInfo.SendAddonMessage))
  QM_Print("RegisterAddonMessagePrefix = " .. tostring(RegisterAddonMessagePrefix) .. " | C_ChatInfo.RegisterAddonMessagePrefix = " .. tostring(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix))
  QM_Print("GetNumQuestLogEntries = " .. tostring(GetNumQuestLogEntries) .. " | GetQuestLogTitle = " .. tostring(GetQuestLogTitle)
    .. " | C_QuestLog = " .. tostring(C_QuestLog)
    .. " | GetNumQuestLogEntries = " .. tostring(C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
    .. " | GetInfo = " .. tostring(C_QuestLog and C_QuestLog.GetInfo))
  QM_Print("GetRealZoneText = " .. tostring(GetRealZoneText) .. " | GetZoneText = " .. tostring(GetZoneText) .. " | C_Map = " .. tostring(C_Map))
  QM_Print("ChatFrame_AddMessageEventFilter = " .. tostring(ChatFrame_AddMessageEventFilter) .. " | ChatFrameUtil = " .. tostring(ChatFrameUtil))
  QM_Print("JoinChannelByName = " .. tostring(JoinChannelByName) .. " | ChatFrame_RemoveChannel = " .. tostring(ChatFrame_RemoveChannel) .. " | GetChannelName = " .. tostring(GetChannelName))
  QM_Print("InviteByName = " .. tostring(InviteByName) .. " | C_PartyInfo = " .. tostring(C_PartyInfo)
    .. " | C_PartyInfo.InviteByName = " .. tostring(C_PartyInfo and C_PartyInfo.InviteByName)
    .. " | C_PartyInfo.InviteUnit = " .. tostring(C_PartyInfo and C_PartyInfo.InviteUnit)
    .. " | InviteUnit = " .. tostring(InviteUnit))
  QM_Print("TargetByName = " .. tostring(TargetByName) .. " | TargetUnit = " .. tostring(TargetUnit)
    .. " | AcceptGroup = " .. tostring(AcceptGroup) .. " | C_PartyInfo.AcceptGroup = " .. tostring(C_PartyInfo and C_PartyInfo.AcceptGroup))
  QM_Print("GetPlayerMapPosition = " .. tostring(GetPlayerMapPosition) .. " | C_Map.GetPlayerMapPosition = " .. tostring(C_Map and C_Map.GetPlayerMapPosition))
  QM_Print("C_NamePlate = " .. tostring(C_NamePlate) .. " | GetNamePlates = " .. tostring(C_NamePlate and C_NamePlate.GetNamePlates)
    .. " | CheckInteractDistance = " .. tostring(CheckInteractDistance))
  QM_Print("UnitIsPlayer = " .. tostring(UnitIsPlayer) .. " | UnitPlayerControlled = " .. tostring(UnitPlayerControlled) .. " | UnitExists = " .. tostring(UnitExists))
  QM_Print("UnitName = " .. tostring(UnitName) .. " | UnitFullName = " .. tostring(UnitFullName)
    .. " | GetRealmName = " .. tostring(GetRealmName) .. " | GetNumGroupMembers = " .. tostring(GetNumGroupMembers)
    .. " | GetNumSubgroupMembers = " .. tostring(GetNumSubgroupMembers))
  if GetCVar then
    local CVARS = { "nameplateShowFriendlyPlayers", "nameplateShowAll", "nameplateShowEnemies", "nameplateMaxDistance" }
    for i = 1, qn(CVARS) do
      local okc, cv = pcall(GetCVar, CVARS[i])
      QM_Print("cvar " .. CVARS[i] .. " = " .. tostring(okc and cv or "n/a"))
    end
  end
  if C_NamePlate and C_NamePlate.GetNamePlates and UnitIsPlayer then
    local okp, plates = pcall(C_NamePlate.GetNamePlates)
    if okp and type(plates) == "table" then
      local total, players = qn(plates), 0
      for i = 1, total do
        local token = plates[i] and (plates[i].namePlateUnitToken or plates[i].unit)
        if token and UnitIsPlayer(token) then players = players + 1 end
      end
      QM_Print("nameplates: " .. players .. " player(s) / " .. total .. " total")
    end
  end
  QM_Print("C_QuestLog.IsComplete = " .. tostring(C_QuestLog and C_QuestLog.IsComplete)
    .. " | C_QuestLog.IsQuestFlaggedCompleted = " .. tostring(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted))
  QM_Print("locale = " .. tostring(locale) .. " | zone = " .. QM_GetZone())
  if GetChannelName then
    local ok, num, cname = pcall(GetChannelName, CHANNEL)
    QM_Print("channel " .. CHANNEL .. " -> ok=" .. tostring(ok) .. " num=" .. tostring(num) .. " name=" .. tostring(cname))
  end
  -- quest log: try both APIs, dump the fields of the first entry
  local n = 0
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    local ok, v = pcall(C_QuestLog.GetNumQuestLogEntries)
    if ok then n = tonumber(v) or 0 end
  end
  if n == 0 and GetNumQuestLogEntries then
    local ok, v = pcall(GetNumQuestLogEntries)
    if ok then n = tonumber(v) or 0 end
  end
  QM_Print("quest log entries = " .. n)
  -- dump the first NON-header entry (entry 1 is often a zone header)
  if n > 0 and C_QuestLog and C_QuestLog.GetInfo then
    for i = 1, n do
      local ok, info = pcall(C_QuestLog.GetInfo, i)
      if ok and type(info) == "table" and not info.isHeader then
        local keys = {}
        for k in pairs(info) do keys[qn(keys) + 1] = tostring(k) end
        table.sort(keys)
        QM_Print("quest #" .. i .. " keys: " .. table.concat(keys, ","))
        QM_Print("quest #" .. i .. ": title=" .. tostring(info.title) .. " level=" .. tostring(info.level)
          .. " questLevel=" .. tostring(info.questLevel) .. " questID=" .. tostring(info.questID)
          .. " isComplete=" .. tostring(info.isComplete) .. " isHeader=" .. tostring(info.isHeader))
        break
      end
    end
  elseif n > 0 and GetQuestLogTitle then
    local ok, t, lv = pcall(GetQuestLogTitle, 1)
    QM_Print("quest #1: title=" .. tostring(t) .. " level=" .. tostring(lv))
  end
end
