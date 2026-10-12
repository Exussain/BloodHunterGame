class_name Militia
extends CharacterBody3D
## Placeholder traitor militia soldier: patrols, spots the volatile, shoots.
## The volatile's powers can grab (tendril), stun and panic (scream, rage) it.
## Going down (claw, pounce, tendril landing) throws it into a physics ragdoll
## (see scripts/world/ragdoll.gd) that settles, freezes and stays in the world to be fed on.
## Full AI (cover, flanking, alarms) and gore come in later build steps.

const RagdollScript := preload("res://scripts/world/ragdoll.gd")
const BloodPool := preload("res://scripts/enemies/blood_pool.gd")

enum State { PATROL, ALERT, DOWNED, FED_ON, DEAD, GRABBED, STUNNED, PANIC }

@export var max_health := 90.0
@export var walk_speed := 2.2
@export var sight_range := 28.0
@export var fire_interval := 1.1
@export var hit_chance := 0.35
@export var shot_damage := 7.0
@export var patrol_points: Array[Vector3] = []
## Which generated character to use (see tools/assets/manifest.json).
@export var variant := "militia_rifleman"

var state: State = State.PATROL
var health := max_health

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _model: Node3D
var _anim: AnimationPlayer
var _hit_until := 0.0
var _muzzle_light: OmniLight3D
var _patrol_index := 0
var _fire_timer := 0.0
var _player: Volatile
var _feeder: Node3D
## Tendril grab: who is pulling, from where, and how far along the arc (0..1).
var _grabber: Node3D
var _grab_from := Vector3.ZERO
var _grab_t := 0.0
var _grab_time := 0.5
var _grab_arc := 2.5
var _grab_drop := 1.3
## Stun, then panic: seconds left in each, and how fast it runs while panicking.
var _stun_left := 0.0
var _panic_left := 0.0
var _panic_speed := 4.6
var _saved_layers := Vector2i.ZERO
## Where the grabbed body was last frame, to carry its momentum into the ragdoll.
var _grab_prev := Vector3.ZERO
var _grab_velocity := Vector3.ZERO
var _body_shape: CollisionShape3D
## The physics ragdoll once the soldier is down (null for the placeholder look).
var _ragdoll: RagdollScript

func _ready() -> void:
	add_to_group(&"militia")
	health = max_health
	_fire_timer = randf() * fire_interval
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_body_shape = shape
	_build_model()

func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	var generated := GeneratedAssets.character(variant)
	if generated:
		_model.add_child(generated)
		_anim = GeneratedAssets.find_animation_player(generated)
	else:
		_build_placeholder()
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.75, 0.35)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 6.0
	_muzzle_light.position = Vector3(0.22, 1.25, -0.85)
	_model.add_child(_muzzle_light)

func _build_placeholder() -> void:
	# Placeholder look: olive Sipah-style uniform (invented insignia only).
	var uniform := StandardMaterial3D.new()
	uniform.albedo_color = Color(0.22, 0.25, 0.16)
	uniform.roughness = 0.85
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.62, 0.47, 0.38)
	var gun := StandardMaterial3D.new()
	gun.albedo_color = Color(0.05, 0.05, 0.05)
	gun.metallic = 0.6
	gun.roughness = 0.4
	_part(CapsuleMesh.new(), uniform, Vector3(0, 0.9, 0), Vector3(0.76, 0.95, 0.76))
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	_part(head, skin, Vector3(0, 1.68, 0), Vector3.ONE)
	var rifle := BoxMesh.new()
	rifle.size = Vector3(0.08, 0.1, 0.9)
	_part(rifle, gun, Vector3(0.22, 1.25, -0.35), Vector3.ONE)

