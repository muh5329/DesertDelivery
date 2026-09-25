extends Node
## The architecture kit on show: a street per style (puerto, valdoro, sarmada, isola, campo, core)
## with every kind of that style, on a flat plaza floating 600 m up (no terrain in the way),
## built exactly as the streamer builds towns (BuildingKit.build_group, groups of six), then
## rendered from the street (1.7 m eye), from 20 m and from 120 m. Prints build timings.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --audio-driver Dummy --rendering-driver vulkan -- \
##       --facet --test=building_showcase --out=/tmp/showcase [--styles=puerto,isola] [--views=street,mid,air] [--nofog]
## Headless (timings only): godot --headless --path . -- --test=building_showcase --timing

const Y := 600.0
const ORIGIN := Vector3(0.0, Y, -14000.0)
const STREETS := {
	"puerto": [["rowhouse", 6, 3], ["rowhouse", 7, 4], ["shop", 8, 4], ["rowhouse", 6, 5], ["rowhouse", 5.5, 6], ["palazzo", 9, 5], ["rowhouse", 6.5, 3], ["house", 7, 2], ["shop", 12, 3],
		["|"], ["warehouse", 20, 2], ["tower", 9, 7], ["church", 14, 1], ["palazzo", 9.5, 4], ["shop", 7, 5], ["rowhouse", 6, 4], ["rowhouse", 6, 6]],
	"valdoro": [["house", 8, 2], ["house", 9, 3], ["shop", 7, 3], ["house", 10, 4], ["barn", 9, 2], ["house", 7, 2], ["granary", 8, 2],
		["|"], ["church", 9, 1], ["tower", 6, 7], ["barn", 12, 3], ["house", 8, 3], ["house", 11, 4]],
	"sarmada": [["house", 8, 2], ["house", 9, 3], ["shop", 8, 1], ["house", 10, 2], ["house", 7, 3], ["shop", 9, 2], ["granary", 9, 2], ["house", 12, 1],
		["|"], ["gate", 16, 3], ["wall", 30, 3], ["market_hall", 9.6, 2], ["tower", 9, 4], ["barn", 12, 2], ["house", 9, 3], ["citadel", 62, 3]],
	"isola": [["house", 6, 2], ["house", 7, 3], ["shop", 6, 2], ["house", 8, 3], ["house", 5.5, 2], ["house", 9, 3], ["boathouse", 6, 1], ["house", 7, 3],
		["|"], ["church", 9, 1], ["house", 8, 2], ["shop", 7, 3], ["barn", 8, 1], ["house", 6.5, 3], ["lighthouse", 7, 5]],
	"campo": [["house", 10, 2], ["shop", 9, 2], ["palazzo", 9, 3], ["house", 12, 3], ["barn", 14, 2], ["granary", 9, 2], ["granary", 8, 2],
		["|"], ["windmill", 9, 3], ["tower", 7, 5], ["gate", 14, 3], ["wall", 30, 3], ["house", 11, 2], ["shop", 10, 2]],
	"core": [["house", 7, 2], ["house", 6, 1], ["house", 8, 2], ["house", 6.5, 2], ["house", 7, 1],
		["|"], ["house", 7, 2], ["house", 6, 2], ["house", 8, 1]],
}
const DEPTH := {"rowhouse": 11.0, "shop": 12.0, "house": 10.0, "palazzo": 13.0, "warehouse": 18.0, "tower": 9.0, "church": 15.0,
	"barn": 11.0, "granary": 9.0, "gate": 9.0, "wall": 3.0, "market_hall": 12.6, "boathouse": 9.0, "windmill": 9.0,
	"citadel": 52.0, "lighthouse": 7.0}

var game: Game
var out := "/tmp/showcase"
var cams: Array = []
var idx := 0
var frame := 0
var settle := 20
var cam: Camera3D
var timing: Array = []


