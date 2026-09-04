class_name GameplayManager
extends Node3D
## Owns the gameplay systems (delivery loop, weapons, later quests / interaction / combat).
## Systems below it talk through the WorldDatabase, the EntityManager and the EventBus —
## never to the UI or to each other's internals.

var delivery: DeliverySystem
var gun: GunSystem
var autopilot: Autopilot


func setup(world: WorldManager, entities: EntityManager, bike: Bike, player: Player, cam: ChaseCamera, jobs: Array[JobDefinition]) -> void:
	delivery = DeliverySystem.new(); delivery.name = "DeliverySystem"; add_child(delivery)
	delivery.setup(world.database, bike, jobs)
	gun = GunSystem.new(); gun.name = "GunSystem"; add_child(gun)
	gun.setup(world, entities, player, cam)


func enable_autopilot(bike: Bike, terrain: Terrain, controls: Controls.Scripted) -> Autopilot:
	autopilot = Autopilot.new(); autopilot.name = "Autopilot"; add_child(autopilot)
	autopilot.setup(bike, delivery, terrain, controls)
	return autopilot


static func load_jobs() -> Array[JobDefinition]:
	var out: Array[JobDefinition] = []
	var dir := DirAccess.open("res://data/jobs")
	if dir == null: return out
	var names: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".tres") or f.ends_with(".tres.remap"): names.append(f.trim_suffix(".remap"))
	names.sort()
	for n in names:
		var r := load("res://data/jobs/" + n)
		if r is JobDefinition: out.append(r)
	return out
