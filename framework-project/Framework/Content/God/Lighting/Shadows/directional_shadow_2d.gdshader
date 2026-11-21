shader_type canvas_item;

uniform bool shadows_enabled = true;
uniform float shadow_length_px = 160.0;
uniform float fade_start_px = 96.0;
uniform float softness_px = 12.0;

varying vec2 sdf_origin;
varying float sdf_units_per_pixel;



void fragment() {
	sdf_origin = screen_uv_to_sdf(SCREEN_UV);

	vec2 next_pixel = screen_uv_to_sdf(
		SCREEN_UV + vec2(SCREEN_PIXEL_SIZE.x, 0.0)
	);

	sdf_units_per_pixel = max(
		length(next_pixel - sdf_origin),
		0.000001
	);
}


void light() {
	vec3 contribution = LIGHT_COLOR.rgb * COLOR.rgb;

	if (LIGHT_IS_DIRECTIONAL) {
		float direction_length = length(LIGHT_DIRECTION.xy);

		if (
			shadows_enabled
			&& shadow_length_px > 0.0
			&& direction_length > 0.000001
		) {
			vec2 toward_light = LIGHT_DIRECTION.xy
				/ direction_length;

			float travel_px = 0.0;
			float visibility = 1.0;

			for (int step_index = 0; step_index < 64; step_index++) {
				if (travel_px >= shadow_length_px) {
					break;
				}

				vec2 sample_position = sdf_origin
					+ toward_light * travel_px * sdf_units_per_pixel;

				float distance_px = texture_sdf(sample_position)
					/ sdf_units_per_pixel;

				float edge_visibility = 1.0;

				if (distance_px <= 1.0) {
					edge_visibility = 0.0;
				} else if (softness_px > 0.0) {
					float penumbra_px = max(
						softness_px * travel_px / shadow_length_px,
						0.001
					);

					edge_visibility = smoothstep(
						0.0,
						penumbra_px,
						distance_px - 1.0
					);
				}

				float distance_fade = smoothstep(
					fade_start_px,
					shadow_length_px,
					travel_px
				);

				float sample_visibility = mix(
					edge_visibility,
					1.0,
					distance_fade
				);

				visibility = min(visibility, sample_visibility);

				if (distance_px <= 1.0) {
					break;
				}
				travel_px += max(distance_px * 0.8, 1.0);
			}

			contribution *= visibility;
		}
	} else {
		contribution *= LIGHT_ENERGY;
	}

	LIGHT = vec4(contribution, LIGHT_COLOR.a);
}