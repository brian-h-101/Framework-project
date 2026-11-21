extends RefCounted

const RegistryCore = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/executor_registry_core.gd"
)

var _core := RegistryCore.new()


func register_executor(
	behavior_id: StringName,
	executor: Variant
) -> Dictionary:
	return _core.register_executor(behavior_id, executor)


func resolve(behavior_id: StringName) -> Dictionary:
	return _core.resolve(behavior_id)


func describe(behavior_id: StringName) -> Dictionary:
	return _core.describe(behavior_id)


func catalogue() -> Dictionary:
	return _core.catalogue()


func has_executor(behavior_id: StringName) -> bool:
	return _core.has_executor(behavior_id)


func get_ids() -> Array[StringName]:
	return _core.get_ids()


func close() -> void:
	_core.close()
