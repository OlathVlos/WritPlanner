import json,sys
# Usage: gen_data.py data.json Data.lua [--with-prices]
# Without --with-prices (the public/GitHub build) no price snapshot is bundled: prices come from the
# player's own Auctionator / TSM / GoldScout. --with-prices adds a fallback snapshot for a private install.
WITH_PRICES='--with-prices' in sys.argv
d=json.load(open(sys.argv[1]));W=d['writs']
Z={'Badlands':1418,'Blasted Lands':1419,'Swamp of Sorrows':1435,'Duskwood':1431,'Wetlands':1437,'Dustwallow Marsh':1445,'Azshara':1447,'Western Plaguelands':1422,'Stranglethorn Vale':1434,'Alterac Mountains':1416,'Deadwind Pass':1430,'Arathi Highlands':1417,'Burning Steppes':1428,'The Hinterlands':1425,'Searing Gorge':1427,'Eastern Plaguelands':1423,'Hillsbrad Foothills':1424,'Ashenvale':1440,'Feralas':1444,'Felwood':1448,'Thousand Needles':1441,'Desolace':1443,'Stonetalon Mountains':1442,'Tanaris':1446,"Un'Goro Crater":1449,'Moonglade':1450,'Winterspring':1452,'Silithus':1451,'Riverglades':2548}
CONT={'EK':'Eastern Kingdoms','K':'Kalimdor','?':'New Forever zones'}
ONLY={'Lifelike Mechanical Toad':'Horde','Field Repair Bot 74A':'Horde','Ghostweave Vest':'Horde','Felcloth Boots':'Alliance'}
def s(v):
  if v is None: return 'nil'
  return '"'+str(v).replace('\\','\\\\').replace('"','\\"')+'"'
def n(v):
  if v is None: return 'nil'
  if isinstance(v,bool): return 'true' if v else 'false'
  return repr(round(v,2)) if isinstance(v,float) else str(int(v))
def pr(p):
  if not p or not WITH_PRICES: return 'nil'
  return '{%s,%s,%s}'%(n(p.get('ia')),n(p.get('wa')),'true' if p.get('fx') else 'false')
out=['-- WritPlanner data: generated from the Writ Run Planner dataset. Do not edit by hand.',
'-- Turn-in NPCs and coordinates derived from QuestieDB (GPL-3.0, see NOTICE.md). '+('Includes a private fallback price snapshot ('+str(d.get('scanned'))+').' if WITH_PRICES else 'No prices bundled: live prices come from Auctionator / TSM / GoldScout.'),
'local _, ns = ...','ns.SNAPSHOT = '+(s(d.get('scanned')) if WITH_PRICES else 'nil'),'ns.WRITS = {',
'-- {qid, writItemID, itemID, qty, rep, tier, writName, itemName, npc, zone, uiMapID, x, y, lo, hi, onlyFaction, hordePrice{item,writ,est}, alliancePrice, continent}']
for w in sorted(W,key=lambda w:w['qid']):
  out.append('{%s},'%','.join([n(w['qid']),n(w['wid']),n(w['iid']),n(w.get('q')),n(w['r']),s(w['t']),s(w['w']),s(w['i']),s(w.get('n')),s(w.get('z')),n(Z.get(w.get('z'))),n(w.get('x')),n(w.get('y')),n(w.get('lo')),n(w.get('hi')),s(ONLY.get(w['w'])),pr(w.get('h')),pr(w.get('a')),s(CONT.get(w.get('c')))]))
out.append('}')
# Waylaid Crates (Merchant's Favor): {crateID, tier, category, level, favor, favorEstimated, name, crateH, crateA, options{{itemID, qty, name, h, a}}}
def pp(x): return n(x[0]) if WITH_PRICES and x and x[0] else 'nil'
out.append('ns.CRATES = {')
for c in d.get('crates',[]):
    ops=','.join('{%s,%s,%s,%s,%s}'%(n(o['id']),n(o['q']),s(o['n']),pp(o.get('h')),pp(o.get('a'))) for o in c['opts'])
    out.append('{%s,%s,%s,%s,%s,%s,%s,%s,%s,{%s}},'%(n(c['cid']),s(c['tier']),s(c['cat']),n(c['lvl']),n(c['favor'] or 20),
        'true' if c['favor'] is None else 'false',s(c['crate']),pp(c.get('h')),pp(c.get('a')),ops))
out.append('}')
open(sys.argv[2],'w',newline='\n').write('\n'.join(out)+'\n')
missing=[w['z'] for w in W if w.get('z') and w['z'] not in Z]; print('rows',len(W),'missing maps',missing)
