extends "res://Framework/Infrastructure/API/Runtime/game_setup.gd"

const StartingContent = preload(
	"res://Framework/Content/Authored/starting_definitions.gd"
)
const ActionContent = preload(
	"res://Framework/Content/Action/actions.gd"
)
const InteractionContent = preload(
	"res://Framework/Content/Interaction/interactions.gd"
)
const Startup = preload(
	"res://Framework/Content/Configuration/Session/startup.gd"
)
const WorldTime = preload(
	"res://Framework/Content/Configuration/Session/world_time.gd"
)

var _startup: Dictionary = Startup.defaults()


func register_content(runtime: GameRuntime) -> Dictionary:
	var starting_result := StartingContent.definitions()
	if not starting_result["ok"]:
		return starting_result

	var action_result := ActionContent.definitions()
	if not action_result["ok"]:
		return action_result

	var interaction_result := InteractionContent.definitions()
	if not interaction_result["ok"]:
		return interaction_result

	var definitions: Array[Dictionary] = starting_result["value"]
	var actions: Array[Dictionary] = action_result["value"]
	var interactions: Array[Dictionary] = interaction_result["value"]

	for definition in definitions:
		var containers: Dictionary[StringName, Dictionary] = {}
		containers.assign(definition["containers"])

		runtime.define_attributes(
			StringName(definition["id"]),
			containers
		)

	for definition in actions:
		runtime.define_action(definition)

	for definition in interactions:
		runtime.define_interaction(definition)

	return {"ok": true, "value": true, "error": ""}


func create_entities(
	runtime: GameRuntime
) -> Dictionary[StringName, int]:
	var entity_ids: Dictionary[StringName, int] = {}
	var specifications: Dictionary = _startup["entities"]

	for entity_name in specifications:
		var specification: Dictionary = specifications[entity_name]
		var overrides: Dictionary[StringName, Dictionary] = {}
		overrides.assign(specification.get("overrides", {}))

		entity_ids[StringName(entity_name)] = runtime.spawn(
			StringName(specification["definition"]),
			overrides
		)

	return entity_ids


func get_initial_map() -> PackedScene:
	return load(String(_startup["initial_map"])) as PackedScene


func get_clock_definition() -> Dictionary:
	return WorldTime.defaults()
