extends SceneTree
## Studio renders of the M1 Garand and the courier's rifle poses (no world boot).
##   xvfb-run -a godot --path . --rendering-driver vulkan -s tests/garand_view.gd -- --out=DIR [--only=a,b]
## Shots: rifle_right, rifle_left, rifle_top, rifle_receiver, rifle_muzzle, pose_side, pose_front,
## pose_ots (over the shoulder), pose_hip, slung_back, hands_rest.

var out := "/tmp/garand"
var only: PackedStringArray = []
var frame := 0
var idx := 0
var shots: Array = []
var cam: Camera3D
var rifle: GarandModel
var person: RiderModel
var crew: Array = []            # bandits and pirates for the outfit lineup
var stage: Node3D


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--only="): only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	stage = Node3D.new()
	get_root().add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.80, 0.79, 0.76)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; stage.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 150, 0); sun.light_energy = 1.1; sun.shadow_enabled = true
	stage.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-20, -40, 0); fill.light_energy = 0.35
	stage.add_child(fill)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(30, 30); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.72, 0.66, 0.55); ground.material_override = gm; stage.add_child(ground)
	cam = Camera3D.new(); cam.fov = 30; stage.add_child(cam); cam.current = true
	# the rifle alone on a stand, muzzle toward -Z, 1.2 m up
	rifle = GarandModel.new()
	rifle.position = Vector3(3.0, 1.2, 0.55)
	stage.add_child(rifle)
	rifle.set_loaded(8)
	# the courier holding one
	person = RiderModel.new()
	stage.add_child(person)
	var rc := Vector3(3.0, 1.2, 0.0)
	var pc := Vector3(0, 1.35, -0.2)
	shots = [
		["rifle_right", rc + Vector3(1.9, 0.12, 0.0), rc, 38.0, "none"],
		["rifle_left", rc + Vector3(-1.9, 0.18, -0.1), rc, 38.0, "none"],
		["rifle_top", rc + Vector3(0.9, 1.0, 0.6), rc + Vector3(0, 0, 0.1), 38.0, "none"],
		["rifle_receiver", rc + Vector3(0.45, 0.18, 0.35), rc + Vector3(0, 0, 0.18), 30.0, "none"],
		["rifle_muzzle", rc + Vector3(0.35, 0.12, -0.75), rc + Vector3(0, -0.01, -0.52), 30.0, "none"],
		["pose_side", pc + Vector3(2.6, 0.05, -0.3), pc + Vector3(0, -0.05, -0.3), 34.0, "ads"],
		["pose_front", pc + Vector3(-1.7, 0.2, -2.4), pc + Vector3(0, -0.1, -0.2), 34.0, "ads"],
		["pose_ots", pc + Vector3(0.55, 0.32, 1.75), pc + Vector3(0.1, 0.1, -3.0), 55.0, "ads"],
		["pose_hip", pc + Vector3(2.2, 0.0, -1.2), pc + Vector3(0, -0.3, -0.2), 38.0, "hip"],
		["slung_back", pc + Vector3(1.2, 0.2, 2.6), pc + Vector3(0, -0.3, 0), 38.0, "slung"],
		["hands_rest", pc + Vector3(0.9, -0.3, -1.2), pc + Vector3(0.2, -0.45, 0), 30.0, "rest"],
		["pose_reload", pc + Vector3(1.9, 0.25, -1.3), pc + Vector3(0, -0.25, -0.3), 36.0, "reload"],
	]
	shots.append(["enemies", Vector3(0.0, 1.35, 16.2), Vector3(0.0, 1.0, 10.0), 42.0, "enemies"])
	shots.append(["enemies_close", Vector3(-1.2, 1.55, 12.6), Vector3(-1.9, 1.35, 10.0), 34.0, "enemies"])
	# a turntable: the rifle turns in 45 degree steps in front of a fixed camera
	for i in range(8):
		shots.append(["turntable_%d" % i, rc + Vector3(0.0, 0.34, 2.0), rc + Vector3(0, 0, 0.0), 24.0, "none", i * 45.0])
	if not only.is_empty():
		shots = shots.filter(func(s): return s[0] in only)


func _pose(kind: String) -> void:
	for i in range(30):
		match kind:
			"ads":
				person.gun_ads = 1.0
				person.animate("idle", 0.0, 0.05, true, 0.0, 0.0)
			"hip":
				person.gun_ads = 0.0
				person.left_grip_weight = 0.0
				person.animate("idle", 0.0, 0.05, true, 0.0, 0.0)
			"reload":
				person.gun_ads = 0.0
				person.left_grip_override = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(0.0, 0.11, -0.37))
				person.left_grip_weight = 1.0
				person.animate("idle", 0.0, 0.05, true, 0.0, 0.0)
			_:
				person.animate("idle", 0.0, 0.05, false, 0.0, 0.0)
	person.sync_resident_pose()


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var kit := [[&"bandit", &"lever"], [&"bandit", &"revolver"], [&"bandit", &"lever"], [&"pirate", &"carbine"], [&"pirate", &"revolver"], [&"pirate", &"carbine"]]
		for i in range(kit.size()):
			var m := RiderModel.new()
			stage.add_child(m)
			m.position = Vector3(-3.1 + i * 1.24, 0, 10.0)
			m.rotation.y = PI
			EnemyOutfit.dress(m, kit[i][0], 1000 + i * 17)
			if EnemyWeapons.is_long(kit[i][1]):
				m.attach_long_gun(EnemyWeapons.make(kit[i][1]), EnemyWeapons.make(kit[i][1]))
			else:
				var rv := EnemyWeapons.make(kit[i][1])
				m.hand_r.add_child(rv)
				rv.position = Vector3(0.0, -0.085, -0.02)
				rv.rotation_degrees = Vector3(-90, 0, 0)
			m.visible = false
			crew.append(m)
		var held := GarandModel.new(); held.set_loaded(8)
		var slung := GarandModel.new(); slung.set_loaded(8); slung.set_sling(true)
		person.attach_long_gun(held, slung)
		return false
	if idx >= shots.size():
		quit(); return true
	var s: Array = shots[idx]
	var f := frame - 2
	if f % 8 == 0:
		person.visible = s[4] != "none" and s[4] != "enemies"
		rifle.visible = s[4] == "none"
		for m in crew:
			m.visible = s[4] == "enemies"
			for k in range(30):
				m.gun_ads = 0.0
				m.animate("idle", 0.0, 0.05, m.long_gun != null, 0.0, 0.25)
			m.sync_resident_pose()
		# turntable shots spin the rifle about its middle; the others show it side-on
		var spin: float = s[5] if s.size() > 5 else 0.0
		rifle.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(spin + 90.0)), Vector3(3.0, 1.2, 0.0)) * Transform3D(Basis(), Vector3(0, 0, 0.55)) if s.size() > 5 else Transform3D(Basis(), Vector3(3.0, 1.2, 0.55))
		_pose(s[4])
		cam.fov = s[3]
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
	if f % 8 == 7:
		var img := get_root().get_texture().get_image()
		img.save_png("%s/%s.png" % [out, s[0]])
		print("saved ", s[0])
		idx += 1
	return false
