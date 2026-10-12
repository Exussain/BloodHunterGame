class_name Ragdoll
extends Node
## Runtime physics ragdoll for the Meshy-rigged characters (militia and volatile).
##
## `Ragdoll.activate()` builds a PhysicalBoneSimulator3D with one PhysicalBone3D per
## major bone (pelvis, chest, head, arms, legs, feet) on the character's Skeleton3D,
## starts it from the pose the character is in right now (so there is no pop), and
## throws it with the given momentum. Once the body has come to rest it bakes the
## final pose into the skeleton and frees every physics body, so a corpse costs
## nothing afterwards.
##
## The Meshy skeleton is in centimetres under a 0.01-scaled Armature, which Jolt cannot
## simulate cleanly, so activation first rewrites that one skeleton in metres at unit
## scale (`_unscale_rig`). Every size below is in metres.
## Physics layers: bodies sit on LAYER and collide with MASK (the level) only.

## Emitted once, when the body has stopped moving and the physics bodies are gone.
signal settled

## Physics layer the ragdoll bodies sit on (layer 10). Nothing masks it, so the
## player and soldiers walk through corpses instead of being blocked or pushed.
const LAYER := 1 << 9
## Ragdoll bodies collide with the level geometry only (layer 1).
const MASK := 1
const SELF_PATH := "res://scripts/world/ragdoll.gd"

## Below these speeds (m/s, rad/s) for SETTLE_TIME seconds the body counts as at rest.
const SETTLE_SPEED := 0.2
const SETTLE_SPIN := 1.0
const SETTLE_TIME := 0.3
## Never freeze earlier than this, and always freeze after MAX_TIME (no endless twitching).
const MIN_TIME := 0.8
const MAX_TIME := 4.0
## After this long the joints stiffen (heavy damping), so a body that has landed
## stops creeping and jittering on its contacts instead of twitching for seconds.
const STIFFEN_TIME := 1.4
const DAMP := Vector2(0.15, 2.5)
const STIFF_DAMP := Vector2(2.0, 8.0)

## One entry per simulated bone, parents before children:
## bone, shape, end (bone the segment runs to), extend (fraction past `end`),
## radius (m), mass (kg), joint, swing/upper (deg), twist/lower (deg), flex direction.
## Box shapes use `size` (height, depth, width) in metres instead of `end`/`radius`;
## the head is a fixed-length capsule over the skull.
## A hinge's flex is the way the child swings when the joint bends (skeleton rest space,
## where the character faces +Z), so knees and elbows only fold the natural way.
const BODIES := [
	{bone = "Hips", shape = "box", top = "Spine01", size = Vector3(0.0, 0.22, 0.34), drop = 0.07, mass = 12.0},
	{bone = "Spine01", shape = "box", top = "neck", size = Vector3(0.0, 0.24, 0.36), mass = 14.0, joint = "cone", swing = 30.0, twist = 25.0},
	{bone = "neck", shape = "head", radius = 0.11, mass = 5.0, joint = "cone", swing = 28.0, twist = 60.0},
	{bone = "LeftArm", end = "LeftForeArm", radius = 0.055, mass = 2.5, joint = "cone", swing = 75.0, twist = 50.0},
	{bone = "LeftForeArm", end = "LeftHand", extend = 0.45, radius = 0.045, mass = 1.8, joint = "hinge", upper = 135.0, lower = 0.0, flex = Vector3(0, 0, 1)},
	{bone = "RightArm", end = "RightForeArm", radius = 0.055, mass = 2.5, joint = "cone", swing = 75.0, twist = 50.0},
	{bone = "RightForeArm", end = "RightHand", extend = 0.45, radius = 0.045, mass = 1.8, joint = "hinge", upper = 135.0, lower = 0.0, flex = Vector3(0, 0, 1)},
	{bone = "LeftUpLeg", end = "LeftLeg", radius = 0.085, mass = 8.0, joint = "cone", swing = 55.0, twist = 25.0},
	{bone = "LeftLeg", end = "LeftFoot", radius = 0.065, mass = 4.0, joint = "hinge", upper = 130.0, lower = 0.0, flex = Vector3(0, 0, -1)},
	{bone = "LeftFoot", end = "LeftToeBase", extend = 0.6, radius = 0.045, mass = 1.0, joint = "cone", swing = 25.0, twist = 10.0},
	{bone = "RightUpLeg", end = "RightLeg", radius = 0.085, mass = 8.0, joint = "cone", swing = 55.0, twist = 25.0},
	{bone = "RightLeg", end = "RightFoot", radius = 0.065, mass = 4.0, joint = "hinge", upper = 130.0, lower = 0.0, flex = Vector3(0, 0, -1)},
	{bone = "RightFoot", end = "RightToeBase", extend = 0.6, radius = 0.045, mass = 1.0, joint = "cone", swing = 25.0, twist = 10.0},
]
## How much of `upper_push` each body gets: the chest and head take the blow, the
## legs are swept the other way, so the body tips over instead of sliding.
const PUSH_WEIGHT := {
	"Hips": 0.25, "Spine01": 1.0, "neck": 1.15, "LeftArm": 0.9, "RightArm": 0.9,
	"LeftForeArm": 0.9, "RightForeArm": 0.9, "LeftUpLeg": -0.1, "RightUpLeg": -0.1,
	"LeftLeg": -0.3, "RightLeg": -0.3, "LeftFoot": -0.35, "RightFoot": -0.35,
}

