extends "res://Framework/Env/Configuration/Resources/Shared/configuration_resource.gd"

@export_file("*.tscn") var initial_map: String = ""
@export_file("*.tscn") var ui_scene: String = ""
@export var entities: Array[Dictionary] = []


func to_definition() -> Dictionary:
	return {"initial_map": initial_map, "ui_scene": ui_scene, "entities": named_entries(entities, "key")}


func validation_error() -> String:
	for field in ["initial_map", "ui_scene"]:
		var path: String = get(field)
		if path.is_empty():
			continue
		if not path.begins_with("res://") or path.get_extension() != "tscn":
			return "%s must be a project .tscn path or empty." % field
		if not ResourceLoader.exists(path, "PackedScene"):
			return "%s does not exist: %s" % [field, path]
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
