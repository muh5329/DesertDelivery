extends Node
## Dev probe: where the Jeep's test beach is (tests/beach_finder.gd), with the raw crossings.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var game := Game.current
	var t: Terrain = game.world.terrain
	await get_tree().physics_frame
	var n := 0
	for a in range(0, 360, 6):
		var dir := Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a)))
		var last_land := -1.0
		var r := 150.0
		while r < 1900.0:
			var p := dir * r
			var h := t.height_at(p.x, p.z)
			var wl := t.water_level_at(p.x, p.z)
			if h > wl + 0.2:
				last_land = r
			elif last_land > 0.0 and h < wl - 2.0:
				var steep := 0.0; var hi := -INF; var lo := INF; var town := false
				var prev := t.height_at(dir.x * (last_land - 30.0), dir.z * (last_land - 30.0))
				var k := last_land - 28.0
				var prof := ""
				while k <= r:
					var q := dir * k
					var hq := t.height_at(q.x, q.z)
					steep = maxf(steep, absf(hq - prev)); prev = hq
					if k < last_land: hi = maxf(hi, hq); lo = minf(lo, hq); town = town or t.biome_at(q.x, q.z) == Terrain.Biome.TOWN
					prof += " %.1f" % hq
					k += 4.0
				print("  bearing %d shore %.0f deep %.0f (gap %.0f) wl %.2f steep %.2f land %.1f..%.1f town %s |%s" % [a, last_land, r, r - last_land, wl, steep, lo, hi, town, prof])
				n += 1
				last_land = -1.0
			r += 2.0
	print("crossings: %d" % n)
	var b: Dictionary = await load("res://tests/beach_finder.gd").find(game, game.jeep)
	print("BEACH: ", b)
	get_tree().quit()
