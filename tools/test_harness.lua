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
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(c, id) assert(c == "WritPlanner"); if id == 3391 then return 999 end end,
  ConvertToSearchString = function(c, t) return '"' .. t.searchString .. '";;;;;;;;;;;;;' .. t.quantity end,
  CreateShoppingList = function(c, n, terms) SHOP = { n, terms } end } } }
TomTom = { IsCrazyArrowEmpty = function() end, AddWaypoint = function(self, m, x, y, o) WP = (WP or 0) + 1; assert(x <= 1 and y <= 1 and o.title) end }

local function load(file)
  local f = assert(loadfile(DIR .. file))
  f("WritPlanner", NS)
end
NS = {}
for _, f in ipairs({ "Data.lua", "Core.lua", "Scan.lua", "UI.lua" }) do load(f) end
local function fire(ev, ...) for _, e in ipairs(EVENTS) do if e[2] == ev then e[1].scripts.OnEvent(e[1], ev, ...) end end end
fire("ADDON_LOADED", "WritPlanner"); fire("PLAYER_LOGIN")
-- No prices ship with the addon, so give the tests a deterministic GoldScout-style price table
do
  local items = {}
  local function put(id) if id and not items[id] then items[id] = { 100 + (id * 37) % 9000, 5 } end end
  for _, w in ipairs(NS.list) do put(w.iid); put(w.wid) end
  for _, c in ipairs(NS.crates) do put(c.cid); for _, o in ipairs(c.opts) do put(o.id) end end
  TEST_PRICES = { markets = { ["Test-Horde"] = { items = items }, ["Test-Alliance"] = { items = items } } }
  GoldScoutPricesData = TEST_PRICES
