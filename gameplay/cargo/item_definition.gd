class_name ItemDefinition
extends Resource
## One kind of thing that can be carried: a colony good, a piece of equipment. Red Sea Baron's
## ItemDefinition (id, title, mass, value) with a `look` for the Cart's load and a `use`.
##
## The catalogue is built once from the colony economy's goods (EconomyCatalog.ITEMS: timber,
## planks, stone blocks, tools, bread, fish, cloth...) plus the courier's own equipment: Garand
## ammunition crates and fuel cans. Item ids are the economy's, so a sack of grain moved from a
## warehouse into a cart and on to another warehouse is the same item all the way.

@export var id := ""
@export var title := ""
@export var mass := 1.0            ## kg per unit
@export var value := 1             ## coins per unit at a shop
## How it looks on a cart bed: crate, sack, barrel, planks, logs, blocks, bolt, can, ammo.
@export var look := "crate"
## What using one does: "" (nothing), "fuel" (a quarter tank), "ammo" (Garand clips).
@export var use := ""
@export var colour := Color.WHITE

## Equipment that is not a colony good: [title, kg, coins, look, use, colour].
const EQUIPMENT := {
	"ammo_crate": ["Ammo crate", 6.0, 24, "ammo", "ammo", Color("5b6340")],     # four Garand clips
	"fuel_can": ["Fuel can", 18.0, 12, "can", "fuel", Color("a8322a")],          # 20 L: a quarter tank
}
## The equipment a road station's shop keeps in stock.
const SHOP_STOCK := ["fuel_can", "ammo_crate"]
## Garand clips in one ammunition crate; a fuel can's share of a full tank.
const CLIPS_PER_CRATE := 4
const CAN_TANK_SHARE := 0.25

## Economy goods by how they travel.
const LOOKS := {
	"wood": "logs", "planks": "planks", "stone": "blocks", "blocks": "blocks", "ore": "blocks",
	"grain": "sack", "flour": "sack", "salt": "sack", "cotton": "sack", "olive": "sack", "grapes": "crate",
	"dates": "sack", "potatoes": "sack", "vegetables": "crate", "berry": "crate", "fish": "crate",
	"preserved_fish": "crate", "bread": "crate", "cheese": "crate", "game": "crate", "tools": "crate",
	"oil": "barrel", "wine": "barrel", "cloth": "bolt",
}

static var catalog: Dictionary = {}


static func get_item(key: String) -> ItemDefinition:
	if catalog.is_empty(): _build()
	return catalog.get(key)


static func ids() -> Array:
	if catalog.is_empty(): _build()
	return catalog.keys()


static func _build() -> void:
	for gid: String in EconomyCatalog.ITEMS:
		var row: Array = EconomyCatalog.ITEMS[gid]
		var item := ItemDefinition.new()
		item.id = gid
		item.title = String(row[0])
		item.mass = float(row[1])
		item.value = maxi(1, roundi(float(row[1]) * 2.0))
		item.look = String(LOOKS.get(gid, "crate"))
		item.colour = row[3]
		catalog[gid] = item
	for eid: String in EQUIPMENT:
		var row: Array = EQUIPMENT[eid]
		var item := ItemDefinition.new()
		item.id = eid
		item.title = String(row[0])
		item.mass = float(row[1])
		item.value = int(row[2])
		item.look = String(row[3])
		item.use = String(row[4])
		item.colour = row[5]
		catalog[eid] = item
