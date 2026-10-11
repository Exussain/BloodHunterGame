class_name Militia
extends CharacterBody3D
## Placeholder traitor militia soldier: patrols, spots the volatile, shoots.
## The volatile's powers can grab (tendril), stun and panic (scream, rage) it.
## Full AI (cover, flanking, alarms) and gore come in later build steps.

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
	_spawn_blood(global_position + Vector3.UP * 1.2, 0.5)
	if health <= 0:
		_go_down()
	else:
		_alert(source)
		if GeneratedAssets.play(_anim, &"hit", 0.05, 1.3):
			_hit_until = Time.get_ticks_msec() / 1000.0 + 0.5

func take_pounce(source: Node3D) -> void:
	if is_standing():
		_spawn_blood(global_position + Vector3.UP * 1.0, 0.8)
		_go_down()
		_alert_nearby(source)

func begin_feed(feeder: Node3D) -> void:
	state = State.FED_ON
	_feeder = feeder

func finish_feed() -> void:
	state = State.DEAD
	_spawn_blood(global_position + Vector3.UP * 0.3, 1.4)
	if _anim == null:
		_model.scale = Vector3(1, 0.6, 1)

func _go_down() -> void:
	state = State.DOWNED
	velocity = Vector3.ZERO
	_muzzle_light.light_energy = 0.0
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
	var look := to - _grab_from
	look.y = 0
	if look.length() > 0.1:
		_face(look.normalized())
	if _grab_t >= 1.0:
		_end_grab()

func _end_grab() -> void:
	collision_layer = _saved_layers.x
	collision_mask = _saved_layers.y
	_spawn_blood(global_position + Vector3.UP * 0.5, 0.9)
	_go_down()

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

func _spawn_blood(at: Vector3, size: float) -> void:
	var pool := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = size
	disc.bottom_radius = size
	disc.height = 0.01
	pool.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.0, 0.0)
	mat.roughness = 0.05
	mat.metallic_specular = 0.9
	pool.material_override = mat
	get_parent().add_child(pool)
	pool.global_position = Vector3(at.x + randf_range(-0.3, 0.3), global_position.y + 0.02, at.z + randf_range(-0.3, 0.3))

# --- Behaviour --------------------------------------------------------------

func _physics_process(delta: float) -> void:
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

func _face(dir: Vector3) -> void:
	_model.global_basis = Basis.looking_at(dir)