func _ready() -> void:
	game = Game.current
	out = game.cli.get_string("out", out)
	settle = game.cli.get_int("settle", 20)
	DirAccess.make_dir_recursive_absolute(out)
	var args := OS.get_cmdline_user_args()
	game.hud.visible = false
	var ui := game.get_node_or_null("UI")
	if ui:
		for c in ui.get_children():
			if c is CanvasLayer or c is Control: c.visible = false
	game.bike.visible = false; game.player.visible = false
	if "jeep" in game and game.jeep: game.jeep.visible = false; game.cart.visible = false
	if "--nofog" in args:
		for c in game.world.environment.get_children():
			if c is WorldEnvironment: c.environment.fog_enabled = false
	var styles: PackedStringArray = game.cli.get_string("styles", "puerto,valdoro,sarmada,isola,campo,core").split(",", false)
	var views: PackedStringArray = game.cli.get_string("views", "street,mid,air").split(",", false)
	var root := Node3D.new(); root.name = "Showcase"; add_child(root)
	_ground(root)
	BuildingKit.warm()
	var row := 0
	for style: String in ["puerto", "valdoro", "sarmada", "isola", "campo", "core"]:
		var z0 := ORIGIN.z + row * 90.0
		row += 1
		if not style in styles: continue
		var plots := _street(style, z0)
		BuildingKit.annotate(plots)
		for g in range(0, plots.size(), 6):
			var group: Array = plots.slice(g, g + 6)
			var cen := Vector3.ZERO
			for p in group: cen += Vector3(p.x, Y, p.z)
			cen /= group.size()
			var parent := Node3D.new(); root.add_child(parent); parent.global_position = cen
			var t0 := Time.get_ticks_usec()
			BuildingKit.build_group(parent, group, cen)
			timing.append([style, group.size(), (Time.get_ticks_usec() - t0) / 1000.0])
		var t1 := Time.get_ticks_usec()
		var lod := BuildingKit.build_lod(plots)
		print("  lod %s: %d plots %.1f ms, %d verts" % [style, plots.size(), (Time.get_ticks_usec() - t1) / 1000.0, lod.surface_get_array_len(0) if lod.get_surface_count() > 0 else 0])
		var x_end: float = plots[plots.size() - 1].x
		var a := ORIGIN + Vector3(-6, 1.7, z0 - ORIGIN.z)
		for v in views:
			match v:
				"street": cams.append([style + "_street", a + Vector3(-2, 0, 1.0), a + Vector3(30, 3.0, -3.5)])
				"street2": cams.append([style + "_street2", Vector3(x_end + 4, Y + 1.7, z0 - 0.5), Vector3(x_end - 30, Y + 4.0, z0 + 3.0)])
				"mid": cams.append([style + "_mid", Vector3(ORIGIN.x + 8, Y + 20, z0 + 34), Vector3(ORIGIN.x + 40, Y + 6, z0 - 6)])
				"air": cams.append([style + "_air", Vector3(ORIGIN.x + 40, Y + 120, z0 + 110), Vector3(ORIGIN.x + 45, Y, z0)])
				"close": cams.append([style + "_close", Vector3(ORIGIN.x + 12, Y + 2.5, z0 - 1.0), Vector3(ORIGIN.x + 16, Y + 5.5, z0 - 8.0)])
	_report()
	if "--timing" in args or cams.is_empty():
		get_tree().quit(); return
	cam = Camera3D.new(); cam.fov = game.cli.get_float("fov", 62.0); cam.far = 20000; cam.near = 0.05
	add_child(cam); cam.current = true
	game.world.terrain.set_view_camera(cam)
	game.bike.place(ORIGIN + Vector3(0, 2, 0), Vector3(0, 0, -1))
	game.world.set_focus(game.bike)
	_place()


func _street(style: String, z0: float) -> Array:
	var plots: Array = []
	var x := ORIGIN.x
	var side := 0
	var seed_v := 1000 + style.hash() % 1000
	for e in STREETS[style]:
		if e[0] == "|":
			side = 1; x = ORIGIN.x; continue
		var kind: String = e[0]
		var w: float = e[1]
		var d: float = DEPTH.get(kind, 10.0)
		if kind == "church" and style == "puerto": d = 22.0
		seed_v += 7919
		var yaw := 0.0 if side == 0 else 180.0
		var zc := z0 - 6.0 - d * 0.5 if side == 0 else z0 + 6.0 + d * 0.5
		var gap := 0.0 if style in ["puerto", "sarmada"] or kind == "wall" else 2.5
		if kind in ["tower", "church", "windmill", "gate", "warehouse", "barn", "granary", "boathouse", "market_hall", "citadel", "lighthouse"]: gap = 3.0
		var tags: Array = []
		if kind == "shop": tags.append("shopfront")
		if style == "isola" or (style == "sarmada" and kind == "house"): tags.append("terrace")
		if style == "campo" and kind == "shop": tags.append("arcade")
		var p := {"id": "show.%s.%d" % [style, plots.size()], "style": style, "kind": kind, "x": x + w * 0.5, "z": zc, "y": Y + 0.0,
			"yaw": yaw, "w": w, "d": d, "floors": int(e[2]), "seed": seed_v, "tags": tags, "ground_min": Y - 0.2}
		if style == "core":
			p.wall = [Color(.94, .92, .84), Color(.90, .67, .24), Color(.42, .73, .76), Color(.98, .95, .88)][plots.size() % 4]
			if plots.size() % 3 == 0: tags.append("terrace")
		plots.append(p)
		x += w + gap
	return plots


