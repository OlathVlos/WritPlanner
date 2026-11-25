-- Writ Planner: core logic (data, prices, bag/quest state, planner).
-- Information only: this addon never buys, sells, turns in, moves or clicks anything for you.

local ADDON, ns = ...

local floor, max, min, tonumber, tostring, type, pairs, ipairs, pcall, wipe =
      math.floor, math.max, math.min, tonumber, tostring, type, pairs, ipairs, pcall, wipe
local tinsert, sort = table.insert, table.sort

ns.CALLER = "WritPlanner"
ns.FACTION_IDS = { Alliance = 2586, Horde = 2587 } -- Azeroth Commerce Authority / Durotar Supply and Logistics

---------------------------------------------------------------------------
-- Data: unpack the compact rows from Data.lua into records
---------------------------------------------------------------------------
ns.list, ns.byQid = {}, {}
for _, r in ipairs(ns.WRITS or {}) do
  local w = {
    qid = r[1], wid = r[2], iid = r[3], qty = r[4], rep = r[5], tier = r[6],
    name = r[7], item = r[8], npc = r[9], zone = r[10], map = r[11],
    x = r[12], y = r[13], lo = r[14], hi = r[15], only = r[16],
    snap = { Horde = r[17], Alliance = r[18] }, cont = r[19],
  }
  tinsert(ns.list, w)
  ns.byQid[w.qid] = w
end
ns.WRITS = nil -- free the raw rows

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DEFAULTS = { source = "auto", minimap = { hide = false, angle = 200 }, showUnknown = false, scale = 1 }
local CHAR_DEFAULTS = { mode = "both", run = {}, excl = {}, ticks = {}, resetKey = nil }

local function applyDefaults(t, d)
  for k, v in pairs(d) do
    if t[k] == nil then
      if type(v) == "table" then t[k] = {}; applyDefaults(t[k], v) else t[k] = v end
    elseif type(v) == "table" and type(t[k]) == "table" then
      applyDefaults(t[k], v)
    end
  end
end

---------------------------------------------------------------------------
-- Game API wrappers (all guarded so a missing API never throws)
---------------------------------------------------------------------------
local function ItemCount(id)
  if not id then return 0 end
  if C_Item and C_Item.GetItemCount then
    local ok, n = pcall(C_Item.GetItemCount, id, false)
    if ok and n then return n end
  end
  if GetItemCount then
    local ok, n = pcall(GetItemCount, id, false)
    if ok and n then return n end
  end
  return 0
end
ns.ItemCount = ItemCount

local function QuestDone(qid)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
    if ok then return v and true or false end
  end
  if IsQuestFlaggedCompleted then
    local ok, v = pcall(IsQuestFlaggedCompleted, qid)
    if ok then return v and true or false end
  end
  return false
end
ns.QuestDone = QuestDone

function ns.PlayerFaction()
  local f = UnitFactionGroup("player")
  if f ~= "Alliance" then f = "Horde" end
  return f
end

function ns.PlayerLevel()
  local l = UnitLevel("player")
  return (type(l) == "number" and l > 0) and l or 1
end

-- Current standing with this faction's writ reputation. Returns name, value-in-standing, standing-size, standing-label.
function ns.GetRep()
  local id = ns.FACTION_IDS[ns.PlayerFaction()]
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
    if ok and type(d) == "table" and d.name then
      local cur = (d.currentStanding or 0) - (d.currentReactionThreshold or 0)
      local size = (d.nextReactionThreshold or 0) - (d.currentReactionThreshold or 0)
      return d.name, cur, size, d.reaction and _G["FACTION_STANDING_LABEL" .. d.reaction], d.reaction
    end
  end
  if GetFactionInfoByID then
    local ok, name, _, standing, bmin, bmax, val = pcall(GetFactionInfoByID, id)
    if ok and name then
      return name, (val or 0) - (bmin or 0), (bmax or 0) - (bmin or 0), standing and _G["FACTION_STANDING_LABEL" .. standing], standing
    end
  end
  return nil
