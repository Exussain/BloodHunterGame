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

@export_group("Camera")
## Resting field of view (deg); sprinting, pouncing and rage widen it from here.
@export var base_fov := 75.0
## Extra FOV (deg) at full sprint, during a pounce, and in rage form.
@export var sprint_fov := 7.0
@export var pounce_fov := 12.0
@export var rage_fov := 9.0
## How fast the rig catches up with the body (1/s), across and up/down, and the most
## it may trail behind (m). The trail gives speed a sense of weight without losing aim.
@export var follow_rate := 16.0
@export var follow_rate_vertical := 9.0
@export var max_trail := 0.6
@export var max_trail_vertical := 0.8
## Camera distance behind the shoulder (m), normal and in rage form.
@export var arm_length := 3.8
@export var rage_arm_length := 4.8
@export_group("")

## Ground speed (m/s) that the feet of each locomotion clip travel at when it plays at
## 1x, measured from the clips' planted-foot motion (tests/render/motion_probe.gd).
## Playback rate = ground speed / this, so the feet stay planted instead of skating.
const RUN_CLIP_SPEED := 6.2
const STALK_CLIP_SPEED := 1.6
## The climb clip gains only ~0.8 m/s; matching 6 m/s would need 7x, so it is played
## as fast as still reads (about 2.5x at full climb speed) and the hands slip a little.
const CLIMB_CLIP_SPEED := 2.4
## Below this ground speed the volatile stalks (crouch-walk); above it, it runs.
const STALK_MAX_SPEED := 3.2
## Triple_Combo_Attack holds three hits: [start, end] seconds of each.
const CLAW_HITS := [[0.2, 0.85], [1.05, 2.05], [2.05, 2.75]]
const CLAW_RATE := 1.7
## A claw within this many seconds of the last one plays the combo's next hit.
const COMBO_WINDOW := 0.8
## Run_and_Leap (the pounce clip): takeoff, the stretched airborne pose that is held
## through the flight, touchdown, and the end of the landing.
const LEAP_START := 1.62
const LEAP_HOLD := 1.92
const LEAP_LAND := 2.06
const LEAP_LAND_END := 2.4
## Zombie_Scream: the rear-up, hunch and roar, without the idle lead-in and recovery.
const SCREAM_START := 0.8
const SCREAM_END := 2.1
const SCREAM_RATE := 1.4
## Kneel_on_One_Knee_and_Stand starts kneeling; the stand-up begins at FEED_KNEEL_END.
## Feeding holds the kneel and spends its last FEED_STAND_TIME seconds standing up.
const FEED_KNEEL_END := 0.45
const FEED_STAND_TIME := 0.9
## Model turn: rate (1/s) toward the wanted heading, capped at MAX_TURN (rad/s).
## Render layer bit for the volatile's meshes; the camera fill light lights only this.
const FILL_LAYER := 2
const TURN_RATE := 12.0
const MAX_TURN := 12.0

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
## Tilts the visible body (lean into turns, tilt off a wall-run) without tilting the
## gameplay rays that hang off _model.
var _visual: Node3D
var _upper: UpperBodyLayer
var _fader: PoseFader
## Game time (s), advanced by physics ticks so it pauses with Engine.time_scale.
var _clock := 0.0
## The full-body one-shot showing now: its clip, end position (s) and rate.
var _oneshot_clip := &""
var _oneshot_end := 0.0
var _oneshot_rate := 1.0
var _claw_combo := 0
var _last_claw := -10.0
var _air_time := 0.0
var _jumped := false
var _was_grounded := false
var _fall_speed := 0.0
## While _clock < _face_lock_until the body turns toward _face_lock (feed, scream).
var _face_lock := Vector3.ZERO
var _face_lock_until := 0.0
var _yaw_rate := 0.0
var _prev_hvel := Vector3.ZERO
var _lean := Vector3.ZERO
var _hunch := 0.0
var _wall_run_spent := false
# Camera rig state (see _update_camera).
var _rig_pos := Vector3.INF
var _cam_dist := 3.8
var _dip := 0.0
var _dip_vel := 0.0
var _shake_left := 0.0
var _shake_total := 0.0
var _shake_strength := 0.0
var _shake_t := 0.0
var _exclude_tick := 0.0
var _physics_ticks := 0

