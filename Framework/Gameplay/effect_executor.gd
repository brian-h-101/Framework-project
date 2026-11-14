extends RefCounted

const AttributeConnector = preload(
	"res://Framework/Entity/attribute_connector.gd"
)
const AttributeReference = preload(
	"res://Framework/Entity/attribute_reference.gd"
)

var _connector: AttributeConnector


func _init(connector: AttributeConnector) -> void:
	_connector = connector


func execute(
	operation: StringName,
	address: AttributeReference,
	value: Variant
) -> Dictionary:
	match operation:
		&"set":
			return _connector.write(address, value)

		&"add":
			var current := _connector.read(address)
			if not current.ok:
				return current

			if (
				typeof(current.value) not in [TYPE_INT, TYPE_FLOAT]
				or typeof(value) not in [TYPE_INT, TYPE_FLOAT]
			):
				return _failure("The add operation requires two numbers.")

			var updated: Variant = current.value + value

			if typeof(updated) == TYPE_FLOAT and not is_finite(updated):
				return _failure(
					"The add operation must produce a finite number."
				)

			return _connector.write(address, updated)

		_:
			return _failure("Unknown effect operation: %s" % operation)


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}