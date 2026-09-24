extends Node
## Actual streamed gameplay-world views; wait for the bounded dressing queue to settle.
var camera: Camera3D
var frame:=0
var index:=0
var out: String
var spots: Array[Vector2]=[Vector2(-4200,-4200),Vector2(4200,3400)]
func _ready() -> void:
	out=Game.current.cli.get_string("out","artifacts/overhaul-2026-09-19/wilderness")
	DirAccess.make_dir_recursive_absolute(out)
	Game.current.cam.set_physics_process(false); Game.current.cam.current=false
	Game.current.use_scripted_controls(); Game.current.hud.visible=false
	Game.current.bike.visible=false; Game.current.player.visible=false
	camera=Camera3D.new(); camera.far=25000; camera.fov=62; add_child(camera); camera.current=true
	_place()
func _place() -> void:
	var world:=Game.current.world
	var p:=spots[index]
	var origin:=Vector3(p.x,world.terrain.height_at(p.x,p.y),p.y)
	Game.current.bike.place(origin+Vector3.UP*.8,Vector3.FORWARD)
	camera.look_at_from_position(origin+Vector3(0,5,0),origin+Vector3(40,7,-130))
	world.terrain.set_view_camera(camera)
func _process(_dt: float) -> void:
	frame+=1
	if frame%45!=0: return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out+"/outer_%d.png"%index)
	print("OUTER FLORA ",Game.current.world.outer.flora.stats())
	index+=1
	if index==spots.size(): get_tree().quit(); return
	_place()
