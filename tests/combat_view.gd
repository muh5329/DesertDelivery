extends Node
## Forward+ renders of the fighting (in the booted game, streamed like play):
##   aim_ots     the real over-the-shoulder aiming view with the HUD (crosshair, clip, health)
##   fire        the same, a frame after a shot: muzzle flash, smoke, tracer
##   camp_fight  the badlands bandit camp in a fight: the courier aiming, bandits in cover
##   cove        the pirate cove on the south-west shore
##   lineup      bandits and pirates side by side (outfits and guns; the studio lineup in
##               garand_view.gd frames them better)
##   ambush      a bandit roadblock on an outer highway
##   riding      the courier on the bike with the Garand slung across his back
## xvfb-run -a godot --path . --rendering-driver vulkan -- --facet --test=combat_view --out=DIR [--only=a,b]

var game: Game
var out := "/tmp/combat_view"
var shots: Array[String] = ["aim_ots", "fire", "camp_fight", "cove", "ambush", "riding"]
var idx := -1
var sc: Controls.Scripted
var cam: Camera3D
var t := 0.0
var frames := 0
var phase := 0
var focus_camp := &""
var aim_target := Vector3.ZERO
var shots0 := -1
var since_shot := 0


func _ready() -> void:
	game = Game.current
	out = game.cli.get_string("out", out)
	var only := game.cli.get_string("only", "")
	if only != "":
		var keep: Array[String] = []
		for s in only.split(","): keep.append(s)
		shots = keep
	DirAccess.make_dir_recursive_absolute(out)
	sc = game.use_scripted_controls()
	game.encounters.ambush_enabled = false
	game.vitals.health.invulnerable = 1e9
	Engine.max_physics_steps_per_frame = 24
	cam = Camera3D.new(); cam.fov = 50.0; cam.far = 20000.0; cam.near = 0.05
	add_child(cam)
	game.rider.request_dismount()
	_next_shot()


func _hud(on: bool) -> void:
	game.hud.visible = on
	var ui := game.get_node_or_null("UI")
	if ui:
		for c in ui.get_children():
			if c is CanvasLayer and c != game.hud: c.visible = false
			elif c is Control: c.visible = false


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, game.world.terrain.height_at(x, z) + 0.05, z)


func _aim_at(p: Vector3) -> void:
	var d: Vector3 = p - game.cam.global_position
	game.cam.set_look(atan2(-d.x, -d.z), -atan2(d.y, Vector2(d.x, d.z).length()))


