extends RefCounted

const ContextCore = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/execution_context_core.gd"
)

var _core: ContextCore


func _init(core: ContextCore = null) -> void:
	_core = core if core != null else ContextCore.new()


func read_attribute(entity_id: int, container_id: StringName, path: Array) -> Dictionary:
	return _core.read_attribute(entity_id, container_id, path)


func write_attribute(entity_id: int, container_id: StringName, path: Array, value: Variant) -> Dictionary:
	return _core.write_attribute(entity_id, container_id, path, value)


func execute_effect(operation: StringName, entity_id: int, container_id: StringName, path: Array, value: Variant) -> Dictionary:
	return _core.execute_effect(operation, entity_id, container_id, path, value)


func is_closed() -> bool:
	return _core.is_closed()


func close() -> void:
	_core.close()
