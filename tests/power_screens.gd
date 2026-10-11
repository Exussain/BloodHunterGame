extends SceneTree
## Renders evidence screenshots of the volatile's powers (needs a GPU or software Vulkan):
##   godot -s res://tests/power_screens.gd -- <output_dir>
## Each shot runs the power, lets it play for a moment, then freezes time to capture it.

var _out := "user://power_screens"
var _level: Node
var _player: Volatile

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _snap(name: String) -> void:
	# Freeze the action, then give the renderer frames to settle (TAA, fog, SDFGI).
	Engine.time_scale = 0.0
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)
	Engine.time_scale = 1.0

func _soldier(pos: Vector3, variant := "militia_rifleman") -> Militia:
	var m := Militia.new()
	m.variant = variant
	m.sight_range = 0.0
	m.hit_chance = 0.0
	_level.add_child(m)
	m.global_position = pos
	return m

func _place(pos: Vector3, look_at_point: Vector3, pitch := -0.12) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.state = Volatile.State.GROUND
	_player._yaw.global_position = pos + Vector3.UP * 1.6
	var flat := Vector3(look_at_point.x, pos.y + 1.6, look_at_point.z)
	_player._yaw.look_at(flat)
	_player._pitch.rotation.x = pitch
	var face := flat - _player._yaw.global_position
	_player._model.global_basis = Basis.looking_at(Vector3(face.x, 0, face.z).normalized())

## Highest walkable point under (x, z), for putting a soldier on a roof.
func _roof_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -1, z))
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else 0.0

func _run() -> void:
	_level = load("res://scenes/world/haft_hoz.tscn").instantiate()
	root.add_child(_level)
	for m in get_nodes_in_group(&"militia"):
		m.free()
	_player = get_first_node_in_group(&"player")
	await _physics(30)
	_player.add_mutation(100.0)
	# Clear the three "new power" banners so they don't cover the shots.
	for child in _level.get_children():
		if child.has_method(&"show_message"):
			child.show_message("")

	# 1. Tendril: yank a soldier off the far side of the pool, over its tiled edge.
	var lookout := _soldier(Vector3(-4.6, 0.5, 18), "militia_heavy")
	await _physics(20)
	_place(Vector3(8, 0.2, 31), lookout.global_position, -0.08)
	await _physics(4)
	print("tendril grabbed: ", _player.use_tendril())
	await _physics(9)
	await _snap("01_tendril_grab")
	await _physics(80)

	# 2. Scream: a squad of three on the lane ahead.
	var squad: Array[Militia] = []
	for offset: Vector3 in [Vector3(-2, 0, -7), Vector3(1.5, 0, -8.5), Vector3(4, 0, -11)]:
		squad.append(_soldier(Vector3(8, 0.2, 20) + offset, "militia_officer" if offset.x > 3 else "militia_rifleman"))
	await _physics(20)
	_place(Vector3(8, 0.2, 20), Vector3(9, 0, 8), -0.05)
	await _physics(4)
	_player.use_scream()
	await _physics(10)
	await _snap("02_scream")
	await _physics(150)
	await _snap("03_scream_panic")

	# 3. Rage form, with fresh soldiers breaking and running.
	for m in squad:
		m.free()
	for offset: Vector3 in [Vector3(-3, 0, -9), Vector3(2, 0, -12)]:
		_soldier(Vector3(8, 0.2, 0) + offset)
	await _physics(20)
	_place(Vector3(8, 0.2, 0), Vector3(8, 0, -12), -0.15)
	await _physics(4)
	_player.mutation = Volatile.MAX_MUTATION
	_player.use_rage()
	await _physics(50)
	await _snap("04_rage_form")
	quit()
