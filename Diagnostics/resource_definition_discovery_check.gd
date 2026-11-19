extends SceneTree

const ResourceDefinitionDiscovery = preload(
	"res://Framework/Env/Setup/resource_definition_discovery.gd"
)
const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/action_resource.gd"
)
const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/interaction_resource.gd"
)
const ExistingAction = preload(
	"res://Diagnostics/Fixtures/GameplayBaselines/change_health.gd"
)
const ExistingInteraction = preload(
	"res://Diagnostics/Fixtures/GameplayBaselines/strike.gd"
)

const FIXTURE_ROOT: String = (
	"res://Diagnostics/Fixtures/GameplayResources"
)


func _initialize() -> void:
	var actions: Dictionary = ResourceDefinitionDiscovery.definitions_in(
		FIXTURE_ROOT,
		ActionResource
	)

	var interactions: Dictionary = (
		ResourceDefinitionDiscovery.definitions_in(
			FIXTURE_ROOT,
			InteractionResource
		)
	)

	for result in [actions, interactions]:
		if not result["ok"]:
			push_error(String(result["error"]))
			quit(1)
			return

	var actions_match: bool = (
		actions["value"] == [ExistingAction.definition()]
	)

	var interactions_match: bool = (
		interactions["value"] == [ExistingInteraction.definition()]
	)

	var sources_match: bool = (
		actions["sources"].get(&"change_health", "")
		== FIXTURE_ROOT.path_join("change_health.tres")
		and interactions["sources"].get(&"strike", "")
		== FIXTURE_ROOT.path_join("strike.tres")
	)

	print(
		"[resource-discovery] Action catalogue matches: ",
		actions_match
	)
	print(
		"[resource-discovery] Interaction catalogue matches: ",
		interactions_match
	)
	print(
		"[resource-discovery] Source paths are preserved: ",
		sources_match
	)

	var passed: bool = (
		actions_match
		and interactions_match
		and sources_match
	)

	print("[resource-discovery] Checks passed: ", passed)
	quit(0 if passed else 1)
