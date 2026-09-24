extends Node
## Tool: find open, flat ground for a camp near a point (static colliders counted with a physics
## shape query once the chunks are built). Prints the best candidates.
##   godot --headless --path . -- --test=camp_site_probe --at=x,z --radius=160
var game: Game
var frames := 0
var at := Vector2.ZERO
var radius := 160.0

func _ready() -> void:
	game = Game.current
	var a := game.cli.get_string("at", "167,125").split(",")
	at = Vector2(float(a[0]), float(a[1]))
	radius = game.cli.get_float("radius", 160.0)
	game.bike.place(Vector3(at.x, game.world.terrain.height_at(at.x, at.y) + 30.0, at.y), Vector3(0, 0, -1))
	game.world.set_focus(game.bike)
	game.world.streamer.load_all_pending()

func _physics_process(_d: float) -> void:
	frames += 1
	game.bike.global_position = Vector3(at.x, game.world.terrain.height_at(at.x, at.y) + 30.0, at.y)
	if frames < 30: return
	var t := game.world.terrain
	var space := get_viewport().world_3d.direct_space_state
	var sh := SphereShape3D.new(); sh.radius = 13.0
	var q := PhysicsShapeQueryParameters3D.new(); q.shape = sh; q.collision_mask = 1
	var found: Array = []
	var step := 8.0
	var n := int(radius / step)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var x := at.x + i * step; var z := at.y + j * step
			if Vector2(i, j).length() * step > radius: continue
			var h := t.height_at(x, z)
			if h < 1.5 or t.road_dist_at(x, z) < 18.0: continue
			var rough := 0.0
			for o in [Vector2(10, 0), Vector2(-10, 0), Vector2(0, 10), Vector2(0, -10), Vector2(7, 7), Vector2(-7, -7)]:
				rough += absf(t.height_at(x + o.x, z + o.y) - h)
			if rough > 5.0: continue
			q.transform = Transform3D(Basis(), Vector3(x, h + 15.0, z))
			var hits := space.intersect_shape(q, 32)
			var solid := 0
			for hh in hits:
				var c: Object = hh.collider
				if c is StaticBody3D and not (c as Node).name.begins_with("Terrain"): solid += 1
			found.append([solid * 3.0 + rough, x, z, h, solid, rough])
	found.sort_custom(func(a, b): return a[0] < b[0])
	for k in range(mini(12, found.size())):
		var f: Array = found[k]
		print("SITE %.0f %.0f h=%.1f solids=%d rough=%.1f" % [f[1], f[2], f[3], f[4], f[5]])
	get_tree().quit()