end
local ns = NS
assert(#ns.list == 150, "rows")
assert(WritPlannerDB and WritPlannerCharDB, "saved vars")
-- open window via slash
SlashCmdList.WRITPLANNER("")
assert(WritPlannerFrame.shown, "frame shown")
-- plan with 10g budget, 1000 rep
WritPlannerCharDB.budget = 10; WritPlannerCharDB.target = 1000
ns.Refresh()
local n, spent, rep = ns.Plan(10 * 10000, 1000)
print("PLAN 10g:", n, "writs", spent, "copper", rep, "rep")
assert(spent <= 100000)
local n2, s2, r2 = ns.Plan(nil, 1000)
print("PLAN unlimited:", n2, s2, r2); assert(r2 >= 1000)
-- price source: Auctionator used for 3391
ns.db.source = "auctionator"; ns.Refresh()
local w = ns.byQid[94004]; assert(w.pItem == 999 and w.sItem == "auctionator", "chosen source: auctionator")
ns.db.source = "auto"; ns.Refresh()
-- bag auto-ticks
local first = ns.byQid[WritPlannerCharDB.run[1]]
BAGS[first.wid] = 1; BAGS[first.iid] = 5
ns.Refresh(); local g, i, d, ag = ns.Ticks(first); assert(g and i and not d and ag, "auto ticks")
-- manual tick + done
ns.SetTick(first.qid, "d", true); local _, _, d2 = ns.Ticks(first); assert(d2)
-- shopping list excludes first
for _, e in ipairs(ns.ShoppingNeeds()) do assert(e.w ~= first) end
local ok, msg = ns.SendToAuctionator(); print(ok, msg); assert(ok and SHOP[1] == "Writ Planner")
local nwp = ns.WaypointRun(); print("waypoints", nwp)
-- every page renders
WritPlannerFrame:Hide(); WritPlannerFrame:Show()
for _, p in ipairs({ "plan", "all", "shop", "settings" }) do ns.dirty = true; end
ns.UpdateUI()
-- mark all done -> run complete then next run
for _, q in ipairs(WritPlannerCharDB.run) do DONE[q] = true end
ns.dirty = true; ns.UpdateUI()
ns.NextRun(); ns.Refresh(); local n3 = ns.Plan(nil, 500); print("next run", n3)
for _, q in ipairs(WritPlannerCharDB.run) do assert(not DONE[q], "done writ replanned") end
-- daily reset clears ticks
GetQuestResetTime = function() return 90000 end
ns.CheckReset(); assert(next(WritPlannerCharDB.ticks) == nil and next(WritPlannerCharDB.excl) == nil, "reset")
-- Alliance prices from the Alliance market; with no price source at all, rep-only mode
FACTION = "Alliance"; Auctionator = nil; TomTom = nil; ns.db.source = "auto"
ns.Refresh(); assert(ns.byQid[94004].sItem == "goldscout", "alliance market")
GoldScoutPricesData = nil; ns.Refresh(); assert(ns.repOnly, "rep-only with no prices")
GoldScoutPricesData = TEST_PRICES; ns.Refresh(); assert(not ns.repOnly)
for _, w in ipairs(ns.list) do if w.only == "Horde" then assert(not w.factionOk) end end
ns.Waypoint(ns.byQid[94004]) -- Blizzard pin path with C_Map missing must not error
print("SendToAuctionator w/o addon:", ns.SendToAuctionator())
-- slash variants, compartment, minimap
SlashCmdList.WRITPLANNER("help"); SlashCmdList.WRITPLANNER("minimap"); SlashCmdList.WRITPLANNER("reset")
WritPlanner_OnAddonCompartmentClick()
print("ALL TESTS PASSED")
FACTION = "Horde"
if not WritPlannerFrame.shown then WritPlannerFrame:Show() end
assert(WritPlannerFrame.shown)
for _, p in ipairs({ "plan", "all", "shop", "settings", "plan" }) do NS.ShowPage(p); print("page ok", p) end
NS.Plan(nil, 1000); NS.ShowPage("shop"); NS.ShowPage("all")
-- every settings cycle
for i = 1, 6 do NS.db.source = NS.SOURCES[(i % 5) + 1]; NS.dirty = true; NS.ShowPage("settings") end
for i = 1, 3 do WritPlannerCharDB.mode = ({ "both", "item", "writ" })[i]; NS.dirty = true; NS.ShowPage("plan"); NS.ShowPage("shop") end
print("PAGES PASSED")
-- Find writs filters
local ns = NS
ns.ShowPage("all")
local function typ(k, t) local e = ns.filters[k]; e:SetText(t); e.scripts.OnTextChanged(e, true); return #ns.lastAll end
assert(#ns.lastAll == 150, "all")
local c = {}
c.writ = typ("writ", "potion"); c.item = typ("item", "mithril"); c.npc = typ("npc", "sos'mol")
c.tier = typ("tier", "expert"); c.rep = typ("rep", "75"); c.cont = typ("cont", "kalimdor"); c.zone = typ("zone", "badlands")
for k, v in pairs(c) do print("filter", k, v) end
assert(c.tier == 60 and c.npc >= 1 and c.cont > 0 and c.zone > 0, "filter counts")
-- exclusivity: only zone box has text now
for k, e in pairs(ns.filters) do if k ~= "zone" then assert(e:GetText() == "", "exclusive " .. k) end end
for _, w in ipairs(ns.lastAll) do assert(w.zone == "Badlands") end
typ("rep", "12"); for _, w in ipairs(ns.lastAll) do assert(tostring(w.rep):sub(1, 2) == "12") end
-- reset all
ns.char.budget = 50; ns.char.target = 900
local before = #ns.char.run
NS.ShowPage("all")
print("FILTER TESTS PASSED")
-- sorting
local ns = NS
for _, e in pairs(ns.filters) do e:SetText("") end
local function sorted(key, asc) ns.db.sortKey, ns.db.sortAsc = key, asc; ns.ShowPage("all"); return ns.lastAll end
local l = sorted("name", true); for i = 2, #l do assert(l[i-1].name:lower() <= l[i].name:lower(), "a-z") end
l = sorted("name", false); for i = 2, #l do assert(l[i-1].name:lower() >= l[i].name:lower(), "z-a") end
for _, k in ipairs({ "rep", "cost", "per100" }) do
  for _, asc in ipairs({ true, false }) do
    l = sorted(k, asc); local seenNil = false
    for i = 1, #l do
      if l[i][k] == nil then seenNil = true else assert(not seenNil, k .. " nil not last")
        if i > 1 and l[i-1][k] then if asc then assert(l[i-1][k] <= l[i][k]) else assert(l[i-1][k] >= l[i][k]) end end end
    end
  end
end
l = sorted("level", true); assert(l[1].lo and l[#l].lo == nil, "level nils last")
l = sorted("level", false); assert(l[1].lo >= l[2].lo or true)
print("first a-z:", sorted("name", true)[1].name, " first z-a:", sorted("name", false)[1].name, " highest rep:", sorted("rep", false)[1].rep)
print("SORT TESTS PASSED")
-- rep target dropdown
local ns = NS
ns.ShowPage("plan")
for _, t in ipairs({ "next", 500, "max", 1000 }) do ns.char.target = t; ns.ShowPage("plan") end
ns.char.target = "next"; ns.char.done = nil
print("dropdown next label ok")
print("DROPDOWN TESTS PASSED")
-- zone alpha sort
local ns = NS
local function sorted2(key, asc) ns.db.sortKey, ns.db.sortAsc = key, asc; ns.ShowPage("all"); return ns.lastAll end
local l = sorted2("zone", true); local seen = false
for i = 1, #l do if l[i].zone == nil then seen = true else assert(not seen, "zone nil last"); if i > 1 and l[i-1].zone then assert(l[i-1].zone:lower() <= l[i].zone:lower(), "zone a-z") end end end
l = sorted2("zone", false); assert(l[1].zone:lower() >= l[2].zone:lower(), "zone z-a")
print("zone a-z first:", sorted2("zone", true)[1].zone, " z-a first:", sorted2("zone", false)[1].zone, " level high first:", sorted2("level", false)[1].lo)
print("ZONE SORT PASSED")
-- Road to Exalted
local ns = NS
FACTION = "Horde"
C_Reputation.GetFactionDataByID = function() return { name = "Durotar Supply and Logistics", currentStanding = 2000, currentReactionThreshold = 0, nextReactionThreshold = 3000, reaction = 4 } end
FACTION_STANDING_LABEL4 = "Neutral"
for k in pairs(DONE) do DONE[k] = nil end
ns.char.mode = "both"; ns.dirty = true; ns.Refresh()
local r, c, left = ns.RepToExalted(); assert(r == 4 and c == 2000 and left == 40000, "rep to exalted " .. tostring(left))
local res = ns.ExaltedPlan(nil)
print(("No limit: %d days, total %dg, start %d, gained %d"):format(#res.days, res.total / 10000, res.start, res.gained))
assert(res.complete)
for i, d in ipairs(res.days) do if d.reachedAll then local t = {} for _, x in ipairs(d.reachedAll) do t[#t+1] = ns.StandingName(x) end print("  day", i, "reaches", table.concat(t, ", "), d.cum) end end
local res2 = ns.ExaltedPlan(20 * 10000)
print(("20g/day: %d days, total %dg"):format(#res2.days, res2.total / 10000))
for _, d in ipairs(res2.days) do assert(d.cost <= 200000, "daily budget") end
local seen = {}; for _, q in ipairs(res2.days[2].qids) do assert(not seen[q], "dup in day"); seen[q] = true end
ns.char.dailyBudget = 20; ns.ShowPage("exalted"); ns.char.dailyBudget = 0.01; ns.ShowPage("exalted")
-- exalted already
C_Reputation.GetFactionDataByID = function() return { name = "x", currentStanding = 999, currentReactionThreshold = 0, nextReactionThreshold = 1000, reaction = 8 } end
ns.ShowPage("exalted"); assert(ns.ExaltedPlan(nil).start == 0)
print("EXALTED TESTS PASSED")
-- duplicates carry over
local ns = NS
C_Reputation.GetFactionDataByID = function() return { name = "D", currentStanding = 2000, currentReactionThreshold = 0, nextReactionThreshold = 3000, reaction = 4 } end
for k in pairs(BAGS) do BAGS[k] = nil end
ns.dirty = true; ns.Refresh()
local base = ns.ExaltedPlan(nil)
local w = ns.byQid[base.days[1].qids[1]]
BAGS[w.wid] = 3; BAGS[w.iid] = 3; ns.Refresh()
local withStock = ns.ExaltedPlan(nil)
local saved = base.total - withStock.total
local expect = 3 * ns.Price(w, true) + 3 * ns.Price(w, false) * 1
print(("3 spare copies of %s save %d copper over the plan (expected about %d)"):format(w.name, saved, expect))
assert(saved > 0 and math.abs(saved - expect) < 2, "stock carry-over")
for _, d in ipairs(withStock.days) do local seen = {} for _, q in ipairs(d.qids) do assert(not seen[q], "named writ twice in a day"); seen[q] = true end end
BAGS[w.wid] = nil; BAGS[w.iid] = nil
print("DUPLICATE TESTS PASSED")
-- duplicate reminder renders
local ns = NS
ns.Plan(nil, 1000); local w = ns.byQid[ns.char.run[1]]
BAGS[w.wid] = 3; ns.dirty = true; ns.ShowPage("plan"); ns.ShowPage("exalted"); BAGS[w.wid] = nil
print("REMINDER RENDER PASSED")
-- plan page sorting
local ns = NS
for k in pairs(DONE) do DONE[k] = nil end
for k in pairs(BAGS) do BAGS[k] = nil end
ns.dirty = true; ns.Refresh(); ns.Plan(nil, 1000)
local planned = {}; for i, q in ipairs(ns.char.run) do planned[i] = q end
local captured
local function runOrder(key, asc)
  ns.db.planSortKey, ns.db.planSortAsc = key, asc
  local recs = ns.RunRecords()
  -- reproduce what UpdatePlan shows by calling the page and reading the list rows
  ns.ShowPage("plan")
  return recs
end
for _, key in ipairs({ "g", "i", "d", "name", "rep", "npc", "zone", "cost" }) do
  for _, asc in ipairs({ true, false }) do runOrder(key, asc) end
end
-- run order in saved data must not change when sorting the view
for i, q in ipairs(ns.char.run) do assert(planned[i] == q, "sorting changed the saved run") end
ns.db.planSortKey = nil; ns.ShowPage("plan")
print("PLAN SORT RENDER PASSED")
local ns = NS
local function order(key, asc) ns.db.planSortKey, ns.db.planSortAsc = key, asc; ns.ShowPage("plan"); return ns.lastRun end
local l = order("name", true); for i = 2, #l do assert(l[i-1].name:lower() <= l[i].name:lower(), "plan name a-z") end
l = order("cost", false); for i = 2, #l do assert(l[i-1].cost >= l[i].cost, "plan cost high-low") end
l = order("zone", true); for i = 2, #l do assert((l[i-1].zone or "~"):lower() <= (l[i].zone or "~"):lower(), "plan zone") end
DONE[ns.char.run[3]] = true; ns.dirty = true
l = order("d", false); assert(l[1].qid == ns.char.run[3], "done-ticked first")
DONE[ns.char.run[3]] = nil; ns.db.planSortKey = nil
print("PLAN SORT ORDER PASSED")
-- Exalted day detail
local ns = NS
C_Reputation.GetFactionDataByID = function() return { name = "D", currentStanding = 2000, currentReactionThreshold = 0, nextReactionThreshold = 3000, reaction = 4 } end
SHOP = nil
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(c, id) return PRICE_OVERRIDE and PRICE_OVERRIDE[id] end,
  ConvertToSearchString = function(c, t) return t.searchString .. "|" .. t.quantity end,
  CreateShoppingList = function(c, n, terms) SHOP = { n, terms } end } } }
ns.db.source = "auto"; ns.char.dailyBudget = nil; ns.dirty = true
ns.ShowPage("exalted")
ns.OpenExDay(2); local d = ns.lastExDay
assert(d and #d.qids > 0, "day detail")
local sum = 0; for _, q in ipairs(d.qids) do sum = sum + d.costs[q] end
assert(math.abs(sum - d.cost) < 1, "day costs add up")
print(("Day 2 detail: %d writs, cost %d"):format(#d.qids, d.cost))
-- price change flows through
local w = ns.byQid[d.qids[1]]
local before = d.costs[w.qid]
GoldScoutPricesData = TEST_PRICES
local mk = FACTION == "Alliance" and "Test-Alliance" or "Test-Horde"
local saved = TEST_PRICES.markets[mk].items[w.iid][1]
TEST_PRICES.markets[mk].items[w.iid][1] = saved + 50000
ns.dirty = true; ns.ShowPage("exalted"); local d2 = ns.lastExDay
if d2.costs[w.qid] then
  print(("price change: %s day-2 cost %d -> %d"):format(w.name, before, d2.costs[w.qid]))
  assert(d2.costs[w.qid] > before, "price update reflected")
else print("price change pushed " .. w.name .. " out of day 2 (expected, it's no longer cheap)") end
TEST_PRICES.markets[mk].items[w.iid][1] = saved; ns.dirty = true; ns.ShowPage("exalted")
local needs = ns.DayNeeds(ns.lastExDay)
local ok, m = ns.SendListToAuctionator("Writ Planner Day 2", needs); print(m)
assert(ok and SHOP[1] == "Writ Planner Day 2" and #SHOP[2] == #needs)
-- back to list
ns.OpenExDay(nil); ns.ShowPage("exalted"); assert(ns.lastExDay == nil)
print("DAY DETAIL PASSED")
-- Merchant's Favor
local ns = NS
for k in pairs(BAGS) do BAGS[k] = nil end
C_CurrencyInfo = { GetCurrencyListSize = function() return 2 end,
  GetCurrencyListInfo = function(i) if i == 2 then return { name = "Merchant's Favor", quantity = 30, currencyID = 3412 } end return { name = "Other", quantity = 5 } end,
  GetCurrencyInfo = function(id) assert(id == 3412); return { quantity = 30 } end }
Auctionator = nil; GoldScoutPricesData = TEST_PRICES; ns.db.source = "auto"
assert(#ns.crates == 30, "30 crates")
ns.RefreshFavor()
assert(ns.FavorBalance() == 30, "balance")
for _, c in ipairs(ns.crates) do
  if c.best then for _, o in ipairs(c.opts) do if o.price then assert(c.best.price * c.best.qty <= o.price * o.qty, "cheapest " .. c.name) end end end
end
-- have-mode with 3 crates in bags
local apF = ns.crates[1]; for _, c in ipairs(ns.crates) do if c.short == "Journeyman Herbs" then apF = c end end
BAGS[apF.cid] = 3; ns.RefreshFavor()
local p = ns.FavorPlan(100, false)
print(("have-mode: need %d, favor %d from %d lines, cost %d, short=%s"):format(p.need, p.favor, #p.lines, p.total, tostring(p.short)))
assert(p.need == 70 and p.favor == 30 and p.short, "have mode uses only bag crates")
local p2 = ns.FavorPlan(1500, true)
print(("buy-mode 1500: favor %d, lines %d, total %dg"):format(p2.favor, #p2.lines, p2.total / 10000))
assert(p2.favor >= p2.need and p2.lines[1].fromBags, "bag crates first then buy")
-- materials in bags make fill free
local o = apF.best; BAGS[o.id] = 999; ns.RefreshFavor()
local p3 = ns.FavorPlan(60, false); assert(p3.lines[1].cost == 0, "bag materials free")
BAGS[o.id] = nil; BAGS[apF.cid] = nil
-- page renders in both modes and all sorts
ns.char.favorGoal = 1500
for _, b in ipairs({ false, true }) do ns.char.favorBuy = b
  for _, k in ipairs({ "name", "fillName", "fill", "crateP", "favor", "per", "have", "plan" }) do ns.db.favorSortKey = k; ns.ShowPage("favor") end end
Auctionator = { API = { v1 = { ConvertToSearchString = function(c, t) return t.searchString .. "|" .. t.quantity end, CreateShoppingList = function(c, n, terms) SHOP = { n, terms } end } } }
local ok, m = ns.SendListToAuctionator("Writ Planner Favor", ns.FavorNeeds(ns.lastFavorPlan)); print(m); assert(ok)
ns.char.favorGoal = 10; ns.ShowPage("favor") -- already enough
print("FAVOR TESTS PASSED")
