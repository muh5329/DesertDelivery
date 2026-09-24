class_name UrgentSupply
extends RefCounted
## Urgent supply runs: when a founded town colony runs short of food or of a good, it posts an
## optional courier job — "Urgent: 20 bread to Isola Serena" — collected at a town that has it
## (the plains market for bread, the ports for fish, the souk for cloth and dates, Valdoro for
## tools...) and carried in the cargo truck. Taking one (U, or `accept`) makes it the courier's
## current job through the DeliverySystem (a JobDefinition like any other, shown on the HUD);
## the regular route resumes where it was once it is delivered. Delivery pays the job's reward
## (a bonus for the urgency and the distance) and puts the goods into the colony's stock.
##
## Offers are transient (re-posted from the colonies' state); the accepted job is the
## DeliverySystem's and persists with it (its id is `job.urgent.<colony>.<item>`).

const CHECK_EVERY := 3.0
const PREFIX := "job.urgent."
## item -> where a courier can buy it (WorldDatabase locations), best first
const SOURCES := {
	"bread": ["campo_real", "hamlet_molino_alto", "villa_rosa_office"],
	"fish": ["puerto_alto", "isola_serena", "sarmada", "harbour_cafe"],
	"preserved_fish": ["sarmada", "puerto_alto"],
	"dates": ["sarmada", "hamlet_oasis_zagora"],
	"olive": ["campo_real", "isola_serena", "villa_rosa_office"],
	"cloth": ["sarmada"],
	"tools": ["valdoro", "puerto_alto"],
	"oil": ["campo_real", "villa_rosa_office"],
	"wine": ["isola_serena", "villa_rosa_office"],
}
const FOOD_ORDER := ["bread", "fish", "dates", "olive", "preserved_fish"]
const UNIT_VALUE := {"food": 2.0, "goods": 4.0}

var econ: ColonyEconomy
var offers: Array = []          # {id, colony, item, qty, from, reward, need}
var delivered := 0
var _t := 0.0


func setup(p_econ: ColonyEconomy) -> void:
	econ = p_econ
	if not Events.delivery_completed.is_connected(_on_delivered):
		Events.delivery_completed.connect(_on_delivered)


func _db() -> WorldDatabase:
	return econ.game.world.database if econ != null and econ.game != null else null


func _gm() -> DeliverySystem:
	return econ.game.gm if econ != null and econ.game != null else null


## The urgent job the courier has taken (the DeliverySystem's current job), or null.
func active_job() -> JobDefinition:
	var gm := _gm()
	if gm == null: return null
	var j := gm.current_job()
	return j if j != null and String(j.id).begins_with(PREFIX) else null


func update(delta: float) -> void:
	_t += delta
	if _t < CHECK_EVERY: return
	_t = 0.0
	refresh()


## Post an offer for every founded town colony that is short (and has none yet); drop offers
## whose shortage has passed (unless taken).
func refresh() -> void:
	var taken := active_job()
	for o in offers.duplicate():
		var t := econ.town(String(o.colony))
		if t == null or not t.founded or (not _short_of(t, String(o.item)) and (taken == null or String(taken.id) != String(o.id))):
			offers.erase(o)
	for cid in econ.towns:
		if cid == "core": continue
		var t: ColonyTown = econ.towns[cid]
		if not t.founded or t.colonists.is_empty(): continue
		if _has_offer(cid): continue
		var need := _shortage(t)
		if need == "": continue
		var o := make_offer(cid, need)
		if not o.is_empty():
			offers.append(o)
			econ._notify(cid, "Urgent: %d %s wanted at %s (+%d coins) - U to take the job." % [o.qty, EconomyCatalog.item_name(need).to_lower(), t.display_name, o.reward], true)


func _has_offer(cid: String) -> bool:
	for o in offers:
		if String(o.colony) == cid: return true
	var j := active_job()
	return j != null and String(j.id).begins_with(PREFIX + cid + ".")


## What a colony is short of: a food when its people go hungry or the larder is nearly empty,
## otherwise a good it wants and has none of. "" when all is well.
func _shortage(t: ColonyTown) -> String:
	var pop := t.colonists.size()
	var food := 0
	for f in EconomyCatalog.FOODS: food += t.count(f)
	if float(t.needs.get("food", 1.0)) < 0.8 or food < maxi(4, pop * 2):
		var best := ""; var least := 1 << 30
		for f in FOOD_ORDER:
			if t.count(f) < least: least = t.count(f); best = f
		return best
	# goods only once the colony has lived through a needs period (a new colony has none yet)
	if t.clock > ColonyTown.NEED_PERIOD * 2.0 and float(t.needs.get("goods", 1.0)) < 0.5:
		for g in EconomyCatalog.GOODS:
			if t.count(g) == 0: return g
	return ""


