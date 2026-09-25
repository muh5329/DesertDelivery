class_name EconomyCatalog
extends RefCounted
## The colony economy as data: goods, buildings, ships, needs and the towns that can become
## colonies. Pure tables, read by ColonyTown (the rules), ColonyEconomy (the world) and the
## Mayor view (the menus). Item ids keep the original colony's names (wood, olive, stone, ore,
## berry) so the core warehouse of a v1 save is already an economy stockpile.

## id -> [display name, mass per unit, category, map colour]
const ITEMS := {
	"wood": ["Timber", 2.0, "raw", Color("8a6a44")],
	"stone": ["Stone", 3.0, "raw", Color("a7a39a")],
	"ore": ["Ore", 4.0, "raw", Color("7d6f6a")],
	"grain": ["Grain", 1.0, "raw", Color("e0c26a")],
	"olive": ["Olives", 1.0, "food", Color("7f8a45")],
	"grapes": ["Grapes", 1.0, "raw", Color("7b3f6e")],
	"fish": ["Fish", 1.0, "food", Color("8fb3c4")],
	"salt": ["Salt", 1.0, "raw", Color("eeeae0")],
	"cotton": ["Cotton", 0.5, "raw", Color("f4f1e8")],
	"dates": ["Dates", 1.0, "food", Color("8c5a2b")],
	"berry": ["Berries", 1.0, "food", Color("b983a5")],
	"cheese": ["Cheese", 1.0, "food", Color("e8d27a")],
	"potatoes": ["Potatoes", 1.0, "food", Color("b89a5e")],
	"game": ["Game", 1.0, "food", Color("8a4f3a")],
	"vegetables": ["Vegetables", 1.0, "food", Color("6f9a3e")],
	"planks": ["Planks", 2.0, "material", Color("c79a5f")],
	"blocks": ["Stone blocks", 3.0, "material", Color("cfc6b2")],
	"tools": ["Tools", 2.0, "goods", Color("5f6b73")],
	"flour": ["Flour", 1.0, "raw", Color("f3ead2")],
	"bread": ["Bread", 1.0, "food", Color("c98b45")],
	"oil": ["Olive oil", 1.0, "goods", Color("c7b43c")],
	"wine": ["Wine", 1.0, "goods", Color("7a2335")],
	"cloth": ["Cloth", 0.5, "goods", Color("5a7fa8")],
	"preserved_fish": ["Preserved fish", 1.0, "food", Color("b07a4c")],
}
const FOODS := ["bread", "fish", "preserved_fish", "dates", "olive", "berry", "cheese", "potatoes", "game", "vegetables"]
const GOODS := ["cloth", "tools", "oil", "wine"]
const LEGACY_ITEMS := ["wood", "berry", "stone", "ore", "olive"]