var _skeleton: Skeleton3D
var _sim: PhysicalBoneSimulator3D
var _bones: Array[PhysicalBone3D] = []
var _hips: PhysicalBone3D
var _anim: AnimationPlayer
var _age := 0.0
var _still := 0.0
var _frozen := false
## Pelvis position in skeleton space (rest before the fall, the final pose after it).
var _hips_local := Vector3.ZERO

## Turns the character under `model` into a ragdoll and throws it: every body gets
## `velocity`, plus `upper_push` weighted toward the chest and head so it topples.
## `owner_body`'s own collider is ignored. Returns the Ragdoll node (added under
## `owner_body`), or null if the model has no skeleton.
## Callers reach this through `preload("res://scripts/world/ragdoll.gd")`, which works
## before the editor has registered the class name.
static func activate(model: Node3D, owner_body: CollisionObject3D, velocity: Vector3, upper_push := Vector3.ZERO) -> Node:
	var skeleton := _find_skeleton(model)
	if skeleton == null or skeleton.find_bone("Hips") < 0:
		return null
	var ragdoll = (load(SELF_PATH) as GDScript).new()
	ragdoll.name = "Ragdoll"
	ragdoll._skeleton = skeleton
	ragdoll._anim = GeneratedAssets.find_animation_player(model)
	owner_body.add_child(ragdoll)
	ragdoll._build(owner_body)
	ragdoll._start(velocity, upper_push)
	return ragdoll

## True once the body has come to rest and been frozen.
func is_settled() -> bool:
	return _frozen

## World position of the pelvis bone (follows the body while it falls).
func hips_position() -> Vector3:
	if _hips and is_instance_valid(_hips):
		return (_hips.global_transform * _hips.body_offset.affine_inverse()).origin
	return _skeleton.global_transform * _hips_local

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null

## Rest position of a bone in skeleton space.
func _rest(bone: String) -> Vector3:
	return _skeleton.get_bone_global_rest(_skeleton.find_bone(bone)).origin

## Basis whose X runs along `dir` and whose Z is the hinge axis for bending toward `flex`.
static func _frame(dir: Vector3, flex: Vector3) -> Basis:
	var x := dir.normalized()
	var z := x.cross(flex)
	if z.length() < 0.001:
		z = x.cross(Vector3.UP if absf(x.y) < 0.9 else Vector3.FORWARD)
	z = z.normalized()
	return Basis(x, z.cross(x), z)

