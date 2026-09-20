class_name PivotSkinBridge
extends Node
## Drives optional skinned clothing from the existing prop/animation pivots.
## Bind in the neutral pose, before changing character proportions or seating.
## Bone names are explicit: renamed Elbow/Hand/Knee nodes need no name inference.

var _skeleton: Skeleton3D
var _pivots: Dictionary = {}
var _offsets: Dictionary = {}
var _order: Array[int] = []
var _parents: Array[int] = []
var _globals: Array[Transform3D] = []


func _init() -> void:
	# ResidentActor changes occupation poses after calling RiderModel.animate().
	# Synchronize after those ordinary process callbacks, before rendering.
	process_priority = 100
	set_process(false)


## Returns false without retaining a partial binding if any supplied bone/pivot
## is missing. An empty map is a valid disabled bridge for legacy models.
func bind(skeleton: Skeleton3D, bone_pivots: Dictionary) -> bool:
	clear()
	if bone_pivots.is_empty(): return true
	if not is_instance_valid(skeleton) or not skeleton.is_inside_tree(): return false
	if is_zero_approx(skeleton.global_transform.basis.determinant()): return false
	for bone_name in bone_pivots:
		var pivot = bone_pivots[bone_name]
		if not pivot is Node3D or not is_instance_valid(pivot): return false
		if not pivot.is_inside_tree(): return false
		if is_zero_approx(pivot.global_transform.basis.determinant()): return false
		if skeleton.find_bone(String(bone_name)) < 0: return false
	_skeleton = skeleton
	var count := skeleton.get_bone_count()
	_parents.resize(count)
	_globals.resize(count)
	# Parent indices need not precede child indices in imported rigs.
	for index in range(count): _parents[index] = skeleton.get_bone_parent(index)
	for index in skeleton.get_parentless_bones(): _append_branch(index)
	for bone_name in bone_pivots:
		var index := skeleton.find_bone(String(bone_name))
		var pivot: Node3D = bone_pivots[bone_name]
		_pivots[index] = pivot
		_offsets[index] = pivot.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(index)
	set_process(true)
	sync_pose()
	return true


func clear() -> void:
	set_process(false)
	_skeleton = null
	_pivots.clear()
	_offsets.clear()
	_order.clear()
	_parents.clear()
	_globals.clear()


func _append_branch(index: int) -> void:
	_order.append(index)
	for child in _skeleton.get_bone_children(index): _append_branch(child)


func _process(_delta: float) -> void:
	sync_pose()


## The skeleton is dedicated to these pivots; do not concurrently animate its
## mapped bones with AnimationPlayer or SkeletonModifier3D. Unmapped bones retain
## their local pose. Call bind again after changing rest transforms or topology.
func sync_pose() -> void:
	if not is_instance_valid(_skeleton):
		clear()
		return
	if _skeleton.get_bone_count() != _parents.size():
		clear()
		return
	if is_zero_approx(_skeleton.global_transform.basis.determinant()): return
	var inverse := _skeleton.global_transform.affine_inverse()
	for index in _order:
		var parent := _parents[index]
		var parent_global := Transform3D.IDENTITY if parent < 0 else _globals[parent]
		var pose := _skeleton.get_bone_pose(index)
		if _pivots.has(index):
			var pivot = _pivots[index]
			if not is_instance_valid(pivot):
				clear()
				return
			var desired: Transform3D = inverse * pivot.global_transform * _offsets[index]
			if is_zero_approx(parent_global.basis.determinant()): return
			pose = parent_global.affine_inverse() * desired
			# Godot bone poses are full local transforms, not rest-relative deltas.
			_skeleton.set_bone_pose(index, pose)
			# Use the engine's TRS decomposition for descendants as well. Skeleton3D
			# cannot represent shear introduced by rotated nonuniform scales.
			pose = _skeleton.get_bone_pose(index)
		_globals[index] = parent_global * pose
