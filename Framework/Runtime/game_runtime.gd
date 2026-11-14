extends RefCounted

const EntityDefinition = preload(
	"res://Framework/Entity/entity_definition.gd"
)
const EntityRegistry = preload(
	"res://Framework/Entity/entity_registry.gd"
)
const AttributeConnector = preload(
	"res://Framework/Entity/attribute_connector.gd"
)

const EffectExecutor = preload(
	"res://Framework/Gameplay/effect_executor.gd"
)

const ActionExecutor = preload(
	"res://Framework/Gameplay/action_executor.gd"
)

const InteractionExecutor = preload(
	"res://Framework/Gameplay/interaction_executor.gd"
)

var _definitions: Dictionary[StringName, EntityDefinition] = {}
var _actions: Dictionary[StringName, Dictionary] = {}
var _interactions: Dictionary[StringName, Dictionary] = {}

var _registry := EntityRegistry.new()
var connector := AttributeConnector.new(_registry)
var _effect_executor := EffectExecutor.new(connector)
var _action_executor := ActionExecutor.new(
	connector, _effect_executor
)
var _interaction_executor := InteractionExecutor.new(
	connector, _action_executor
)

func define_attributes(
	definition_id: StringName,
	containers: Dictionary[StringName, Dictionary]
) -> void:
	var definition := EntityDefinition.new()

	definition.id = definition_id
	definition.containers = containers.duplicate(true)

	_definitions[definition.id] = definition

func define_action(definition: Dictionary) -> void:
	var action_id := StringName(definition["id"])
	_actions[action_id] = definition.duplicate(true)

func define_interaction(definition: Dictionary) -> void:
	var interaction_id := StringName(definition["id"])
	_interactions[interaction_id] = definition.duplicate(true)


func interact(
	interaction_id: StringName,
	actor_id: int,
	target_id: int
) -> Dictionary:
	if not _interactions.has(interaction_id):
		return {
			"ok": false,
			"value": null,
			"error": "Unknown interaction: %s" % interaction_id,
		}

	var definition: Dictionary = _interactions[interaction_id]
	var action_id := StringName(definition["action"])

	if not _actions.has(action_id):
		return {
			"ok": false,
			"value": null,
			"error": "Unknown action: %s" % action_id,
		}

	return _interaction_executor.execute(
		definition,
		_actions[action_id],
		actor_id,
		target_id
	)

func spawn(
	definition_id: StringName,
	overrides: Dictionary[StringName, Dictionary] = {}
) -> int:
	return _registry.create_entity(_definitions[definition_id], overrides)

func read_attribute(
	entity_id: int,
	container_id: StringName,
	path: Array
) -> Dictionary:
	var address := connector.make_reference(entity_id, container_id, path)
	return connector.read(address)

func write_attribute(
	entity_id: int,
	container_id: StringName,
	path: Array,
	value: Variant
) -> Dictionary:
	var address := connector.make_reference(entity_id, container_id, path)
	return connector.write(address, value)

func execute_effect(
	operation: StringName,
	entity_id: int,
	container_id: StringName,
	path: Array,
	value: Variant
) -> Dictionary:
	var address := connector.make_reference(
		entity_id, container_id, path
	)
	return _effect_executor.execute(operation, address, value)

func compare_attributes(
	left_entity_id: int,
	left_container_id: StringName,
	left_path: Array,
	operator: String,
	right_entity_id: int,
	right_container_id: StringName,
	right_path: Array
) -> Dictionary:
	var left := connector.make_reference(
		left_entity_id, left_container_id, left_path
	)
	var right := connector.make_reference(
		right_entity_id, right_container_id, right_path
	)

	return connector.compare(left, operator, right)

func print_entities() -> void:
	_registry.print_entities()