end

-- A key that changes at each daily quest reset (manual ticks are cleared then).
local function ResetKey()
  if GetQuestResetTime then
    local ok, s = pcall(GetQuestResetTime)
    if ok and type(s) == "number" and s > 0 then
      return floor((time() + s) / 600) -- 10-minute bucket of the next reset moment
    end
  end
  return date("%Y-%m-%d")
end

---------------------------------------------------------------------------
-- Prices (copper). Auto order: GoldScout (hourly) -> Auctionator (your last scan) -> TSM -> bundled snapshot.
---------------------------------------------------------------------------
ns.SOURCES = { "auto", "auctionator", "tsm", "goldscout", "scan", "snapshot" }
ns.SOURCE_LABEL = { auto = "Auto (best available)", auctionator = "Auctionator", tsm = "TradeSkillMaster",
                    goldscout = "GoldScout", scan = "Writ Planner scan", snapshot = "Bundled snapshot" }

local function fromAuctionator(id)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if api and api.GetAuctionPriceByItemID then
    local ok, p = pcall(api.GetAuctionPriceByItemID, ns.CALLER, id)
    if ok and type(p) == "number" and p > 0 then return p end
  end
end

local function fromTSM(id)
  if TSM_API and TSM_API.GetCustomPriceValue then
    local ok, p = pcall(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. id)
    if ok and type(p) == "number" and p > 0 then return p end
  end
end

