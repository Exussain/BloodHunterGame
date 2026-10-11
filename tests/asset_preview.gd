extends SceneTree
## Renders a studio preview of every generated model (needs a GPU or software Vulkan):
##   godot -s res://tests/asset_preview.gd -- <output_dir>

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://previews"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.33, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	root.add_child(key)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()

	for kind in ["props", "characters"]:
		var dir := DirAccess.open("res://assets/" + kind)
		if dir == null:
			continue
		for id in dir.get_directories():
			var path := "res://assets/%s/%s/model.glb" % [kind, id]
			if not ResourceLoader.exists(path):
				continue
			var node: Node3D = load(path).instantiate()
			root.add_child(node)
			var aabb := GeneratedAssets._bounds(node, Transform3D.IDENTITY)
			var c := aabb.get_center()
			var r := aabb.size.length() * 0.5
			if kind == "characters":
				# Skinned meshes report bind-pose bounds; frame a ~1.8 m person instead.
				c = Vector3(0, 0.9, 0)
				r = 1.0
			# glTF faces +Z, so look from +Z and a little to the side.
			cam.position = c + Vector3(0.5, 0.25, 1.0).normalized() * r * 1.7
			cam.look_at(c)
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [kind, id]))
			print("preview ", kind, "/", id, " size=", aabb.size)
			node.queue_free()
			await process_frame
	quit()
