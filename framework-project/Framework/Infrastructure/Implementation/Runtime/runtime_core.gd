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
	"res://Framework/Infrastructure/Implementation/Gameplay/Execution/effect_executor.gd"
)

const ActionExecutor = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/Execution/action_executor.gd"
)
const ExecutorRegistry = preload(
	"res://Framework/Infrastructure/API/Gameplay/executor_registry.gd"
)
const ExecutionContext = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/execution_context.gd"
)
const ExecutionContextCore = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/Execution/execution_context_core.gd"
)
const AttributeEffectsExecutor = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/Executors/attribute_effects_executor.gd"
)
const ExecutorContract = preload("res://Framework/Infrastructure/Implementation/Gameplay/Registry/executor_contract.gd")

const InteractionExecutor = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/Execution/interaction_executor.gd"
)

const SessionClock = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/session_clock.gd"
)
const AutomationSystem = preload("res://Framework/Infrastructure/Implementation/Gameplay/Automation/automation_system.gd")

var _definitions: Dictionary[StringName, EntityDefinition] = {}
var _entity_definition_ids: Dictionary[int, StringName] = {}
var _actions: Dictionary[StringName, Dictionary] = {}
var _interactions: Dictionary[StringName, Dictionary] = {}
const BehaviorSystem = preload("res://Framework/Infrastructure/Implementation/Gameplay/Behavior/behavior_system.gd")
var _behaviors := BehaviorSystem.new()
var _automations := AutomationSystem.new()

