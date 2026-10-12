extends Node3D
## Greybox of Haft Hoz (Narmak) at night: the boulevard with its seven pools,
## apartment blocks you can climb, and the militia-held کلانتری at the north end.
## Primitive geometry stands in until real Tehran street kits are dressed in.

const PERSIAN_FONT := preload("res://assets/fonts/Vazirmatn-Black.ttf")
const SODIUM := Color(1.0, 0.62, 0.28)

var _env: Environment
var _mats := {}
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 7
	_build_environment()
	_build_ground()
	_build_pools()
	_build_blocks()
	_build_station()
	_build_parked_cars()
	_build_streetlights()
	_build_backdrop()
	_spawn_militia()
	_spawn_player()
	Graphics.apply(get_viewport(), _env)
	Settings.changed.connect(func() -> void: Graphics.apply(get_viewport(), _env))

# --- Materials ------------------------------------------------------------

func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var gen := _generated_mat(key)
	if gen:
		_mats[key] = gen
		return gen
	var m := StandardMaterial3D.new()
	match key:
		"asphalt":
			# Wet asphalt: dark and glossy so SSR picks up the streetlights.
			m.albedo_color = Color(0.045, 0.045, 0.05)
			m.roughness = 0.16
			m.metallic_specular = 0.7
		"sidewalk":
			m.albedo_color = Color(0.32, 0.3, 0.28)
			m.roughness = 0.55
		"curb":
			m.albedo_color = Color(0.55, 0.53, 0.5)
			m.roughness = 0.7
		"water":
			# Lit pools: near-black mirror water with a faint teal underwater glow.
			m.albedo_color = Color(0.01, 0.03, 0.04)
			m.roughness = 0.03
			m.metallic = 0.1
			m.emission_enabled = true
			m.emission = Color(0.02, 0.2, 0.22)
			m.emission_energy_multiplier = 0.14
		"pool_edge":
			m.albedo_color = Color(0.7, 0.68, 0.62)
			m.roughness = 0.5
		"window":
			m.albedo_color = Color(0.1, 0.08, 0.05)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.72, 0.42)
			m.emission_energy_multiplier = 1.1
		"window_cold":
			m.albedo_color = Color(0.05, 0.07, 0.1)
			m.emission_enabled = true
			m.emission = Color(0.7, 0.85, 1.0)
			m.emission_energy_multiplier = 1.8
		"station":
			m.albedo_color = Color(0.68, 0.66, 0.6)
			m.roughness = 0.8
		"sandbag":
			m.albedo_color = Color(0.4, 0.35, 0.24)
			m.roughness = 1.0
		"metal":
			m.albedo_color = Color(0.15, 0.15, 0.15)
			m.metallic = 0.8
			m.roughness = 0.35
		"truck":
			m.albedo_color = Color(0.85, 0.85, 0.82)
			m.metallic = 0.4
			m.roughness = 0.3
		_:
			var c := _rng.randf_range(0.35, 0.6)
			m.albedo_color = Color(c, c * 0.95, c * 0.88)
			m.roughness = 0.85
	_mats[key] = m
	return m

## Generated textures (tools/assets) override the flat greybox colours.
const TEXTURED := {
	"asphalt": ["asphalt_wet", 0.15, 6.0],
	"sidewalk": ["sidewalk_tiles", 0.6, 2.0],
	"pool_edge": ["pool_tiles", 0.35, 1.0],
	"station": ["station_wall", 0.85, 4.0],
	"block0": ["facade_brick", 0.85, 3.0],
	"block1": ["facade_stone", 0.75, 4.0],
	"block2": ["facade_concrete", 0.9, 5.0],
	"block3": ["facade_brick", 0.85, 3.0],
}

const WET_ASPHALT := preload("res://assets/shaders/spatial_env_wet_asphalt.gdshader")

func _generated_mat(key: String) -> Material:
	if not TEXTURED.has(key):
		return null
	var spec: Array = TEXTURED[key]
	if key == "asphalt":
		return _wet_asphalt(spec[0], spec[2])
	var m := GeneratedAssets.texture_material(spec[0], spec[1], spec[2])
	if m and key == "sidewalk":
		# Rain-damp paving: darker and the red/grey tiles less saturated. Kept fairly
		# rough: at satin values every lamp threw a broad white glint across the
		# tiles that read as a halo around the player.
		m.albedo_color = Color(0.62, 0.6, 0.6)
		m.roughness = 0.52
	return m