## Jolt does not simulate scaled bodies and joints reliably, and the Meshy rig sits
## under a 0.01-scaled Armature. This rewrites the skeleton in metres at unit scale
## (rests, current pose and skin bind poses), so the physical bones are unscaled.
## The visible pose does not change. Animation is paused from here on.
func _unscale_rig() -> void:
	var s := _skeleton.global_transform.basis.get_scale().x
	if absf(s - 1.0) < 0.0001 or s <= 0.0:
		return
	_skeleton.scale /= s
	for i in _skeleton.get_bone_count():
		var rest := _skeleton.get_bone_rest(i)
		rest.origin *= s
		_skeleton.set_bone_rest(i, rest)
		_skeleton.set_bone_pose_position(i, _skeleton.get_bone_pose_position(i) * s)
	var to_metres := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
	for child in _skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.skin == null:
			continue
		var skin := mi.skin.duplicate() as Skin
		for b in skin.get_bind_count():
			skin.set_bind_pose(b, to_metres * skin.get_bind_pose(b))
		mi.skin = skin
		# The mesh's own bounds are still in centimetres; give culling a body-sized box.
		mi.custom_aabb = AABB(Vector3(-2.5, -1.0, -2.5), Vector3(5.0, 3.5, 5.0))

func _build(owner_body: CollisionObject3D) -> void:
	_unscale_rig()
	var unit := 1.0 / maxf(_skeleton.global_transform.basis.get_scale().x, 0.0001)
	_sim = PhysicalBoneSimulator3D.new()
	_sim.name = "RagdollSimulator"
	_skeleton.add_child(_sim)
	var skip: Array[RID] = []
	if owner_body:
		skip.append(owner_body.get_rid())
	for group: StringName in [&"player", &"militia"]:
		for n in _skeleton.get_tree().get_nodes_in_group(group):
			if n is CollisionObject3D and not skip.has(n.get_rid()):
				skip.append((n as CollisionObject3D).get_rid())
	for spec: Dictionary in BODIES:
		var bone: String = spec.bone
		var idx := _skeleton.find_bone(bone)
		if idx < 0:
			continue
		var head := _rest(bone)
		var body_xf := Transform3D()
		var shape := CollisionShape3D.new()
		var kind: String = spec.get("shape", "capsule")
		var half := 0.0
		match kind:
			"box":
				# Pelvis / chest: a box from this bone up to `top`.
				var top := _rest(spec.top)
				var bottom := head - Vector3.UP * float(spec.get("drop", 0.0)) * unit
				var height := top.y - bottom.y
				var size: Vector3 = spec.size
				var box := BoxShape3D.new()
				box.size = Vector3(height, size.y * unit, size.z * unit)
				shape.shape = box
				body_xf = Transform3D(_frame(Vector3.UP, Vector3.BACK), Vector3(head.x, (top.y + bottom.y) * 0.5, head.z))
				half = (body_xf.origin.y - head.y)
			"head":
				# Head: a capsule from the jaw to the crown, hinged at the neck, so the
				# skull rests on the street instead of sinking into it.
				var skull := _rest("Head") + Vector3.UP * 0.1 * unit
				var capsule := CapsuleShape3D.new()
				capsule.radius = float(spec.radius) * unit
				capsule.height = 0.3 * unit
				shape.shape = capsule
				shape.transform = Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3.ZERO)
				body_xf = Transform3D(_frame(skull - head, Vector3.BACK), skull)
				half = head.distance_to(skull)
			_:
				var tail := _rest(spec.end)
				tail += (tail - head) * float(spec.get("extend", 0.0))
				var dir := tail - head
				var capsule := CapsuleShape3D.new()
				capsule.radius = float(spec.radius) * unit
				capsule.height = maxf(dir.length() + capsule.radius * 2.0 * 0.6, capsule.radius * 2.0)
				shape.shape = capsule
				# Capsules run along their Y; the body's X runs along the limb.
				shape.transform = Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3.ZERO)
				body_xf = Transform3D(_frame(dir, spec.get("flex", Vector3.BACK)), (head + tail) * 0.5)
				half = dir.length() * 0.5
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + bone
		pb.bone_name = bone
		pb.add_child(shape)
		pb.body_offset = _skeleton.get_bone_global_rest(idx).affine_inverse() * body_xf
		# The joint pivots at the bone's own head, which is `half` back along the body's X.
		pb.joint_offset = Transform3D(Basis(), Vector3(-half, 0, 0))
		match String(spec.get("joint", "")):
			"cone":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
				pb.set(&"joint_constraints/swing_span", float(spec.swing))
				pb.set(&"joint_constraints/twist_span", float(spec.twist))
			"hinge":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
				pb.set(&"joint_constraints/angular_limit_enabled", true)
				# The hinge angle grows when the child turns clockwise about the axis
				# (measured, Jolt 4.7), the opposite of the flex frame, so negate the range.
				pb.set(&"joint_constraints/angular_limit_upper", -float(spec.lower))
				pb.set(&"joint_constraints/angular_limit_lower", -float(spec.upper))
			_:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		pb.mass = float(spec.mass)
		pb.friction = 0.9
		pb.bounce = 0.0
		pb.linear_damp = DAMP.x
		pb.angular_damp = DAMP.y
		pb.collision_layer = LAYER
		pb.collision_mask = MASK
		# Built in the rest pose, so every joint limit is measured from the rest pose.
		pb.transform = body_xf
		_sim.add_child(pb)
		for rid in skip:
			PhysicsServer3D.body_add_collision_exception(pb.get_rid(), rid)
		_bones.append(pb)
		if bone == "Hips":
			_hips = pb
	# Limbs of one body never collide with each other: overlapping shapes at the
	# start would otherwise shove the joints apart.
	for a in _bones:
		for b in _bones:
			if a != b:
				PhysicsServer3D.body_add_collision_exception(a.get_rid(), b.get_rid())
	_hips_local = _rest("Hips")