## Building id -> definition.
##   cat: house / raw / processing / storage / port;  kind: the BuildingKit plot kind
##   w, d, floors: the plot;  cost: materials from the colony stock;  coins: from the wallet
##   workers, cycle (s), inputs / outputs per cycle, storage (per-building output buffer)
##   raw: the regional resource the site needs (EconomyCatalog.REGIONS);  coast: must be by water
##   housing: colonists housed;  capacity: stockpile mass added;  prop: the yard dressing
const BUILDINGS := {
	"cottage": {"name": "Cottage", "cat": "house", "kind": "house", "w": 8.0, "d": 7.0, "floors": 2, "cost": {"planks": 6}, "coins": 20, "housing": 4, "build": 20.0, "prop": "garden"},
	"townhouse": {"name": "Townhouse", "cat": "house", "kind": "rowhouse", "w": 9.0, "d": 9.0, "floors": 3, "cost": {"planks": 8, "blocks": 6}, "coins": 45, "housing": 8, "build": 32.0, "prop": "garden"},
	"woodcutter": {"name": "Woodcutter's lodge", "cat": "raw", "kind": "house", "w": 7.0, "d": 6.0, "floors": 1, "cost": {"planks": 4}, "coins": 25, "workers": 2, "cycle": 30.0, "inputs": {}, "outputs": {"wood": 3}, "storage": 18, "raw": "wood", "build": 18.0, "prop": "logs", "occupation": "ranger"},
	"quarry": {"name": "Stone quarry", "cat": "raw", "kind": "barn", "w": 8.0, "d": 7.0, "floors": 1, "cost": {"planks": 6}, "coins": 30, "workers": 2, "cycle": 30.0, "inputs": {}, "outputs": {"stone": 3}, "storage": 18, "raw": "stone", "build": 20.0, "prop": "quarry", "occupation": "stonemason"},
	"mine": {"name": "Ore mine", "cat": "raw", "kind": "house", "w": 7.0, "d": 7.0, "floors": 1, "cost": {"planks": 8, "tools": 1}, "coins": 40, "workers": 3, "cycle": 40.0, "inputs": {}, "outputs": {"ore": 3}, "storage": 18, "raw": "ore", "build": 24.0, "prop": "mine", "occupation": "stonemason"},
	"grain_farm": {"name": "Grain farm", "cat": "raw", "kind": "barn", "w": 10.0, "d": 8.0, "floors": 1, "cost": {"planks": 6}, "coins": 25, "workers": 2, "cycle": 40.0, "inputs": {}, "outputs": {"grain": 4}, "storage": 24, "raw": "grain", "build": 20.0, "prop": "wheat", "occupation": "farmer"},
	"olive_grove": {"name": "Olive grove", "cat": "raw", "kind": "house", "w": 7.0, "d": 6.0, "floors": 1, "cost": {"planks": 4}, "coins": 20, "workers": 2, "cycle": 40.0, "inputs": {}, "outputs": {"olive": 4}, "storage": 24, "raw": "olive", "build": 18.0, "prop": "olives", "occupation": "farmer"},
	"vineyard": {"name": "Vineyard", "cat": "raw", "kind": "house", "w": 7.0, "d": 6.0, "floors": 1, "cost": {"planks": 4}, "coins": 20, "workers": 2, "cycle": 40.0, "inputs": {}, "outputs": {"grapes": 4}, "storage": 24, "raw": "grapes", "build": 18.0, "prop": "vines", "occupation": "farmer"},
	"fishing_hut": {"name": "Fishing hut", "cat": "raw", "kind": "boathouse", "w": 7.0, "d": 8.0, "floors": 1, "cost": {"planks": 5}, "coins": 20, "workers": 2, "cycle": 30.0, "inputs": {}, "outputs": {"fish": 3}, "storage": 18, "raw": "fish", "coast": true, "build": 18.0, "prop": "fish_racks", "occupation": "fisher"},
	"salt_pans": {"name": "Salt pans", "cat": "raw", "kind": "shop", "w": 6.0, "d": 6.0, "floors": 1, "cost": {"planks": 4}, "coins": 20, "workers": 2, "cycle": 40.0, "inputs": {}, "outputs": {"salt": 3}, "storage": 18, "raw": "salt", "coast": true, "build": 18.0, "prop": "salt", "occupation": "porter"},
	"cotton_field": {"name": "Cotton field", "cat": "raw", "kind": "barn", "w": 9.0, "d": 7.0, "floors": 1, "cost": {"planks": 5}, "coins": 25, "workers": 2, "cycle": 40.0, "inputs": {}, "outputs": {"cotton": 3}, "storage": 18, "raw": "cotton", "build": 20.0, "prop": "cotton", "occupation": "farmer"},
	"date_grove": {"name": "Date palm grove", "cat": "raw", "kind": "house", "w": 7.0, "d": 6.0, "floors": 1, "cost": {"planks": 4}, "coins": 20, "workers": 2, "cycle": 40.0, "inputs": {}, "outputs": {"dates": 3}, "storage": 18, "raw": "dates", "build": 18.0, "prop": "palms", "occupation": "gardener"},
	"dairy": {"name": "Dairy", "cat": "raw", "kind": "barn", "w": 9.0, "d": 7.0, "floors": 1, "cost": {"planks": 5}, "coins": 25, "workers": 2, "cycle": 40.0, "inputs": {}, "outputs": {"cheese": 3}, "storage": 18, "raw": "cheese", "build": 20.0, "prop": "barrels", "occupation": "farmer"},
	"potato_field": {"name": "Potato field", "cat": "raw", "kind": "barn", "w": 9.0, "d": 7.0, "floors": 1, "cost": {"planks": 4}, "coins": 20, "workers": 2, "cycle": 40.0, "inputs": {}, "outputs": {"potatoes": 4}, "storage": 24, "raw": "potatoes", "build": 18.0, "prop": "wheat", "occupation": "farmer"},
	"hunting_lodge": {"name": "Hunting lodge", "cat": "raw", "kind": "house", "w": 7.0, "d": 6.0, "floors": 1, "cost": {"planks": 4}, "coins": 20, "workers": 2, "cycle": 45.0, "inputs": {}, "outputs": {"game": 3}, "storage": 18, "raw": "game", "build": 18.0, "prop": "logs", "occupation": "ranger"},
	"market_garden": {"name": "Market garden", "cat": "raw", "kind": "house", "w": 7.0, "d": 6.0, "floors": 1, "cost": {"planks": 4}, "coins": 20, "workers": 2, "cycle": 40.0, "inputs": {}, "outputs": {"vegetables": 4}, "storage": 24, "raw": "vegetables", "build": 18.0, "prop": "garden", "occupation": "gardener"},
	"sawmill": {"name": "Sawmill", "cat": "processing", "kind": "warehouse", "w": 10.0, "d": 8.0, "floors": 1, "cost": {"planks": 6, "blocks": 2}, "coins": 40, "workers": 2, "cycle": 30.0, "inputs": {"wood": 2}, "outputs": {"planks": 2}, "storage": 20, "build": 26.0, "prop": "sawmill", "occupation": "porter"},
	"flour_mill": {"name": "Flour mill", "cat": "processing", "kind": "windmill", "w": 7.0, "d": 7.0, "floors": 2, "cost": {"planks": 8, "blocks": 4}, "coins": 45, "workers": 1, "cycle": 30.0, "inputs": {"grain": 3}, "outputs": {"flour": 2}, "storage": 20, "build": 30.0, "prop": "sacks", "occupation": "baker"},
	"bakery": {"name": "Bakery", "cat": "processing", "kind": "shop", "w": 8.0, "d": 7.0, "floors": 2, "cost": {"planks": 6, "blocks": 4}, "coins": 40, "workers": 2, "cycle": 30.0, "inputs": {"flour": 2}, "outputs": {"bread": 4}, "storage": 24, "build": 26.0, "prop": "oven", "occupation": "baker"},
	"olive_press": {"name": "Olive press", "cat": "processing", "kind": "shop", "w": 8.0, "d": 7.0, "floors": 1, "cost": {"planks": 6, "blocks": 2}, "coins": 35, "workers": 2, "cycle": 40.0, "inputs": {"olive": 3}, "outputs": {"oil": 1}, "storage": 12, "build": 24.0, "prop": "vats", "occupation": "merchant"},
	"winery": {"name": "Winery", "cat": "processing", "kind": "warehouse", "w": 9.0, "d": 8.0, "floors": 1, "cost": {"planks": 8, "blocks": 4}, "coins": 45, "workers": 2, "cycle": 50.0, "inputs": {"grapes": 3}, "outputs": {"wine": 1}, "storage": 12, "build": 28.0, "prop": "barrels", "occupation": "merchant"},
	"smithy": {"name": "Smithy", "cat": "processing", "kind": "shop", "w": 8.0, "d": 7.0, "floors": 1, "cost": {"planks": 6, "blocks": 6}, "coins": 50, "workers": 2, "cycle": 50.0, "inputs": {"ore": 2, "planks": 1}, "outputs": {"tools": 1}, "storage": 12, "build": 30.0, "prop": "forge", "occupation": "mechanic"},
	"weaver": {"name": "Weaver", "cat": "processing", "kind": "house", "w": 8.0, "d": 7.0, "floors": 2, "cost": {"planks": 6, "blocks": 2}, "coins": 35, "workers": 2, "cycle": 40.0, "inputs": {"cotton": 2}, "outputs": {"cloth": 1}, "storage": 12, "build": 24.0, "prop": "frames", "occupation": "weaver"},
	"smokehouse": {"name": "Smokehouse", "cat": "processing", "kind": "barn", "w": 8.0, "d": 6.0, "floors": 1, "cost": {"planks": 6, "blocks": 2}, "coins": 35, "workers": 2, "cycle": 40.0, "inputs": {"fish": 2, "salt": 1}, "outputs": {"preserved_fish": 3}, "storage": 18, "build": 24.0, "prop": "smoke_racks", "occupation": "fisher"},
	"mason": {"name": "Mason's yard", "cat": "processing", "kind": "shop", "w": 8.0, "d": 7.0, "floors": 1, "cost": {"planks": 6}, "coins": 35, "workers": 2, "cycle": 30.0, "inputs": {"stone": 2}, "outputs": {"blocks": 2}, "storage": 20, "build": 22.0, "prop": "blocks", "occupation": "stonemason"},
	"warehouse": {"name": "Warehouse", "cat": "storage", "kind": "warehouse", "w": 11.0, "d": 9.0, "floors": 1, "cost": {"planks": 10, "blocks": 4}, "coins": 50, "capacity": 800.0, "build": 30.0, "prop": "crates"},
	"shipyard": {"name": "Shipyard", "cat": "port", "kind": "boathouse", "w": 10.0, "d": 12.0, "floors": 1, "cost": {"planks": 16, "blocks": 8, "tools": 2}, "coins": 120, "workers": 2, "port": true, "coast": true, "build": 40.0, "prop": "slipway", "occupation": "dockworker"},
	"colony_hall": {"name": "Colony hall & warehouse", "cat": "storage", "kind": "warehouse", "w": 12.0, "d": 10.0, "floors": 2, "cost": {}, "coins": 0, "capacity": 1000.0, "build": 1.0, "prop": "crates", "unique": true},
}
const CATEGORIES := [["house", "Housing"], ["raw", "Raw resources"], ["processing", "Processing"], ["storage", "Storage"], ["port", "Port & ships"]]

