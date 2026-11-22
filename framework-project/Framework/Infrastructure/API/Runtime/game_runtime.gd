extends RefCounted

signal attribute_written(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName
)

const RuntimeCore = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd"
)

var _core: RuntimeCore


func _init(core: RuntimeCore) -> void:
	_core = core
	_core.attribute_written.connect(_on_core_attribute_written)

func close() -> void:
	if _core.attribute_written.is_connected(_on_core_attribute_written):
		_core.attribute_written.disconnect(_on_core_attribute_written)

	_core.close()

func define_attributes(
	definition_id: StringName,
	containers: Dictionary[StringName, Dictionary]
) -> void:
	_core.define_attributes(definition_id, containers)


func register_executor(behavior_id: StringName, executor: Variant) -> Dictionary:
	return _core.register_executor(behavior_id, executor)


func has_executor(behavior_id: StringName) -> bool:
	return _core.has_executor(behavior_id)


func get_executor_ids() -> Array[StringName]:
	return _core.get_executor_ids()


func define_action(definition: Dictionary) -> Dictionary:
	return _core.define_action(definition)


func executor_catalogue() -> Dictionary:
	return _core.executor_catalogue()


func define_interaction(definition: Dictionary) -> Dictionary:
	return _core.define_interaction(definition)


func define_automation(definition: Dictionary) -> Dictionary:
	return _core.define_automation(definition)


func read_automation(id: StringName) -> Dictionary:
	return _core.read_automation(id)


func bind_automation(entity_id: int, id: StringName, enabled: bool = true) -> Dictionary:
	return _core.bind_automation(entity_id, id, enabled)


func automation_bindings(entity_id: int) -> Dictionary:
	return _core.automation_bindings(entity_id)


func set_automation_enabled(entity_id: int, id: StringName, enabled: bool) -> Dictionary:
	return _core.set_automation_enabled(entity_id, id, enabled)


func unbind_automation(entity_id: int, id: StringName) -> Dictionary:
	return _core.unbind_automation(entity_id, id)


func advance_automations(delta: float, resolve_target: Callable) -> Dictionary:
	return _core.advance_automations(delta, resolve_target)


func snapshot_automations(entity_ids: Dictionary[StringName, int]) -> Dictionary:
	return _core.snapshot_automations(entity_ids)


func restore_automations(records: Variant, entity_ids: Dictionary[StringName, int]) -> Dictionary:
	return _core.restore_automations(records, entity_ids)


func interact(
	interaction_id: StringName,
	actor_id: int,
	target_id: int
) -> Dictionary:
	return _core.interact(interaction_id, actor_id, target_id)

func execute_action(
	action_id: StringName,
	actor_id: int,
	target_id: int,
	arguments: Dictionary = {}
) -> Dictionary:
	return _core.execute_action(
		action_id,
		actor_id,
		target_id,
		arguments
	)

func spawn(
	definition_id: StringName,
	overrides: Dictionary[StringName, Dictionary] = {}
) -> int:
	return _core.spawn(definition_id, overrides)


func has_definition(definition_id: StringName) -> bool:
	return _core.has_definition(definition_id)


func definition_id_for(entity_id: int) -> StringName:
	return _core.definition_id_for(entity_id)


func has_entity(entity_id: int) -> bool:
	return _core.has_entity(entity_id)

func snapshot_entity(entity_id: int) -> Dictionary:
	return _core.snapshot_entity(entity_id)

func snapshot_entities(
	entity_ids: Dictionary[StringName, int]
) -> Dictionary:
	return _core.snapshot_entities(entity_ids)

func restore_entity(snapshot: Dictionary) -> Dictionary:
	return _core.restore_entity(snapshot)

func restore_entities(records: Dictionary) -> Dictionary:
	return _core.restore_entities(records)

func add_container(
	entity_id: int,
	container_id: StringName,
	attributes: Dictionary = {}
) -> Dictionary:
	return _core.add_container(entity_id, container_id, attributes)

func add_attribute(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName,
	value: Variant
) -> Dictionary:
	return _core.add_attribute(entity_id, container_id, attribute_name, value)

func read_attribute(
	entity_id: int,
	container_id: StringName,
	path: Array
) -> Dictionary:
	return _core.read_attribute(entity_id, container_id, path)


func write_attribute(
	entity_id: int,
	container_id: StringName,
	path: Array,
	value: Variant
) -> Dictionary:
	return _core.write_attribute(entity_id, container_id, path, value)


func execute_effect(
	operation: StringName,
	entity_id: int,
	container_id: StringName,
	path: Array,
	value: Variant
) -> Dictionary:
	return _core.execute_effect(operation, entity_id, container_id, path, value)


func compare_attributes(
	left_entity_id: int,
	left_container_id: StringName,
	left_path: Array,
	operator: String,
	right_entity_id: int,
	right_container_id: StringName,
	right_path: Array
) -> Dictionary:
	return _core.compare_attributes(
		left_entity_id, left_container_id, left_path,
		operator,
		right_entity_id, right_container_id, right_path
	)


func print_entities() -> void:
	_core.print_entities()


func read_time() -> Dictionary:
	return _core.read_time()


func advance_time(delta_seconds: float) -> Dictionary:
	return _core.advance_time(delta_seconds)

func snapshot_time() -> Dictionary:
	return _core.snapshot_time()


func restore_time(snapshot: Dictionary) -> Dictionary:
	return _core.restore_time(snapshot)

func _on_core_attribute_written(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName
) -> void:
	attribute_written.emit(entity_id, container_id, attribute_name)

func define_behavior(definition: Dictionary) -> Dictionary:
	return _core.define_behavior(definition)

func read_behavior(id: StringName) -> Dictionary:
	return _core.read_behavior(id)

func bind_behavior(entity_id: int, id: StringName, enabled: bool = true) -> Dictionary:
	return _core.bind_behavior(entity_id, id, enabled)

func behavior_bindings(entity_id: int) -> Dictionary:
	return _core.behavior_bindings(entity_id)

func set_behavior_enabled(entity_id: int, id: StringName, enabled: bool) -> Dictionary:
	return _core.set_behavior_enabled(entity_id, id, enabled)

func unbind_behavior(entity_id: int, id: StringName) -> Dictionary:
	return _core.unbind_behavior(entity_id, id)

func select_target(actor: int, target: int) -> Dictionary:
	return _core.select_target(actor, target)

func selected_target(actor: int) -> int:
	return _core.selected_target(actor)

func invoke_behavior(id: StringName, actor: int, resolve_target: Callable,
		step_id: StringName = &"", step_arguments: Dictionary = {}) -> Dictionary:
	return _core.invoke_behavior(id, actor, resolve_target, step_id, step_arguments)

func emit_behavior_event(actor: int, event_id: StringName, resolve_target: Callable) -> Dictionary:
	return _core.emit_behavior_event(actor, event_id, resolve_target)

func advance_behaviors(delta: float, resolve_target: Callable) -> Dictionary:
	return _core.advance_behaviors(delta, resolve_target)

func snapshot_behaviors(entity_ids: Dictionary[StringName, int]) -> Dictionary:
	return _core.snapshot_behaviors(entity_ids)

func restore_behaviors(records: Variant, entity_ids: Dictionary[StringName, int]) -> Dictionary:
	return _core.restore_behaviors(records, entity_ids)
