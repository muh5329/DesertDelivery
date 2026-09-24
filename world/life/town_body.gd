class_name TownBody
extends Node3D
## A pooled body for an outer-town Townsperson: a RiderModel dressed by CharacterLook (its near
## and far meshes handed over by TownFolk as PersonBuilder finishes them), a hand prop and a
## crate, and a small collider while close to the courier. Bodies are reused: `assign` swaps the
## look (meshes only; the rig stays), `release` hides it for the next person.

const PROP_KINDS := ["vend", "browse", "hoe", "fish", "mend", "shopkeep", "work", "carry", "chop"]

var model: RiderModel
var person: Townsperson
var near := false                  # near-eligible (one of the closest ~40)
var showing_near := false
var pose := ""
var seated := false
var anim_t := 0.0                  # seconds since the last pose update
var move_t := 0.0                  # seconds since the last move (far walkers move at 10-20 Hz)
var check_t := 0.0                 # countdown to the next mesh / collider check
var last_pos := Vector3.INF
var _prop_root: Node3D
var _prop_kind := ""
var _crate: MeshInstance3D
var _collider: StaticBody3D
var _shadow := true

static var _mats: Dictionary = {}


static func _mat(key: String, c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key): _mats[key] = Mats.solid(c, rough, metal)
	return _mats[key]


func _init() -> void:
	model = RiderModel.new()
	model.manual_meshes = true


## First use: the model enters the tree with a look (so it builds the townsperson rig).
func setup(look: Dictionary) -> void:
	model.look = look
	add_child(model)
	model.enable_resident_lod()          # (the skin is flushed after each pose, not every frame)
	_prop_root = Node3D.new(); _prop_root.name = "Prop"
	model.hand_r.add_child(_prop_root)
	_crate = MeshInstance3D.new(); _crate.name = "Crate"
	var bm := BoxMesh.new(); bm.size = Vector3(0.46, 0.32, 0.36); _crate.mesh = bm
	_crate.material_override = _mat("crate", Color("9a7448"))
	_crate.position = Vector3(0, 1.1, -0.36)
	_crate.visible = false
	add_child(_crate)
	_collider = StaticBody3D.new(); _collider.name = "Body"
	_collider.collision_layer = 0; _collider.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.27; cap.height = 1.65
	cs.shape = cap; cs.position.y = 0.84
	_collider.add_child(cs)
	add_child(_collider)


func assign(p: Townsperson, look: Dictionary) -> void:
	person = p
	p.body = self
	if model.is_inside_tree(): model.set_look(look)
	else: setup(look)
	model.set_person_meshes(null, null)
	showing_near = false
	visible = false
	# staggered, so a crowd handed out in one pass does not pose all in the same frame
	var k := float(p.index % 11)
	pose = ""; seated = false; anim_t = k * 0.1; check_t = k * 0.011; move_t = 1.0; last_pos = Vector3.INF
	_set_prop("")
	_crate.visible = false


func release() -> void:
	if person != null and person.body == self: person.body = null
	person = null
	visible = false
	set_collision(false)


func set_collision(on: bool) -> void:
	if _collider: _collider.collision_layer = 16 if on else 0


func set_shadows(on: bool) -> void:
	if on == _shadow: return
	_shadow = on
	for mi: MeshInstance3D in model.person_mesh_instances():
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Swap in whatever meshes exist; draw the near one only when it is there and wanted.
func refresh_meshes(look: Dictionary, want_near: bool) -> bool:
	var meshes := model.person_meshes()
	var far_mesh: Mesh = meshes[1]
	var near_mesh: Mesh = meshes[0]
	var changed := false
	if far_mesh == null:
		far_mesh = PersonBuilder.part(look, false)
		changed = far_mesh != null
	if want_near and near_mesh == null:
		near_mesh = PersonBuilder.part(look, true)
		changed = changed or near_mesh != null
	if changed: model.set_person_meshes(near_mesh, far_mesh)
	var show_near := want_near and near_mesh != null
	if show_near != showing_near or changed:
		showing_near = show_near
		model.show_person_level(show_near)
	return far_mesh != null