## Asphalt with procedural puddles (see spatial_env_wet_asphalt.gdshader).
func _wet_asphalt(tex_id: String, tile_m: float) -> Material:
	var path := GeneratedAssets.TEX_PATH % tex_id
	if not ResourceLoader.exists(path):
		return null
	var m := ShaderMaterial.new()
	m.shader = WET_ASPHALT
	m.set_shader_parameter(&"albedo_tex", load(path))
	m.set_shader_parameter(&"tile_m", tile_m)
	return m

## Swaps a greybox's mesh for a generated prop scaled to fill it, keeping its collision.
## Swaps a greybox's mesh for a generated prop scaled to fill it, keeping its collision.
## `fit_size` overrides the box size (props taller than their collider), and `yaw_deg`
## turns the prop inside the box (Meshy props face +Z with their long side on X).
func _dress(box: MeshInstance3D, prop_id: String, fit_size := Vector3.ZERO, yaw_deg := 0.0) -> MeshInstance3D:
	var prop := GeneratedAssets.prop(prop_id)
	if prop == null:
		return box
	var box_size := (box.mesh as BoxMesh).size
	var size: Vector3 = fit_size if fit_size != Vector3.ZERO else box_size
	var pivot := Node3D.new()
	pivot.rotation_degrees.y = yaw_deg
	box.add_child(pivot)
	pivot.add_child(prop)
	# Fit in the prop's own frame: a quarter turn swaps width and depth.
	var local := Vector3(size.z, size.y, size.x) if is_equal_approx(absf(fmod(yaw_deg, 180.0)), 90.0) else size
	GeneratedAssets.fit_prop(prop, local)
	prop.position.y += (size.y - box_size.y) * 0.5
	box.mesh = null
	return box

func _box(size: Vector3, pos: Vector3, mat: Material, collide := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		mi.add_child(body)
	add_child(mi)
	return mi

# --- Environment ----------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	# Deep navy zenith over Tehran's smoggy sodium glow on the horizon: the cool/warm
	# split that keeps rooflines readable against the sky.
	sky_mat.sky_top_color = Color(0.012, 0.02, 0.05)
	sky_mat.sky_horizon_color = Color(0.2, 0.1, 0.055)
	sky_mat.sky_curve = 0.09
	# Below the horizon: a dim smog brown, close to the unlit ground's tone, so the
	# far edge of the ground plane fades out instead of cutting against the sky.
	sky_mat.ground_horizon_color = Color(0.09, 0.05, 0.032)
	sky_mat.ground_bottom_color = Color(0.012, 0.01, 0.01)
	sky_mat.ground_curve = 0.06
	# Low smog clouds catch the city glow; the moon's disc shows through them.
	sky_mat.sky_cover = _cloud_cover()
	sky_mat.sky_cover_modulate = Color(0.32, 0.2, 0.15, 0.85)
	sky_mat.sun_angle_max = 2.2
	sky_mat.sun_curve = 0.06
	var sky := Sky.new()
	sky.sky_material = sky_mat

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.2
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.72
	# AgX (4.6+): a lower white point lifts the mid-tones so the street isn't crushed.
	_env.tonemap_agx_white = 9.0
	_env.tonemap_agx_contrast = 1.2
	_env.sdfgi_enabled = true
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_read_sky_light = true
	_env.sdfgi_cascades = 6
	_env.sdfgi_min_cell_size = 0.2
	_env.sdfgi_energy = 1.4
	_env.sdfgi_bounce_feedback = 0.6
	_env.ssr_enabled = true
	_env.ssr_fade_in = 0.1
	_env.ssr_fade_out = 1.5
	_env.ssr_depth_tolerance = 0.25
	_env.ssao_enabled = true
	_env.ssao_intensity = 1.6
	_env.ssao_radius = 1.2
	_env.ssil_enabled = true
	_env.ssil_intensity = 1.2
	# Glow runs before tonemapping in 4.6+: lamps and windows get a wide, soft halo
	# from the lower levels without the whole frame blooming.
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.02
	_env.glow_hdr_threshold = 1.0
	_env.glow_hdr_scale = 1.6
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.set("glow_levels/2", 0.6)
	_env.set("glow_levels/3", 0.7)
	_env.set("glow_levels/4", 0.5)
	_env.set("glow_levels/5", 0.25)
	# Thin city haze: enough to carry the lamp cones, not enough to grey out the street.
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.011
	_env.volumetric_fog_albedo = Color(0.78, 0.8, 0.86)
	_env.volumetric_fog_emission = Color(0.012, 0.014, 0.024)
	_env.volumetric_fog_emission_energy = 0.6
	_env.volumetric_fog_anisotropy = 0.72
	_env.volumetric_fog_length = 180.0
	_env.volumetric_fog_detail_spread = 1.6
	_env.volumetric_fog_ambient_inject = 0.25
	_env.volumetric_fog_gi_inject = 0.6
	_env.volumetric_fog_sky_affect = 0.35
	_env.adjustment_enabled = true
	_env.adjustment_brightness = 1.0
	_env.adjustment_contrast = 1.06
	_env.adjustment_saturation = 1.0
	_env.adjustment_color_correction = _grade_lut()

	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.56, 0.66, 0.92)
	moon.light_energy = 0.25
	moon.light_volumetric_fog_energy = 0.12
	moon.light_angular_distance = 0.6
	moon.shadow_enabled = true
	moon.shadow_blur = 1.5
	moon.directional_shadow_max_distance = 150.0
	moon.rotation_degrees = Vector3(-34, 25, 0)
	add_child(moon)

