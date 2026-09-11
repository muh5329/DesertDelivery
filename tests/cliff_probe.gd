extends Node
## Dumps a height/biome/road-distance grid of the NW sea-cliff area (the cliff_coast spots) so the
## cliff-wall layout in island.gd can be planned against the real terrain.
## Run: godot --headless --path . -- --test=cliff_probe
func _ready() -> void:
	var t: Terrain = Game.current.world.terrain
	var x0 := -640.0; var x1 := -400.0; var z0 := -400.0; var z1 := -40.0
	var step := 10.0
	if "--fine" in OS.get_cmdline_user_args():
		# 2 m strip across the west wall's foot: plans the coast bench / road spur
		x0 = -570.0; x1 = -520.0; z0 = -320.0; z1 = -140.0; step = 2.0
	# any rectangle: --x0=.. --x1=.. --z0=.. --z1=.. --step=.. (islet / headland planning)
	var cli: CliArgs = Game.current.cli
	x0 = cli.get_float("x0", x0); x1 = cli.get_float("x1", x1); z0 = cli.get_float("z0", z0); z1 = cli.get_float("z1", z1); step = cli.get_float("step", step)
	var header := "      "
	var x := x0
	while x <= x1:
		header += ("%6d" if step >= 5.0 else "%4d") % int(x); x += step
	print(header)
	var z := z0
	while z <= z1:
		var line := "%6d" % int(z)
		x = x0
		while x <= x1:
			var h := t.height_at(x, z)
			var rd := t.road_dist_at(x, z)
			var s := "%5.0f" % h
			if step < 5.0: s = "%3.0f" % h
			if rd < 6.0: s = "  R" + ("%2.0f" % h).strip_edges()
			line += (" " if step >= 5.0 else "") + s
			x += step
		print(line)
		z += step
	get_tree().quit()
