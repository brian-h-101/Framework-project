extends RefCounted

var entity_id: int
var container_id: StringName
var path: Array


func _init(
	target_entity_id: int,
	target_container_id: StringName,
	attribute_path: Array
) -> void:
	entity_id = target_entity_id
	container_id = target_container_id
	path = attribute_path.duplicate(true)