## Ships: capacity (units), speed (m/s at sea: the country is compressed), port time per unit.
const SHIPS := {
	"coaster": {"name": "Motor coaster", "capacity": 40, "speed": 16.0, "cost": {"planks": 20, "tools": 4}, "coins": 150, "load_s": 0.12},
	"schooner": {"name": "Topsail schooner", "capacity": 90, "speed": 12.5, "cost": {"planks": 40, "cloth": 10, "tools": 6}, "coins": 300, "load_s": 0.1},
}
const SHIP_NAMES := ["Santa Rosa", "Gaviota", "Estrella", "Brisa", "Marinera", "Aurora", "Delfina", "Sirena",
	"Esperanza", "Golondrina", "Paloma", "Corazon", "Luz del Mar", "Alba", "Levante", "Poniente"]

## The colonies: the core villa colony and the five towns. raw: what the land around each gives.
## Hamlets are too small for a charter; they stay delivery stops.
## staple: what the settlers grow, catch or hunt round the colony hall from the first day (the
## hall's kitchen garden: 2 workers), so a charter left alone feeds itself; every town also has
## local food buildings (its `raw` foods) to grow on.
const COLONIES := {
	"core": {"name": "Villa Rosa (core island)", "style": "island", "raw": ["olive", "grapes", "stone", "fish", "salt", "wood", "berry", "vegetables"], "charter": 0, "radius": 720.0},
	"puerto_alto": {"name": "Puerto Alto", "style": "puerto", "raw": ["fish", "stone", "salt", "potatoes", "vegetables"], "charter": 120, "staple": "fish"},
	"valdoro": {"name": "Valdoro", "style": "valdoro", "raw": ["wood", "stone", "ore", "cheese", "potatoes", "game"], "charter": 120, "staple": "potatoes"},
	"sarmada": {"name": "Sarmada", "style": "sarmada", "raw": ["salt", "cotton", "dates", "fish", "vegetables"], "charter": 120, "staple": "dates"},
	"isola_serena": {"name": "Isola Serena", "style": "isola", "raw": ["fish", "grapes", "olive", "cheese", "vegetables"], "charter": 120, "staple": "fish"},
	"campo_real": {"name": "Campo Real", "style": "campo", "raw": ["grain", "olive", "wood", "cheese", "vegetables", "game"], "charter": 120, "staple": "vegetables"},
}
## What a founding charter brings: the hall, settlers and a starter stock (plus STAPLE_STOCK of
## the colony's staple): ~20 minutes of food for the settlers with no production at all.
const CHARTER_STOCK := {"planks": 30, "blocks": 12, "tools": 4, "bread": 16}
const STAPLE_STOCK := 16
const HALL_GARDEN := {"workers": 2, "cycle": 40.0, "amount": 3, "storage": 18}
const CHARTER_SETTLERS := 5
const BUILD_RADIUS := 320.0
const MALE_NAMES := ["Tomas", "Mateo", "Luca", "Pau", "Hugo", "Iker", "Marco", "Nico", "Rafa", "Emilio", "Bruno",
	"Dario", "Elio", "Felix", "Gil", "Ivo", "Joel", "Leo", "Omar", "Pablo", "Ramon", "Samir", "Teo", "Yusuf"]
