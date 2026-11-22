extends SceneTree

const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Actions/action_resource.gd"
)
const ExistingAction = preload(
	"res://Diagnostics/Fixtures/GameplayBaselines/change_health.gd"
)


func _initialize() -> void:
	var action := ResourceLoader.load(
		"res://Diagnostics/Fixtures/GameplayResources/change_health.tres"
	) as ActionResource

	if action == null:
		push_error("Could not load the action resource.")
		quit(1)
		return

	var definition := action.to_definition()
	var expected := ExistingAction.definition()
	expected["behavior_id"] = &"attribute_effects"
	var matches := definition == expected

	print(
		"[resource] Action matches existing definition: ",
		matches
	)

	definition["effects"][0]["path"][0] = "diagnostic_only"

	var resource_unchanged: bool = (
		action.effects[0]["path"] == ["current"]
	)

	print(
		"[resource] Converted data is independent: ",
		resource_unchanged
	)

	var passed: bool = matches and resource_unchanged

	print("[resource] Checks passed: ", passed)
	quit(0 if passed else 1)
