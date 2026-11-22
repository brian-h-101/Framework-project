extends Resource

const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Interactions/interaction_resource.gd"
)

@export var id: StringName = &""
@export var interaction: InteractionResource
@export var trigger: StringName = &"interval"
@export var targeting: StringName = &"nearest"

# Elapsed running-session seconds, independent of day/night scaling.
@export var interval_seconds: float = 1.0
@export var cooldown_seconds: float = 1.0


func validation_error() -> String:
	if String(id).strip_edges().is_empty():
		return "Automation requires a nonempty ID."

	if interaction == null:
		return "Automation requires an Interaction resource."

	if String(interaction.id).strip_edges().is_empty():
		return "The referenced Interaction requires a nonempty ID."

	if trigger != &"interval":
		return "Automation currently supports only the interval trigger."

	if targeting != &"nearest":
		return "Automation currently supports only nearest targeting."

	if not is_finite(interval_seconds) or interval_seconds <= 0.0:
		return "Automation interval must be finite and greater than zero."

	if not is_finite(cooldown_seconds) or cooldown_seconds < 0.0:
		return "Automation cooldown must be finite and nonnegative."

	return ""


func to_definition() -> Dictionary:
	return {
		"id": id,
		"interaction": interaction.id if interaction != null else &"",
		"trigger": trigger,
		"targeting": targeting,
		"interval_seconds": interval_seconds,
		"cooldown_seconds": cooldown_seconds,
	}


func read() -> Dictionary:
	var error := validation_error()

	if not error.is_empty():
		return {"ok": false, "value": null, "error": error}

	return {
		"ok": true,
		"value": to_definition(),
		"error": "",
	}
