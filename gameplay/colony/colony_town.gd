class_name ColonyTown
extends RefCounted
## One colony's economy: stockpile, buildings, colonists, needs and happiness. Pure rules - no
## nodes, no physics - so it ticks the same whether its town is loaded, on the other side of the
## country or inside a unit test. ColonyEconomy owns the towns and draws the near ones.
##
## Buildings are records: {id, type, x, y, z, yaw, built, progress (construction 0..1),
## cycle (production 0..1, 0 = idle), inbuf, outbuf, paused, produced, carry}. `carry` is the
## building's porter on the road: {phase 0 = to the warehouse with `load`, 1 = back with inputs,
## t, dur, load}. Goods move only when the porter arrives, so the logistics are the same
## abstract or drawn (the drawn porter walks exactly that trip).

const WALK_SPEED := 2.2
const NEED_PERIOD := 20.0
const FOOD_RATE := 1.0 / 150.0        # units per colonist per second (one every 2.5 minutes)
const GOODS_RATE := 1.0 / 400.0       # units of EACH good per colonist per second
const TAX_RATE := 0.25 / NEED_PERIOD  # coins per colonist per second at full happiness
const MAX_BUILDINGS := 64
const MAX_COLONISTS := 160

var id := ""
var display_name := ""
var style: StringName = &"island"
var founded := false
var discovered := false
var stock: Dictionary = {}
var buildings: Array = []
var colonists: Array = []
var happiness := 60.0
var needs := {"food": 1.0, "variety": 0.0, "goods": 0.0, "housing": 1.0}
var growth := 0.0
var decline := 0.0
var next_id := 1
var hall := Vector3.ZERO            # the colony hall / warehouse (trip ends, build area centre)
var coins_due := 0.0                # taxes not yet paid into the courier's wallet
var journal: Array = []             # [{t, text}] newest last, for the Mayor view
var clock := 0.0
var base_capacity := 0.0            # the core's original warehouse
var _food_owed := 0.0
var _goods_owed := {}                # good -> units owed (fractional)
var _eaten := {}                     # food -> clock when last eaten (variety)
var _short := {}                     # good -> seconds this period it was wanted and out of stock
var _hungry := 0.0                   # seconds this period with food owed and none in stock
var _period := 0.0
var _crew := {}                      # building id -> colonists working there (assign() keeps it)
var _employed := 0
var _cap := -1.0                     # stockpile capacity (recomputed when buildings change)
var _warned_food := false


func _init(p_id: String = "") -> void:
	id = p_id
	var info: Dictionary = EconomyCatalog.COLONIES.get(id, {})
	display_name = String(info.get("name", id))
	style = StringName(info.get("style", "island"))


# ------------------------------------------------------------------ stock
func count(item: String) -> int:
	return int(stock.get(item, 0))


func capacity() -> float:
	if _cap >= 0.0: return _cap
	var total := base_capacity
	for b in buildings:
		if b.built: total += float(EconomyCatalog.building(b.type).get("capacity", 0.0))
	_cap = total
	return total


func stock_mass() -> float:
	var total := 0.0
	for item in stock: total += EconomyCatalog.mass(item) * int(stock[item])
	return total


## How many of `item` still fit in the stockpile.
func room_for(item: String) -> int:
	return maxi(0, floori((capacity() - stock_mass()) / EconomyCatalog.mass(item) + 0.0001))


## Adds up to `amount`; returns how many fitted.
func add(item: String, amount: int) -> int:
	var n := mini(amount, room_for(item))
	if n <= 0: return 0
	stock[item] = count(item) + n
	return n


func take(item: String, amount: int) -> int:
	var n := mini(amount, count(item))
	if n <= 0: return 0
	stock[item] = count(item) - n
	if int(stock[item]) == 0 and not item in EconomyCatalog.LEGACY_ITEMS: stock.erase(item)
	return n


func can_afford(cost: Dictionary) -> bool:
	for item in cost:
		if count(item) < int(cost[item]): return false
	return true


