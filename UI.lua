-- Writ Planner: standalone window (opens anywhere; does not close or move other windows).

local ADDON, ns = ...

local floor, max, min, tonumber, ipairs, pairs = math.floor, math.max, math.min, tonumber, ipairs, pairs
local tinsert = table.insert

local W, H, NAVW, ROWH = 820, 540, 150, 24
local C = { -- palette matches the website
  bg = { 0.047, 0.051, 0.071 }, panel = { 0.075, 0.067, 0.059 }, line = { 0.188, 0.169, 0.153 },
  title = "|cffe9bd78", ink = "|cfff3ebe2", mute = "|cffc6b8aa", good = "|cff5cc96b", warn = "|cffff9a3c",
}
local DANGER = { rd = "|cffff4d4d", ["or"] = "|cffff9a3c", ye = "|cfff2e05a", gr = "|cff5cc96b", gy = "|cffb4bac1" }
local TIERC = { Journeyman = "|cff9fd3ff", Artisan = "|cffc9a0ff", Expert = "|cffffb15c" }
local MODES = { "both", "item", "writ" }
local MODE_LABEL = { both = "Buy writ + item", item = "Buy item only", writ = "Buy writ only" }

local hasBackdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
local function Skin(f, bg, a)
  if not f.SetBackdrop then return end
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  local c = bg or C.panel
  f:SetBackdropColor(c[1], c[2], c[3], a or 0.97)
  f:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
end

local function Text(parent, template, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function Button(parent, label, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function Edit(parent, w, numeric)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, 20)
  e:SetAutoFocus(false)
  e:SetNumeric(numeric and true or false)
  e:SetMaxLetters(numeric and 7 or 40)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  return e
end

local function Label(parent, text, anchor, x)
  local fs = Text(parent, "GameFontNormalSmall")
  fs:SetText(text)
  fs:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", x or 0, 2)
  return fs
end

local function Tooltip(owner, fn)
  owner:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fn(self, GameTooltip)
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", GameTooltip_Hide)
end

local SRC_SHORT = { auctionator = "Auctionator", tsm = "TSM", goldscout = "GoldScout", scan = "WP scan", snapshot = "snapshot" }
local function WritTooltip(w, tt)
  tt:AddLine(w.name, 0.91, 0.74, 0.47)
  tt:AddLine(("%s%s|r  ·  +%d rep"):format(TIERC[w.tier] or "", w.tier, w.rep), 1, 1, 1)
  tt:AddLine(("Hand in: %d × %s"):format(w.qty or 1, w.item), 0.95, 0.92, 0.89)
  if w.npc then
    tt:AddLine(("Turn in to %s, %s (%.1f, %.1f)"):format(w.npc, w.zone or "?", w.x or 0, w.y or 0), 0.78, 0.72, 0.67)
  else
    tt:AddLine("Turn-in NPC unknown: check in game", 1, 0.6, 0.24)
  end
  if w.lo then tt:AddLine(("Zone level %d–%d"):format(w.lo, w.hi), 0.78, 0.72, 0.67) end
  tt:AddLine(" ")
  tt:AddDoubleLine("Item each", ns.Money(w.pItem) .. "  |cff8a8178" .. (SRC_SHORT[w.sItem] or "") .. "|r", 0.78, 0.72, 0.67)
  tt:AddDoubleLine("Writ", ns.Money(w.pWrit) .. "  |cff8a8178" .. (SRC_SHORT[w.sWrit] or "") .. "|r", 0.78, 0.72, 0.67)
  local li, lw = ns.ListedQty(w.iid), ns.ListedQty(w.wid)
  if li or lw then tt:AddDoubleLine("Listed on AH", ("item %s · writ %s"):format(li or "?", lw or "?"), 0.78, 0.72, 0.67, 1, 1, 1) end
  tt:AddDoubleLine("In bags", ("writ %d · item %d"):format(w.haveWrit or 0, w.haveItem or 0), 0.78, 0.72, 0.67, 1, 1, 1)
  if not w.factionOk then tt:AddLine("Game data lists rep for " .. w.only .. " only", 1, 0.3, 0.3) end
  if w.done then tt:AddLine("Turned in today", 0.36, 0.79, 0.42) end
  if (w.haveWrit or 0) > 1 then
    tt:AddLine(("You have %d copies: only 1 can be handed in today."):format(w.haveWrit), 1, 0.6, 0.24, true)
  end
  tt:AddLine("One hand-in per day for each named writ. Extra copies wait for another day.", 0.54, 0.51, 0.47, true)
end

---------------------------------------------------------------------------
-- Scroll list helper (rows are created once and reused)
---------------------------------------------------------------------------
local function CreateList(parent, width, build, update)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(width, 1)
  sf:SetScrollChild(child)
  sf.rows, sf.data = {}, {}
  function sf:SetData(data)
    self.data = data
    for i, d in ipairs(data) do
      local r = self.rows[i]
      if not r then
        r = CreateFrame("Button", nil, child)
        r:SetSize(width, ROWH)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROWH)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.6, 0.06)
        local stripe = r:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
        build(r)
        self.rows[i] = r
      end
      update(r, d, i)
      r:Show()
    end
    for i = #data + 1, #self.rows do self.rows[i]:Hide() end
    child:SetHeight(max(1, #data * ROWH))
  end
  return sf
end

---------------------------------------------------------------------------
-- Main frame
---------------------------------------------------------------------------
local F = CreateFrame("Frame", "WritPlannerFrame", UIParent, hasBackdrop)
ns.UI = F
F:Hide()
F:SetSize(W, H)
F:SetPoint("CENTER")
F:SetFrameStrata("MEDIUM")
F:SetToplevel(true)
F:SetClampedToScreen(true)
F:SetMovable(true)
F:EnableMouse(true)
F:RegisterForDrag("LeftButton")
F:SetScript("OnDragStart", F.StartMoving)
F:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  ns.db.pos = { p, rp, x, y }
end)
Skin(F, C.bg, 0.96)
tinsert(UISpecialFrames, "WritPlannerFrame") -- Esc closes it, like other standalone windows

local title = Text(F, "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 14, -12)
title:SetText(C.title .. "Writ Planner|r")
local sub = Text(F, "GameFontDisableSmall")
sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
local topNote = Text(F, "GameFontHighlightSmall")
topNote:SetPoint("LEFT", sub, "RIGHT", 16, 0)
topNote:SetPoint("RIGHT", F, "RIGHT", -34, 0)
local titleScan = CreateFrame("Button", nil, F, "UIPanelButtonTemplate")
titleScan:SetSize(110, 20)
titleScan:SetPoint("TOPRIGHT", -32, -10)
titleScan:SetScript("OnClick", function() if ns.Scan then ns.Scan:Start() end end)
titleScan:Hide()
topNote:SetText("|cffe9bd78Reminder:|r |cfff3ebe2each named writ: one hand-in per day. Extras wait.|r")
titleScan:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:AddLine("Scan auction house prices")
  GameTooltip:AddLine("Reads the lowest buyouts for the items Writ Planner uses. Read-only: it never buys or posts.", 1, 1, 1, true)
  GameTooltip:AddLine("For the best prices also run TSM, Auctionator or GoldScout: they scan more often and track market values.", 1, 0.82, 0, true)
  GameTooltip:Show()
end)
titleScan:SetScript("OnLeave", GameTooltip_Hide)
local close = CreateFrame("Button", nil, F, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)

-- Nav
local nav = CreateFrame("Frame", nil, F, hasBackdrop)
nav:SetPoint("TOPLEFT", 8, -40)
nav:SetPoint("BOTTOMLEFT", 8, 8)
nav:SetWidth(NAVW)
Skin(nav, C.panel)

local body = CreateFrame("Frame", nil, F, hasBackdrop)
body:SetPoint("TOPLEFT", nav, "TOPRIGHT", 6, 0)
body:SetPoint("BOTTOMRIGHT", -8, 8)
Skin(body, C.panel)
local BW = W - NAVW - 22 -- body width

local pages, navButtons, current = {}, {}, nil
local function ShowPage(key)
  current = key
  for k, p in pairs(pages) do p:SetShown(k == key) end
  for k, b in pairs(navButtons) do
    b.sel:SetShown(k == key)
    b.text:SetText((k == key and C.title or C.mute) .. b.label .. "|r")
  end
  ns.UpdateUI()
end

ns.ShowPage = function(k) ShowPage(k) end
local NAV = { { "plan", "Plan your run" }, { "exalted", "Road to Exalted" }, { "favor", "Merchant's Favor" }, { "all", "Find writs" }, { "shop", "Shopping list" }, { "settings", "Settings" } }
for i, n in ipairs(NAV) do
  local b = CreateFrame("Button", nil, nav)
  b:SetSize(NAVW - 8, 26)
  b:SetPoint("TOPLEFT", 4, -6 - (i - 1) * 28)
  b.label = n[2]
  b.text = Text(b, "GameFontHighlight")
  b.text:SetPoint("LEFT", 10, 0)
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(0.91, 0.74, 0.47, 0.12)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.05)
  b:SetScript("OnClick", function() ShowPage(n[1]) end)
  navButtons[n[1]] = b
  local p = CreateFrame("Frame", nil, body)
  p:SetAllPoints()
  p:Hide()
  pages[n[1]] = p
end

local credit = Text(nav, "GameFontDisableSmall")
credit:SetPoint("BOTTOMLEFT", 10, 10)
credit:SetWidth(NAVW - 20)
credit:SetWordWrap(true)
credit:SetText("Info only: you buy and turn in.")

local repBar = CreateFrame("StatusBar", nil, nav)
repBar:SetPoint("BOTTOMLEFT", credit, "TOPLEFT", 0, 8)
repBar:SetSize(NAVW - 20, 8)
repBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
repBar:SetStatusBarColor(0.36, 0.79, 0.42)
repBar:SetMinMaxValues(0, 1)
local repBarBg = repBar:CreateTexture(nil, "BACKGROUND")
repBarBg:SetAllPoints()
repBarBg:SetColorTexture(1, 1, 1, 0.08)

