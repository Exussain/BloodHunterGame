class_name Volatile
extends CharacterBody3D
## The player: the lone volatile. Third-person predator movement with
## wall-climb, wall-run, charged pounce, claw attack and feeding, plus the
## powers feeding unlocks: tendril grab, scream and rage form.

signal health_changed(value: float, max_value: float)
signal mutation_changed(value: float, max_value: float)
signal pounce_charge_changed(value: float)
signal feed_target_changed(available: bool)
signal power_unlocked(power: StringName)
## Seconds left on a power's cooldown (0 when ready) and its full length.
signal power_cooldown_changed(power: StringName, left: float, total: float)
signal rage_changed(active: bool)
signal died

enum State { GROUND, AIR, CLIMB, WALL_RUN, POUNCE, FEED }

const MAX_HEALTH := 100.0
const MAX_MUTATION := 100.0
## Mutation needed for each power, in unlock order (see core design skill tree).
const UNLOCKS := [[25.0, &"tendril"], [50.0, &"scream"], [100.0, &"rage"]]
## Power tuning (ranges, cooldowns, rage multipliers); see design/quick-specs/volatile-powers-*.md.
const POWERS_PATH := "res://assets/data/volatile_powers.json"

@export var walk_speed := 6.5
@export var sprint_speed := 12.0
@export var accel := 40.0
@export var air_accel := 8.0
@export var jump_velocity := 8.0
@export var gravity_scale := 1.7
@export var climb_speed := 6.0
@export var wall_run_time := 1.6
@export var pounce_min := 14.0
@export var pounce_max := 30.0
@export var pounce_charge_time := 0.8
@export var claw_damage := 45.0
@export var claw_range := 2.4
@export var feed_time := 2.2
@export var mouse_sensitivity := 0.0025

var state: State = State.AIR
var health := MAX_HEALTH
var mutation := 0.0
var unlocked: Array[StringName] = []

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _yaw: Node3D
var _pitch: Node3D
var _camera: Camera3D
var _model: Node3D
var _anim: AnimationPlayer
## Until this time (s), a one-shot clip (claw) owns the animation.
var _oneshot_until := 0.0
var _wall_ray: RayCast3D
var _ledge_ray: RayCast3D
var _left_ray: RayCast3D
var _right_ray: RayCast3D
var _pounce_charge := -1.0
var _wall_run_left := 0.0
var _wall_normal := Vector3.ZERO
var _feed_left := 0.0
var _feed_target: Node3D
var _claw_cooldown := 0.0
var _feed_available := false
var _powers: Dictionary
var _cooldowns := {&"tendril": 0.0, &"scream": 0.0}
var _rage_left := 0.0
var _fear_tick := 0.0
var _arm: SpringArm3D
var _rage_light: OmniLight3D

func _ready() -> void:
	add_to_group(&"player")
	floor_snap_length = 0.4
	_build_body()
	_build_camera()
	_build_rays()
	_powers = JSON.parse_string(FileAccess.get_file_as_string(POWERS_PATH))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health_changed.emit.call_deferred(health, MAX_HEALTH)
	mutation_changed.emit.call_deferred(mutation, MAX_MUTATION)

func get_camera() -> Camera3D:
	return _camera

## The way the volatile's body faces (flat), used to drop grabbed soldiers in front of it.
func facing() -> Vector3:
	var f := -_model.global_basis.z
	f.y = 0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD

func is_raging() -> bool:
	return _rage_left > 0.0

func power_ready(power: StringName) -> bool:
	if not unlocked.has(power):
		return false
	if power == &"rage":
		return not is_raging() and mutation >= float(_powers.rage.cost)
	return _cooldowns[power] <= 0.0

