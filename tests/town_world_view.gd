extends Node
## Captures the actual streamed town at street and harbour scale.
var cam: Camera3D
var views: Array = []
var frame := 0
var index := 0
var out := "/tmp/desert-town-world"
func _ready() -> void:
	out=Game.current.cli.get_string("out",out)
	DirAccess.make_dir_recursive_absolute(out)
	var game := Game.current; var terrain := game.world.terrain
	game.cam.set_physics_process(false); game.cam.current=false
	game.use_scripted_controls(); game.hud.visible = false; game.bike.visible = false; game.player.visible = false
	cam = Camera3D.new(); cam.fov = 62; cam.far = 1600; add_child(cam); cam.current = true; terrain.set_view_camera(cam)
	var p := terrain.nearest_road(Vector3(235,0,-200))
	views.append([p.point + Vector3(0,2.5,0),p.point+p.tangent*30+Vector3(0,2,0)])
	views.append([Vector3(205,terrain.height_at(205,-100)+32,-100),Vector3(300,terrain.height_at(300,-220)+4,-220)])
	var q := terrain.nearest_road(Vector3(350,0,-190))
	views.append([q.point + Vector3(0,2.6,0),q.point-q.tangent*35+Vector3(0,3,0)])
	var court := Vector3(300,terrain.height_at(300,-245),-245)
	var entry := terrain.nearest_road(court)
	var court_front: Vector3 = (entry.point-court).normalized()
	views.append([court+court_front*34.0+Vector3(0,18,0),court+Vector3(0,2,0)])
	_place()
func _place() -> void:
	cam.look_at_from_position(views[index][0],views[index][1])
	cam.current=true
	print("VIEW ",index," ",cam.global_transform," current ",get_viewport().get_camera_3d())
	Game.current.bike.place(views[index][1]+Vector3(0,20,0),Vector3.FORWARD)
	Game.current.world.streamer.load_all_pending()
func _process(_dt: float) -> void:
	frame += 1
	if frame%12==0:
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(out+"/town_%d.png"%index)
		print("Town screenshot ",index)
		index += 1
		if index == views.size(): get_tree().quit(); return
		_place()