func _ready() -> void:
	add_to_group(&"player")
	floor_snap_length = 0.4
	_build_body()
	_build_camera()
	_build_rays()
	_add_render_layer(_model, FILL_LAYER)
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
	_visual = Node3D.new()
	_model.add_child(_visual)
	var generated := GeneratedAssets.character("volatile")
	if generated:
		_visual.add_child(generated)
		_anim = GeneratedAssets.find_animation_player(generated)
		var skeletons := generated.find_children("*", "Skeleton3D", true, false)
		if _anim and not skeletons.is_empty():
			# Order matters: the fader smooths the base clip, then the upper layer goes on top.
			_fader = PoseFader.new()
			skeletons[0].add_child(_fader)
			_upper = UpperBodyLayer.new()
			skeletons[0].add_child(_upper)
			died.connect(_release_skeleton)
		return
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.55, 0.02, 0.02)
	red.roughness = 0.6
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.35, 0.3, 0.28)
	skin.roughness = 0.4
	_add_part(_visual, CapsuleMesh.new(), red, Vector3(0, 0.95, 0), Vector3(0.8, 1.0, 0.8))
	var head := SphereMesh.new()
	head.radius = 0.22
	head.height = 0.44
	_add_part(_visual, head, skin, Vector3(0, 1.75, -0.05), Vector3.ONE)
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(1, 0.9, 0.6)
	eye.emission_enabled = true
	eye.emission = Color(1, 0.75, 0.3)
	eye.emission_energy_multiplier = 6.0
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.035
	eye_mesh.height = 0.07
	_add_part(_visual, eye_mesh, eye, Vector3(-0.08, 1.78, -0.24), Vector3.ONE)
	_add_part(_visual, eye_mesh, eye, Vector3(0.08, 1.78, -0.24), Vector3.ONE)

## Puts every mesh under `node` on render layer `layer` as well as its own layers.
func _add_render_layer(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers |= layer
	for child in node.get_children():
		_add_render_layer(child, layer)

func _add_part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)

func _build_camera() -> void:
	# The rig is top-level and placed every rendered frame from the body's interpolated
	# transform (_update_camera), so it is kept out of physics interpolation itself.
	_yaw = Node3D.new()
	_yaw.position.y = 1.6
	_yaw.top_level = true
	_yaw.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_yaw)
	_pitch = Node3D.new()
	_pitch.rotation.x = -0.25
	_yaw.add_child(_pitch)
	# The spring arm only measures how far back the camera fits; the camera is a sibling
	# placed at a smoothed distance, so a pillar sweeping past pulls it in fast but lets
	# it out gently instead of popping both ways.
	_arm = SpringArm3D.new()
	_arm.spring_length = arm_length
	_arm.position = Vector3(0.6, 0.2, 0)
	_arm.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	_arm.add_excluded_object(get_rid())
	_pitch.add_child(_arm)
	_cam_dist = arm_length
	_camera = Camera3D.new()
	_camera.fov = base_fov
	_camera.far = 800.0
	_camera.position = _arm.position + Vector3(0, 0, _cam_dist)
	_pitch.add_child(_camera)
	_camera.make_current()
	# Soft fill light that travels with the camera so the volatile never turns into a silhouette.
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.85, 0.75)
	fill.light_energy = 0.9
	fill.omni_range = 8.0
	fill.light_specular = 0.2
	fill.shadow_enabled = false
	# Lights the volatile, not the street fog (it would hang a haze bubble around it).
	fill.light_volumetric_fog_energy = 0.0
	# Only the volatile's own meshes (render layer 2, see _ready) catch it, so it keeps her
	# readable at night without painting a disc of light on the street.
	fill.light_cull_mask = FILL_LAYER
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
	_clock += delta
	_physics_ticks += 1
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

	var fall := maxf(-velocity.y, 0.0)
	move_and_slide()

	if state in [State.GROUND, State.AIR]:
		state = State.GROUND if is_on_floor() else State.AIR
	var grounded := is_on_floor()
	if grounded:
		if not _was_grounded and _air_time > 0.15:
			_on_landed(maxf(fall, _fall_speed))
		_air_time = 0.0
		_jumped = false
		_fall_speed = 0.0
	else:
		_air_time += delta
		_fall_speed = maxf(_fall_speed, fall)
	_was_grounded = grounded

	_update_model_facing(delta)
	_update_lean(delta)
	_update_animation()

