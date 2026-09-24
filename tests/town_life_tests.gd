extends Node
## The outer world's life: townsfolk, traffic, boats, the new-look enemies, urgent supply jobs.
##   godot --headless --path . -- --test=town_life_tests
var game: Game
var failures := 0
var life: IslandLife
var tf: TownFolk
var tr: OuterTraffic
var boats: OuterBoats


func _ready() -> void:
	game = Game.current
	life = game.life
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + label)
	if not ok: failures += 1


func frames(n: int) -> void:
	for i in n: await get_tree().process_frame


func _run() -> void:
	await get_tree().physics_frame
	tf = life.outer.towns
	tr = life.outer.traffic
	boats = life.outer.boats
	check(tf != null and tr != null and boats != null, "outer life is built (townsfolk, traffic, boats)")
	await _far_costs_nothing()
	_populations()
	_routes_on_streets()
	await _routines_and_bodies()
	await _traffic()
	_boats()
	await _enemies()
	await _urgent_supply()
	print("TOWN LIFE TESTS: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------- far towns
func _far_costs_nothing() -> void:
	# at the start (the villa, on the core) every town is kilometres away
	await frames(30)
	check(tf.active_ids().is_empty(), "no town is active from the core island")
	check(tf.bodies_in_use() == 0, "no townsfolk bodies exist far from the towns")
	var ready := 0
	for id in tf.towns: if (tf.towns[id] as TownPopulation).ready: ready += 1
	check(ready <= 2, "far towns are not even generated (%d of %d ready)" % [ready, tf.towns.size()])
	check(tf.frame_us < 400, "townsfolk cost with every town far away: %.3f ms" % (tf.frame_us / 1000.0))


# ---------------------------------------------------------------- populations
func _populations() -> void:
	var outer: OuterWorld = game.world.outer
	var height := func(x: float, z: float) -> float: return outer.height_at(x, z)
	var by_id := {}
	for group in ["towns", "hamlets"]:
		for t in outer.plan()[group]: by_id[t.id] = t
	var counts := {}
	for id in tf.order:
		tf.prepare_now(id)
		counts[id] = (tf.towns[id] as TownPopulation).people.size()
	print("    populations: ", counts)
	check(int(counts.puerto_alto) >= 250 and int(counts.puerto_alto) <= 500, "Puerto Alto has a few hundred people (%d)" % counts.puerto_alto)
	var hamlets_ok := true
	for id in counts:
		if String(id).begins_with("hamlet_") and (int(counts[id]) < 3 or int(counts[id]) > 12): hamlets_ok = false
	check(hamlets_ok, "every hamlet has a handful of people")
	# deterministic: a second generation from the same plan is the same town
	var again := TownPopulation.new(by_id.sarmada, height)
	again.generate()
	var first: TownPopulation = tf.towns.sarmada
	var same := again.people.size() == first.people.size() and again.spots.size() == first.spots.size()
	for i in mini(again.people.size(), first.people.size()):
		var a: Townsperson = again.people[i]; var b: Townsperson = first.people[i]
		same = same and a.seed == b.seed and a.occupation == b.occupation and a.home == b.home and a.work == b.work and str(a.routine) == str(b.routine)
	check(same, "populations are deterministic per town (Sarmada generated twice: identical)")
	var looks_same: bool = str(CharacterLook.signature(first.people[3].look(first.style))) == str(CharacterLook.signature(again.people[3].look(again.style)))
	check(looks_same, "a townsperson's look is the same every time")
	# occupations fit the place
	var puerto: Dictionary = (tf.towns.puerto_alto as TownPopulation).counts
	var campo: Dictionary = (tf.towns.campo_real as TownPopulation).counts
	var valdoro: Dictionary = (tf.towns.valdoro as TownPopulation).counts
	var sarmada: Dictionary = first.counts
	check(int(puerto.get("dockworker", 0)) > 10 and int(puerto.get("fisher", 0)) > 5 and int(puerto.get("vendor", 0)) + int(puerto.get("merchant", 0)) > 10,
		"Puerto Alto: dockworkers, fishers and merchants (%s)" % puerto)
	check(int(campo.get("farmer", 0)) > 20, "Campo Real: farmers (%s)" % campo)
	check(int(valdoro.get("shepherd", 0)) + int(valdoro.get("woodcutter", 0)) > 10, "Valdoro: shepherds and woodcutters (%s)" % valdoro)
	check(int(sarmada.get("vendor", 0)) + int(sarmada.get("merchant", 0)) > 10 and int(sarmada.get("porter", 0)) + int(sarmada.get("weaver", 0)) > 5, "Sarmada: souk traders, porters, weavers (%s)" % sarmada)
	var styles_ok := true
	for p: Townsperson in (tf.towns.isola_serena as TownPopulation).people.slice(0, 20):
		styles_ok = styles_ok and p.look(&"isola").style == &"isola"
	check(styles_ok, "townsfolk wear their town's style")


# ---------------------------------------------------------------- streets
func _routes_on_streets() -> void:
	var pop: TownPopulation = tf.towns.puerto_alto
	var bad_nodes := 0
	for nid in pop.graph.get_point_ids():
		var q := pop.graph.get_point_position(nid)
		if not pop.clear(q.x, q.z, 0.0) or q.y < 0.25: bad_nodes += 1
	check(bad_nodes == 0, "no walking-graph node lies inside a building, a prop or the water (%d nodes)" % pop.node_count())
	var n := 0; var ok := 0; var inside := 0; var worst := 0
	for p: Townsperson in pop.people:
		if p.work < 0 or n >= 60: continue
		n += 1
		var r := pop.route(p.home, p.work)
		if r.size() >= 2: ok += 1
		var bad := 0
		for k in range(1, r.size() - 1):
			if not pop.clear(r[k].x, r[k].z, 0.0) or r[k].y < 0.2: bad += 1
		inside += bad; worst = maxi(worst, bad)
	check(ok >= n * 0.9, "home -> work routes exist for %d of %d workers" % [ok, n])
	check(inside == 0, "routes follow the streets, never through a building or a prop (%d points inside)" % inside)


# ---------------------------------------------------------------- routines and bodies
func _routines_and_bodies() -> void:
	var pop: TownPopulation = tf.towns.puerto_alto
	var plaza: Vector3 = pop.centre
	var day := floorf(life.total_minutes / 1440.0) * 1440.0
	life.set_physics_process(false)
	tf.simulate("puerto_alto", day + 600.0, day + 680.0)
	var walking := 0; var at_spot := 0; var moved := 0; var inside := 0
	var t := life.total_minutes
	for p: Townsperson in pop.people:
		if p.state == Townsperson.State.WALKING:
			walking += 1
			var q: Vector3 = p.sample(tf._walked(p, t))[0]
			if not pop.clear(q.x, q.z, 0.0) or q.y < 0.2: inside += 1
		elif p.state == Townsperson.State.AT_SPOT: at_spot += 1
		if p.entry != p.entry_at(fposmod(day + 600.0, 1440.0)): moved += 1
	check(moved > 20, "routines move people between spots in an hour of the morning (%d moved)" % moved)
	check(walking > 5 and at_spot > 80, "mid-morning: %d walking, %d at their spots (stalls, quays, benches...)" % [walking, at_spot])
	check(inside == 0, "walkers are on the streets, not in walls")
	# at night everybody is home
	tf.simulate("puerto_alto", day + 1440.0 + 180.0, day + 1440.0 + 200.0)
	var out_at_night := 0
	for p: Townsperson in pop.people:
		if p.state != Townsperson.State.INDOORS: out_at_night += 1
	check(out_at_night < pop.people.size() * 0.05, "at 3 am the town sleeps (%d out)" % out_at_night)
	tf.simulate("puerto_alto", day + 2880.0 + 600.0, day + 2880.0 + 640.0)
	life.set_physics_process(true)
	# bodies near the viewer only, bounded
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	cam.global_position = plaza + Vector3(-40, 1.7, 30)
	game.bike.global_position = cam.global_position + Vector3(0, 30, 0)
	for i in 20: await get_tree().process_frame
	for i in 30:
		tf._select_views()
		if not tf._pending_views: break
	check(tf.bodies_in_use() > 30, "people round the plaza get bodies (%d)" % tf.bodies_in_use())
	check(tf.bodies_in_use() <= TownFolk.MAX_BODIES, "at most %d bodies (%d)" % [TownFolk.MAX_BODIES, tf.bodies_in_use()])
	var nearest := 0.0; var farthest := 0.0; var near_count := 0
	for b: TownBody in tf.bodies:
		if b.person == null: continue
		farthest = maxf(farthest, b.person.view_distance)
		if b.near: near_count += 1
	check(farthest <= TownFolk.VIEW_RADIUS + 5.0 and near_count <= TownFolk.MAX_NEAR, "bodies within %.0f m, %d near-eligible" % [farthest, near_count])
	PersonBuilder.wait_parts(); PersonBuilder.poll_parts()
	for i in 10: await get_tree().process_frame
	check(tf.near_in_use() <= TownFolk.MAX_NEAR, "detailed meshes shown: %d (<= %d)" % [tf.near_in_use(), TownFolk.MAX_NEAR])
	var drawn := 0; var floating := 0; var tposed := 0
	for b: TownBody in tf.bodies:
		if b.person == null or not b.visible: continue
		drawn += 1
		var ground := game.world.terrain.height_at(b.global_position.x, b.global_position.z)
		if absf(b.global_position.y - ground) > 0.35 and not b.seated:
			floating += 1
			print("    off the ground: %s %s at %s (ground %.2f) state %d pose %s" % [b.person.id, b.person.occupation, b.global_position, ground, b.person.state, b.pose])
		if absf(b.model.arm_l.rotation.z) > 1.2 or absf(b.model.arm_r.rotation.z) > 1.2: tposed += 1
	check(drawn > 20, "bodies draw once their meshes are built (%d)" % drawn)
	check(floating == 0, "nobody floats or sinks (%d off the ground)" % floating)
	check(tposed == 0, "no T-poses")
	# the cost of the records and the views, over a second of frames
	var total := 0; var worst := 0
	for i in 60:
		await get_tree().process_frame
		total += tf.frame_us; worst = maxi(worst, tf.frame_us)
	print("    townsfolk: %.3f ms/frame average, %.3f ms worst, %d bodies" % [total / 60000.0, worst / 1000.0, tf.bodies_in_use()])
	check(total / 60.0 < 3000.0, "townsfolk records + views average %.2f ms a frame in Puerto Alto (headless)" % (total / 60000.0))
	var t0 := Time.get_ticks_usec()
	for i in 30: tf._tick(1.0 / 60.0)
	var tick_ms := float(Time.get_ticks_usec() - t0) / 30000.0
	check(tick_ms < 1.0, "the routines of an active town cost %.3f ms a frame (< 1 ms)" % tick_ms)
	# walk away: the town lets go of everything
	cam.global_position = Vector3(0, 60, 0)
	game.bike.global_position = Vector3(0, 60, 0)
	for i in 10: await get_tree().process_frame
	check(tf.bodies_in_use() == 0 and not tf.active.has("puerto_alto"), "leaving town frees every body and deactivates it")
	cam.queue_free()


# ---------------------------------------------------------------- traffic
func _traffic() -> void:
	var c := Vector3(5099.95, 52.66, -344.88)
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	cam.global_position = c + Vector3(0, 25, 0)
	game.bike.global_position = c + Vector3(0, 30, 0)
	game.world.set_focus(game.bike)
	game.world.outer.focus = game.bike
	game.world.outer.refresh_collision()
	var target := tr.target_count(c)
	for i in 240: await get_tree().physics_frame
	check(tr.count() > 0 and target > 0, "traffic spawns round a highway (%d vehicles, target %d)" % [tr.count(), target])
	var near_spawn := 0; var off_road := 0; var kinds := {}
	for v in tr.vehicles:
		kinds[v.kind] = true
		if (v.pos as Vector3).distance_to(c) > OuterTraffic.DESPAWN: near_spawn += 1
		var n := tr.nav.nearest(v.pos)
		if tr.nav.graph.get_point_position(n).distance_to(v.pos) > 9.0: off_road += 1
	check(near_spawn == 0, "every vehicle is within %.0f m of the viewer" % OuterTraffic.DESPAWN)
	check(off_road == 0, "vehicles stay on the roads (%d off)" % off_road)
	# lanes: two vehicles meeting never overlap
	var overlap := 0
	for a in tr.vehicles:
		for b in tr.vehicles:
			if a == b: continue
			if (a.pos as Vector3).distance_to(b.pos) < 1.5: overlap += 1
	check(overlap == 0, "no two vehicles overlap")
	var moving := 0
	for v in tr.vehicles: if float(v.v) > 3.0: moving += 1
	check(moving > 0, "traffic is moving (%d)" % moving)
	# a vehicle stops for the courier in its lane
	var rec := tr.spawn_one(tr.nodes_near(c, 0.0, 200.0)[0], "car", 0)
	if not rec.is_empty():
		rec.v = 12.0
		var ahead: Vector3 = tr._sample(rec, float(rec.s) + 40.0)[0]
		game.truck.set_physics_process(false)
		game.truck.global_position = ahead
		tr._gap_t = 0.0
		for i in 600: await get_tree().physics_frame
		print("    stop test: in traffic %s, s %.1f, done %s, limit %.1f, v %.1f" % [tr.vehicles.has(rec), float(rec.s), rec.done, float(rec.limit), float(rec.v)])
		var gap := (rec.pos as Vector3).distance_to(game.truck.global_position)
		check(float(rec.v) < 0.5 and gap > 3.0, "a car stops behind the courier's truck in its lane (gap %.1f m, speed %.1f)" % [gap, float(rec.v)])
		game.truck.set_physics_process(true)
		game.truck.place(game.world.database.location_pos(&"villa_square") + Vector3(40, 0, 6), Vector3.FORWARD)
	# go away: all gone
	cam.global_position = c + Vector3(3000, 200, 0)
	game.bike.global_position = cam.global_position
	var old: Array = tr.vehicles.duplicate()
	await get_tree().create_timer(1.0).timeout
	var stayed := 0
	for v in old: if tr.vehicles.has(v): stayed += 1
	var far := 0
	for v in tr.vehicles: if (v.pos as Vector3).distance_to(cam.global_position) > OuterTraffic.DESPAWN + 50.0: far += 1
	check(stayed == 0 and far == 0, "traffic despawns when the viewer leaves (%d of %d stayed; %d spawned, %d despawned)" % [stayed, old.size(), tr.spawned, tr.despawned])
	print("    traffic paths %.1f ms total for %d vehicles" % [tr.paths_ms, tr.spawned])
	cam.queue_free()
	game.bike.global_position = Vector3(0, 60, 0)


# ---------------------------------------------------------------- boats
func _boats() -> void:
	var total := 0; var wet := true; var with_routes := 0
	for id in ["isola_serena", "puerto_alto", "sarmada"]:
		var hb := boats.prepare_now(id)
		check(not hb.is_empty() and not (hb.slots as Array).is_empty(), "%s has moorings off its quay (%d)" % [id, (hb.get("slots", []) as Array).size()])
	var per := {}
	for b in boats.boats:
		per[b.harbour.id] = str(per.get(b.harbour.id, "")) + ("+" if (b.route as PackedVector3Array).size() >= 2 else "-")
	print("    boat routes by harbour: ", per)
	for b in boats.boats:
		if (b.route as PackedVector3Array).size() < 2: continue
		with_routes += 1
		wet = wet and boats.route_on_water(b.route)
		for k in 40:
			var pose := boats.pose_at(b, k * 17.3)
			var p: Vector3 = pose[0]
			total += 1
			if game.world.outer.height_at(p.x, p.z) >= -2.0: wet = false
	check(with_routes >= 10, "fishing boats have routes out to their grounds (%d)" % with_routes)
	check(wet, "boats stay on water deeper than 2 m (%d poses checked)" % total)


# ---------------------------------------------------------------- enemies
func _enemies() -> void:
	var enc: EncounterDirector = game.encounters
	var bandit := &""; var pirate := &""
	for id in enc.camps:
		if enc.camps[id].kind == &"bandit" and bandit == &"": bandit = id
		if enc.camps[id].kind == &"pirate" and pirate == &"": pirate = id
	for id in [bandit, pirate]:
		enc.spawn_camp(id)
	await get_tree().physics_frame
	var people := true; var styled := true; var gear := true; var guns := 0; var gripped := 0
	for id in [bandit, pirate]:
		for e: Enemy in enc.enemies_of(id):
			people = people and e.model.is_person()
			styled = styled and e.model.look.get("style") == e.kind
			gear = gear and e.model.head.get_node_or_null("Outfit") != null
			if e.model.long_gun != null:
				guns += 1
				e.model.gun_ads = 1.0
				for k in 20: e.model.animate("idle", 0.0, 0.05, true, 1.0, 0.0)
				var grip: Vector3 = e.model.long_gun.get_node("GripR").global_position
				if e.model.hand_r.global_position.distance_to(grip) < 0.12: gripped += 1
	check(people, "bandits and pirates are CharacterLook townsfolk bodies")
	check(styled, "their looks are in the bandit / pirate styles")
	check(gear, "EnemyOutfit's gear (hats, bandanas, sashes, earrings) is on them")
	check(guns > 0 and gripped == guns, "long guns are held through the rifle IK (%d of %d hands on the grip)" % [gripped, guns])
	var b0: Enemy = enc.enemies_of(bandit)[0]
	var p0: Enemy = enc.enemies_of(pirate)[0]
	check(b0.model.look.hair != "headscarf" and p0.model.look.hair == "headscarf", "pirates wear headscarves, bandits their hats")
	var duster: Color = b0.model.look.top_color
	check(duster.get_luminance() < 0.45, "bandits wear dark dusters (luminance %.2f), readable at range" % duster.get_luminance())
	for id in [bandit, pirate]: enc.despawn_camp(id)


# ---------------------------------------------------------------- urgent supply
func _urgent_supply() -> void:
	var econ: ColonyEconomy = game.colony.economy
	var urgent: UrgentSupply = econ.urgent
	var gm := game.gm
	gm.coins += 500
	var why := econ.found("isola_serena", true)
	var t := econ.town("isola_serena")
	check(t.founded, "Isola Serena is chartered for the test (%s)" % why)
	for item in EconomyCatalog.FOODS + EconomyCatalog.GOODS: t.stock[item] = 30
	t.needs.food = 1.0; t.needs.goods = 1.0
	urgent.refresh()
	check(urgent.offers.is_empty(), "a well-stocked colony posts no urgent job")
	for f in EconomyCatalog.FOODS: t.stock[f] = 0
	t.needs.food = 0.3
	urgent.refresh()
	check(not urgent.offers.is_empty(), "a colony short of food posts an urgent supply job")
	var o: Dictionary = urgent.offers[0] if not urgent.offers.is_empty() else {}
	print("    offer: ", o, " -> ", urgent.hud_text())
	check(String(o.get("item", "")) in EconomyCatalog.FOODS and int(o.get("qty", 0)) >= 10 and String(o.get("from", "")) != "isola_serena", "the job asks for a food from another town")
	var before := gm.coins
	var route_index := gm.job_index
	check(urgent.accept() == "", "the courier takes the job")
	var job := gm.current_job()
	check(job != null and String(job.id).begins_with(UrgentSupply.PREFIX) and job.vehicle == "truck", "it is the courier's current job, carried by truck")
	# pick up with the truck (the bike cannot)
	game.bike.place(gm.target_position(), Vector3.FORWARD)
	_ground_at(game.bike)
	await get_tree().create_timer(0.9).timeout
	check(not gm.carrying, "the bike cannot take on the urgent load")
	game.bike.place(gm.target_position() + Vector3(30, 0, 0), Vector3.FORWARD)
	for i in 120:
		await get_tree().physics_frame
		if game.rider.is_on_foot() or game.rider.request_dismount(): break
	for i in 30: await get_tree().physics_frame
	game.truck.place(game.player.global_position + Vector3(1.8, 0, 0), Vector3.FORWARD)
	for i in 120:
		await get_tree().physics_frame
		if game.rider.request_mount(): break
	check(game.rider.active_vehicle() == game.truck, "the courier drives the cargo truck")
	game.truck.place(gm.target_position(), Vector3.FORWARD)
	_ground_at(game.truck)
	await get_tree().create_timer(1.2).timeout
	check(gm.carrying and gm.stage == DeliverySystem.Stage.TO_DROPOFF, "the truck loads the supplies")
	var saved := gm.save_state()
	gm.load_state(saved)
	check(gm.carrying and String(gm.current_job().id) == String(job.id), "an urgent run in progress survives save / load")
	var stock_before := t.count(String(o.item))
	game.truck.place(gm.target_position(), Vector3.FORWARD)
	_ground_at(game.truck)
	await get_tree().create_timer(1.5).timeout
	check(gm.coins == before + int(o.reward), "delivery pays the reward with its bonus (%d -> %d, reward %d)" % [before, gm.coins, int(o.reward)])
	check(t.count(String(o.item)) >= stock_before + int(o.qty) - 1, "the colony receives the goods (%d %s)" % [t.count(String(o.item)), o.item])
	check(gm.job_index == route_index and not String(gm.current_job().id if gm.current_job() else "").begins_with(UrgentSupply.PREFIX), "the regular route resumes where it was")


func _ground_at(node: Node3D) -> void:
	game.world.set_focus(node)
	game.world.outer.focus = node
	game.world.outer.refresh_collision()
	game.world.streamer.load_all_pending()
	if node is Vehicle: (node as Vehicle).place(node.global_position, Vector3.FORWARD)
