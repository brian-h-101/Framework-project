extends "res://Framework/Env/Configuration/Resources/configuration_resource.gd"

@export var startup_mode: StringName = &""
@export var save_path: String = ""
@export var map_path_redirects: Dictionary[String, String] = {}


func to_definition() -> Dictionary:
	return {"startup_mode": startup_mode, "save_path": save_path,
		"map_path_redirects": map_path_redirects.duplicate()}


func validation_error() -> String:
	if startup_mode not in [&"new", &"restore"]:
		return "Startup mode must be new or restore."
	if not save_path.begins_with("user://") or save_path.get_file().is_empty():
		return "Save path must name a file under user://."
	for previous_path in map_path_redirects:
		var current_path := map_path_redirects[previous_path]
		for path in [previous_path, current_path]:
			if not path.begins_with("res://") or path.simplify_path() != path or path.contains("\\") or path.get_extension() != "tscn":
				return "Map redirects require canonical project .tscn paths."
		if not ResourceLoader.exists(current_path, "PackedScene"):
			return "Redirected map does not exist: %s" % current_path
	return ""
