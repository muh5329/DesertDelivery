class_name EnemyWeapons
extends RefCounted
## The bad guys' firearms, built like the Garand (MeshKit lofts, shared meshes):
##   &"lever"    a lever-action carbine: straight-wrist stock, brass receiver, finger loop, the
##               tube magazine under the round barrel held by a band (bandits)
##   &"carbine"  a short bolt-action carbine with a turned-down bolt knob (pirates)
##   &"revolver" a single-action revolver: cylinder, round barrel, bird's-head grip
## Long guns carry the same markers as the Garand (Butt, GripR, GripL, Muzzle) so RiderModel's
## two-handed pose holds them; the revolver has a Muzzle and sits in the right hand.

const STATS := {
	&"lever":    {"mag": 7, "rate": 0.95, "reload": 2.6, "damage": 13.0, "accuracy": 0.60, "range": 90.0, "sound": &"lever_shot"},
	&"carbine":  {"mag": 5, "rate": 1.25, "reload": 2.4, "damage": 16.0, "accuracy": 0.66, "range": 110.0, "sound": &"lever_shot"},
	&"revolver": {"mag": 6, "rate": 0.62, "reload": 2.2, "damage": 9.0, "accuracy": 0.48, "range": 40.0, "sound": &"pistol_shot"},
}

static var _meshes: Dictionary = {}


static func is_long(kind: StringName) -> bool:
	return kind != &"revolver"


static func make(kind: StringName) -> Node3D:
	if _meshes.is_empty(): _build()
	var n := Node3D.new()
	n.name = String(kind).capitalize()
	var mi := MeshInstance3D.new(); mi.mesh = _meshes[kind]; n.add_child(mi)
	var marks: Array
	match kind:
		&"lever":
			marks = [["Muzzle", Vector3(0, 0, -0.99)], ["Butt", Vector3(0, -0.085, 0.0)], ["GripR", Vector3(0.015, -0.048, -0.24)], ["GripL", Vector3(0, -0.040, -0.56)]]
		&"carbine":
			marks = [["Muzzle", Vector3(0, 0, -0.96)], ["Butt", Vector3(0, -0.090, 0.0)], ["GripR", Vector3(0.017, -0.052, -0.25)], ["GripL", Vector3(0, -0.044, -0.58)]]
		_:
			marks = [["Muzzle", Vector3(0, 0.035, -0.225)]]
	for m in marks:
		var k := Node3D.new(); k.name = m[0]
		if m[0] == "GripR": k.transform = Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), m[1])
		elif m[0] == "GripL": k.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), m[1])
		else: k.position = m[1]
		n.add_child(k)
	return n