func _short_of(t: ColonyTown, item: String) -> bool:
	return _shortage(t) != "" and t.count(item) < maxi(4, t.colonists.size())


## An offer: the item, a quantity for the colony's size, the nearest source at least 500 m
## away, and a reward for the goods, the urgency and the distance.
func make_offer(cid: String, item: String) -> Dictionary:
	var db := _db()
	var t := econ.town(cid)
	if db == null or t == null or not db.locations.has(StringName(cid)): return {}
	var to := db.location_pos(StringName(cid))
	var best := ""; var best_d := INF
	for src: String in SOURCES.get(item, []):
		if src == cid or not db.locations.has(StringName(src)): continue
		var d := db.location_pos(StringName(src)).distance_to(to)
		if d > 500.0 and d < best_d: best_d = d; best = src
	if best == "": return {}
	var qty := clampi(snappedi(maxi(t.colonists.size() * 3, 10), 5), 10, 40)
	var cat := String(EconomyCatalog.ITEMS.get(item, ["", 1.0, "food"])[2])
	var reward := roundi(qty * float(UNIT_VALUE.get(cat, 2.0)) * 1.5 + best_d / 120.0)
	return {"id": "%s%s.%s.%d" % [PREFIX, cid, item, qty], "colony": cid, "item": item, "qty": qty, "from": best, "reward": reward}


## The JobDefinition for an offer: carried in the cargo truck.
static func job_for(o: Dictionary) -> JobDefinition:
	var j := JobDefinition.new()
	j.id = StringName(o.id)
	j.display_name = "Urgent supplies"
	j.from_location = StringName(o.from)
	j.to_location = StringName(o.colony)
	j.item = "%d %s (urgent)" % [int(o.qty), EconomyCatalog.item_name(String(o.item)).to_lower()]
	j.reward = int(o.reward)
	j.cargo_kind = "heavy"
	j.cargo_mass_kg = clampf(float(o.qty) * EconomyCatalog.mass(String(o.item)), 0.0, 80.0)
	j.vehicle = "truck"
	return j


## Take an offer (the first when `id` is empty). Returns "" or why not.
func accept(id := "") -> String:
	var gm := _gm()
	if gm == null: return "No courier."
	if offers.is_empty(): return "No urgent supply job right now."
	var o: Dictionary = offers[0]
	if id != "":
		o = {}
		for c in offers:
			if String(c.id) == id: o = c
		if o.is_empty(): return "That job is gone."
	if active_job() != null: return "You are already on an urgent run."
	if gm.carrying: return "Deliver the parcel you are carrying first."
	if not gm.start_extra_job(job_for(o)): return "The job could not be started."
	Events.message.emit("Urgent: collect %d %s at %s with the cargo truck, take it to %s. +%d coins." % [int(o.qty),
		EconomyCatalog.item_name(String(o.item)).to_lower(), _db().location_name(StringName(o.from)), _db().location_name(StringName(o.colony)), int(o.reward)], 5.0)
	return ""


## HUD line for the first open offer ("" when none, or when one is being run).
func hud_text() -> String:
	if active_job() != null or offers.is_empty(): return ""
	var o: Dictionary = offers[0]
	return "URGENT · %d %s → %s · +%d coins · U to take it" % [int(o.qty), EconomyCatalog.item_name(String(o.item)).to_lower(),
		_db().location_name(StringName(o.colony)), int(o.reward)]


func _on_delivered(job_id: StringName, _total: int) -> void:
	var s := String(job_id)
	if not s.begins_with(PREFIX): return
	var parts := s.substr(PREFIX.length()).split(".")
	if parts.size() < 3: return
	var cid := parts[0]; var item := parts[1]; var qty := maxi(1, int(parts[2]))
	var t := econ.town(cid)
	for o in offers.duplicate():
		if String(o.id) == s: offers.erase(o)
	if t != null:
		t.add(item, qty)
		delivered += 1
		econ._notify(cid, "%s received %d %s from the courier." % [t.display_name, qty, EconomyCatalog.item_name(item).to_lower()], true)
		econ.changed.emit()
