class_name Townsperson
extends RefCounted
## One ambient townsperson of an outer town or hamlet: who (seed, occupation, look), where he
## lives and works (spot indices in his TownPopulation) and his day (the routine), plus the few
## fields of what he is doing right now. Cheap on purpose: a town holds hundreds, and a town the
## courier is nowhere near never touches them (TownFolk only ticks the active towns).
##
## The routine is a list of [minute of day, spot index, activity]; activity is "home" (indoors:
## no body), "work", "rest" (a seat, a bench, a cafe chair, a chat on the plaza) or "shop"
## (browsing a stall). Everything here is decided by TownPopulation from the plan, so it is the
## same every run; only the live state below changes.

enum State { INDOORS, WALKING, AT_SPOT }

var id := ""
var index := 0
var seed := 0
var sex := ""
var occupation := ""
var home := -1                  # spot index (a door)
var work := -1                  # spot index, -1 = none (retired, idle)
var routine: Array = []         # [[minute, spot, activity], ...] sorted by minute
var speed := 1.3                # walking, m/s
var lane := 0.0                 # sideways offset on the street (spreads a crowd)
var _look: Dictionary = {}

## Live state (only meaningful while the town is active).
var state := State.INDOORS
var entry := -1                 # routine index in force
var spot := -1                  # the spot he is at / walking to
var target := -1                # the spot a route has been asked for
var activity := "home"
var position := Vector3.ZERO
var forward := Vector3.FORWARD
var path := PackedVector3Array()
var cum := PackedFloat32Array() # cumulative length along `path`
var depart := 0.0               # game minute the walk started
var waiting := false            # a leg is due but its route is not computed yet
var hold := 0.0                 # real seconds the walk was held (the courier in the way)
var body: Node3D = null         # the TownBody drawing him, if any
var view_distance := INF


func look(style: StringName) -> Dictionary:
	if _look.is_empty():
		_look = CharacterLook.from_seed(seed, style, occupation, sex)
	return _look


func visible() -> bool:
	return state != State.INDOORS


## The routine entry in force at `minute` (minute of day).
func entry_at(minute: float) -> int:
	if routine.is_empty(): return -1
	var e := routine.size() - 1
	for i in routine.size():
		if float(routine[i][0]) <= minute: e = i
	return e


func path_length() -> float:
	return cum[cum.size() - 1] if cum.size() > 0 else 0.0


## Where he is `walked` metres along his path, and which way he faces.
func sample(walked: float) -> Array:
	var n := path.size()
	if n == 0: return [position, forward]
	if n == 1 or walked <= 0.0:
		return [path[0], _dir(0)]
	if walked >= cum[n - 1]:
		return [path[n - 1], _dir(n - 2)]
	var lo := 0; var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= walked: lo = mid
		else: hi = mid
	var seg := maxf(cum[hi] - cum[lo], 0.0001)
	return [path[lo].lerp(path[hi], (walked - cum[lo]) / seg), _dir(lo)]


func _dir(i: int) -> Vector3:
	if path.size() < 2: return forward
	i = clampi(i, 0, path.size() - 2)
	var d := path[i + 1] - path[i]; d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-6 else forward


func set_path(p: PackedVector3Array) -> void:
	path = p
	cum = PackedFloat32Array(); cum.resize(p.size())
	var total := 0.0
	for i in p.size():
		if i > 0: total += Vector2(p[i].x - p[i - 1].x, p[i].z - p[i - 1].z).length()
		cum[i] = total
