extends Resource

@export var containers: Dictionary = {}


func to_containers() -> Dictionary:
	var error := container_error(containers)
	if not error.is_empty():
		return {"ok": false, "value": null, "error": error}
	var copied: Dictionary[StringName, Dictionary] = {}
	for container_id in containers:
		copied[StringName(container_id)] = containers[container_id].duplicate(true)
	return {"ok": true, "value": copied, "error": ""}


static func container_error(value: Dictionary) -> String:
	for container_id in value:
		if (
			typeof(container_id) not in [TYPE_STRING, TYPE_STRING_NAME]
			or String(container_id).is_empty()
			or not value[container_id] is Dictionary
		):
			return "Containers require nonempty text names and dictionary attributes."
	return ""
