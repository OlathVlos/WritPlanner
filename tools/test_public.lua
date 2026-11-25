-- Minimal permissive WoW API mock
time, date = os.time, os.date
local calls = {}
local function obj(kind)
  local o = { __kind = kind, scripts = {}, shown = false, text = "", checked = false, w = 100, h = 20 }
  return setmetatable(o, { __index = function(t, k)
    local f = function(self, ...)
      local a = ...
      if k == "SetScript" then self.scripts[a] = select(2, ...); return end
      if k == "GetScript" then return self.scripts[a] end
      if k == "Show" then self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end return end
      if k == "Hide" then self.shown = false; return end
      if k == "SetShown" then if a then self:Show() else self:Hide() end return end
      if k == "IsShown" then return self.shown end
      if k == "SetText" then self.text = a or ""; return end
      if k == "GetText" then return self.text end
      if k == "SetChecked" then self.checked = a and true or false; return end
      if k == "GetChecked" then return self.checked end
      if k == "HasFocus" then return false end
      if k == "GetWidth" then return 140 end
      if k == "GetCenter" then return 100, 100 end
      if k == "GetEffectiveScale" then return 1 end
      if k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0 end
      if k == "CreateTexture" or k == "CreateFontString" then return obj(k) end
      if k == "Click" then if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end return end
      if k == "RegisterEvent" then if a == "BAD_EVENT" then error("unknown event") end; EVENTS[#EVENTS+1] = {self, a}; return end
      return nil
    end
    rawset(t, k, f); return f
  end })
end
EVENTS = {}
function CreateFrame(kind, name, parent, template) local o = obj(kind); if name then _G[name] = o end; return o end
UIParent, Minimap, GameTooltip = obj("f"), obj("f"), obj("tt")
GameTooltip_Hide = function() end
UISpecialFrames, SlashCmdList = {}, {}
BackdropTemplateMixin = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("CHAT", m) end }
C_Timer = { After = function(_, fn) fn() end }
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
BreakUpLargeNumbers = function(n) return tostring(n) end
UnitFactionGroup = function() return FACTION or "Horde" end
UnitLevel = function() return 38 end
GetQuestResetTime = function() return 3600 end
GetCursorPosition = function() return 0, 0 end
BAGS = {}
C_Item = { GetItemCount = function(id) return BAGS[id] or 0 end, GetItemNameByID = function() return nil end }
DONE = {}
C_QuestLog = { IsQuestFlaggedCompleted = function(q) return DONE[q] or false end }
C_Reputation = { GetFactionDataByID = function(id) return { name = "Durotar Supply and Logistics", currentStanding = 4200, currentReactionThreshold = 3000, nextReactionThreshold = 9000, reaction = 5 } end }
FACTION_STANDING_LABEL5 = "Friendly"
-- Auctionator mock
SHOP = nil
AuctionatorX = { API = { v1 = {
  GetAuctionPriceByItemID = function(c, id) assert(c == "WritPlanner"); if id == 3391 then return 999 end end,
  ConvertToSearchString = function(c, t) return '"' .. t.searchString .. '";;;;;;;;;;;;;' .. t.quantity end,
  CreateShoppingList = function(c, n, terms) SHOP = { n, terms } end } } }
TomTomX = { IsCrazyArrowEmpty = function() end, AddWaypoint = function(self, m, x, y, o) WP = (WP or 0) + 1; assert(x <= 1 and y <= 1 and o.title) end }

local function load(file)
  local f = assert(loadfile(DIR .. file))
  f("WritPlanner", NS)
end
NS = {}
for _, f in ipairs({ "Data.lua", "Core.lua", "Scan.lua", "UI.lua" }) do load(f) end
local function fire(ev, ...) for _, e in ipairs(EVENTS) do if e[2] == ev then e[1].scripts.OnEvent(e[1], ev, ...) end end end
fire("ADDON_LOADED", "WritPlanner"); fire("PLAYER_LOGIN")

