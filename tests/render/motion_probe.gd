extends SceneTree
## Headless motion probe for the volatile: drives a fixed input script through the
## level and logs per-frame numbers that show animation and camera problems without
## rendering. Run with a fixed frame rate so frames map to time:
##   godot --headless --fixed-fps 60 -s res://tests/render/motion_probe.gd -- <out_dir>
##   godot --headless --fixed-fps 144 -s res://tests/render/motion_probe.gd -- <out_dir> [nointerp]
## Writes <out_dir>/motion_<fps>.tsv (one row per rendered frame) and prints a summary
## per segment:
##   slide   while moving on the ground, the slowest horizontal speed (m/s) of the lower
##           foot in each 0.25 s window (at least one step), averaged / worst. A planted
##           foot is still for part of every step, so ~0 means no skating; over ~1 reads
##           as skating. Read it from the 60 fps run only: it uses the physics (not
##           interpolated) body position, so at 144 fps the body steps every ~2.4 frames
##           and the number is noise.
##   pop     largest one-frame jump (m) of a head/hand/foot bone in model space, and the
##           largest change in that jump between frames (a blend pop or clip restart).
##   yaw     largest model turn in one frame (deg).
##   cam     largest frame-to-frame change in camera velocity (m/s), i.e. visible judder.

const KEY_BONES := ["Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]

var _out := "user://motion_probe"
var _player: Volatile
var _level: Node
var _skel: Skeleton3D
var _rows: PackedStringArray = []
var _segment := ""
var _seg: Dictionary = {}
var _summary: PackedStringArray = []
var _prev_bones: Dictionary = {}
var _prev_step: Dictionary = {}
var _prev_feet: Array = []
var _prev_cam := Vector3.INF
var _prev_cam_v := Vector3.INF
var _prev_yaw := INF
var _frame := 0
var _window: Array[float] = []
## Bone positions captured when the skeleton finishes its pose (after modifiers such as
## the volatile's PoseFader), i.e. what is actually drawn. Reading bones between
## updates returns the raw animation pose instead.
var _drawn_local: Dictionary = {}
var _drawn_feet: Array = []
var _window_time := 0.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	# "nointerp" compares against the game without physics interpolation.
	if args.size() > 1 and args[1] == "nointerp":
		physics_interpolation = false
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame
		_sample()

func _physics_frames(n: int) -> void:
	var start := Engine.get_physics_frames()
	while Engine.get_physics_frames() - start < n:
		await process_frame
		_sample()

func _begin(name: String) -> void:
	_end()
	print("segment ", name, " frame ", _frame, " physics ", Engine.get_physics_frames())
	_segment = name
	_seg = {"slide_sum": 0.0, "slide_n": 0, "slide_max": 0.0, "pop": 0.0, "pop_at": "", "jerk": 0.0,
		"jerk_at": "", "yaw": 0.0, "cam": 0.0, "clips": []}

func _end() -> void:
	if _segment == "":
		return
	var mean: float = _seg.slide_sum / maxf(_seg.slide_n, 1)
	_summary.append("%-18s slide %.2f/%.2f  pop %.3f (%s) jerk %.3f (%s)  yaw %.1f  cam %.2f  clips %s" % [
		_segment, mean, _seg.slide_max, _seg.pop, _seg.pop_at, _seg.jerk, _seg.jerk_at, _seg.yaw, _seg.cam,
		",".join(_seg.clips)])
	_segment = ""

func _sample() -> void:
	_frame += 1
	var dt := maxf(root.get_process_delta_time(), 0.0001)
	var anim := _player._anim
	var clip := String(anim.current_animation).trim_prefix("game/") if anim else ""
	var pos := anim.current_animation_position if anim and anim.is_playing() else 0.0
	var rate := anim.get_playing_speed() if anim and anim.is_playing() else 0.0
	if _segment != "" and not _seg.clips.has(clip):
		_seg.clips.append(clip)

	# Bones in model space: pure animation, independent of where the body is or faces.
	var max_step := 0.0
	var max_jerk := 0.0
	var worst := ""
	for b: String in KEY_BONES:
		if not _drawn_local.has(b):
			continue
		var local: Vector3 = _drawn_local[b]
		if _prev_bones.has(b):
			var step: Vector3 = local - _prev_bones[b]
			if step.length() > max_step:
				max_step = step.length()
				worst = b
			if _prev_step.has(b):
				max_jerk = maxf(max_jerk, (step - _prev_step[b]).length())
			_prev_step[b] = step
		_prev_bones[b] = local

	# Planted-foot slide: the lower foot, when it is near the ground and not lifting.
	var feet := _drawn_feet
	var slide := -1.0
	var ground_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if _prev_feet.size() == 2 and feet.size() == 2 and _player.state == Volatile.State.GROUND and _player.is_on_floor():
		var low := 0 if feet[0].y < feet[1].y else 1
		var h: float = feet[low].y - _player.global_position.y
		var v: Vector3 = (feet[low] - _prev_feet[low]) / dt
		if h < 0.34:
			slide = Vector2(v.x, v.z).length()
	_prev_feet = feet
	var step_min := -1.0
	var moving_on_ground := _player.state == Volatile.State.GROUND and ground_speed > 0.5
	if moving_on_ground:
		if slide >= 0.0:
			_window.append(slide)
		_window_time += dt
		if _window_time >= 0.25:
			if not _window.is_empty():
				step_min = _window.min()
			_window.clear()
			_window_time = 0.0
	else:
		_window.clear()
		_window_time = 0.0

	var cam := _player._camera.global_position
	var cam_jolt := 0.0
	if _prev_cam != Vector3.INF and cam.distance_to(_prev_cam) > 2.0:
		_prev_cam_v = Vector3.INF  # a teleport, not judder
	elif _prev_cam != Vector3.INF:
		var cv := (cam - _prev_cam) / dt
		if _prev_cam_v != Vector3.INF:
			cam_jolt = (cv - _prev_cam_v).length()
		_prev_cam_v = cv
	_prev_cam = cam

	var yaw := rad_to_deg(_player._model.global_rotation.y)
	var dyaw := 0.0 if _prev_yaw == INF else absf(wrapf(yaw - _prev_yaw, -180.0, 180.0))
	_prev_yaw = yaw

	if _segment != "":
		if step_min >= 0.0:
			_seg.slide_sum += step_min
			_seg.slide_n += 1
			_seg.slide_max = maxf(_seg.slide_max, step_min)
		if max_step > _seg.pop:
			_seg.pop = max_step
			_seg.pop_at = "%s@%d %s" % [worst, _frame, clip]
		if max_jerk > _seg.jerk:
			_seg.jerk = max_jerk
			_seg.jerk_at = "%d %s" % [_frame, clip]
		_seg.yaw = maxf(_seg.yaw, dyaw)
		_seg.cam = maxf(_seg.cam, cam_jolt)
	_rows.append("%d\t%s\t%s\t%s\t%.3f\t%.2f\t%.2f\t%.2f\t%.3f\t%.3f\t%.1f\t%.2f\t%.2f\t%.2f" % [
		_frame, _segment, Volatile.State.keys()[_player.state], clip, pos, rate, ground_speed, slide,
		max_step, max_jerk, dyaw, cam_jolt, _player._camera.fov, _player.global_position.y])

func _capture_pose() -> void:
	var inv := _player._model.global_transform.affine_inverse()
	for b: String in KEY_BONES:
		_drawn_local[b] = inv * (_skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(b)).origin)
	_drawn_feet = []
	for b: String in ["LeftFoot", "RightFoot"]:
		_drawn_feet.append(_skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(b)).origin)

