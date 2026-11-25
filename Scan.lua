-- Writ Planner: optional auction house price scan, for players without TSM / Auctionator / GoldScout.
-- Runs only when the player presses Scan with the auction house open. It is read-only: one browse
-- query lists every item with its lowest buyout and quantity, page by page, paced by the game's
-- request throttle. It never buys, bids or posts. Only the items Writ Planner uses are kept.

local ADDON, ns = ...

local floor, ipairs, pairs, pcall, time, type, tostring = math.floor, ipairs, pairs, pcall, time, type, tostring
local tinsert = table.insert

local Scan = { ahOpen = false }
ns.Scan = Scan

local PAGE_TIMEOUT = 20 -- seconds to wait for one page before saving what arrived
local MAX_LOG = 20

local function realmName()
  local r = GetRealmName and GetRealmName()
  if not r or r == "" then r = GetNormalizedRealmName and GetNormalizedRealmName() end
  if not r or r == "" then r = "Forever" end -- some clients report an empty realm name
  return r
end
local function realmKey()
  local key = realmName() .. "-" .. ns.PlayerFaction()
  -- scans saved before the realm-name fix used "-Faction"; carry them over once
  local scans = ns.db and ns.db.scans
  local old = "-" .. ns.PlayerFaction()
  if scans and scans[old] and not scans[key] then scans[key], scans[old] = scans[old], nil end
  return key
end

-- Items we keep from a scan: writs, hand-in items, crates and crate materials
local wanted
local function Wanted()
  if wanted then return wanted end
  wanted = {}
  for _, w in ipairs(ns.list) do wanted[w.iid] = true; wanted[w.wid] = true end
  for _, c in ipairs(ns.crates or {}) do
    wanted[c.cid] = true
    for _, o in ipairs(c.opts) do wanted[o.id] = true end
  end
  return wanted
end

local function Store()
  ns.db.scans = ns.db.scans or {}
  local k = realmKey()
  ns.db.scans[k] = ns.db.scans[k] or { items = {} }
  return ns.db.scans[k]
end

-- Price from the last scan on this realm and faction
function ns.FromScan(id)
  local s = ns.db and ns.db.scans and ns.db.scans[realmKey()]
  local e = s and s.items and s.items[id]
  if e and type(e[1]) == "number" and e[1] > 0 then return e[1], e[2] end
end

function ns.ScanInfo()
  local s = ns.db and ns.db.scans and ns.db.scans[realmKey()]
  if s and s.time then return s.time, s.count or 0 end
end

local function Log(msg)
  local s = Store()
  s.log = s.log or {}
  tinsert(s.log, 1, date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg))
  for i = #s.log, MAX_LOG + 1, -1 do s.log[i] = nil end
end
Scan.Log = Log

local function Supported()
  return C_AuctionHouse and C_AuctionHouse.SendBrowseQuery and C_AuctionHouse.GetBrowseResults
     and C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.RequestMoreBrowseResults
     and C_AuctionHouse.IsThrottledMessageSystemReady
end

-- Blizzard's Sell tab errors if a request goes out while it holds an item, so wait while it's shown
local function SellTabOpen()
  local ah = AuctionHouseFrame
  if not ah then return false end
  for _, key in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
    local f = ah[key]
    if type(f) == "table" and f.IsVisible and f:IsVisible() then return true end
  end
  return false
end

local queue = {}
local function Pump()
  if #queue == 0 then return end
  if not Scan.ahOpen then wipe(queue); return end
  if SellTabOpen() then
    if Scan.cur and not Scan.cur.paused then
      Scan.cur.paused = true
      ns.Print("Scan paused while the Sell tab is open. It carries on when you leave it.")
    end
    return
  end
  local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
  if ok and ready then
    local send = table.remove(queue, 1)
    local sent, err = pcall(send)
    if not sent then Log("send error: " .. tostring(err)); Scan:Finish(false, "request error") end
  end
end

local function Request(kind, send)
  local cur = Scan.cur
  tinsert(queue, function()
    if Scan.cur ~= cur then return end
    cur.waiting = kind
    send()
    local token = {}
    cur.token = token
    C_Timer.After(PAGE_TIMEOUT, function()
      if Scan.cur == cur and cur.token == token and cur.waiting then
        Log("timeout waiting for page " .. (cur.pages + 1))
        ns.Print("The auction house stopped responding. Saving what was received.")
        Scan:Finish(false, "timeout")
      end
    end)
  end)
  Pump()
end

function Scan:IsRunning() return self.cur ~= nil end

function Scan:Start()
  if self.cur then ns.Print("A scan is already running."); return false end
  if not self.ahOpen then ns.Print("Open the auction house first, then press Scan."); return false end
  if not Supported() then
    Log("unsupported: this client has no modern auction house browse API")
    ns.Print("Sorry: this auction house type isn't supported by the Writ Planner scan yet. Install Auctionator for prices.")
    return false
  end
  self.cur = { started = GetTime and GetTime() or time(), pages = 0, seen = 0, results = {} }
  self.cur.ticker = C_Timer.NewTicker(1, Pump)
  Log("scan started on " .. realmKey())
  ns.Print("Scanning auction house prices... (read-only; you can keep using the auction house, except the Sell tab)")
  Request("first", function()
    C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
  end)
  if ns.UpdateUI then ns.UpdateUI() end
  return true
