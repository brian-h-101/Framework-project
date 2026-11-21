extends RefCounted

const ROOT = "res://Framework/Content/Behavior"
const Paths = preload("res://Framework/Env/Setup/library_path_policy.gd")


static func path_error(path: String, allow_root: bool = true) -> String:
	return Paths.path_error(path, ROOT, allow_root)


static func resource_error(path: String) -> String:
	var error := path_error(path, false)
	return error if not error.is_empty() else "" if path.get_extension() == "tres" else "Choose an external .tres behavior Resource."


static func name_error(name: String) -> String:
	return Paths.name_error(name)
