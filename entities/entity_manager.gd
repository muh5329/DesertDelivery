class_name EntityManager
extends Node3D
## Registry of every simulated thing in the world (player, vehicles, NPCs, animals, targets...)
## by stable id, and the owner of their simulation tier. Entities are plain nodes; they opt in to
## tiering by implementing `set_simulation_tier(tier: int)`. Distant entities are ticked less
## (or not at all) — this is where "2000 NPCs" stays cheap.
##
##   register(node, id, kind)   /  unregister(id)  /  get_entity(id)  /  entities_of(kind)
##   focus                      the node distances are measured from (the player's body or bike)
##   tier_of(id)                SimulationTier

enum SimulationTier { FULL, REDUCED, ABSTRACT, DORMANT }

const TIER_NAMES := ["FULL", "REDUCED", "ABSTRACT", "DORMANT"]

var focus: Node3D
var config: WorldConfig
var _entities: Dictionary = {}      # id -> {node, kind, tier}
var _tick := 0.0
var tier_interval := 0.5           # seconds between tier passes


func setup(p_config: WorldConfig) -> void:
	config = p_config


func register(node: Node3D, id: StringName, kind: StringName) -> void:
	if _entities.has(id):
		push_warning("EntityManager: duplicate id %s" % id)
	_entities[id] = {"node": node, "kind": kind, "tier": SimulationTier.FULL}
	node.set_meta("entity_id", id)
	if node.get_parent() == null:
		add_child(node)
	node.tree_exiting.connect(func(): if _entities.has(id) and _entities[id].node == node: _entities.erase(id))
	Events.entity_registered.emit(id)


func unregister(id: StringName) -> void:
	if _entities.erase(id):
		Events.entity_unregistered.emit(id)


func get_entity(id: StringName) -> Node3D:
	return _entities[id].node if _entities.has(id) else null


func has_entity(id: StringName) -> bool:
	return _entities.has(id)


func entities_of(kind: StringName) -> Array:
	var out := []
	for e in _entities.values():
		if e.kind == kind: out.append(e.node)
	return out


func ids() -> Array:
	return _entities.keys()


func tier_of(id: StringName) -> int:
	return _entities[id].tier if _entities.has(id) else SimulationTier.DORMANT


func count() -> int:
	return _entities.size()


func tier_counts() -> Array[int]:
	var c: Array[int] = [0, 0, 0, 0]
	for e in _entities.values(): c[e.tier] += 1
	return c


func _process(delta: float) -> void:
	_tick += delta
	if _tick < tier_interval or focus == null: return
	_tick = 0.0
	var fp := focus.global_position
	for id in _entities.keys():
		var e: Dictionary = _entities[id]
		var node: Node3D = e.node
		if not is_instance_valid(node): _entities.erase(id); continue
		var d := node.global_position.distance_to(fp)
		var tier := SimulationTier.FULL
		if node.has_meta("always_full"): tier = SimulationTier.FULL
		elif d > config.abstract_tier_radius: tier = SimulationTier.DORMANT
		elif d > config.reduced_tier_radius: tier = SimulationTier.ABSTRACT
		elif d > config.full_tier_radius: tier = SimulationTier.REDUCED
		if tier != e.tier:
			e.tier = tier
			if node.has_method("set_simulation_tier"):
				node.set_simulation_tier(tier)
			Events.simulation_tier_changed.emit(id, tier)
