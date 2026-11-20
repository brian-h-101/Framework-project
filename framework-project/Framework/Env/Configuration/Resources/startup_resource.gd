extends "res://Framework/Env/Configuration/Resources/configuration_resource.gd"

@export_file("*.tscn") var initial_map: String = ""
@export var entities: Array[Dictionary] = []


func to_definition() -> Dictionary:
	return {"initial_map": initial_map, "entities": named_entries(entities, "key")}


func validation_error() -> String:
	if not initial_map.begins_with("res://") or initial_map.get_extension() != "tscn":
		return "Initial map must be a project .tscn path."
	if not ResourceLoader.exists(initial_map, "PackedScene"):
		return "Initial map does not exist: %s" % initial_map
	var error := entry_error(entities, "key")
	if not error.is_empty():
		return error
	for specification in entities:
		if not is_text(specification.get("definition")) or String(specification["definition"]).is_empty():
			return "Startup entities require nonempty keys and definition IDs."
		var overrides: Variant = specification.get("overrides", {})
		if not overrides is Dictionary:
			return "Startup entity overrides must be a dictionary."
		for container_id in overrides:
			if not is_text(container_id) or String(container_id).is_empty() or not overrides[container_id] is Dictionary:
				return "Startup overrides require named dictionary containers."
	return ""
