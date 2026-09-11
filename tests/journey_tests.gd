extends Node
## Local counter integration: offers use real routes, handoffs, wallet and persistence.
var game: Game
var failures:=0
var collections:=0
func _ready() -> void:
	game=Game.current
	Events.package_collected.connect(func(_id): collections+=1)
	call_deferred("_run")

func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1

func settle(seconds: float=.6) -> void:
	game.world.streamer.load_all_pending()
	await get_tree().create_timer(seconds).timeout

func _run() -> void:
	var controls:=game.use_scripted_controls(); controls.intent.handbrake=true
	var journey:=game.journey; var gm:=game.gm
	gm.handoffs_paused=true
	var home:=game.world.database.location_pos(&"villa_rosa_office")
	game.bike.place(home,Vector3.FORWARD)
	await settle(.3)
	# The Journal is a modal too. Reading it while parked in a pickup Ring must not collect the
	# parcel behind the book — before the panels shared one protocol, only the Counter paused
	# handoffs, so it did.
	gm.handoffs_paused=false
	game.catalogue.toggle()
	check(game.catalogue.is_open() and gm.handoffs_paused and game.player_controls.blocked,
		"the journal pauses handoffs and blocks controls, exactly like the counter")
	await settle(.7)
	check(not gm.carrying,"reading the journal at a pickup does not collect the parcel behind the book")
	game.catalogue.toggle()
	await settle(.3)
	check(not gm.handoffs_paused and not game.player_controls.blocked,"closing the journal resumes handoffs and controls")
	gm.handoffs_paused=true
	check(journey.open_counter(),"stopped courier opens a local counter")
	check(journey.is_open() and game.player_controls.blocked and gm.handoffs_paused,"counter blocks controls and pauses automatic handoff")
	await settle(.7)
	check(not gm.carrying,"browsing at pickup does not collect a parcel behind the panel")
	game.catalogue.toggle()
	check(not game.catalogue.is_open(),"journal cannot steal an open counter's input")
	var offers:=journey.offers_for(&"villa_rosa_office")
	check(offers.size()==3 and offers[0].mass_kg<offers[1].mass_kg and offers[1].mass_kg<offers[2].mass_kg,"local board has three distinct load/reward choices")
	var original_reward:=gm.jobs[0].reward
	check(journey.accept_offer("heavy"),"heavy offer selects existing local route")
	check(not journey.is_open() and gm.current_job().cargo_mass_kg==55 and gm.current_job().reward==68,"offer closes board and configures its advertised load/reward")
	await settle(.8)
	check(gm.carrying and float(game.bike.get_meta("cargo_mass_kg"))==55,"collecting selected parcel changes real bike payload metadata")
	check(not journey.accept_offer("light") and gm.current_job().cargo_kind=="heavy","a carried parcel cannot be replaced at the board")
	var saved_delivery:=gm.save_state(); var before_collections:=collections
	gm.load_state(saved_delivery); gm.load_state(saved_delivery)
	check(gm.carrying and gm.current_job().reward==68 and gm.current_job().cargo_mass_kg==55 and collections==before_collections,"load restores chosen parcel without transactions or duplicated collection")
	var before_day:=floori(game.life.total_minutes/1440)
	var work_total: int=game.life.residents[0].completed_tasks
	check(journey.rest_until_morning(),"courier can rest at Villa Rosa")
	check(floori(game.life.total_minutes/1440)==before_day+1 and is_equal_approx(game.life.minute_of_day(),480.0),"rest advances calendar to next day at08:00")
	check(gm.carrying and game.life.residents[0].completed_tasks==work_total,"rest preserves the parcel and does not invent completed resident work")
	journey.fuel_ratio=1.0; journey._odometer=game.bike.odometer
	game.bike.odometer+=1000.0; journey._process(1.0)
	check(is_equal_approx(journey.fuel_ratio,.83125),"fuel uses actual travel distance and cargo weight")
	var stopped_fuel:=journey.fuel_ratio; journey._process(3600.0)
	check(is_equal_approx(journey.fuel_ratio,stopped_fuel),"waiting at a counter does not consume fuel")
	game.bike.place(gm.target_position(),Vector3.FORWARD)
	await settle(.8)
	check(gm.deliveries==1 and gm.coins==68,"selected heavy route pays its advertised reward once")
	check(gm.active_job_override==null and gm.job_index==1 and gm.jobs[0].reward==original_reward,"default chain continues and original job resource remains unchanged")
	check(journey.open_counter(),"next village offers workshop services")
	check(not journey.rest_until_morning(),"rest is only available at the courier's home")
	gm.coins=500; journey.fuel_ratio=.1
	check(journey.refuel() and gm.coins==483 and journey.fuel_ratio==1.0,"full refill charges exact missing fuel cost")
	check(not journey.refuel() and gm.coins==483,"a full tank cannot charge coins again")
	check(journey.upgrade_engine() and journey.engine_level==1 and gm.coins==363,"first engine upgrade spends earned coins and updates level")
	check(journey.upgrade_engine() and journey.engine_level==2 and gm.coins==123,"second engine upgrade uses its own price")
	check(not journey.upgrade_engine() and journey.engine_level==2 and gm.coins==123,"unaffordable upgrade is an atomic no-op")
	gm.coins=500; check(journey.upgrade_engine() and journey.engine_level==3 and gm.coins==140,"third engine upgrade applies once")
	check(not journey.upgrade_engine() and gm.coins==140,"maximum engine level cannot charge again")
	journey.fuel_ratio=0.0; gm.coins=0
	check(journey.courier_reserve() and is_equal_approx(journey.fuel_ratio,.2) and gm.coins==0,"empty broke courier gets20percent station reserve")
	check(not journey.courier_reserve() and is_equal_approx(journey.fuel_ratio,.2),"reserve fuel cannot refill beyond its limit")
	var saved_journey:=journey.save_state()
	journey.fuel_ratio=.9; journey.engine_level=0; journey.load_state(saved_journey)
	check(is_equal_approx(journey.fuel_ratio,.2) and journey.engine_level==3 and int(game.bike.get_meta("engine_level"))==3,"fuel and engine save/load restore real bike metadata")
	check(Saves._providers.get("journey")==journey,"journey is registered with the game save provider")
	var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true
	journey._input(escape)
	check(not journey.is_open() and journey.just_closed and game.player_controls.blocked,"Escape closes counter without immediate gameplay click-through")
	for i in range(4): await get_tree().process_frame
	check(not game.player_controls.blocked and not gm.handoffs_paused,"controls and handoffs resume after closing")
	# Fragile risk is wired to actual vehicle events and survives a loaded parcel save.
	gm._start_job(0,false)
	check(gm.select_board_offer(0,{"kind":"fragile","mass_kg":14.0,"reward":54}),"fragile offer is selectable before collection")
	gm._complete_stage()
	Events.vehicle_crashed.emit(&"vehicle.other")
	check(is_equal_approx(gm.parcel_condition,1.0),"unrelated vehicle crash cannot damage carried cargo")
	Events.vehicle_crashed.emit(game.bike.entity_id)
	check(is_equal_approx(gm.parcel_condition,.78) and gm.current_payout()==48,"courier crash reduces fragile condition and the real payout")
	Events.vehicle_crashed.emit(game.bike.entity_id)
	check(is_equal_approx(gm.parcel_condition,.78),"one collision cannot repeatedly damage a parcel in consecutive frames")
	var fragile_save:=gm.save_state(); gm.load_state(fragile_save)
	check(is_equal_approx(gm.parcel_condition,.78) and gm.current_payout()==48,"save/load preserves fragile condition and payout")
	gm._impact_cooldown=0
	Events.vehicle_landed.emit(game.bike.entity_id,6.0)
	check(is_equal_approx(gm.parcel_condition,.78),"gentle landings preserve fragile cargo")
	Events.vehicle_landed.emit(game.bike.entity_id,10.0)
	check(gm.parcel_condition<.78,"hard landing damages fragile cargo")
	var expected_payout: int = gm.current_payout(); var wallet_before:=gm.coins
	gm._complete_stage()
	check(gm.coins==wallet_before+expected_payout,"handoff pays adjusted fragile value exactly once")
	# All service entry points revalidate location; button state is not authorization.
	game.bike.place(Vector3(10000,50,10000),Vector3.FORWARD)
	check(not journey.refuel() and not journey.upgrade_engine() and not journey.courier_reserve() and not journey.accept_offer("light"),"remote actions cannot spend money or select local jobs")
	print("JOURNEY_TESTS_PASS" if failures==0 else "JOURNEY_TESTS_FAIL: %d" % failures)
	get_tree().quit(0 if failures==0 else 1)
