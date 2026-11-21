shader_type canvas_item;
render_mode unshaded;

uniform float debug_range_px = 32.0;

void fragment() {
	vec2 sdf_position = screen_uv_to_sdf(SCREEN_UV);

	vec2 next_pixel = screen_uv_to_sdf(
		SCREEN_UV + vec2(SCREEN_PIXEL_SIZE.x, 0.0)
	);

	float units_per_pixel = max(
		length(next_pixel - sdf_position),
		0.000001
	);

	float distance_px = texture_sdf(sdf_position) / units_per_pixel;

	float halo = 1.0 - smoothstep(
		0.0,
		debug_range_px,
		max(distance_px, 0.0)
	);

	vec3 background = vec3(0.03, 0.04, 0.06);
	vec3 outline = vec3(0.1, 1.0, 0.4);

	COLOR = vec4(mix(background, outline, halo), 1.0);
}