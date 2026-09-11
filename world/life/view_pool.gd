class_name ViewPool
extends RefCounted
## Keeps exactly the near records instantiated, and frees the rest.
##
## The rule is the same wherever it is applied: a record has an id and a position; when the focus
## comes within `spawn radius` a view is built and registered with the EntityManager under that
## id, and when the focus goes further than `radius + keep_margin` the view is freed. The margin
## is the hysteresis that stops a resident flickering as you idle on the boundary.
##
## IslandLife and IslandWildlife each had their own copy of that loop with their own radii —
## 105/125, 95/115 and 210/230 — none of them findable from the EntityManager, whose own tier
## radii were documented as owning exactly this. Now the radii sit in WorldConfig with the tier
## radii, and the division of labour is stated once: the pool decides whether a view *exists*,
## the EntityManager decides how much a view that exists is *simulated*.
##
## Interface:
##   ViewPool.new(entities, kind, factory)   factory: (record) -> Node3D, construction only
##   configure                               optional (record, node), run once the node is in
##                                           the tree — for anything that needs children
##   spawn_radius / keep_margin              distance in metres
##   radius_for                              optional (record) -> float, for mixed populations
##   awake_for                               optional (record) -> bool: false never spawns
##   sync(records, focus)                    call once a frame
##   views                                   id -> Node3D, for callers that drive their views
##   view(id) / has(id) / count() / clear()

var spawn_radius := 105.0
var keep_margin := 20.0
var radius_for: Callable
var awake_for: Callable
var configure: Callable
var views: Dictionary = {}

var _entities: EntityManager
var _kind: StringName
var _factory: Callable


func _init(entities: EntityManager, kind: StringName, factory: Callable) -> void:
	_entities = entities
	_kind = kind
	_factory = factory


func has(id) -> bool:
	return views.has(id)


func view(id) -> Node3D:
	return views.get(id)


func count() -> int:
	return views.size()


## Bring the near records into the world and let the far ones go.
func sync(records: Array, focus: Vector3) -> void:
	for r in records:
		var id: Variant = r.id
		var radius: float = float(radius_for.call(r)) if radius_for.is_valid() else spawn_radius
		var awake: bool = bool(awake_for.call(r)) if awake_for.is_valid() else true
		var distance: float = focus.distance_to(r.position)
		if awake and distance < radius:
			if not views.has(id):
				var node: Node3D = _factory.call(r)
				if node == null: continue
				# Register first: that is what puts the node in the tree, and a view that builds
				# children in its setup needs to be there before it does.
				_entities.register(node, StringName(id), _kind)
				views[id] = node
				if configure.is_valid(): configure.call(r, node)
		elif views.has(id) and (not awake or distance > radius + keep_margin):
			_free(id)


func clear() -> void:
	for id in views.keys(): _free(id)


func _free(id) -> void:
	var node: Node3D = views[id]
	_entities.unregister(StringName(id))
	if is_instance_valid(node): node.queue_free()
	views.erase(id)