local ns = NS
assert(#ns.list == 150 and #ns.crates == 30)
SlashCmdList.WRITPLANNER("")
assert(WritPlannerFrame.shown)
ns.dirty = true; ns.Refresh()
assert(ns.repOnly == true, "rep-only mode when no prices")
local n, spent, rep = ns.Plan(5 * 10000, 1000)
print(("rep-only plan: %d writs, +%d rep, spent %d"):format(n, rep, spent))
assert(n > 0 and rep >= 1000 and spent == 0)
local prev = 999; for _, q in ipairs(ns.char.run) do local r = ns.byQid[q].rep; assert(r <= prev, "highest rep first"); prev = r end
C_Reputation.GetFactionDataByID = function() return { name = "D", currentStanding = 2000, currentReactionThreshold = 0, nextReactionThreshold = 3000, reaction = 4 } end
local res = ns.ExaltedPlan(nil); print("rep-only exalted days:", #res.days, "total cost", res.total); assert(res.complete and res.total == 0)
for _, p in ipairs({ "plan", "exalted", "favor", "all", "shop", "settings", "plan" }) do ns.ShowPage(p) end
ns.OpenExDay(1); ns.ShowPage("exalted")
-- installing a price addon later switches to normal pricing
GoldScoutPricesData = { markets = { ["X-Horde"] = { items = { [3391] = { 700, 3 }, [264011] = { 5000, 2 } } } } }
ns.dirty = true; ns.Refresh(); assert(not ns.repOnly and ns.byQid[94004].cost == 5700, "prices appear with GoldScout")
ns.ShowPage("favor")
print("PUBLIC BUILD TESTS PASSED")

GoldScoutPricesData = nil
local ns = NS
local function fire(ev, ...) for _, e in ipairs(EVENTS) do if e[2] == ev then e[1].scripts.OnEvent(e[1], ev, ...) end end end
-- deferred timers
local timers = {}
C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
C_Timer.NewTicker = function(_, fn) return { Cancel = function() end } end
GetRealmName = function() return "Realm1" end
GetTime = function() return os.time() end
local w = ns.byQid[94004]
local results, sent, ready = {}, 0, true
local page1 = { { itemKey = { itemID = w.iid }, minPrice = 400, totalQuantity = 7 }, { itemKey = { itemID = 999999 }, minPrice = 5, totalQuantity = 1 } }
local page2 = { { itemKey = { itemID = w.wid }, minPrice = 6000, totalQuantity = 2 }, { itemKey = { itemID = w.iid, itemLevel = 5 }, minPrice = 350, totalQuantity = 3 } }
local full = false
C_AuctionHouse = {
  IsThrottledMessageSystemReady = function() return ready end,
  SendBrowseQuery = function(q) sent = sent + 1; assert(q.searchString == ""); for _, r in ipairs(page1) do results[#results + 1] = r end end,
  GetBrowseResults = function() return results end,
  HasFullBrowseResults = function() return full end,
  RequestMoreBrowseResults = function() sent = sent + 1; for _, r in ipairs(page2) do results[#results + 1] = r end; full = true end,
}
Auctionator = nil; GoldScoutPricesData = nil; TSM_API = nil; ns.db.source = "auto"
-- not at AH: refuses
assert(ns.Scan:Start() == false)
fire("AUCTION_HOUSE_SHOW")
assert(ns.Scan.ahOpen)
-- throttled: nothing sent until ready
ready = false
assert(ns.Scan:Start())
assert(sent == 0, "waits for throttle")
ready = true; fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
assert(sent == 1)
fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")   -- page 1 -> requests more
assert(sent == 2, "requests next page")
fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")     -- page 2 -> full -> finish
assert(not ns.Scan:IsRunning(), "finished")
local p, q = ns.FromScan(w.iid); assert(p == 350 and q == 10, "merged item levels: min price, summed qty " .. tostring(p) .. " " .. tostring(q))
assert(ns.FromScan(999999) == nil, "unwanted items dropped")
assert(ns.FromScan(w.wid) == 6000)
local s = ns.db.scans["Realm1-Horde"]; print("scan log:", s.log[1]); assert(s.last.kept == 2 and s.last.complete)
-- prices flow into planner
ns.dirty = true; ns.Refresh()
assert(not ns.repOnly and w.pItem == 350 and w.sItem == "scan", "scan used as price source")
ns.ShowPage("settings"); ns.ShowPage("plan")
-- other addons win over scan
GoldScoutPricesData = { markets = { ["X-Horde"] = { items = { [w.iid] = { 500, 1 } } } } }
ns.Refresh(); assert(w.pItem == 500 and w.sItem == "goldscout"); GoldScoutPricesData = nil
-- timeout path
results, full = {}, false
C_AuctionHouse.SendBrowseQuery = function() sent = sent + 1 end -- no reply
ns.Scan:Start(); for _, t in ipairs(timers) do t() end
assert(not ns.Scan:IsRunning(), "timeout ends scan"); assert(ns.FromScan(w.iid) == 350, "old prices kept when nothing new came back")
-- AH closed mid-scan
timers = {}; ns.Scan:Start(); fire("AUCTION_HOUSE_CLOSED"); assert(not ns.Scan:IsRunning() and not ns.Scan.ahOpen)
-- browse failure
fire("AUCTION_HOUSE_SHOW"); ns.Scan:Start(); fire("AUCTION_HOUSE_BROWSE_FAILURE"); assert(not ns.Scan:IsRunning())
-- sell tab pause
AuctionHouseFrame = { ItemSellFrame = { IsVisible = function() return true end } }
local before = sent; ns.Scan:Start(); assert(sent == before, "paused while Sell tab open")
AuctionHouseFrame.ItemSellFrame.IsVisible = function() return false end; fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY"); assert(sent == before + 1, "resumes")
fire("AUCTION_HOUSE_BROWSE_FAILURE")
-- unsupported client
local keep = C_AuctionHouse; C_AuctionHouse = nil; assert(ns.Scan:Start() == false); C_AuctionHouse = keep
print("log entries:", #s.log)
print("SCAN TESTS PASSED")

local ns = NS
local timers = {}
C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
local function tab(name, right) return { name = name, IsShown = function() return true end, GetRight = function() return right end, GetTop = function() return 98 end } end
local deals = tab("Deals", 765)
local tabs = { tab("Buy", 60), tab("Sell", 110), tab("Auctions", 170) }
local others = { tab("Gold Capped", 300), tab("Auctionator", 600), deals, { IsShown = function() return true end, GetRight = function() return 900 end, GetTop = function() return 400 end } }
local anchored
AuctionHouseFrame = CreateFrame("Frame")
AuctionHouseFrame.Tabs = tabs
AuctionHouseFrame.GetBottom = function() return 100 end
AuctionHouseFrame.GetChildren = function() return unpack(others) end
for _, e in ipairs(EVENTS) do if e[2] == "AUCTION_HOUSE_CLOSED" then e[1].scripts.OnEvent(e[1], "AUCTION_HOUSE_CLOSED") end end
for _, e in ipairs(EVENTS) do if e[2] == "AUCTION_HOUSE_SHOW" then e[1].scripts.OnEvent(e[1], "AUCTION_HOUSE_SHOW") end end
for _, t in ipairs(timers) do t() end
local b = WritPlannerAHButton
assert(b and b.shown, "button shown")
-- inspect anchor: our mock records SetPoint calls? patch to capture
b.SetPoint = function(self, p, rel, rp) anchored = rel end
for _, e in ipairs(EVENTS) do if e[2] == "AUCTION_HOUSE_CLOSED" then e[1].scripts.OnEvent(e[1], "AUCTION_HOUSE_CLOSED") end end
timers = {}
for _, e in ipairs(EVENTS) do if e[2] == "AUCTION_HOUSE_SHOW" then e[1].scripts.OnEvent(e[1], "AUCTION_HOUSE_SHOW") end end
for _, t in ipairs(timers) do t() end
assert(anchored == deals, "anchored after the last tab (Deals), not the off-row frame")
print("anchored after:", anchored.name)
-- right-click starts scan, left toggles window
local wasShown = WritPlannerFrame.shown
b.scripts.OnClick(b, "LeftButton"); assert(WritPlannerFrame.shown ~= wasShown)
-- setting off hides it
ns.db.ahButton = false; timers = {}; ns.OnAHShown(); for _, t in ipairs(timers) do t() end; assert(not b.shown, "hidden when setting off")
ns.db.ahButton = nil
print("AH BUTTON TESTS PASSED")

-- old "-Horde" scans carry over to the realm-named key
local ns = NS
GetRealmName = function() return "" end
GetNormalizedRealmName = function() return "" end
ns.db.scans = { ["-Horde"] = { items = { [123] = { 77, 1 } }, time = 1 } }
assert(ns.FromScan(123) == 77, "old -Horde scan migrated")
assert(ns.db.scans["Forever-Horde"] and not ns.db.scans["-Horde"])
print("MIGRATION PASSED")