# --- Construction ---------------------------------------------------------

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.9
	shape.shape = capsule
	shape.position.y = 0.95
	add_child(shape)

	# Placeholder: a figure in a red human outfit, until rigged models arrive.
	_model = Node3D.new()
	add_child(_model)
	var generated := GeneratedAssets.character("volatile")
	if generated:
		_model.add_child(generated)
		_anim = GeneratedAssets.find_animation_player(generated)
		return
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.55, 0.02, 0.02)
	red.roughness = 0.6
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.35, 0.3, 0.28)
	skin.roughness = 0.4
	_add_part(_model, CapsuleMesh.new(), red, Vector3(0, 0.95, 0), Vector3(0.8, 1.0, 0.8))
	var head := SphereMesh.new()
	head.radius = 0.22
	head.height = 0.44
	_add_part(_model, head, skin, Vector3(0, 1.75, -0.05), Vector3.ONE)
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(1, 0.9, 0.6)
	eye.emission_enabled = true
	eye.emission = Color(1, 0.75, 0.3)
	eye.emission_energy_multiplier = 6.0
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.035
	eye_mesh.height = 0.07
	_add_part(_model, eye_mesh, eye, Vector3(-0.08, 1.78, -0.24), Vector3.ONE)
	_add_part(_model, eye_mesh, eye, Vector3(0.08, 1.78, -0.24), Vector3.ONE)

func _add_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)

func _build_camera() -> void:
	_yaw = Node3D.new()
	_yaw.position.y = 1.6
	_yaw.top_level = true
	add_child(_yaw)
	_pitch = Node3D.new()
	_pitch.rotation.x = -0.25
	_yaw.add_child(_pitch)
	_arm = SpringArm3D.new()
	_arm.spring_length = 3.8
	_arm.position = Vector3(0.6, 0.2, 0)
	_arm.margin = 0.2
	_arm.add_excluded_object(get_rid())
	_pitch.add_child(_arm)
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.far = 800.0
	_arm.add_child(_camera)
	_camera.make_current()
	# Soft fill light that travels with the camera so the volatile never turns into a silhouette.
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.85, 0.75)
	fill.light_energy = 0.6
	fill.omni_range = 6.0
	fill.light_specular = 0.2
	fill.shadow_enabled = false
	fill.position = Vector3(0, 0.3, 0)
	_camera.add_child(fill)

func _build_rays() -> void:
	_wall_ray = _ray(Vector3(0, 1.2, 0), Vector3(0, 0, -0.9))
	_ledge_ray = _ray(Vector3(0, 2.3, -0.7), Vector3(0, -1.0, 0))
	_left_ray = _ray(Vector3(0, 1.1, 0), Vector3(-0.9, 0, 0))
	_right_ray = _ray(Vector3(0, 1.1, 0), Vector3(0.9, 0, 0))

func _ray(origin: Vector3, target: Vector3) -> RayCast3D:
	var r := RayCast3D.new()
	r.position = origin
	r.target_position = target
	r.add_exception(self)
	_model.add_child(r)
	return r

# --- Input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw.rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch.rotation.x = clampf(_pitch.rotation.x - event.relative.y * mouse_sensitivity, -1.3, 0.9)

# --- Simulation -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	_yaw.global_position = global_position + Vector3.UP * 1.6
	_claw_cooldown = maxf(_claw_cooldown - delta, 0.0)
	_tick_powers(delta)
	_update_feed_target()
	if state != State.FEED and health > 0:
		_handle_powers()

	match state:
		State.FEED:
			_process_feed(delta)
		State.CLIMB:
			_process_climb(delta)
		State.WALL_RUN:
			_process_wall_run(delta)
		State.POUNCE:
			_process_pounce(delta)
		_:
			_process_move(delta)

	move_and_slide()
	_update_model_facing(delta)
	_update_animation()

	if state in [State.GROUND, State.AIR]:
		state = State.GROUND if is_on_floor() else State.AIR

func _input_dir() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := _yaw.global_basis
	var forward := -basis.z
	forward.y = 0
	var right := basis.x
	right.y = 0
	return (right.normalized() * v.x - forward.normalized() * v.y).limit_length(1.0)

