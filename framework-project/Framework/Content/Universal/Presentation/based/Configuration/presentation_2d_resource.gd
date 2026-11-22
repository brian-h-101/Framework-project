extends Resource

const MovementConfiguration = preload("res://Framework/Content/Universal/Movement/based/Configuration/movement_profile.gd")

@export var body_size: Vector2 = Vector2(32, 32)
@export var body_color: Color = Color(0.55, 0.65, 0.75, 1.0)
@export var casts_shadow: bool = true
@export var movement_content: MovementConfiguration
@export var camera_scene: PackedScene
@export var interaction_input: bool = false


func to_definition() -> Dictionary:
	if not body_size.is_finite() or body_size.x <= 0.0 or body_size.y <= 0.0:
		return {
			"ok": false,
			"value": null,
			"error": "Presentation body size must contain two positive finite values.",
		}
	if movement_content != null:
		var checked := movement_content.read()
		if not checked["ok"]:
			return checked
	return {
		"body_size": body_size,
		"body_color": body_color,
		"casts_shadow": casts_shadow,
		"movement_content": movement_content,
		"camera_scene": camera_scene,
		"interaction_input": interaction_input,
	}
