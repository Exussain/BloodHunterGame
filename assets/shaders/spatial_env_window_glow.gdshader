shader_type spatial;
// Night window lights for generated buildings, drawn as an additive pass over the
// building's own material. `glass_mask` (from tools/assets/generate.py) marks the
// window panes in the model's texture; world-space cells the size of one window
// bay decide which panes are lit, so a window split across UV islands lights as one.
// Target: Forward+ desktop. Five mask samples, no branches, unshaded additive.
render_mode blend_add, unshaded, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

group_uniforms mask;
uniform sampler2D glass_mask : hint_default_black, filter_linear_mipmap;
/// Blur radius in mask texels: wipes balcony railings and frame noise out of the
/// mask so panes light as clean shapes instead of glittering specks. (The masks
/// import without mipmaps, so this is a 4-tap box blur rather than a mip bias.)
uniform float mask_blur : hint_range(0.0, 16.0) = 6.0;
/// Mask level where a pane starts and finishes lighting.
uniform float mask_low : hint_range(0.0, 1.0) = 0.55;
uniform float mask_high : hint_range(0.0, 1.0) = 0.78;

group_uniforms rooms;
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.35;
uniform float cold_fraction : hint_range(0.0, 1.0) = 0.2;
uniform vec3 cell_size = vec3(3.0, 3.2, 3.0);
/// Tungsten interior, fluorescent-white kitchen, and TV-blue room colours.
uniform vec3 warm : source_color = vec3(1.0, 0.66, 0.36);
uniform vec3 neutral : source_color = vec3(1.0, 0.9, 0.74);
uniform vec3 cold : source_color = vec3(0.6, 0.76, 1.0);
uniform float energy = 1.7;

group_uniforms dark_glass;
/// Faint sky/city reflection on unlit panes so dark windows still read as glass.
uniform vec3 dark_glass_tint : source_color = vec3(0.05, 0.07, 0.11);
uniform float dark_glass_energy = 0.35;
group_uniforms;

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
	// Blurred mask (shapes) times the sharp mask (edges): clean panes, crisp frames.
	vec2 texel = mask_blur / vec2(textureSize(glass_mask, 0));
	float sharp = texture(glass_mask, UV).r;
	float soft = 0.2 * sharp + 0.2 * (
		texture(glass_mask, UV + vec2(texel.x, texel.y)).r
		+ texture(glass_mask, UV + vec2(-texel.x, texel.y)).r
		+ texture(glass_mask, UV + vec2(texel.x, -texel.y)).r
		+ texture(glass_mask, UV + vec2(-texel.x, -texel.y)).r);
	float glass = smoothstep(mask_low, mask_high, soft) * smoothstep(0.25, 0.6, sharp);
	// Flat roofs and ledges are never windows.
	glass *= 1.0 - smoothstep(0.25, 0.45, abs(world_normal.y));
	vec3 cell = floor(world_pos / cell_size);
	float h = hash(cell);
	float lit = step(h, lit_fraction);
	// Ground floors are shops and lobbies: dark at night.
	lit *= step(cell_size.y, world_pos.y);
	float pick = hash(cell + 17.0);
	vec3 colour = mix(warm, neutral, step(0.6, pick));
	colour = mix(colour, cold, step(1.0 - cold_fraction, pick));
	// Dimmer and brighter rooms, so a lit facade isn't one flat tone.
	float level = 0.45 + 0.55 * hash(cell + 41.0);
	// Ceiling light: a room is brighter near the top of its window than at the sill.
	float in_cell = fract(world_pos.y / cell_size.y);
	level *= mix(0.75, 1.15, in_cell);
	vec3 lit_rgb = colour * lit * level * energy;
	vec3 dark_rgb = dark_glass_tint * dark_glass_energy * (1.0 - lit);
	ALBEDO = (lit_rgb + dark_rgb) * glass;
}
