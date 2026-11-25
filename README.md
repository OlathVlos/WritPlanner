# Writ Planner

An in-game planner for **Craftsman's Writs** on **WoW Forever**. It works out the cheapest way to hit your reputation target for your budget and level. Then it keeps a checklist that ticks itself off as you buy and turn things in.

It's the in-game companion to the Writ Run Planner web page.

## Requirements
- **WoW Forever** (Interface 16001).
- **At least one price addon, for live prices.** Any one is enough; with more than one installed, Writ Planner picks the freshest.
  - **GoldScout** (CurseForge project 1790110) with the GoldScout Companion app (prices refreshed about hourly from Blizzard's auction data)
  - [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (uses your own auction house scans: scan regularly)
  - [TradeSkillMaster](https://www.tradeskillmaster.com/) with the TSM desktop app (market values)

  **No price addon?** Open the auction house and press **Scan AH prices** (top of the Writ Planner window, or right-click the **Writ Planner** button at the end of the auction house tabs). It reads the lowest buyout and quantity for the ~280 items Writ Planner uses. It's read-only: it never buys, bids or posts. *Running TSM, Auctionator or GoldScout as well may give better results: they scan more often and track market values over time, while this scan is a snapshot of the cheapest listings right now.*

  With no price addon and no scan, Writ Planner still works in **rep-only mode**: plans reach your rep target in the fewest turn-ins, and the checklist, waypoints, Road to Exalted and Find writs all work, but costs show as "–" and Merchant's Favor can't rank crates. No prices are bundled with the addon.
- **Optional:** [TomTom](https://www.curseforge.com/wow/addons/tomtom) for waypoint arrows to every turn-in. Without it you get a Blizzard map pin to one turn-in at a time.
- **Optional:** Auctionator is also needed for the **Send to Auctionator** shopping lists.

## Features
- **Plan your run.** Enter a budget, pick a rep target from the dropdown (next standing, 250–5000, or no target to spend the budget), optionally set a level,, and choose what you're buying: writ + item, item only, or writ only. It picks the cheapest gold-per-rep writs that fit. Writs and items already in your bags count as free.
- **Auto-ticking checklist.** *Have writ*, *Have items* and *Turned in* tick themselves from your bags and quest log. You can also tick them yourself. Ticks clear at the daily reset.
- **Run complete.** Clear the run, or plan another run today without the writs you've just done.
- **Road to Exalted.** Starts from your live rep and plans every day to Exalted with current prices. Each writ can only be turned in once a day, so it fills each day with the cheapest writs (within an optional daily budget) and shows the rep, cost and standing reached each day. Load today's writs into Plan your run with one click.
- **Merchant's Favor.** Ranks all 30 Waylaid Crates by gold per Favor using each crate's cheapest fill at live prices, counting materials already in your bags. It reads your Favor balance, plans enough crates to reach a goal (recipes, titles, Packmule Treat, Pack Kodo), uses crates in your bags first, and can add empty crates bought on the AH. Sends the materials list to Auctionator. Crates have no daily limit.
- **Find writs.** The same filters as the website: Writ, Item, Turn-in NPC, Tier, Rep, Continent and Zone. Typing in a box starts a new search; there's also Clear filters, and Reset all, which also clears the planner inputs. Zone levels are colour-coded against your level (Deadly / Risky / Even / Easy / Trivial), and you click a writ to add it to or remove it from your run.
- **Shopping list.** What's left to buy, with one click to make an Auctionator shopping list for the auction house.
- **Waypoints.** Adds TomTom waypoints for every turn-in, or a Blizzard map pin if TomTom isn't installed.
- **Auction house scan.** Optional built-in price scan for players without a price addon, plus a **Writ Planner** button at the end of the auction house tab row.
- **Standalone window.** Open it anywhere. It doesn't close your character, bags or other windows. Use the minimap button, the Addon Compartment or `/writplan`.

## Install
1. Download or clone this repository.
2. Put the folder in `World of Warcraft\_forever_\Interface\AddOns\` and name it `WritPlanner`. `WritPlanner.toc` must sit directly inside that folder.
3. Restart the game, or `/reload`.

See [Requirements](#requirements) for the price addons it uses.

## Commands
| Command | What it does |
|---|---|
| `/writplan` | Open or close the window |
| `/writplan reset` | Reset window position and scale |
| `/writplan minimap` | Show or hide the minimap button |

## Prices
Auto mode uses the freshest data available:
1. **GoldScout**, from the Blizzard Game Data API, roughly hourly.
2. **Auctionator**, from your last scan.
3. **TradeSkillMaster** market value.
4. **Writ Planner's own scan** (lowest current buyouts from your last scan on this realm and faction).
You can pick one source in Settings; if it has no price for an item, the others are used.

## Blizzard policy and safety
Writ Planner follows Blizzard's UI Add-On Development Policy:
- **Information only.** It never buys, sells, posts, turns in quests, moves your character or clicks anything for you. You do all of that yourself.
- The optional price scan only runs when you press Scan with the auction house open, waits for the game's request throttle between pages, and only reads listings.
- It uses no protected or secure functions, and has no `loadstring`/`RunScript` or other dynamic code.
- It's free and open source (GPL-3.0), with no obfuscation, ads or donation prompts in game.
- It reads other addons only through their public APIs (`Auctionator.API.v1`, `TSM_API`, `TomTom:AddWaypoint`) and GoldScout's published price table.
- It only creates globals for its saved variables, its window, its minimap button and its slash command, all prefixed `WritPlanner`.
- It's lightweight. Bag and quest events are debounced, and the window only redraws while it's open.

## Updating the data
`Data.lua` is generated, so don't edit it by hand. To regenerate it from the web planner's `data.json` (no prices bundled; add `--with-prices` only for a private copy you don't publish):

```
python3 tools/gen_data.py path/to/data.json Data.lua
```

## Developer checks
- `node tools/lint.js *.lua` checks syntax (Lua 5.1) and lists any globals. Needs `npm i -g luaparse`.
- `tools/test_harness.lua` (full feature tests, using made-up test prices) and `tools/test_public.lua` (no price addon, the auction house scan and the auction house button) run the addon against a mocked WoW API in Lua 5.1. Set `DIR` to the addon folder first, e.g. with Python's `lupa`.

## Credits
- Turn-in NPCs and locations: **Questie** / QuestieDB (GPL-3.0). See [NOTICE.md](NOTICE.md).
- Prices: **GoldScout** (Blizzard Game Data API), **Auctionator**, **TradeSkillMaster**, **Gold Capped**.
- Waypoints: **TomTom**.

Not affiliated with or endorsed by Blizzard Entertainment.

## License
GPL-3.0-or-later. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
