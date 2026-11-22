extends SceneTree

const ConditionGroupResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_group_resource.gd"
)
const ExistingInteraction = preload(
	"res://Diagnostics/Fixtures/GameplayBaselines/strike.gd"
)


func _initialize() -> void:
	var group := ResourceLoader.load(
		"res://Diagnostics/Fixtures/GameplayResources/can_strike.tres"
	) as ConditionGroupResource

	if group == null:
		push_error("Could not load the condition group resource.")
		quit(1)
		return

	var named_correctly: bool = (
		group.id == &"can_strike"
	)

	print(
		"[condition-group] Group ID is preserved: ",
		named_correctly
	)

	var reference_matches: bool = (
		group.conditions.size() == 1
		and group.conditions[0] != null
		and group.conditions[0].resource_path
		== "res://Diagnostics/Fixtures/GameplayResources/actor_strength.tres"
	)

	print(
		"[condition-group] References the saved condition: ",
		reference_matches
	)

	if not reference_matches:
		quit(1)
		return

	var requirements: Array[Dictionary] = group.to_requirements()
	var existing: Dictionary = ExistingInteraction.definition()
	var expected: Array = existing["requirements"]

	var matches: bool = requirements == expected

	print(
		"[condition-group] Matches existing requirements: ",
		matches
	)

	requirements[0]["path"][0] = "diagnostic_only"

	var resource_unchanged: bool = (
		group.conditions[0].requirement["path"] == ["current"]
	)

	print(
		"[condition-group] Converted data is independent: ",
		resource_unchanged
	)

	var passed: bool = (
		named_correctly
		and reference_matches
		and matches
		and resource_unchanged
	)

	print("[condition-group] Checks passed: ", passed)
	quit(0 if passed else 1)