## Equirectangular smog-cloud cover for the sky: soft, wide-scale noise.
func _cloud_cover() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 11
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 1024
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	# Remap so clear patches show the navy sky between cloud banks.
	var ramp := Gradient.new()
	ramp.set_offset(0, 0.35)
	ramp.set_color(0, Color(0, 0, 0))
	ramp.set_offset(1, 0.85)
	ramp.set_color(1, Color(1, 1, 1))
	tex.color_ramp = ramp
	return tex

## Per-channel grading curve: cool, slightly lifted shadows (moonlight) and warm,
## gently rolled-off highlights (sodium), the teal/orange split of night cinematography.
func _grade_lut() -> Texture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(0.0, 0.006, 0.02))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1.0, 0.98, 0.94))
	g.add_point(0.18, Color(0.15, 0.175, 0.205))
	g.add_point(0.5, Color(0.51, 0.5, 0.49))
	g.add_point(0.8, Color(0.82, 0.79, 0.74))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	return tex

# --- Layout ----------------------------------------------------------------
# The boulevard runs north-south along Z. Pools sit in the median,
# roads either side, apartment blocks beyond the sidewalks.

const BLVD_LENGTH := 180.0

func _build_ground() -> void:
	_box(Vector3(220, 1, 260), Vector3(0, -0.5, 0), _mat("asphalt"))
	for side: int in [-1, 1]:
		_box(Vector3(5, 0.18, BLVD_LENGTH), Vector3(side * 17.5, 0.09, 0), _mat("sidewalk"))
		_box(Vector3(0.25, 0.22, BLVD_LENGTH), Vector3(side * 15.1, 0.11, 0), _mat("curb"))
	_box(Vector3(8, 0.3, BLVD_LENGTH - 20), Vector3(0, 0.15, 0), _mat("sidewalk"))

func _build_pools() -> void:
	# هفت حوض: seven pools down the median.
	for i in 7:
		var z := -60.0 + i * 20.0
		_box(Vector3(6.4, 0.6, 12.4), Vector3(0, 0.3, z), _mat("pool_edge"))
		_box(Vector3(5.8, 0.02, 11.8), Vector3(0, 0.6, z), _mat("water"), false)
		# Underwater pool lights spill teal onto the rim and the mist above.
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.3, 0.85, 0.85)
		glow.light_energy = 0.15
		glow.omni_range = 5.0
		glow.light_volumetric_fog_energy = 0.6
		glow.light_specular = 0.2
		glow.position = Vector3(0, 0.9, z)
		add_child(glow)
	# Back-to-back labels: a double-sided one would read mirrored from behind.
	for facing in [0.0, 180.0]:
		var sign_label := _persian_label(tr("SQUARE_SIGN"), 220, Color(0.95, 0.95, 0.9))
		sign_label.position = Vector3(0, 4.5, 78)
		sign_label.rotation_degrees.y = facing
		add_child(sign_label)

