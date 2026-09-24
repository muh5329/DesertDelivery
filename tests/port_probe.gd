extends Node
## Probe: the sea grid along the plan's lanes (where does navigable water break?) and pirate
## coves' distances to the routes.
func _ready() -> void: call_deferred("run")
func run() -> void:
	var game := Game.current
	var econ := game.colony.economy
	econ.ensure_shipping()
	var sh := econ.shipping
	var t := game.world.terrain
	for lane in game.world.outer.plan().sea_lanes:
		var broken := PackedStringArray()
		for p in lane.points:
			var c := sh.cell_of(Vector2(p[0], p[1]))
			var k := c.y * ShippingNetwork.N + c.x
			if sh.nav[k] == 0: broken.append("(%d,%d) max %.1f h %.1f" % [p[0], p[1], sh.cell_max[k], t.height_at(p[0], p[1])])
		print(lane.id, ": ", lane.points.size(), " points, not navigable at ", broken.size(), ": ", " | ".join(broken.slice(0, 30)))
	for cid in sh.ports:
		print(cid, " approach ", sh.ports[cid].approach, " path ", sh.ports[cid].approach_path)
	for camp in econ._pirate_camps(): print("pirate ", camp.id, " ", camp.pos)
	get_tree().quit()