func _process_move(delta: float) -> void:
	var dir := _input_dir()
	var on_floor := is_on_floor()
	var speed := (sprint_speed if Input.is_action_pressed("sprint") else walk_speed) * _speed_mult()
	var a := accel if on_floor else air_accel
	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, a * delta)
	velocity.z = move_toward(velocity.z, target.z, a * delta)
	if not on_floor:
		velocity.y -= _gravity * gravity_scale * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	if Input.is_action_just_pressed("attack"):
		_claw()
	if Input.is_action_just_pressed("feed") and _feed_target:
		_start_feed()
		return

	_handle_pounce_charge(delta, on_floor)

	# Moving into a wall starts a climb; sprinting past one in the air starts a wall-run.
	if dir.length() > 0.3:
		var wall_n := Vector3.ZERO
		if _wall_ray.is_colliding():
			wall_n = _wall_ray.get_collision_normal()
		elif is_on_wall():
			wall_n = get_wall_normal()
		if _is_wall(wall_n) and -wall_n.dot(dir) > 0.5:
			_enter_climb(wall_n)
			return
	if not on_floor and Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > 7.0:
		for side_ray in [_left_ray, _right_ray]:
			if side_ray.is_colliding() and _is_wall(side_ray.get_collision_normal()):
				_enter_wall_run(side_ray.get_collision_normal())
				return

func _is_wall(n: Vector3) -> bool:
	return n != Vector3.ZERO and absf(n.y) < 0.3

# Climb ---------------------------------------------------------------------

func _enter_climb(normal: Vector3) -> void:
	state = State.CLIMB
	_wall_normal = normal
	_pounce_charge = -1.0
	pounce_charge_changed.emit(0.0)

func _process_climb(delta: float) -> void:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wall_right := Vector3.UP.cross(_wall_normal).normalized()
	var climb := climb_speed * _speed_mult()
	velocity = Vector3.UP * (-v.y * climb) + wall_right * (-v.x * climb * 0.8) - _wall_normal * 2.0

	if Input.is_action_just_pressed("jump"):
		# Kick off the wall.
		velocity = _wall_normal * 9.0 + Vector3.UP * jump_velocity
		state = State.AIR
		return
	if not _wall_ray.is_colliding() and not is_on_wall():
		# Reached the top: mantle over the ledge.
		if v.y < 0 and _ledge_ray.is_colliding():
			velocity = Vector3.UP * 6.0 - _wall_normal * 4.0
		state = State.AIR
		return
	if _wall_ray.is_colliding():
		_wall_normal = _wall_normal.slerp(_wall_ray.get_collision_normal(), clampf(delta * 10.0, 0, 1)).normalized()
	if is_on_floor() and v.y >= 0:
		state = State.GROUND
	_handle_pounce_charge(delta, true)

# Wall-run ----------------------------------------------------------------

func _enter_wall_run(normal: Vector3) -> void:
	state = State.WALL_RUN
	_wall_normal = normal
	_wall_run_left = wall_run_time
	var along := Vector3.UP.cross(normal).normalized()
	if along.dot(velocity) < 0:
		along = -along
	var speed := maxf(Vector2(velocity.x, velocity.z).length(), sprint_speed)
	velocity = along * speed + Vector3.UP * maxf(velocity.y, 2.5)

func _process_wall_run(delta: float) -> void:
	_wall_run_left -= delta
	velocity.y -= _gravity * 0.25 * delta
	velocity -= _wall_normal * 1.5 * delta
	if Input.is_action_just_pressed("jump"):
		var forward := Vector3(velocity.x, 0, velocity.z).normalized()
		velocity = forward * sprint_speed + _wall_normal * 7.0 + Vector3.UP * jump_velocity
		state = State.AIR
		return
	var still_on_wall := (_left_ray.is_colliding() or _right_ray.is_colliding()) and is_on_wall()
	if _wall_run_left <= 0 or is_on_floor() or not Input.is_action_pressed("sprint") or not still_on_wall:
		state = State.AIR

# Pounce ------------------------------------------------------------------

func _handle_pounce_charge(delta: float, can_launch: bool) -> void:
	if Input.is_action_pressed("pounce"):
		if _pounce_charge < 0:
			_pounce_charge = 0.0
		_pounce_charge = minf(_pounce_charge + delta / pounce_charge_time, 1.0)
		pounce_charge_changed.emit(_pounce_charge)
	elif _pounce_charge >= 0:
		if can_launch or is_on_floor():
			_launch_pounce(_pounce_charge)
		_pounce_charge = -1.0
		pounce_charge_changed.emit(0.0)

