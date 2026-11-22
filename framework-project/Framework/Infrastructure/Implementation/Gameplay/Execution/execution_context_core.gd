extends RefCounted

const AttributeConnector = preload(
	"res://Framework/Infrastructure/Implementation/Entity/attribute_connector.gd"
)
const EffectExecutor = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/Execution/effect_executor.gd"
)

var _connector: AttributeConnector
var _effects: EffectExecutor
var _closed: bool = false


func _init(
	connector: AttributeConnector = null,
	effects: EffectExecutor = null
) -> void:
	_connector = connector
	_effects = effects


func read_attribute(entity_id: int, container_id: StringName, path: Array) -> Dictionary:
	var error := _service_error()
	if not error.is_empty():
		return _failure(error)
	return _connector.read(_connector.make_reference(entity_id, container_id, path))


func write_attribute(entity_id: int, container_id: StringName, path: Array, value: Variant) -> Dictionary:
	var error := _service_error()
	if not error.is_empty():
		return _failure(error)
	return _connector.write(_connector.make_reference(entity_id, container_id, path), value)


func execute_effect(operation: StringName, entity_id: int, container_id: StringName, path: Array, value: Variant) -> Dictionary:
	var error := _service_error()
	if not error.is_empty():
		return _failure(error)
	if _effects == null:
		return _failure("Execution context has no effect executor.")
	return _effects.execute(operation, _connector.make_reference(entity_id, container_id, path), value)


func is_closed() -> bool:
	return _closed


func close() -> void:
	if _closed:
		return
	_closed = true
	_connector = null
	_effects = null


func _service_error() -> String:
	if _closed:
		return "Execution context is closed."
	return "Execution context has no attribute connector." if _connector == null else ""


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
