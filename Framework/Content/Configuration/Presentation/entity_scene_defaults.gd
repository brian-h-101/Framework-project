extends RefCounted


static func defaults() -> Dictionary:
	return {
		"body_size": Vector2(32, 32),
		"body_color": Color(0.55, 0.65, 0.75, 1.0),
		"casts_shadow": true,
		"movement_content": null,
		"camera_scene": null,
		"interaction_input": false,
	}