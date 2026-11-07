-- ============================================================================
-- QuestMates - UI (window, scrollable quest list, responders panel, options)
--
-- Loaded after QuestMates.lua (see the .toc). Everything is built with plain
-- CreateFrame calls so it works on old and modern clients alike: no XML
-- templates, no Ace. Textures use Interface\Tooltips\UI-Tooltip-Background
-- and the FRIZQT__ font, which exist on every client.
-- ============================================================================

local QM = QuestMates
if not QM then return end
local L = QM.L
local function qn(t) return table.getn(t) end

-- layout ---------------------------------------------------------------------
local W, H        = 300, 458
local ROW_H       = 16
local LIST_ROWS   = 9
local LIST_W      = W - 40
local LIST_H      = ROW_H * LIST_ROWS
local RESP_ROWS   = 5
local RESP_H      = 20

local Y_TITLE = -6
local Y_BCAST = -28
local Y_SEL   = -54
local Y_QHDR  = -70
local Y_LIST  = -84
local Y_RHDR  = Y_LIST - LIST_H - 6                 -- -234
local Y_RROW0 = Y_RHDR - 14                          -- -248
local Y_OPT0  = Y_RROW0 - RESP_ROWS * RESP_H - 8     -- -356
local Y_OPT1  = Y_OPT0 - 18                          -- -374
local Y_OPT2  = Y_OPT1 - 18                          -- -392
local Y_OPT3  = Y_OPT2 - 18                          -- -410
local Y_OPT4  = Y_OPT3 - 18                          -- -428
local Y_COUNT = Y_OPT4 - 15                          -- -443

local RADAR_S   = 140   -- radar window size
local RADAR_DOTS = 12

local UI = {}
QM.UI = UI

-- small helpers ---------------------------------------------------------------
local function allpoints(tex, parent)
  if tex.SetAllPoints then
    tex:SetAllPoints(parent)
  else
    tex:SetPoint("TOPLEFT", parent, "TOPLEFT")
    tex:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
  end
end

local function newfs(parent, size)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  if fs.SetFont then pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", size or 11) end
  return fs
end

local function newbg(parent, r, g, b, a)
  local t = parent:CreateTexture(nil, "BACKGROUND")
  t:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  t:SetVertexColor(r, g, b, a)
  allpoints(t, parent)
  return t
end

-- thin 1px border around a frame (purely visual; fails silently if unsupported)
local function addborder(fr)
  local function mk()
    local t = fr:CreateTexture(nil, "BORDER")
    t:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    t:SetVertexColor(0.55, 0.55, 0.65, 1)
    return t
  end
  local top = mk()
  top:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", fr, "TOPRIGHT", 0, 0)
  pcall(top.SetHeight, top, 1)
  local bottom = mk()
  bottom:SetPoint("BOTTOMLEFT", fr, "BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", 0, 0)
  pcall(bottom.SetHeight, bottom, 1)
  local left = mk()
  left:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", fr, "BOTTOMLEFT", 0, 0)
  pcall(left.SetWidth, left, 1)
  local right = mk()
  right:SetPoint("TOPRIGHT", fr, "TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", 0, 0)
  pcall(right.SetWidth, right, 1)
end

local function makebutton(parent, w, h, text, onClick, tip)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w)
  b:SetHeight(h)
  local bg = newbg(b, 0.25, 0.25, 0.32, 0.9)
  local fs = newfs(b, 11)
  fs:SetPoint("CENTER", b, "CENTER")
  if text then fs:SetText(text) end
  if b.SetFontString then pcall(b.SetFontString, b, fs) end
  b:SetScript("OnClick", function() onClick(b) end)
  b:SetScript("OnEnter", function()
    bg:SetVertexColor(0.45, 0.45, 0.62, 0.95)
    if tip and GameTooltip then
      pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_TOP")
      pcall(GameTooltip.AddLine, GameTooltip, tip)
      pcall(GameTooltip.Show, GameTooltip)
    end
  end)
  b:SetScript("OnLeave", function()
    bg:SetVertexColor(0.25, 0.25, 0.32, 0.9)
    if tip and GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
  end)
  b._bg = bg
  return b