func _part(mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	_model.add_child(mi)

# --- Queries used by the volatile -------------------------------------------

func is_downed() -> bool:
	return state == State.DOWNED

func is_alive_body() -> bool:
	return state in [State.PATROL, State.ALERT, State.DOWNED, State.STUNNED, State.PANIC]

## Standing and able to fight back (or about to).
func is_standing() -> bool:
	return state in [State.PATROL, State.ALERT, State.STUNNED, State.PANIC]

func is_panicking() -> bool:
	return state in [State.STUNNED, State.PANIC]

# --- Damage -----------------------------------------------------------------

func take_damage(amount: float, source: Node3D) -> void:
	if state in [State.DOWNED, State.FED_ON, State.DEAD, State.GRABBED]:
		return
	health -= amount
	_spawn_blood(global_position, 0.3, 0.8)
	if health <= 0:
		# Thrown away from the claw; harder hits (rage) throw harder.
		var away := _away_from(source)
		var k := clampf(amount / 45.0, 1.0, 2.5)
		_go_down(away * 1.0 * k + Vector3.UP * 0.4, away * 2.4 * k)
	else:
		_alert(source)
		if GeneratedAssets.play(_anim, &"hit", 0.05, 1.3):
			_hit_until = Time.get_ticks_msec() / 1000.0 + 0.5

func take_pounce(source: Node3D) -> void:
	if is_standing():
		_spawn_blood(global_position, 0.4, 1.0)
		# Bowled over along the leap: chest driven ahead of it, legs swept out.
		var away := _away_from(source)
		if source is CharacterBody3D:
			var leap := (source as CharacterBody3D).velocity
			leap.y = 0.0
			if leap.length() > 1.0:
				away = leap.normalized()
		_go_down(away * 1.8 + Vector3.UP * 0.4, away * 3.2)
		_alert_nearby(source)

func begin_feed(feeder: Node3D) -> void:
	state = State.FED_ON
	_feeder = feeder

func finish_feed() -> void:
	state = State.DEAD
	# Feeding opens the body up: a wide pool spreads out from under it.
	_spawn_blood(global_position, 0.95, 2.5)
	if _anim == null:
		_model.scale = Vector3(1, 0.6, 1)

## Flat direction from `source` to this soldier (forward if there is no source).
func _away_from(source: Node3D) -> Vector3:
	var away := -_model.global_basis.z
	if is_instance_valid(source):
		away = global_position - source.global_position
	away.y = 0.0
	return away.normalized() if away.length() > 0.01 else Vector3.FORWARD

## Drops the soldier: a ragdoll thrown with `push` (all of it) and `upper_push`
## (mostly chest and head, so it topples), or the old clip/tween without a rig.
func _go_down(push := Vector3.ZERO, upper_push := Vector3.ZERO) -> void:
	state = State.DOWNED
	velocity = Vector3.ZERO
	_muzzle_light.light_energy = 0.0
	_ragdoll = RagdollScript.activate(_model, self, push, upper_push) as RagdollScript
	if _ragdoll:
		# The corpse is the ragdoll now; the standing capsule would block the player.
		_body_shape.set_deferred(&"disabled", true)
		_ragdoll.settled.connect(_on_body_settled)
		return
	if GeneratedAssets.play(_anim, &"down", 0.1):
		return
	var tw := create_tween()
	tw.tween_property(_model, "rotation:x", -PI / 2, 0.35).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_model, "position:y", 0.38, 0.35)

func _alert(source: Node3D) -> void:
	if source is Volatile:
		_player = source
	# Panic and grabs outrank the alarm; they turn hostile once they recover.
	if state in [State.PATROL, State.ALERT]:
		state = State.ALERT

## Hearing a scream or a fight nearby turns a patrolling soldier hostile.
func hear_threat(source: Node3D) -> void:
	if state == State.PATROL:
		_alert(source)

# --- Volatile powers ----------------------------------------------------------

