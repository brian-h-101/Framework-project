extends RefCounted

const EntityRegistry = preload(
	"res://Framework/Entity/entity_registry.gd"
)
const AttributeReference = preload(
	"res://Framework/Entity/attribute_reference.gd"
)

var _registry: EntityRegistry


func _init(registry: EntityRegistry) -> void:
	_registry = registry


func make_reference(
	entity_id: int,
	container_id: StringName,
	path: Array
) -> AttributeReference:
	return AttributeReference.new(entity_id, container_id, path)


func read(address: AttributeReference) -> Dictionary:
	if _registry == null:
		return _failure("Connector has no registry.")
	if address == null:
		return _failure("Attribute reference is null.")
	if address.path.is_empty():
		return _failure("Attribute path is empty.")

	var first: Variant = address.path[0]
	if typeof(first) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure("The first path segment must name an attribute.")
	var attribute_name := StringName(String(first))

	if not _registry.has_value(
		address.entity_id, address.container_id, attribute_name
	):
		return _failure("Missing entity, container, or attribute: %s/%s/%s" % [
			address.entity_id, address.container_id, attribute_name
		])

	# The registry returns copied collections; traversal stays within that copy.
	var value: Variant = _registry.get_value(
		address.entity_id, address.container_id, attribute_name
	)
	for segment in address.path.slice(1):
		if value is Dictionary:
			if typeof(segment) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return _failure("Dictionary path segments must be strings.")
			var key := String(segment)
			if not value.has(key):
				return _failure("Missing dictionary key: %s" % key)
			value = value[key]
		elif value is Array:
			if typeof(segment) != TYPE_INT:
				return _failure("Array path segments must be integers.")
			var index: int = segment
			if index < 0 or index >= value.size():
				return _failure("Array index out of bounds: %s" % index)
			value = value[index]
		else:
			return _failure("The path continues beyond a scalar value.")

	return {"ok": true, "value": value, "error": ""}

func write(address: AttributeReference, value: Variant) -> Dictionary:
	var existing := read(address)
	if not existing.ok:
		return existing

	var attribute_name := StringName(String(address.path[0]))
	var replacement: Variant = value

	if address.path.size() > 1:
		replacement = _registry.get_value(
			address.entity_id, address.container_id, attribute_name
		)

		var parent: Variant = replacement
		for segment in address.path.slice(1, address.path.size() - 1):
			if parent is Dictionary:
				parent = parent[String(segment)]
			else:
				parent = parent[segment]

		var last: Variant = address.path[address.path.size() - 1]
		if parent is Dictionary:
			parent[String(last)] = value
		else:
			parent[last] = value

	if not _registry.set_value(
		address.entity_id,
		address.container_id,
		attribute_name,
		replacement
	):
		return _failure("The attribute could not be updated.")

	return read(address)


func compare(
	left: AttributeReference,
	operator: String,
	right: Variant
) -> Dictionary:
	var left_result := read(left)
	if not left_result.ok:
		return _failure("Left operand: %s" % left_result.error)

	var a: Variant = left_result.value
	var b: Variant = right

	if right is AttributeReference:
		var right_result := read(right)
		if not right_result.ok:
			return _failure("Right operand: %s" % right_result.error)

		b = right_result.value

	if (
		typeof(a) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(b) not in [TYPE_INT, TYPE_FLOAT]
	):
		return _failure("Numeric comparison requires two numbers.")

	if typeof(a) == TYPE_FLOAT and not is_finite(a):
		return _failure("Left operand must be finite.")

	if typeof(b) == TYPE_FLOAT and not is_finite(b):
		return _failure("Right operand must be finite.")

	var comparison: bool = false
	match operator:
		"==":
			comparison = a == b
		"!=":
			comparison = a != b
		">":
			comparison = a > b
		">=":
			comparison = a >= b
		"<":
			comparison = a < b
		"<=":
			comparison = a <= b
		_:
			return _failure("Unsupported comparison operator: %s" % operator)

	return {"ok": true, "value": comparison, "error": ""}
	
func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
