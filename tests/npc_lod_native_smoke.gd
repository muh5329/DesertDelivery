extends SceneTree
## Native-backend smoke: 8 animated rigs, repeated full/reduced visibility changes.
## Run without --headless using the target renderer. Does not load the game/world.
var people: Array[RiderModel] = []
var frame := 0
func _init() -> void: call_deferred("run")
func run() -> void:
	var camera := Camera3D.new(); root.add_child(camera); camera.position=Vector3(0,3,10)
	camera.look_at(Vector3(0,1,0)); camera.current=true
	var light := DirectionalLight3D.new(); root.add_child(light); light.rotation_degrees=Vector3(-40,-20,0)
	for index in 8:
		var person := RiderModel.new(); root.add_child(person)
		person.position=Vector3((index%4-1.5)*1.8,0,-(index/4)*2.0)
		person.set_palette(Color(.4,.6,.8),Color(.8,.65,.35),Color(.6,.3,.1),Color(.9,.72,.55))
		person.enable_resident_lod(); people.append(person)
	print("NPC NATIVE SMOKE initialized")
func _process(delta: float) -> bool:
	if people.is_empty(): return false
	frame+=1
	for person in people:
		person.set_resident_lod_distance(30 if (frame/30)%2 else 10)
		person.animate("walk",1.35,delta);person.sync_resident_pose()
	if frame%30==0: print("NPC NATIVE SMOKE frame ",frame)
	if frame>=240:
		print("NPC NATIVE SMOKE PASS: 8 rigs, 8 LOD transitions")
		quit()
	return false