func _launch_pounce(charge: float) -> void:
	var aim := -_camera.global_basis.z
	# Never pounce flatter than ~15 degrees so the arc clears low cover.
	aim.y = maxf(aim.y, 0.26)
	aim = aim.normalized()
	velocity = aim * lerpf(pounce_min, pounce_max, charge)
	if state == State.CLIMB:
		velocity += _wall_normal * 6.0
	state = State.POUNCE

func _process_pounce(delta: float) -> void:
	velocity.y -= _gravity * gravity_scale * 0.8 * delta
	for enemy in _enemies_in_range(2.4 if is_raging() else 1.6, false):
		enemy.take_pounce(self)
		velocity = Vector3(0, 2.0, 0)
		state = State.AIR
		return
	if is_on_floor():
		state = State.GROUND
	elif is_on_wall():
		var n := get_wall_normal()
		if _is_wall(n):
			_enter_climb(n)

# Claw --------------------------------------------------------------------

func _claw() -> void:
	if _claw_cooldown > 0:
		return
	_claw_cooldown = 0.45
	_play_oneshot(&"claw", 0.5)
	var forward := -_model.global_basis.z
	for enemy in _enemies_in_range(claw_range, false):
		var to: Vector3 = enemy.global_position - global_position
		to.y = 0
		if to.normalized().dot(forward) > 0.3:
			enemy.take_damage(claw_damage * (float(_powers.rage.claw_mult) if is_raging() else 1.0), self)

# Feed --------------------------------------------------------------------

func _update_feed_target() -> void:
	if state == State.FEED:
		return
	_feed_target = null
	var downed := _enemies_in_range(2.2, true)
	if not downed.is_empty():
		_feed_target = downed[0]
	_set_feed_available(_feed_target != null)

func _set_feed_available(available: bool) -> void:
	if available != _feed_available:
		_feed_available = available
		feed_target_changed.emit(available)

func _start_feed() -> void:
	state = State.FEED
	_set_feed_available(false)
	_feed_left = feed_time
	velocity = Vector3.ZERO
	_feed_target.begin_feed(self)
	var look := _feed_target.global_position - global_position
	look.y = 0
	if look.length() > 0.1:
		_model.global_basis = Basis.looking_at(look.normalized())

func _process_feed(delta: float) -> void:
	# Feeding leaves the volatile exposed; it can't move until done.
	velocity.x = 0
	velocity.z = 0
	velocity.y -= _gravity * gravity_scale * delta
	_feed_left -= delta
	if _feed_left > 0:
		return
	if is_instance_valid(_feed_target):
		_feed_target.finish_feed()
	heal(40.0)
	add_mutation(25.0)
	state = State.GROUND

# Stats -------------------------------------------------------------------

func heal(amount: float) -> void:
	health = minf(health + amount, MAX_HEALTH)
	health_changed.emit(health, MAX_HEALTH)

func take_damage(amount: float) -> void:
	if health <= 0:
		return
	if is_raging():
		amount *= float(_powers.rage.damage_taken_mult)
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, MAX_HEALTH)
	if health <= 0:
		GeneratedAssets.play(_anim, &"death", 0.1)
		died.emit()

func add_mutation(amount: float) -> void:
	mutation = minf(mutation + amount, MAX_MUTATION)
	mutation_changed.emit(mutation, MAX_MUTATION)
	for entry in UNLOCKS:
		if mutation >= entry[0] and not unlocked.has(entry[1]):
			unlocked.append(entry[1])
			power_unlocked.emit(entry[1])

# Powers ------------------------------------------------------------------

func _handle_powers() -> void:
	if Input.is_action_just_pressed("tendril"):
		use_tendril()
	if Input.is_action_just_pressed("scream"):
		use_scream()
	if Input.is_action_just_pressed("rage"):
		use_rage()

