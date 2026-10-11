extends SceneTree
## Renders reference screenshots (needs a GPU or software Vulkan, not --headless):
##   godot -s res://tests/screenshots.gd -- <output_dir>

var _out := "user://screens"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _snap(name: String, frames := 30) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)

func _run() -> void:
	var gate: Node = load("res://scenes/ui/age_gate.tscn").instantiate()
	# Show the gate even if this machine already confirmed.
	root.get_node("Settings").age_confirmed = false
	root.add_child(gate)
	await _snap("01_age_gate", 5)
	gate.queue_free()
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _snap("02_main_menu", 5)
	menu.queue_free()

	var level: Node = load("res://scenes/world/haft_hoz.tscn").instantiate()
	root.add_child(level)
	var player: Volatile = get_first_node_in_group(&"player")
	await _snap("03_haft_hoz_start", 25)

	# Rooftop view down the boulevard of seven pools toward the station.
	player.set_physics_process(false)
	player.global_position = Vector3(26, 30, 40)
	player._yaw.global_position = player.global_position + Vector3.UP * 1.6
	player._yaw.look_at(Vector3(0, 0, -60))
	player._pitch.rotation.x = -0.35
	await _snap("04_rooftop_boulevard", 20)

	# Street level facing the captured station and its checkpoint.
	player.global_position = Vector3(6, 0.2, -60)
	player._yaw.global_position = player.global_position + Vector3.UP * 1.6
	player._yaw.look_at(Vector3(0, 5, -110))
	player._pitch.rotation.x = 0.0
	await _snap("05_station_checkpoint", 20)

	# Face-on look at the volatile next to a parked Paykan.
	player.global_position = Vector3(11.5, 0.2, 30)
	player._yaw.global_position = player.global_position + Vector3.UP * 1.6
	player._yaw.rotation = Vector3(0, PI, 0)
	player._pitch.rotation.x = -0.12
	await _snap("06_volatile_closeup", 20)

	# Over the volatile's shoulder at the checkpoint guards.
	player.global_position = Vector3(3, 0.2, -78)
	player._yaw.global_position = player.global_position + Vector3.UP * 1.6
	player._yaw.look_at(Vector3(0, 1.4, -92))
	player._pitch.rotation.x = -0.05
	await _snap("07_checkpoint_guards", 20)
	quit()