func _place(pos: Vector3, yaw: float) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.state = Volatile.State.AIR
	_player._yaw.rotation = Vector3(0, yaw, 0)
	_player._yaw.global_position = pos + Vector3.UP * 1.6
	_player._pitch.rotation.x = -0.2
	if _player.has_method(&"snap_camera"):
		_player.snap_camera()

func _press(action: String, frames: int) -> void:
	Input.action_press(action)
	await _physics_frames(frames)
	Input.action_release(action)

func _find_block_wall_z() -> float:
	var space := _player.get_world_3d().direct_space_state
	for z in range(-80, 70):
		var q := PhysicsRayQueryParameters3D.create(Vector3(16, 1.2, z), Vector3(30, 1.2, z))
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf(hit.position.x - 20.0) < 0.05:
			var q2 := PhysicsRayQueryParameters3D.create(Vector3(16, 1.2, z + 2), Vector3(30, 1.2, z + 2))
			q2.exclude = [_player.get_rid()]
			if not space.intersect_ray(q2).is_empty():
				return z + 1.0
	return 0.0

func _run() -> void:
	_level = load("res://scenes/world/haft_hoz.tscn").instantiate()
	root.add_child(_level)
	for m in get_nodes_in_group(&"militia"):
		m.free()
	_player = get_first_node_in_group(&"player")
	_skel = _player._model.find_children("*", "Skeleton3D", true, false)[0]
	_skel.skeleton_updated.connect(_capture_pose)
	await _physics_frames(30)
	_place(Vector3(8, 0.3, 30), 0.0)
	await _physics_frames(30)

	_begin("walk_hold")
	await _press("move_forward", 100)
	await _physics_frames(30)
	_place(Vector3(8, 0.3, 30), 0.0)
	await _physics_frames(20)
	_begin("idle")
	await _physics_frames(40)
	_begin("walk_start_stop")
	await _press("move_forward", 60)
	await _physics_frames(40)
	_begin("sprint")
	Input.action_press("sprint")
	await _press("move_forward", 75)
	Input.action_release("sprint")
	await _physics_frames(40)
	_place(Vector3(8, 0.3, 30), 0.0)
	await _physics_frames(20)
	_begin("turn_180")
	Input.action_press("move_forward")
	await _physics_frames(30)
	Input.action_release("move_forward")
	await _press("move_back", 40)
	await _physics_frames(30)
	_begin("claw_combo_still")
	for i in 3:
		await _press("attack", 2)
		await _physics_frames(16)
	await _physics_frames(50)
	_place(Vector3(8, 0.3, 30), 0.0)
	await _physics_frames(20)
	_begin("claw_running")
	Input.action_press("move_forward")
	await _physics_frames(20)
	await _press("attack", 2)
	await _physics_frames(40)
	Input.action_release("move_forward")
	await _physics_frames(30)
	_place(Vector3(8, 0.3, 30), 0.0)
	await _physics_frames(20)
	_begin("jump_run")
	Input.action_press("move_forward")
	await _physics_frames(20)
	await _press("jump", 2)
	await _physics_frames(60)
	Input.action_release("move_forward")
	await _physics_frames(30)
	_place(Vector3(8, 0.3, 30), 0.0)
	await _physics_frames(20)
	_begin("pounce")
	_player._pitch.rotation.x = 0.1
	await _press("pounce", 30)
	await _physics_frames(110)

	_begin("climb")
	var wall_z := _find_block_wall_z()
	_place(Vector3(18.6, 0.3, wall_z), -PI / 2)
	await _physics_frames(20)
	await _press("move_forward", 50)
	await _physics_frames(30)
	await _press("move_forward", 30)
	await _physics_frames(90)

	_begin("wall_run")
	var run_z := _find_block_wall_z()
	_place(Vector3(19.45, 0.3, run_z - 4.0), PI)
	await _physics_frames(10)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _physics_frames(20)
	await _press("jump", 2)
	await _physics_frames(110)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _physics_frames(40)

	_begin("feed")
	_place(Vector3(8, 0.3, 30), 0.0)
	var m := Militia.new()
	m.sight_range = 0.0
	m.hit_chance = 0.0
	_level.add_child(m)
	m.global_position = Vector3(8, 0.3, 28.6)
	await _physics_frames(20)
	m.take_pounce(_player)
	await _physics_frames(60)
	# The body may have been thrown; walk up to wherever it settled.
	_player.global_position = m.global_position + Vector3(0, 0.3, 1.2)
	_player.velocity = Vector3.ZERO
	await _physics_frames(20)
	await _press("feed", 2)
	await _physics_frames(170)
	if is_instance_valid(m):
		m.free()

	_begin("scream_rage")
	_player.add_mutation(100.0)
	await _physics_frames(10)
	_player.use_scream()
	await _physics_frames(80)
	_player.mutation = Volatile.MAX_MUTATION
	_player.use_rage()
	await _physics_frames(30)
	Input.action_press("sprint")
	await _press("move_forward", 60)
	Input.action_release("sprint")
	await _physics_frames(40)
	_end()

	var fps := roundi(1.0 / maxf(root.get_process_delta_time(), 0.0001))
	var f := FileAccess.open(_out.path_join("motion_%d.tsv" % fps), FileAccess.WRITE)
	f.store_line("frame\tsegment\tstate\tclip\tpos\trate\tspeed\tslide\tbone_step\tbone_jerk\tyaw_step\tcam_jolt\tfov\ty")
	for r in _rows:
		f.store_line(r)
	for s in _summary:
		print(s)
	quit()