## Tendril grab: yanked through the air in an arc to `drop` metres in front of
## the grabber, ignoring walls and damage on the way, then dropped downed.
func begin_grab(grabber: Node3D, pull_speed: float, arc_height: float, drop: float) -> void:
	if not is_standing():
		return
	state = State.GRABBED
	_grabber = grabber
	_grab_from = global_position
	_grab_t = 0.0
	_grab_prev = _grab_from
	_grab_velocity = Vector3.ZERO
	_grab_arc = arc_height
	_grab_drop = drop
	_grab_time = maxf(_grab_from.distance_to(grabber.global_position) / pull_speed, 0.2)
	_muzzle_light.light_energy = 0.0
	_saved_layers = Vector2i(collision_layer, collision_mask)
	collision_layer = 0
	collision_mask = 0
	GeneratedAssets.play(_anim, &"hit", 0.05, 0.6)

func is_grabbed() -> bool:
	return state == State.GRABBED

func grab_point() -> Vector3:
	return global_position + Vector3.UP * 1.3

func _process_grab(delta: float) -> void:
	velocity = Vector3.ZERO
	if not is_instance_valid(_grabber):
		_end_grab()
		return
	var fwd := -_grabber.global_basis.z
	if _grabber.has_method(&"facing"):
		fwd = _grabber.facing()
	var to := _grabber.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * _grab_drop
	_grab_t = minf(_grab_t + delta / _grab_time, 1.0)
	# Ease in so the yank snaps, with a hop over whatever is between them.
	var t := 1.0 - pow(1.0 - _grab_t, 2.0)
	global_position = _grab_from.lerp(to, t) + Vector3.UP * sin(t * PI) * _grab_arc
	if delta > 0.0:
		_grab_velocity = (global_position - _grab_prev) / delta
	_grab_prev = global_position
	var look := to - _grab_from
	look.y = 0
	if look.length() > 0.1:
		_face(look.normalized())
	if _grab_t >= 1.0:
		_end_grab()

func _end_grab() -> void:
	collision_layer = _saved_layers.x
	collision_mask = _saved_layers.y
	_spawn_blood(global_position, 0.4, 1.0)
	# Slammed down where the yank ends: the legs carry on toward the volatile and the
	# chest snaps back, so it lands on its back at the volatile's feet, not on them.
	var travel := Vector3(_grab_velocity.x, 0.0, _grab_velocity.z).limit_length(4.0)
	var dir := travel.normalized() if travel.length() > 0.1 else _away_from(_grabber) * -1.0
	_go_down(travel * 0.25 + Vector3.DOWN * 1.5, -dir * 2.4)

## Scream: stunned on the spot, then panics and runs from `source`.
func stun(source: Node3D, stun_time: float, panic_time: float, panic_speed: float) -> void:
	if not is_standing():
		return
	if source is Volatile:
		_player = source
	state = State.STUNNED
	_stun_left = stun_time
	_panic_left = panic_time
	_panic_speed = panic_speed
	_muzzle_light.light_energy = 0.0
	GeneratedAssets.play(_anim, &"hit", 0.05, 0.5)

## Rage form: panics straight away (no stun) and flees.
func panic(source: Node3D, panic_time: float, panic_speed: float) -> void:
	if not is_standing():
		return
	if source is Volatile:
		_player = source
	state = State.PANIC
	_panic_left = maxf(_panic_left, panic_time)
	_panic_speed = panic_speed

func _process_panic(delta: float) -> void:
	if state == State.STUNNED:
		velocity.x = 0
		velocity.z = 0
		_stun_left -= delta
		if _stun_left <= 0:
			state = State.PANIC
		return
	_panic_left -= delta
	if _panic_left <= 0:
		state = State.ALERT if _player and _player.health > 0 else State.PATROL
		return
	var away := Vector3.FORWARD
	if _player:
		away = global_position - _player.global_position
		away.y = 0
		away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	velocity.x = away.x * _panic_speed
	velocity.z = away.z * _panic_speed
	_face(away)

func _alert_nearby(source: Node3D) -> void:
	for other in get_tree().get_nodes_in_group(&"militia"):
		if other != self and other.state == State.PATROL and other.global_position.distance_to(global_position) < 18.0:
			other._alert(source)