const FEMALE_NAMES := ["Mara", "Ines", "Rosa", "Nora", "Celia", "Elsa", "Greta", "Iris", "Kira", "Mina", "Alma",
	"Clara", "Flora", "Lena", "Nina", "Pia", "Sara", "Vera", "Leila", "Amina", "Carmen", "Lucia"]
const SURNAMES := {
	"island": ["Rosales", "Marin", "Soler", "Ferrer"], "puerto": ["Almeida", "Costa", "Ribeiro", "Pinto"],
	"valdoro": ["Brunner", "Rossi", "Gasser", "Moser"], "sarmada": ["Haddad", "Benali", "Idrissi", "Tazi"],
	"isola": ["Russo", "Esposito", "Greco", "Marino"], "campo": ["Garcia", "Molina", "Serrano", "Navarro"]}


static func item_name(id: String) -> String:
	return String(ITEMS[id][0]) if ITEMS.has(id) else id.capitalize()


static func mass(id: String) -> float:
	return float(ITEMS[id][1]) if ITEMS.has(id) else 1.0


static func item_color(id: String) -> Color:
	return ITEMS[id][3] if ITEMS.has(id) else Color.WHITE


static func building(id: String) -> Dictionary:
	return BUILDINGS.get(id, {})


## A building as it works in this colony: the colony hall keeps the settlers' kitchen garden
## (the colony's staple food) in a town colony.
static func def_for(colony_id: String, id: String) -> Dictionary:
	var def: Dictionary = BUILDINGS.get(id, {})
	if id != "colony_hall": return def
	var staple := String(COLONIES.get(colony_id, {}).get("staple", ""))
	if staple == "": return def
	var d := def.duplicate()
	d.workers = HALL_GARDEN.workers; d.cycle = HALL_GARDEN.cycle; d.inputs = {}
	d.outputs = {staple: HALL_GARDEN.amount}; d.storage = HALL_GARDEN.storage; d.occupation = "farmer"
	return d