# ---------------------------------------------------------------- poses
## One pose update: `walking` (with the crate for a dockworker's loaded leg), or the spot's pose.
func animate(walking: bool, carrying: bool, spot_pose: String, seat_h: float, delta: float, clock: float) -> void:
	var m := model
	pose = "walk" if walking else spot_pose
	if walking:
		if seated: _stand_up()
		m.animate("walk", person.speed, delta)
		if carrying:
			m.arm_l.rotation.x = 1.05; m.arm_r.rotation.x = 1.05
			m.arm_l.rotation.z = -0.25; m.arm_r.rotation.z = 0.25
			m.arm_l.get_node("Elbow").rotation.x = 0.5; m.arm_r.get_node("Elbow").rotation.x = 0.5
		_crate.visible = carrying
		_set_prop("")
		m.sync_resident_pose()
		return
	_crate.visible = carrying
	var phase := float(person.seed % 97) * 0.37
	var t := clock + phase
	if spot_pose == "sit":
		if not seated:
			seated = true
		m.animate("idle", 0.0, delta)
		m.pose_seated(seat_h)
		m.head.rotation.y = sin(t * 0.4) * 0.35
		m.head.rotation.x = 0.05
		if sin(t * 0.31) > 0.55:
			m.arm_r.rotation.x = 0.9 + sin(t * 1.7) * 0.25       # talking with the hands / a cup
			m.arm_r.get_node("Elbow").rotation.x = 1.3
		_set_prop("")
		m.sync_resident_pose()
		return
	if seated: _stand_up()
	m.animate("idle", 0.0, delta)
	match spot_pose:
		"vend":
			m.arm_r.rotation.x = 0.35 + maxf(0.0, sin(t * 1.1)) * 0.75
			m.arm_r.get_node("Elbow").rotation.x = 0.8
			m.arm_l.rotation.x = 0.3
			m.head.rotation.y = sin(t * 0.5) * 0.45
			_set_prop("")
		"browse":
			m.torso.rotation.x = -0.12
			m.head.rotation.x = 0.3
			m.head.rotation.y = sin(t * 0.6) * 0.3
			m.arm_l.rotation.x = 0.25; m.arm_l.get_node("Elbow").rotation.x = 1.2
			m.arm_r.rotation.x = 0.2 + maxf(0.0, sin(t * 0.9)) * 0.7
			_set_prop("basket")
		"chat":
			m.arm_r.rotation.x = 0.2 + maxf(0.0, sin(t * 1.3)) * 0.6
			m.arm_r.get_node("Elbow").rotation.x = 0.9
			m.arm_l.rotation.x = 0.1 + maxf(0.0, sin(t * 0.9 + 1.0)) * 0.3
			m.head.rotation.y = sin(t * 0.45) * 0.2
			m.head.rotation.x = sin(t * 0.8) * 0.06
			_set_prop("")
		"shopkeep":
			var sweep := sin(t * 0.21) > 0.0
			if sweep:
				m.torso.rotation.x = -0.18
				m.arm_r.rotation.x = 0.65 + sin(t * 2.6) * 0.3
				m.arm_l.rotation.x = 0.55 + sin(t * 2.6) * 0.3
				m.arm_r.get_node("Elbow").rotation.x = 0.4
				_set_prop("broom")
			else:
				m.arm_l.rotation.z = 0.5; m.arm_r.rotation.z = -0.5
				m.arm_l.get_node("Elbow").rotation.x = 1.6; m.arm_r.get_node("Elbow").rotation.x = 1.6
				m.arm_l.rotation.x = 0.35; m.arm_r.rotation.x = 0.35
				m.head.rotation.y = sin(t * 0.4) * 0.5
				_set_prop("")
		"mend":
			m.torso.rotation.x = -0.1
			m.arm_r.rotation.x = 1.0 + sin(t * 3.1) * 0.18
			m.arm_l.rotation.x = 1.0 + sin(t * 3.1 + 1.2) * 0.15
			m.arm_r.get_node("Elbow").rotation.x = 0.7; m.arm_l.get_node("Elbow").rotation.x = 0.7
			m.head.rotation.x = 0.35
			_set_prop("")
		"fish":
			m.arm_r.rotation.x = 0.85 + sin(t * 0.5) * 0.05
			m.arm_l.rotation.x = 0.75
			m.arm_l.rotation.z = -0.3
			m.arm_r.get_node("Elbow").rotation.x = 0.6; m.arm_l.get_node("Elbow").rotation.x = 0.9
			_set_prop("rod")
		"hoe":
			var swing := sin(t * 1.6)
			m.torso.rotation.x = -0.28 - swing * 0.08
			m.arm_r.rotation.x = 0.7 + swing * 0.45
			m.arm_l.rotation.x = 0.6 + swing * 0.45
			m.arm_r.get_node("Elbow").rotation.x = 0.4; m.arm_l.get_node("Elbow").rotation.x = 0.5
			_set_prop("hoe")
		"work", "carry":
			m.torso.rotation.x = -0.2
			m.arm_r.rotation.x = 0.6 + sin(t * 2.0) * 0.3
			m.arm_l.rotation.x = 0.45 + sin(t * 2.0 + 0.8) * 0.2
			m.arm_r.get_node("Elbow").rotation.x = 0.5
			_set_prop("axe" if person.occupation == "woodcutter" else ("" if spot_pose == "carry" else "tool"))
		_:
			_set_prop("")
	if carrying:
		m.arm_l.rotation.x = 1.05; m.arm_r.rotation.x = 1.05
		m.arm_l.rotation.z = -0.25; m.arm_r.rotation.z = 0.25
	m.sync_resident_pose()


