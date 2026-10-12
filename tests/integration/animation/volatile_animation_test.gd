extends SceneTree
## Headless integration test for the volatile's animation and facing:
##   godot --headless -s res://tests/integration/animation/volatile_animation_test.gd
## Regression checks for the motion-polish pass (production/qa/evidence/polish-animation/):
## feet planted while sprinting, the climb clip playing, the pounce showing the leap,
## claw combo hits, no facing snaps, and the rage form keeping its size while turning.
## Runs on the east lane of the Haft Hoz boulevard with the level's militia removed.

const PLAYER_POS := Vector3(8, 0.3, 30)
## Planted-foot speed (m/s) above which the feet visibly skate.
const MAX_SLIDE := 1.5
## Largest acceptable model turn in one 60 Hz physics frame (deg).
const MAX_TURN_STEP := 15.0
## Where the leap starts inside Run_and_Leap (s); the clip's first 1.6 s is a run-up.
const LEAP_START := 1.6

var _failures := 0
var _level: Node
var _player: Volatile
var _skel: Skeleton3D
## Feet relative to the body and the clip time, captured each time the skeleton is drawn.
var _feet: Array = []
var _feet_clip_time := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failures += 1

func _release() -> void:
	for a in ["move_forward", "move_back", "sprint", "pounce", "attack"]:
		Input.action_release(a)

func _reset_player(yaw := 0.0) -> void:
	_release()
	_player.global_position = PLAYER_POS
	_player.velocity = Vector3.ZERO
	_player.state = Volatile.State.AIR
	_player._yaw.global_position = PLAYER_POS + Vector3.UP * 1.6
	_player._yaw.rotation = Vector3(0, yaw, 0)
	_player._pitch.rotation.x = 0.0

## Foot positions as drawn (after skeleton modifiers), captured on skeleton_updated.
func _capture_feet() -> void:
	_feet = []
	for b: String in ["LeftFoot", "RightFoot"]:
		var world := _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(b)).origin
		_feet.append(world - _player.global_position)
	_feet_clip_time = _player._anim.current_animation_position

func _run() -> void:
	_level = load("res://scenes/world/haft_hoz.tscn").instantiate()
	root.add_child(_level)
	for m in get_nodes_in_group(&"militia"):
		m.free()
	_player = get_first_node_in_group(&"player")
	_skel = _player._model.find_children("*", "Skeleton3D", true, false)[0]
	_skel.skeleton_updated.connect(_capture_feet)
	await _frames(30)

	await _test_sprint_keeps_feet_planted()
	await _test_climb_clip_advances_while_climbing()
	await _test_pounce_launch_shows_the_leap()
	await _test_second_claw_plays_next_combo_hit()
	await _test_turnaround_has_no_facing_snap()
	await _test_rage_form_keeps_scale_while_turning()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)

func _test_sprint_keeps_feet_planted() -> void:
	# Arrange
	_reset_player()
	await _frames(20)
	# Act: sprint for a second; every 0.25 s window holds at least one planted step, so its
	# slowest lower-foot speed is the skate speed.
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _frames(20)
	# The foot's world speed is the body's velocity plus the foot's motion relative to the
	# body; the latter is timed by the clip clock, so the check holds at any frame rate.
	var minima: Array[float] = []
	var window: Array[float] = []
	var window_time := 0.0
	var prev: Array = []
	var prev_t := 0.0
	for i in 1200:
		await process_frame
		var dt := (_feet_clip_time - prev_t) / maxf(_player._anim.get_playing_speed(), 0.01)
		if prev.size() == 2 and _feet.size() == 2 and dt > 0.0005:
			var low := 0 if _feet[0].y < _feet[1].y else 1
			var v: Vector3 = _player.velocity + (_feet[low] - prev[low]) / dt
			window.append(Vector2(v.x, v.z).length())
			window_time += dt
		if dt != 0.0:
			prev = _feet.duplicate()
			prev_t = _feet_clip_time
		if window_time >= 0.25:
			minima.append(window.min())
			window.clear()
			window_time = 0.0
		if minima.size() >= 8:
			break
	_release()
	var mean := 0.0
	for m in minima:
		mean += m / minima.size()
	# Assert
	_check(not minima.is_empty() and mean < MAX_SLIDE, "sprinting feet stay planted (skate %.2f m/s)" % mean)

