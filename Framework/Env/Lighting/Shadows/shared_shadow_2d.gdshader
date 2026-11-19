shader_type canvas_item;
render_mode unshaded;

uniform bool shadows_enabled = true;
uniform bool debug_mask = false;
uniform bool debug_channels = false;
uniform float density : hint_range(0.0, 1.0) = 0.45;

uniform bool sun_enabled = false;
uniform vec2 sun_direction = vec2(0.0, -1.0);

uniform int point_count = 0;
uniform vec3 point_lights[8];

uniform float shadow_length_px = 160.0;
uniform float fade_px = 64.0;
uniform float softness_px = 12.0;


void fragment() {
	vec2 origin = screen_uv_to_sdf(SCREEN_UV);
	vec2 next_pixel = screen_uv_to_sdf(
		SCREEN_UV + vec2(SCREEN_PIXEL_SIZE.x, 0.0)
	);

	float units_per_pixel = max(
		length(next_pixel - origin),
		0.000001
	);

	float surface_distance = texture_sdf(origin) / units_per_pixel;
	vec2 pixel_position = SCREEN_UV / SCREEN_PIXEL_SIZE;

	float sun_mask = 0.0;
	float point_mask = 0.0;

	float fade_width = clamp(
		fade_px,
		0.0,
		max(shadow_length_px, 0.0)
	);

	if (
		shadows_enabled
		&& shadow_length_px > 0.0
		&& surface_distance > 1.0
	) {
		// Source 0 is the sun. Remaining sources are point lights.
		for (int source_index = 0; source_index < 9; source_index++) {
			if (source_index > point_count) {
				break;
			}

			bool is_sun = source_index == 0;
			vec2 toward_light = vec2(0.0);
			float trace_length = shadow_length_px;
			float light_coverage = 1.0;

			if (is_sun) {
				if (
					!sun_enabled
					|| trace_length <= 0.0
					|| length(sun_direction) <= 0.000001
				) {
					continue;
				}

				toward_light = normalize(sun_direction);
			} else {
				vec3 light_data = point_lights[source_index - 1];
				vec2 to_light = light_data.xy - pixel_position;
				float distance_to_light = length(to_light);

				if (
					distance_to_light <= 1.0
					|| distance_to_light > light_data.z
				) {
					continue;
				}

				toward_light = to_light / distance_to_light;
				trace_length = min(
					shadow_length_px,
					distance_to_light - 1.0
				);

				if (fade_width > 0.0) {
					light_coverage = smoothstep(
						0.0,
						fade_width,
						light_data.z - distance_to_light
					);
				}
			}

			float travel_px = 1.0;
			float visibility = 1.0;

			for (int step_index = 0; step_index < 64; step_index++) {
				if (travel_px >= trace_length) {
					break;
				}

				vec2 sample_position = origin
					+ toward_light * travel_px * units_per_pixel;

				float distance_px = texture_sdf(sample_position)
					/ units_per_pixel;

				float sample_visibility = 1.0;

				if (distance_px <= 1.0) {
					sample_visibility = 0.0;
				} else if (softness_px > 0.0) {
					float penumbra_px = max(
						softness_px * travel_px / shadow_length_px,
						0.001
					);

					sample_visibility = smoothstep(
						0.0,
						penumbra_px,
						distance_px - 1.0
					);
				}

				if (fade_width > 0.0) {
					float distance_fade = smoothstep(
						shadow_length_px - fade_width,
						shadow_length_px,
						travel_px
					);

					sample_visibility = mix(
						sample_visibility,
						1.0,
						distance_fade
					);
				}

				visibility = min(visibility, sample_visibility);

				if (distance_px <= 1.0) {
					break;
				}

				travel_px += max(distance_px * 0.8, 1.0);
			}

			float coverage = (1.0 - visibility) * light_coverage;

			if (is_sun) {
				sun_mask = coverage;
			} else {
				point_mask = max(point_mask, coverage);
			}
		}
	}

	float combined_mask = max(sun_mask, point_mask);

	if (debug_mask) {
		vec3 preview_color = debug_channels
			? vec3(sun_mask, 0.0, point_mask)
			: vec3(combined_mask);

		if (surface_distance <= 1.0) {
			preview_color = vec3(0.35);
		}

		COLOR = vec4(preview_color, 1.0);
	} else {
		float opacity = clamp(density, 0.0, 1.0) * combined_mask;
		COLOR = vec4(vec3(0.0), opacity);
	}
}