local gsMarket, gsMarketFaction, gsData
local function fromGoldScout(id)
  local d = GoldScoutPricesData
  if type(d) ~= "table" or type(d.markets) ~= "table" then return end
  local fac = ns.PlayerFaction()
  if gsMarketFaction ~= fac or gsData ~= d then
    gsMarket, gsMarketFaction, gsData = nil, fac, d
    local suffix = "-" .. fac
    for key, m in pairs(d.markets) do
      if type(key) == "string" and key:sub(-#suffix) == suffix and type(m) == "table" and type(m.items) == "table" then
        gsMarket = m.items
        break
      end
    end
  end
  local e = gsMarket and gsMarket[id]
  if type(e) == "table" and type(e[1]) == "number" and e[1] > 0 then return e[1] end
end

local function fromSnapshot(w, isWrit)
  local s = w.snap[ns.PlayerFaction()] or w.snap.Horde
  if not s then return end
  local p = isWrit and s[2] or s[1]
  if type(p) == "number" and p > 0 then return p end
end

local function fromScan(id) if ns.FromScan then return (ns.FromScan(id)) end end
local FETCH = { auctionator = fromAuctionator, tsm = fromTSM, goldscout = fromGoldScout, scan = fromScan }
-- freshest first; the built-in scan is last because the dedicated price addons track markets better
local AUTO = { "goldscout", "auctionator", "tsm", "scan" }

-- Returns price, sourceKey
function ns.Price(w, isWrit)
  local id = isWrit and w.wid or w.iid
  local src = ns.db and ns.db.source or "auto"
  if src == "snapshot" then return fromSnapshot(w, isWrit), "snapshot" end
  if FETCH[src] then
    local p = FETCH[src](id)
    if p then return p, src end
  end
  for _, k in ipairs(AUTO) do -- auto, or the chosen source had no price
    local p = FETCH[k](id)
    if p then return p, k end
  end
  return fromSnapshot(w, isWrit), "snapshot"
end

function ns.SourcesAvailable()
  local t = {}
  if Auctionator and Auctionator.API and Auctionator.API.v1 then tinsert(t, "Auctionator") end
  if TSM_API and TSM_API.GetCustomPriceValue then tinsert(t, "TSM") end
  if type(GoldScoutPricesData) == "table" then tinsert(t, "GoldScout") end
  if ns.ScanInfo and ns.ScanInfo() then tinsert(t, "Writ Planner scan") end
  return t
end

---------------------------------------------------------------------------
-- State refresh: bag counts, done-today, prices, costs. Cheap (150 rows).
---------------------------------------------------------------------------
-- mode: "both" = buy writ + item, "item" = buy item only, "writ" = buy writ only
-- True when any price is available: a price addon, or a bundled snapshot (private builds only)
function ns.HasPrices()
  if ns.SNAPSHOT then return true end
  return #ns.SourcesAvailable() > 0
end

function ns.Refresh()
  ns.repOnly = not ns.HasPrices() -- no prices anywhere: plan by rep only
  local mode = ns.char and ns.char.mode or "both"
  local fac = ns.PlayerFaction()
  for _, w in ipairs(ns.list) do
    w.haveWrit = ItemCount(w.wid)
    w.haveItem = ItemCount(w.iid)
    w.done = QuestDone(w.qid)
    w.pItem, w.sItem = ns.Price(w, false)
    w.pWrit, w.sWrit = ns.Price(w, true)
    w.factionOk = (w.only == nil or w.only == fac)
    local qty = w.qty or 1
    local cost, ok = 0, true
    if mode ~= "writ" then
      local need = max(0, qty - w.haveItem)
      if need > 0 then
        if w.pItem then cost = cost + w.pItem * need else ok = false end
      end
    end
    if mode ~= "item" then
      if w.haveWrit < 1 then
        if w.pWrit then cost = cost + w.pWrit else ok = false end
      end
    end
    w.cost = ok and cost or nil
    w.per100 = (ok and w.rep and w.rep > 0) and floor(cost * 100 / w.rep) or nil
  end
end

---------------------------------------------------------------------------
-- Level colour (same rules as the website)
---------------------------------------------------------------------------
-- returns key: rd/or/ye/gr/gy, label
function ns.Danger(w, L)
  if not w.lo then return nil end
  local m = (w.lo + w.hi) / 2
  if w.lo - L >= 5 then return "rd", "Deadly"
  elseif m - L >= 3 then return "or", "Risky"
  elseif m - L >= -2 then return "ye", "Even"
  elseif w.hi >= L - 8 then return "gr", "Easy"
  else return "gy", "Trivial" end
end

---------------------------------------------------------------------------
-- Planner (greedy: cheapest gold per rep first, within budget, until target)
---------------------------------------------------------------------------
function ns.Plan(budgetCopper, target)
  local c = ns.char
  local L = c.levelOverride or ns.PlayerLevel()
  local showUnknown = ns.db.showUnknown
  local cands = {}
  for _, w in ipairs(ns.list) do
    local levelOk = (not w.lo) or ((w.lo + w.hi) / 2 <= L + 5)
    if (w.cost or ns.repOnly) and not w.done and not c.excl[w.qid] and w.factionOk and levelOk
       and (w.npc or showUnknown) then
      tinsert(cands, w)
    end
  end
  if ns.repOnly then
    budgetCopper = nil -- no prices: budget can't apply; fewest turn-ins (highest rep) first
    sort(cands, function(a, b)
      if a.rep == b.rep then return a.qid < b.qid end
      return a.rep > b.rep
    end)
  else
    sort(cands, function(a, b)
      local ra, rb = a.cost / a.rep, b.cost / b.rep
      if ra == rb then return a.qid < b.qid end
      return ra < rb
    end)
  end
  wipe(c.run)
  local spent, rep = 0, 0
  target = target or 1000
  for _, w in ipairs(cands) do
    if rep >= target then break end
    if (not budgetCopper) or spent + w.cost <= budgetCopper then
      tinsert(c.run, w.qid)
      spent, rep = spent + (w.cost or 0), rep + w.rep
    end
  end
  return #c.run, spent, rep
end

function ns.RunRecords()
  local t = {}
  for _, q in ipairs(ns.char.run) do
    local w = ns.byQid[q]
    if w then tinsert(t, w) end
  end
  return t
end

function ns.InRun(qid)
  for _, q in ipairs(ns.char.run) do if q == qid then return true end end
  return false
end

function ns.ToggleRun(qid)
  local run = ns.char.run
  for i, q in ipairs(run) do
    if q == qid then table.remove(run, i); return false end
  end
  tinsert(run, qid)
  return true
end

-- Ticks: g = have writ, i = have items, d = turned in. Auto from game state, manual as override.
function ns.Ticks(w)
  local m = ns.char.ticks[w.qid] or {}
  local autoG = w.haveWrit >= 1
  local autoI = w.haveItem >= (w.qty or 1)
  local autoD = w.done
  return (autoG or m.g or autoD) and true or false,
         (autoI or m.i or autoD) and true or false,
         (autoD or m.d) and true or false,
         autoG or autoD, autoI or autoD, autoD
end

function ns.SetTick(qid, field, value)
  local t = ns.char.ticks
  t[qid] = t[qid] or {}
  t[qid][field] = value or nil
  if not next(t[qid]) then t[qid] = nil end
end

function ns.ClearRun()
  wipe(ns.char.run)
  wipe(ns.char.ticks)
  wipe(ns.char.excl)
end

-- "Plan another run today": exclude what you just did, then re-plan.
function ns.NextRun()
  for _, q in ipairs(ns.char.run) do ns.char.excl[q] = true; ns.char.ticks[q] = nil end
  wipe(ns.char.run)
end

---------------------------------------------------------------------------
-- Merchant's Favor: Waylaid Crates (no daily limit). Cheapest fill option per crate.
---------------------------------------------------------------------------
ns.crates = {}
for _, r in ipairs(ns.CRATES or {}) do
  local c = { cid = r[1], tier = r[2], cat = r[3], lvl = r[4], favor = r[5], favorEst = r[6], name = r[7],
              snap = { Horde = r[8], Alliance = r[9] }, opts = {} }
  c.short = c.name:gsub("^Waylaid Crate: ", "")
  for _, o in ipairs(r[10]) do
    tinsert(c.opts, { id = o[1], qty = o[2], name = o[3], snap = { Horde = o[4], Alliance = o[5] } })
  end
  tinsert(ns.crates, c)
end
ns.CRATES = nil

-- Live price for any item id; snap = {Horde=, Alliance=} fallback
function ns.ItemPrice(id, snap)
  local src = ns.db and ns.db.source or "auto"
  local function fallback()
    local p = snap and (snap[ns.PlayerFaction()] or snap.Horde)
    if type(p) == "number" and p > 0 then return p, "snapshot" end
  end
  if src == "snapshot" then return fallback() end
  if FETCH[src] then
    local p = FETCH[src](id)
    if p then return p, src end
  end
  for _, k in ipairs(AUTO) do
    local p = FETCH[k](id)
    if p then return p, k end
  end
  return fallback()
end

-- Listed quantity, from GoldScout when available (nil = unknown)
function ns.ListedQty(id)
  fromGoldScout(id) -- makes sure the market table is picked
  local e = gsMarket and gsMarket[id]
  if type(e) == "table" and type(e[2]) == "number" then return e[2] end
  if ns.FromScan then local _, q = ns.FromScan(id); return q end
end

local function bestFill(c, stock)
  local best, bestOpt
  for _, o in ipairs(c.opts) do
    if o.price then
      local need = max(0, o.qty - (stock[o.id] or 0))
      local cost = need * o.price
      if not best or cost < best then best, bestOpt = cost, o end
    end
  end
  return best, bestOpt
end
ns.BestFill = bestFill

function ns.RefreshFavor()
  local L = ns.PlayerLevel()
  local stock = {}
  for _, c in ipairs(ns.crates) do
    c.have = ItemCount(c.cid)
    c.crateP, c.crateSrc = ns.ItemPrice(c.cid, c.snap)
    c.listed = ns.ListedQty(c.cid)
    c.levelOk = L >= (c.lvl or 1)
    for _, o in ipairs(c.opts) do
      o.price, o.src = ns.ItemPrice(o.id, o.snap)
      o.have = ItemCount(o.id)
      stock[o.id] = o.have
    end
  end
  local none = {}
  for _, c in ipairs(ns.crates) do
    c.fill, c.best = bestFill(c, none)          -- cheapest fill at full price
    c.fillNow = bestFill(c, stock)              -- counting materials already in bags
    c.perFill = c.fill and floor(c.fill / c.favor) or nil
    c.perBuy = (c.fill and c.crateP) and floor((c.fill + c.crateP) / c.favor) or nil
  end
end

-- Merchant's Favor balance from the currency tab (found by name; nil if unavailable)
local favorCurrencyID
function ns.FavorBalance()
  if not C_CurrencyInfo then return nil end
  if favorCurrencyID and C_CurrencyInfo.GetCurrencyInfo then
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, favorCurrencyID)
    if ok and type(info) == "table" then return info.quantity end
  end
  if C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo then
    local okN, n = pcall(C_CurrencyInfo.GetCurrencyListSize)
    for i = 1, (okN and n or 0) do
      local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
      if ok and type(info) == "table" and info.name == "Merchant's Favor" then
        if info.currencyID then favorCurrencyID = info.currencyID end
        return info.quantity
      end
    end
  end
  return nil