func _tick_powers(delta: float) -> void:
	for power: StringName in _cooldowns:
		if _cooldowns[power] > 0.0:
			_cooldowns[power] = maxf(_cooldowns[power] - delta, 0.0)
			power_cooldown_changed.emit(power, _cooldowns[power], float(_powers[power].cooldown))
	if not is_raging():
		return
	_rage_left = maxf(_rage_left - delta, 0.0)
	# Soldiers who see the rage form break and run.
	_fear_tick -= delta
	if _fear_tick <= 0.0:
		_fear_tick = 0.4
		for e: Militia in get_tree().get_nodes_in_group(&"militia"):
			if e.is_standing() and not e.is_panicking() \
					and e.global_position.distance_to(global_position) <= float(_powers.rage.fear_range) \
					and _can_see(e):
				e.panic(self, float(_powers.scream.panic_time), float(_powers.militia.panic_speed))
	if _rage_left <= 0.0:
		_end_rage()

func _start_cooldown(power: StringName) -> void:
	_cooldowns[power] = float(_powers[power].cooldown)
	power_cooldown_changed.emit(power, _cooldowns[power], _cooldowns[power])

## Tendril grab: yanks the soldier nearest the crosshair to the volatile's feet, downed.
## Returns the grabbed soldier, or null if nothing was in reach.
func use_tendril() -> Militia:
	if not power_ready(&"tendril"):
		return null
	var p: Dictionary = _powers.tendril
	var target := _tendril_target(float(p.range), deg_to_rad(float(p.aim_cone_deg)))
	if target == null:
		return null
	_start_cooldown(&"tendril")
	_play_oneshot(&"claw", 0.5)
	target.begin_grab(self, float(p.pull_speed), float(p.arc_height), float(p.drop_distance))
	PowerFx.tendril(get_parent(), self, target)
	return target

func _tendril_target(reach: float, cone: float) -> Militia:
	var eye := _camera.global_position
	var aim := -_camera.global_basis.z
	var best: Militia
	var best_angle := cone
	for e: Militia in get_tree().get_nodes_in_group(&"militia"):
		if not e.is_standing() or e.global_position.distance_to(global_position) > reach:
			continue
		var angle := aim.angle_to(e.grab_point() - eye)
		if angle < best_angle and _can_see(e):
			best = e
			best_angle = angle
	return best

## Scream: stuns and panics the squad in front; everyone else in earshot turns hostile.
## Returns how many soldiers it stunned.
func use_scream() -> int:
	if not power_ready(&"scream"):
		return 0
	var p: Dictionary = _powers.scream
	_start_cooldown(&"scream")
	_play_oneshot(&"scream", 1.0)
	var forward := -_camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	_model.global_basis = Basis.looking_at(forward)
	PowerFx.scream_wave(get_parent(), global_position + Vector3.UP * 1.4, forward, float(p.range))
	_shake_camera(0.5, 0.12)
	var stunned := 0
	for e: Militia in get_tree().get_nodes_in_group(&"militia"):
		if not e.is_standing():
			continue
		var to := e.global_position - global_position
		var dist := to.length()
		to.y = 0
		if dist <= float(p.range) and forward.angle_to(to) <= deg_to_rad(float(p.cone_deg)) and _can_see(e):
			e.stun(self, float(p.stun_time), float(p.panic_time), float(_powers.militia.panic_speed))
			stunned += 1
		elif dist <= float(p.hear_range):
			e.hear_threat(self)
	return stunned

## Rage form: spends a full mutation meter for a timed, near-unkillable super state.
func use_rage() -> bool:
	if not power_ready(&"rage"):
		return false
	var p: Dictionary = _powers.rage
	_rage_left = float(p.duration)
	_fear_tick = 0.0
	mutation = maxf(mutation - float(p.cost), 0.0)
	mutation_changed.emit(mutation, MAX_MUTATION)
	_play_oneshot(&"scream", 1.0)
	_shake_camera(0.7, 0.18)
	var tw := create_tween().set_parallel()
	tw.tween_property(_model, "scale", Vector3.ONE * float(p.scale), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_arm, "spring_length", 4.8, 0.5)
	tw.tween_property(_camera, "fov", 84.0, 0.5)
	if _rage_light == null:
		_rage_light = OmniLight3D.new()
		_rage_light.light_color = Color(1.0, 0.12, 0.05)
		_rage_light.omni_range = 4.0
		_rage_light.light_specular = 0.0
		_rage_light.position = Vector3(0, 1.4, 0)
		add_child(_rage_light)
	tw.tween_property(_rage_light, "light_energy", 1.0, 0.4).from(0.0)
	rage_changed.emit(true)
	return true

