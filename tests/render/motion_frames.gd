extends SceneTree
## Renders short frame sequences of the volatile in motion, through the game camera, for
## judging animation poses, blends and camera framing (needs a GPU or software Vulkan):
##   godot --resolution 960x540 -s res://tests/render/motion_frames.gd -- <out_dir> [shot ...]
## Shots: run, claw, pounce, climb, wallrun, feed, powers. No shot names renders them all.
## Each frame plays the action for a set time, then freezes the game to capture it.

var _out := "user://motion_frames"
var _level: Node
var _player: Volatile
var _shots: PackedStringArray = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
		_shots = args.slice(1)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _want(shot: String) -> bool:
	return _shots.is_empty() or _shots.has(shot)

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _snap(name: String) -> void:
	Engine.time_scale = 0.0
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name, " state=", Volatile.State.keys()[_player.state], " clip=",
		_player._anim.current_animation, " t=%.2f" % _player._anim.current_animation_position)
	Engine.time_scale = 1.0

func _place(pos: Vector3, yaw: float, pitch := -0.2) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.state = Volatile.State.AIR
	_player._yaw.rotation = Vector3(0, yaw, 0)
	_player._pitch.rotation.x = pitch
	_player._model.rotation = Vector3(0, yaw, 0)
	if _player.has_method(&"snap_camera"):
		_player.call(&"snap_camera")

func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "pounce", "attack", "jump"]:
		Input.action_release(a)

## A z where the east apartment wall (x = 20) runs unbroken for `length` metres.
func _wall_run_z(length: float) -> float:
	var space := _player.get_world_3d().direct_space_state
	for z in range(-80, 70):
		var ok := true
		for dz in range(0, int(length) + 1):
			var q := PhysicsRayQueryParameters3D.create(Vector3(16, 2.0, z + dz), Vector3(30, 2.0, z + dz))
			q.exclude = [_player.get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty() or absf(hit.position.x - 20.0) > 0.05:
				ok = false
				break
		if ok:
			return z
	return 0.0

func _run() -> void:
	_level = load("res://scenes/world/haft_hoz.tscn").instantiate()
	root.add_child(_level)
	for m in get_nodes_in_group(&"militia"):
		m.free()
	_player = get_first_node_in_group(&"player")
	await _physics(30)
	for child in _level.get_children():
		if child.has_method(&"show_message"):
			child.show_message("")

	if _want("run"):
		# Sprint start and stop down the lane; camera looks along -Z.
		_place(Vector3(8, 0.3, 34), 0.0)
		await _physics(30)
		Input.action_press("sprint")
		Input.action_press("move_forward")
		await _physics(6)
		await _snap("run_a_start_0.1s")
		await _physics(40)
		await _snap("run_b_full_sprint")
		_release_all()
		await _physics(6)
		await _snap("run_c_stop_0.1s")
		await _physics(30)

	if _want("claw"):
		_place(Vector3(8, 0.3, 30), 0.0, -0.1)
		await _physics(30)
		_player._yaw.rotation.y = 0.6  # three-quarter view of the swing
		_player._claw()
		await _physics(9)
		await _snap("claw_a_hit1")
		await _physics(18)
		_player._claw()
		await _physics(16)
		await _snap("claw_b_hit2")
		await _physics(40)

	if _want("pounce"):
		_place(Vector3(8, 0.3, 30), 0.0, 0.05)
		await _physics(30)
		_player._yaw.rotation.y = 0.35
		Input.action_press("pounce")
		await _physics(30)
		await _snap("pounce_a_charge")
		Input.action_release("pounce")
		await _physics(5)
		await _snap("pounce_b_launch")
		await _physics(20)
		await _snap("pounce_c_flight")
		var landed := false
		for i in 120:
			await physics_frame
			if _player.is_on_floor():
				landed = true
				break
		await _physics(4)
		await _snap("pounce_d_landing")
		await _physics(30)

	if _want("climb"):
		var wall_z := _wall_run_z(3.0)
		_place(Vector3(18.6, 0.3, wall_z + 1.0), -PI / 2 + 0.5, -0.05)
		await _physics(20)
		Input.action_press("move_forward")
		await _physics(30)
		await _snap("climb_a")
		await _physics(8)
		await _snap("climb_b")
		_release_all()
		await _physics(120)

	if _want("wallrun"):
		var z := _wall_run_z(14.0)
		_place(Vector3(19.45, 0.3, z + 1.0), PI + 0.5, -0.1)
		await _physics(10)
		# Sprint along the wall and jump: the side ray catches it and the run starts.
		Input.action_press("sprint")
		Input.action_press("move_forward")
		await _physics(20)
		Input.action_press("jump")
		await _physics(2)
		Input.action_release("jump")
		await _physics(30)
		await _snap("wallrun_a")
		_release_all()
		await _physics(60)

	if _want("feed"):
		_place(Vector3(8, 0.3, 30), 0.4, -0.25)
		var m := Militia.new()
		m.sight_range = 0.0
		m.hit_chance = 0.0
		_level.add_child(m)
		m.global_position = Vector3(8, 0.3, 28.4)
		await _physics(20)
		m.take_pounce(_player)
		await _physics(60)
		_player.global_position = m.global_position + Vector3(0, 0.3, 1.2)
		if _player.has_method(&"snap_camera"):
			_player.call(&"snap_camera")
		await _physics(20)
		Input.action_press("feed")
		await _physics(2)
		Input.action_release("feed")
		await _physics(40)
		await _snap("feed_a_kneel")
		await _physics(150)

	if _want("powers"):
		_player.add_mutation(100.0)
		for child in _level.get_children():
			if child.has_method(&"show_message"):
				child.show_message("")
		_place(Vector3(8, 0.3, 24), 0.0, -0.05)
		await _physics(20)
		_player.use_scream()
		await _physics(12)
		await _snap("power_a_scream")
		await _physics(60)
		_player.mutation = Volatile.MAX_MUTATION
		_player.use_rage()
		await _physics(40)
		await _snap("power_b_rage")
	quit()