func _ground(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(3000, 3000)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.6, 0.56)
	var tex := "res://assets/terrain/cobble_alb_ht.png"
	if ResourceLoader.exists(tex):
		mat.albedo_texture = load(tex); mat.uv1_scale = Vector3(600, 600, 1)
	mat.roughness = 0.9
	mi.material_override = mat
	mi.position = Vector3(ORIGIN.x, Y, ORIGIN.z + 200)
	root.add_child(mi)


func _report() -> void:
	var tot := 0.0; var mx := 0.0; var n := 0; var plots := 0
	for t in timing:
		tot += t[2]; mx = maxf(mx, t[2]); n += 1; plots += t[1]
	if n > 0:
		print("BUILDING SHOWCASE: %d groups, %d plots, build_group avg %.2f ms, max %.2f ms (first call includes texture decode %.0f ms), modules built %.1f ms" % [n, plots, tot / n, mx, ArchMaterials.load_ms, ArchModules.build_ms])
		for t in timing: print("  group %s x%d: %.2f ms" % t)
	var outer: OuterWorld = game.world.outer
	if outer and outer.ok:
		var best: Dictionary = {}
		for t in outer.ground.plan.get("towns", []):
			if best.is_empty() or t.plots.size() > best.plots.size(): best = t
		if not best.is_empty():
			var plots_copy: Array = best.plots.duplicate(true)
			var t0 := Time.get_ticks_usec()
			BuildingKit.annotate(plots_copy)
			var ta := (Time.get_ticks_usec() - t0) / 1000.0
			t0 = Time.get_ticks_usec()
			var lod := BuildingKit.build_lod(plots_copy)
			print("  build_lod %s: %d plots in %.1f ms (annotate %.1f ms), %d vertices" % [best.id, plots_copy.size(), (Time.get_ticks_usec() - t0) / 1000.0, ta, lod.surface_get_array_len(0)])
			# real groups: time build_group over the first 30 groups of six in plan order
			var root := Node3D.new(); add_child(root)
			var times: Array = []
			BuildingKit.geom_ms = 0.0; BuildingKit.finish_ms = 0.0; BuildingKit.prof = {}
			for g in range(0, mini(plots_copy.size(), 180), 6):
				var group: Array = plots_copy.slice(g, g + 6)
				var cen := Vector3.ZERO
				for p in group: cen += Vector3(p.x, p.y, p.z)
				cen /= group.size()
				var parent := Node3D.new(); root.add_child(parent); parent.position = cen
				var t1 := Time.get_ticks_usec()
				BuildingKit.build_group(parent, group, cen)
				times.append((Time.get_ticks_usec() - t1) / 1000.0)
				if g < 18: print("    keys: ", BuildingKit.last_keys)
			times.sort()
			var s := 0.0
			for v in times: s += v
			print("  build_group on %s plots: %d calls, mean %.2f ms, median %.2f ms, p90 %.2f ms, max %.2f ms" % [best.id, times.size(), s / times.size(), times[times.size() / 2], times[int(times.size() * 0.9)], times[times.size() - 1]])
			var nodes := 0; var verts := 0; var mmis := 0
			for parent in root.get_children():
				for ch in parent.get_children():
					nodes += 1
					if ch is MeshInstance3D: verts += (ch as MeshInstance3D).mesh.surface_get_array_len(0)
					if ch is MultiMeshInstance3D: mmis += 1
			var pr := ""
			for k in BuildingKit.prof: pr += "%s %.2f  " % [k, BuildingKit.prof[k] / 1000.0 / times.size()]
			print("  profile per call (ms): ", pr)
			print("  split: geometry %.2f ms, nodes (mesh + multimesh + shapes) %.2f ms per call" % [BuildingKit.geom_ms / times.size(), BuildingKit.finish_ms / times.size()])
			print("  per group: %.1f nodes, %.1f MultiMeshInstances, %.0f merged vertices" % [float(nodes) / times.size(), float(mmis) / times.size(), float(verts) / times.size()])
			root.queue_free()


func _place() -> void:
	var from: Vector3 = cams[idx][1]; var at: Vector3 = cams[idx][2]
	cam.look_at_from_position(from, at, Vector3.UP)
	frame = 0


func _process(_d: float) -> void:
	if cams.is_empty() or cam == null: return
	frame += 1
	game.bike.global_position = ORIGIN + Vector3(0, 2, 0)
	if frame >= settle:
		var img := get_viewport().get_texture().get_image()
		var p := "%s/%s.png" % [out, cams[idx][0]]
		img.save_png(p)
		print("saved ", p, "  draw calls %d, objects %d, primitives %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		idx += 1
		if idx >= cams.size():
			get_tree().quit(); return
		_place()