## Spreads a blood pool of `size` metres on the ground near `at`, over `grow` seconds.
func _spawn_blood(at: Vector3, size: float, grow := 1.6) -> void:
	var ground := Vector3(at.x + randf_range(-0.2, 0.2), global_position.y + 0.03, at.z + randf_range(-0.2, 0.2))
	BloodPool.spawn(get_parent(), ground, size, grow)

# --- Behaviour --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _ragdoll:
		# Down for good: the ragdoll moves the body, this node just tracks it.
		if not _ragdoll.is_settled():
			_follow_body()
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	match state:
		State.PATROL:
			_patrol()
			_look_for_player()
		State.ALERT:
			_combat(delta)
		State.GRABBED:
			_process_grab(delta)
			_update_animation()
			return
		State.STUNNED, State.PANIC:
			_process_panic(delta)
		_:
			velocity.x = 0
			velocity.z = 0
	move_and_slide()
	_update_animation()
	_muzzle_light.light_energy = maxf(_muzzle_light.light_energy - delta * 40.0, 0.0)

func _update_animation() -> void:
	if _anim == null or Time.get_ticks_msec() / 1000.0 < _hit_until:
		return
	match state:
		State.PATROL:
			var moving := Vector2(velocity.x, velocity.z).length() > 0.3
			GeneratedAssets.play(_anim, &"patrol" if moving else &"idle", 0.3)
		State.ALERT:
			GeneratedAssets.play(_anim, &"combat", 0.2)
		State.PANIC:
			# No run clip yet: a sped-up patrol walk reads as fleeing.
			GeneratedAssets.play(_anim, &"patrol", 0.2, 2.2)

func _patrol() -> void:
	if patrol_points.is_empty():
		velocity.x = 0
		velocity.z = 0
		return
	var target := patrol_points[_patrol_index]
	var to := target - global_position
	to.y = 0
	if to.length() < 0.6:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		return
	var dir := to.normalized()
	velocity.x = dir.x * walk_speed
	velocity.z = dir.z * walk_speed
	_face(dir)

func _look_for_player() -> void:
	var p := get_tree().get_first_node_in_group(&"player") as Volatile
	if p == null:
		return
	var to := p.global_position - global_position
	if to.length() > sight_range:
		return
	var facing := -_model.global_basis.z
	if facing.dot(to.normalized()) < 0.2 and to.length() > 4.0:
		return
	if _has_line_of_sight(p):
		_alert(p)
		_alert_nearby(p)

func _has_line_of_sight(p: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.6, p.global_position + Vector3.UP * 1.2)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty() or hit.collider == p

func _combat(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	if _player == null or _player.health <= 0:
		return
	var to := _player.global_position - global_position
	to.y = 0
	if to.length() > 0.1:
		_face(to.normalized())
	_fire_timer -= delta
	if _fire_timer > 0:
		return
	_fire_timer = fire_interval
	if not _has_line_of_sight(_player) or to.length() > sight_range * 1.5:
		return
	_muzzle_light.light_energy = 8.0
	if randf() < hit_chance:
		_player.take_damage(shot_damage)

func _on_body_settled() -> void:
	_follow_body()
	reset_physics_interpolation()
	# The body bleeds out where it came to rest.
	_spawn_blood(_ragdoll.hips_position(), 0.7, 3.0)

## Keeps this node on the floor under the ragdoll's hips, so the volatile's range
## checks (feeding) find the body where it actually lies.
func _follow_body() -> void:
	var hips := _ragdoll.hips_position()
	var q := PhysicsRayQueryParameters3D.create(hips + Vector3.UP * 0.2, hips + Vector3.DOWN * 2.5, 1)
	# Only the street counts: not the volatile or a soldier standing over the body.
	var skip: Array[RID] = []
	for group: StringName in [&"player", &"militia"]:
		for n in get_tree().get_nodes_in_group(group):
			if n is CollisionObject3D:
				skip.append((n as CollisionObject3D).get_rid())
	q.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	global_position = hit.position if not hit.is_empty() else hips + Vector3.DOWN * 0.15

func _face(dir: Vector3) -> void:
	_model.global_basis = Basis.looking_at(dir)
