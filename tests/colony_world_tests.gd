extends Node
var failures:=0
func check(value: bool,label: String) -> void:
	print(("PASS " if value else "FAIL ")+label)
	if not value: failures+=1
func _ready() -> void: call_deferred("run")
func run() -> void:
	var game:=Game.current; game.use_scripted_controls(); game.life.set_physics_process(false); game.colony.set_physics_process(false)
	for i in range(3): await get_tree().physics_frame
	var colony:=game.colony
	var sources:=colony.sources(); check(sources.size()==12,"All original nearby resource clusters seeded on dry clear terrain")
	for source in sources: check(colony.walkable(source.position),"Resource accessible: "+source.source_id)
	var worker: Resident=game.life.residents[0]
	for r in game.life.residents:
		if r.position.distance_squared_to(colony.warehouse_position)<worker.position.distance_squared_to(colony.warehouse_position): worker=r
	print("COLONY nearest resident ",worker.name," at ",worker.position," warehouse ",colony.warehouse_position)
	var wood: ColonyResource
	for source in sources:
		if source.item_id=="wood" and (wood==null or source.position.distance_squared_to(worker.position)<wood.position.distance_squared_to(worker.position)): wood=source
	check(wood!=null,"Timber source present")
	print("ENDPOINTS ",worker.position," clear ",colony.walkable(worker.position)," snapped ",colony.roads.point(colony.roads.cell(worker.position))," clear ",colony.walkable(colony.roads.point(colony.roads.cell(worker.position)))," wood ",wood.position," snapped ",colony.roads.point(colony.roads.cell(wood.position))," clear ",colony.walkable(colony.roads.point(colony.roads.cell(wood.position)))," warehouseclear ",colony.walkable(colony.warehouse_position))
	colony.designate("Woodcutter",wood.position,6); colony.assign_role(worker.id,"Woodcutter")
	var initial:=int(colony.warehouse.wood); var start:=Time.get_ticks_usec(); var max_tick:=0
	for i in range(2400):
		var before:=Time.get_ticks_usec(); colony.tick(.1); max_tick=maxi(max_tick,Time.get_ticks_usec()-before)
		if int(colony.warehouse.wood)>initial: break
	print("COLONY gather wall_ms=",(Time.get_ticks_usec()-start)/1000.0," max_tick_ms=",max_tick/1000.0," status=",colony.statuses.get(worker.id)," position=",worker.position)
	check(int(colony.warehouse.wood)==initial+5,"Actual island resident completes gather→warehouse")
	colony.assign_role(worker.id,"Builder")
	var placed:=false
	for x in range(-32,33,4):
		for z in range(-32,33,4):
			var at:=colony.warehouse_position+Vector3(x,0,z)
			if colony.can_place(at,"Depot"):
				placed=colony.place_site("Depot",at); break
		if placed: break
	check(placed,"Clear real-world construction footprint found")
	if placed:
		var site: ColonySite=colony.sites.values()[0]
		for i in range(3000):
			colony.tick(.1)
			if site.built: break
		print("BUILD built=",site.built," warehouse=",colony.warehouse," orders=",colony.orders)
		check(site.built and int(colony.warehouse.wood)==20+(60-wood.stock)-10,"Actual resident delivers ten timber and completes construction")
		await get_tree().physics_frame
		check(not colony.walkable(site.position+Vector3(0,0,-4)),"Completed structure participates in collision")
	var saved:=colony.save_state(); check(colony.load_state(JSON.parse_string(JSON.stringify(saved))),"Actual world colony JSON persistence restores")
	check(JSON.stringify(colony.save_state().warehouse)==JSON.stringify(saved.warehouse) and colony.sites.size()==saved.sites.size(),"Warehouse and construction survive save roundtrip")
	print("COLONY WORLD failures=",failures); get_tree().quit(1 if failures else 0)
