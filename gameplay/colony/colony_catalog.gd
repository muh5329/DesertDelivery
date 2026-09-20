class_name ColonyCatalog
extends RefCounted
const CORE := ["Unemployed","Forager","Woodcutter","Miner","Farmer","Builder","Transporter"]
const ZONE_ROLES := ["Forager","Woodcutter","Miner","Farmer"]
const WORKPLACES := {"Gathering camp":"Forager","Lumber camp":"Woodcutter","Quarry":"Miner","Farm":"Farmer","Depot":"Transporter"}
const PROFESSIONS := {
"Bailiff":"Lord manor","Baker":"Bakery","Bartender":"Tavern","Bee Keeper":"Apiary","Blacksmith":"Blacksmith / Weaponsmith","Brewer":"Brewery","Builder":"Construction site","Butcher":"Butchery","Carpenter":"Sawmill","Charcoal Burner":"Coal hut","Cheesemaker":"Cheesemaker","Cook":"Tavern","Cooper":"Cooperage","Farmer":"Farm","Fisherman":"Fisher's hut","Forager":"Gathering camp","Forester":"Forester camp","Herbalist":"Herb garden","Hopgrower":"Hop farm","Hunter":"Hunter's hut","Iron Smelter":"Iron smelter","Market Tender":"Market","Miller":"Windmill","Miner":"Quarry","Monk":"Monastery","Nun":"Monastery","Shepherd":"Sheep farm","Soldier":"Keep / Lord manor","Stone Cutter":"Stonecutter camp","Stone Mason":"Stonemason hut","Tailor":"Tailor's workshop","Tax Collector":"Tax office","Transporter":"Depot / Warehouse","Unemployed":"No workplace","Vinegrower":"Vineyard","Vintner":"Winery","Weaver":"Weaver hut","Woodcutter":"Lumber camp"}
static func accepts(role: String, item: String) -> bool:
	return item in {"Forager":["berry"],"Woodcutter":["wood"],"Miner":["ore","stone"],"Farmer":["olive"]}.get(role,[])
static func color(role: String) -> Color:
	return {"Forager":Color("b983a5"),"Woodcutter":Color("71a879"),"Miner":Color("96abb5"),"Farmer":Color("d8b765"),"Builder":Color("d29062")}.get(role,Color("70acb3"))
