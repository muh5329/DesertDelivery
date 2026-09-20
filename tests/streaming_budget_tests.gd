extends SceneTree
## Synthetic atomic builders verify shared budget, deterministic continuation,
## synchronous helpers and collider-preserving oversized recipe ownership.
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,message:String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures+=1
func add_recipes(db:WorldDatabase,kit:WorldKit,values:Array,delay:int) -> void:
	for index in 8:
		db.add(1,1,func():
			if delay: OS.delay_usec(delay)
			values.append(kit.rng.randf())
			kit.sink.add_child(Node3D.new()))
func run() -> void:
	var streamer_script=load("res://world/streaming/world_streamer.gd")
	var db:=WorldDatabase.new();db.chunk_size=60
	var kit:=WorldKit.new();root.add_child(kit)
	var config:=WorldConfig.new();config.stream_radius=0;config.unload_margin=0;config.chunks_per_frame=1
	var values:Array=[];add_recipes(db,kit,values,1300)
	var stream=streamer_script.new();root.add_child(stream);stream.set_process(false);stream.setup(db,kit,config)
	stream._process(1.0/60)
	check(values.size()>0 and values.size()<8,"one frame stops between recipes rather than constructing whole chunk")
	check(not stream.is_loaded_at(Vector3(1,0,1)),"partial chunk is not reported as collision-ready")
	check(stream.max_recipe_usec>=1300,"instrumentation records individual expensive builder")
	for frame in 20:
		if stream.stats().pending==0:break
		# Unrelated use of the shared RNG must not affect the resumed chunk.
		kit.rng.seed=frame+99;kit.rng.randf()
		stream._process(1.0/60)
	check(values.size()==8 and stream.is_loaded_at(Vector3(1,0,1)),"incremental queue finishes each recipe exactly once")
	var db2:=WorldDatabase.new();db2.chunk_size=60
	var reference:Array=[];add_recipes(db2,kit,reference,0)
	var chunk:=Chunk.new();root.add_child(chunk);chunk.coord=Vector2i.ZERO;chunk.build(db2,kit)
	check(values==reference,"RNG sequence identical for synchronous and interrupted construction")
	chunk.free();stream.free()
	# Finish a partially-built chunk synchronously when an explicit caller asks.
	var db3:=WorldDatabase.new();db3.chunk_size=60
	var synchronous:Array=[];add_recipes(db3,kit,synchronous,1300)
	stream=streamer_script.new();root.add_child(stream);stream.set_process(false);stream.setup(db3,kit,config)
	stream._process(.016);stream.load_all_pending()
	check(synchronous.size()==8 and stream.stats().pending==0,"load_all_pending drains both partial and not-started work")
	stream.free()
	var shared_db:=WorldDatabase.new();shared_db.chunk_size=60
	var counter:Dictionary={"calls":0}
	shared_db.add(90,1,func():
		counter.calls+=1
		var body:=StaticBody3D.new();body.name="SharedBridge";body.collision_layer=1
		var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(160,1,4)
		collider.shape=box;body.add_child(collider);body.position=Vector3(90,2,1)
		kit.sink.add_child(body),100)
	stream=streamer_script.new();root.add_child(stream);stream.set_process(false);stream.setup(shared_db,kit,config)
	for coordinate in [Vector2i(0,0),Vector2i(1,0),Vector2i(2,0)]:stream._load(coordinate)
	var recipe:Recipe=shared_db.records_in(Vector2i(0,0))[0]
	var container:Node3D=stream.loaded[Vector2i(0,0)]._owned[recipe]
	var body:StaticBody3D=container.get_child(0)
	var identity:=body.get_instance_id();var rid:=body.get_rid();var transform:=body.global_transform
	var departing: Array[Vector2i] = [Vector2i(0,0),Vector2i(1,0)]
	stream._unload_group(departing)
	check(recipe.owner==Vector2i(2,0) and counter.calls==1,"batch departure transfers to survivor without bouncing/rebuilding")
	check(body.get_instance_id()==identity and body.get_rid()==rid and body.global_transform==transform,"shared structure preserves node, physics RID and world placement")
	await physics_frame;await physics_frame
	var query:=PhysicsRayQueryParameters3D.create(Vector3(130,5,1),Vector3(130,0,1),1)
	check(not root.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"transferred shared bridge remains physically collidable")
	stream._unload(Vector2i(2,0))
	check(recipe.unclaimed(),"last owner leaving releases recipe")
	check(body.collision_layer==0 and body.collision_mask==0,"retired collider disabled before deferred deletion")
	stream._load(Vector2i(2,0));check(counter.calls==2,"same-frame return rebuilds once without active stale collider")
	await process_frame
	stream.load_everything()
	check(not stream.enabled and stream.stats().pending==0,"load_everything remains synchronous and disables streaming")
	stream.free();kit.free()
	await process_frame
	print("STREAMING BUDGET failures: ",failures);quit(1 if failures else 0)
