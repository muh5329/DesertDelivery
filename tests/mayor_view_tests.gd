extends Node
## Real-game modal, terrain projection and map-tool regression checks.
var failures := 0
func _ready() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ")+message)
	if not value: failures += 1
func run() -> void:
	var game := Game.current
	game.use_scripted_controls()
	var view: MayorView = game.get("mayor")
	if view == null:
		check(false,"Mayor view is wired into game boot")
		get_tree().quit(1); return
	view.set_active(true)
	check(not view.active,"mounted entry rejected")
	await get_tree().process_frame
	var original_guard := game.rider.pointer_blocks_actions
	var entry_press := InputEventMouseButton.new()
	entry_press.button_index=MOUSE_BUTTON_LEFT;entry_press.pressed=true
	entry_press.position=view.entry.get_global_rect().get_center()
	view._input(entry_press)
	game.rider.pointer_blocks_actions=func(): return view.blocks_world_input()
	game.scripted_controls.press(Controls.FIRE)
	game.rider._physics_process(1.0/120.0)
	check(view.entry_pointer_pressed and not game.rider._last_intent.pressed(Controls.FIRE),"inactive entry held press strips FIRE in actual Rider routing")
	entry_press.pressed=false;view._input(entry_press)
	game.rider.pointer_blocks_actions=original_guard
	game.rider._set_mode(Rider.Mode.ON_FOOT)
	var pos := game.bike.global_position+Vector3(2,0,0)
	pos.y = game.world.terrain.height_at(pos.x,pos.z)+0.1
	game.player.place(pos,Vector3.FORWARD)
	for frame in 90: await get_tree().physics_frame
	check(game.player.is_on_floor(),"courier grounded before opening")
	var previous_camera := get_viewport().get_camera_3d()
	var previous_mode := game.rider.mode
	var previous_process := game.player.is_physics_processing()
	var previous_hud := game.hud.visible
	view.set_active(true)
	check(view.active and game.panels.is_open(view),"grounded entry uses shared modal protocol")
	check(get_viewport().get_camera_3d()==view.camera,"mayor camera becomes current")
	check(not game.hud.visible and not game.player.is_physics_processing(),"mayor hides HUD and holds courier physics")
	for page in ["Jobs","Areas","Build","Paths"]:
		view.current_page=page; view.build_page()
		check(view.content.get_child_count()>2,"actual "+page+" controls built")
	await get_tree().process_frame
	view.set_tool("zone:Woodcutter")
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=Vector2(30,130)
	view._unhandled_input(event)
	check(not view.drawing,"sidebar press cannot start terrain order")
	view.drawing=true; view.stroke=PackedVector3Array([Vector3.ZERO])
	event.pressed=false;view._input(event)
	check(not view.drawing and view.stroke.is_empty(),"drag released over sidebar cancels without order")
	view.center=Vector3(-2600,0,-3600);view.update_camera()
	var at:Variant=view.project_ground(get_viewport().get_visible_rect().size*0.5)
	check(at!=null and Vector2(at.x+2600,at.z+3600).length()<0.1,"terrain ray projection reaches remote island without loaded collider")
	view.center=Vector3(50000,0,-50000);view.update_camera()
	check(absf(view.center.x)<=12450 and absf(view.center.z)<=12450,"camera pan obeys 25 km island bounds")
	var held := InputEventMouseButton.new()
	held.button_index=MOUSE_BUTTON_LEFT;held.pressed=true;held.position=Vector2(20,20)
	Input.parse_input_event(held)
	view.close_panel()
	check(not view.active and not game.panels.is_open(view),"close releases modal")
	check(get_viewport().get_camera_3d()==previous_camera,"close restores prior camera")
	check(game.rider.mode==previous_mode and game.player.is_physics_processing()==previous_process,"close preserves courier mode and physics flag")
	check(game.hud.visible==previous_hud,"close restores prior HUD visibility")
	for frame in 3: await get_tree().process_frame
	game.panels.process()
	check(game.player_controls.blocked,"closing while mouse held keeps gameplay input blocked beyond frame latch")
	var keyboard_intent := game.player_controls.read(Controls.Foot.new(),1.0/120.0)
	check(not keyboard_intent.pressed(Controls.FIRE),"held close click cannot leak a gameplay FIRE command")
	held.pressed=false;Input.parse_input_event(held)
	await get_tree().process_frame
	game.panels.process()
	check(not game.player_controls.blocked,"releasing close click restores gameplay controls")
	var other:=Node.new();add_child(other);game.panels.open(other)
	view.set_active(true);check(not view.active,"entry rejects another modal")
	game.panels.close(other);other.queue_free()
	game.player.stamina=17.0;game.player.sprint_exhausted=true;game.player.regen_delay=0.6
	var rider_snapshot:=game.rider.save_state()
	game.player.stamina=100.0;game.player.sprint_exhausted=false;game.player.regen_delay=0.0
	game.rider.load_state(rider_snapshot)
	check(is_equal_approx(game.player.stamina,17.0) and game.player.sprint_exhausted and is_equal_approx(game.player.regen_delay,0.6),"Rider save/load preserves stamina exhaustion and regeneration delay")
	print("MAYOR VIEW failures: ",failures)
	get_tree().quit(1 if failures else 0)
