extends RefCounted

const ConfigurationType = preload("res://Framework/Env/Configuration/Resources/Shared/configuration_type_resource.gd")
const Preset = preload("res://Framework/Env/Configuration/Resources/Shared/custom_configuration_resource.gd")
const Policy = preload("res://Framework/Env/Setup/Library/behavior_library_policy.gd")
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Drafts = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")

const TYPE_SUFFIX := ".type.tres"
const OPERATIONS := ["draft_configuration_type", "draft_custom_configuration", "set_custom_configuration_field"]


static func catalogue(folder: String) -> Dictionary:
	var error := Policy.shared_folder_error(folder)
	if not error.is_empty():
		return Values.failure(error)
	var fingerprint := Drafts.fingerprint(folder)
	var directory := DirAccess.open(folder)
	if directory == null:
		return Values.failure("Could not read the selected Shared folder.")
	var types: Array[Dictionary] = []
	var ids := {}
	var hashes := {}
	for name in directory.get_files():
		if name.begins_with(".") or not name.ends_with(TYPE_SUFFIX):
			continue
		var source := folder.path_join(name)
		var checked := _load_type(source, hashes)
		if not checked["ok"]:
			return checked
		var schema: ConfigurationType = checked["value"]
		if ids.has(schema.id):
			return Values.failure("Duplicate Configuration Type ID '%s' in %s and %s." % [schema.id, ids[schema.id], source])
		ids[schema.id] = source
		var fields: Array[Dictionary] = []
		for field in schema.fields:
			fields.append({"name": field["name"], "type": field["type"], "default_text": Values.value_text(field["default"])})
		types.append({"id": String(schema.id), "label": schema.label, "source_path": source,
			"content_hash": hashes[source], "fields": fields})
	if Drafts.fingerprint(folder) != fingerprint:
		return Values.failure("The selected Shared folder changed. Refresh and retry.")
	var verified := Files.check_hashes(hashes, hashes)
	return Values.success(types) if verified["ok"] else verified


static func edit(path: String, request: Dictionary) -> Dictionary:
	var folder := path.get_base_dir()
	var error := Policy.shared_folder_error(folder)
	if error.is_empty():
		error = Paths.project_error(path)
	if error.is_empty():
		error = Policy.name_error(path.get_file())
	if not error.is_empty():
		return Values.failure(error)
	if path.get_extension() != "tres":
		return Values.failure("Choose a .tres configuration file.")
	if request["operation"] == "draft_configuration_type":
		return _draft_type(path, request)
	if path.ends_with(TYPE_SUFFIX):
		return Values.failure("Use a preset filename ending in .tres. The .type.tres suffix is for definitions.")
	if request["operation"] == "draft_custom_configuration":
		return _draft_preset(path, request)
	return _edit_preset(path, request)


static func _draft_type(path: String, request: Dictionary) -> Dictionary:
	var id: Variant = request.get("type_id")
	var label: Variant = request.get("type_label")
	var fields: Variant = request.get("type_fields")
	if not id is String or not label is String or not fields is Array or fields.size() > ConfigurationType.MAX_FIELDS:
		return Values.failure("Provide a Configuration Type ID, label, and field definitions.")
	if path.get_file() != id + TYPE_SUFFIX:
		return Values.failure("Use the Configuration Type ID followed by .type.tres.")
	var schema := ConfigurationType.new()
	schema.id = StringName(id)
	schema.label = label.strip_edges()
	for field: Variant in fields:
		if not field is Dictionary or not field.get("name") is String or field.get("type") not in ConfigurationType.FIELD_TYPES or not field.get("value_text") is String:
			return Values.failure("Each configuration field requires a name, supported type, and default.")
		var parsed := Values.parse(field["type"], field["value_text"])
		if not parsed["ok"]:
			return Values.failure("%s: %s" % [field["name"], parsed["error"]])
		schema.fields.append({"name": field["name"], "type": field["type"], "default": parsed["value"]})
	var error := schema.validation_error()
	if not error.is_empty():
		return Values.failure(error)
	var listed := catalogue(path.get_base_dir())
	if not listed["ok"]:
		return listed
	for existing: Dictionary in listed["value"]:
		if existing["id"] == id:
			return Values.failure("A Configuration Type with ID '%s' already exists." % id)
	return Drafts.draft(path, request.get("expected_parent"), schema, _snapshot)


