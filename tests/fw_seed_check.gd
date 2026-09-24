extends SceneTree
## fixworld: which Sarmada plots does the kit plan in ochre adobe (vs whitewash)? (checks the
## generator's port of the kit's random sequence, used to pick plot seeds by colour)
func _initialize() -> void:
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.READ)
	var plots: Array = JSON.parse_string(f.get_as_text())
	for p in plots:
		var q := ArchStyles.plan(p)
		var ochre: bool = int(q.wall[0]) == ArchMaterials.ADOBE
		var pal: Array = ArchStyles.SARMADA_OCHRE if ochre else ArchStyles.SARMADA_WALLS
		print("SEED ", p.id, " ", "ochre" if ochre else "white", " ", pal.find(q.wall[1]))
	quit(0)