func _end_rage() -> void:
	_rage_left = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_model, "scale", Vector3.ONE, 0.5)
	tw.tween_property(_arm, "spring_length", 3.8, 0.6)
	tw.tween_property(_camera, "fov", 75.0, 0.6)
	if _rage_light:
		tw.tween_property(_rage_light, "light_energy", 0.0, 0.5)
	rage_changed.emit(false)

func _speed_mult() -> float:
	return float(_powers.rage.speed_mult) if is_raging() else 1.0

func _can_see(e: Militia) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.4, e.grab_point())
	q.exclude = [get_rid(), e.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _shake_camera(seconds: float, strength: float) -> void:
	var tw := create_tween()
	var steps := int(seconds / 0.04)
	for i in steps:
		var k := strength * (1.0 - float(i) / steps)
		tw.tween_property(_camera, "h_offset", randf_range(-k, k), 0.04)
		tw.parallel().tween_property(_camera, "v_offset", randf_range(-k, k), 0.04)
	tw.tween_property(_camera, "h_offset", 0.0, 0.04)
	tw.parallel().tween_property(_camera, "v_offset", 0.0, 0.04)

# Helpers -----------------------------------------------------------------

func _enemies_in_range(radius: float, downed: bool) -> Array:
	var result: Array = []
	for e in get_tree().get_nodes_in_group(&"militia"):
		if e.is_downed() == downed and e.is_alive_body() and e.global_position.distance_to(global_position) <= radius:
			result.append(e)
	result.sort_custom(func(a, b) -> bool:
		return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	return result

func _update_animation() -> void:
	if _anim == null or health <= 0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _oneshot_until and state in [State.GROUND, State.AIR]:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	match state:
		State.FEED:
			GeneratedAssets.play(_anim, &"feed")
		State.CLIMB:
			# Freeze the climb cycle when hanging still on the wall.
			GeneratedAssets.play(_anim, &"climb", 0.15, clampf(absf(velocity.y) / climb_speed, 0.0, 1.5))
		State.WALL_RUN:
			GeneratedAssets.play(_anim, &"wall_run", 0.1)
		State.POUNCE:
			GeneratedAssets.play(_anim, &"pounce", 0.1)
		State.AIR:
			if velocity.y < -2.0:
				GeneratedAssets.play(_anim, &"pounce", 0.2)
		_:
			if speed > sprint_speed * 0.7:
				GeneratedAssets.play(_anim, &"run", 0.2, speed / sprint_speed)
			elif speed > 0.5:
				GeneratedAssets.play(_anim, &"stalk", 0.2, clampf(speed / walk_speed, 0.6, 1.4))
			else:
				GeneratedAssets.play(_anim, &"idle", 0.3)

func _play_oneshot(clip: StringName, seconds: float) -> void:
	if GeneratedAssets.play(_anim, clip, 0.08, 1.6):
		_oneshot_until = Time.get_ticks_msec() / 1000.0 + seconds

func _update_model_facing(delta: float) -> void:
	var face := Vector3.ZERO
	match state:
		State.CLIMB:
			face = -_wall_normal
		State.FEED:
			return
		_:
			face = _input_dir() * 10.0
			if face.length() < 0.5:
				face = Vector3(velocity.x, 0, velocity.z)
	if face.length() > 0.5:
		var target := Basis.looking_at(face.normalized())
		_model.global_basis = _model.global_basis.slerp(target, clampf(delta * 12.0, 0, 1)).orthonormalized()