static func _draft_preset(path: String, request: Dictionary) -> Dictionary:
	var schema_path: Variant = request.get("configuration_schema_path")
	if not schema_path is String or schema_path.get_base_dir() != path.get_base_dir():
		return Values.failure("Choose a Configuration Type from the selected profile.")
	var hashes := {}
	var checked := _load_type(schema_path, hashes)
	if not checked["ok"]:
		return checked
	var preset := Preset.new()
	preset.schema = checked["value"]
	checked = _check_expected(request, hashes)
	if not checked["ok"]:
		return checked
	var values: Variant = request.get("configuration_values")
	if not values is Dictionary:
		return Values.failure("Provide configuration field values.")
	for field in preset.schema.fields:
		var field_name: String = field["name"]
		if not values.has(field_name):
			continue
		checked = _set_value(preset, field, values[field_name])
		if not checked["ok"]:
			return checked
	if preset.values.size() != values.size():
		return Values.failure("The preset request contains an unknown configuration field.")
	var draft := Drafts.draft(path, request.get("expected_parent"), preset, _snapshot)
	if not draft["ok"]:
		return draft
	checked = Files.check_hashes(hashes, hashes)
	return draft if checked["ok"] else checked


static func _edit_preset(path: String, request: Dictionary) -> Dictionary:
	var checked := Files.check_path(path)
	if not checked["ok"]:
		return checked
	var hashes := {path: FileAccess.get_sha256(path)}
	var preset := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Preset
	if preset == null or preset.schema == null or preset.schema.resource_path.get_base_dir() != path.get_base_dir():
		return Values.failure("Choose a preset with a Configuration Type from the same profile.")
	checked = _load_type(preset.schema.resource_path, hashes)
	if not checked["ok"]:
		return checked
	preset.schema = checked["value"]
	checked = _check_expected(request, hashes)
	if not checked["ok"]:
		return checked
	for field in preset.schema.fields:
		if field["name"] == request.get("field"):
			checked = _set_value(preset, field, request.get("value_text"))
			if not checked["ok"]:
				return checked
			var error := preset.validation_error()
			return Files.save(path, hashes, preset, _snapshot) if error.is_empty() else Values.failure(error)
	return Values.failure("Choose a field defined by the preset's Configuration Type.")


static func _load_type(path: String, hashes: Dictionary) -> Dictionary:
	if not path.ends_with(TYPE_SUFFIX):
		return Values.failure("Choose a saved .type.tres definition.")
	var checked := Files.check_path(path)
	if not checked["ok"]:
		return checked
	hashes[path] = FileAccess.get_sha256(path)
	var schema := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as ConfigurationType
	if schema == null:
		return Values.failure("Expected a Configuration Type: " + path)
	var error := schema.validation_error()
	return Values.success(schema) if error.is_empty() else Values.failure(path + ": " + error)


static func _check_expected(request: Dictionary, hashes: Dictionary) -> Dictionary:
	var expected: Variant = request.get("expected_hashes")
	if not expected is Dictionary:
		return Values.failure("Configuration edits require inspected resource hashes.")
	return Files.check_hashes(expected, hashes)


static func _set_value(preset: Preset, field: Dictionary, input: Variant) -> Dictionary:
	if not input is String:
		return Values.failure("Provide a text value for configuration field " + field["name"] + ".")
	var parsed := Values.parse(field["type"], input)
	if not parsed["ok"]:
		return Values.failure("%s: %s" % [field["name"], parsed["error"]])
	preset.values[field["name"]] = parsed["value"]
	return Values.success(true)


static func _snapshot(resource: Resource) -> Dictionary:
	var result := {"script": resource.get_script(), "name": resource.resource_name,
		"local": resource.resource_local_to_scene, "metadata": {}}
	for key in resource.get_meta_list():
		result["metadata"][key] = resource.get_meta(key)
	if resource is ConfigurationType:
		result.merge({"id": resource.id, "label": resource.label, "fields": resource.fields})
	elif resource is Preset:
		result.merge({"schema": resource.schema, "values": resource.values})
	return result