## Generated apartment blocks and the real height (m) each is scaled to.
const BUILDINGS := {"apt_brick_5": 21.0, "apt_stone_6": 24.0, "apt_old_3": 12.5, "apt_concrete_8": 31.0}
## Turn (degrees) that brings each model's front to +Z; Meshy keeps the concept's 3/4 view.
const BUILDING_FRONT_YAW := {}

func _build_blocks() -> void:
	var ids: Array[String] = []
	for id: String in BUILDINGS:
		if ResourceLoader.exists(GeneratedAssets.BUILDING_DIR % id + "model.glb"):
			ids.append(id)
	for side: int in [-1, 1]:
		var z := -85.0
		var last := ""
		while z < 75.0:
			var gap := _rng.randf_range(2.5, 5.0)
			if not ids.is_empty():
				# Never the same block twice in a row.
				var id := ids[_rng.randi() % ids.size()]
				if id == last and ids.size() > 1:
					id = ids[(ids.find(id) + 1) % ids.size()]
				last = id
				z += _place_building(id, BUILDINGS[id], side, z) + gap
				continue
			var depth := _rng.randf_range(12.0, 20.0)
			var width := _rng.randf_range(14.0, 22.0)
			var floors := _rng.randi_range(3, 8)
			var h := floors * 3.2
			var x: float = side * (20.0 + width * 0.5)
			_box(Vector3(width, h, depth), Vector3(x, h * 0.5, z + depth * 0.5), _mat("block%d" % _rng.randi_range(0, 3)))
			_add_windows(x - side * width * 0.5, z, depth, floors, side)
			# Rooftop clutter for the predator to perch on: water tanks and AC units.
			var roof := _box(Vector3(2.2, 1.6, 2.2), Vector3(x + _rng.randf_range(-4, 4), h + 0.8, z + depth * 0.5), _mat("metal"))
			_dress(roof, "water_tank" if _rng.randf() < 0.5 else "ac_unit")
			z += depth + gap

## Stands a generated building on its lot with its front on the sidewalk at x = side * 20,
## starting at z0, under one box collider the player can climb. Returns its length along the street.
func _place_building(id: String, height: float, side: int, z0: float) -> float:
	var pivot := _building_pivot(id, -90.0 * side, height)
	var aabb := GeneratedAssets._bounds(pivot, Transform3D.IDENTITY)
	var street_edge := aabb.position.x if side > 0 else aabb.end.x
	pivot.position = Vector3(side * 20.0 - street_edge, -aabb.position.y, z0 - aabb.position.z)
	_building_collider(aabb, pivot.position)
	return aabb.size.z

## The model under a pivot turned to face `yaw_deg` and scaled to `height`.
func _building_pivot(id: String, yaw_deg: float, height: float) -> Node3D:
	var model := GeneratedAssets.building(id)
	model.rotation_degrees.y = BUILDING_FRONT_YAW.get(id, 0.0)
	var pivot := Node3D.new()
	pivot.add_child(model)
	pivot.rotation_degrees.y = yaw_deg
	add_child(pivot)
	var raw := GeneratedAssets._bounds(pivot, Transform3D.IDENTITY)
	pivot.scale = Vector3.ONE * (height / raw.size.y)
	return pivot

