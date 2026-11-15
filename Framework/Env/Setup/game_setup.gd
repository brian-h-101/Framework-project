extends "res://Framework/Infrastructure/API/Runtime/game_setup.gd"

const EntityContent = preload(
	"res://Framework/Content/Authored/Entity/entities.gd"
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

var _startup: Dictionary = Startup.defaults()


func register_content(runtime: GameRuntime) -> void:
	EntityContent.define(runtime)

	for definition in ActionContent.definitions():
		runtime.define_action(definition)

	for definition in InteractionContent.definitions():
		runtime.define_interaction(definition)


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