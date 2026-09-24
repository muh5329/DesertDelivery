extends Node
## Transactions through real physics ticks: handoffs, mode changes and silent persistence.
var game: Game
var failures := 0
var collected_events := 0
var delivered_events := 0
var wallet_snapshot: Dictionary = {}

func _ready() -> void:
	game=Game.current
	Events.package_collected.connect(func(_id): collected_events+=1)
	Events.delivery_completed.connect(func(_id,_total):
		delivered_events+=1
		# A UI/event subscriber must never re-enter and pay the same handoff twice.
		game.gm._complete_stage())
	game.gm.wallet_changed.connect(func(_coins): wallet_snapshot=game.gm.save_state())
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1

func settle(seconds: float=.8) -> void:
	game.world.streamer.load_all_pending()
	await get_tree().create_timer(seconds).timeout

func _run() -> void:
	var controls:=game.use_scripted_controls()
	controls.intent.handbrake=true
	var gm:=game.gm
	gm._start_job(0,false)
	game.bike.place(gm.target_position()+Vector3(0,4,0),Vector3.FORWARD)
	check(not gm._contains_courier(gm.pickup_zone,game.bike),"aircraft above ring cannot hand off")
	game.bike.place(gm.target_position(),Vector3.FORWARD)
	await settle()
	check(gm.carrying and gm.stage==DeliverySystem.Stage.TO_DROPOFF,"bike loads the first parcel")
	var saved:=gm.save_state()
	var count:=collected_events
	gm.load_state(saved)
	check(gm.carrying and gm.stage==DeliverySystem.Stage.TO_DROPOFF and collected_events==count,"loading an in-progress parcel is silent and preserves stage")
	gm.load_state(saved)
	check(collected_events==count and gm.coins==0,"repeated load creates no duplicate collection or reward")
	# Walking away from a parked bike must not hand over its parcel remotely.
	game.bike.place(gm.target_position(),Vector3.FORWARD)
	await get_tree().physics_frame
	check(game.rider.request_dismount(),"can dismount for a walking delivery")
	game.player.place(gm.target_position()+Vector3(14,0,0),Vector3.FORWARD)
	await settle()
	check(gm.deliveries==0,"unattended vehicle in dropoff ring cannot deliver remotely")
	game.player.place(gm.target_position(),Vector3.FORWARD)
	await settle(.1)
	controls.intent.press(Controls.JUMP)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await settle(.52)
	check(not game.player.is_on_floor() and gm.deliveries==0 and gm._zone_timer==0,"jumping resets the handoff timer and cannot deliver")
	await settle()
	check(gm.deliveries==1 and gm.coins==40 and delivered_events==1,"on-foot handoff pays exactly one actual reward")
	# Put the courier back on the bike and exercise every remaining pickup/dropoff.
	game.bike.place(game.player.global_position+Vector3(1,0,0),Vector3.FORWARD)
	check(game.rider.request_mount(),"return to bike after handoff")
	var expected_coins:=40
	for index in range(1,gm.jobs.size()):
		gm._cooldown=0
		game.bike.place(gm.target_position(),Vector3.FORWARD)
		await settle()
		check(gm.job_index==index and gm.stage==DeliverySystem.Stage.TO_DROPOFF,"job %d pickup"%index)
		expected_coins+=gm.current_job().reward if gm.current_job() else 0
		game.bike.place(gm.target_position(),Vector3.FORWARD)
		await settle()
		check(gm.deliveries==index+1,"job %d dropoff"%index)
	check(gm.stage==DeliverySystem.Stage.DONE and not gm.carrying and gm.coins==expected_coins,"all %d deliveries finish and rewards balance" % gm.jobs.size())
	check(gm.receipts.size()==gm.jobs.size(),"one persisted receipt for every completed handoff")
	check(int(wallet_snapshot.stage)==DeliverySystem.Stage.DONE and int(wallet_snapshot.job_index)==gm.jobs.size(),"wallet callback saves committed next-job state")
	var final_state:=gm.save_state()
	gm.load_state(final_state)
	check(gm.stage==DeliverySystem.Stage.DONE and gm.target_location()==&"" and gm.coins==expected_coins,"completed job set reloads without a phantom target")
	gm._complete_stage()
	check(gm.deliveries==gm.jobs.size() and gm.coins==expected_coins,"completed job cannot pay twice")
	# Truck must be the active courier vehicle, including after swapping while carrying.
	gm.load_state(saved)
	game.bike.place(gm.target_position()+Vector3(20,0,0),Vector3.FORWARD)
	await get_tree().physics_frame
	game.rider.request_dismount()
	game.truck.place(game.player.global_position+Vector3(1,0,0),Vector3.FORWARD)
	game.rider.request_mount()
	check(gm.vehicle==game.truck and gm.carrying,"carried job follows a switch to the truck")
	game.truck.place(gm.target_position(),Vector3.FORWARD)
	await settle(1.2)
	check(gm.deliveries==1 and gm.coins==40,"truck handoff completes through real overlap and stop")
	print("DELIVERY TESTS: %s (%d failures)" % ["PASS" if failures==0 else "FAIL",failures])
	get_tree().quit(0 if failures==0 else 1)