func _building_collider(aabb: AABB, offset: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	shape.shape = box
	body.add_child(shape)
	body.position = aabb.get_center() + offset
	add_child(body)

func _add_windows(face_x: float, z0: float, depth: float, floors: int, side: int) -> void:
	for f in floors:
		var cols := int(depth / 3.5)
		for c in cols:
			if _rng.randf() > 0.35:
				continue
			var key := "window" if _rng.randf() < 0.75 else "window_cold"
			_box(Vector3(0.08, 1.4, 1.6), Vector3(face_x - side * 0.05, f * 3.2 + 1.8, z0 + 1.8 + c * 3.5), _mat(key), false)

func _build_parked_cars() -> void:
	# Paykans parked along both curbs, some gaps, slightly skewed like real parking.
	for side: int in [-1, 1]:
		var z := -78.0
		while z < 74.0:
			if _rng.randf() < 0.55:
				var car := _box(Vector3(1.75, 1.45, 4.4), Vector3(side * 13.6, 0.72, z), _mat("truck"))
				car.rotation_degrees.y = _rng.randf_range(-4.0, 4.0) + (180.0 if side < 0 else 0.0)
				_dress(car, "paykan", Vector3.ZERO, 90.0)
			z += _rng.randf_range(6.0, 11.0)

const STATION_HEIGHT := 16.0
const STATION_SIGN_HEIGHT := 11.0

func _build_station() -> void:
	# The captured کلانتری closes the north end of the boulevard.
	var z := -110.0
	var sign_pos := Vector3(0, 7.2, z + 9.2)
	if ResourceLoader.exists(GeneratedAssets.BUILDING_DIR % "police_station" + "model.glb"):
		# The compound faces the boulevard, its front wall on the old box's front at z + 9.
		var pivot := _building_pivot("police_station", 0.0, STATION_HEIGHT)
		var aabb := GeneratedAssets._bounds(pivot, Transform3D.IDENTITY)
		pivot.position = Vector3(-aabb.get_center().x, -aabb.position.y, z + 9.0 - aabb.end.z)
		_building_collider(aabb, pivot.position)
		sign_pos = Vector3(0, STATION_SIGN_HEIGHT, z + 9.0 + 0.3)
	else:
		_box(Vector3(34, 9, 18), Vector3(0, 4.5, z), _mat("station"))
		_box(Vector3(10, 4, 1), Vector3(0, 2, z + 9.4), _mat("metal"))
	var sign_label := _persian_label(tr("STATION_SIGN"), 160, Color(0.85, 0.92, 1.0))
	sign_label.position = sign_pos
	add_child(sign_label)
	var sign_light := OmniLight3D.new()
	sign_light.light_color = Color(0.7, 0.85, 1.0)
	sign_light.light_energy = 2.0
	sign_light.omni_range = 12.0
	sign_light.position = Vector3(0, 7.5, z + 11)
	add_child(sign_light)
	# Militia checkpoint: sandbag walls and an armed pickup.
	for x in [-8.0, -4.0, 4.0, 8.0]:
		_dress(_box(Vector3(3.5, 1.1, 1.0), Vector3(x, 0.55, z + 20), _mat("sandbag")), "sandbag_wall")
	_dress(_box(Vector3(2.0, 1.4, 4.8), Vector3(10, 0.7, z + 26), _mat("truck")), "pickup_armed", Vector3(2.0, 2.6, 4.8), 90.0)
	_dress(_box(Vector3(5.0, 1.0, 0.2), Vector3(0, 0.5, z + 30), _mat("curb"), false), "barrier")
	_box(Vector3(0.15, 0.15, 1.6), Vector3(10, 2.1, z + 25), _mat("metal"), false)
	_light_station(z)

## Night lighting for the captured station: two crossing floodlights on the
## checkpoint (the only shadowed lights here), a cold wash on the white facade,
## the police green at the gate, and a burn barrel the guards stand around.
func _light_station(z: float) -> void:
	for side: int in [-1, 1]:
		var flood := SpotLight3D.new()
		flood.light_color = Color(0.92, 0.96, 1.0)
		flood.light_energy = 6.5
		flood.spot_range = 42.0
		flood.spot_angle = 26.0
		flood.spot_angle_attenuation = 0.7
		flood.shadow_enabled = true
		flood.shadow_blur = 1.2
		flood.light_specular = 0.5
		flood.light_volumetric_fog_energy = 0.8
		flood.position = Vector3(side * 9.5, 10.5, z + 9.6)
		add_child(flood)
		# Each lamp crosses over to the far side of the sandbag line.
		flood.look_at(Vector3(-side * 2.5, 0.0, z + 19.0))
		_lamp_head(flood.position + Vector3(0, 0.15, 0), Color(0.9, 0.95, 1.0), 6.0, 0.35)
		# Facade wash from the pavement up the white walls, no shadows.
		var wash := SpotLight3D.new()
		wash.light_color = Color(0.75, 0.88, 1.0)
		wash.light_energy = 3.0
		wash.spot_range = 16.0
		wash.spot_angle = 40.0
		wash.light_volumetric_fog_energy = 0.0
		wash.position = Vector3(side * 6.0, 0.4, z + 13.5)
		add_child(wash)
		wash.look_at(Vector3(side * 6.0, 8.0, z + 8.5))
	# Green police strip over the gate (FARAJA green), soft and unshadowed.
	var green := OmniLight3D.new()
	green.light_color = Color(0.25, 1.0, 0.45)
	green.light_energy = 1.6
	green.omni_range = 9.0
	green.light_volumetric_fog_energy = 0.8
	green.position = Vector3(0, 3.6, z + 10.6)
	add_child(green)
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color.BLACK
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(0.3, 1.0, 0.5)
	strip_mat.emission_energy_multiplier = 4.0
	_box(Vector3(7.0, 0.12, 0.08), Vector3(0, 4.1, z + 9.3), strip_mat, false)
	_burn_barrel(Vector3(-11.5, 0, z + 17.0))
	_headlights(Vector3(10.0, 0.95, z + 28.45))

## The armed pickup idles with its headlights on down the boulevard: one shadowed
## beam that throws anything approaching the checkpoint into long silhouettes.
## (The model's own headlight lenses catch it; no extra lens geometry is needed.)
func _headlights(front: Vector3) -> void:
	var beam := SpotLight3D.new()
	beam.light_color = Color(1.0, 0.94, 0.82)
	beam.light_energy = 7.0
	beam.spot_range = 38.0
	beam.spot_angle = 24.0
	beam.spot_angle_attenuation = 0.8
	beam.shadow_enabled = true
	beam.light_volumetric_fog_energy = 0.7
	beam.position = front + Vector3(0, 0.05, 0.3)
	add_child(beam)
	beam.look_at(front + Vector3(-1.5, -1.2, 20.0))

## A rusted oil drum with a fire in it: a flickering warm key light at knee height
## that rims the guards from below. No shadows, no collision.
func _burn_barrel(pos: Vector3) -> void:
	var drum := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 0.9
	drum.mesh = cyl
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.22, 0.12, 0.07)
	rust.roughness = 0.9
	rust.metallic = 0.3
	drum.material_override = rust
	drum.position = pos + Vector3(0, 0.45, 0)
	add_child(drum)
	var embers := StandardMaterial3D.new()
	embers.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	embers.albedo_color = Color(1.0, 0.45, 0.12) * 6.0
	_box(Vector3(0.5, 0.05, 0.5), pos + Vector3(0, 0.88, 0), embers, false)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.5, 0.18)
	fire.light_energy = 3.0
	fire.omni_range = 9.0
	fire.omni_attenuation = 1.6
	fire.light_volumetric_fog_energy = 1.2
	fire.position = pos + Vector3(0, 1.3, 0)
	add_child(fire)
	var tw := fire.create_tween().set_loops()
	tw.tween_property(fire, "light_energy", 2.2, 0.13)
	tw.tween_property(fire, "light_energy", 3.4, 0.09)
	tw.tween_property(fire, "light_energy", 2.7, 0.17)

