shader_type canvas_item;
// Rage form screen filter: a pulsing blood-red vignette, chromatic split and a
// slow heat warp toward the edges. `strength` fades it in and out (0..1).

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint : source_color = vec3(0.85, 0.02, 0.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_centre = uv - 0.5;
	float edge = clamp(length(from_centre) * 1.6, 0.0, 1.0);
	float pulse = 0.75 + 0.25 * sin(TIME * 7.0);
	// Warp: edges ripple more than the centre, so the aim point stays readable.
	vec2 warp = vec2(sin(uv.y * 24.0 + TIME * 3.0), cos(uv.x * 20.0 - TIME * 2.5)) * 0.004 * edge * strength;
	vec2 split = from_centre * 0.012 * edge * strength;
	vec3 colour;
	colour.r = texture(screen, uv + warp + split).r;
	colour.g = texture(screen, uv + warp).g;
	colour.b = texture(screen, uv + warp - split).b;
	// Drain colour toward red, then darken the edges with a pulsing red vignette.
	float luma = dot(colour, vec3(0.299, 0.587, 0.114));
	colour = mix(colour, vec3(luma * 1.25, luma * 0.35, luma * 0.3), 0.55 * strength);
	colour = mix(colour, tint * 0.35, smoothstep(0.35, 1.0, edge) * pulse * strength);
	COLOR = vec4(colour, 1.0);
}