end

-- Plan crates to reach goal. buy = also buy empty crates on the AH.
-- Returns { need, lines = { {c=, n=, fromBags=, cost=, favor=} }, total, favor, short }
function ns.FavorPlan(goal, buy)
  local bal = ns.FavorBalance() or 0
  local res = { balance = bal, goal = goal, need = max(0, (goal or 0) - bal), lines = {}, total = 0, favor = 0, buy = {} }
  if res.need <= 0 then return res end
  local stock = {}
  for _, c in ipairs(ns.crates) do for _, o in ipairs(c.opts) do stock[o.id] = o.have or 0 end end
  local function addFill(c, fromBags, line)
    local cost, o = bestFill(c, stock)
    if not cost then return false end
    local need = max(0, o.qty - (stock[o.id] or 0))
    stock[o.id] = max(0, (stock[o.id] or 0) - o.qty)
    if need > 0 then res.buy[o.id] = { name = o.name, qty = ((res.buy[o.id] or {}).qty or 0) + need, price = o.price } end
    local total = cost + ((not fromBags) and c.crateP or 0)
    if not fromBags then res.buy[c.cid] = { name = c.name, qty = ((res.buy[c.cid] or {}).qty or 0) + 1, price = c.crateP, crate = true } end
    line.n = line.n + 1; line.cost = line.cost + total; line.favor = line.favor + c.favor
    res.total = res.total + total; res.favor = res.favor + c.favor
    return true
  end
  -- 1) crates already in bags, cheapest fill per Favor first
  local owned = {}
  for _, c in ipairs(ns.crates) do if c.have > 0 and c.levelOk and c.perFill then tinsert(owned, c) end end
  sort(owned, function(a, b) return a.perFill < b.perFill end)
  for _, c in ipairs(owned) do
    local line = { c = c, n = 0, cost = 0, favor = 0, fromBags = true }
    for _ = 1, c.have do
      if res.favor >= res.need then break end
      addFill(c, true, line)
    end
    if line.n > 0 then tinsert(res.lines, line) end
  end
  -- 2) buy crates on the AH, cheapest (crate + fill) per Favor first
  if buy and res.favor < res.need then
    local cands = {}
    for _, c in ipairs(ns.crates) do if c.levelOk and c.perBuy then tinsert(cands, c) end end
    sort(cands, function(a, b) return a.perBuy < b.perBuy end)
    for _, c in ipairs(cands) do
      if res.favor >= res.need then break end
      local line = { c = c, n = 0, cost = 0, favor = 0, fromBags = false }
      local cap = c.listed or 999
      while res.favor < res.need and line.n < cap do
        if not addFill(c, false, line) then break end
      end
      if line.n > 0 then tinsert(res.lines, line) end
    end
  end
  res.short = res.favor < res.need
  return res
