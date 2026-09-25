extends Node
var failures:=0
var checks:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(label)
	else: print("PASS ",label)
func _ready() -> void: call_deferred("run")
func run() -> void:
	var colony:=ColonySystem.new(); add_child(colony); colony.set_physics_process(false)
	colony._test_height=func(_p): return 2.0
	var a:=Resident.new(); a.id="worker_a"; a.name="Ada"; a.position=Vector3(0,2.08,0)
	var b:=Resident.new(); b.id="worker_b"; b.name="Ben"; b.position=a.position
	colony.warehouse_position=a.position; colony._initialize([a,b]); colony.warehouse={"wood":20}
	var source:=colony._add_source("wood","wood",Vector3(8,2.08,0),false); source.stock=7
	check(colony.designate("Woodcutter",source.position,6),"Matching resource zone accepted")
	colony.assign_role(a.id,"Woodcutter"); colony.assign_role(b.id,"Woodcutter"); colony.tick(.5)
	check(colony.orders[a.id].amount==5 and colony.orders[b.id].amount==2 and colony.reserved("wood","wood")==7,"Concurrent gathering reserves stock exactly")
	var before:=colony.save_state(); check(colony.accepts(before),"Pending route snapshot validates")
	for i in range(400): colony.tick(.05)
	check(source.stock==0 and int(colony.warehouse.wood)==27 and colony.orders.is_empty(),"Workers physically gather and deliver conserved stock")
	check(colony.place_site("Farm",Vector3(20,2.08,12)),"Farm blueprint placement")
	colony.assign_role(a.id,"Builder"); colony.assign_role(b.id,"Builder")
	for i in range(900): colony.tick(.05)
	var site: ColonySite=colony.sites.values()[0]
	check(site.built and site.field!=null and int(colony.warehouse.wood)==17,"Two deliveries consume ten timber and create renewable farm")
	site.field.stock=0; colony.tick(15.0); check(site.field.stock==20,"Renewable farm produces stock over time")
	colony.assign_role(a.id,"Unemployed"); colony.assign_role(b.id,"Unemployed")
	colony._add_source("ore","ore",Vector3(12,2.08,0),false)
	colony.designate("Miner",Vector3(12,2.08,0),6); colony.assign_role(a.id,"Miner")
	for i in range(500):
		colony.tick(.05)
		if colony.orders.get(a.id,{}).get("acquired",false): break
	check(colony.orders[a.id].acquired,"Test reached in-flight cargo")
	var snapshot:=colony.save_state(); var encoded: Dictionary=JSON.parse_string(JSON.stringify(snapshot))
	check(colony.load_state(encoded),"JSON roundtrip restores active cargo and generated farm")
	colony.assign_role(a.id,"Unemployed")
	for i in range(400): colony.tick(.05)
	check(int(colony.warehouse.get("ore",0))==5 and colony.orders.is_empty(),"Disabling worker finishes cargo once after restore")
	var invalid:=colony.save_state(); invalid.orders={a.id:{"phase":"deliver","item":"wood","amount":999}}
	var committed:=colony.save_state(); check(colony.load_state(invalid) and not colony.load_report().is_empty() and colony.save_state()==committed,"Invalid core snapshot is reported and not applied; the rest still loads")
	check(int(committed.version)==ColonySystem.SAVE_VERSION and committed.has("economy"),"Colony snapshot is version 2 with the economy")
	var v1:=committed.duplicate(true); v1.erase("economy"); v1.version=1
	check(colony.load_state(JSON.parse_string(JSON.stringify(v1))) and int(colony.warehouse.get("ore",0))==int(committed.warehouse.get("ore",0)),"Version 1 snapshot still loads; its warehouse is the core stockpile")
	check(colony.economy.town("core").stock==colony.warehouse,"Core colony stockpile is the colony warehouse")
	check(colony.roads.add_stroke(PackedVector3Array([Vector3(0,2,0),Vector3(12,2,0)]),"Road"),"Road stroke snaps to connected four-metre cells")
	check(colony.roads.preferences.get(Vector2i(1,0))==1.0 and colony.roads.erase_at(Vector3(4,2,0)),"Road preference applied and erase removes it")
	check(colony.manual_order(a.id,Vector3(4,2.08,4)),"Manual move order accepts existing resident")
	colony.set_paused(true); var position:=a.position; colony.tick(10); check(a.position==position,"Pause holds managed movement and production")
	colony.set_paused(false)
	for i in range(600): colony.tick(.05)
	check(a.position.distance_to(Vector3(4,2.08,4))<.01 and colony.orders.is_empty(),"Manual order routes to destination then releases resident")
	var queued:=Time.get_ticks_usec()
	for i in range(100): colony.replan_workers()
	check(Time.get_ticks_usec()-queued<50000,"Replanning only queues work")
	colony.free(); print("COLONY TESTS ",checks," checks / ",failures," failures"); get_tree().quit(1 if failures else 0)
