extends "res://Framework/Infrastructure/API/Runtime/game_setup.gd"

const StartingContent = preload(
	"res://Framework/Env/Setup/starting_definitions.gd"
)
const ActionContent = preload(
	"res://Framework/Content/Behavior/Action/actions.gd"
)
const InteractionContent = preload(
	"res://Framework/Content/Behavior/Interaction/interactions.gd"
)
const AutomationContent = preload("res://Framework/Content/Behavior/Automation/automations.gd")
const Startup = preload(
	"res://Framework/Content/Configuration/Session/startup.tres"
)
const WorldTime = preload(
	"res://Framework/Content/Configuration/Session/world_time.tres"
)
const ExecutorDiscovery = preload(
	"res://Framework/Env/Setup/executor_discovery.gd"
)

var _startup: Dictionary = {}

func register_executors(runtime: GameRuntime) -> Dictionary:
	return ExecutorDiscovery.register_all(runtime)

func register_content(runtime: GameRuntime) -> Dictionary:
	var startup_result := Startup.read()
	if not startup_result["ok"]:
		return startup_result
	var clock_result := WorldTime.read()
	if not clock_result["ok"]:
		return clock_result
	_startup = startup_result["value"]

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
	var automation_result := AutomationContent.definitions()
	if not automation_result["ok"]:
		return automation_result

	for definition in definitions:
		var containers: Dictionary[StringName, Dictionary] = {}
		containers.assign(definition["containers"])

		runtime.define_attributes(
			StringName(definition["id"]),
			containers
		)

	for definition in actions:
		var registered := runtime.define_action(definition)
		if not registered["ok"]:
			var source: String = action_result["sources"][StringName(definition["id"])]
			return {"ok": false, "value": null,
				"error": "Action registration failed in %s: %s" % [source, registered["error"]]}

	for definition in interactions:
		var registered := runtime.define_interaction(definition)
		if not registered["ok"]:
			return {"ok": false, "value": null, "error": "Interaction registration failed in %s: %s" % [interaction_result["sources"][StringName(definition["id"])], registered["error"]]}

	for definition: Dictionary in automation_result["value"]:
		var registered := runtime.define_automation(definition)
		if not registered["ok"]:
			return {"ok": false, "value": null, "error": "Automation registration failed in %s: %s"
				% [automation_result["sources"][StringName(definition["id"])], registered["error"]]}

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
	var checked := Startup.read()
	if not checked["ok"]:
		return null
	var startup: Dictionary = checked["value"]
	return load(String(startup["initial_map"])) as PackedScene


func get_clock_definition() -> Dictionary:
	var result := WorldTime.read()
	return result["value"] if result["ok"] else {}