func _start(velocity: Vector3, upper_push: Vector3) -> void:
	_sim.physical_bones_start_simulation()
	if _anim:
		_anim.pause()
	for pb in _bones:
		var w: float = PUSH_WEIGHT.get(String(pb.bone_name), 0.0)
		PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity + upper_push * w)

func _physics_process(delta: float) -> void:
	if _frozen:
		return
	var was := _age
	_age += delta
	if was < STIFFEN_TIME and _age >= STIFFEN_TIME:
		for pb in _bones:
			pb.linear_damp = STIFF_DAMP.x
			pb.angular_damp = STIFF_DAMP.y
	var moving := false
	for pb in _bones:
		var rid := pb.get_rid()
		var lin: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var ang: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		if lin.length() > SETTLE_SPEED or ang.length() > SETTLE_SPIN:
			moving = true
			break
	_still = 0.0 if moving else _still + delta
	if (_age >= MIN_TIME and _still >= SETTLE_TIME) or _age >= MAX_TIME:
		_freeze()

## Bakes the simulated pose into the skeleton and removes the physics bodies.
func _freeze() -> void:
	_frozen = true
	var count := _skeleton.get_bone_count()
	var sim_global := {}
	var inv := _skeleton.global_transform.affine_inverse()
	for pb in _bones:
		var idx := _skeleton.find_bone(pb.bone_name)
		sim_global[idx] = inv * pb.global_transform * pb.body_offset.affine_inverse()
	var globals: Array[Transform3D] = []
	globals.resize(count)
	# Bones are ordered parents first in these rigs; walk them in index order.
	for i in count:
		var parent := _skeleton.get_bone_parent(i)
		var parent_global := globals[parent] if parent >= 0 else Transform3D()
		if sim_global.has(i):
			var g: Transform3D = sim_global[i]
			g.basis = g.basis.orthonormalized()
			globals[i] = g
			var local := parent_global.affine_inverse() * g
			_skeleton.set_bone_pose_position(i, local.origin)
			_skeleton.set_bone_pose_rotation(i, local.basis.orthonormalized().get_rotation_quaternion())
		else:
			globals[i] = parent_global * _skeleton.get_bone_pose(i)
	_hips_local = globals[_skeleton.find_bone("Hips")].origin
	_sim.active = false
	_sim.physical_bones_stop_simulation()
	_sim.queue_free()
	_sim = null
	_bones.clear()
	_hips = null
	settled.emit()