local repStanding = Text(nav, "GameFontHighlightSmall")
repStanding:SetPoint("BOTTOMLEFT", repBar, "TOPLEFT", 0, 4)
repStanding:SetWidth(NAVW - 20)

local repText = Text(nav, "GameFontNormalSmall")
repText:SetPoint("BOTTOMLEFT", repStanding, "TOPLEFT", 0, 2)
repText:SetWidth(NAVW - 20)
repText:SetWordWrap(true)
repText:SetMaxLines(2)

---------------------------------------------------------------------------
-- Page: Plan your run
---------------------------------------------------------------------------
local P = pages.plan
local budgetBox = Edit(P, 70, true)
budgetBox:SetPoint("TOPLEFT", 16, -28)
Label(P, "Budget (gold)", budgetBox, -4)
-- Rep target dropdown (own lightweight menu: no dependency on Blizzard's dropdown library)
local TARGETS = { "next", 250, 500, 750, 1000, 1500, 2000, 3000, 5000, "max" }
local function RepToNext()
  local _, cur, size = ns.GetRep()
  if cur and size and size > 0 then return max(0, size - cur) end
end
local function TargetLabel(t)
  if t == "next" then
    local n = RepToNext()
    return n and ("Next standing (%d)"):format(n) or "Next standing"
  elseif t == "max" then return "No target (use budget)"
  elseif t then return ("%d rep"):format(t) end
  return "1000 rep"
end
local targetBox = CreateFrame("Button", nil, P, hasBackdrop)
targetBox:SetSize(150, 22)
targetBox:SetPoint("LEFT", budgetBox, "RIGHT", 14, 0)
Skin(targetBox, C.bg, 1)
targetBox.text = Text(targetBox, "GameFontHighlightSmall")
targetBox.text:SetPoint("LEFT", 8, 0)
targetBox.text:SetPoint("RIGHT", -20, 0)
local arrow = targetBox:CreateTexture(nil, "OVERLAY")
arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
arrow:SetSize(14, 14)
arrow:SetPoint("RIGHT", -4, -3)
local thl = targetBox:CreateTexture(nil, "HIGHLIGHT")
thl:SetAllPoints()
thl:SetColorTexture(1, 0.85, 0.6, 0.08)
Label(P, "Rep target", targetBox, 0)

local menu = CreateFrame("Frame", nil, targetBox, hasBackdrop)
menu:SetPoint("TOPLEFT", targetBox, "BOTTOMLEFT", 0, -2)
menu:SetSize(170, #TARGETS * 20 + 8)
menu:SetFrameStrata("DIALOG")
menu:EnableMouse(true)
Skin(menu, C.bg, 1)
menu:Hide()
menu.items = {}
for i, t in ipairs(TARGETS) do
  local it = CreateFrame("Button", nil, menu)
  it:SetSize(162, 20)
  it:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
  it.text = Text(it, "GameFontHighlightSmall")
  it.text:SetPoint("LEFT", 6, 0)
  local hl = it:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(0.91, 0.74, 0.47, 0.15)
  it:SetScript("OnClick", function()
    ns.char.target = t
    menu:Hide()
    ns.UpdateUI()
  end)
  it.t = t
  menu.items[i] = it
end
menu:SetScript("OnShow", function(self)
  for _, it in ipairs(self.items) do
    local sel = ns.char.target == it.t or (ns.char.target == nil and it.t == 1000)
    it.text:SetText((sel and C.title or C.ink) .. TargetLabel(it.t) .. "|r")
  end
end)
targetBox:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
targetBox:SetScript("OnHide", function() menu:Hide() end)
Tooltip(targetBox, function(_, tt)
  tt:AddLine("Rep target")
  tt:AddLine("How much reputation this run should earn. 'No target' spends your budget on the cheapest rep.", 1, 1, 1, true)
end)
local levelBox = Edit(P, 40, true)
levelBox:SetPoint("LEFT", targetBox, "RIGHT", 18, 0)
levelBox:SetMaxLetters(2)
Label(P, "Level", levelBox, -4)
Tooltip(levelBox, function(_, tt)
  tt:AddLine("Character level")
  tt:AddLine("Leave blank to use your current level.", 1, 1, 1, true)
end)

local modeBtn = Button(P, "", 130)
modeBtn:SetPoint("LEFT", levelBox, "RIGHT", 14, 0)
Label(P, "Writs", modeBtn, 2)
modeBtn:SetScript("OnClick", function()
  local cur = ns.char.mode
  for i, m in ipairs(MODES) do
    if m == cur then ns.char.mode = MODES[i % #MODES + 1]; break end
  end
  ns.dirty = true
  ns.UpdateUI()
end)
Tooltip(modeBtn, function(_, tt)
  tt:AddLine("What you still need to buy")
  tt:AddLine("Writs or items already in your bags are counted as free.", 1, 1, 1, true)
end)

local function readInputs()
  local b = tonumber(budgetBox:GetText())
  local t = ns.char.target
  if t == "next" then t = RepToNext() or 1000
  elseif t == "max" then t = math.huge
  elseif type(t) ~= "number" then t = 1000 end
  local l = tonumber(levelBox:GetText())
  ns.char.budget = b
  ns.char.levelOverride = (l and l >= 1 and l <= 80) and l or nil
  return b and b * 10000 or nil, t
end

local planBtn = Button(P, "Plan run", 90, function()
  budgetBox:ClearFocus(); levelBox:ClearFocus(); menu:Hide()
  local b, t = readInputs()
  ns.Refresh()
  local n, spent, rep = ns.Plan(b, t)
  if n == 0 then ns.Print("No writs fit that budget and level. Try a higher budget or check the All writs page.") end
  ns.UpdateUI()
end)
planBtn:SetPoint("LEFT", modeBtn, "RIGHT", 10, 0)
for _, e in ipairs({ budgetBox, levelBox }) do
  e:SetScript("OnEnterPressed", function() planBtn:Click() end)
end

local summary = Text(P, "GameFontHighlight")
summary:SetPoint("TOPLEFT", 16, -58)
summary:SetWidth(BW - 32)
local dupNote = Text(P, "GameFontHighlightSmall")
dupNote:SetPoint("BOTTOMLEFT", 16, 66)
dupNote:SetWidth(BW - 32)

-- column headers
local hdr = CreateFrame("Frame", nil, P)
hdr:SetPoint("TOPLEFT", 10, -80)
hdr:SetSize(BW - 40, 16)
-- Sortable headings for the run list. Click: sort; again: reverse; third click: back to planned order.
local PSORTS = {
  { key = "g", label = "Writ", x = 0, w = 40, just = "CENTER", tick = true },
  { key = "i", label = "Items", x = 40, w = 40, just = "CENTER", tick = true },
  { key = "d", label = "Done", x = 80, w = 40, just = "CENTER", tick = true },
  { key = "name", label = "Name", x = 124, w = 44, alpha = true },
  { key = "rep", label = "Rep", x = 178, w = 40 },
  { key = "npc", label = "NPC", x = 312, w = 34, alpha = true },
  { key = "zone", label = "Zone", x = 356, w = 50, alpha = true },
  { key = "danger", label = "Danger", x = 428, w = 50 },
  { key = "cost", label = "Cost", x = 508, w = 60, just = "RIGHT" },
}
local planHeaders = {}
local function PlanSortHint(c, asc)
  if c.tick then return asc and "not ticked first" or "ticked first" end
  if c.alpha then return asc and "A to Z" or "Z to A" end
  if c.key == "danger" then return asc and "safest first" or "most dangerous first" end
  return asc and "lowest to highest" or "highest to lowest"
end
local function UpdatePlanHeaders()
  local key, asc = ns.db.planSortKey, ns.db.planSortAsc ~= false
  for _, b in ipairs(planHeaders) do
    local on = b.c.key == key
    b.text:SetText((on and C.title or "|cffd8b46a") .. b.c.label ..
      (on and (asc and "|TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t" or "|TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t") or "") .. "|r")
  end
end
for _, c in ipairs(PSORTS) do
  local b = CreateFrame("Button", nil, hdr)
  b:SetSize(c.w, 16)
  b:SetPoint("LEFT", c.x, 0)
  b.c = c
  b.text = Text(b, "GameFontNormalSmall", c.just or "LEFT")
  b.text:SetAllPoints()
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.85, 0.6, 0.08)
  b:SetScript("OnClick", function()
    if ns.db.planSortKey ~= c.key then
      ns.db.planSortKey, ns.db.planSortAsc = c.key, true
    elseif ns.db.planSortAsc ~= false then
      ns.db.planSortAsc = false
    else
      ns.db.planSortKey, ns.db.planSortAsc = nil, true -- back to planned order
    end
    ns.UpdateUI()
  end)
  Tooltip(b, function(_, tt)
    local on, asc = ns.db.planSortKey == c.key, ns.db.planSortAsc ~= false
    tt:AddLine("Sort by " .. c.label .. (c.tick and " tick" or ""))
    if on and not asc then tt:AddLine("Click: back to planned order", 1, 1, 1)
    else tt:AddLine("Click: " .. PlanSortHint(c, not on), 1, 1, 1) end
  end)
  tinsert(planHeaders, b)
end
for _, sl in ipairs({ { 168, "/" }, { 346, "/" } }) do
  local t = Text(hdr, "GameFontNormalSmall"); t:SetPoint("LEFT", sl[1], 0); t:SetText("|cff8a8178" .. sl[2] .. "|r")
end

local function SortRun(run)
  local key, asc = ns.db.planSortKey, ns.db.planSortAsc ~= false
  UpdatePlanHeaders()
  if not key then return run end
  local pos = {}
  for i, w in ipairs(run) do pos[w] = i end
  local function val(w)
    if key == "g" or key == "i" or key == "d" then
      local g, i, d = ns.Ticks(w)
      local t = (key == "g" and g) or (key == "i" and i) or (key == "d" and d)
      return t and 1 or 0
    elseif key == "name" then return w.name:lower()
    elseif key == "npc" then return w.npc and w.npc:lower() or nil
    elseif key == "zone" then return w.zone and w.zone:lower() or nil
    elseif key == "danger" then return w.lo and (w.lo + w.hi) / 2 or nil
    else return w[key] end
  end
  table.sort(run, function(a, b)
    local va, vb = val(a), val(b)
    if va == nil or vb == nil then
      if va == vb then return pos[a] < pos[b] end
      return vb == nil
    end
    if va == vb then return pos[a] < pos[b] end
    if asc then return va < vb else return va > vb end
  end)
  return run
end

local L -- player level used for colours this refresh

local function TickBox(row, field, x)
  local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  cb:SetSize(20, 20)
  cb:SetPoint("LEFT", x, 0)
  cb:SetScript("OnClick", function(self)
    if self.auto then self:SetChecked(true); return end
    ns.SetTick(row.w.qid, field, self:GetChecked())
    ns.UpdateUI()
  end)
  Tooltip(cb, function(self, tt)
    local names = { g = "Have the writ", i = "Have the item(s)", d = "Turned in" }
    tt:AddLine(names[field])
    if self.auto then tt:AddLine("Ticked automatically from your bags / quest log.", 1, 1, 1, true)
    else tt:AddLine("Click to tick it yourself.", 1, 1, 1, true) end
  end)
  return cb
end

local planList = CreateList(P, BW - 46, function(r)
  r.g = TickBox(r, "g", 10)
  r.i = TickBox(r, "i", 50)
  r.d = TickBox(r, "d", 90)
  r.name = Text(r); r.name:SetPoint("LEFT", 124, 0); r.name:SetWidth(180)
  r.where = Text(r); r.where:SetPoint("LEFT", 312, 0); r.where:SetWidth(112)
  r.lvl = Text(r); r.lvl:SetPoint("LEFT", 428, 0); r.lvl:SetWidth(50)
  r.cost = Text(r, nil, "RIGHT"); r.cost:SetPoint("RIGHT", -34, 0); r.cost:SetWidth(90)
  r.pin = CreateFrame("Button", nil, r)
  r.pin:SetSize(20, 20)
  r.pin:SetPoint("RIGHT", -6, 0)
  r.pin:SetNormalTexture("Interface\\Icons\\INV_Misc_Map_01")
  r.pin:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  r.pin:SetScript("OnClick", function()
    if ns.Waypoint(r.w) then ns.Print("Waypoint set: " .. (r.w.npc or "") .. ", " .. (r.w.zone or ""))
    else ns.Print("No location for this writ.") end
  end)
  Tooltip(r.pin, function(_, tt) tt:AddLine("Set waypoint"); tt:AddLine(TomTom and "TomTom arrow" or "Blizzard map pin", 1, 1, 1) end)
  Tooltip(r, function(self, tt) WritTooltip(self.w, tt) end)
end, function(r, w)
  r.w = w
  local g, i, d, ag, ai, ad = ns.Ticks(w)
  r.g:SetChecked(g); r.g.auto = ag
  r.i:SetChecked(i); r.i.auto = ai
  r.d:SetChecked(d); r.d.auto = ad
  local alpha = d and 0.45 or 1
  r.name:SetText((d and C.mute or C.ink) .. w.name .. "|r  " .. (TIERC[w.tier] or "") .. "+" .. w.rep .. "|r")
  local dk, dl = ns.Danger(w, L)
  local loc = w.npc and (w.npc .. ", " .. (w.zone or "?")) or (C.warn .. "NPC unknown|r")
  r.where:SetText(C.mute .. loc .. "|r")
  r.lvl:SetText(dk and (DANGER[dk] .. dl .. "|r") or "")
  r.cost:SetText(d and (C.good .. "done|r") or ns.Money(w.cost))
  r.pin:SetShown(w.map ~= nil)
  r.name:SetAlpha(alpha); r.where:SetAlpha(alpha); r.lvl:SetAlpha(alpha)
end)
planList:SetPoint("TOPLEFT", 10, -98)
planList:SetPoint("BOTTOMRIGHT", -30, 84)

local still = Text(P, "GameFontHighlightSmall")
still:SetPoint("BOTTOMLEFT", 16, 50)
still:SetWidth(BW - 32)

-- Run complete banner
local done = CreateFrame("Frame", nil, P, hasBackdrop)
done:SetPoint("BOTTOMLEFT", 10, 44)
done:SetPoint("BOTTOMRIGHT", -10, 44)
done:SetHeight(26)
Skin(done, { 0.12, 0.25, 0.14 }, 0.9)
local doneText = Text(done, "GameFontHighlight")
doneText:SetPoint("LEFT", 10, 0)
done:Hide()

local clearBtn = Button(P, "Clear run", 90, function()
  ns.ClearRun(); ns.UpdateUI()
end)
clearBtn:SetPoint("BOTTOMLEFT", 14, 12)
local nextBtn = Button(P, "Plan another run today", 160, function()
  ns.NextRun()
  local b, t = readInputs()
  ns.Refresh()
  ns.Plan(b, t)
  ns.UpdateUI()
end)
nextBtn:SetPoint("LEFT", clearBtn, "RIGHT", 6, 0)
local ticksBtn = Button(P, "Clear ticks", 86, function()
  for _, q in ipairs(ns.char.run) do ns.char.ticks[q] = nil end
  ns.UpdateUI()
end)
ticksBtn:SetPoint("LEFT", nextBtn, "RIGHT", 6, 0)
Tooltip(ticksBtn, function(_, tt)
  tt:AddLine("Clear ticks")
  tt:AddLine("Removes the ticks you added yourself. Ticks from your bags and quest log stay.", 1, 1, 1, true)
end)
Tooltip(nextBtn, function(_, tt)
  tt:AddLine("Plan another run")
  tt:AddLine("Leaves out the writs in this run and plans the next cheapest ones.", 1, 1, 1, true)
end)
local wpBtn = Button(P, "Waypoints", 90, function()
  local n, multi = ns.WaypointRun()
  if n == 0 then ns.Print("No turn-ins left to mark.")
  elseif multi then ns.Print(("%d TomTom waypoints added."):format(n))
  else ns.Print("Map pin set on your next turn-in (install TomTom to mark them all).") end
end)
wpBtn:SetPoint("BOTTOMRIGHT", -14, 12)
local ahBtn = Button(P, "Send to Auctionator", 140, function()
  local ok, msg = ns.SendToAuctionator(); ns.Print(msg)
end)
ahBtn:SetPoint("RIGHT", wpBtn, "LEFT", -6, 0)

local function UpdatePlan()
  modeBtn:SetText(MODE_LABEL[ns.char.mode] or MODE_LABEL.both)
  if not budgetBox:HasFocus() then budgetBox:SetText(ns.char.budget and tostring(ns.char.budget) or "") end
  targetBox.text:SetText(TargetLabel(ns.char.target))
  if not levelBox:HasFocus() then levelBox:SetText(ns.char.levelOverride and tostring(ns.char.levelOverride) or "") end
  local run = SortRun(ns.RunRecords())
  ns.lastRun = run
  planList:SetData(run)
  if #run == 0 then
    summary:SetText(C.mute .. "Enter a budget and pick a rep target, then press Plan run. Blank budget = no limit.|r")
    still:SetText(""); done:Hide(); dupNote:SetText(ns.repOnly and (C.warn .. "No price addon found, so plans go by rep only (fewest turn-ins) and costs show as \226\128\147. Open the auction house and press Scan AH prices (top right), or install Auctionator, GoldScout or TSM.|r") or "")
    for _, b in ipairs({ clearBtn, nextBtn, wpBtn, ahBtn, ticksBtn }) do b:Disable() end
    return
  end
  for _, b in ipairs({ clearBtn, wpBtn, ahBtn, ticksBtn }) do b:Enable() end
  local total, rep, left, leftCost, nDone, unknown = 0, 0, 0, 0, 0, false
  for _, w in ipairs(run) do
    local _, _, d = ns.Ticks(w)
    rep = rep + w.rep
    if w.cost then total = total + w.cost else unknown = true end
    if d then nDone = nDone + 1 else left = left + 1; leftCost = leftCost + (w.cost or 0) end
  end
  local extra = 0
  for _, w in ipairs(run) do if (w.haveWrit or 0) > 1 then extra = extra + w.haveWrit - 1 end end
  dupNote:SetText(ns.repOnly and (C.warn .. "No price addon found, so plans go by rep only (fewest turn-ins) and costs show as \226\128\147. Open the auction house and press Scan AH prices (top right), or install Auctionator, GoldScout or TSM.|r") or (extra > 0 and (C.warn .. ("You have %d spare writ cop%s in your bags: only one of each can be handed in today.|r"):format(extra, extra == 1 and "y" or "ies")) or ""))
  summary:SetText(("%s%d writs|r  ·  cost %s  ·  %s+%d rep|r  ·  %d of %d turned in"):format(
    C.ink, #run, ns.Money(total), C.good, rep, nDone, #run) .. (unknown and (C.warn .. "  (some prices missing)|r") or ""))
  if left == 0 then
    done:Show(); still:SetText("")
    doneText:SetText(C.good .. "Run complete!|r  +" .. rep .. " rep. Clear it, or plan another run today.")
    nextBtn:Enable(); ahBtn:Disable(); wpBtn:Disable()
  else
    done:Hide(); nextBtn:Disable()
    local needs = ns.ShoppingNeeds()
    local nw, ni = 0, 0
    for _, e in ipairs(needs) do if e.isWrit then nw = nw + 1 else ni = ni + e.qty end end
    still:SetText(("Still to buy: %d writs, %d items (%s)  ·  %d turn-ins left"):format(nw, ni, ns.Money(leftCost), left))
  end
end

---------------------------------------------------------------------------
-- Page: All writs (search; click a row to add/remove it from your run)
---------------------------------------------------------------------------
local A = pages.all
local findHead = Text(A, "GameFontNormal")
findHead:SetPoint("TOPLEFT", 16, -10)

local FIELDS = {
  { "writ", "Writ", "e.g. potion" }, { "item", "Item", "e.g. Mithril" }, { "npc", "Turn-in NPC", "e.g. Gorgrash" },
  { "tier", "Tier", "e.g. Expert" }, { "rep", "Rep", "e.g. 125" }, { "cont", "Continent", "e.g. Kalimdor" },
  { "zone", "Zone", "e.g. Badlands" },
}
local filters, order = {}, {}
for idx, f in ipairs(FIELDS) do
  local e = Edit(A, 80, false)
  e:SetPoint("TOPLEFT", 18 + (idx - 1) * 86, -46)
  Label(A, f[2], e, -4)
  e.ph = Text(e, "GameFontDisableSmall")
  e.ph:SetPoint("LEFT", 1, 0)
  e.ph:SetText(f[3])
  e:SetScript("OnTextChanged", function(self, user)
    self.ph:SetShown(self:GetText() == "")
    if user then
      -- like the website: typing in one box starts a new search
      if self:GetText() ~= "" then
        for _, o in ipairs(order) do if o ~= self and o:GetText() ~= "" then o:SetText("") end end
      end
      ns.UpdateUI()
    end
  end)
  e:SetScript("OnTabPressed", function(self)
    local n = order[(idx % #order) + 1]
    if n then n:SetFocus() end
  end)
  filters[f[1]] = e
  order[idx] = e
end

ns.filters = filters
local function ClearFilters()
  for _, e in ipairs(order) do e:SetText(""); e:ClearFocus() end
end
local searchBtn = Button(A, "Search", 80, function()
  for _, e in ipairs(order) do e:ClearFocus() end
  ns.UpdateUI()
end)
searchBtn:SetPoint("TOPLEFT", 16, -74)
for _, e in ipairs(order) do e:SetScript("OnEnterPressed", function() searchBtn:Click() end) end
local clearF = Button(A, "Clear filters", 100, function() ClearFilters(); ns.UpdateUI() end)
clearF:SetPoint("LEFT", searchBtn, "RIGHT", 6, 0)
local resetAll = Button(A, "Reset all", 80, function()
  ClearFilters()
  ns.char.budget, ns.char.target, ns.char.levelOverride, ns.char.mode = nil, nil, nil, "both"
  ns.dirty = true
  ns.UpdateUI()
  ns.Print("Filters and planner inputs reset. Your current run is kept.")
end)
resetAll:SetPoint("LEFT", clearF, "RIGHT", 6, 0)
Tooltip(resetAll, function(_, tt)
  tt:AddLine("Reset all")
  tt:AddLine("Clears these filters plus budget, rep target, level and buy mode. Your planned run and ticks stay.", 1, 1, 1, true)
end)
local allNote = Text(A, "GameFontDisableSmall")
allNote:SetPoint("LEFT", resetAll, "RIGHT", 12, 0)
allNote:SetWidth(BW - 326)
allNote:SetWordWrap(true)
allNote:SetText("Type in a box, then press Search (or Enter). Typing in another box starts a new search. Click a writ to add or remove it from your run.")

local hdr2 = CreateFrame("Frame", nil, A)
hdr2:SetPoint("TOPLEFT", 10, -102)
hdr2:SetSize(BW - 40, 16)
-- Sortable headers: click to sort, click again to flip. Writ sorts A-Z / Z-A, the rest low-high / high-low.
local SORTS = {
  { key = "name", label = "Writ", x = 24, w = 200 },
  { key = "rep", label = "Rep", x = 230, w = 34 },
  { key = "zone", label = "Zone", x = 266, w = 54 },
  { key = "level", label = "Level", x = 330, w = 70 },
  { key = "cost", label = "Cost", x = 494, w = 40, right = true },
  { key = "per100", label = "/100 rep", x = 540, w = 58, right = true },
}
local sortButtons = {}
local function SortTip(c, asc)
  if c.key == "name" or c.key == "zone" then return asc and "A to Z" or "Z to A" end
  return asc and "lowest to highest" or "highest to lowest"
end
local function UpdateSortHeaders()
  local key, asc = ns.db.sortKey or "per100", ns.db.sortAsc ~= false
  for _, b in ipairs(sortButtons) do
    local on = b.c.key == key
    b.text:SetText((on and C.title or "|cffd8b46a") .. b.c.label .. (on and (asc and " |TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t" or " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t") or "") .. "|r")
  end
end
for _, c in ipairs(SORTS) do
  local b = CreateFrame("Button", nil, hdr2)
  b:SetSize(c.w, 16)
  b:SetPoint("LEFT", c.x, 0)
  b.c = c
  b.text = Text(b, "GameFontNormalSmall", c.right and "RIGHT" or "LEFT")
  b.text:SetAllPoints()
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.85, 0.6, 0.08)
  b:SetScript("OnClick", function()
    if (ns.db.sortKey or "per100") == c.key then
      ns.db.sortAsc = not (ns.db.sortAsc ~= false)
    else
      ns.db.sortKey, ns.db.sortAsc = c.key, true
    end
    ns.UpdateUI()
  end)
  Tooltip(b, function(_, tt)
    local on = (ns.db.sortKey or "per100") == c.key
    local asc = ns.db.sortAsc ~= false
    tt:AddLine("Sort by " .. c.label)
    tt:AddLine("Click: " .. SortTip(c, not on or not asc), 1, 1, 1)
  end)
  tinsert(sortButtons, b)
end
local slash = Text(hdr2, "GameFontNormalSmall")
slash:SetPoint("LEFT", 318, 0)
slash:SetText("|cff8a8178/|r")

local allList = CreateList(A, BW - 46, function(r)
  r.mark = Text(r, "GameFontNormal"); r.mark:SetPoint("LEFT", 6, 0)
  r.name = Text(r); r.name:SetPoint("LEFT", 24, 0); r.name:SetWidth(200)
  r.rep = Text(r); r.rep:SetPoint("LEFT", 230, 0); r.rep:SetWidth(32)
  r.where = Text(r); r.where:SetPoint("LEFT", 266, 0); r.where:SetWidth(188)
  r.cost = Text(r, nil, "RIGHT"); r.cost:SetPoint("LEFT", 458, 0); r.cost:SetWidth(76)
  r.per = Text(r, nil, "RIGHT"); r.per:SetPoint("LEFT", 536, 0); r.per:SetWidth(62)
  Tooltip(r, function(self, tt) WritTooltip(self.w, tt); tt:AddLine(" "); tt:AddLine(ns.InRun(self.w.qid) and "Click to remove from run" or "Click to add to run", 0.6, 0.8, 1) end)
  r:SetScript("OnClick", function(self) ns.ToggleRun(self.w.qid); ns.UpdateUI() end)
end, function(r, w)
  r.w = w
  local inRun = ns.InRun(w.qid)
  r.mark:SetText(inRun and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t" or "")
  local flag = w.done and (C.good .. " (done today)|r") or (not w.factionOk and (C.warn .. " (other faction rep)|r") or "")
  r.name:SetText((TIERC[w.tier] or C.ink) .. w.name .. "|r" .. flag)
  r.rep:SetText(C.ink .. w.rep .. "|r")
  local dk, dl = ns.Danger(w, L)
  r.where:SetText(C.mute .. (w.zone or "unknown") .. "|r" .. (dk and ("  " .. DANGER[dk] .. w.lo .. "–" .. w.hi .. " " .. dl .. "|r") or ""))
  r.cost:SetText(ns.Money(w.cost))
  r.per:SetText(ns.Money(w.per100))
end)
allList:SetPoint("TOPLEFT", 10, -120)
allList:SetPoint("BOTTOMRIGHT", -30, 10)

local function UpdateAll()
  local v = {}
  for k, e in pairs(filters) do v[k] = (e:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end
  local function has(x, k)
    return v[k] == "" or (x ~= nil and tostring(x):lower():find(v[k], 1, true) ~= nil)
  end
  local out = {}
  for _, w in ipairs(ns.list) do
    if has(w.name, "writ") and has(w.item, "item") and has(w.npc, "npc") and has(w.tier, "tier")
       and (v.rep == "" or tostring(w.rep):sub(1, #v.rep) == v.rep)
       and has(w.cont, "cont") and has(w.zone, "zone") then
      tinsert(out, w)
    end
  end
  local key, asc = ns.db.sortKey or "per100", ns.db.sortAsc ~= false
  local function val(w)
    if key == "name" then return w.name:lower()
    elseif key == "zone" then return w.zone and w.zone:lower() or nil
    elseif key == "level" then return w.lo and (w.lo + w.hi) / 2 or nil
    else return w[key] end
  end
  table.sort(out, function(a, b)
    local va, vb = val(a), val(b)
    if va == nil or vb == nil then -- missing values always go last
      if va == vb then return a.qid < b.qid end
      return vb == nil
    end
    if va == vb then
      if key == "level" and a.zone ~= b.zone then return tostring(a.zone) < tostring(b.zone) end
      if key == "zone" and a.lo ~= b.lo then return (a.lo or 999) < (b.lo or 999) end
      return a.qid < b.qid
    end
    if asc then return va < vb else return va > vb end
  end)
  UpdateSortHeaders()
  allList:SetData(out)
  ns.lastAll = out
  local any = false
  for _, x in pairs(v) do if x ~= "" then any = true end end
  findHead:SetText(C.title .. "Find writs|r  " .. C.mute .. (any and ("%d of %d match"):format(#out, #ns.list) or ("all %d writs"):format(#ns.list)) .. "|r")
end

---------------------------------------------------------------------------
-- Page: Road to Exalted
---------------------------------------------------------------------------
local E = pages.exalted
local exDay -- selected day index (detail view), or nil for the day list
local exHead = Text(E, "GameFontNormal")
exHead:SetPoint("TOPLEFT", 16, -10)
exHead:SetText(C.title .. "Road to Exalted|r")
local dailyBox = Edit(E, 70, true)
dailyBox:SetPoint("TOPLEFT", 18, -46)
Label(E, "Daily budget (gold)", dailyBox, -4)
local exPlan
local exBuild = Button(E, "Build plan", 100, function()
  dailyBox:ClearFocus()
  local g = tonumber(dailyBox:GetText())
  ns.char.dailyBudget = g
  ns.dirty = true
  exPlan = nil
  exDay = nil
  ns.UpdateUI()
end)
exBuild:SetPoint("LEFT", dailyBox, "RIGHT", 12, 0)
dailyBox:SetScript("OnEnterPressed", function() exBuild:Click() end)
local exNote = Text(E, "GameFontDisableSmall")
exNote:SetPoint("LEFT", exBuild, "RIGHT", 12, 0)
exNote:SetWidth(BW - 250)
exNote:SetWordWrap(true)
exNote:SetText("Blank = no daily limit. Reminder: each named writ can only be handed in once a day, and extra copies wait for another day. The plan fills each day with the cheapest writs and uses your spare copies first. Uses your buy mode and level from Plan your run.")

local exSummary = Text(E, "GameFontHighlight")
exSummary:SetPoint("TOPLEFT", 16, -76)
exSummary:SetWidth(BW - 32)
exSummary:SetWordWrap(true)

local hdr3 = CreateFrame("Frame", nil, E)
hdr3:SetPoint("TOPLEFT", 10, -112)
hdr3:SetSize(BW - 40, 16)
for _, c in ipairs({ { "Day", 6 }, { "Writs", 56 }, { "Rep", 110 }, { "Cost", 170 }, { "Total rep", 270 }, { "Reaches", 360 } }) do
  local fs = Text(hdr3, "GameFontNormalSmall"); fs:SetPoint("LEFT", c[2], 0); fs:SetText(c[1])
end

local exList = CreateList(E, BW - 46, function(r)
  r.day = Text(r); r.day:SetPoint("LEFT", 6, 0); r.day:SetWidth(46)
  r.n = Text(r); r.n:SetPoint("LEFT", 56, 0); r.n:SetWidth(50)
  r.rep = Text(r); r.rep:SetPoint("LEFT", 110, 0); r.rep:SetWidth(56)
  r.cost = Text(r, nil, "RIGHT"); r.cost:SetPoint("LEFT", 150, 0); r.cost:SetWidth(100)
  r.cum = Text(r); r.cum:SetPoint("LEFT", 270, 0); r.cum:SetWidth(86)
  r.reach = Text(r); r.reach:SetPoint("LEFT", 360, 0); r.reach:SetWidth(120)
  r.load = Button(r, "Use as run", 90, function(self)
    local d = self:GetParent().d
    wipe(ns.char.run)
    for _, q in ipairs(d.qids) do tinsert(ns.char.run, q) end
    ns.Print(("Day %d loaded into Plan your run (%d writs)."):format(self:GetParent().i, #d.qids))
    ns.ShowPage("plan")
  end)
  r.load:SetHeight(20)
  r.load:SetPoint("RIGHT", -4, 0)
  r:SetScript("OnClick", function(self) ns.OpenExDay(self.i) end)
  Tooltip(r, function(self, tt)
    tt:AddLine(("Day %d: %d writs"):format(self.i, #self.d.qids), 0.91, 0.74, 0.47)
    tt:AddLine("Click to see items and prices", 0.6, 0.8, 1)
    for k, q in ipairs(self.d.qids) do
      local w = ns.byQid[q]
      if k > 25 then tt:AddLine(("...and %d more"):format(#self.d.qids - 25), 0.78, 0.72, 0.67); break end
      tt:AddDoubleLine(w.name .. "  |cff8a8178" .. (w.zone or "?") .. "|r", "+" .. w.rep, 0.95, 0.92, 0.89, 0.36, 0.79, 0.42)
    end
  end)
end, function(r, d, i)
  r.d, r.i = d, i
  r.day:SetText(C.ink .. i .. "|r")
  r.n:SetText(C.ink .. #d.qids .. "|r")
  r.rep:SetText(C.good .. "+" .. d.rep .. "|r")
  r.cost:SetText(ns.Money(d.cost))
  r.cum:SetText(C.mute .. d.cum .. "|r")
  local names = {}
  for _, rr in ipairs(d.reachedAll or {}) do tinsert(names, ns.StandingName(rr)) end
  r.reach:SetText(#names > 0 and ((d.reached >= 8 and C.title or C.good) .. table.concat(names, ", ") .. "|r") or "")
  r.load:SetShown(i == 1) -- the plan rebuilds from your live rep each day, so day 1 is always today
end)
exList:SetPoint("TOPLEFT", 10, -130)
exList:SetPoint("BOTTOMRIGHT", -30, 30)
local exFoot = Text(E, "GameFontDisableSmall")
exFoot:SetPoint("BOTTOMLEFT", 16, 10)
exFoot:SetWidth(BW - 32)
exFoot:SetText("Click a day to see its items and live prices. Buying many of one item can push its price up, so later days may cost more.")

-- Day detail view: that day's writs with live item and writ prices
local exDetail = CreateFrame("Frame", nil, E)
exDetail:SetPoint("TOPLEFT", 0, -106)
exDetail:SetPoint("BOTTOMRIGHT", 0, 28)
exDetail:Hide()
local backBtn = Button(exDetail, "< All days", 90, function() exDay = nil; ns.UpdateUI() end)
backBtn:SetPoint("TOPLEFT", 14, -2)
local dayTitle = Text(exDetail, "GameFontHighlight")
dayTitle:SetPoint("LEFT", backBtn, "RIGHT", 12, 0)
local useDay = Button(exDetail, "Use as run", 90)
useDay:SetPoint("TOPRIGHT", -14, -2)
local sendDay = Button(exDetail, "Send to Auctionator", 150)
sendDay:SetPoint("RIGHT", useDay, "LEFT", -6, 0)
local hdr4 = CreateFrame("Frame", nil, exDetail)
hdr4:SetPoint("TOPLEFT", 10, -30)
hdr4:SetSize(BW - 40, 16)
for _, c in ipairs({ { "Writ", 6, 170 }, { "Hand in", 180, 150 }, { "Item price", 334, 70, "RIGHT" },
                      { "Writ price", 408, 70, "RIGHT" }, { "Cost", 482, 70, "RIGHT" }, { "Rep", 560, 40 } }) do
  local fs = Text(hdr4, "GameFontNormalSmall", c[4]); fs:SetPoint("LEFT", c[2], 0); fs:SetWidth(c[3]); fs:SetText(c[1])
end
local dayList = CreateList(exDetail, BW - 46, function(r)
  r.name = Text(r); r.name:SetPoint("LEFT", 6, 0); r.name:SetWidth(170)
  r.item = Text(r); r.item:SetPoint("LEFT", 180, 0); r.item:SetWidth(150)
  r.ip = Text(r, nil, "RIGHT"); r.ip:SetPoint("LEFT", 334, 0); r.ip:SetWidth(70)
  r.wp = Text(r, nil, "RIGHT"); r.wp:SetPoint("LEFT", 408, 0); r.wp:SetWidth(70)
  r.cost = Text(r, nil, "RIGHT"); r.cost:SetPoint("LEFT", 482, 0); r.cost:SetWidth(70)
  r.rep = Text(r); r.rep:SetPoint("LEFT", 560, 0); r.rep:SetWidth(40)
  Tooltip(r, function(self, tt) WritTooltip(self.w, tt) end)
end, function(r, e)
  local w, b = e.w, e.b
  r.w = w
  r.name:SetText((TIERC[w.tier] or C.ink) .. w.name .. "|r")
  local itemTxt = (w.qty or 1) .. "× " .. w.item
  if b and b.i == 0 and ns.char.mode ~= "writ" then itemTxt = itemTxt .. C.good .. " (in bags)|r" end
  r.item:SetText(C.ink .. itemTxt .. "|r")
  r.ip:SetText(ns.char.mode == "writ" and (C.mute .. "–|r") or ns.Money(w.pItem))
  r.wp:SetText(ns.char.mode == "item" and (C.mute .. "–|r") or ((b and not b.w) and (C.good .. "in bags|r") or ns.Money(w.pWrit)))
  r.cost:SetText(ns.Money(e.c))
  r.rep:SetText(C.good .. "+" .. w.rep .. "|r")
end)
dayList:SetPoint("TOPLEFT", 10, -48)
dayList:SetPoint("BOTTOMRIGHT", -30, 4)

function ns.OpenExDay(i) exDay = i; ns.UpdateUI() end

local function UpdateExalted()
  if not dailyBox:HasFocus() then dailyBox:SetText(ns.char.dailyBudget and tostring(ns.char.dailyBudget) or "") end
  local res = ns.ExaltedPlan(ns.char.dailyBudget and ns.char.dailyBudget * 10000 or nil)
  local d = exDay and res.days[exDay]
  ns.lastExDay = d
  if exDay and not d then exDay = nil end
  hdr3:SetShown(not d); exList:SetShown(not d); exDetail:SetShown(d and true or false)
  if d then
    local rows = {}
    for _, q in ipairs(d.qids) do tinsert(rows, { w = ns.byQid[q], c = d.costs[q], b = d.buy[q] }) end
    dayList:SetData(rows)
    dayTitle:SetText(("Day %d: %d writs  ·  %s+%d rep|r  ·  %s"):format(exDay, #d.qids, C.good, d.rep, ns.Money(d.cost)))
    local idx = exDay
    sendDay:SetScript("OnClick", function()
      local _, m = ns.SendListToAuctionator(("Writ Planner Day %d"):format(idx), ns.DayNeeds(d)); ns.Print(m)
    end)
    useDay:SetScript("OnClick", function()
      wipe(ns.char.run)
      for _, q in ipairs(d.qids) do tinsert(ns.char.run, q) end
      ns.Print(("Day %d loaded into Plan your run (%d writs)."):format(idx, #d.qids))
      exDay = nil
      ns.ShowPage("plan")
    end)
  end
  exList:SetData(res.days)
  local startTxt = ("%s %d"):format(ns.StandingName(res.reaction), res.cur or 0)
  if res.start <= 0 then
    exSummary:SetText(C.title .. "You're already Exalted.|r")
  elseif #res.days == 0 then
    exSummary:SetText(C.warn .. "No writs fit that daily budget at your level. Raise the budget or check prices.|r")
  else
    local days = #res.days
    if ns.repOnly then
      exSummary:SetText(("From %s%s|r: %s%d rep|r to Exalted in %s%d day%s|r. "):format(C.ink, startTxt, C.good, res.start, C.ink, #res.days, #res.days == 1 and "" or "s") .. C.warn .. "No price addon found, so plans go by rep only (fewest turn-ins) and costs show as \226\128\147. Open the auction house and press Scan AH prices (top right), or install Auctionator, GoldScout or TSM.|r")
    else
    exSummary:SetText(("From %s%s|r: %s%d rep|r to Exalted. %s%d day%s|r, about %s in total (avg %s a day)."):format(
      C.ink, startTxt, C.good, res.start, C.ink, days, days == 1 and "" or "s", ns.Money(res.total), ns.Money(res.total / days))
      .. (res.complete and "" or (C.warn .. " Stops at 365 days: raise the daily budget.|r"))
      .. (res.guessed and (C.warn .. " (Couldn't read your rep: assumed Neutral 0.)|r") or ""))
    end
  end
end

---------------------------------------------------------------------------
-- Page: Merchant's Favor (Waylaid Crates; no daily limit)
---------------------------------------------------------------------------
local M = pages.favor
local mHead = Text(M, "GameFontNormal")
mHead:SetPoint("TOPLEFT", 16, -10)
mHead:SetText(C.title .. "Merchant's Favor|r")
local mBal = Text(M, "GameFontHighlight", "RIGHT")
mBal:SetPoint("TOPRIGHT", -16, -10)
mBal:SetWidth(300)

local goalBox = Edit(M, 60, true)
goalBox:SetPoint("TOPLEFT", 18, -46)
Label(M, "Favor goal", goalBox, -4)

local PRESETS = {
  { 30, "Recipe (30)" }, { 45, "Recipe (45)" }, { 200, "Tabard (200, Exalted)" },
  { 360, "Engineering schematic (270-360)" }, { 1000, "Profession title (1000)" },
  { 1200, "Advertising License (1200, Honored)" }, { 1500, "Packmule Treat pet (1500, Revered)" },
  { 6000, "Pack Kodo mount (6000, Exalted)" },
}
local presetBtn = CreateFrame("Button", nil, M, hasBackdrop)
presetBtn:SetSize(130, 22)
presetBtn:SetPoint("LEFT", goalBox, "RIGHT", 10, 0)
Skin(presetBtn, C.bg, 1)
presetBtn.text = Text(presetBtn, "GameFontHighlightSmall")
presetBtn.text:SetPoint("LEFT", 8, 0)
presetBtn.text:SetText("Pick a reward...")
local pArrow = presetBtn:CreateTexture(nil, "OVERLAY")
pArrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up"); pArrow:SetSize(14, 14); pArrow:SetPoint("RIGHT", -4, -3)
Label(M, "Rewards", presetBtn, 0)
local pMenu = CreateFrame("Frame", nil, presetBtn, hasBackdrop)
pMenu:SetPoint("TOPLEFT", presetBtn, "BOTTOMLEFT", 0, -2)
pMenu:SetSize(230, #PRESETS * 20 + 8)
pMenu:SetFrameStrata("DIALOG")
pMenu:EnableMouse(true)
Skin(pMenu, C.bg, 1)
pMenu:Hide()
for i, pr in ipairs(PRESETS) do
  local it = CreateFrame("Button", nil, pMenu)
  it:SetSize(222, 20)
  it:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
  it.text = Text(it, "GameFontHighlightSmall"); it.text:SetPoint("LEFT", 6, 0); it.text:SetText(pr[2])
  local hl = it:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.91, 0.74, 0.47, 0.15)
  it:SetScript("OnClick", function() ns.char.favorGoal = pr[1]; pMenu:Hide(); ns.UpdateUI() end)
end
presetBtn:SetScript("OnClick", function() pMenu:SetShown(not pMenu:IsShown()) end)
presetBtn:SetScript("OnHide", function() pMenu:Hide() end)

local buyBtn = Button(M, "", 170)
buyBtn:SetPoint("LEFT", presetBtn, "RIGHT", 10, 0)
Label(M, "Crates", buyBtn, 2)
buyBtn:SetScript("OnClick", function() ns.char.favorBuy = not ns.char.favorBuy; ns.UpdateUI() end)
Tooltip(buyBtn, function(_, tt)
  tt:AddLine("Where your crates come from")
  tt:AddLine("I have the crates: only the fill cost counts. Buy crates on the AH: the empty crate's price is added. Crates already in your bags are always used first.", 1, 1, 1, true)
end)
local mPlanBtn = Button(M, "Plan Favor", 90, function()
  goalBox:ClearFocus()
  ns.char.favorGoal = tonumber(goalBox:GetText())
  ns.UpdateUI()
end)
mPlanBtn:SetPoint("LEFT", buyBtn, "RIGHT", 10, 0)
goalBox:SetScript("OnEnterPressed", function() mPlanBtn:Click() end)

local mSummary = Text(M, "GameFontHighlight")
mSummary:SetPoint("TOPLEFT", 16, -76)
mSummary:SetWidth(BW - 32)
mSummary:SetWordWrap(true)

local MSORTS = {
  { key = "name", label = "Crate", x = 4, w = 50, alpha = true },
  { key = "fillName", label = "Cheapest fill", x = 166, w = 120, alpha = true },
  { key = "fill", label = "Fill", x = 318, w = 58, just = "RIGHT" },
  { key = "crateP", label = "Crate", x = 378, w = 58, just = "RIGHT" },
  { key = "favor", label = "Favor", x = 440, w = 36 },
  { key = "per", label = "g/Favor", x = 478, w = 56, just = "RIGHT" },
  { key = "have", label = "Have", x = 540, w = 28 },
  { key = "plan", label = "Plan", x = 570, w = 30 },
}
local hdr5 = CreateFrame("Frame", nil, M)
hdr5:SetPoint("TOPLEFT", 10, -110)
hdr5:SetSize(BW - 40, 16)
local mHeaders = {}
local function UpdateMHeaders()
  local key, asc = ns.db.favorSortKey or "per", ns.db.favorSortAsc ~= false
  for _, b in ipairs(mHeaders) do
    local on = b.c.key == key
    b.text:SetText((on and C.title or "|cffd8b46a") .. b.c.label ..
      (on and (asc and "|TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t" or "|TInterface\\Buttons\\Arrow-Down-Up:12:12:0:2|t") or "") .. "|r")
  end
end
for _, c in ipairs(MSORTS) do
  local b = CreateFrame("Button", nil, hdr5)
  b:SetSize(c.w, 16); b:SetPoint("LEFT", c.x, 0); b.c = c
  b.text = Text(b, "GameFontNormalSmall", c.just or "LEFT"); b.text:SetAllPoints()
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.85, 0.6, 0.08)
  b:SetScript("OnClick", function()
    if (ns.db.favorSortKey or "per") == c.key then ns.db.favorSortAsc = not (ns.db.favorSortAsc ~= false)
    else ns.db.favorSortKey, ns.db.favorSortAsc = c.key, true end
    ns.UpdateUI()
  end)
  Tooltip(b, function(_, tt)
    local on, asc = (ns.db.favorSortKey or "per") == c.key, ns.db.favorSortAsc ~= false
    local up = not on or not asc
    tt:AddLine("Sort by " .. c.label)
    tt:AddLine("Click: " .. (c.alpha and (up and "A to Z" or "Z to A") or (up and "lowest to highest" or "highest to lowest")), 1, 1, 1)
  end)
  tinsert(mHeaders, b)
end

local planCount = {}
local mList = CreateList(M, BW - 46, function(r)
  r.name = Text(r); r.name:SetPoint("LEFT", 4, 0); r.name:SetWidth(158)
  r.fillN = Text(r); r.fillN:SetPoint("LEFT", 166, 0); r.fillN:SetWidth(150)
  r.fill = Text(r, nil, "RIGHT"); r.fill:SetPoint("LEFT", 318, 0); r.fill:SetWidth(58)
  r.crate = Text(r, nil, "RIGHT"); r.crate:SetPoint("LEFT", 378, 0); r.crate:SetWidth(58)
  r.favor = Text(r); r.favor:SetPoint("LEFT", 440, 0); r.favor:SetWidth(36)
  r.per = Text(r, nil, "RIGHT"); r.per:SetPoint("LEFT", 478, 0); r.per:SetWidth(56)
  r.have = Text(r); r.have:SetPoint("LEFT", 540, 0); r.have:SetWidth(28)
  r.plan = Text(r); r.plan:SetPoint("LEFT", 570, 0); r.plan:SetWidth(30)
  Tooltip(r, function(self, tt)
    local c = self.c
    tt:AddLine(c.name, 0.91, 0.74, 0.47)
    tt:AddLine(("Requires level %d  ·  %d Favor%s"):format(c.lvl, c.favor, c.favorEst and " (estimated)" or ""), 1, 1, 1)
    if not c.levelOk then tt:AddLine("Your level is too low for this crate.", 1, 0.3, 0.3) end
    tt:AddLine("Fill with ANY ONE of:", 0.78, 0.72, 0.67)
    for _, o in ipairs(c.opts) do
      local cost = o.price and o.price * o.qty
      local tag = (o == c.best) and "  |cff5cc96b(cheapest)|r" or ""
      tt:AddDoubleLine(("%d× %s%s"):format(o.qty, o.name, tag), (cost and ns.Money(cost) or "no price") ..
        ((o.have or 0) > 0 and ("  |cff8a8178(%d in bags)|r"):format(o.have) or ""), 0.95, 0.92, 0.89)
    end
    tt:AddLine(" ")
    tt:AddDoubleLine("Empty crate on AH", ns.Money(c.crateP) .. (c.listed and ("  |cff8a8178%d listed|r"):format(c.listed) or ""), 0.78, 0.72, 0.67)
    tt:AddDoubleLine("In your bags", tostring(c.have or 0), 0.78, 0.72, 0.67, 1, 1, 1)
    tt:AddLine("Green sealed crates pay double Favor.", 0.54, 0.51, 0.47, true)
  end)
end, function(r, c)
  r.c = c
  r.name:SetText((c.levelOk and C.ink or "|cffff4d4d") .. c.short .. "|r")
  r.fillN:SetText(c.best and (C.mute .. c.best.qty .. "× " .. c.best.name .. "|r") or (C.warn .. "no prices|r"))
  r.fill:SetText(ns.Money(c.fill))
  r.crate:SetText(ns.Money(c.crateP))
  r.favor:SetText(C.good .. c.favor .. (c.favorEst and "?" or "") .. "|r")
  local per = ns.char.favorBuy and c.perBuy or c.perFill
  r.per:SetText(ns.Money(per))
  r.have:SetText((c.have or 0) > 0 and (C.title .. c.have .. "|r") or (C.mute .. "0|r"))
  r.plan:SetText(planCount[c] and (C.good .. planCount[c] .. "|r") or "")
end)
mList:SetPoint("TOPLEFT", 10, -128)
mList:SetPoint("BOTTOMRIGHT", -30, 40)

local mPlan
local mSend = Button(M, "Send to Auctionator", 150, function()
  if not mPlan then return end
  local _, msg = ns.SendListToAuctionator("Writ Planner Favor", ns.FavorNeeds(mPlan)); ns.Print(msg)
end)
mSend:SetPoint("BOTTOMRIGHT", -14, 10)
local mFoot = Text(M, "GameFontDisableSmall")
mFoot:SetPoint("BOTTOMLEFT", 16, 16)
mFoot:SetWidth(BW - 200)
mFoot:SetWordWrap(true)
mFoot:SetText("No daily limit on crates. Each crate shows its cheapest fill at live prices; hover for every option. Green crates pay double. Artisan Favor (20?) is estimated.")

local function UpdateFavor()
  ns.RefreshFavor()
  local bal = ns.FavorBalance()
  mBal:SetText(bal and ("You have " .. C.title .. bal .. "|r Favor") or (C.mute .. "Favor balance not readable|r"))
  if not goalBox:HasFocus() then goalBox:SetText(ns.char.favorGoal and tostring(ns.char.favorGoal) or "") end
  buyBtn:SetText(ns.char.favorBuy and "Buy crates on the AH" or "I have the crates")
  wipe(planCount)
  mPlan = nil
  if ns.repOnly then
    mSummary:SetText(C.warn .. "Merchant's Favor needs prices to rank crates. Open the auction house and press Scan AH prices, or install Auctionator, GoldScout or TSM. Hover a crate to see its fill options.|r")
  elseif ns.char.favorGoal and ns.char.favorGoal > 0 then
    mPlan = ns.FavorPlan(ns.char.favorGoal, ns.char.favorBuy)
    for _, l in ipairs(mPlan.lines) do planCount[l.c] = (planCount[l.c] or 0) + l.n end
    if mPlan.need <= 0 then
      mSummary:SetText(C.good .. "You already have enough Favor for that goal.|r")
    else
      local fromBags, bought = 0, 0
      for _, l in ipairs(mPlan.lines) do if l.fromBags then fromBags = fromBags + l.n else bought = bought + l.n end end
      local txt = ("Need %s%d|r more Favor: fill %s%d|r crate%s from your bags"):format(C.ink, mPlan.need, C.ink, fromBags, fromBags == 1 and "" or "s")
      if ns.char.favorBuy then txt = txt .. (" and buy %s%d|r more on the AH"):format(C.ink, bought) end
      txt = txt .. (". Total %s for %s+%d Favor|r."):format(ns.Money(mPlan.total), C.good, mPlan.favor)
      if mPlan.short then
        txt = txt .. C.warn .. (ns.char.favorBuy and " Not enough crates listed to reach the goal." or " Not enough crates in your bags: switch to Buy crates on the AH, or loot more.") .. "|r"
      end
      mSummary:SetText(txt)
    end
  else
    mSummary:SetText(C.mute .. "Pick a reward or type a Favor goal, then press Plan Favor. The list shows every crate's cheapest fill at today's prices.|r")
  end
  mSend:SetEnabled(mPlan ~= nil and next(mPlan.buy) ~= nil)
  -- sort
  local key, asc = ns.db.favorSortKey or "per", ns.db.favorSortAsc ~= false
  local list = {}
  for _, c in ipairs(ns.crates) do tinsert(list, c) end
  local function val(c)
    if key == "name" then return c.short:lower()
    elseif key == "fillName" then return c.best and c.best.name:lower() or nil
    elseif key == "per" then return ns.char.favorBuy and c.perBuy or c.perFill
    elseif key == "plan" then return planCount[c] or 0
    else return c[key] end
  end
  table.sort(list, function(a, b)
    local va, vb = val(a), val(b)
    if va == nil or vb == nil then
      if va == vb then return a.cid < b.cid end
      return vb == nil
    end
    if va == vb then return a.cid < b.cid end
    if asc then return va < vb else return va > vb end
  end)
  UpdateMHeaders()
  mList:SetData(list)
  ns.lastFavorPlan = mPlan
end

---------------------------------------------------------------------------
-- Page: Shopping list
---------------------------------------------------------------------------
local S = pages.shop
local shopHead = Text(S, "GameFontHighlight")
shopHead:SetPoint("TOPLEFT", 16, -16)
shopHead:SetWidth(BW - 32)
local shopList = CreateList(S, BW - 46, function(r)
  r.qty = Text(r, nil, "RIGHT"); r.qty:SetPoint("LEFT", 4, 0); r.qty:SetWidth(30)
  r.name = Text(r); r.name:SetPoint("LEFT", 44, 0); r.name:SetWidth(330)
  r.price = Text(r, nil, "RIGHT"); r.price:SetPoint("LEFT", 400, 0); r.price:SetWidth(110)
  r.src = Text(r, "GameFontDisableSmall"); r.src:SetPoint("LEFT", 524, 0)
  Tooltip(r, function(self, tt) WritTooltip(self.e.w, tt) end)
end, function(r, e)
  r.e = e
  r.qty:SetText(C.ink .. e.qty .. "×|r")
  r.name:SetText((e.isWrit and C.title or C.ink) .. e.name .. "|r" .. (e.isWrit and (C.mute .. "  (writ)|r") or ""))
  r.price:SetText(ns.Money(e.price and e.price * e.qty))
  r.src:SetText(SRC_SHORT[e.isWrit and e.w.sWrit or e.w.sItem] or "")
end)
shopList:SetPoint("TOPLEFT", 10, -44)
shopList:SetPoint("BOTTOMRIGHT", -30, 44)
local shopAH = Button(S, "Send to Auctionator", 150, function() local _, m = ns.SendToAuctionator(); ns.Print(m) end)
shopAH:SetPoint("BOTTOMRIGHT", -14, 12)
local shopNote = Text(S, "GameFontDisableSmall")
shopNote:SetPoint("BOTTOMLEFT", 16, 18)
shopNote:SetText("Items already in your bags are left off. You do the buying at the auction house.")

local function UpdateShop()
  local needs = ns.ShoppingNeeds()
  shopList:SetData(needs)
  local total = 0
  for _, e in ipairs(needs) do total = total + (e.price or 0) * e.qty end
  if #ns.char.run == 0 then shopHead:SetText(C.mute .. "Plan a run first.|r")
  elseif #needs == 0 then shopHead:SetText(C.good .. "Nothing left to buy for this run.|r")
  else shopHead:SetText(("%d lines  ·  about %s"):format(#needs, ns.Money(total))) end
  shopAH:SetEnabled(#needs > 0)
end

---------------------------------------------------------------------------
-- Page: Settings
---------------------------------------------------------------------------
local G = pages.settings
local y = -20
local function Row(h) local r = y; y = y - h; return r end

local srcLabel = Text(G, "GameFontNormal"); srcLabel:SetPoint("TOPLEFT", 16, Row(22)); srcLabel:SetText("Price source")
local srcBtn = Button(G, "", 200)
srcBtn:SetPoint("TOPLEFT", 16, Row(30))
srcBtn:SetScript("OnClick", function()
  for i, s in ipairs(ns.SOURCES) do
    if s == ns.db.source then ns.db.source = ns.SOURCES[i % #ns.SOURCES + 1]; break end
  end
  ns.dirty = true; ns.UpdateUI()
end)
local srcInfo = Text(G, "GameFontDisableSmall"); srcInfo:SetPoint("TOPLEFT", 16, Row(30)); srcInfo:SetWidth(BW - 40); srcInfo:SetWordWrap(true)

local function Check(label, get, set)
  local cb = CreateFrame("CheckButton", nil, G, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", 12, Row(30))
  local t = Text(G, "GameFontHighlight"); t:SetPoint("LEFT", cb, "RIGHT", 4, 0); t:SetText(label)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); ns.dirty = true; ns.UpdateUI() end)
  cb.get = get
  return cb
end
local cbMini = Check("Show minimap button", function() return not ns.db.minimap.hide end, function(v)
  ns.db.minimap.hide = not v
  if ns.minimapButton then ns.minimapButton:SetShown(v) end
end)
local cbUnknown = Check("Include writs with an unknown turn-in NPC in plans", function() return ns.db.showUnknown end,
  function(v) ns.db.showUnknown = v end)
local cbAH = Check("Show a Writ Planner button on the auction house", function() return ns.db.ahButton ~= false end,
  function(v) ns.db.ahButton = v; if ns.OnAHShown then ns.OnAHShown() end end)

local scaleLabel = Text(G, "GameFontNormal"); scaleLabel:SetPoint("TOPLEFT", 16, Row(26))
local function setScale(d)
  local v = floor(((ns.db.scale or 1) + d) * 20 + 0.5) / 20
  v = max(0.7, min(1.3, v))
  ns.db.scale = v; F:SetScale(v); ns.UpdateUI()
end
local scaleDown = Button(G, "-", 30, function() setScale(-0.05) end)
scaleDown:SetPoint("TOPLEFT", 16, Row(34))
local scaleUp = Button(G, "+", 30, function() setScale(0.05) end)
scaleUp:SetPoint("LEFT", scaleDown, "RIGHT", 4, 0)

local resetPos = Button(G, "Reset window position", 170, function()
  ns.db.pos = nil; F:ClearAllPoints(); F:SetPoint("CENTER")
end)
resetPos:SetPoint("TOPLEFT", 16, Row(36))

local scanHead = Text(G, "GameFontNormal"); scanHead:SetPoint("TOPLEFT", 16, Row(22)); scanHead:SetText("Auction house scan (no price addon needed)")
local scanBtn = Button(G, "Scan auction house", 160, function() if ns.Scan then ns.Scan:Start() end end)
scanBtn:SetPoint("TOPLEFT", 16, Row(30))
local scanStatus = Text(G, "GameFontHighlightSmall"); scanStatus:SetPoint("LEFT", scanBtn, "RIGHT", 10, 0); scanStatus:SetWidth(BW - 210)
local scanNote = Text(G, "GameFontDisableSmall"); scanNote:SetPoint("TOPLEFT", 16, Row(44)); scanNote:SetWidth(BW - 40); scanNote:SetWordWrap(true)
scanNote:SetText("Open the auction house and press Scan: it reads the lowest buyout and quantity for the items Writ Planner uses, and is read-only (it never buys or posts). " ..
  "Running TSM, Auctionator or GoldScout as well may give better results: they scan more often and track market values over time, while this scan is a snapshot of the cheapest listings right now.")

local about = Text(G, "GameFontDisableSmall")
about:SetPoint("BOTTOMLEFT", 16, 14)
about:SetWidth(BW - 32)
about:SetWordWrap(true)
about:SetJustifyV("BOTTOM")
about:SetText("Writ Planner only shows information: it never buys, posts, turns in or moves for you. " ..
  "Prices: Auctionator, TradeSkillMaster, GoldScout (Blizzard Game Data API) when installed, otherwise " ..
  (ns.SNAPSHOT and ("a bundled snapshot (" .. ns.SNAPSHOT .. ")") or "none (plans go by rep only)") .. ". Turn-in data: Questie (GPL-3.0). Commands: /writplan, /writplan reset.")

local function ScanStatusText()
  if ns.Scan and ns.Scan:IsRunning() then
    local c = ns.Scan.cur
    return C.title .. ("Scanning... %d pages, %d listings"):format(c.pages, c.seen) .. "|r"
  end
  local t, n
  if ns.ScanInfo then t, n = ns.ScanInfo() end
  local ago = t and floor((time() - t) / 60)
  local when = not t and "No scan yet on this realm and faction." or
    (ago < 60 and ("Last scan %d min ago"):format(ago) or ago < 1440 and ("Last scan %d h ago"):format(floor(ago / 60)) or ("Last scan %d days ago"):format(floor(ago / 1440)))
  if t then when = when .. (" · %d items priced"):format(n) end
  if ns.Scan and not ns.Scan.ahOpen then when = when .. C.mute .. "  (open the auction house to scan)|r" end
  return when
end
ns.ScanStatusText = ScanStatusText

local function UpdateSettings()
  srcBtn:SetText(ns.SOURCE_LABEL[ns.db.source] or ns.db.source)
  local av = ns.SourcesAvailable()
  srcInfo:SetText("Installed: " .. (#av > 0 and table.concat(av, ", ") or (ns.SNAPSHOT and "none (using the bundled snapshot)" or "none: press Scan at the auction house, or install Auctionator, GoldScout or TSM")) ..
    ". Auto uses GoldScout (hourly), then Auctionator (your last scan), then TSM, then Writ Planner's own scan" .. (ns.SNAPSHOT and ", then the snapshot." or "."))
  cbMini:SetChecked(cbMini.get()); cbUnknown:SetChecked(cbUnknown.get()); cbAH:SetChecked(cbAH.get())
  scanStatus:SetText(ScanStatusText())
  scanBtn:SetEnabled(ns.Scan and ns.Scan.ahOpen and not ns.Scan:IsRunning())
  scaleLabel:SetText(("Window scale: %d%%"):format(floor((ns.db.scale or 1) * 100 + 0.5)))
end

---------------------------------------------------------------------------
-- Update dispatcher
---------------------------------------------------------------------------
function ns.UpdateUI()
  if not ns.char or not F:IsShown() then return end
  if ns.dirty then ns.Refresh(); ns.dirty = false end
  L = ns.char.levelOverride or ns.PlayerLevel()
  if ns.Scan then
    titleScan:SetShown(ns.Scan.ahOpen)
    topNote:SetPoint("RIGHT", F, "RIGHT", ns.Scan.ahOpen and -148 or -34, 0)
    titleScan:SetText(ns.Scan:IsRunning() and ("Scanning %d"):format(ns.Scan.cur.pages) or "Scan AH prices")
    titleScan:SetEnabled(not ns.Scan:IsRunning())
  end
  sub:SetText(("%s · level %d"):format(ns.PlayerFaction(), ns.PlayerLevel()))
  local name, cur, size, label = ns.GetRep()
  if name then
    repText:SetText(C.title .. name .. "|r")
    repStanding:SetText(C.mute .. (label or "") .. (size and size > 0 and ("  %d / %d"):format(cur, size) or "") .. "|r")
    repBar:SetValue((size and size > 0) and min(1, max(0, cur / size)) or 0)
    repBar:Show()
  else
    repText:SetText(""); repStanding:SetText(""); repBar:Hide()
  end
  if current == "plan" then UpdatePlan()
  elseif current == "all" then UpdateAll()
  elseif current == "exalted" then UpdateExalted()
  elseif current == "favor" then UpdateFavor()
  elseif current == "shop" then UpdateShop()
  elseif current == "settings" then UpdateSettings() end
end

F:SetScript("OnShow", function()
  if ns.CheckReset then ns.CheckReset() end
  ns.dirty = true
  ShowPage(current or "plan")
end)

if ns.Scan then
  ns.Scan.status = function() if F:IsShown() then ns.UpdateUI() end end
end

-- "Writ Planner" button at the end of the auction house tab row. A plain button anchored after the
-- last tab (not a real tab), so Blizzard's tab system and other addons' tabs are left untouched.
local ahButton
local function PlaceAHButton()
  local ah = AuctionHouseFrame
  if not ah or ns.db.ahButton == false then
    if ahButton then ahButton:Hide() end
    return
  end
  if not ahButton then
    ahButton = CreateFrame("Button", "WritPlannerAHButton", ah, "UIPanelButtonTemplate")
    ahButton:SetSize(100, 22)
    ahButton:SetText("Writ Planner")
    ahButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ahButton:SetScript("OnClick", function(_, btn)
      if btn == "RightButton" then
        if ns.Scan then ns.Scan:Start() end
      else
        ns.Toggle()
      end
    end)
    ahButton:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine("Writ Planner")
      GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
      GameTooltip:AddLine("Right-click: scan auction house prices (read-only)", 1, 1, 1)
      GameTooltip:Show()
    end)
    ahButton:SetScript("OnLeave", GameTooltip_Hide)
  end
  -- find the right-most visible button sitting along the bottom edge (Blizzard's and other addons' tabs)
  local best, bestR
  local bottom = ah:GetBottom()
  local function consider(f)
    if f == ahButton or type(f) ~= "table" or not f.IsShown or not f:IsShown() or not f.GetRight then return end
    local r, top = f:GetRight(), f:GetTop()
    if r and top and bottom and top <= bottom + 6 and top >= bottom - 40 and (not bestR or r > bestR) then
      best, bestR = f, r
    end
  end
  if type(ah.Tabs) == "table" then for _, t in ipairs(ah.Tabs) do consider(t) end end
  for _, child in ipairs({ ah:GetChildren() }) do consider(child) end
  ahButton:ClearAllPoints()
  if best then
    ahButton:SetPoint("LEFT", best, "RIGHT", 3, 0)
  else
    ahButton:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", 0, 2)
  end
  ahButton:Show()
end
-- other addons add their tabs when the AH opens, so place ours after a short delay (and once more later)
ns.OnAHShown = function()
  C_Timer.After(0.3, PlaceAHButton)
  C_Timer.After(2, PlaceAHButton)
end

function ns.Toggle()
  if not ns.char then return end
  if F:IsShown() then F:Hide() else F:Show() end
end

local function restore()
  if ns.db.pos then
    local p = ns.db.pos
    F:ClearAllPoints()
    F:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 0, p[4] or 0)
  end
  F:SetScale(ns.db.scale or 1)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function() restore() end)

---------------------------------------------------------------------------
-- Minimap button (drag to move around the minimap)
---------------------------------------------------------------------------
function ns.CreateMinimapButton()
  if ns.minimapButton or not Minimap then return end
  local b = CreateFrame("Button", "WritPlannerMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  local function place()
    local a = math.rad(ns.db.minimap.angle or 200)
    local r = (Minimap:GetWidth() / 2) + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  end
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      ns.db.minimap.angle = math.deg(math.atan2(py / s - my, px / s - mx)) % 360
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
      if not F:IsShown() then F:Show() end
      ShowPage("settings")
    else ns.Toggle() end
  end)
  Tooltip(b, function(_, tt)
    tt:AddLine("Writ Planner")
    tt:AddLine("Left-click: open / close", 1, 1, 1)
    tt:AddLine("Right-click: settings", 1, 1, 1)
    tt:AddLine("Drag: move", 1, 1, 1)
  end)
  place()
  b:SetShown(not ns.db.minimap.hide)
  ns.minimapButton = b
end

---------------------------------------------------------------------------
-- Slash command and Addon Compartment
---------------------------------------------------------------------------
SLASH_WRITPLANNER1 = "/writplan"
SLASH_WRITPLANNER2 = "/writplanner"
SlashCmdList.WRITPLANNER = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "reset" then
    ns.db.pos = nil; ns.db.scale = 1; F:SetScale(1); F:ClearAllPoints(); F:SetPoint("CENTER")
    ns.Print("Window position and scale reset.")
  elseif msg == "minimap" then
    ns.db.minimap.hide = not ns.db.minimap.hide
    if ns.minimapButton then ns.minimapButton:SetShown(not ns.db.minimap.hide) end
  elseif msg == "help" then
    ns.Print("/writplan — open/close · /writplan reset — reset window · /writplan minimap — toggle minimap button")
  else
    ns.Toggle()
  end
end

function WritPlanner_OnAddonCompartmentClick()
  ns.Toggle()
end
