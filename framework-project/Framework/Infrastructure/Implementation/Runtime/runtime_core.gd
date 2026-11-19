extends RefCounted

signal attribute_written(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName
)

const EntityDefinition = preload(
	"res://Framework/Infrastructure/Implementation/Entity/entity_definition.gd"
)
const EntityRegistry = preload(
	"res://Framework/Infrastructure/Implementation/Entity/entity_registry.gd"
)
const AttributeConnector = preload(
	"res://Framework/Infrastructure/Implementation/Entity/attribute_connector.gd"
)

const EffectExecutor = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/effect_executor.gd"
)

const ActionExecutor = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/action_executor.gd"
)

const InteractionExecutor = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/interaction_executor.gd"
)

const SessionClock = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/session_clock.gd"
)

var _definitions: Dictionary[StringName, EntityDefinition] = {}
var _entity_definition_ids: Dictionary[int, StringName] = {}
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
var _closed: bool = false
var _clock: SessionClock

func define_attributes(
	definition_id: StringName,
	containers: Dictionary[StringName, Dictionary]
) -> void:
	if _closed:
		return

	var definition := EntityDefinition.new()

	definition.id = definition_id
	definition.containers = containers.duplicate(true)

	_definitions[definition.id] = definition

func _init(clock_definition: Dictionary = {}) -> void:
	_registry.attribute_written.connect(_on_registry_attribute_written)

	if not clock_definition.is_empty():
		_clock = SessionClock.new(clock_definition)

func close() -> void:
	if _closed:
		return

	_closed = true

	if _registry.attribute_written.is_connected(_on_registry_attribute_written):
		_registry.attribute_written.disconnect(_on_registry_attribute_written)

	_definitions.clear()
	_entity_definition_ids.clear()
	_actions.clear()
	_interactions.clear()

	_interaction_executor = null
	_action_executor = null
	_effect_executor = null
	connector = null
	_registry = null
	_clock = null

func _on_registry_attribute_written(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName
) -> void:
	if _closed:
		return

	attribute_written.emit(entity_id, container_id, attribute_name)

func define_action(definition: Dictionary) -> void:
	if _closed:
		return

	var action_id := StringName(definition["id"])
	_actions[action_id] = definition.duplicate(true)

func define_interaction(definition: Dictionary) -> void:
	if _closed:
		return

	var interaction_id := StringName(definition["id"])
	_interactions[interaction_id] = definition.duplicate(true)


func interact(
	interaction_id: StringName,
	actor_id: int,
	target_id: int
) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")
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
	if not has_definition(definition_id):
		return 0

	var entity_id := _registry.create_entity(
		_definitions[definition_id], overrides
	)
	_entity_definition_ids[entity_id] = definition_id

	return entity_id


func has_definition(definition_id: StringName) -> bool:
	return not _closed and _definitions.has(definition_id)


func definition_id_for(entity_id: int) -> StringName:
	if _closed:
		return &""

	return _entity_definition_ids.get(entity_id, &"")


func has_entity(entity_id: int) -> bool:
	if _closed:
		return false

	return _registry.has_entity(entity_id)

func snapshot_entity(entity_id: int) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	var containers_result := _registry.snapshot_containers(entity_id)
	if not containers_result["ok"]:
		return containers_result

	return {
		"ok": true,
		"value": {
			"definition": definition_id_for(entity_id),
			"containers": containers_result["value"],
		},
		"error": "",
	}

func snapshot_entities(
	entity_ids: Dictionary[StringName, int]
) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	var records: Dictionary[StringName, Dictionary] = {}
	var seen_ids: Dictionary[int, StringName] = {}
	var entity_keys: Array = entity_ids.keys()
	entity_keys.sort()

	for entity_key in entity_keys:
		if entity_key == &"":
			return _failure("Entity key cannot be empty.")

		var entity_id: int = entity_ids[entity_key]
		if seen_ids.has(entity_id):
			return _failure(
				"Entity %s is assigned to both '%s' and '%s'."
				% [entity_id, seen_ids[entity_id], entity_key]
			)

		var captured := snapshot_entity(entity_id)
		if not captured["ok"]:
			return _failure(
				"Cannot capture entity '%s': %s"
				% [entity_key, captured["error"]]
			)

		records[entity_key] = captured["value"]
		seen_ids[entity_id] = entity_key

	return {
		"ok": true,
		"value": records,
		"error": "",
	}

func restore_entity(snapshot: Dictionary) -> Dictionary:
	var prepared := _prepare_entity_snapshot(snapshot)
	if not prepared["ok"]:
		return prepared

	var data: Dictionary = prepared["value"]
	var definition_id: StringName = data["definition"]
	var entity_id := _registry.create_from_containers(data["containers"])
	_entity_definition_ids[entity_id] = definition_id

	return {
		"ok": true,
		"value": entity_id,
		"error": "",
	}

