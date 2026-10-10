class_name Militia
extends CharacterBody3D
## Placeholder traitor militia soldier: patrols, spots the volatile, shoots.
## Full AI (cover, flanking, alarms, panic) and gore come in later build steps.

enum State { PATROL, ALERT, DOWNED, FED_ON, DEAD }

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
var _muzzle_light: OmniLight3D
var _patrol_index := 0
var _fire_timer := 0.0
var _player: Volatile
var _feeder: Node3D

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
	return state in [State.PATROL, State.ALERT, State.DOWNED]

# --- Damage -----------------------------------------------------------------

func take_damage(amount: float, source: Node3D) -> void:
	if state in [State.DOWNED, State.FED_ON, State.DEAD]:
		return
	health -= amount
	_spawn_blood(global_position + Vector3.UP * 1.2, 0.5)
	if health <= 0:
		_go_down()
	else:
		_alert(source)

func take_pounce(source: Node3D) -> void:
	if state in [State.PATROL, State.ALERT]:
		_spawn_blood(global_position + Vector3.UP * 1.0, 0.8)
		_go_down()
		_alert_nearby(source)

func begin_feed(feeder: Node3D) -> void:
	state = State.FED_ON
	_feeder = feeder

func finish_feed() -> void:
	state = State.DEAD
	_spawn_blood(global_position + Vector3.UP * 0.3, 1.4)
	_model.scale = Vector3(1, 0.6, 1)

func _go_down() -> void:
	state = State.DOWNED
	velocity = Vector3.ZERO
	_muzzle_light.light_energy = 0.0
	var tw := create_tween()
	tw.tween_property(_model, "rotation:x", -PI / 2, 0.35).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_model, "position:y", 0.38, 0.35)

func _alert(source: Node3D) -> void:
	if source is Volatile:
		_player = source
	state = State.ALERT

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
		_:
			velocity.x = 0
			velocity.z = 0
	move_and_slide()
	GeneratedAssets.drive_locomotion(_anim, Vector2(velocity.x, velocity.z).length(), walk_speed * 3.0)
	_muzzle_light.light_energy = maxf(_muzzle_light.light_energy - delta * 40.0, 0.0)

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