## The foods a colony can grow itself.
static func local_foods(colony_id: String) -> Array:
	var out: Array = []
	for f in COLONIES.get(colony_id, {}).get("raw", []):
		if f in FOODS: out.append(f)
	return out


static func buildable_in(colony_id: String, id: String) -> bool:
	var b: Dictionary = BUILDINGS.get(id, {})
	if b.is_empty() or b.get("unique", false): return false
	if b.has("raw") and not String(b.raw) in COLONIES.get(colony_id, {}).get("raw", []): return false
	return true


## How far from its hall a colony may build (the core colony covers its whole island).
static func build_radius(colony_id: String) -> float:
	return float(COLONIES.get(colony_id, {}).get("radius", BUILD_RADIUS))


static func occupation(id: String) -> String:
	return String(BUILDINGS.get(id, {}).get("occupation", "porter"))


static func style_of(colony_id: String) -> StringName:
	return StringName(COLONIES.get(colony_id, {}).get("style", "island"))


static func describe_cost(cost: Dictionary, coins: int) -> String:
	var parts := PackedStringArray()
	if coins > 0: parts.append("%d coins" % coins)
	for item in cost: parts.append("%d %s" % [int(cost[item]), item_name(item).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "free"


static func describe_flow(b: Dictionary) -> String:
	var ins := PackedStringArray(); var outs := PackedStringArray()
	for item in b.get("inputs", {}): ins.append("%d %s" % [int(b.inputs[item]), item_name(item).to_lower()])
	for item in b.get("outputs", {}): outs.append("%d %s" % [int(b.outputs[item]), item_name(item).to_lower()])
	if outs.is_empty(): return ""
	return ("%s -> " % " + ".join(ins) if not ins.is_empty() else "") + " + ".join(outs) + " / %ds" % int(b.get("cycle", 30))