end

local function AddResults(cur, results)
  for _, r in ipairs(results) do
    local key = r.itemKey
    local id = key and key.itemID
    if id and r.minPrice and r.totalQuantity and r.totalQuantity > 0 then
      local e = cur.results[id]
      if e then
        if r.minPrice < e[1] then e[1] = r.minPrice end
        e[2] = e[2] + r.totalQuantity
      else
        cur.results[id] = { r.minPrice, r.totalQuantity }
      end
    end
  end
end

local function OnBrowse()
  local cur = Scan.cur
  if not cur or not cur.waiting then return end
  local ok, all = pcall(C_AuctionHouse.GetBrowseResults)
  all = ok and all or {}
  if cur.waiting == "more" and #all <= cur.seen then return end -- results are cumulative
  cur.waiting = nil
  -- only the new tail of the cumulative list is added; repeated item keys merge by item id
  local fresh = {}
  for i = cur.seen + 1, #all do fresh[#fresh + 1] = all[i] end
  cur.seen = #all
  AddResults(cur, fresh)
  cur.pages = cur.pages + 1
  if Scan.status then Scan.status(cur.pages, cur.seen) end
  local okF, full = pcall(C_AuctionHouse.HasFullBrowseResults)
  if okF and full then
    Scan:Finish(true)
  else
    Request("more", function() C_AuctionHouse.RequestMoreBrowseResults() end)
  end
end

function Scan:Finish(complete, why)
  local cur = self.cur
  if not cur then return end
  self.cur = nil
  wipe(queue)
  if cur.ticker then cur.ticker:Cancel() end
  local want, store, kept, missing = Wanted(), Store(), 0, 0
  local items = {}
  for id, e in pairs(cur.results) do
    if want[id] then items[id] = e; kept = kept + 1 end
  end
  for id in pairs(want) do if not items[id] then missing = missing + 1 end end
  if kept > 0 then
    store.items = items
    store.time = time()
    store.count = kept
    store.complete = complete and true or false
  end
  local secs = floor(((GetTime and GetTime() or time()) - cur.started) + 0.5)
  store.last = { pages = cur.pages, listed = cur.seen, kept = kept, notListed = missing, seconds = secs,
                 complete = complete and true or false, why = why, api = "modern browse" }
  Log(("%s: %d pages, %d listings seen, %d of our items priced, %d not listed, %ds%s"):format(
    complete and "complete" or "stopped", cur.pages, cur.seen, kept, missing, secs, why and (" (" .. why .. ")") or ""))
  if kept > 0 then
    ns.Print(("Scan %s: %d of Writ Planner's items priced (%d not listed right now). Type /reload to save the results to disk."):format(
      complete and "complete" or "stopped early", kept, missing))
  else
    ns.Print("Scan stopped before any of Writ Planner's items came back. Try again in a moment.")
  end
  ns.dirty = true
  if ns.UpdateUI then ns.UpdateUI() end
end

---------------------------------------------------------------------------
-- Auction house open / close
---------------------------------------------------------------------------
local function Shown()
  if Scan.ahOpen then return end
  Scan.ahOpen = true
  if ns.OnAHShown then pcall(ns.OnAHShown) end
  if ns.UpdateUI then ns.UpdateUI() end
end

local function Closed()
  if not Scan.ahOpen then return end
  Scan.ahOpen = false
  if Scan.cur then Scan:Finish(false, "auction house closed") end
  wipe(queue)
  if ns.UpdateUI then ns.UpdateUI() end
end

local function isAuctioneer(kind)
  return Enum and Enum.PlayerInteractionType and kind == Enum.PlayerInteractionType.Auctioneer
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, e, a)
  if e == "AUCTION_HOUSE_SHOW" then Shown()
  elseif e == "AUCTION_HOUSE_CLOSED" then Closed()
  elseif e == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then if isAuctioneer(a) then Shown() end
  elseif e == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then if isAuctioneer(a) then Closed() end
  elseif e == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or e == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then OnBrowse()
  elseif e == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then Pump()
  elseif e == "AUCTION_HOUSE_BROWSE_FAILURE" then
    if Scan.cur and Scan.cur.waiting then
      Log("browse failure from the server")
      ns.Print("The auction house refused the request. Try again in a moment.")
      Scan:Finish(false, "refused")
    end
  end
end)
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
                     "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
                     "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
                     "AUCTION_HOUSE_BROWSE_FAILURE" }) do
  pcall(ev.RegisterEvent, ev, e) -- guarded: an event missing on this client must not throw
end
