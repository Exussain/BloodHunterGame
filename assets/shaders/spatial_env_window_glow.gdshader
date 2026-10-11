shader_type spatial;
// Night window lights for generated buildings, drawn as an additive pass over the
// building's own material. `glass_mask` (from tools/assets/generate.py) marks the
// window panes in the model's texture; world-space cells the size of one window
// bay decide which panes are lit, so a window split across UV islands lights as one.
render_mode blend_add, unshaded, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

uniform sampler2D glass_mask : hint_default_black, filter_linear_mipmap;
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.35;
uniform float cold_fraction : hint_range(0.0, 1.0) = 0.25;
uniform vec3 cell_size = vec3(3.0, 3.2, 3.0);
uniform vec3 warm : source_color = vec3(1.0, 0.62, 0.3);
uniform vec3 cold : source_color = vec3(0.65, 0.8, 1.0);
uniform float energy = 2.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Soft edges only; flat roofs and ledges are never windows.
	float glass = smoothstep(0.45, 0.8, texture(glass_mask, UV).r);
	glass *= 1.0 - smoothstep(0.25, 0.45, abs(world_normal.y));
	vec3 cell = floor(world_pos / cell_size);
	float h = hash(cell);
	float lit = step(h, lit_fraction);
	// Ground floors are shops and lobbies: dark at night.
	lit *= step(cell_size.y, world_pos.y);
	vec3 colour = mix(warm, cold, step(1.0 - cold_fraction, hash(cell + 17.0)));
	// Dimmer and brighter rooms, so a lit facade isn't one flat tone.
	float level = 0.55 + 0.45 * hash(cell + 41.0);
	ALBEDO = colour * glass * lit * level * energy;
}
