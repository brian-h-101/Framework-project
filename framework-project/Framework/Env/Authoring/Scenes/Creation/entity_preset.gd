extends RefCounted

const AttributeLibrary = preload("res://Framework/Env/Authoring/Attributes/attribute_library.gd")
const Authored = preload("res://Framework/Env/Setup/Library/authored_library.gd")
const Definitions = preload("res://Framework/Env/Setup/Definitions/starting_definitions.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Fragment = preload("res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd")
const Preset = preload("res://Framework/Infrastructure/API/Entity/Resources/starting_attributes_resource.gd")
const Shared = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")

const ROOTS = [
	"res://Framework/Content/Gameplay/Presentation/Entity",
	"res://Framework/Content/Gameplay/Presentation/Items",
	"res://Framework/Content/Gameplay/Presentation/Objects",
]
const FILENAME = "starting_attributes.tres"


static func fragments() -> Dictionary:
	var catalogue := AttributeLibrary.catalogue()
	if not catalogue["ok"]:
		return catalogue
	var paths: Array[String] = []
	for entry: Dictionary in catalogue["value"]["entries"]:
		if entry["kind"] == "resource" and entry["supported"]:
			paths.append(entry["source_path"])
	return Values.success(paths)


static func draft(folder: String, scene_name: String, request: Dictionary) -> Dictionary:
	if folder.get_base_dir() not in ROOTS:
		return Values.failure("Choose an entity, item, or object folder directly under its Presentation category.")
	var id: Variant = request.get("definition_id")
	if not id is String or not id.is_valid_identifier() or id != id.to_lower():
		return Values.failure("Enter a lowercase definition ID using letters, digits, and underscores.")
	var path := folder.path_join(FILENAME)
	var target_error := Shared.target_error(path, request.get("expected_parent"))
	if not target_error.is_empty():
		return Values.failure("%s: %s" % [path, target_error])
	var definitions := Definitions.definitions()
	if not definitions["ok"]:
		return definitions
	if definitions["sources"].has(StringName(id)):
		return Values.failure("Definition ID '%s' is already used by %s." % [id, definitions["sources"][StringName(id)]])

	var selected: Variant = request.get("fragments")
	if not selected is Array or selected.size() > 1000:
		return Values.failure("Choose up to 1000 authored attribute fragments.")
	var preset := Preset.new()
	preset.id = StringName(id)
	preset.overrides = {&"identity": {"name": scene_name}}
	var hashes := {}
	for fragment_path: Variant in selected:
		if not fragment_path is String:
			return Values.failure("Attribute fragment paths must be text.")
		if hashes.has(fragment_path):
			return Values.failure("Repeated attribute fragment: " + fragment_path)
		var error := Authored.resource_error(fragment_path)
		if not error.is_empty():
			return Values.failure(error)
		var checked := Files.check_path(fragment_path)
		if not checked["ok"]:
			return checked
		hashes[fragment_path] = FileAccess.get_sha256(fragment_path)
		var fragment := ResourceLoader.load(fragment_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Fragment
		if fragment == null:
			return Values.failure("Expected an authored container fragment: " + fragment_path)
		preset.fragments.append(fragment)
	var definition := preset.to_definition()
	if not definition.get("ok", true):
		return definition
	var prepared := Shared.draft(path, request.get("expected_parent"), preset, _snapshot)
	if not prepared["ok"]:
		return prepared
	var checked := Files.check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked
	prepared["value"]["dependency_hashes"] = hashes
	return prepared


static func verify(folder: String, id: String) -> Dictionary:
	if folder.get_base_dir() not in ROOTS:
		return Values.failure("The scene is outside the starting definition library.")
	var definitions := Definitions.definitions()
	if not definitions["ok"]:
		return definitions
	if definitions["sources"].get(StringName(id), "") != folder.path_join(FILENAME):
		return Values.failure("The new starting attributes did not register the scene's definition ID.")
	return Values.success(true)


static func _snapshot(resource: Preset) -> Dictionary:
	return {"id": resource.id, "fragments": resource.fragments, "definition": resource.to_definition()}
