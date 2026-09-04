extends Node
## Renders one screenshot per feature scenario through the real game camera:
##   0 dismounted next to the bike   1 swimming   2 aiming the pistol at the cans   3 flying
## xvfb-run godot --path . --rendering-driver opengl3 -- --test=feature_shots --out=/tmp/fshots

var main
var out := "/tmp/fshots"
var frame := 0
var scenario := -1
var settle := 0
var shots_done := 0


func _ready() -> void:
	main = Game.current
	out = main.cli.get_string("out", out)
	DirAccess.make_dir_recursive_absolute(out)


func _setup(i: int) -> void:
	var bike = main.bike; var pl = main.player; var cam = main.cam
	var tr = main.level.terrain
	var sc: Controls.Scripted = main.use_scripted_controls()
	match i:
		0:
			sc.intent.throttle = 0.0
			main.rider.request_dismount()
			sc.intent.move = Vector2(0.3, 1)
		1:
			pl.global_position = Vector3(150, 0.2, 203)
			sc.intent.move = Vector2(0, 1)
			cam.snap_to_target()
		2:
			main.gun.grant()
			var t: Area3D = main.gun.targets()[0]
			var stand: Vector3 = t.global_position + Vector3(1.0, 0, 6.0)
			stand.y = tr.height_at(stand.x, stand.z) + 0.05
			pl.place(stand, Vector3(0, 0, -1))
			sc.intent.move = Vector2.ZERO
			cam.snap_to_target()
		3:
			sc.intent.aim = false
			var side: Vector3 = bike.global_transform.basis.x
			pl.global_position = bike.global_position + side * 1.0
			main.rider.request_mount()
			main.rider.request_wings()
			bike.visual._wing_open = 1.0
			bike.global_position = Vector3(-69, tr.height_at(-69, -69) + 40.0, -69)
			bike.airborne = true
			bike.speed = 30.0
			sc.intent.throttle = 1.0; sc.intent.pitch = 0.2; sc.intent.steer = 0.4
			cam.snap_to_target()


func _process(_d: float) -> void:
	frame += 1
	if main.bike == null: return
	if scenario < 0:
		scenario = 0; _setup(0); settle = frame
		return
	# after a few frames in each scenario, capture and move on
	var waited := frame - settle
	var sc: Controls.Scripted = main.scripted_controls
	if scenario == 2 and waited >= 1 and waited <= 9:
		var t: Area3D = main.gun.targets()[0]
		var d: Vector3 = t.global_position + Vector3(0, 0.13, 0) - main.cam.global_position
		main.cam.set_look(atan2(-d.x, -d.z), -atan2(d.y, Vector2(d.x, d.z).length()))
		sc.intent.aim = true
	if scenario == 2 and waited == 9:
		sc.press("fire")
	if waited == 10:
		var img := get_tree().root.get_texture().get_image()
		img.save_png("%s/feature_%d.png" % [out, scenario])
		print("saved feature_%d.png" % scenario)
		scenario += 1
		if scenario > 3:
			get_tree().quit(); return
		_setup(scenario)
		settle = frame
	return
