extends RefCounted

const Controller = preload("res://Framework/Content/Universal/Movement/based/Controllers/movement_controller.gd")
const MovementCatalog = preload("res://Framework/Env/Authoring/Scenes/Configuration/movement_configuration_catalog.gd")
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const Document = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_document.gd")
const ROOT := "res://Framework/Content/Gameplay/Controller"


static func read() -> Dictionary:
	var found := Paths.paths_in(ROOT)
	if not found["ok"]:
		return found
	var controllers: Array[Dictionary] = []
	for path: String in found["value"]:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Controller
		if resource != null:
			var inspected := resource.read()
			if inspected["ok"]:
				var kind: Variant = inspected["value"].get("kind")
				if kind is String and not kind.is_empty():
					controllers.append({"source_path": path, "kind": kind})
	return Document.success(controllers)


static func inspect(path: String) -> Dictionary:
	var error := Paths.path_error(path, ROOT, false)
	if not error.is_empty():
		return Document.failure(error)
	if path.get_extension() != "tres":
		return Document.failure("Choose a movement controller .tres resource.")
	var hashes := {}
	var hashed := MovementCatalog._collect_dependencies(path, hashes, 0)
	if not hashed["ok"]:
		return hashed
	var controller := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Controller
	if controller == null:
		return Document.failure("Expected a movement controller: %s." % path)
	var inspected := controller.read()
	if not inspected["ok"]:
		return inspected
	var definition: Dictionary = inspected["value"]
	var kind: Variant = definition.get("kind")
	if not kind is String or kind.is_empty():
		return Document.failure("The movement controller must identify its kind.")
	if kind == "keyboard" and not definition.get("actions") is Dictionary:
		return Document.failure("The keyboard controller must provide directional actions.")
	return Document.success({"definition": definition, "dependency_hashes": hashes})
