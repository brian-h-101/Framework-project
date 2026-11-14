extends RefCounted

const EntityDefinition = preload(
	"res://Framework/Entity/entity_definition.gd"
)

var _next_id: int = 1
var _entities: Dictionary[int, Dictionary] = {}


func create_entity(
	definition: EntityDefinition,
	overrides: Dictionary[StringName, Dictionary] = {}
) -> int:
	# Definitions remain reusable; each entity owns its nested data.
	var data: Dictionary[StringName, Dictionary] = (
		definition.containers.duplicate(true)
	)
	for container_id in overrides:
		if not data.has(container_id):
			data[container_id] = {}
		data[container_id].merge(overrides[container_id].duplicate(true), true)

	var entity_id := _next_id
	_next_id += 1
	_entities[entity_id] = data
	return entity_id

func has_entity(entity_id: int) -> bool:
	return _entities.has(entity_id)


func has_container(
	entity_id: int,
	container_id: StringName
) -> bool:
	return (
		has_entity(entity_id)
		and _entities[entity_id].has(container_id)
	)


func has_value(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName
) -> bool:
	return (
		has_container(entity_id, container_id)
		and _entities[entity_id][container_id].has(String(attribute_name))
	)


func get_value(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName
) -> Variant:
	# The developer supplies existing IDs and paths; no schema is consulted.
	var value: Variant = (
		_entities[entity_id][container_id][String(attribute_name)]
	)
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value

func set_value(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName,
	value: Variant
) -> bool:
	if not has_value(entity_id, container_id, attribute_name):
		return false

	var stored_value: Variant = value
	if value is Dictionary or value is Array:
		stored_value = value.duplicate(true)

	_entities[entity_id][container_id][String(attribute_name)] = stored_value
	return true

func print_entities() -> void:
	for entity_id in _entities:
		print("Entity ", entity_id)

		var containers: Dictionary = _entities[entity_id]

		for container_id in containers:
			print("  ", container_id, ":")

			var attributes: Dictionary = containers[container_id]

			for attribute_name in attributes:
				print(
					"    ", attribute_name,
					" = ", attributes[attribute_name]
				)