## Finds a z where the east apartment wall (x = 20) stands, as in test_gameplay.gd.
func _find_block_wall_z() -> float:
	var space := _player.get_world_3d().direct_space_state
	for z in range(-80, 70):
		var q := PhysicsRayQueryParameters3D.create(Vector3(16, 1.2, z), Vector3(30, 1.2, z))
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf(hit.position.x - 20.0) < 0.05:
			return z + 1.0
	return 0.0

func _test_climb_clip_advances_while_climbing() -> void:
	# Arrange: at the foot of the apartment wall, facing it.
	_reset_player(-PI / 2)
	_player.global_position = Vector3(19.3, 0.3, _find_block_wall_z())
	await _frames(10)
	# Act
	Input.action_press("move_forward")
	await _frames(15)
	var t0 := _player._anim.current_animation_position
	await _frames(15)
	var t1 := _player._anim.current_animation_position
	var clip := String(_player._anim.current_animation)
	_release()
	await _frames(90)
	# Assert
	_check(clip.ends_with("climb") and not is_equal_approx(t0, t1),
		"climb clip plays while climbing (%s %.2f -> %.2f)" % [clip, t0, t1])

func _test_pounce_launch_shows_the_leap() -> void:
	# Arrange
	_reset_player()
	await _frames(20)
	# Act
	Input.action_press("pounce")
	await _frames(20)
	Input.action_release("pounce")
	await _frames(3)
	var clip := String(_player._anim.current_animation)
	var t := _player._anim.current_animation_position
	await _frames(120)
	# Assert
	_check(clip.contains("pounce") and t >= LEAP_START, "pounce launch plays the leap, not the run-up (%s at %.2f s)" % [clip, t])

func _test_second_claw_plays_next_combo_hit() -> void:
	# Arrange
	_reset_player()
	await _frames(30)
	# Act: two claws 0.5 s apart (just past the claw cooldown).
	_player._claw()
	await _frames(3)
	var first := _player._anim.current_animation_position
	await _frames(27)
	_player._claw()
	await _frames(3)
	var clip := String(_player._anim.current_animation)
	var second := _player._anim.current_animation_position
	await _frames(60)
	# Assert: the second swing is the combo's second hit (about 1.05 s into the clip),
	# not the first hit again from the top.
	_check(clip.contains("claw") and second > 1.0,
		"second claw plays the combo's next hit (%.2f s then %s at %.2f s)" % [first, clip, second])

func _test_turnaround_has_no_facing_snap() -> void:
	# Arrange: running north.
	_reset_player()
	await _frames(20)
	Input.action_press("move_forward")
	await _frames(30)
	Input.action_release("move_forward")
	# Act: reverse.
	Input.action_press("move_back")
	var worst := 0.0
	var prev := _player._model.global_rotation.y
	for i in 30:
		await physics_frame
		var yaw := _player._model.global_rotation.y
		worst = maxf(worst, absf(rad_to_deg(wrapf(yaw - prev, -PI, PI))))
		prev = yaw
	_release()
	await _frames(20)
	# Assert
	_check(worst <= MAX_TURN_STEP, "180 turn has no facing snap (worst %.1f deg/frame)" % worst)

func _test_rage_form_keeps_scale_while_turning() -> void:
	# Arrange
	_reset_player()
	await _frames(20)
	_player.add_mutation(Volatile.MAX_MUTATION)
	_player.mutation = Volatile.MAX_MUTATION
	# Act: rage, then turn around while it grows.
	_player.use_rage()
	Input.action_press("move_back")
	await _frames(40)
	_release()
	await _frames(5)
	var s := _player._model.scale.y
	# Assert
	_check(s > 1.15, "rage form keeps its size while turning (scale %.2f)" % s)