## A spot `dist` from `cp` with a clear view of it and room for the camera behind.
func _vantage(cp: Vector3, dist: float, first_dir: Vector3) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var a0 := atan2(first_dir.z, first_dir.x)
	for i in range(24):
		var a := a0 + float(i >> 1) * 0.3 * (1.0 if i % 2 == 0 else -1.0)
		var d := Vector3(cos(a), 0, sin(a))
		var p := _ground(cp.x + d.x * dist, cp.z + d.z * dist)
		if absf(p.y - cp.y) > 4.0: continue
		var eye := p + Vector3(0, 1.7, 0)
		var q := PhysicsRayQueryParameters3D.create(eye, cp + Vector3(0, 1.2, 0), 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.position.distance_to(cp) > 9.0: continue
		var right := (-d).cross(Vector3.UP).normalized()
		for c in [eye + d * 4.0 + Vector3(0, 1.0, 0), eye + d * 3.6 + right * 1.3 + Vector3(0, 0.7, 0), eye + d * 1.7 + right * 0.6]:
			var q2 := PhysicsRayQueryParameters3D.create(eye, c, 1)
			if not space.intersect_ray(q2).is_empty(): p = Vector3.INF; break
		if p == Vector3.INF: continue
		return p
	return _ground(cp.x + first_dir.x * dist, cp.z + first_dir.z * dist)


func _place_player(p: Vector3, facing: Vector3) -> void:
	game.player.place(p, facing)
	game.world.set_focus(game.player)
	game.entities.focus = game.player
	game.world.streamer.load_all_pending()
	game.cam.snap_to_target()


func _next_shot() -> void:
	idx += 1
	t = 0.0
	frames = 0
	phase = 0
	sc.intent.aim = false
	if idx >= shots.size():
		get_tree().quit()
		return
	var s := shots[idx]
	print("[view] setting up ", s)
	var dir := game.encounters
	game.hud._title.visible = false
	game.hud._prompt_bg.visible = false
	match s:
		"aim_ots", "fire":
			_hud(true)
			game.hud.set_process(true)
			game.cam.current = true
			var lk := game.world.database.location_pos(&"dunes_lookout")
			var camp: Dictionary = dir.camp(&"camp.core.badlands")
			var cp: Vector3 = camp.pos
			var from := cp + (lk - cp).normalized() * 40.0
			_place_player(_ground(from.x, from.z), (cp - from).normalized())
			dir.spawn_camp(&"camp.core.badlands")
			focus_camp = &"camp.core.badlands"
			aim_target = cp + Vector3(0, 1.2, 0)
			phase = -1
			sc.intent.aim = true
		"camp_fight":
			_hud(false)
			var lk := game.world.database.location_pos(&"dunes_lookout")
			var camp: Dictionary = dir.camp(&"camp.core.badlands")
			var cp: Vector3 = camp.pos
			var from := cp + (lk - cp).normalized() * 30.0
			_place_player(_ground(from.x, from.z), (cp - from).normalized())
			dir.spawn_camp(&"camp.core.badlands")
			focus_camp = &"camp.core.badlands"
			aim_target = cp + Vector3(0, 1.0, 0)
			phase = -1
			sc.intent.aim = true
		"cove":
			_hud(false)
			var camp: Dictionary = dir.camp(&"camp.core.cove")
			var cp: Vector3 = camp.pos
			var f: Vector3 = camp.facing
			var from := cp - f * 70.0
			_place_player(_ground(from.x, from.z), f)
			dir.spawn_camp(&"camp.core.cove")
			focus_camp = &"camp.core.cove"
			var eye := cp - f * 13.0 + f.cross(Vector3.UP) * 6.0
			cam.global_position = _ground(eye.x, eye.z) + Vector3(0, 3.2, 0)
			cam.look_at(cp + Vector3(0, 0.8, 0), Vector3.UP)
			cam.current = true
		"lineup":
			_hud(false)
			var s0: Vector3 = game.world.database.location_pos(&"salinas") + Vector3(40, 0, -30)
			_place_player(_ground(s0.x, s0.z + 90.0), Vector3(0, 0, 1))
			dir.add_camp(&"camp.view.bandits", &"bandit", _ground(s0.x - 3.2, s0.z), Vector3(0, 0, 1), 4, &"squad")
			dir.add_camp(&"camp.view.pirates", &"pirate", _ground(s0.x + 9.2, s0.z), Vector3(0, 0, 1), 4, &"squad")
			dir.spawn_camp(&"camp.view.bandits")
			dir.spawn_camp(&"camp.view.pirates")
			cam.global_position = _ground(s0.x + 3.0, s0.z + 12.5) + Vector3(0, 1.7, 0)
			cam.look_at(_ground(s0.x + 3.0, s0.z) + Vector3(0, 1.0, 0), Vector3.UP)
			cam.fov = 56.0
			cam.current = true
		"riding":
			_hud(false)
			var b: Bike = game.bike
			var p := b.global_position
			game.player.global_position = p + b.global_transform.basis.x * 1.2
			game.rider.request_mount()
			var side := b.global_transform.basis.x
			var back := b.global_transform.basis.z
			cam.global_position = p + side * 2.6 + back * 1.6 + Vector3(0, 1.5, 0)
			cam.look_at(p + Vector3(0, 1.1, 0), Vector3.UP)
			cam.fov = 45.0
			cam.current = true
		"ambush":
			_hud(false)
			var outer: OuterWorld = game.world.outer
			var road: Dictionary = {}
			var k := -1
			for e: Dictionary in outer.roads.roads:
				if e.cls != "highway": continue
				var br: PackedByteArray = e.bridge
				for kk in range(300, (e.pts as PackedVector3Array).size() - 120, 40):
					var clear := true
					for j in range(kk - 70, kk + 70):
						if j < br.size() and br[j] == 1: clear = false; break
					if clear: k = kk; break
				if k >= 0: road = e; break
			var pts: PackedVector3Array = road.pts
			var fwd := pts[k + 1] - pts[k - 1]; fwd.y = 0.0
			game.rider.request_mount()
			_place_player(pts[k] + Vector3.UP * 0.3, fwd.normalized())
			game.bike.place(pts[k] + Vector3.UP * 0.4, fwd.normalized())
			var id := dir.spawn_ambush_ahead(true)
			focus_camp = id
			if id != &"":
				dir.spawn_camp(id)
				var cp: Vector3 = dir.camp(id).pos
				var back := (pts[k] - cp).normalized()
				var eye := cp + back * 16.0 + back.cross(Vector3.UP) * 5.0
				cam.global_position = _ground(eye.x, eye.z) + Vector3(0, 2.6, 0)
				cam.look_at(cp + Vector3(0, 0.9, 0), Vector3.UP)
				cam.current = true


func _physics_process(delta: float) -> void:
	if idx < 0 or idx >= shots.size(): return
	t += delta
	var s := shots[idx]
	if phase == -1:
		if t < 0.4: return
		var cp: Vector3 = game.encounters.camp(focus_camp).pos
		var lk := game.world.database.location_pos(&"dunes_lookout")
		var dist := 38.0 if s != "camp_fight" else 28.0
		var p := _vantage(cp, dist, (lk - cp).normalized())
		_place_player(p, (cp - p).normalized())
		phase = 0
		t = 0.0
		frames = 0
		return
	match s:
		"aim_ots", "fire":
			_aim_at(aim_target)
			if s == "fire" and t > 2.0 and phase == 0:
				# slow time first, so the flash, the smoke and the tracer are still there when drawn
				phase = 1
				shots0 = game.gun.shots_fired
				Engine.time_scale = 0.01
				sc.press("fire")
		"camp_fight":
			if t > 0.5 and phase == 0:
				phase = 1
				for e in game.encounters.enemies_of(focus_camp): e.alert_to(game.player.global_position + Vector3(0, 1.2, 0))
			var men := game.encounters.enemies_of(focus_camp)
			if not men.is_empty():
				# aim at the nearest standing bandit
				var best: Enemy = null
				for e in men:
					if e.is_dead() or e.role == &"lookout": continue
					if best == null or e.global_position.distance_to(game.player.global_position) < best.global_position.distance_to(game.player.global_position): best = e
				if best: aim_target = best.global_position + Vector3(0, 1.1, 0)
			_aim_at(aim_target)
			if t > 5.5 and phase == 1:
				phase = 2
				shots0 = game.gun.shots_fired
				Engine.time_scale = 0.01
				sc.press("fire")
			# a chase-style view from behind and above the courier's right shoulder
			var p := game.player.global_position
			var to := (aim_target - p); to.y = 0.0; to = to.normalized()
			var right := to.cross(Vector3.UP)
			cam.global_position = p - to * 3.4 + right * 1.4 + Vector3(0, 1.9, 0)
			cam.look_at(p + to * 14.0 + Vector3(0, 1.0, 0), Vector3.UP)
			cam.fov = 58.0
			cam.current = true


func _process(_delta: float) -> void:
	if idx < 0 or idx >= shots.size(): return
	frames += 1
	if shots0 >= 0 and game.gun.shots_fired > shots0: since_shot += 1
	var s := shots[idx]
	var ready := false
	match s:
		"aim_ots": ready = phase == 0 and t > 2.5 and frames > 20
		"fire": ready = phase == 1 and since_shot >= 2
		"camp_fight": ready = phase == 2 and since_shot >= 2
		"cove", "ambush", "riding": ready = t > 2.5 and frames > 20
		"lineup":
			# frame whoever is standing there, from in front
			var men: Array = game.encounters.enemies_of(&"camp.view.bandits") + game.encounters.enemies_of(&"camp.view.pirates")
			if not men.is_empty() and t > 1.0:
				var c := Vector3.ZERO
				for e in men: c += e.global_position
				c /= men.size()
				cam.global_position = c + Vector3(0, 1.5, 9.5)
				cam.look_at(c + Vector3(0, 0.95, 0), Vector3.UP)
				cam.fov = 62.0
			ready = t > 2.5 and frames > 20
	if ready:
		var img := get_tree().root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out, s])
		print("[view] saved %s/%s.png (t=%.1f, frames=%d)" % [out, s, t, frames])
		if s == "camp_fight":
			for e in game.encounters.enemies_of(focus_camp):
				print("[view]   %s state=%d sub=%d shots=%d at %s" % [e.enemy_id, e.state, e.sub, e.shots, e.global_position])
		cam.current = false
		game.cam.current = true
		Engine.time_scale = 1.0
		shots0 = -1
		since_shot = 0
		_next_shot()
