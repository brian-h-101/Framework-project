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


func define_action(definition: Dictionary) -> void:
	_core.define_action(definition)


func define_interaction(definition: Dictionary) -> void:
	_core.define_interaction(definition)


func interact(
	interaction_id: StringName,
	actor_id: int,
	target_id: int
) -> Dictionary:
	return _core.interact(interaction_id, actor_id, target_id)


func spawn(
	definition_id: StringName,
	overrides: Dictionary[StringName, Dictionary] = {}
) -> int:
	return _core.spawn(definition_id, overrides)


func has_entity(entity_id: int) -> bool:
	return _core.has_entity(entity_id)


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


func _on_core_attribute_written(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName
) -> void:
	attribute_written.emit(entity_id, container_id, attribute_name)