end

function ns.FavorNeeds(plan)
  local out = {}
  for id, b in pairs(plan.buy) do tinsert(out, { name = b.name, id = id, qty = b.qty, price = b.price, crate = b.crate }) end
  sort(out, function(a, b) return a.name < b.name end)
  return out
end

---------------------------------------------------------------------------
-- Road to Exalted: spread the cheapest writs over days (each writ once per day)
---------------------------------------------------------------------------
local STANDING_SIZE = { [4] = 3000, [5] = 6000, [6] = 12000, [7] = 21000 } -- Neutral, Friendly, Honored, Revered
local STANDING_NAME = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
function ns.StandingName(i) return _G["FACTION_STANDING_LABEL" .. i] or STANDING_NAME[i] or "?" end

-- Returns reaction index, rep into it, rep left to Exalted
function ns.RepToExalted()
  local _, cur, size, _, reaction = ns.GetRep()
  if not reaction or not cur then return 4, 0, 42000, true end -- unknown: assume start of Neutral
  if reaction >= 8 then return 8, cur, 0 end
  local left = math.max(0, (STANDING_SIZE[reaction] or size or 0) - cur)
  for r = reaction + 1, 7 do left = left + STANDING_SIZE[r] end
  return reaction, cur, left
end

-- Cost of one hand-in on a given day, using spare writs/items still in your bags first.
local function dayCost(e, mode)
  if ns.repOnly then return 0 end
  local w, c = e.w, 0
  if mode ~= "writ" then
    local need = math.max(0, (w.qty or 1) - e.items)
    if need > 0 then
      if not w.pItem then return nil end
      c = c + w.pItem * need
    end
  end
  if mode ~= "item" and e.writs < 1 then
    if not w.pWrit then return nil end
    c = c + w.pWrit
  end
  return c
