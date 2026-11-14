extends RefCounted


# Later parts override attributes from earlier parts without dropping sibling fields.
# Dictionary and array attribute values are replaced as a whole, matching spawn overrides.
static func combine(parts: Array[Dictionary]) -> Dictionary[StringName, Dictionary]:
	var containers: Dictionary[StringName, Dictionary] = {}
	for part in parts:
		for container_id in part:
			if not containers.has(container_id):
				containers[container_id] = {}
			containers[container_id].merge(part[container_id].duplicate(true), true)
	return containers
