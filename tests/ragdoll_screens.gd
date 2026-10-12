extends SceneTree
## Renders evidence sequences of militia deaths (needs a GPU or software Vulkan):
##   godot -s res://tests/ragdoll_screens.gd -- <output_dir> [scenarios] [times]
## scenarios: comma list of pounce, claw, tendril, feed, volatile (default: the first three).
## times: comma list of seconds after the soldier goes down (default 0.1,0.3,0.6,1.2,3.0).
## A fixed side camera frames each fall, so consecutive frames show how smoothly it settles.

var _out := "user://ragdoll_screens"
var _scenarios: PackedStringArray = ["pounce", "claw", "tendril"]
var _times: Array[float] = [0.1, 0.3, 0.6, 1.2, 3.0]
var _level: Node
var _player: Volatile
var _cam: Camera3D

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1 and args[1] != "":
		_scenarios = args[1].split(",")
	if args.size() > 2:
		_times.clear()
		for t in args[2].split(","):
			_times.append(float(t))
	DirAccess.make_dir_recursive_absolute(_out)
	# Small frames: software Vulkan renders these slowly.
	root.size = Vector2i(960, 540)
	_run.call_deferred()

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _snap(file: String) -> void:
	# Freeze the action, then give the renderer frames to settle (TAA, fog, SDFGI).
	Engine.time_scale = 0.0
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(file + ".png"))
	print("saved ", file)
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
	if _player.has_method(&"snap_camera"):
		_player.snap_camera()  # no trailing camera rig after a teleport

## Points the observer camera at `focus` from the side of the line `along`.
func _frame(focus: Vector3, along: Vector3) -> void:
	var side := along.cross(Vector3.UP).normalized()
	_cam.global_position = focus + side * 3.4 + along.normalized() * 1.0 + Vector3.UP * 1.3
	_cam.look_at(focus + Vector3.UP * 0.35)
	_cam.make_current()

## Waits for `m` to go down (up to `limit` frames), then captures the sequence.
func _sequence(tag: String, m: Militia, along: Vector3, limit := 240) -> void:
	for i in limit:
		if m.is_downed():
			break
		await physics_frame
	print(tag, " downed: ", m.is_downed(), " at ", m.global_position)
	_frame(m.global_position, along)
	var elapsed := 0.0
	for t in _times:
		await _physics(maxi(roundi((t - elapsed) * 60.0), 0))
		elapsed = t
		await _snap("%s_%ss" % [tag, String.num(t, 2)])
	print(tag, " rest position: ", m.global_position, " state ", m.state)

func _run() -> void:
	_level = load("res://scenes/world/haft_hoz.tscn").instantiate()
	root.add_child(_level)
	for m in get_nodes_in_group(&"militia"):
		m.free()
	_player = get_first_node_in_group(&"player")
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_level.add_child(_cam)
	# Soft fill on the observer, like the volatile's own camera fill, so the body reads.
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.85, 0.75)
	fill.light_energy = 0.7
	fill.omni_range = 7.0
	fill.light_specular = 0.2
	_cam.add_child(fill)
	await _physics(30)
	_player.add_mutation(100.0)
	for child in _level.get_children():
		if child is CanvasLayer:
			child.visible = false  # HUD off: these are shots of the bodies

	var n := 0
	if "pounce" in _scenarios:
		# Leap into a soldier from 3.5 m away, the way a full pounce lands.
		n += 1
		var m := _soldier(Vector3(8, 0.2, 14))
		await _physics(20)
		var from := Vector3(8, 0.2, 17.5)
		_place(from, m.global_position)
		await _physics(2)
		_player.velocity = (m.global_position - from).normalized() * 15.0 + Vector3.UP * 4.5
		# Leave the ground first, as a real launch does, so the pounce isn't ended by the floor.
		_player.state = Volatile.State.AIR
		await physics_frame
		_player.state = Volatile.State.POUNCE
		await _sequence("%02d_pounce" % n, m, m.global_position - from)
		m.free()
		await _physics(10)

	if "claw" in _scenarios:
		# Finishing claw on a wounded soldier.
		n += 1
		var m := _soldier(Vector3(8, 0.2, 2))
		await _physics(20)
		m.health = 20.0
		var from := Vector3(9.0, 0.2, 3.4)
		_place(from, m.global_position)
		await _physics(2)
		_player._claw()
		await _sequence("%02d_claw" % n, m, m.global_position - from)
		m.free()
		await _physics(10)

	if "tendril" in _scenarios:
		# Yank a soldier across the lane; it lands in front of the volatile.
		n += 1
		var m := _soldier(Vector3(8, 0.2, -12), "militia_heavy")
		await _physics(20)
		var from := Vector3(8, 0.2, -2)
		_place(from, m.global_position, -0.05)
		await _physics(10)
		print("tendril grabbed: ", _player.use_tendril())
		await _sequence("%02d_tendril" % n, m, m.global_position - from, 120)
		await _physics(10)

	if "feed" in _scenarios:
		# Feed on a pounced soldier once it has settled: the pool spreads out from under it.
		n += 1
		var m := _soldier(Vector3(8, 0.2, 8))
		await _physics(20)
		_place(Vector3(8, 0.2, 10.5), m.global_position)
		m.take_pounce(_player)
		await _physics(150)
		var body := m.global_position
		_place(body + Vector3(0.9, 0, 0.9), body)
		await _physics(4)
		_frame(body, Vector3(1, 0, 1))
		Input.action_press("feed")
		await _physics(2)
		Input.action_release("feed")
		await _physics(60)
		await _snap("%02d_feed_during" % n)
		for i in 200:
			if m.state == Militia.State.DEAD:
				break
			await physics_frame
		await _physics(30)
		await _snap("%02d_feed_after_0.5s" % n)
		await _physics(120)
		await _snap("%02d_feed_after_2.5s" % n)

	if "volatile" in _scenarios:
		# The volatile itself shot dead mid-run.
		n += 1
		var from := Vector3(8, 0.2, 26)
		_place(from, Vector3(8, 0.2, 18))
		_player.velocity = Vector3(0, 0, -6)
		await _physics(1)
		_player.take_damage(1000.0)
		_frame(_player.global_position + Vector3(0, 0, -1), Vector3(0, 0, -1))
		var elapsed := 0.0
		for t in _times:
			await _physics(maxi(roundi((t - elapsed) * 60.0), 0))
			elapsed = t
			await _snap("%02d_volatile_%ss" % [n, String.num(t, 2)])
	quit()