end

-- build the window (called once from the core on ADDON_LOADED) -----------------
function QuestMates_BuildUI()
  if UI.frame then return end
  QM_InitDB()

  local f = CreateFrame("Frame", "QuestMatesFrame", UIParent)
  f:SetWidth(W)
  f:SetHeight(H)
  -- restore saved position, or center the window on first run
  -- (a fresh (0,0) position would hide it behind the chat frames)
  if QM.db.posSet and type(QM.db.pos) == "table" and QM.db.pos.x then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", QM.db.pos.x, QM.db.pos.y)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  if f.SetFrameStrata then f:SetFrameStrata("HIGH") end  -- never hidden behind chat frames
  if f.SetToplevel then f:SetToplevel(true) end
  newbg(f, 0.05, 0.05, 0.09, 0.93)
  if f.SetMovable then f:SetMovable(true) end
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    QM_UI_SavePos()
    QM_UI_Clamp()
  end)
  addborder(f)
  UI.frame = f

  -- child container frames (list, responder rows) intercept left-clicks by
  -- default, which would make most of the window undraggable: forward their
  -- drags to the main window (buttons on top of them keep their own clicks)
  local function forwardDrag(child)
    child:EnableMouse(true)
    child:RegisterForDrag("LeftButton")
    child:SetScript("OnDragStart", function() f:StartMoving() end)
    child:SetScript("OnDragStop", function()
      f:StopMovingOrSizing()
      QM_UI_SavePos()
      QM_UI_Clamp()
    end)
  end
  UI.forwardDrag = forwardDrag

  -- title bar + close button
  local title = newfs(f, 13)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, Y_TITLE)
  title:SetText(L.title)
  title:SetTextColor(1, 0.82, 0)
  local close = makebutton(f, 18, 18, "X", function() f:Hide() end)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

  -- two action buttons: LFM broadcast (addon users) + invite nearby (everyone)
  local bw = math.floor((W - 20) / 2)
  local bcast = makebutton(f, bw, 22, L.broadcast, function() QM_BroadcastLFM() end, L.tipBroadcast)
  bcast:SetPoint("TOPLEFT", f, "TOPLEFT", 8, Y_BCAST)
  local bnear = makebutton(f, bw, 22, L.inviteNearbyBtn, function() QM_QueueNearbyInvites(true) end, L.tipNearby)
  bnear:SetPoint("TOPLEFT", bcast, "TOPRIGHT", 4, 0)
  UI.bcast, UI.bnear = bcast, bnear
  -- cooldown label (right of the selected-quest line) + selected quest label
  local cd = newfs(f, 10)
  cd:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, Y_SEL + 2)
  cd:SetWidth(90)
  if cd.SetJustifyH then cd:SetJustifyH("RIGHT") end
  cd:SetTextColor(0.7, 0.7, 0.7)
  UI.cd = cd
  local sel = newfs(f, 11)
  sel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, Y_SEL)
  sel:SetWidth(W - 110)
  if sel.SetJustifyH then sel:SetJustifyH("LEFT") end
  UI.sel = sel

  -- quest list header + scrollable list (mouse wheel + up/down buttons)
  local qh = newfs(f, 11)
  qh:SetPoint("TOPLEFT", f, "TOPLEFT", 8, Y_QHDR)
  qh:SetTextColor(1, 0.82, 0)
  UI.qh = qh

  local list = CreateFrame("Frame", nil, f)
  list:SetWidth(LIST_W)
  list:SetHeight(LIST_H)
  list:SetPoint("TOPLEFT", f, "TOPLEFT", 8, Y_LIST)
  newbg(list, 0, 0, 0, 0.45)
  if list.EnableMouseWheel then
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
      if delta == nil then delta = arg1 end  -- legacy style
      local d = tonumber(delta)
      if d then QM_UI_Scroll(-d) end          -- wheel up => show earlier quests
    end)
  end
  UI.list = list
  forwardDrag(list)  -- grabbing the quest list area drags the window (wheel still scrolls)
  UI.listOffset = 0
  UI.rows = {}
  for i = 1, LIST_ROWS do
    local b = CreateFrame("Button", nil, list)
    b:SetWidth(LIST_W)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
    local hl = b:CreateTexture(nil, "BACKGROUND")
    hl:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    hl:SetVertexColor(0.3, 0.5, 0.9, 0.35)
    allpoints(hl, b)
    hl:Hide()
    local fs = newfs(b, 11)
    fs:SetPoint("LEFT", b, "LEFT", 4, 0)
    fs:SetWidth(LIST_W - 8)
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    b:SetScript("OnClick", function()
      if QM.Debug then QM.Debug("quest row clicked, idx=" .. tostring(b._idx)) end
      if b._idx then QM_UI_Select(b._idx) end
    end)
    b._hl = hl
    b._fs = fs
    b:Hide()
    UI.rows[i] = b
  end
  UI.listRows = LIST_ROWS
  local up = makebutton(f, 16, 16, "^", function() QM_UI_Scroll(-1) end)
  up:SetPoint("TOPLEFT", list, "TOPRIGHT", 4, 0)
  local down = makebutton(f, 16, 16, "v", function() QM_UI_Scroll(1) end)
  down:SetPoint("TOPLEFT", up, "BOTTOMLEFT", 0, -2)
  UI.upBtn, UI.downBtn = up, down

  -- responders panel: name + status + Invite button
  local rh = newfs(f, 11)
  rh:SetPoint("TOPLEFT", f, "TOPLEFT", 8, Y_RHDR)
  rh:SetTextColor(1, 0.82, 0)
  UI.rh = rh
  UI.respRows = {}
  for i = 1, RESP_ROWS do
    local row = CreateFrame("Frame", nil, f)
    row:SetWidth(W - 16)
    row:SetHeight(RESP_H)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 8, Y_RROW0 - (i - 1) * RESP_H)
    local name = newfs(row, 11)
    name:SetPoint("LEFT", row, "LEFT", 2, 0)
    name:SetWidth(104)
    local status = newfs(row, 10)
    status:SetPoint("LEFT", name, "RIGHT", 6, 0)
    status:SetWidth(86)
    local inv = makebutton(row, 52, 16, L.invite, function()
      if row._resp then
        -- if the responder is visible nearby, pass their unit token (taint-safe invite path)
        local token
        local near = QM_NearbyPlayers()
        for i = 1, qn(near) do
          if near[i].name == row._resp.name then token = near[i].token; break end
        end
        QM_Invite(row._resp.name, false, token)
      end
    end)
    inv:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row._name, row._status = name, status
    forwardDrag(row)
    row:Hide()
    UI.respRows[i] = row
  end

  -- options (custom checkboxes: no templates needed)
  local function checkbox(y, label, get, set)
    local b = CreateFrame("Button", nil, f)
    b:SetWidth(14)
    b:SetHeight(14)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 8, y)
    newbg(b, 0.15, 0.15, 0.2, 1)
    local mark = newfs(b, 11)
    mark:SetPoint("CENTER", b, "CENTER")
    mark:SetText("X")
    mark:SetTextColor(0.4, 1, 0.4)
    local lbl = newfs(f, 10)
    lbl:SetPoint("LEFT", b, "RIGHT", 5, -2)
    lbl:SetText(label)
    if get() then mark:Show() else mark:Hide() end
    b:SetScript("OnClick", function()
      local v = not get()
      set(v)
      if v then mark:Show() else mark:Hide() end
    end)
  end
  checkbox(Y_OPT0, L.optAuto,   function() return QM.db.prefs.autoAnnounce  end, function(v) QM.db.prefs.autoAnnounce  = v end)
  checkbox(Y_OPT1, L.optAccept, function() return QM.db.prefs.autoAccept    end, function(v) QM.db.prefs.autoAccept    = v end)
  checkbox(Y_OPT2, L.optNearby, function() return QM.db.prefs.inviteNearby  end, function(v) QM.db.prefs.inviteNearby  = v end)
  checkbox(Y_OPT3, L.optCount,  function() return QM.db.prefs.showInviteCount end, function(v) QM.db.prefs.showInviteCount = v; QM_UI_RefreshCount() end)
  checkbox(Y_OPT4, L.optRadar,  function() return QM.db.prefs.showRadar end, function(v) QM.db.prefs.showRadar = v; QM_UI_SyncRadar() end)

  -- invite counter (how many "random"/nearby invites were sent this session)
  local invc = newfs(f, 10)
  invc:SetPoint("TOPLEFT", f, "TOPLEFT", 8, Y_COUNT)
  invc:SetTextColor(0.7, 0.9, 1)
  UI.invCount = invc

  -- backup ticker on the (visible) window: keeps the cooldown label and the
  -- responder expiry fresh even if the core event frame's OnUpdate stalls
  local uiAcc = 0
  f:SetScript("OnUpdate", function(self, elapsed)
    if elapsed == nil then elapsed = arg1 end  -- legacy style
    uiAcc = uiAcc + (tonumber(elapsed) or 0.05)
    if uiAcc >= 0.5 then
      uiAcc = 0
      pcall(QM_Tick)
    end
  end)

  f:Show()
  QM_UI_RefreshAll()
  QM_UI_BuildMinimapButton()
  QM_UI_BuildRadar()
