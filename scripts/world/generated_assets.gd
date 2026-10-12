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

const LOOPING := [&"idle", &"run", &"stalk", &"climb", &"wall_run", &"patrol", &"combat"]
## Clips whose travel the game already moves the body for; their hip drift is removed
## so the mesh doesn't run ahead of the collider and snap back each loop.
const IN_PLACE := [&"run", &"stalk", &"climb", &"wall_run", &"pounce", &"claw", &"patrol", &"combat"]
## One-shots that restart while already playing (combo hits, back-to-back leaps). Each
## also gets a "<name>_b" copy so play_at() can cross-fade from one take to the next.
const ALIASED := [&"claw", &"pounce", &"scream"]
const ALIAS_SUFFIX := "_b"

## Loads the Meshy action clips from animations.glb into the model's AnimationPlayer
## under the game's names (idle, run, claw, ...), as mapped in animations.json.
static func _add_clips(model: Node3D, id: String) -> void:
	var player := find_animation_player(model)
	var map_path := CHAR_DIR % id + "animations.json"
	var anim_path := CHAR_DIR % id + "animations.glb"
	if player == null or not FileAccess.file_exists(map_path) or not ResourceLoader.exists(anim_path):
		return
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	var lib := AnimationLibrary.new()
	var src: Node = load(anim_path).instantiate()
	var src_player := find_animation_player(src)
	if src_player:
		for game_name: String in mapping:
			var clip := _match_clip(src_player, mapping[game_name])
			if clip == &"":
				push_warning("%s: no clip for %s (%s)" % [id, game_name, mapping[game_name]])
				continue
			var anim: Animation = src_player.get_animation(clip).duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR if StringName(game_name) in LOOPING else Animation.LOOP_NONE
			if StringName(game_name) in IN_PLACE:
				_remove_root_drift(anim)
			lib.add_animation(game_name, anim)
	src.free()
	if player.has_animation_library(&"game"):
		player.remove_animation_library(&"game")
	player.add_animation_library(&"game", lib)

static func _remove_root_drift(anim: Animation) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D or not String(anim.track_get_path(t)).ends_with(":Hips"):
			continue
		var count := anim.track_get_key_count(t)
		if count < 2:
			return
		var start: Vector3 = anim.track_get_key_value(t, 0)
		var drift: Vector3 = anim.track_get_key_value(t, count - 1) - start
		var length := maxf(anim.track_get_key_time(t, count - 1), 0.001)
		for k in count:
			# Subtract the straight-line travel, keeping the bob and sway around it.
			var v: Vector3 = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, v - drift * (anim.track_get_key_time(t, k) / length))
		return

## Meshy renames clips on export ("Run Fast" -> "RunFast", "..._inplace"), so match loosely.
static func _match_clip(player: AnimationPlayer, library_name: String) -> StringName:
	var want := _norm(library_name)
	for clip in player.get_animation_list():
		var have := _norm(clip)
		if have.contains(want) or (have != "" and want.contains(have)):
			return clip
	return &""

static func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out

static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := find_animation_player(child)
		if found:
			return found
	return null

## Plays one of the game-named clips ("idle", "run", ...) if the character has it.
## Returns false when it doesn't, so callers can fall back. Calling it again for the
## clip that is already playing only changes its speed, so it can be called every frame.
## The speed lives in the player's speed_scale (never the per-play custom speed, which
## would multiply with it and freeze a clip started at speed 0), and the cross-fade is
## scaled so it lasts `blend` real seconds at that speed. Callers that change the rate
## while a cross-fade runs should pass blend 0 and fade the pose themselves (see
## Volatile.PoseFader), since AnimationPlayer advances its fades by speed_scale.
static func play(player: AnimationPlayer, clip: StringName, blend := 0.2, speed := 1.0) -> bool:
	if player == null:
		return false
	var full := StringName("game/" + clip)
	if not player.has_animation(full):
		return false
	player.speed_scale = speed
	if player.current_animation != full or not player.is_playing():
		player.play(full, _scaled_blend(blend, speed), 1.0)
	return true

## Like play(), but always (re)starts the clip `from` seconds in, cross-fading from
## whatever was showing. Used for one-shots and for clips whose useful part starts late
## (the leap inside Run_and_Leap, the second hit of a combo).
static func play_at(player: AnimationPlayer, clip: StringName, from: float, blend := 0.1, speed := 1.0) -> bool:
	if player == null:
		return false
	var full := StringName("game/" + clip)
	if not player.has_animation(full):
		return false
	player.speed_scale = speed
	if player.current_animation == full and player.is_playing():
		# Restarting the same clip can't cross-fade with itself; use its alias if there is one.
		var alt := StringName(String(full) + ALIAS_SUFFIX)
		if player.has_animation(alt):
			full = alt
	player.play(full, _scaled_blend(blend, speed), 1.0)
	player.seek(from, true)
	return true

## The name (without "game/") of the clip showing now, with any alias suffix removed;
## "" when nothing is playing.
static func current_clip(player: AnimationPlayer) -> StringName:
	if player == null or not player.is_playing():
		return &""
	return StringName(String(player.current_animation).trim_prefix("game/").trim_suffix(ALIAS_SUFFIX))

## AnimationPlayer advances cross-fades by speed_scale * delta, so a fade started at
## a high or low clip rate would finish early or late; this keeps it in real seconds
## (for a rate that holds steady during the fade).
static func _scaled_blend(blend: float, speed: float) -> float:
	return blend * maxf(absf(speed), 0.05) if blend > 0.0 else 0.0

static func has_clip(player: AnimationPlayer, clip: StringName) -> bool:
	return player != null and player.has_animation(StringName("game/" + clip))

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

const BUILDING_DIR := "res://assets/buildings/%s/"
const WINDOW_GLOW := preload("res://assets/shaders/spatial_env_window_glow.gdshader")

## A generated building whose window panes (windows.png, from generate.py) light up
## at random at night, through an additive pass over the model's own material.
static func building(id: String, lit_fraction := 0.35) -> Node3D:
	var path := BUILDING_DIR % id + "model.glb"
	if not ResourceLoader.exists(path):
		return null
	var model: Node3D = load(path).instantiate()
	var mask_path := BUILDING_DIR % id + "windows.png"
	if ResourceLoader.exists(mask_path):
		var glow := ShaderMaterial.new()
		glow.shader = WINDOW_GLOW
		glow.set_shader_parameter(&"glass_mask", load(mask_path))
		glow.set_shader_parameter(&"lit_fraction", lit_fraction)
		_add_next_pass(model, glow)
	return model

static func _add_next_pass(node: Node, pass_material: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s)
			if base == null:
				continue
			var m := base.duplicate() as Material
			m.next_pass = pass_material
			mi.set_surface_override_material(s, m)
	for child in node.get_children():
		_add_next_pass(child, pass_material)
