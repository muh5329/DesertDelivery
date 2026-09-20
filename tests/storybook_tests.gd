extends Node
func _ready() -> void:
	var original:=StandardMaterial3D.new()
	var painted:=Storybook.material(original)
	assert(Storybook.material(painted)==painted,"already painted material must retain identity")
	for index in range(Storybook.CACHE_LIMIT+20):
		var source:=StandardMaterial3D.new(); source.albedo_color=Color(float(index)/300.0,.5,.3)
		Storybook.material(source)
	assert(Storybook._materials.size()<=Storybook.CACHE_LIMIT,"material cache bound")
	var transparent:=StandardMaterial3D.new(); transparent.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	var preserved: StandardMaterial3D=Storybook.material(transparent)
	assert(preserved.transparency==transparent.transparency and preserved.albedo_texture==null,"glass remains unpainted")
	assert(Storybook.material(preserved)==preserved,"transparent materials are also idempotent")
	print("STORYBOOK MATERIAL TESTS: PASS")
	get_tree().quit()