end

-- minimap button: click toggles the window, drag moves the button around the rim
function QM_UI_BuildMinimapButton()
  if UI.minimapBtn or not Minimap then return end
  QM_InitDB()

  local b = CreateFrame("Button", "QuestMatesMinimapButton", Minimap)
  b:SetWidth(28)
  b:SetHeight(28)
  -- background is invisible by default (the round icon.tga is the button);
  -- it only appears on hover as a highlight. (A permanent opaque bg would
  -- show as a square around the round icon.)
  local mbg = newbg(b, 0.05, 0.05, 0.09, 0.0)
  local fs = newfs(b, 16)
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  fs:SetText("Q")
  fs:SetTextColor(1, 0.82, 0)
  if b.SetFontString then pcall(b.SetFontString, b, fs) end
  -- icon image (created after the text, same layer, so it covers the "Q" when
  -- it loads; if the file is missing/unreadable the texture stays blank and
  -- the gold "Q" remains visible as fallback)
  local icon = b:CreateTexture(nil, "OVERLAY")
  allpoints(icon, b)
  pcall(icon.SetTexture, icon, "Interface\\AddOns\\QuestMates\\icon.tga")
  -- z-order: the minimap's own widgets (zoom buttons, ...) sit at high frame
  -- levels, so +1 is not enough — render above all of them or the button ends
  -- up behind the minimap
  if b.SetFrameStrata then pcall(b.SetFrameStrata, b, "HIGH") end
  if Minimap.GetFrameLevel and b.SetFrameLevel then
    pcall(b.SetFrameLevel, b, Minimap:GetFrameLevel() + 100)
  elseif b.SetFrameLevel then
    pcall(b.SetFrameLevel, b, 1000)
  end

  local function frameCenter(fr)
    local x = fr:GetLeft() + fr:GetWidth() / 2
    local y
    if fr.GetBottom then y = fr:GetBottom() + fr:GetHeight() / 2
    else y = fr:GetTop() - fr:GetHeight() / 2 end
    return x, y
  end

  local function updatePos()
    local angle = tonumber(QM.db.minimapAngle) or 225
    local r = Minimap:GetWidth() / 2
    local rad = math.rad(angle)
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
  end
  updatePos()

  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnClick", function() QM_UI_Toggle() end)
  b:SetScript("OnEnter", function()
    mbg:SetVertexColor(0.05, 0.05, 0.09, 0.6)  -- hover highlight
    if GameTooltip then
      pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_LEFT")
      pcall(GameTooltip.AddLine, GameTooltip, L.title .. " - " .. L.tipMinimap)
      pcall(GameTooltip.Show, GameTooltip)
    end
  end)
  b:SetScript("OnLeave", function()
    mbg:SetVertexColor(0.05, 0.05, 0.09, 0.0)
    if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
  end)

  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function()
    b:SetScript("OnUpdate", function()
      local mx, my = GetCursorPosition()
      local scale = 1
      if UIParent.GetEffectiveScale then scale = UIParent:GetEffectiveScale()
      elseif UIParent.GetScale then scale = UIParent:GetScale() end
      mx, my = mx / scale, my / scale
      local cx, cy = frameCenter(Minimap)
      local angle = math.deg(math.atan2(my - cy, mx - cx))
      if angle < 0 then angle = angle + 360 end
      QM.db.minimapAngle = angle
      updatePos()
    end)
  end)
  b:SetScript("OnDragStop", function()
    b:SetScript("OnUpdate", nil)  -- angle is already in SavedVariables
  end)

  UI.minimapBtn = b