func pay(cost: Dictionary) -> void:
	for item in cost: take(item, int(cost[item]))


# ------------------------------------------------------------------ buildings
func building(bid: String) -> Dictionary:
	for b in buildings:
		if b.id == bid: return b
	return {}


func add_building(type: String, at: Vector3, yaw: float, built := false) -> Dictionary:
	var b := {"id": "%s.b%d" % [id, next_id], "type": type, "x": at.x, "y": at.y, "z": at.z, "yaw": yaw,
		"built": built, "progress": 1.0 if built else 0.0, "cycle": 0.0, "inbuf": {}, "outbuf": {},
		"paused": false, "produced": 0, "carry": {}}
	next_id += 1
	buildings.append(b)
	_cap = -1.0
	return b


func remove_building(bid: String) -> bool:
	for i in range(buildings.size()):
		if buildings[i].id == bid:
			var b: Dictionary = buildings[i]
			if b.type == "colony_hall": return false
			# goods on the premises go back to the stockpile, as much as fits
			for buf in [b.inbuf, b.outbuf, b.carry.get("load", {})]:
				for item in buf: add(item, int(buf[item]))
			buildings.remove_at(i)
			for c in colonists:
				if c.job == bid: c.job = ""
				if c.home == bid: c.home = ""
			_recount()
			return true
	return false


func position_of(b: Dictionary) -> Vector3:
	return Vector3(float(b.x), float(b.y), float(b.z))


