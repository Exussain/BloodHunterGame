extends SceneTree
## Headless gameplay smoke test:
##   godot --headless -s res://tests/test_gameplay.gd
## Checks landing, wall-climb, pounce takedown, feeding and power unlock.

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failures += 1

## Finds a z on the east side where an apartment block's wall stands at x = 20.
func _find_block_wall_z(player: Node3D) -> float:
	var space := player.get_world_3d().direct_space_state
	for z in range(-80, 70):
		var q := PhysicsRayQueryParameters3D.create(Vector3(16, 1.2, z), Vector3(30, 1.2, z))
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf(hit.position.x - 20.0) < 0.05:
			var q2 := PhysicsRayQueryParameters3D.create(Vector3(16, 1.2, z + 2), Vector3(30, 1.2, z + 2))
			q2.exclude = [player.get_rid()]
			if not space.intersect_ray(q2).is_empty():
				return z + 1.0
	return 0.0

func _run() -> void:
	var level: Node = load("res://scenes/world/haft_hoz.tscn").instantiate()
	root.add_child(level)
	await _frames(90)
	var player: Volatile = get_first_node_in_group(&"player")
	_check(player != null and player.is_on_floor(), "player lands on the street")

	# Climb the first apartment block on the east side.
	var wall_z := _find_block_wall_z(player)
	player.global_position = Vector3(19.3, 0.3, wall_z)
	player.velocity = Vector3.ZERO
	player._yaw.rotation = Vector3(0, -PI / 2, 0)  # face +X, toward the wall
	await _frames(10)
	var start_y := player.global_position.y
	Input.action_press("move_forward")
	await _frames(45)
	_check(player.global_position.y > start_y + 2.0, "wall-climb gains height (%.1f -> %.1f)" % [start_y, player.global_position.y])
	Input.action_release("move_forward")
	await _frames(120)

	# Pounce onto the stationary militia guard in front of the station.
	var target: Militia
	for m in get_nodes_in_group(&"militia"):
		if m.patrol_points.size() == 2 and m.patrol_points[0] == m.patrol_points[1]:
			target = m
	target.sight_range = 0.0  # keep it from shooting during the test
	player.global_position = target.global_position + Vector3(0, 0.2, 9)
	player.velocity = Vector3.ZERO
	player.state = Volatile.State.AIR
	await _frames(30)
	player._yaw.look_at(target.global_position + Vector3.UP * 1.6)
	player._pitch.rotation.x = -0.1
	Input.action_press("pounce")
	await _frames(20)
	Input.action_release("pounce")
	var downed := false
	for i in 120:
		await physics_frame
		if target.is_downed():
			downed = true
			break
	_check(downed, "pounce downs a militia soldier")

	# Feed on the downed soldier.
	player.global_position = target.global_position + Vector3(0, 0.2, 1.2)
	player.velocity = Vector3.ZERO
	await _frames(10)
	Input.action_press("feed")
	await _frames(2)
	Input.action_release("feed")
	await _frames(160)
	_check(target.state == Militia.State.DEAD, "feeding consumes the body")
	_check(is_equal_approx(player.mutation, 25.0), "feeding adds mutation (%.0f)" % player.mutation)
	_check(player.unlocked.has(&"tendril"), "tendril grab unlocks at 25 mutation")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)