## A small emissive bulb so each fixture reads as a light source (and blooms).
func _lamp_head(pos: Vector3, color: Color, energy: float, size := 0.28) -> void:
	var bulb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size * 0.5
	mesh.height = size * 0.6
	mesh.radial_segments = 12
	mesh.rings = 6
	bulb.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b) * energy
	bulb.material_override = m
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.position = pos
	add_child(bulb)

## Sodium for most lamps; every fourth is a newer, colder LED head, and one
## is dying, so the boulevard reads as pools of light rather than a lit corridor.
func _lamp_colour(i: int) -> Color:
	if i == 7:
		return SODIUM * 0.35
	if i % 4 == 3:
		return Color(0.9, 0.93, 1.0)
	return SODIUM

func _build_streetlights() -> void:
	var i := 0
	for z in range(-80, 80, 16):
		for side: int in [-1, 1]:
			var x: float = side * 15.6
			_dress(_box(Vector3(0.18, 7.5, 0.18), Vector3(x, 3.75, z), _mat("metal")), "streetlight", Vector3(2.6, 8.2, 2.6), -90.0 * side)
			_box(Vector3(1.6, 0.12, 0.3), Vector3(x - side * 0.7, 7.5, z), _mat("metal"), false)
			var colour := _lamp_colour(i)
			var head := Vector3(x - side * 1.3, 7.2, z)
			# A downward cone: lit pool on the road and a visible shaft in the mist.
			var lamp := SpotLight3D.new()
			lamp.light_color = Color(colour.r, colour.g, colour.b) if i != 7 else SODIUM
			lamp.light_energy = (12.0 if i % 4 != 3 else 8.0) if i != 7 else 3.0
			# Pools about 12 m across, so each lamp lights its own stretch of street
			# instead of washing into the next one (or framing the player in a halo).
			lamp.spot_range = 15.0
			lamp.spot_attenuation = 0.5
			lamp.spot_angle = 60.0
			lamp.spot_angle_attenuation = 1.2
			lamp.light_volumetric_fog_energy = 0.9
			lamp.light_size = 0.15
			# Puddles still mirror the lamps through SSR; a softer direct glint keeps
			# the damp pavement from flaring white under every head.
			lamp.light_specular = 0.55
			# Shadow budget: only every other lamp casts shadows.
			lamp.shadow_enabled = i % 2 == 0
			lamp.shadow_blur = 1.5
			lamp.distance_fade_enabled = true
			lamp.distance_fade_begin = 80.0
			lamp.distance_fade_length = 20.0
			lamp.position = head
			lamp.rotation_degrees = Vector3(-90, 0, 0)
			add_child(lamp)
			_lamp_head(head + Vector3(0, 0.12, 0), colour, 8.0)
			i += 1

