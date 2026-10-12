extends SceneTree
## Headless integration test for death ragdolls (scripts/world/ragdoll.gd):
##   godot --headless -s res://tests/integration/ragdoll/militia_ragdoll_test.gd
## A downed soldier becomes a physics ragdoll that falls the way it was hit, settles
## on the street without sinking or flying apart, freezes (no physics bodies left),
## keeps its node on the body for feeding, and never blocks the volatile.
## Runs on the east lane of the Haft Hoz boulevard with the level's own militia removed.

const PLAYER_POS := Vector3(8, 0.2, 30)
## The street surface on this lane (m).
const FLOOR_Y := 0.0
## Allowed sink below the street for any bone (m): skin and capsule radius slack.
const SINK_TOLERANCE := 0.06
## A limb further than this from the pelvis has been torn off its joints (m).
const MAX_LIMB_REACH := 1.3
## Ragdoll.MAX_TIME plus a margin (s).
const SETTLE_LIMIT := 4.5

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

func _soldier(pos: Vector3) -> Militia:
	var m := Militia.new()
	m.sight_range = 0.0
	m.hit_chance = 0.0
	_level.add_child(m)
	m.global_position = pos
	return m

func _ragdoll_of(m: Node) -> Node:
	return m.get_node_or_null(^"Ragdoll")

## Waits until `m`'s ragdoll has frozen; returns the seconds it took (or -1).
func _await_settled(m: Node) -> float:
	var rd := _ragdoll_of(m)
	if rd == null:
		return -1.0
	for i in roundi(SETTLE_LIMIT * 60.0):
		if rd.is_settled():
			return i / 60.0
		await physics_frame
	return -1.0

## World positions of every bone of the frozen skeleton.
func _bone_points(m: Node) -> PackedVector3Array:
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var pts := PackedVector3Array()
	for i in sk.get_bone_count():
		pts.append((sk.global_transform * sk.get_bone_global_pose(i)).origin)
	return pts

func _run() -> void:
	_level = load("res://scenes/world/haft_hoz.tscn").instantiate()
	root.add_child(_level)
	for m in get_nodes_in_group(&"militia"):
		m.free()
	_player = get_first_node_in_group(&"player")
	await _frames(30)
	_player.global_position = PLAYER_POS
	await _frames(10)

	await _test_claw_kill_ragdoll_settles_on_street()
	await _test_pounce_throws_body_along_the_leap()
	await _test_ragdolled_body_can_be_fed_on()
	await _test_volatile_death_ragdolls()

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)

func _test_claw_kill_ragdoll_settles_on_street() -> void:
	# Arrange: a wounded soldier 1.5 m north of the volatile.
	var m := _soldier(PLAYER_POS + Vector3(0, 0, -1.5))
	await _frames(20)
	var start := m.global_position
	m.health = 10.0
	# Act
	m.take_damage(45.0, _player)
	await _frames(1)
	# Assert
	var rd := _ragdoll_of(m)
	_check(rd != null and m.is_downed(), "claw kill turns the soldier into a ragdoll")
	var shape := m.get_children().filter(func(c: Node) -> bool: return c is CollisionShape3D)
	_check(not shape.is_empty() and shape[0].disabled, "downed soldier's standing capsule stops blocking")
	var t := await _await_settled(m)
	_check(t >= 0.0, "body comes to rest and freezes (%.2f s)" % t)
	_check(m.find_children("*", "PhysicalBone3D", true, false).is_empty() if t >= 0.0 else false,
		"frozen body has no physics bodies left")
	var pts := _bone_points(m)
	var lowest := INF
	var hips: Vector3 = pts[0]
	var reach := 0.0
	for p in pts:
		lowest = minf(lowest, p.y)
		reach = maxf(reach, p.distance_to(hips))
	_check(lowest > FLOOR_Y - SINK_TOLERANCE, "no bone sinks through the street (lowest %.3f m)" % lowest)
	_check(reach < MAX_LIMB_REACH, "limbs stay on their joints (furthest %.2f m from the pelvis)" % reach)
	_check(hips.y < 0.45, "body lies on the ground (pelvis %.2f m up)" % hips.y)
	var away := m.global_position - start
	_check(away.z < -0.1, "claw throws the body away from the volatile (%.2f m)" % -away.z)
	var flat := Vector2(m.global_position.x - hips.x, m.global_position.z - hips.z).length()
	_check(flat < 0.05, "soldier node rests on the body's pelvis (%.3f m off)" % flat)
	_check(m.global_position.y > FLOOR_Y - 0.05 and m.global_position.y < FLOOR_Y + 0.2,
		"soldier node sits on the street (y %.2f)" % m.global_position.y)
	m.free()

func _test_pounce_throws_body_along_the_leap() -> void:
	# Arrange: the volatile leaps east into a soldier.
	var m := _soldier(PLAYER_POS + Vector3(3, 0, 0))
	await _frames(20)
	var start := m.global_position
	_player.velocity = Vector3(14, 3, 0)
	# Act
	m.take_pounce(_player)
	await _await_settled(m)
	# Assert
	_check(m.global_position.x - start.x > 0.3, "pounce knocks the body along the leap (%.2f m)" % (m.global_position.x - start.x))
	_player.velocity = Vector3.ZERO
	m.free()

func _test_ragdolled_body_can_be_fed_on() -> void:
	# Arrange: a soldier pounced, then the volatile walks over the body.
	var m := _soldier(PLAYER_POS + Vector3(0, 0, -2))
	await _frames(20)
	m.take_pounce(_player)
	await _frames(20)
	# Act: the body is still falling; the volatile steps up beside the pelvis, and
	# feeding must find the body there by the soldier node's position.
	var hips: Vector3 = _ragdoll_of(m).hips_position()
	_player.global_position = Vector3(hips.x + 1.0, PLAYER_POS.y, hips.z)
	var found: bool = _player._enemies_in_range(2.2, true).has(m)
	m.begin_feed(_player)
	await _await_settled(m)
	m.finish_feed()
	await _frames(5)
	# Assert
	_check(found, "falling body is in feeding range of a volatile beside its pelvis")
	_check(m.state == Militia.State.DEAD and is_instance_valid(m) and m.is_inside_tree(), "fed-on body is consumed and stays in the world")
	# The volatile walks straight through the corpse instead of being stopped by it.
	_player.global_position = m.global_position + Vector3(0, 0.2, 1.5)
	_player.velocity = Vector3.ZERO
	await _frames(10)
	var motion := Vector3(0, 0, -3.0)
	var blocked := _player.test_move(_player.global_transform.translated(Vector3.UP * 0.05), motion)
	_check(not blocked, "corpse never blocks the volatile walking over it")
	m.free()

func _test_volatile_death_ragdolls() -> void:
	# Arrange: no death screen or level reload, just the body.
	for c: Dictionary in _player.died.get_connections():
		_player.died.disconnect(c.callable)
	_player.global_position = PLAYER_POS
	_player.velocity = Vector3.ZERO
	await _frames(10)
	# Act
	_player.take_damage(1000.0)
	await _frames(1)
	var rd := _ragdoll_of(_player)
	# Assert
	_check(rd != null, "the volatile's own death is a ragdoll")
	var t := await _await_settled(_player)
	_check(t >= 0.0, "the volatile's body settles (%.2f s)" % t)
