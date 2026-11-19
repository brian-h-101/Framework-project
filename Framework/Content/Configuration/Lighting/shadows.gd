extends RefCounted


static func defaults() -> Dictionary:
	return {
		"shadow_enabled": true,
		"density": 0.45,
		"debug_sdf": false,
		"debug_shadow_mask": false,
		"debug_shadow_channels": false,
		"sdf_scale": Viewport.SDF_SCALE_25_PERCENT,
		"blend": {
			"length_px": 160.0,
			"fade_px": 64.0,
			"softness_px": 12.0,
		},
	}