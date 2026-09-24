class_name OuterLife
extends Node3D
## Life in the outer world (ADR 0010's country round the core): the townsfolk of the five towns
## and fourteen hamlets (TownFolk), traffic on the outer roads (OuterTraffic) and the fishing
## boats off the ports (OuterBoats). Each only costs anything near the viewer; the clock is
## IslandLife's.

var towns: TownFolk
var traffic: OuterTraffic
var boats: OuterBoats


func setup(world: WorldManager, entities: EntityManager, life: IslandLife) -> void:
	name = "OuterLife"
	if world.outer == null or not world.outer.ok: return
	if "--no-outer-life" in OS.get_cmdline_user_args(): return      # (to measure without it)
	var t0 := Time.get_ticks_msec()
	towns = TownFolk.new(); add_child(towns); towns.setup(world, entities, life)
	traffic = OuterTraffic.new(); add_child(traffic); traffic.setup(world, entities, life)
	boats = OuterBoats.new(); add_child(boats); boats.setup(world, entities, life)
	print("[life] outer: %d towns and hamlets (%d people), traffic on %d roads, %d fishing boats in %d ms" % [towns.towns.size(),
		_people(), traffic.road_count(), boats.boats.size(), Time.get_ticks_msec() - t0])


func _people() -> int:
	var n := 0
	for id in towns.towns: n += TownPopulation.population_for((towns.towns[id] as TownPopulation)._plan)
	return n


func wait() -> void:
	if towns: towns.wait()
	if traffic: traffic.wait()
	if boats: boats.wait()