func _process(delta: float) -> void:
	_update_camera(delta)

## Puts the camera straight behind the body with no trailing, for teleports
## (level start, respawn, test placement).
func snap_camera() -> void:
	reset_physics_interpolation()
	_rig_pos = Vector3.INF
	_dip = 0.0
	_dip_vel = 0.0
	_update_camera(0.0)

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
		_jumped = true

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
	# One wall-run per jump: without the latch it re-entered every other frame, flickering
	# between wall-run and fall and climbing forever on the refreshed upward kick.
	if on_floor:
		_wall_run_spent = false
	if not on_floor and not _wall_run_spent and Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > 7.0:
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
		_jumped = true
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
	_wall_run_spent = true
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
		_jumped = true
		return
	# The side rays track the wall; is_on_wall() alone drops out because the run moves
	# along the wall, not into it.
	var still_on_wall := _left_ray.is_colliding() or _right_ray.is_colliding() or is_on_wall()
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
	_oneshot_clip = &""
	_play_at(&"pounce", LEAP_START, 0.08, 1.4)
	_shake_camera(0.12, 0.03 + 0.04 * charge)

func _process_pounce(delta: float) -> void:
	velocity.y -= _gravity * gravity_scale * 0.8 * delta
	for enemy in _enemies_in_range(2.4 if is_raging() else 1.6, false):
		enemy.take_pounce(self)
		velocity = Vector3(0, 2.0, 0)
		state = State.AIR
		_shake_camera(0.3, 0.1)
		_play_upper(&"claw", CLAW_HITS[0][0], CLAW_HITS[0][1], CLAW_RATE)
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
	# Quick follow-ups chain through the clip's three hits instead of replaying the first.
	_claw_combo = (_claw_combo + 1) % CLAW_HITS.size() if _clock - _last_claw < COMBO_WINDOW else 0
	_last_claw = _clock
	var hit: Array = CLAW_HITS[_claw_combo]
	_play_oneshot(&"claw", hit[0], hit[1], CLAW_RATE)
	var forward := -_model.global_basis.z
	var connected := false
	for enemy in _enemies_in_range(claw_range, false):
		var to: Vector3 = enemy.global_position - global_position
		to.y = 0
		if to.normalized().dot(forward) > 0.3:
			enemy.take_damage(claw_damage * (float(_powers.rage.claw_mult) if is_raging() else 1.0), self)
			connected = true
	if connected:
		_shake_camera(0.14, 0.04)

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
		_lock_facing(look, 0.5)

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
	_shake_camera(0.18, clampf(amount * 0.004, 0.02, 0.08))
	if health <= 0:
		# Collapse as a ragdoll, carrying the run and knocked back off its feet;
		# the death clip is the fallback for a model without a rig.
		_release_skeleton()
		var back := -facing()
		if preload("res://scripts/world/ragdoll.gd").activate(_model, self, velocity * 0.7 + back * 0.6, back * 1.6) == null:
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
	_lock_facing(target.global_position - global_position, 0.35)
	_play_oneshot(&"claw", CLAW_HITS[2][0], CLAW_HITS[2][1], CLAW_RATE)
	_shake_camera(0.15, 0.04)
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
	_play_oneshot(&"scream", SCREAM_START, SCREAM_END, SCREAM_RATE)
	var forward := -_camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	_lock_facing(forward, 0.6)
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
	_play_oneshot(&"scream", SCREAM_START, SCREAM_END, SCREAM_RATE)
	_shake_camera(0.7, 0.18)
	# Transform tweens run on physics ticks so physics interpolation smooths them.
	# The FOV and camera distance follow is_raging() in _update_camera.
	var tw := create_tween().set_parallel().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(_model, "scale", Vector3.ONE * float(p.scale), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	var tw := create_tween().set_parallel().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(_model, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _rage_light:
		tw.tween_property(_rage_light, "light_energy", 0.0, 0.5)
	rage_changed.emit(false)

func _speed_mult() -> float:
	return float(_powers.rage.speed_mult) if is_raging() else 1.0

func _can_see(e: Militia) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.4, e.grab_point())
	q.exclude = [get_rid(), e.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## Shakes the camera for `seconds`, fading out; `strength` is the peak offset (m).
## A stronger shake replaces a weaker one already running; a weaker one is ignored.
func _shake_camera(seconds: float, strength: float) -> void:
	var current := _shake_strength * (_shake_left / _shake_total) if _shake_left > 0.0 else 0.0
	if strength < current:
		return
	_shake_total = maxf(seconds, 0.01)
	_shake_left = _shake_total
	_shake_strength = strength

# Helpers -----------------------------------------------------------------

func _enemies_in_range(radius: float, downed: bool) -> Array:
	var result: Array = []
	for e in get_tree().get_nodes_in_group(&"militia"):
		if e.is_downed() == downed and e.is_alive_body() and e.global_position.distance_to(global_position) <= radius:
			result.append(e)
	result.sort_custom(func(a, b) -> bool:
		return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	return result

# Animation ---------------------------------------------------------------

func _update_animation() -> void:
	if _anim == null:
		return
	if health <= 0:
		# Death (and any ragdoll) owns the skeleton from here.
		_release_skeleton()
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if _clock < _oneshot_until and state in [State.GROUND, State.AIR]:
		if state == State.AIR or speed < 2.0 or _upper == null:
			return
		# Started moving mid-swing: the arms finish the move on the upper-body layer
		# while the legs go back to running, so the planted feet don't skate.
		var pos := _anim.current_animation_position
		if pos < _oneshot_end:
			_upper.play(_anim.get_animation(StringName("game/" + _oneshot_clip)), pos, _oneshot_end, _oneshot_rate, 0.0)
		_oneshot_until = 0.0
	match state:
		State.FEED:
			# Hold the kneel while feeding, then stand up over the last FEED_STAND_TIME.
			var kneel_rate := FEED_KNEEL_END / maxf(feed_time - FEED_STAND_TIME, 0.1)
			_play(&"feed", 0.3, kneel_rate if _feed_left > FEED_STAND_TIME else 1.1)
		State.CLIMB:
			var along := velocity - _wall_normal * velocity.dot(_wall_normal)
			# Frozen mid-reach when hanging still.
			_play(&"climb", 0.15, clampf(along.length() / CLIMB_CLIP_SPEED, 0.0, 2.6))
		State.WALL_RUN:
			# The Meshy wall-run clip is a jump up the wall that floats the body off the
			# collider; a stride-matched run tilted off the wall (_update_lean) reads better.
			_play(&"run", 0.12, clampf(speed / RUN_CLIP_SPEED, 0.8, 3.0))
		State.POUNCE:
			_leap_pose(LEAP_START, 0.1, 1.4)
		State.AIR:
			if _jumped:
				_leap_pose(LEAP_START + 0.06, 0.12, 1.3)
			elif _air_time > 0.3 or velocity.y < -4.0:
				# Stepped or knocked off an edge: drift into the airborne pose.
				_leap_pose(LEAP_HOLD - 0.06, 0.3, 0.4)
		_:
			_locomotion(speed)

func _locomotion(speed: float) -> void:
	var input := _input_dir().length()
	var target := input * (sprint_speed if Input.is_action_pressed("sprint") else walk_speed) * _speed_mult()
	if input < 0.1 and speed < 4.0 or speed < 0.4:
		_play(&"idle", 0.25 if speed < 1.0 else 0.18)
		return
	# Pick the gait from where the volatile is heading, so a sprint start goes straight
	# to the run instead of flashing the crouch-walk for a few frames.
	var current := GeneratedAssets.current_clip(_anim)
	var run_above := STALK_MAX_SPEED - (0.6 if current == &"run" else 0.0)
	if maxf(speed, target) > run_above:
		_play(&"run", 0.18, clampf(speed / RUN_CLIP_SPEED, 0.7, 3.0))
	else:
		_play(&"stalk", 0.22, clampf(speed / STALK_CLIP_SPEED, 0.6, 2.2))

## Switches the base clip (or updates its rate). Cross-fades are done by the PoseFader
## from the last shown pose, not by AnimationPlayer, so they take `blend` real seconds
## however the clip rate changes meanwhile (AnimationPlayer scales fades by its rate).
func _play(clip: StringName, blend: float, rate := 1.0) -> bool:
	if GeneratedAssets.current_clip(_anim) != clip and _fader:
		_fader.fade(blend)
	return GeneratedAssets.play(_anim, clip, 0.0 if _fader else blend, rate)

## Starts `clip` at `from` seconds, cross-fading over `blend` seconds.
func _play_at(clip: StringName, from: float, blend: float, rate := 1.0) -> bool:
	if _fader:
		_fader.fade(blend)
	return GeneratedAssets.play_at(_anim, clip, from, 0.0 if _fader else blend, rate)

## Hands the skeleton over to the death animation or ragdoll: the fader and the upper
## layer stop touching bones at once (connected to `died`).
func _release_skeleton() -> void:
	if _upper:
		_upper.stop(true)
	for mod: SkeletonModifier3D in [_fader, _upper]:
		if mod:
			mod.active = false

## Plays (or holds) the airborne part of Run_and_Leap: enters at `entry` and plays to
## the stretched-out LEAP_HOLD pose, then nearly freezes there until landing.
func _leap_pose(entry: float, blend: float, rate: float) -> void:
	var pos := _anim.current_animation_position
	if GeneratedAssets.current_clip(_anim) != &"pounce" or pos < LEAP_START - 0.05 or pos > LEAP_LAND:
		_play_at(&"pounce", entry, blend, rate)
	elif pos >= LEAP_LAND - 0.04:
		_anim.speed_scale = 0.0
	elif pos >= LEAP_HOLD:
		_anim.speed_scale = 0.1

func _on_landed(fall_speed: float) -> void:
	# The camera dips with the impact and springs back (_update_camera).
	_dip_vel -= clampf(fall_speed * 0.12, 0.0, 2.2)
	if fall_speed > 14.0:
		_shake_camera(0.25, clampf(fall_speed * 0.004, 0.0, 0.1))
	if _anim == null or health <= 0 or state != State.GROUND:
		return
	# A hard landing at low speed shows the leap's touchdown; at a run the legs carry on.
	if fall_speed > 5.0 and Vector2(velocity.x, velocity.z).length() < 3.0:
		_play_oneshot(&"pounce", LEAP_LAND, LEAP_LAND_END, 1.3, 0.06)

## Plays [from, to] seconds of a one-shot clip. Standing on the ground it is full-body,
## so the feet step with the move; otherwise only the arms and torso play it, over
## whatever the legs are doing (running, falling, climbing).
func _play_oneshot(clip: StringName, from: float, to: float, rate: float, blend := 0.08) -> void:
	if _anim == null:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 2.0
	if (state != State.GROUND or moving) and _upper:
		_play_upper(clip, from, to, rate)
		return
	if _play_at(clip, from, blend, rate):
		if _upper:
			_upper.stop()
		_oneshot_clip = clip
		_oneshot_end = to
		_oneshot_rate = rate
		_oneshot_until = _clock + (to - from) / rate

func _play_upper(clip: StringName, from: float, to: float, rate: float) -> void:
	if _upper and _anim and _anim.has_animation(StringName("game/" + clip)):
		_upper.play(_anim.get_animation(StringName("game/" + clip)), from, to, rate)

## Turns the body to face `dir` for the next `seconds`, overriding movement.
func _lock_facing(dir: Vector3, seconds: float) -> void:
	dir.y = 0.0
	if dir.length() > 0.01:
		_face_lock = dir.normalized()
		_face_lock_until = _clock + seconds

func _update_model_facing(delta: float) -> void:
	if health <= 0:
		return
	var face := Vector3.ZERO
	var rate := TURN_RATE
	if _clock < _face_lock_until:
		face = _face_lock
		rate = TURN_RATE * 1.6
	else:
		match state:
			State.CLIMB:
				face = -_wall_normal
			State.FEED:
				return
			State.POUNCE, State.WALL_RUN:
				face = Vector3(velocity.x, 0, velocity.z)
			_:
				face = _input_dir() * 10.0
				if face.length() < 0.5:
					face = Vector3(velocity.x, 0, velocity.z)
	var yaw := _model.rotation.y
	var step := 0.0
	if face.length() > 0.5:
		# Exponential approach with a speed cap: snappy on small corrections, but a
		# 180 is a visible ~0.3 s turn instead of a 36-degree jump in one frame.
		var target := atan2(-face.x, -face.z)
		var diff := wrapf(target - yaw, -PI, PI)
		var cap := MAX_TURN * rate / TURN_RATE * delta
		step = clampf(diff * minf(rate * delta, 1.0), -cap, cap)
		# Only the yaw is set, so the rage-form scale tween on _model is left alone.
		_model.rotation = Vector3(0.0, wrapf(yaw + step, -PI, PI), 0.0)
	_yaw_rate = lerpf(_yaw_rate, step / maxf(delta, 0.0001), minf(10.0 * delta, 1.0))

## Leans the visible body: into turns and against acceleration on the ground, and away
## from the wall on a wall-run so the feet reach it. Purely visual.
func _update_lean(delta: float) -> void:
	if health <= 0:
		# Frozen at death: the ragdoll bakes its final pose relative to this pivot.
		return
	var hvel := Vector3(velocity.x, 0, velocity.z)
	var accel := (hvel - _prev_hvel) / maxf(delta, 0.0001)
	_prev_hvel = hvel
	var target := Vector3.ZERO
	var hunch := 0.0
	match state:
		State.GROUND:
			var fwd := -_model.global_basis.z
			target.z = clampf(atan(hvel.length() * _yaw_rate / 9.8) * 0.45, -0.3, 0.3)
			target.x = -clampf(accel.dot(fwd) * 0.006, -0.1, 0.14)
		State.WALL_RUN:
			var side := _model.global_basis.x.dot(_wall_normal)
			target.z = -signf(side) * 0.45
		State.FEED:
			if _feed_left > FEED_STAND_TIME:
				# Hunched over the body, tearing at it: a heavy, uneven bob.
				target.x = -0.28 - 0.08 * sin(_clock * 9.0) * absf(sin(_clock * 2.3))
				hunch = 0.3
	_lean = _lean.lerp(target, minf(delta * 8.0, 1.0))
	_visual.rotation = _lean
	# While feeding, the body shifts forward over the kill (visual only; the collider stays).
	_hunch = lerpf(_hunch, hunch, minf(delta * 6.0, 1.0))
	_visual.position = Vector3(0, 0, -_hunch)

# Camera ------------------------------------------------------------------

func _update_camera(delta: float) -> void:
	var body := get_global_transform_interpolated().origin if is_physics_interpolated_and_enabled() else global_position
	var target := body + Vector3.UP * 1.6
	if _rig_pos == Vector3.INF or _rig_pos.distance_to(target) > 4.0:
		_rig_pos = target
	else:
		# Trail a little behind the body, more vertically (stairs, landings) than across.
		var kh := 1.0 - exp(-follow_rate * delta)
		var kv := 1.0 - exp(-follow_rate_vertical * delta)
		var nx := lerpf(_rig_pos.x, target.x, kh)
		var nz := lerpf(_rig_pos.z, target.z, kh)
		var ny := lerpf(_rig_pos.y, target.y, kv)
		var lag := Vector2(target.x - nx, target.z - nz)
		if lag.length() > max_trail:
			lag = lag.limit_length(max_trail)
			nx = target.x - lag.x
			nz = target.z - lag.y
		ny = clampf(ny, target.y - max_trail_vertical, target.y + max_trail_vertical)
		_rig_pos = Vector3(nx, ny, nz)
	# Landing dip: a damped spring kicked by _on_landed.
	if delta > 0.0:
		_dip_vel += (-_dip * 140.0 - _dip_vel * 17.0) * delta
		_dip += _dip_vel * delta
	_yaw.global_position = _rig_pos + Vector3.UP * _dip

	# Collision: pull in fast (never more than 0.15 m behind the safe distance), ease out slowly.
	_arm.spring_length = lerpf(_arm.spring_length, rage_arm_length if is_raging() else arm_length, 1.0 - exp(-4.0 * delta))
	_exclude_tick -= delta
	if _exclude_tick <= 0.0:
		# Soldiers (and ones flying on the tendril) shouldn't shove the camera around.
		_exclude_tick = 1.0
		for e in get_tree().get_nodes_in_group(&"militia"):
			if e is CollisionObject3D:
				_arm.add_excluded_object(e.get_rid())
	# The arm measures on physics ticks and reads 0 until its first one.
	var safe := _arm.get_hit_length() if _physics_ticks >= 2 else _arm.spring_length
	if safe < _cam_dist:
		_cam_dist = minf(lerpf(_cam_dist, safe, 1.0 - exp(-30.0 * delta)), safe + 0.15)
	else:
		_cam_dist = lerpf(_cam_dist, safe, 1.0 - exp(-4.0 * delta))
	if delta == 0.0:
		_cam_dist = safe
	_camera.position = _arm.position + Vector3(0, 0, _cam_dist)

	# FOV: wider with speed, a punch-in while charging a pounce, a kick on launch.
	var fov := base_fov
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if state in [State.GROUND, State.WALL_RUN]:
		fov += sprint_fov * clampf((hspeed - walk_speed) / (sprint_speed - walk_speed), 0.0, 1.0)
	if _pounce_charge >= 0.0:
		fov -= 5.0 * _pounce_charge
	if state == State.POUNCE:
		fov += pounce_fov
	if is_raging():
		fov += rage_fov
	_camera.fov = lerpf(_camera.fov, fov, 1.0 - exp(-(9.0 if state == State.POUNCE else 4.5) * delta))

	# Shake: smooth, decaying layered sines (no per-step random jumps).
	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - delta, 0.0)
		_shake_t += delta
		var k := _shake_strength * pow(_shake_left / _shake_total, 1.5)
		_camera.h_offset = k * (0.6 * sin(_shake_t * 47.0) + 0.4 * sin(_shake_t * 83.0 + 1.3))
		_camera.v_offset = k * (0.6 * sin(_shake_t * 53.0 + 2.1) + 0.4 * sin(_shake_t * 97.0))
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0

## Plays the arms-and-torso part of an animation clip over whatever the AnimationPlayer
## is doing with the legs, fading in and out, so the volatile can claw mid-stride, mid-air
## or on a wall. A new take cross-fades from the pose the last one left.
class UpperBodyLayer extends SkeletonModifier3D:
	## Bones the layer drives, with how much of the clip each one takes. The lower spine
	## is only partly driven so the twist blends into the running hips.
	const BONES := {
		"Spine02": 0.5, "Spine01": 0.8, "Spine": 1.0, "neck": 1.0, "Head": 1.0,
		"LeftShoulder": 1.0, "LeftArm": 1.0, "LeftForeArm": 1.0, "LeftHand": 1.0,
		"RightShoulder": 1.0, "RightArm": 1.0, "RightForeArm": 1.0, "RightHand": 1.0,
	}
	const FADE_IN := 0.08
	const FADE_OUT := 0.16
	const CROSSFADE := 0.1

	var _anim: Animation
	## [track index, bone index, weight] per driven bone.
	var _tracks: Array = []
	var _t := 0.0
	var _end := 0.0
	var _rate := 1.0
	var _left := 0.0
	var _w := 0.0
	var _last: Dictionary = {}
	var _snap: Dictionary = {}
	var _snap_k := 1.0

	## Plays [from, to] seconds of `anim` at `rate`. `fade_in` 0 starts at full weight
	## (used when taking over a full-body one-shot that was already showing).
	func play(anim: Animation, from: float, to: float, rate: float, fade_in := FADE_IN) -> void:
		var skel := get_skeleton()
		if skel == null or anim == null:
			return
		if _w > 0.0:
			_snap = _last.duplicate()
			_snap_k = 0.0
		if anim != _anim:
			_anim = anim
			_tracks.clear()
			for t in anim.get_track_count():
				if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
					continue
				var bone_name := String(anim.track_get_path(t)).get_slice(":", 1)
				var bone := skel.find_bone(bone_name)
				if bone >= 0 and BONES.has(bone_name):
					_tracks.append([t, bone, float(BONES[bone_name])])
		_t = from
		_end = to
		_rate = rate
		_left = (to - from) / maxf(rate, 0.01)
		if fade_in <= 0.0:
			_w = 1.0

	## Fades the layer out (or drops it at once with `now`).
	func stop(now := false) -> void:
		_left = 0.0
		if now:
			_w = 0.0

	func is_playing() -> bool:
		return _left > 0.0

	func _process_modification_with_delta(delta: float) -> void:
		if _anim == null or (_left <= 0.0 and _w <= 0.0):
			return
		var skel := get_skeleton()
		_left = maxf(_left - delta, 0.0)
		var want := 1.0 if _left > FADE_OUT else _left / FADE_OUT
		_w = move_toward(_w, want, delta / FADE_IN) if want > _w else want
		_t = minf(_t + delta * _rate, _end)
		_snap_k = minf(_snap_k + delta / CROSSFADE, 1.0)
		var k := smoothstep(0.0, 1.0, _snap_k)
		for e: Array in _tracks:
			var q := _anim.rotation_track_interpolate(e[0], _t)
			if k < 1.0 and _snap.has(e[1]):
				q = (_snap[e[1]] as Quaternion).slerp(q, k)
			_last[e[1]] = q
			var cur := skel.get_bone_pose_rotation(e[1])
			skel.set_bone_pose_rotation(e[1], cur.slerp(q, _w * e[2]))

## Cross-fades the base animation from the pose shown last frame ("frozen pose" blending),
## so clip changes take real time whatever rate the AnimationPlayer runs at, and a new
## change mid-fade starts from what is actually on screen instead of popping.
class PoseFader extends SkeletonModifier3D:
	var _pos := PackedVector3Array()
	var _rot: Array[Quaternion] = []
	var _from_pos := PackedVector3Array()
	var _from_rot: Array[Quaternion] = []
	var _left := 0.0
	var _total := 0.0

	## Starts fading from the current on-screen pose to the animation over `seconds`.
	func fade(seconds: float) -> void:
		if _pos.is_empty() or seconds <= 0.0:
			_left = 0.0
			return
		_from_pos = _pos.duplicate()
		_from_rot = _rot.duplicate()
		_total = seconds
		_left = seconds

	func _process_modification_with_delta(delta: float) -> void:
		var skel := get_skeleton()
		var count := skel.get_bone_count()
		if _pos.size() != count:
			_pos.resize(count)
			_rot.resize(count)
			_left = 0.0
		var k := 1.0
		if _left > 0.0:
			_left = maxf(_left - delta, 0.0)
			k = smoothstep(0.0, 1.0, 1.0 - _left / _total)
		for b in count:
			var p := skel.get_bone_pose_position(b)
			var r := skel.get_bone_pose_rotation(b)
			if k < 1.0:
				p = _from_pos[b].lerp(p, k)
				r = _from_rot[b].slerp(r, k)
				skel.set_bone_pose_position(b, p)
				skel.set_bone_pose_rotation(b, r)
			_pos[b] = p
			_rot[b] = r
