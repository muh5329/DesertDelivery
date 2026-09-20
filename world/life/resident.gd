class_name Resident
extends RefCounted
## One islander: who he is, where he is, and what he is doing right now.
##
## This used to be an anonymous 25-key Dictionary built in IslandLife.setup and read by five
## other modules, each of which had to guess which keys were guaranteed. Worse, the field list
## existed three times — creation, save_state and load_state — and the three had drifted, so
## `activity`, `blocked_time` and `station_validated` were persisted by nobody and a new field
## was a silent data loss waiting to happen. Now the fields, the schedule and the persistence
## are one thing.
##
## Interface:
##   Resident.from_source(dict)      build one from data/life/residents.json
##   schedule_for(day)               the day resolved into continuous bands (weekly overrides in)
##   task_at(day, minute)            the schedule entry in force at that moment
##   station(place) / set_station()  the roadside point for "home" / "work" / "cafe" / "market"
##   to_dict() / apply_dict(d)       persistence, defined once beside the fields
##   lifetime totals                 distance, completed_tasks, deliveries_completed — the fields
##                                   a time skip must carry across, by construction

## Identity and routine, straight from the data file. Never changes at run time.
var id: String = ""
var name: String = ""
var occupation: String = ""
var district: String = ""
var home: String = ""
var location: String = ""
var transport: String = "walk"
var route_locations: Array = []
var palette: Array = []
var car_color: String = "#ffffff"
var scale: float = 1.0
var slot: int = 0
var daily: Array = []
var weekly: Array = []

## Stations: "home" / "work" / "cafe" / "market" -> a resolved roadside point.
var places: Dictionary = {}

## Where he is and what he is doing.
enum State { RESTING, TRAVELLING, WORKING, YIELDING, UNLOADING, ROUTE_BLOCKED }
var state: int = State.RESTING
var state_elapsed := 0.0
var route_retry := 0.0

var position := Vector3.ZERO
var forward := Vector3.FORWARD
var surface_normal := Vector3.UP
var route := PackedVector3Array()
var cursor := 0
var destination := Vector3.ZERO
var task_key := ""
var task := ""
var place := "home"
var activity := "sleep"
var status := "At home"
var moving := false
var driving := false
var speed := 0.0
var wait := 0.0
var circuit := 0
var work_progress := 0.0
var blocked_time := 0.0
var station_validated := false
var sim_elapsed := 0.0

## Lifetime totals. Skipping time, loading a save or re-assigning a task must never reset these.
var distance := 0.0
var completed_tasks := 0
var deliveries_completed := 0

## What goes in the save file. One list, used by both directions — there is no second list to
## fall out of step with it.
const SAVED := ["state", "state_elapsed", "route_retry", "destination", "position", "forward", "route", "cursor", "task_key", "task", "place", "activity",
	"status", "moving", "driving", "speed", "wait", "circuit", "work_progress", "blocked_time",
	"station_validated", "distance", "completed_tasks", "deliveries_completed"]
## The subset that is a running total rather than a state.
const LIFETIME := ["distance", "completed_tasks", "deliveries_completed"]


static func from_source(src: Dictionary) -> Resident:
	var r := Resident.new()
	for key in ["id", "name", "occupation", "district", "home", "location", "transport", "car_color"]:
		if src.has(key): r.set(key, String(src[key]))
	if src.has("scale"): r.scale = float(src.scale)
	if src.has("slot"): r.slot = int(src.slot)
	for key in ["route_locations", "palette", "daily", "weekly"]:
		if src.has(key): r.set(key, (src[key] as Array).duplicate(true))
	return r


# ---------------------------------------------------------------- stations
func station(key: String) -> Vector3:
	return places.get(key, position)


func set_station(key: String, p: Vector3) -> void:
	places[key] = p


func has_station(key: String) -> bool:
	return places.has(key)


# ---------------------------------------------------------------- routine
## The schedule entry in force on `day` at `minute`: the daily routine, with any weekly override
## for that day laid over it.
func task_at(day: int, minute: float) -> Dictionary:
	if daily.is_empty(): return {"at":0,"task":"At home","place":"home","activity":"sleep"}
	minute = fposmod(minute, 1440.0)
	var result: Dictionary = daily[-1]
	for entry in daily:
		if float(entry.at) <= minute: result = entry
	for entry in weekly:
		if int(entry.day) == posmod(day, 7) and minute >= float(entry.at) and minute < float(entry.until):
			result = entry
	return result


## One day resolved into continuous bands, with the override boundaries folded in and identical
## neighbours merged — what the week chart and the itinerary both draw.
func schedule_for(day: int) -> Array[Dictionary]:
	var boundaries: Array[int] = [0, 1440]
	for entry in daily:
		if int(entry.at) not in boundaries: boundaries.append(int(entry.at))
	for entry in weekly:
		if int(entry.day) != posmod(day, 7): continue
		for minute in [int(entry.at), int(entry.until)]:
			if minute not in boundaries: boundaries.append(minute)
	boundaries.sort()
	var result: Array[Dictionary] = []
	for i in range(boundaries.size() - 1):
		var entry := task_at(day, boundaries[i]).duplicate()
		entry.at = boundaries[i]
		entry.until = boundaries[i + 1]
		if not result.is_empty() and result[-1].task == entry.task and result[-1].place == entry.place \
				and result[-1].activity == entry.activity:
			result[-1].until = entry.until
		else:
			result.append(entry)
	return result


## A detached copy, fields and all — the test suites build probe residents this way, and a
## reflection copy cannot fall behind the field list the way a hand-written one does.
func clone() -> Resident:
	var out := Resident.new()
	for p in get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var v: Variant = get(p.name)
		if v is Dictionary or v is Array: out.set(p.name, v.duplicate(true))
		elif v is PackedVector3Array: out.set(p.name, PackedVector3Array(v))
		else: out.set(p.name, v)
	return out


func transition(next: int) -> void:
	if state == next: return
	state = next
	state_elapsed = 0.0


# ---------------------------------------------------------------- persistence
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for key in SAVED:
		var v: Variant = get(key)
		out[key] = Array(v) if v is PackedVector3Array else v
	return out


func apply_dict(d: Dictionary) -> void:
	for key in SAVED:
		if not d.has(key): continue
		if key == "route": route = PackedVector3Array(d.route)
		else: set(key, d[key])
	if not d.has("destination"):
		destination = route[-1] if not route.is_empty() else station(place)
	cursor = clampi(cursor, 0, route.size())
	state = clampi(state, State.RESTING, State.ROUTE_BLOCKED)
	if moving and cursor >= route.size():
		moving = false
		transition(State.ROUTE_BLOCKED)
	sim_elapsed = 0.0


## Everything a resident has *accumulated*, so a time skip can hand it back without a caller
## having to remember the list.
func lifetime_totals() -> Dictionary:
	var out: Dictionary = {}
	for key in LIFETIME: out[key] = get(key)
	return out


func restore_lifetime(totals: Dictionary) -> void:
	for key in LIFETIME:
		if totals.has(key): set(key, totals[key])
