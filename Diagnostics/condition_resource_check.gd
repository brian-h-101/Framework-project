extends SceneTree

const ConditionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/condition_resource.gd"
)
const ExistingInteraction = preload(
	"res://Diagnostics/Fixtures/GameplayBaselines/strike.gd"
)


func _initialize() -> void:
	var condition := ResourceLoader.load(
		"res://Diagnostics/Fixtures/GameplayResources/actor_strength.tres"
	) as ConditionResource

	if condition == null:
		push_error("Could not load the condition resource.")
		quit(1)
		return

	var named_correctly: bool = (
		condition.id == &"actor_strength"
	)

	var definition: Dictionary = condition.to_definition()
	var existing: Dictionary = ExistingInteraction.definition()
	var expected: Dictionary = existing["requirements"][0]

	var matches: bool = definition == expected

	print(
		"[condition-resource] Condition ID is preserved: ",
		named_correctly
	)
	print(
		"[condition-resource] Matches existing requirement: ",
		matches
	)

	definition["path"][0] = "diagnostic_only"

	var resource_unchanged: bool = (
		condition.requirement["path"] == ["current"]
	)

	print(
		"[condition-resource] Converted data is independent: ",
		resource_unchanged
	)

	var passed: bool = (
		named_correctly
		and matches
		and resource_unchanged
	)

	print("[condition-resource] Checks passed: ", passed)
	quit(0 if passed else 1)