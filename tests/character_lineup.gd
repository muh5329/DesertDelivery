extends Node
## Render the actual runtime resident wardrobe and shared animated rig for review.
func _ready() -> void:
	call_deferred("capture")

func capture() -> void:
	var game:=Game.current
	game.use_scripted_controls(); game.hud.hide(); game.cam.set_physics_process(false)
	var stage:=Node3D.new(); add_child(stage); stage.position=Vector3(0,500,0)
	var floor_mesh:=Mats.box(Vector3(16,.1,10),Mats.solid(Color("dbd8bd")),Vector3(0,-.05,0)); stage.add_child(floor_mesh)
	var lamp:=DirectionalLight3D.new(); lamp.rotation_degrees=Vector3(-50,-25,0); lamp.light_energy=1.2; stage.add_child(lamp)
	var views: Array[Node3D]=[]
	var occupations: Array[String]=[]
	var subjects: Array[Resident]=[]
	for record in game.life.residents:
		if record.occupation not in occupations:
			occupations.append(record.occupation); subjects.append(record)
	for index in subjects.size():
		var record:=subjects[index]
		var person:=RiderModel.new(); stage.add_child(person); views.append(person)
		person.set_palette(Color(record.palette[0]),Color(record.palette[1]),Color(record.palette[2]),Color(record.palette[3]))
		person.set_character_identity(record.id,record.occupation,record.palette)
		person.position=Vector3((index%6-2.5)*1.55,0,0)
		person.rotation.y=-.10
		person.animate("idle",0,1.0)
		var label:=Label3D.new(); label.text=record.occupation; label.font_size=34; label.pixel_size=.0038
		label.position=person.position+Vector3(0,2.2,0); label.modulate=Color("33463c"); label.outline_size=0; label.rotation.y=PI
		stage.add_child(label); label.hide()
	var camera:=Camera3D.new(); stage.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=5.4
	camera.look_at_from_position(Vector3(0,501.9,-9.4),Vector3(0,500.95,0)); camera.current=true
	for i in views.size(): views[i].visible=i<6
	for frame in 10: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output:=game.cli.get_string("out","/tmp/characters")
	DirAccess.make_dir_recursive_absolute(output)
	get_viewport().get_texture().get_image().save_png(output+"/resident-lineup.png")
	for i in views.size(): views[i].visible=i>=6
	for frame in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+"/resident-lineup-second.png")
	print("CHARACTER LINEUP: ",subjects.size()," occupation silhouettes rendered")
	get_tree().quit()
