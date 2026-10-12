shader_type spatial;
// Rain-wet asphalt for the night boulevard. World-space XZ mapping (the ground is
// one big box), with a procedural puddle mask: puddles are dark, near-mirror and
// flat so SSR picks up the sodium lamps and lit windows; the road between them is
// damp and only satin, so the street still reads as asphalt rather than glass.
// Target: Forward+ desktop. One texture sample, 4-octave value noise, no branches.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms surface;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 6.0;
uniform vec3 tint : source_color = vec3(0.55, 0.55, 0.58);
group_uniforms wetness;
/// Roughness of the damp road surface between puddles.
uniform float road_roughness : hint_range(0.0, 1.0) = 0.42;
/// Roughness inside puddles (low = sharp reflections).
uniform float puddle_roughness : hint_range(0.0, 1.0) = 0.04;
/// Share of the road covered by standing water.
uniform float puddle_coverage : hint_range(0.0, 1.0) = 0.42;
/// Puddle size in metres.
uniform float puddle_scale = 7.0;
/// How much darker the wet asphalt reads inside puddles.
uniform float puddle_darken : hint_range(0.0, 1.0) = 0.55;

group_uniforms;

varying vec3 world_pos;
varying vec3 world_normal;

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = texture(albedo_tex, world_pos.xz / tile_m).rgb * tint;
	// Only upward faces collect water; the box sides stay plain damp asphalt.
	float up = smoothstep(0.7, 0.95, world_normal.y);
	float n = fbm(world_pos.xz / puddle_scale);
	float puddle = smoothstep(1.0 - puddle_coverage, 1.0 - puddle_coverage + 0.08, n) * up;
	// Damp rim around each puddle so the edge is a gradient, not a cut-out.
	float rim = smoothstep(1.0 - puddle_coverage - 0.12, 1.0 - puddle_coverage, n) * up;
	ALBEDO = base * mix(1.0, 1.0 - puddle_darken, max(puddle, rim * 0.5));
	ROUGHNESS = mix(mix(road_roughness, road_roughness * 0.6, rim), puddle_roughness, puddle);
	SPECULAR = mix(0.5, 0.65, puddle);
	METALLIC = 0.0;
}
