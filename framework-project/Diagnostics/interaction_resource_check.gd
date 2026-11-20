extends SceneTree

const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/interaction_resource.gd"
)
const ExistingInteraction = preload(
	"res://Diagnostics/Fixtures/GameplayBaselines/strike.gd"
)


func _initialize() -> void:
	var interaction := ResourceLoader.load(
		"res://Framework/Content/Behavior/Interaction/strike.tres"
	) as InteractionResource

	if interaction == null:
		push_error("Could not load the interaction resource.")
		quit(1)
		return

	var action_linked: bool = (
		interaction.action != null
		and interaction.action.resource_path
		== "res://Framework/Content/Behavior/Action/change_health.tres"
	)

	var requirements_linked: bool = (
		interaction.requirements != null
		and interaction.requirements.resource_path
		== "res://Framework/Content/Behavior/Condition/can_strike.tres"
		and interaction.requirements.conditions.size() == 1
		and interaction.requirements.conditions[0] != null
		and interaction.requirements.conditions[0].resource_path
		== "res://Framework/Content/Behavior/Condition/actor_strength.tres"
	)

	print("[interaction-resource] Action reference resolves: ", action_linked)
	print("[interaction-resource] Group reference resolves: ", requirements_linked)

	if not action_linked or not requirements_linked:
		quit(1)
		return

	var definition: Dictionary = interaction.to_definition()
	var expected: Dictionary = ExistingInteraction.definition()
	var matches: bool = definition == expected

	print("[interaction-resource] Matches existing interaction: ", matches)

	if not matches:
		quit(1)
		return

	definition["arguments"][&"amount"] = -99
	definition["requirements"][0]["path"][0] = "diagnostic_only"

	var resources_unchanged: bool = (
		interaction.arguments[&"amount"] == -10
		and interaction.requirements.conditions[0].requirement["path"]
		== ["current"]
	)

	print(
		"[interaction-resource] Converted data is independent: ",
		resources_unchanged
	)

	var unconditional := InteractionResource.new()
	unconditional.id = &"diagnostic_unconditional"
	unconditional.action = interaction.action

	var unconditional_definition: Dictionary = unconditional.to_definition()
	var optional_group: bool = (
		unconditional_definition["requirements"].is_empty()
	)

	print(
		"[interaction-resource] Unassigned group gives no requirements: ",
		optional_group
	)

	var passed: bool = (
		matches
		and resources_unchanged
		and optional_group
	)

	print("[interaction-resource] Checks passed: ", passed)
	quit(0 if passed else 1)