func _stand_up() -> void:
	seated = false
	var m := model
	m.root.position = Vector3(0, RiderModel.HIP_H, 0)
	m.root.rotation = Vector3.ZERO
	for limb in [m.leg_l, m.leg_r, m.arm_l, m.arm_r]:
		limb.rotation = Vector3.ZERO


func _set_prop(kind: String) -> void:
	if kind == _prop_kind: return
	_prop_kind = kind
	for c in _prop_root.get_children(): c.queue_free()
	var wood := _mat("wood", Color(.34, .20, .10))
	var metal := _mat("metal", Color(.40, .44, .43), .4, .6)
	match kind:
		"hoe":
			_prop_root.add_child(Mats.cylinder(.016, 1.3, wood, Vector3(0, .1, -.05), Vector3(15, 0, 0)))
			_prop_root.add_child(Mats.box(Vector3(.2, .05, .12), metal, Vector3(0, -.55, .05)))
		"axe":
			_prop_root.add_child(Mats.cylinder(.018, .75, wood, Vector3(0, .15, 0)))
			_prop_root.add_child(Mats.box(Vector3(.05, .14, .18), metal, Vector3(0, .5, -.07)))
		"broom":
			_prop_root.add_child(Mats.cylinder(.014, 1.25, wood, Vector3(0, -.1, 0)))
			_prop_root.add_child(Mats.box(Vector3(.26, .16, .07), _mat("straw", Color("c9a55a")), Vector3(0, -.75, 0)))
		"rod":
			_prop_root.add_child(Mats.cylinder(.011, 2.4, wood, Vector3(0, .55, -.9), Vector3(-62, 0, 0)))
		"basket":
			_prop_root.add_child(Mats.cylinder(.13, .14, _mat("wicker", Color("b58a52")), Vector3(0, -.12, 0), Vector3.ZERO, 10))
		"tool":
			_prop_root.add_child(Mats.box(Vector3(.05, .24, .03), metal, Vector3(0, -.06, 0)))