## The storage building a porter from `b` walks to: the nearest built hall or warehouse.
func storage_for(b: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var p := position_of(b); var d := INF
	for s in buildings:
		if not s.built or EconomyCatalog.building(s.type).get("cat", "") != "storage": continue
		var e := p.distance_to(position_of(s))
		if e < d: d = e; best = s
	return best


func trip_seconds(b: Dictionary) -> float:
	var s := storage_for(b)
	var d := position_of(b).distance_to(position_of(s)) if not s.is_empty() else 60.0
	return maxf(8.0, 2.0 * d * 1.25 / WALK_SPEED + 4.0)


func workers_needed(b: Dictionary) -> int:
	return int(def_of(b).get("workers", 0))


## A building's definition as it works here (the hall's kitchen garden in a town colony).
func def_of(b: Dictionary) -> Dictionary:
	return EconomyCatalog.def_for(id, String(b.type))


func workers_at(bid: String) -> int:
	return int(_crew.get(bid, 0))


## Rebuild the caches from the records (after anything edits them directly).
func _recount() -> void:
	_crew = {}
	_employed = 0
	for c in colonists:
		if c.job != "": _crew[c.job] = int(_crew.get(c.job, 0)) + 1; _employed += 1
	_cap = -1.0


func housing() -> int:
	var total := 0
	for b in buildings:
		if b.built: total += int(EconomyCatalog.building(b.type).get("housing", 0))
	# the hall houses the charter's settlers
	return total + (6 if not building_of_type("colony_hall").is_empty() else 0)


func building_of_type(type: String) -> Dictionary:
	for b in buildings:
		if b.type == type: return b
	return {}


func has_built(type: String) -> bool:
	for b in buildings:
		if b.type == type and b.built: return true
	return false


func unemployed() -> int:
	return colonists.size() - _employed


## Efficiency of a producer right now (0..1): staffing x happiness.
func efficiency(b: Dictionary) -> float:
	var need := workers_needed(b)
	if need <= 0 or not b.built or b.paused: return 0.0
	return float(workers_at(b.id)) / need * (0.7 + 0.3 * happiness / 100.0)


## What a building is doing, for the inspector and the notifications.
func status(b: Dictionary) -> String:
	if not b.built: return "Foundation" if float(b.progress) < 0.3 else "Under construction (%d%%)" % int(float(b.progress) * 100)
	if b.paused: return "Paused"
	var def := def_of(b)
	if workers_needed(b) > 0 and workers_at(b.id) == 0: return "No workers"
	if not def.has("outputs"): return "Working" if workers_needed(b) > 0 else "Ready"
	if float(b.cycle) > 0.0: return "Producing (%d%%)" % int(float(b.cycle) * 100)
	if _outbuf_total(b) + _sum(def.outputs) > int(def.storage): return "Output full - needs a porter"
	if not _has(b.inbuf, def.inputs): return "Waiting for " + _missing(b, def.inputs)
	return "Ready"


# ------------------------------------------------------------------ colonists
func add_colonist(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var female := rng.randf() < 0.5
	var first: String = (EconomyCatalog.FEMALE_NAMES if female else EconomyCatalog.MALE_NAMES)[rng.randi() % (EconomyCatalog.FEMALE_NAMES if female else EconomyCatalog.MALE_NAMES).size()]
	var sur: Array = EconomyCatalog.SURNAMES.get(String(style), EconomyCatalog.SURNAMES.island)
	var c := {"id": "%s.c%d" % [id, next_id], "name": "%s %s" % [first, sur[rng.randi() % sur.size()]], "seed": seed, "sex": "f" if female else "m", "job": "", "home": ""}
	next_id += 1
	colonists.append(c)
	return c


func colonist(cid: String) -> Dictionary:
	for c in colonists:
		if c.id == cid: return c
	return {}


## Fill jobs in building order, free the jobs of paused or removed buildings, find homes.
func assign() -> void:
	var live := {}
	for b in buildings:
		if b.built and not b.paused and workers_needed(b) > 0: live[b.id] = workers_needed(b)
	var filled := {}
	# the hall's kitchen garden takes the hands nobody else needs: its gardeners are freed first
	# and it is filled last, so a new workshop always gets its workers
	for c in colonists:
		if c.job != "" and live.has(c.job) and String(building(c.job).get("type", "")) != "colony_hall" and int(filled.get(c.job, 0)) < int(live[c.job]):
			filled[c.job] = int(filled.get(c.job, 0)) + 1
		else: c.job = ""
	# the hall's kitchen garden takes the hands nobody else needs (it comes last)
	var order: Array = buildings.filter(func(b): return b.type != "colony_hall") + buildings.filter(func(b): return b.type == "colony_hall")
	for b in order:
		if not live.has(b.id): continue
		for c in colonists:
			if int(filled.get(b.id, 0)) >= int(live[b.id]): break
			if c.job == "":
				c.job = b.id; filled[b.id] = int(filled.get(b.id, 0)) + 1
	# homes: houses first, then the hall
	var beds := {}
	for b in buildings:
		var n := int(EconomyCatalog.building(b.type).get("housing", 0)) if b.built else 0
		if b.type == "colony_hall": n = 6
		if n > 0: beds[b.id] = n
	var used := {}
	for c in colonists:
		if c.home != "" and beds.has(c.home) and int(used.get(c.home, 0)) < int(beds[c.home]): used[c.home] = int(used.get(c.home, 0)) + 1
		else: c.home = ""
	for c in colonists:
		if c.home != "": continue
		for bid in beds:
			if int(used.get(bid, 0)) < int(beds[bid]):
				c.home = bid; used[bid] = int(used.get(bid, 0)) + 1; break
	_recount()


# ------------------------------------------------------------------ the tick
## Advance `dt` seconds. Returns notifications (strings) worth telling the player.
func tick(dt: float) -> Array:
	var notes: Array = []
	if not founded or dt <= 0.0: return notes
	clock += dt
	for b in buildings:
		if not b.built:
			_construct(b, dt, notes)
			continue
		var def := def_of(b)
		if def.has("outputs"):
			_produce(b, def, dt)
			_porter(b, def, dt)
	_period += dt
	_consume(dt)
	if _period >= NEED_PERIOD:
		_period -= NEED_PERIOD
		_evaluate(notes)
	_grow(dt, notes)
	coins_due += colonists.size() * TAX_RATE * (happiness / 100.0) * dt
	for n in notes: _note(n)
	return notes


func _construct(b: Dictionary, dt: float, notes: Array) -> void:
	var build_time := float(EconomyCatalog.building(b.type).get("build", 20.0))
	var rate := 1.0 if unemployed() > 0 or colonists.is_empty() else 0.5
	b.progress = minf(1.0, float(b.progress) + dt * rate / build_time)
	if b.progress >= 1.0:
		b.built = true
		_cap = -1.0
		notes.append("%s completed." % EconomyCatalog.building(b.type).name)
		assign()


func _produce(b: Dictionary, def: Dictionary, dt: float) -> void:
	var eff := efficiency(b)
	if eff <= 0.0: return
	if float(b.cycle) <= 0.0:
		if _outbuf_total(b) + _sum(def.outputs) > int(def.storage): return
		if not _has(b.inbuf, def.inputs): return
		for item in def.inputs: _buf_take(b.inbuf, item, int(def.inputs[item]))
		b.cycle = 0.0001
	b.cycle = float(b.cycle) + dt * eff / float(def.cycle)
	if float(b.cycle) >= 1.0:
		b.cycle = 0.0
		for item in def.outputs:
			b.outbuf[item] = int(b.outbuf.get(item, 0)) + int(def.outputs[item])
			b.produced = int(b.produced) + int(def.outputs[item])


## The porter: out with the building's produce, back with inputs for two cycles.
func _porter(b: Dictionary, def: Dictionary, dt: float) -> void:
	if workers_at(b.id) == 0 and b.carry.is_empty(): return
	var carry: Dictionary = b.carry
	if carry.is_empty():
		var want := _wanted(b, def)
		if _outbuf_total(b) == 0 and want.is_empty(): return
		var load := {}
		for item in b.outbuf:
			if int(b.outbuf[item]) > 0: load[item] = int(b.outbuf[item])
		b.outbuf = {}
		b.carry = {"phase": 0, "t": 0.0, "dur": trip_seconds(b) * 0.5, "load": load}
		return
	carry.t = float(carry.t) + dt
	if float(carry.t) < float(carry.dur): return
	if int(carry.phase) == 0:
		# at the warehouse: unload what fits (the rest waits on the porter), pick up inputs
		var left := {}
		for item in carry.load:
			var n := int(carry.load[item]); var put := add(item, n)
			if put < n: left[item] = n - put
		var pick := {}
		if left.is_empty():
			var want := _wanted(b, def)
			for item in want:
				var got := take(item, int(want[item]))
				if got > 0: pick[item] = got
		if not left.is_empty():
			carry.load = left; carry.t = 0.0; carry.dur = 5.0   # wait at the door and retry
			return
		b.carry = {"phase": 1, "t": 0.0, "dur": trip_seconds(b) * 0.5, "load": pick}
	else:
		for item in carry.load: b.inbuf[item] = int(b.inbuf.get(item, 0)) + int(carry.load[item])
		b.carry = {}


func _wanted(b: Dictionary, def: Dictionary) -> Dictionary:
	var want := {}
	for item in def.get("inputs", {}):
		var need := int(def.inputs[item]) * 2 - int(b.inbuf.get(item, 0))
		var have := mini(need, count(item))
		if have > 0: want[item] = have
	return want


func _consume(dt: float) -> void:
	var pop := colonists.size()
	if pop == 0: return
	# food: a unit whenever a unit is owed; time spent owing with nothing to eat is hunger
	_food_owed = minf(_food_owed + pop * FOOD_RATE * dt, float(pop))
	while _food_owed >= 1.0:
		var item := _pick_food()
		if item == "": break
		take(item, 1); _food_owed -= 1.0
		_eaten[item] = clock
	if _food_owed >= 1.0: _hungry += dt
	# goods: each is wanted on its own; time spent owing one that is out of stock is want
	for g in EconomyCatalog.GOODS:
		var owed := minf(float(_goods_owed.get(g, 0.0)) + pop * GOODS_RATE * dt, maxf(1.0, pop * 0.2))
		while owed >= 1.0 and count(g) > 0:
			take(g, 1); owed -= 1.0
		_goods_owed[g] = owed
		if owed >= 1.0: _short[g] = float(_short.get(g, 0.0)) + dt


## The food in stock that was eaten longest ago: variety comes for free when it exists.
func _pick_food() -> String:
	var best := ""; var oldest := INF
	for f in EconomyCatalog.FOODS:
		if count(f) > 0 and float(_eaten.get(f, -1e9)) < oldest:
			oldest = float(_eaten.get(f, -1e9)); best = f
	return best


func _evaluate(notes: Array) -> void:
	var pop := colonists.size()
	if pop == 0: return
	needs.food = clampf(1.0 - _hungry / NEED_PERIOD, 0.0, 1.0)
	var kinds := 0
	for f in _eaten:
		if clock - float(_eaten[f]) < 90.0: kinds += 1
	needs.variety = clampf((kinds - 1) / 2.0, 0.0, 1.0)
	var goods := 0.0
	for g in EconomyCatalog.GOODS: goods += clampf(1.0 - float(_short.get(g, 0.0)) / NEED_PERIOD, 0.0, 1.0)
	needs.goods = goods / EconomyCatalog.GOODS.size()
	needs.housing = clampf(float(housing()) / pop, 0.0, 1.0)
	if needs.food < 0.5 and happiness > 30.0: notes.append("%s is short of food." % display_name)
	else:
		var left := food_minutes()
		if left < 6.0 and left >= 0.0 and not _warned_food:
			_warned_food = true
			notes.append("%s has food for about %d min: build %s, or send food by road or sea." % [display_name, maxi(1, roundi(left)), _food_hint()])
		elif left < 0.0 or left > 10.0: _warned_food = false
	_hungry = 0.0; _short = {}


## Minutes the stock of food lasts at today's eating and production; -1 when production keeps up.
func food_minutes() -> float:
	var pop := colonists.size()
	if pop == 0: return -1.0
	var eat := pop * FOOD_RATE * 60.0
	var make := food_output_per_minute()
	if make >= eat: return -1.0
	var have := 0
	for f in EconomyCatalog.FOODS: have += count(f)
	return have / (eat - make)


## Food the colony's working producers make a minute at today's staffing and happiness.
func food_output_per_minute() -> float:
	var total := 0.0
	for b in buildings:
		var def := def_of(b)
		if not def.has("outputs") or not def.get("inputs", {}).is_empty() and not _has(b.inbuf, def.inputs): continue
		for item in def.outputs:
			if item in EconomyCatalog.FOODS:
				total += float(def.outputs[item]) * 60.0 / float(def.cycle) * efficiency(b)
	return total


func _food_hint() -> String:
	var names := PackedStringArray()
	for type in EconomyCatalog.BUILDINGS:
		var def: Dictionary = EconomyCatalog.BUILDINGS[type]
		if def.has("raw") and String(def.raw) in EconomyCatalog.local_foods(id): names.append(String(def.name).to_lower())
	return "a " + " or a ".join(names.slice(0, 2)) if not names.is_empty() else "food buildings"


func target_happiness() -> float:
	return 100.0 * (0.42 * needs.food + 0.10 * needs.variety + 0.28 * needs.goods + 0.20 * needs.housing)


func _grow(dt: float, notes: Array) -> void:
	happiness += (target_happiness() - happiness) * minf(1.0, dt / 30.0)
	var pop := colonists.size()
	if happiness >= 55.0 and needs.food >= 0.9 and housing() > pop and pop < MAX_COLONISTS:
		growth += dt / 60.0 * (happiness - 50.0) / 50.0
		decline = 0.0
		if growth >= 1.0:
			growth = 0.0
			var c := add_colonist(hash([id, next_id, int(clock)]))
			assign()
			notes.append("%s arrived in %s." % [c.name, display_name])
	elif (happiness < 30.0 or needs.food < 0.4) and pop > 2:
		decline += dt / 90.0
		growth = 0.0
		if decline >= 1.0:
			decline = 0.0
			var c: Dictionary = colonists.pop_back()
			assign()
			notes.append("%s left %s (unhappy)." % [c.name, display_name])
	else:
		growth = maxf(0.0, growth - dt / 600.0)
		decline = maxf(0.0, decline - dt / 600.0)


func _note(text: String) -> void:
	journal.append({"t": clock, "text": text})
	if journal.size() > 40: journal.pop_front()


# ------------------------------------------------------------------ helpers
static func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d: n += int(d[k])
	return n


func _outbuf_total(b: Dictionary) -> int:
	return _sum(b.outbuf)


static func _has(buf: Dictionary, need: Dictionary) -> bool:
	for item in need:
		if int(buf.get(item, 0)) < int(need[item]): return false
	return true


func _missing(b: Dictionary, need: Dictionary) -> String:
	var parts := PackedStringArray()
	for item in need:
		if int(b.inbuf.get(item, 0)) < int(need[item]): parts.append(EconomyCatalog.item_name(item).to_lower())
	return ", ".join(parts)


static func _buf_take(buf: Dictionary, item: String, n: int) -> void:
	buf[item] = int(buf.get(item, 0)) - n
	if int(buf[item]) <= 0: buf.erase(item)


# ------------------------------------------------------------------ persistence
func to_dict() -> Dictionary:
	return {"id": id, "founded": founded, "discovered": discovered, "stock": stock.duplicate(true),
		"buildings": buildings.duplicate(true), "colonists": colonists.duplicate(true), "happiness": happiness,
		"needs": needs.duplicate(), "growth": growth, "decline": decline, "next_id": next_id,
		"hall": [hall.x, hall.y, hall.z], "coins_due": coins_due, "clock": clock, "log": journal.duplicate(true),
		"food_owed": _food_owed, "goods_owed": _goods_owed.duplicate(), "eaten": _eaten.duplicate(),
		"short": _short.duplicate(), "hungry": _hungry, "period": _period}


func apply_dict(d: Dictionary) -> void:
	founded = d.founded; discovered = d.discovered
	stock = _ints(d.stock); buildings = []
	for b in d.buildings:
		var r: Dictionary = b.duplicate(true)
		r.inbuf = _ints(r.inbuf); r.outbuf = _ints(r.outbuf); r.produced = int(r.produced)
		if not r.carry.is_empty(): r.carry.load = _ints(r.carry.load); r.carry.phase = int(r.carry.phase)
		buildings.append(r)
	colonists = []
	for c in d.colonists:
		var r: Dictionary = c.duplicate(true); r.seed = int(r.seed); colonists.append(r)
	happiness = float(d.happiness); needs = d.needs.duplicate(); growth = float(d.growth); decline = float(d.decline)
	next_id = int(d.next_id); hall = Vector3(d.hall[0], d.hall[1], d.hall[2]); coins_due = float(d.coins_due)
	clock = float(d.clock); journal = d.log.duplicate(true)
	_food_owed = float(d.food_owed); _goods_owed = _floats(d.goods_owed); _eaten = _floats(d.eaten)
	_short = _floats(d.short); _hungry = float(d.hungry); _period = float(d.period)
	_recount()


static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d: out[String(k)] = int(d[k])
	return out


static func _floats(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d: out[String(k)] = float(d[k])
	return out


## item -> finite number, keys from the catalogue.
static func _item_numbers(v: Variant) -> bool:
	if not v is Dictionary: return false
	for k in v:
		if not EconomyCatalog.ITEMS.has(k) or not _num(v[k], -1e9, 1e9): return false
	return true


## Field-by-field validation of a saved town (a rejected save must never half-load).
static func valid(d: Variant, colony_id: String) -> bool:
	if not d is Dictionary or d.get("id") != colony_id: return false
	for key in ["founded", "discovered"]:
		if not d.get(key) is bool: return false
	if not _inventory(d.get("stock")): return false
	for key in ["happiness", "growth", "decline", "coins_due", "clock", "food_owed", "period"]:
		if not _num(d.get(key), -1.0, 1e9): return false
	if not _num(d.happiness, 0.0, 100.0) or not _num(d.get("next_id"), 1, 1e7): return false
	if not d.get("hall") is Array or d.hall.size() != 3: return false
	for v in d.hall:
		if not _num(v, -13000.0, 13000.0): return false
	if not d.get("needs") is Dictionary or not _item_numbers(d.get("goods_owed")) or not _item_numbers(d.get("eaten")) or not _item_numbers(d.get("short")) or not _num(d.get("hungry"), 0.0, 1e6): return false
	for k in ["food", "variety", "goods", "housing"]:
		if not _num(d.needs.get(k), 0.0, 1.0): return false
	if not d.get("log") is Array or d.log.size() > 64: return false
	if not d.get("buildings") is Array or d.buildings.size() > MAX_BUILDINGS: return false
	if not d.get("colonists") is Array or d.colonists.size() > MAX_COLONISTS: return false
	var ids := {}
	for b in d.buildings:
		if not _valid_building(b) or ids.has(b.id): return false
		ids[b.id] = true
	var cids := {}
	for c in d.colonists:
		if not c is Dictionary or not c.get("id") is String or cids.has(c.id) or not c.get("name") is String or not _num(c.get("seed"), -9.3e18, 9.3e18): return false
		if not c.get("job") is String or not c.get("home") is String or (c.job != "" and not ids.has(c.job)) or (c.home != "" and not ids.has(c.home)): return false
		cids[c.id] = true
	return true


## One saved building record on its own (the per-record half of `valid`).
static func _valid_building(b: Variant) -> bool:
	if not b is Dictionary or not b.get("id") is String or not EconomyCatalog.BUILDINGS.has(b.get("type")): return false
	for key in ["x", "z"]:
		if not _num(b.get(key), -12500.0, 12500.0): return false
	if not _num(b.get("y"), -100.0, 3000.0) or not _num(b.get("yaw"), -10.0, 10.0) or not b.get("built") is bool or not b.get("paused") is bool: return false
	if not _num(b.get("progress"), 0.0, 1.0) or not _num(b.get("cycle"), 0.0, 1.5) or not _num(b.get("produced"), 0, 1e9): return false
	if not _inventory(b.get("inbuf")) or not _inventory(b.get("outbuf")) or not b.get("carry") is Dictionary: return false
	if not b.carry.is_empty():
		if not int(b.carry.get("phase", -1)) in [0, 1] or not _num(b.carry.get("t"), 0.0, 1e6) or not _num(b.carry.get("dur"), 0.0, 1e6) or not _inventory(b.carry.get("load")): return false
	return true


## Mend a saved town record instead of throwing the whole save away: keep every valid field,
## clamp numbers into range, drop only a broken building or colonist, fall back to the start
## value for anything else. Returns {data (a record `valid` accepts, or {} when nothing of it
## is usable), fixes: Array[String] (what was changed, for the load report)}.
static func repair(d: Variant, colony_id: String) -> Dictionary:
	var fixes: Array[String] = []
	if not d is Dictionary: return {"data": {}, "fixes": ["the record is missing"]}
	if d.get("id") != colony_id: return {"data": {}, "fixes": ["the record belongs to %s" % str(d.get("id"))]}
	var out: Dictionary = ColonyTown.new(colony_id).to_dict()
	for key in ["founded", "discovered"]:
		if d.get(key) is bool: out[key] = d[key]
		else: fixes.append(key)
	out.stock = _mend_inventory(d.get("stock"), fixes, "stock")
	for spec in [["happiness", 0.0, 100.0], ["growth", -1.0, 1e9], ["decline", -1.0, 1e9], ["coins_due", -1.0, 1e9],
			["clock", -1.0, 1e9], ["food_owed", -1.0, 1e9], ["period", -1.0, 1e9], ["hungry", 0.0, 1e6], ["next_id", 1.0, 1e7]]:
		var v: Variant = d.get(spec[0])
		if (v is int or v is float) and is_finite(float(v)):
			var c := clampf(float(v), spec[1], spec[2])
			if c != float(v): fixes.append("%s %s -> %s" % [spec[0], str(v), str(c)])
			out[spec[0]] = int(c) if spec[0] == "next_id" else c
		else: fixes.append(String(spec[0]))
	var hall: Variant = d.get("hall")
	if hall is Array and hall.size() == 3 and _num(hall[0], -13000.0, 13000.0) and _num(hall[1], -13000.0, 13000.0) and _num(hall[2], -13000.0, 13000.0):
		out.hall = hall.duplicate()
	else: fixes.append("hall")
	var needs: Variant = d.get("needs")
	for k in ["food", "variety", "goods", "housing"]:
		var v: Variant = needs.get(k) if needs is Dictionary else null
		if (v is int or v is float) and is_finite(float(v)): out.needs[k] = clampf(float(v), 0.0, 1.0)
		else: fixes.append("needs.%s" % k)
	for key in ["goods_owed", "eaten", "short"]:
		var v: Variant = d.get(key)
		var clean := {}
		if v is Dictionary:
			for item in v:
				if EconomyCatalog.ITEMS.has(item) and _num(v[item], -1e9, 1e9): clean[item] = float(v[item])
				else: fixes.append("%s.%s" % [key, str(item)])
		else: fixes.append(key)
		out[key] = clean
	var log: Variant = d.get("log")
	out.log = (log as Array).slice(maxi(0, (log as Array).size() - 40)) if log is Array else []
	var ids := {}
	var kept: Array = []
	if d.get("buildings") is Array:
		for b in d.buildings:
			if kept.size() >= MAX_BUILDINGS: fixes.append("buildings over the limit"); break
			if not _valid_building(b) or ids.has(b.id):
				fixes.append("building %s dropped" % (str(b.get("id")) if b is Dictionary else "?"))
				continue
			ids[b.id] = true
			kept.append(b)
	else: fixes.append("buildings")
	out.buildings = kept
	var people: Array = []
	var cids := {}
	if d.get("colonists") is Array:
		for c in d.colonists:
			if people.size() >= MAX_COLONISTS: break
			if not c is Dictionary or not c.get("id") is String or cids.has(c.id) or not c.get("name") is String or not _num(c.get("seed"), -9.3e18, 9.3e18):
				fixes.append("a colonist dropped"); continue
			var r: Dictionary = c.duplicate(true)
			for key in ["job", "home"]:
				if not r.get(key) is String or (r[key] != "" and not ids.has(r[key])): r[key] = ""
			cids[r.id] = true
			people.append(r)
	else: fixes.append("colonists")
	out.colonists = people
	if not valid(out, colony_id): return {"data": {}, "fixes": fixes + ["unrecoverable"]}
	return {"data": out, "fixes": fixes}


static func _mend_inventory(v: Variant, fixes: Array[String], what: String) -> Dictionary:
	var out := {}
	if not v is Dictionary:
		fixes.append(what)
		return out
	for item in v:
		var n: Variant = v[item]
		if EconomyCatalog.ITEMS.has(item) and (n is int or n is float) and is_finite(float(n)):
			out[String(item)] = clampi(int(floorf(float(n))), 0, 1000000)
		else: fixes.append("%s.%s" % [what, str(item)])
	return out


static func _num(v: Variant, lo: float, hi: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) >= lo and float(v) <= hi


static func _inventory(v: Variant) -> bool:
	if not v is Dictionary: return false
	for item in v:
		if not EconomyCatalog.ITEMS.has(item): return false
		var n: Variant = v[item]
		if not (n is int or n is float) or float(n) != floorf(float(n)) or float(n) < 0 or float(n) > 1e6: return false
	return true
