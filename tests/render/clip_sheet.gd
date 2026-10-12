extends SceneTree
## Renders a contact sheet of the volatile's animation clips: one image per clip, a row
## of model copies each frozen at a different time, seen side-on in a bare scene. Cheap
## to render (no level), so it is the fast way to check where a clip's key poses fall.
##   godot -s res://tests/render/clip_sheet.gd -- <output_dir> <clip>[:start:end] ...
## Needs a GPU or software Vulkan.

const COPIES := 8

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "user://clip_sheet"
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.34, 0.38)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.4
	root.add_child(cam)
	for spec: String in args.slice(1):
		var parts := spec.split(":")
		var clip := parts[0]
		var holder := Node3D.new()
		root.add_child(holder)
		var length := 0.0
		for i in COPIES:
			var m := GeneratedAssets.character("volatile")
			holder.add_child(m)
			var p := GeneratedAssets.find_animation_player(m)
			var a := p.get_animation("game/" + clip)
			length = a.length
			var t0 := float(parts[1]) if parts.size() > 1 else 0.0
			var t1 := float(parts[2]) if parts.size() > 2 else length
			var t := lerpf(t0, t1, float(i) / (COPIES - 1))
			# Side-on: the model faces -Z, so put copies along Z and look from +X.
			m.position = Vector3(0, 0, -(i - (COPIES - 1) * 0.5) * 1.15)
			p.play("game/" + clip)
			p.seek(t, true)
			p.pause()
			var label := Label3D.new()
			label.text = "%.2f" % t
			label.font_size = 48
			label.pixel_size = 0.004
			label.position = m.position + Vector3(0, -0.15, 0)
			label.rotation.y = PI / 2
			holder.add_child(label)
		cam.position = Vector3(8, 1.0, 0)
		cam.rotation = Vector3(0, PI / 2, 0)
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.size = COPIES * 1.15 + 0.4
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(spec.replace(":", "_") + ".png"))
		print("saved ", clip, " len ", length)
		holder.free()
	quit()