var _registry := EntityRegistry.new()
var connector := AttributeConnector.new(_registry)
var _effect_executor := EffectExecutor.new(connector)
var _executor_registry := ExecutorRegistry.new()
var _execution_context := ExecutionContext.new(
	ExecutionContextCore.new(connector, _effect_executor)
)
var _action_executor := ActionExecutor.new(
	_executor_registry, _execution_context
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
	var registered := _executor_registry.register_executor(
		&"attribute_effects", AttributeEffectsExecutor.new()
	)
	if not registered["ok"]:
		push_error(String(registered["error"]))
		close()
		return

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
	_automations.close()
	_behaviors.close()
	_execution_context.close()
	_executor_registry.close()

	_interaction_executor = null
	_action_executor = null
	_execution_context = null
	_executor_registry = null
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

func register_executor(behavior_id: StringName, executor: Variant) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")
	return _executor_registry.register_executor(behavior_id, executor)


func has_executor(behavior_id: StringName) -> bool:
	return not _closed and _executor_registry.has_executor(behavior_id)


func get_executor_ids() -> Array[StringName]:
	return [] if _closed else _executor_registry.get_ids()


func executor_catalogue() -> Dictionary:
	return _failure("Game runtime is closed.") if _closed else _executor_registry.catalogue()


func define_action(definition: Dictionary) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")
	var id_value: Variant = definition.get("id")
	if typeof(id_value) not in [TYPE_STRING, TYPE_STRING_NAME] or String(id_value).strip_edges().is_empty():
		return _failure("Action requires a nonempty text ID.")
	var action_id := StringName(id_value)
	var behavior: Variant = definition.get("behavior_id")
	if typeof(behavior) not in [TYPE_STRING, TYPE_STRING_NAME] or String(behavior).strip_edges().is_empty():
		return _failure("Action '%s' requires a nonempty text behavior_id." % action_id)
	var behavior_id := StringName(behavior)
	var resolved := _executor_registry.resolve(behavior_id)
	if not resolved["ok"]:
		return _failure("Action '%s': %s" % [action_id, resolved["error"]])
	var description := _executor_registry.describe(behavior_id)
	var checked := ExecutorContract.argument_specs(description["value"], definition)
	if not checked["ok"]:
		return _failure("Action '%s': %s" % [action_id, checked["error"]])
	for interaction: Dictionary in _interactions.values():
		if StringName(interaction["action"]) == action_id:
			checked = ExecutorContract.validate_arguments(description["value"], definition, interaction.get("arguments", {}))
			if not checked["ok"]:
				return _failure("Interaction '%s': %s" % [interaction["id"], checked["error"]])

	var stored := definition.duplicate(true)
	stored["id"] = action_id
	stored["behavior_id"] = behavior_id
	_actions[action_id] = stored
	return {"ok": true, "value": true, "error": ""}

func define_interaction(definition: Dictionary) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")
	if typeof(definition.get("id")) not in [TYPE_STRING, TYPE_STRING_NAME] or String(definition["id"]).strip_edges().is_empty():
		return _failure("Interaction requires a nonempty text ID.")
	if typeof(definition.get("action")) not in [TYPE_STRING, TYPE_STRING_NAME] or not _actions.has(StringName(definition["action"])):
		return _failure("Interaction requires a registered action.")
	if not definition.get("arguments", {}) is Dictionary:
		return _failure("Interaction arguments must be a dictionary.")
	var action: Dictionary = _actions[StringName(definition["action"])]
	var description := _executor_registry.describe(action["behavior_id"])
	var checked := ExecutorContract.validate_arguments(description["value"], action, definition.get("arguments", {}))
	if not checked["ok"]:
		return _failure("Interaction '%s': %s" % [definition["id"], checked["error"]])
	var interaction_id := StringName(definition["id"])
	_interactions[interaction_id] = definition.duplicate(true)
	return {"ok": true, "value": true, "error": ""}


func define_automation(definition: Dictionary) -> Dictionary:
	return _automations.define_automation(definition, func(id: StringName) -> bool: return _interactions.has(id))


func read_automation(id: StringName) -> Dictionary:
	return _automations.read_automation(id)


func bind_automation(entity_id: int, id: StringName, enabled: bool = true) -> Dictionary:
	if not has_entity(entity_id):
		return _failure("Game runtime is closed or entity is unknown.")
	return _automations.bind_automation(entity_id, id, enabled)


func automation_bindings(entity_id: int) -> Dictionary:
	if not has_entity(entity_id):
		return _failure("Game runtime is closed or entity is unknown.")
	return _automations.read_bindings(entity_id)


func set_automation_enabled(entity_id: int, id: StringName, enabled: bool) -> Dictionary:
	return _automations.set_enabled(entity_id, id, enabled) if has_entity(entity_id) else _failure("Game runtime is closed or entity is unknown.")


func unbind_automation(entity_id: int, id: StringName) -> Dictionary:
	return _automations.unbind_automation(entity_id, id) if has_entity(entity_id) else _failure("Game runtime is closed or entity is unknown.")


func advance_automations(delta: float, resolve_target: Callable) -> Dictionary:
	return _automations.advance(delta, resolve_target, interact)


func snapshot_automations(entity_ids: Dictionary[StringName, int]) -> Dictionary:
	var checked := snapshot_entities(entity_ids)
	return _automations.snapshot(entity_ids) if checked["ok"] else checked


func restore_automations(records: Variant, entity_ids: Dictionary[StringName, int]) -> Dictionary:
	var checked := snapshot_entities(entity_ids)
	return _automations.restore(records, entity_ids) if checked["ok"] else checked


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

func execute_action(
	action_id: StringName,
	actor_id: int,
	target_id: int,
	arguments: Dictionary = {}
) -> Dictionary:
	if _closed:
		return _failure("Game runtime is closed.")

	if String(action_id).strip_edges().is_empty():
		return _failure("Action ID cannot be empty.")

	if not _actions.has(action_id):
		return _failure("Unknown action: %s" % action_id)

	if not _registry.has_entity(actor_id):
		return _failure("Unknown actor entity: %s" % actor_id)

	if not _registry.has_entity(target_id):
		return _failure("Unknown target entity: %s" % target_id)

	var bindings := {
		&"actor": actor_id,
		&"target": target_id,
	}

	return _action_executor.execute(
		_actions[action_id],
		bindings,
		arguments
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

func define_behavior(definition: Dictionary) -> Dictionary:
	return _behaviors.define_behavior(definition, _describe_behavior_executor)

func _describe_behavior_executor(id: StringName) -> Dictionary:
	return _failure("Game runtime is closed.") if _closed else _executor_registry.describe(id)

func read_behavior(id: StringName) -> Dictionary:
	return _behaviors.read_behavior(id)

func bind_behavior(entity_id: int, id: StringName, enabled: bool = true) -> Dictionary:
	return _behaviors.bind(entity_id, id, enabled) if has_entity(entity_id) else _failure("Unknown Behavior entity.")

func behavior_bindings(entity_id: int) -> Dictionary:
	return _behaviors.bindings(entity_id) if has_entity(entity_id) else _failure("Unknown Behavior entity.")

func set_behavior_enabled(entity_id: int, id: StringName, enabled: bool) -> Dictionary:
	return _behaviors.set_enabled(entity_id, id, enabled) if has_entity(entity_id) else _failure("Unknown Behavior entity.")

func unbind_behavior(entity_id: int, id: StringName) -> Dictionary:
	return _behaviors.unbind(entity_id, id) if has_entity(entity_id) else _failure("Unknown Behavior entity.")

func select_target(actor: int, target: int) -> Dictionary:
	return _behaviors.select_target(actor, target) if has_entity(actor) and (target == 0 or has_entity(target)) else _failure("Unknown selection entity.")

func selected_target(actor: int) -> int:
	return _behaviors.selected_target(actor)

func invoke_behavior(id: StringName, actor: int, resolve_target: Callable,
		step_id: StringName = &"", step_arguments: Dictionary = {}) -> Dictionary:
	return _behaviors.invoke(id, actor, resolve_target, has_entity, connector,
		_action_executor, step_id, step_arguments)

func emit_behavior_event(actor: int, event_id: StringName, resolve_target: Callable) -> Dictionary:
	if not has_entity(actor):
		return _failure("Unknown Behavior actor.")
	return _behaviors.emit_event(actor, event_id, func(id: StringName, entity: int) -> Dictionary: return invoke_behavior(id, entity, resolve_target))

func advance_behaviors(delta: float, resolve_target: Callable) -> Dictionary:
	return _behaviors.advance(delta, func(id: StringName, actor: int) -> Dictionary: return invoke_behavior(id, actor, resolve_target))

func snapshot_behaviors(entity_ids: Dictionary[StringName, int]) -> Dictionary:
	var checked := snapshot_entities(entity_ids)
	return _behaviors.snapshot(entity_ids) if checked["ok"] else checked

func restore_behaviors(records: Variant, entity_ids: Dictionary[StringName, int]) -> Dictionary:
	var checked := snapshot_entities(entity_ids)
	return _behaviors.restore(records, entity_ids) if checked["ok"] else checked