end

-- window position --------------------------------------------------------------
function QM_UI_SavePos()
  if not UI.frame then return end
  QM_InitDB()
  local x, y = UI.frame:GetLeft(), UI.frame:GetTop()
  if x and y then
    if type(QM.db.pos) ~= "table" then QM.db.pos = {} end
    QM.db.pos.x, QM.db.pos.y = x, y
    QM.db.posSet = true
  end
end

function QM_UI_Clamp()
  local f = UI.frame
  if not f then return end
  local x, y = f:GetLeft(), f:GetTop()
  local w, h = f:GetWidth(), f:GetHeight()
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  if not x or not y or not sw or not sh then return end
  if x < 0 then x = 0 end
  if y < 0 then y = 0 end
  if w and x + w > sw then x = sw - w end
  if h and y + h > sh then y = sh - h end
  if f.ClearAllPoints then f:ClearAllPoints() end
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

function QM_UI_Toggle()
  if UI.frame then
    if UI.frame:IsVisible() then UI.frame:Hide() else UI.frame:Show() end
    QM_UI_SyncRadar()
  end
end

function QM_UI_Show(on)
  if UI.frame then
    if on then
      UI.frame:Show()
      if UI.frame.Raise then UI.frame:Raise() end  -- bring to front, above chat frames
    else
      UI.frame:Hide()
    end
    QM_UI_SyncRadar()
  end
