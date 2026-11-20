extends "res://Framework/Env/Configuration/Resources/configuration_resource.gd"

@export var shadow_enabled: bool = false
@export_range(0.0, 1.0) var density: float = 0.0
@export var debug_sdf: bool = false
@export var debug_shadow_mask: bool = false
@export var debug_shadow_channels: bool = false
@export_enum("100%:0", "50%:1", "25%:2") var sdf_scale: int = 0
@export var length_px: float = 0.0
@export var fade_px: float = 0.0
@export var softness_px: float = 0.0


func to_definition() -> Dictionary:
	return {
		"shadow_enabled": shadow_enabled,
		"density": density,
		"debug_sdf": debug_sdf,
		"debug_shadow_mask": debug_shadow_mask,
		"debug_shadow_channels": debug_shadow_channels,
		"sdf_scale": sdf_scale,
		"blend": {"length_px": length_px, "fade_px": fade_px, "softness_px": softness_px},
	}


func validation_error() -> String:
	if not is_finite(density) or density < 0.0 or density > 1.0:
		return "Shadow density must be between 0 and 1."
	if sdf_scale not in [0, 1, 2]:
		return "Unsupported viewport SDF scale."
	for value in [length_px, fade_px, softness_px]:
		if not is_finite(value) or value < 0.0:
			return "Shadow blend distances must be nonnegative and finite."
	return ""
