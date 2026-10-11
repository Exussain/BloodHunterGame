extends SceneTree
## Headless integration test for the volatile's powers (tendril grab, scream, rage form):
##   godot --headless -s res://tests/integration/powers/volatile_powers_test.gd
## Spec: design/quick-specs/volatile-powers-2026-10-11.md (Acceptance Criteria).
## Runs on the east lane of the Haft Hoz boulevard with the level's own militia removed,
## so every soldier here is placed by the test.

## The volatile stands here, facing north (-Z) up the open lane.
const PLAYER_POS := Vector3(8, 0.2, 30)

var _failures := 0
var _level: Node
var _player: Volatile

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failures += 1

## A standing soldier that never shoots, at `offset` from the volatile.
func _soldier(offset: Vector3) -> Militia:
	var m := Militia.new()
	m.sight_range = 0.0
	m.hit_chance = 0.0
	_level.add_child(m)
	m.global_position = PLAYER_POS + offset
	return m

func _reset_player() -> void:
	_player.global_position = PLAYER_POS
	_player.velocity = Vector3.ZERO
	_player.state = Volatile.State.GROUND
	_player._yaw.global_position = PLAYER_POS + Vector3.UP * 1.6
	_player._yaw.rotation = Vector3.ZERO
	_player._pitch.rotation.x = 0.0

func _run() -> void:
	_level = load("res://scenes/world/haft_hoz.tscn").instantiate()
	root.add_child(_level)
	for m in get_nodes_in_group(&"militia"):
		m.free()
	_player = get_first_node_in_group(&"player")
	await _frames(30)
	_reset_player()
	await _frames(10)

	await _test_tendril_needs_unlock_returns_null()
	await _test_tendril_pulls_soldier_down_at_feet()
	await _test_scream_stuns_cone_and_alerts_earshot()
	await _test_rage_spends_meter_and_shields()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)

func _test_tendril_needs_unlock_returns_null() -> void:
	# Arrange
	var target := _soldier(Vector3(0, 0, -12))
	await _frames(5)
	# Act
	var grabbed := _player.use_tendril()
	# Assert
	_check(grabbed == null, "tendril does nothing before it is unlocked")
	target.free()

func _test_tendril_pulls_soldier_down_at_feet() -> void:
	# Arrange
	_player.add_mutation(25.0)
	var target := _soldier(Vector3(0, 0, -12))
	var bystander := _soldier(Vector3(-16, 0, -20))
	_reset_player()
	await _frames(5)
	# Act
	var grabbed := _player.use_tendril()
	await _frames(90)
	# Assert
	_check(grabbed == target, "tendril picks the soldier on the crosshair")
	_check(target.is_downed(), "grabbed soldier lands downed")
	var dist := target.global_position.distance_to(_player.global_position)
	_check(dist < 3.0, "grabbed soldier lands at the volatile's feet (%.1f m)" % dist)
	_check(bystander.state == Militia.State.PATROL, "tendril grab is silent (bystander still patrolling)")
	_check(not _player.power_ready(&"tendril"), "tendril goes on cooldown")
	target.free()
	bystander.free()

func _test_scream_stuns_cone_and_alerts_earshot() -> void:
	# Arrange
	_player.add_mutation(25.0)
	var front_a := _soldier(Vector3(-1.5, 0, -7))
	var front_b := _soldier(Vector3(1.5, 0, -9))
	var behind := _soldier(Vector3(0, 0, 20))
	var far := _soldier(Vector3(0, 0, -60))
	_reset_player()
	await _frames(5)
	var start_dist := front_a.global_position.distance_to(_player.global_position)
	# Act
	var stunned := _player.use_scream()
	await _frames(5)
	# Assert
	_check(stunned == 2, "scream stuns both soldiers in the cone (%d)" % stunned)
	_check(front_a.state == Militia.State.STUNNED, "soldier in the cone is stunned")
	_check(behind.state == Militia.State.ALERT, "soldier behind within earshot turns hostile")
	_check(far.state == Militia.State.PATROL, "soldier beyond earshot keeps patrolling")
	await _frames(int((float(_player._powers.scream.stun_time) + 1.0) * 60.0))
	_check(front_a.state == Militia.State.PANIC, "stunned soldier panics after the stun")
	var fled := front_a.global_position.distance_to(_player.global_position) - start_dist
	_check(fled > 2.0, "panicking soldier runs away (%.1f m further)" % fled)
	for m in [front_a, front_b, behind, far]:
		m.free()

func _test_rage_spends_meter_and_shields() -> void:
	# Arrange
	_player.add_mutation(50.0)
	_player._powers.rage.duration = 1.5
	var watcher := _soldier(Vector3(0, 0, -10))
	_reset_player()
	await _frames(5)
	_player.health = Volatile.MAX_HEALTH
	# Act
	var started := _player.use_rage()
	await _frames(30)
	_player.take_damage(20.0)
	# Assert
	_check(started and _player.is_raging(), "rage form starts on a full meter")
	_check(is_zero_approx(_player.mutation), "rage spends the whole meter (%.0f left)" % _player.mutation)
	var expected := Volatile.MAX_HEALTH - 20.0 * float(_player._powers.rage.damage_taken_mult)
	_check(is_equal_approx(_player.health, expected), "rage cuts damage taken (%.1f hp)" % _player.health)
	_check(watcher.is_panicking(), "a soldier who sees the rage form panics")
	_check(not _player.use_rage(), "rage can't start again while running")
	await _frames(90)
	_check(not _player.is_raging(), "rage form ends after its duration")
	_check(_player.unlocked.has(&"tendril") and _player.unlocked.has(&"rage"), "unlocks survive spending the meter")
	watcher.free()
