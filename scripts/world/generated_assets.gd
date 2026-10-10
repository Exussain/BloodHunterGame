class_name GeneratedAssets
## Looks up assets made by tools/assets/generate.py (ChatGPT image + Meshy).
## Every lookup returns null when the file isn't there yet, so the greybox
## placeholders keep working until generation has run.

const CHAR_DIR := "res://assets/characters/%s/"
const PROP_PATH := "res://assets/props/%s/model.glb"
const TEX_PATH := "res://assets/textures/%s.png"

static func character(id: String) -> Node3D:
	var path := CHAR_DIR % id + "model.glb"
	if not ResourceLoader.exists(path):
		return null
	var model: Node3D = load(path).instantiate()
	# glTF faces +Z; Godot characters face -Z.
	model.rotation.y = PI
	_add_clips(model, id)
	return model

## Copies Meshy's walking/running clips into the model's AnimationPlayer as
## "walk" and "run", so callers can just play those names.
static func _add_clips(model: Node3D, id: String) -> void:
	var player := find_animation_player(model)
	if player == null:
		return
	var lib: AnimationLibrary
	if player.has_animation_library(&""):
		lib = player.get_animation_library(&"")
	else:
		lib = AnimationLibrary.new()
		player.add_animation_library(&"", lib)
	for clip in [["walking", &"walk"], ["running", &"run"]]:
		var path: String = CHAR_DIR % id + clip[0] + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var src: Node = load(path).instantiate()
		var src_player := find_animation_player(src)
		if src_player and not src_player.get_animation_list().is_empty():
			var anim: Animation = src_player.get_animation(src_player.get_animation_list()[0]).duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(clip[1], anim)
		src.free()

static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := find_animation_player(child)
		if found:
			return found
	return null

## Plays walk/run/idle on a generated character from its horizontal speed.
static func drive_locomotion(player: AnimationPlayer, speed: float, run_speed: float) -> void:
	if player == null:
		return
	var want: StringName = &""
	if speed > run_speed * 0.7 and player.has_animation(&"run"):
		want = &"run"
	elif speed > 0.5 and player.has_animation(&"walk"):
		want = &"walk"
	if want == &"":
		if player.is_playing() and player.current_animation in [&"walk", &"run"]:
			player.pause()
		return
	if player.current_animation != want or not player.is_playing():
		player.play(want, 0.2)

static func prop(id: String) -> Node3D:
	var path := PROP_PATH % id
	if not ResourceLoader.exists(path):
		return null
	return load(path).instantiate()

## Scales and centres a prop so its bounds fill `size`, standing on the box's base.
static func fit_prop(prop: Node3D, size: Vector3) -> void:
	var aabb := _bounds(prop, Transform3D.IDENTITY)
	if aabb.size.x <= 0.0 or aabb.size.y <= 0.0 or aabb.size.z <= 0.0:
		return
	var s := minf(minf(size.x / aabb.size.x, size.y / aabb.size.y), size.z / aabb.size.z)
	prop.scale = Vector3.ONE * s
	var centre := aabb.get_center() * s
	prop.position = Vector3(-centre.x, -size.y * 0.5 - aabb.position.y * s, -centre.z)

static func _bounds(node: Node, xf: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var local := xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is VisualInstance3D:
		result = local * (node as VisualInstance3D).get_aabb()
		first = false
	for child in node.get_children():
		var child_box := _bounds(child, local)
		if child_box.size == Vector3.ZERO:
			continue
		result = child_box if first else result.merge(child_box)
		first = false
	return result

static func texture_material(id: String, roughness: float, tile_m: float) -> StandardMaterial3D:
	var path := TEX_PATH % id
	if not ResourceLoader.exists(path):
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.roughness = roughness
	# World triplanar mapping, so box geometry of any size tiles cleanly.
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
