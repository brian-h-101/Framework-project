extends "res://Framework/Env/Configuration/Resources/configuration_resource.gd"

@export var startup_mode: StringName = &""
@export var save_path: String = ""


func to_definition() -> Dictionary:
	return {"startup_mode": startup_mode, "save_path": save_path}


func validation_error() -> String:
	if startup_mode not in [&"new", &"restore"]:
		return "Startup mode must be new or restore."
	if not save_path.begins_with("user://") or save_path.get_file().is_empty():
		return "Save path must name a file under user://."
	return ""