static func _build() -> void:
	# --- lever carbine -------------------------------------------------------------------
	var wood := MeshKit.new(); var brass := MeshKit.new(); var blue := MeshKit.new()
	wood.loft(MeshKit.sections([
		[-0.004, -0.030, -0.140, 0.019, 2.6], [-0.08, -0.028, -0.120, 0.0195, 2.5], [-0.17, -0.024, -0.090, 0.0175, 2.4],
		[-0.235, -0.020, -0.068, 0.0150, 2.2], [-0.285, -0.016, -0.058, 0.0150, 2.3], [-0.300, -0.012, -0.054, 0.0160, 2.6]], 3, 24))
	blue.loft([MeshKit.ring(0.003, 0, -0.085, 0.0195, 0.056, 2.8, 24), MeshKit.ring(-0.004, 0, -0.085, 0.0195, 0.056, 2.8, 24)])
	brass.loft(MeshKit.sections([[-0.296, 0.018, -0.050, 0.0165, 4.0], [-0.320, 0.020, -0.052, 0.0170, 4.5], [-0.46, 0.020, -0.052, 0.0170, 4.5], [-0.475, 0.016, -0.044, 0.0160, 3.0]], 2, 20))
	wood.loft(MeshKit.sections([[-0.48, 0.006, -0.040, 0.0170, 2.6], [-0.52, 0.008, -0.038, 0.0175, 2.6], [-0.66, 0.006, -0.034, 0.0165, 2.6], [-0.68, 0.004, -0.032, 0.0150, 2.4]], 2, 20))
	blue.tube(PackedVector3Array([Vector3(0, 0, -0.47), Vector3(0, 0, -0.99)]), [0.0115, 0.0100], 16)
	blue.tube(PackedVector3Array([Vector3(0, -0.024, -0.47), Vector3(0, -0.024, -0.93)]), 0.0080, 12)
	blue.loft(MeshKit.sections([[-0.905, 0.013, -0.034, 0.0125, 2.5], [-0.925, 0.013, -0.034, 0.0125, 2.5]], 1, 18))
	blue.block(Vector3(0, 0.016, -0.97), Vector3(0.003, 0.012, 0.012), 4.0)
	blue.block(Vector3(0, 0.020, -0.56), Vector3(0.016, 0.010, 0.010), 4.0)
	# the lever and its loop under the wrist
	blue.tube(MeshKit_path([Vector3(0, -0.050, -0.44), Vector3(0, -0.060, -0.40), Vector3(0, -0.062, -0.35), Vector3(0, -0.080, -0.31),
		Vector3(0, -0.105, -0.30), Vector3(0, -0.112, -0.26), Vector3(0, -0.098, -0.225), Vector3(0, -0.070, -0.235), Vector3(0, -0.058, -0.28)]), 0.0035, 8, Vector2(1.0, 1.6))
	blue.cyl(Vector3(0, 0.018, -0.33), Vector3(0, 0, 1), 0.0045, 0.03, 8)   # hammer
	var m := wood.commit(null, WeaponMats.wood(Color(0.40, 0.22, 0.11)))
	brass.commit(m, WeaponMats.brass())
	blue.commit(m, WeaponMats.blued())
	_meshes[&"lever"] = m

	# --- bolt carbine --------------------------------------------------------------------
	var w2 := MeshKit.new(); var s2 := MeshKit.new()
	w2.loft(MeshKit.sections([
		[-0.004, -0.034, -0.150, 0.019, 2.6], [-0.09, -0.030, -0.128, 0.0195, 2.5], [-0.18, -0.025, -0.095, 0.0175, 2.4],
		[-0.245, -0.020, -0.075, 0.0150, 2.2], [-0.29, -0.006, -0.060, 0.0175, 2.8], [-0.31, 0.002, -0.056, 0.0200, 3.2],
		[-0.50, 0.002, -0.052, 0.0200, 3.2], [-0.72, 0.000, -0.040, 0.0180, 3.0], [-0.80, -0.002, -0.036, 0.0165, 2.8]], 3, 24))
	w2.loft(MeshKit.sections([[-0.50, 0.018, -0.004, 0.016, 2.4], [-0.78, 0.017, -0.004, 0.015, 2.4]], 1, 18))
	s2.loft(MeshKit.sections([[-0.29, 0.016, -0.016, 0.0140, 3.0], [-0.30, 0.018, -0.018, 0.0150, 4.0], [-0.48, 0.018, -0.018, 0.0150, 4.0], [-0.50, 0.014, -0.014, 0.0135, 3.0]], 2, 18))
	s2.tube(PackedVector3Array([Vector3(0, 0, -0.50), Vector3(0, 0, -0.96)]), [0.0120, 0.0100], 16)
	s2.tube(PackedVector3Array([Vector3(0.012, 0.010, -0.33), Vector3(0.038, -0.004, -0.325), Vector3(0.046, -0.020, -0.33)]), 0.0035, 8)
	s2.tube(PackedVector3Array([Vector3(0.046, -0.020, -0.33), Vector3(0.047, -0.026, -0.33)]), 0.0080, 10)
	s2.loft(MeshKit.sections([[-0.79, 0.020, -0.038, 0.0185, 2.6], [-0.81, 0.020, -0.038, 0.0185, 2.6]], 1, 18))
	s2.loft(MeshKit.sections([[-0.62, 0.020, -0.046, 0.0205, 2.6], [-0.635, 0.020, -0.046, 0.0205, 2.6]], 1, 18))
	s2.block(Vector3(0, 0.017, -0.945), Vector3(0.0035, 0.014, 0.012), 4.0)
	s2.tube(MeshKit_path([Vector3(0, -0.056, -0.30), Vector3(0, -0.084, -0.31), Vector3(0, -0.086, -0.35), Vector3(0, -0.058, -0.38)]), 0.0024, 8, Vector2(1.0, 2.0))
	s2.loft([MeshKit.ring(0.003, 0, -0.092, 0.0195, 0.059, 2.8, 24), MeshKit.ring(-0.004, 0, -0.092, 0.0195, 0.059, 2.8, 24)])
	var m2 := w2.commit(null, WeaponMats.wood(Color(0.30, 0.17, 0.09)))
	s2.commit(m2, WeaponMats.blued())
	_meshes[&"carbine"] = m2

	# --- revolver (frame at the origin, barrel toward -Z, grip down) -----------------------
	var s3 := MeshKit.new(); var g3 := MeshKit.new()
	s3.tube(PackedVector3Array([Vector3(0, 0.035, -0.03), Vector3(0, 0.035, -0.225)]), 0.0085, 14)
	s3.tube(PackedVector3Array([Vector3(0, 0.035, 0.010), Vector3(0, 0.035, -0.035)]), 0.0185, 18)
	s3.loft(MeshKit.sections([[0.035, 0.050, 0.010, 0.0100, 3.0], [0.012, 0.054, 0.006, 0.0110, 4.0], [-0.040, 0.050, 0.014, 0.0110, 3.5], [-0.050, 0.046, 0.024, 0.0090, 2.5]], 2, 16))
	s3.block(Vector3(0, 0.060, 0.034), Vector3(0.006, 0.02, 0.012), 3.0)
	s3.tube(MeshKit_path([Vector3(0, 0.010, 0.005), Vector3(0, -0.012, 0.004), Vector3(0, -0.020, -0.018), Vector3(0, 0.006, -0.025)]), 0.0022, 8, Vector2(1.0, 1.8))
	g3.loft(MeshKit.sections([[0.045, 0.014, -0.090, 0.0135, 2.4, 0.0], [0.030, 0.016, -0.100, 0.0140, 2.4], [0.006, 0.016, -0.085, 0.0135, 2.4]], 3, 16))
	var m3 := s3.commit(null, WeaponMats.blued())
	g3.commit(m3, WeaponMats.wood(Color(0.45, 0.30, 0.16)))
	_meshes[&"revolver"] = m3


static func MeshKit_path(pts: Array) -> PackedVector3Array:
	return GarandModel._smooth_path(pts, 3)