func restore_entities(records: Dictionary) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	if not _entity_definition_ids.is_empty():
		return _failure(
			"Collection restoration requires a runtime with no entities."
		)

	var prepared_records: Dictionary[StringName, Dictionary] = {}

	for saved_key in records:
		if typeof(saved_key) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _failure("Session entity keys must be text.")

		var entity_key := StringName(String(saved_key))
		if entity_key == &"":
			return _failure("Entity key cannot be empty.")

		if prepared_records.has(entity_key):
			return _failure("Duplicate entity key: %s" % entity_key)

		if not records[saved_key] is Dictionary:
			return _failure(
				"Entity record must be a dictionary: %s" % entity_key
			)

		var record: Dictionary = records[saved_key]
		var prepared := _prepare_entity_snapshot(record)
		if not prepared["ok"]:
			return _failure(
				"Cannot restore entity '%s': %s"
				% [entity_key, prepared["error"]]
			)

		prepared_records[entity_key] = prepared["value"]

	var entity_keys: Array = prepared_records.keys()
	entity_keys.sort()

	var entity_ids: Dictionary[StringName, int] = {}
	for entity_key in entity_keys:
		var data: Dictionary = prepared_records[entity_key]
		var definition_id: StringName = data["definition"]
		var entity_id := _registry.create_from_containers(data["containers"])

		_entity_definition_ids[entity_id] = definition_id
		entity_ids[entity_key] = entity_id

	return {
		"ok": true,
		"value": entity_ids,
		"error": "",
	}

func _prepare_entity_snapshot(snapshot: Dictionary) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	var saved_definition: Variant = snapshot.get("definition")
	if typeof(saved_definition) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure("Snapshot requires a text definition ID.")

	var definition_id := StringName(String(saved_definition))
	if not has_definition(definition_id):
		return _failure("Unknown entity definition: %s" % definition_id)

	var saved_containers: Variant = snapshot.get("containers")
	if not saved_containers is Dictionary:
		return _failure("Snapshot requires a containers dictionary.")

	var containers: Dictionary[StringName, Dictionary] = {}
	for container_id in saved_containers:
		if typeof(container_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _failure("Snapshot container IDs must be text.")

		if not saved_containers[container_id] is Dictionary:
			return _failure(
				"Snapshot container '%s' must hold a dictionary."
				% container_id
			)

		var attributes: Dictionary = saved_containers[container_id]
		for attribute_name in attributes:
			if typeof(attribute_name) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return _failure(
					"Snapshot attribute names must be text: %s"
					% container_id
				)

		containers[StringName(String(container_id))] = attributes

	return {
		"ok": true,
		"value": {
			"definition": definition_id,
			"containers": containers,
		},
		"error": "",
	}

func add_container(
	entity_id: int,
	container_id: StringName,
	attributes: Dictionary = {}
) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	if not _registry.has_entity(entity_id):
		return _failure("Unknown entity: %s" % entity_id)

	if _registry.has_container(entity_id, container_id):
		return _failure(
			"Entity %s already has container: %s"
			% [entity_id, container_id]
		)

	if not _registry.add_container(entity_id, container_id, attributes):
		return _failure("The container could not be added.")

	return {
		"ok": true,
		"value": true,
		"error": "",
	}

func add_attribute(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName,
	value: Variant
) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	if not _registry.has_entity(entity_id):
		return _failure("Unknown entity: %s" % entity_id)

	if not _registry.has_container(entity_id, container_id):
		return _failure(
			"Entity %s has no container: %s"
			% [entity_id, container_id]
		)

	if _registry.has_value(entity_id, container_id, attribute_name):
		return _failure(
			"Entity %s already has attribute: %s/%s"
			% [entity_id, container_id, attribute_name]
		)

	if not _registry.add_attribute(
		entity_id,
		container_id,
		attribute_name,
		value
	):
		return _failure("The attribute could not be added.")

	return {
		"ok": true,
		"value": true,
		"error": "",
	}

func read_attribute(
	entity_id: int,
	container_id: StringName,
	path: Array
) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")
	var address := connector.make_reference(entity_id, container_id, path)
	return connector.read(address)

func write_attribute(
	entity_id: int,
	container_id: StringName,
	path: Array,
	value: Variant
) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")
	var address := connector.make_reference(entity_id, container_id, path)
	return connector.write(address, value)

func execute_effect(
	operation: StringName,
	entity_id: int,
	container_id: StringName,
	path: Array,
	value: Variant
) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")
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
	if _closed:
		return _failure("Game runtime is closed.")
	var left := connector.make_reference(
		left_entity_id, left_container_id, left_path
	)
	var right := connector.make_reference(
		right_entity_id, right_container_id, right_path
	)

	return connector.compare(left, operator, right)

func print_entities() -> void:
	if _closed:
		return

	_registry.print_entities()

func read_time() -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	if _clock == null:
		return _failure("Session clock is not configured.")

	return {
		"ok": true,
		"value": {
			"day": _clock.get_day_number(),
			"hour": _clock.get_hour(),
			"day_fraction": _clock.get_day_fraction(),
		},
		"error": "",
	}


func advance_time(delta_seconds: float) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	if _clock == null:
		return _failure("Session clock is not configured.")

	if not is_finite(delta_seconds) or delta_seconds < 0.0:
		return _failure("Time step must be finite and at least zero.")

	_clock.advance(delta_seconds)
	return read_time()

func snapshot_time() -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	if _clock == null:
		return {
			"ok": true,
			"value": null,
			"error": "",
		}

	return {
		"ok": true,
		"value": _clock.snapshot_state(),
		"error": "",
	}


func restore_time(snapshot: Dictionary) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	if _clock == null:
		return _failure("Session clock is not configured.")

	var restored := _clock.restore_state(snapshot)
	if not restored["ok"]:
		return restored

	return read_time()

func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}
