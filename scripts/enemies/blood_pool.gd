extends MeshInstance3D
## A pool of blood on the ground: an irregular, lobed, glossy wet shape that spreads
## out from the wound over a second or two, darker and thicker-looking at its rim.
## Drawn on a flat quad with a procedural noise mask (no texture assets), in the
## opaque pass with alpha scissor so screen-space reflections make it read as wet.
## Call it as preload("res://scripts/enemies/blood_pool.gd").spawn(...).

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform float spread : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;
uniform vec3 core_color : source_color = vec3(0.20, 0.006, 0.004);
uniform vec3 rim_color : source_color = vec3(0.045, 0.0, 0.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * noise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// Lobed outline: the edge radius wanders with direction, plus fine ragged noise.
	vec2 dir = r > 0.0001 ? p / r : vec2(1.0, 0.0);
	float lobes = fbm(dir * 1.6 + vec2(seed, seed * 0.37));
	float edge = spread * (0.42 + 0.58 * lobes);
	float ragged = (fbm(p * 7.0 + seed) - 0.5) * 0.09;
	float dist = edge - (r + ragged);
	// Small satellite drops around the main pool, revealed as it spreads.
	float drops = step(0.86, noise(p * 9.0 + seed * 3.1)) * step(r, spread * 1.05) * step(0.0, -dist);
	float mask = max(smoothstep(0.0, 0.02, dist), drops);
	ALPHA = mask;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Darker toward the rim where it pools thick, a little variation inside.
	float rim = 1.0 - smoothstep(0.0, 0.12, dist);
	float mottling = fbm(p * 4.0 - seed) * 0.35;
	ALBEDO = mix(core_color * (0.8 + mottling), rim_color, max(rim, drops * 0.6));
	ROUGHNESS = 0.04 + rim * 0.05;
	SPECULAR = 0.65;
	// Meniscus: the surface bends down at the rim, catching the street lights.
	float slope = rim * 0.6;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(dir.x * slope, 0.0, dir.y * slope, 0.0)).xyz);
}
"""

static var _shader: Shader

## Spreads a pool of `radius` metres at `at` (on the ground) under `parent`, growing
## from a small spot to full size over `grow_time` seconds.
static func spawn(parent: Node, at: Vector3, radius: float, grow_time := 1.6) -> MeshInstance3D:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var pool := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	pool.mesh = quad
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter(&"seed", randf() * 100.0)
	mat.set_shader_parameter(&"spread", 0.12)
	pool.material_override = mat
	parent.add_child(pool)
	pool.global_position = at
	pool.rotation.y = randf() * TAU
	var tw := pool.create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"spread", v), 0.12, 1.0, grow_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return pool
