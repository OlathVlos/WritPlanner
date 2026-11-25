# Notices

Writ Planner
Copyright (C) 2026 Bill

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY; see
[LICENSE](LICENSE) for details.

## Third-party data

### Questie / QuestieDB (GPL-3.0)
The Craftsman's Writ turn-in NPCs, NPC names, zones, coordinates and zone level ranges in
`Data.lua`, and the Waylaid Crate and material item IDs, are derived from the Questie database
(QuestieDB) for WoW Forever.
Copyright remains with the Questie project and its contributors: https://github.com/Questie/Questie

**Changes made:** the data was extracted and converted into this addon's own compact table format,
reduced to the fields Writ Planner needs, and matched to map IDs for waypoints. It is redistributed
under the same GPL-3.0 licence.

### Game data
World of Warcraft item, NPC, zone and faction names are the property of Blizzard Entertainment.
Writ Planner is not affiliated with or endorsed by Blizzard Entertainment.

## Not included
No prices from TradeSkillMaster, GoldScout, Gold Capped or Auctionator are bundled. At run time
the addon reads prices from whichever of those addons the player has installed, through their
public interfaces.