end

-- ---------------------------------------------------------------------------
-- Radar window: shows nearby players (within nameplate range) around the player
-- ---------------------------------------------------------------------------
function QM_UI_BuildRadar()
  if UI.radar then return end  -- radar parents to UIParent, Minimap not needed here
  QM_InitDB()
  local r = CreateFrame("Frame", "QuestMatesRadarFrame", UIParent)
  r:SetWidth(RADAR_S)
  r:SetHeight(RADAR_S)
  if QM.db.radarPosSet and type(QM.db.radarPos) == "table" and QM.db.radarPos.x then
    r:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", QM.db.radarPos.x, QM.db.radarPos.y)
  else
    r:SetPoint("CENTER", UIParent, "CENTER", 220, 40)
  end
  if r.SetFrameStrata then r:SetFrameStrata("HIGH") end
  if r.SetToplevel then r:SetToplevel(true) end
  newbg(r, 0.04, 0.06, 0.04, 0.85)
  addborder(r)
  if r.SetMovable then r:SetMovable(true) end
  r:EnableMouse(true)
  r:RegisterForDrag("LeftButton")
  r:SetScript("OnDragStart", function() r:StartMoving() end)
  r:SetScript("OnDragStop", function()
    r:StopMovingOrSizing()
    local x, y = r:GetLeft(), r:GetTop()
    if x and y then
      if type(QM.db.radarPos) ~= "table" then QM.db.radarPos = {} end
      QM.db.radarPos.x, QM.db.radarPos.y = x, y
      QM.db.radarPosSet = true
    end
  end)
  local title = newfs(r, 10)
  title:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -3)
  title:SetTextColor(1, 0.82, 0)
  UI.radarTitle = title
  -- center cross
  local function line(w, h)
    local t = r:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    t:SetVertexColor(0.3, 0.4, 0.3, 0.6)
    t:SetWidth(w)
    t:SetHeight(h)
    t:SetPoint("CENTER", r, "CENTER", 0, 0)
  end
  line(RADAR_S - 8, 1)
  line(1, RADAR_S - 8)
  -- self dot (center, gold)
  local selfdot = r:CreateTexture(nil, "OVERLAY")
  selfdot:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
  selfdot:SetVertexColor(1, 0.82, 0)
  selfdot:SetWidth(5)
  selfdot:SetHeight(5)
  selfdot:SetPoint("CENTER", r, "CENTER", 0, 0)
  -- player dots (green)
  UI.radarDots = {}
  for i = 1, RADAR_DOTS do
    local t = r:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
    t:SetVertexColor(0.4, 1, 0.4, 1)
    t:SetWidth(6)
    t:SetHeight(6)
    t:Hide()
    UI.radarDots[i] = t
  end
  UI.radar = r
  QM_UI_SyncRadar()
  QM_UI_RefreshRadar()