## Blocks that close the vista beyond both ends of the boulevard: behind the station
## to the north and past the square sign to the south. They sit outside the play
## space (|z| > 95) with plain box colliders, and take no random draws so the
## rest of the level's layout is unchanged.
const BACKDROP := [
	["apt_concrete_8", 31.0, -42.0, -124.0, 0.0],
	["apt_stone_6", 24.0, -25.0, -128.0, 0.0],
	["apt_brick_5", 21.0, 26.0, -127.0, 0.0],
	["apt_concrete_8", 31.0, 44.0, -123.0, 0.0],
	["apt_brick_5", 21.0, -64.0, -106.0, 0.0],
	["apt_stone_6", 24.0, 64.0, -108.0, 0.0],
	["apt_stone_6", 24.0, -30.0, 100.0, 180.0],
	["apt_old_3", 12.5, -8.0, 104.0, 180.0],
	["apt_brick_5", 21.0, 14.0, 101.0, 180.0],
	["apt_concrete_8", 31.0, 36.0, 99.0, 180.0],
]

func _build_backdrop() -> void:
	for spec: Array in BACKDROP:
		var id: String = spec[0]
		if not ResourceLoader.exists(GeneratedAssets.BUILDING_DIR % id + "model.glb"):
			continue
		var pivot := _building_pivot(id, spec[4], spec[1])
		var aabb := GeneratedAssets._bounds(pivot, Transform3D.IDENTITY)
		# Front face on the given z line, centred on x.
		var front: float = aabb.end.z if spec[4] == 0.0 else aabb.position.z
		pivot.position = Vector3(spec[2] - aabb.get_center().x, -aabb.position.y, spec[3] - front)
		_building_collider(aabb, pivot.position)

func _persian_label(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = PERSIAN_FONT
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	return l

# --- Actors ---------------------------------------------------------------

func _spawn_militia() -> void:
	var routes := [
		[Vector3(-6, 0.2, -88), Vector3(6, 0.2, -88)],
		[Vector3(-12, 0.2, -60), Vector3(-12, 0.2, -20)],
		[Vector3(12, 0.2, -30), Vector3(12, 0.2, 10)],
		[Vector3(-12, 0.2, 20), Vector3(-12, 0.2, 55)],
		[Vector3(8, 0.2, 40), Vector3(8, 0.2, 70)],
		[Vector3(0, 0.2, -95), Vector3(0, 0.2, -95)],
	]
	# Officer at the checkpoint, a heavy gunner at the door, the rest mixed.
	var variants := ["militia_officer", "militia_rifleman", "militia_plainclothes", "militia_rifleman", "militia_plainclothes", "militia_heavy"]
	for i in routes.size():
		var route: Array = routes[i]
		var m := Militia.new()
		m.variant = variants[i]
		m.patrol_points.assign(route)
		m.position = route[0]
		add_child(m)

func _spawn_player() -> void:
	var player := Volatile.new()
	player.position = Vector3(18, 0.3, 82)
	add_child(player)
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	hud.bind(player)
	player.died.connect(_on_player_died.bind(hud))

func _on_player_died(hud: Node) -> void:
	hud.show_message(tr("DEATH_TEXT"))
	await get_tree().create_timer(3.0).timeout
	get_tree().reload_current_scene()