end

function ns.ExaltedPlan(dailyBudget)
  local mode = ns.char.mode
  local L = ns.char.levelOverride or ns.PlayerLevel()
  local reaction, cur, left, guessed = ns.RepToExalted()
  local pool = {}
  for _, w in ipairs(ns.list) do
    local levelOk = (not w.lo) or ((w.lo + w.hi) / 2 <= L + 5)
    if w.factionOk and levelOk and (w.npc or ns.db.showUnknown) then
      -- spare copies in bags carry over: one named writ per day, duplicates wait for later days
      tinsert(pool, { w = w, writs = w.haveWrit or 0, items = w.haveItem or 0 })
    end
  end
  local res = { start = left, reaction = reaction, cur = cur, guessed = guessed, days = {}, total = 0 }
  if left <= 0 then return res end
  local gained, day = 0, 0
  local thresholds, acc = {}, 0 -- rep gained at which each new standing is reached
  local firstLeft = math.max(0, (STANDING_SIZE[reaction] or 0) - cur)
  acc = firstLeft
  for r = reaction + 1, 8 do thresholds[#thresholds + 1] = { r = r, at = acc }; acc = acc + (STANDING_SIZE[r] or 0) end
  while gained < left and day < 365 do
    day = day + 1
    local cands = {}
    for _, e in ipairs(pool) do
      local c = dayCost(e, mode)
      if c and not (day == 1 and e.w.done) then tinsert(cands, { e = e, w = e.w, c = c }) end
    end
    sort(cands, function(a, b)
      local ra, rb = a.c / a.w.rep, b.c / b.w.rep
      if ns.repOnly or ra == rb then
        if a.w.rep ~= b.w.rep then return a.w.rep > b.w.rep end
        return a.w.qid < b.w.qid
      end
      return ra < rb
    end)
    local d = { qids = {}, rep = 0, cost = 0, costs = {}, buy = {} }
    for _, e in ipairs(cands) do
      if gained + d.rep >= left then break end
      if (not dailyBudget) or d.cost + e.c <= dailyBudget then
        tinsert(d.qids, e.w.qid); d.rep = d.rep + e.w.rep; d.cost = d.cost + e.c; d.costs[e.w.qid] = e.c
        d.buy[e.w.qid] = {
          i = (mode ~= "writ") and math.max(0, (e.w.qty or 1) - e.e.items) or 0,
          w = (mode ~= "item") and e.e.writs < 1,
        }
        -- use up bag stock for this hand-in
        if mode ~= "item" and e.e.writs > 0 then e.e.writs = e.e.writs - 1 end
        if mode ~= "writ" then e.e.items = math.max(0, e.e.items - (e.w.qty or 1)) end
      end
    end
    if d.rep == 0 then break end -- nothing affordable: stop
    gained = gained + d.rep
    d.cum = gained
    for _, t in ipairs(thresholds) do
      if gained >= t.at and (gained - d.rep) < t.at then
        d.reached = t.r
        d.reachedAll = d.reachedAll or {}
        tinsert(d.reachedAll, t.r)
      end
    end
    res.total = res.total + d.cost
    tinsert(res.days, d)
  end
  res.gained = gained
  res.complete = gained >= left
  return res
end

---------------------------------------------------------------------------
-- Integrations: Auctionator shopping list, TomTom / Blizzard waypoints
---------------------------------------------------------------------------
function ns.ShoppingNeeds()
  local mode = ns.char.mode
  local out = {}
  for _, w in ipairs(ns.RunRecords()) do
    local _, _, d = ns.Ticks(w)
    if not d then
      if mode ~= "writ" then
        local need = max(0, (w.qty or 1) - w.haveItem)
        if need > 0 then tinsert(out, { name = w.item, id = w.iid, qty = need, price = w.pItem, w = w }) end
      end
      if mode ~= "item" and w.haveWrit < 1 then
        tinsert(out, { name = w.name, id = w.wid, qty = 1, price = w.pWrit, w = w, isWrit = true })
      end
    end
  end
  return out
end

-- Writ items are named after the item, so search the writ by its full item name when cached.
local function searchName(e)
  if e.isWrit then
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(e.id)
    if not n and GetItemInfo then n = GetItemInfo(e.id) end
    return n or e.name
  end
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(e.id)
  return n or e.name
end

-- entries: { {name=, id=, qty=, isWrit=} }
function ns.SendListToAuctionator(listName, needs)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
    return false, "Auctionator is not installed or is too old."
  end
  if #needs == 0 then return false, "Nothing to buy." end
  local terms = {}
  for _, e in ipairs(needs) do
    local ok, s = pcall(api.ConvertToSearchString, ns.CALLER,
                        { searchString = searchName(e), isExact = true, quantity = e.qty })
    if ok and type(s) == "string" then tinsert(terms, s) end
  end
  local ok, err = pcall(api.CreateShoppingList, ns.CALLER, listName, terms)
  if not ok then return false, "Auctionator refused the list: " .. tostring(err) end
  return true, ("Shopping list \"%s\" created in Auctionator (%d items). Open it at the auction house."):format(listName, #terms)
end

-- What to buy for one Road to Exalted day (bag stock already used up by the plan)
function ns.DayNeeds(d)
  local out = {}
  for _, q in ipairs(d.qids) do
    local w, b = ns.byQid[q], d.buy[q]
    if w and b then
      if b.i > 0 then tinsert(out, { name = w.item, id = w.iid, qty = b.i, price = w.pItem, w = w }) end
      if b.w then tinsert(out, { name = w.name, id = w.wid, qty = 1, price = w.pWrit, w = w, isWrit = true }) end
    end
  end
  return out
end

function ns.SendToAuctionator()
  local needs = ns.ShoppingNeeds()
  if #needs == 0 then return false, "Nothing left to buy for this run." end
  return ns.SendListToAuctionator("Writ Planner", needs)
end

local function tomtomReady()
  return TomTom and TomTom.AddWaypoint and TomTom.IsCrazyArrowEmpty
end

function ns.Waypoint(w, silent)
  if not (w.map and w.x and w.y) then return false end
  local title = ("%s: %s"):format(w.name, w.npc or "turn-in")
  if tomtomReady() then
    local ok = pcall(TomTom.AddWaypoint, TomTom, w.map, w.x / 100, w.y / 100,
                     { title = title, from = "Writ Planner", persistent = false, silent = silent })
    return ok
  end
  -- Blizzard's built-in map pin (only one at a time)
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(function()
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(w.map, w.x / 100, w.y / 100))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
      end
    end)
    return ok
  end
  return false
end

function ns.WaypointRun()
  local n = 0
  if not tomtomReady() then
    -- Without TomTom only one pin is possible: point at the first unfinished turn-in.
    for _, w in ipairs(ns.RunRecords()) do
      local _, _, d = ns.Ticks(w)
      if not d and ns.Waypoint(w) then return 1, false end
    end
    return 0, false
  end
  for _, w in ipairs(ns.RunRecords()) do
    local _, _, d = ns.Ticks(w)
    if not d and ns.Waypoint(w, true) then n = n + 1 end
  end
  return n, true
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
function ns.Money(c)
  if not c then return "|cff8a8178–|r" end
  c = floor(c + 0.5)
  local g, s, cp = floor(c / 10000), floor(c / 100) % 100, c % 100
  if g > 0 then
    return ("|cfff2c58c%s|rg |cffc7c7cf%d|rs"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g, s)
  elseif s > 0 then
    return ("|cffc7c7cf%d|rs |cffeda55f%d|rc"):format(s, cp)
  end
  return ("|cffeda55f%d|rc"):format(cp)
end

function ns.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffe9bd78Writ Planner:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Events (debounced; only rebuilds the UI when the window is open)
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local pending = false
ns.dirty = true

local function flush()
  pending = false
  ns.dirty = true
  if ns.UI and ns.UI:IsShown() then ns.UpdateUI() end
end

function ns.QueueUpdate()
  if pending then return end
  pending = true
  C_Timer.After(0.25, flush)
end

local function checkReset()
  local key = ResetKey()
  if ns.char.resetKey ~= key then
    if ns.char.resetKey ~= nil then
      wipe(ns.char.ticks)
      wipe(ns.char.excl)
    end
    ns.char.resetKey = key
  end
end
ns.CheckReset = checkReset

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    WritPlannerDB = type(WritPlannerDB) == "table" and WritPlannerDB or {}
    WritPlannerCharDB = type(WritPlannerCharDB) == "table" and WritPlannerCharDB or {}
    applyDefaults(WritPlannerDB, DEFAULTS)
    applyDefaults(WritPlannerCharDB, CHAR_DEFAULTS)
    ns.db, ns.char = WritPlannerDB, WritPlannerCharDB
    -- drop run entries that no longer exist in the data
    for i = #ns.char.run, 1, -1 do
      if not ns.byQid[ns.char.run[i]] then table.remove(ns.char.run, i) end
    end
    ev:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LOGIN" then
    checkReset()
    if ns.CreateMinimapButton then ns.CreateMinimapButton() end
  else
    if ns.char then
      if event == "QUEST_TURNED_IN" or event == "QUEST_LOG_UPDATE" then checkReset() end
      ns.QueueUpdate()
    end
  end
end)

ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "UPDATE_FACTION", "CURRENCY_DISPLAY_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e) -- guarded: an unknown event on this client must not throw
end