end

-- radar follows the main window + the option
function QM_UI_SyncRadar()
  if not UI.radar then return end
  QM_InitDB()
  local show = QM.db.prefs.showRadar and UI.frame ~= nil and UI.frame:IsVisible()
  if show then UI.radar:Show() else UI.radar:Hide() end
end

local function inRange(token, idx)
  if not CheckInteractDistance then return false end
  local ok, res = pcall(CheckInteractDistance, token, idx)
  return (ok and res) and true or false
end

function QM_UI_RefreshRadar()
  if not UI.radar then return end
  QM_InitDB()
  local players = QM_NearbyPlayers()
  local n = qn(players)
  -- outer ring = nameplate range (nameplateMaxDistance cvar if readable, else 45)
  local maxDist = 45
  if GetCVar then
    local ok, v = pcall(GetCVar, "nameplateMaxDistance")
    if ok and tonumber(v) then maxDist = tonumber(v) end
  end
  if UI.radarTitle then
    UI.radarTitle:SetText(string.format(L.radarTitle, n, math.floor(maxDist)))
  end
  local sx, sy = QM_MapPos("player")
  local half = RADAR_S / 2 - 10
  local rings = { 0.18, 0.42, 0.68, 0.95 }  -- distance buckets -> ring radius fraction
  for i = 1, RADAR_DOTS do
    local dot = UI.radarDots[i]
    if i <= n then
      local p = players[i]
      local ring = 4  -- outermost: within nameplate range
      if inRange(p.token, 4) then ring = 1
      elseif inRange(p.token, 3) then ring = 2
      elseif inRange(p.token, 2) then ring = 3
      end
      -- direction from map coordinates (fallback: north)
      local ang = 0
      local ux, uy = QM_MapPos(p.token)
      if sx and sy and ux and uy and (ux ~= 0 or uy ~= 0) then
        ang = math.atan2(uy - sy, ux - sx)
      end
      local rr = rings[ring] * half
      dot:SetPoint("CENTER", UI.radar, "CENTER", math.cos(ang) * rr, math.sin(ang) * rr)
      dot:Show()
    else
      dot:Hide()
    end
  end
end

-- quest list -------------------------------------------------------------------
-- positive delta scrolls down the list
function QM_UI_Scroll(delta)
  local n = qn(QM.quests)
  local maxoff = math.max(0, n - LIST_ROWS)
  UI.listOffset = math.max(0, math.min(maxoff, (UI.listOffset or 0) + delta))
  if QM.Debug then QM.Debug("scroll delta=" .. tostring(delta) .. " -> offset=" .. tostring(UI.listOffset)) end
  QM_UI_RefreshList()
end

function QM_UI_Select(idx)
  QM.selected = idx
  if QM.Debug then QM.Debug("select quest idx=" .. tostring(idx)) end
  QM_UI_RefreshList()
  QM_UI_RefreshSel()
end

function QM_UI_RefreshSel()
  if not UI.sel then return end
  local q = QM.selected and QM.quests[QM.selected]
  UI.sel:SetText(string.format(L.selLabel, q and q.title or L.none))
  QM_UI_Tick()
end

function QM_UI_RefreshList()
  if not UI.rows then return end
  local qs = QM.quests
  local n = qn(qs)
  if UI.qh then UI.qh:SetText(string.format(L.questsHdr, n)) end
  local maxoff = math.max(0, n - LIST_ROWS)
  if (UI.listOffset or 0) > maxoff then UI.listOffset = maxoff end
  local off = UI.listOffset or 0
  for i = 1, LIST_ROWS do
    local b = UI.rows[i]
    local qi = off + i
    if qi <= n then
      local q = qs[qi]
      b._idx = qi
      local txt = q.title or "?"
      if q.level ~= nil then txt = "[" .. tostring(q.level) .. "] " .. txt end
      if q.complete then txt = txt .. " " .. L.complete end
      b._fs:SetText(txt)
      if qi == QM.selected then b._hl:Show() else b._hl:Hide() end
      b:Show()
    else
      b._idx = nil
      b:Hide()
    end
  end
  -- scroll buttons stay clickable (clicks clamp at the bounds); just dim them
  -- visually when there is nothing to scroll to, instead of Disable() which
  -- would swallow the clicks and make them feel dead
  if UI.upBtn and UI.upBtn._bg then
    if off <= 0 then UI.upBtn._bg:SetVertexColor(0.12, 0.12, 0.16, 0.9) else UI.upBtn._bg:SetVertexColor(0.25, 0.25, 0.32, 0.9) end
    if off >= maxoff then UI.downBtn._bg:SetVertexColor(0.12, 0.12, 0.16, 0.9) else UI.downBtn._bg:SetVertexColor(0.25, 0.25, 0.32, 0.9) end
  end
end

-- responders panel ---------------------------------------------------------------
function QM_UI_RefreshResponders()
  if not UI.respRows then return end
  local rs = QM.responders
  local n = qn(rs)
  if UI.rh then UI.rh:SetText(string.format(L.responders, n)) end
  local zone = QM_GetZone()
  local party = QM_PartySet()
  for i = 1, RESP_ROWS do
    local row = UI.respRows[i]
    if i <= n then
      local r = rs[i]
      row._resp = r
      row._name:SetText(r.name or "?")
      local st, cr, cg, cb
      if party[r.name] then
        st, cr, cg, cb = L.statusGroup, 0.4, 1, 0.4          -- already in our group
      elseif r.zone and r.zone ~= "" and zone ~= "" and r.zone ~= zone then
        st, cr, cg, cb = L.statusZone, 1, 0.4, 0.4           -- wrong zone
      else
        st, cr, cg, cb = L.statusOK, 1, 1, 1                 -- ok
      end
      row._status:SetText(st)
      row._status:SetTextColor(cr, cg, cb)
      row:Show()
    else
      row._resp = nil
      row:Hide()
    end
  end
end

-- periodic refresh of the broadcast cooldown label
function QM_UI_Tick()
  if not UI.cd then return end
  QM_InitDB()
  local wait = QM.db.prefs.minDelay - (time() - QM.lastBroadcast)
  if wait > 0 then
    UI.cd:SetText(string.format(L.waitShort, math.ceil(wait)))
  else
    UI.cd:SetText("")
  end
end

function QM_UI_RefreshCount()
  if not UI.invCount then return end
  QM_InitDB()
  UI.invCount:SetText(string.format(L.invCount, (QM.stats and QM.stats.nearbyInvites) or 0))
  if QM.db.prefs.showInviteCount then UI.invCount:Show() else UI.invCount:Hide() end
end

function QM_UI_RefreshAll()
  QM_UI_RefreshSel()
  QM_UI_RefreshList()
  QM_UI_RefreshResponders()
  QM_UI_RefreshCount()
  QM_UI_RefreshRadar()
end
