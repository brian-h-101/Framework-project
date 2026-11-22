extends RefCounted

const Document = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_document.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")

const TYPES = {
	TYPE_BOOL: "bool", TYPE_INT: "int", TYPE_FLOAT: "float",
	TYPE_STRING: "String", TYPE_STRING_NAME: "StringName",
	TYPE_VECTOR2: "Vector2", TYPE_VECTOR2I: "Vector2i",
	TYPE_VECTOR3: "Vector3", TYPE_VECTOR3I: "Vector3i",
	TYPE_COLOR: "Color", TYPE_PACKED_VECTOR2_ARRAY: "PackedVector2Array",
}
const FRAMEWORK_METADATA = {
	"entity_definition": ["StringName", "Node", ""],
	"entity_key": ["StringName", "Node", ""],
	"entity_spatial_root": ["bool", "Node2D", "true"],
	"ui_anchor_role": ["StringName", "Node2D", "status"],
	"interaction_target": ["bool", "Node2D", "true"],
	"casts_shadow": ["bool", "Polygon2D", "true"],
	"receives_shadow": ["bool", "CanvasItem", "true"],
}


static func can_edit(node: Dictionary, scene_path: String) -> bool:
	return node["structural_scene"] == scene_path and node["type"] != "InstancePlaceholder" and ClassDB.class_exists(node["type"])


static func inspect(scene_path: String, path: String, native_type: String) -> Dictionary:
	var saved := _saved_properties(scene_path, path)
	if not saved["ok"]:
		return saved
	var options := {}
	for entry: Dictionary in ClassDB.class_get_property_list(native_type):
		var name: String = entry["name"]
		var kind := _native_type(entry)
		if not kind.is_empty():
			options[name] = _describe(name, kind, saved["value"])
	for key: String in FRAMEWORK_METADATA:
		var spec: Array = FRAMEWORK_METADATA[key]
		if _compatible(native_type, spec[1]):
			var name := "metadata/" + key
			options[name] = _describe(name, spec[0], saved["value"], spec[2])
	for name: String in saved["value"]:
		if name.begins_with("metadata/") and not options.has(name) and not FRAMEWORK_METADATA.has(name.get_slice("/", 1)):
			var kind: String = TYPES.get(typeof(saved["value"][name]), "")
			if not kind.is_empty():
				options[name] = _describe(name, kind, saved["value"])
	var names := options.keys()
	names.sort()
	var result: Array[Dictionary] = []
	for name: String in names:
		result.append(options[name])
	return Document.success(result)


static func edit(document: Dictionary, request: Dictionary, path: String, native_type: String) -> Dictionary:
	var name: Variant = request.get("property_name")
	var kind: Variant = request.get("property_type")
	var text: Variant = request.get("property_value")
	if not name is String or not kind is String or not text is String or text.length() > 65536:
		return Document.failure("Choose a property and a typed value of up to 65536 characters.")
	var checked := _check_type(name, kind, native_type)
	if not checked["ok"]:
		return checked
	var parsed := _parse_value(kind, text)
	if not parsed["ok"]:
		return parsed
	if name in ["metadata/entity_definition", "metadata/entity_key", "metadata/ui_anchor_role"] and text.strip_edges().is_empty():
		return Document.failure("This framework role requires nonempty text.")
	var literal := var_to_str(parsed["value"])
	for section: Dictionary in document["sections"]:
		if section["tag"] != "node" or Document.node_path(section) != path:
			continue
		var existing: Dictionary = {}
		for field: Dictionary in section["properties"]:
			if field["name"] == name:
				if not existing.is_empty():
					return Document.failure("The node has duplicate declarations of " + name + ".")
				existing = field
		var edit_span: Dictionary
		if existing.is_empty():
			edit_span = _insert(document["source"], section["header_end"], name + " = " + literal)
		else:
			edit_span = {"start": existing["value_start"], "end": existing["value_end"], "text": literal}
		return Document.success({"edit": edit_span, "name": name, "value": parsed["value"]})
	return Document.failure("Open the scene that declares this node to set its properties.")


static func verify(scene_path: String, path: String, name: String, expected: Variant) -> Dictionary:
	var saved := _saved_properties(scene_path, path)
	if not saved["ok"]:
		return saved
	if not saved["value"].has(name):
		return Document.failure("The staged scene did not declare the requested property.")
	var actual: Variant = saved["value"][name]
	if typeof(actual) != typeof(expected) or actual != expected:
		return Document.failure("The staged property did not retain its type and value.")
	return Document.success(true)


static func _native_type(entry: Dictionary) -> String:
	const EDITABLE_FLAGS = PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR
	if (entry["usage"] & EDITABLE_FLAGS) != EDITABLE_FLAGS or (entry["usage"] & PROPERTY_USAGE_READ_ONLY) != 0:
		return ""
	return TYPES.get(entry["type"], "")


static func _compatible(native_type: String, base: String) -> bool:
	return native_type == base or ClassDB.is_parent_class(native_type, base)


static func _check_type(name: String, kind: String, native_type: String) -> Dictionary:
	if name.begins_with("metadata/"):
		var key := name.trim_prefix("metadata/")
		if not key.is_valid_identifier() or not kind in TYPES.values():
			return Document.failure("Choose a valid metadata key and supported value type.")
		if FRAMEWORK_METADATA.has(key):
			var spec: Array = FRAMEWORK_METADATA[key]
			if not _compatible(native_type, spec[1]) or (kind != spec[0] and not (kind == "String" and spec[0] == "StringName")):
				return Document.failure("This metadata requires %s on a %s." % [spec[0], spec[1]])
		return Document.success(true)
	for entry: Dictionary in ClassDB.class_get_property_list(native_type):
		if entry["name"] == name and _native_type(entry) == kind and not kind.is_empty():
			return Document.success(true)
	return Document.failure("Choose a supported native property with its declared type.")


static func _saved_properties(scene_path: String, path: String) -> Dictionary:
	var scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if scene == null:
		return Document.failure("The scene could not be loaded for property inspection.")
	var state := scene.get_state()
	for index in state.get_node_count():
		if String(state.get_node_path(index)).trim_prefix("./") != path:
			continue
		var values := {}
		for property_index in state.get_node_property_count(index):
			values[String(state.get_node_property_name(index, property_index))] = state.get_node_property_value(index, property_index)
		return Document.success(values)
	return Document.failure("The selected node has no declaration in this scene.")


static func _describe(name: String, kind: String, saved: Dictionary, suggested: String = "") -> Dictionary:
	var value: Variant = saved.get(name)
	var local: bool = saved.has(name) and TYPES.get(typeof(value), "") == kind
	return {"name": name, "type": kind, "saved": local, "value": _format(value, kind) if local else suggested}


static func _format(value: Variant, kind: String) -> String:
	if kind not in ["Vector2", "Vector2i", "Vector3", "Vector3i", "Color", "PackedVector2Array"]:
		return Values.value_text(value)
	var native := var_to_str(value)
	return native.get_slice("(", 1).trim_suffix(")")


static func _parse_value(kind: String, text: String) -> Dictionary:
	if kind in Values.SCALARS:
		return Values.parse(kind, text)
	var components := text.strip_edges().split(",")
	match kind:
		"Vector2", "Vector2i":
			if components.size() != 2:
				return Document.failure("Enter two comma-separated coordinates.")
		"Vector3", "Vector3i":
			if components.size() != 3:
				return Document.failure("Enter three comma-separated coordinates.")
		"Color":
			if components.size() not in [3, 4]:
				return Document.failure("Enter red, green, blue, and optional alpha.")
		"PackedVector2Array":
			if text.strip_edges().is_empty():
				return Document.success(PackedVector2Array())
			if components.size() % 2 != 0 or components.size() > 4096:
				return Document.failure("Enter comma-separated X,Y pairs for up to 2048 vertices.")
		_:
			return Document.failure("Unsupported property value type: " + kind)
	var whole := kind in ["Vector2i", "Vector3i"]
	var numbers: Array = []
	for component in components:
		var parsed := Values.parse("int" if whole else "float", component)
		if not parsed["ok"]:
			return parsed
		var number: Variant = parsed["value"]
		if whole and (number < -2147483648 or number > 2147483647):
			return Document.failure("Integer vector components must fit in 32 bits.")
		if not whole and absf(number) > 3.402823466e38:
			return Document.failure("Vector and color components must fit in finite 32-bit floats.")
		numbers.append(number)
	match kind:
		"Vector2":
			return Document.success(Vector2(numbers[0], numbers[1]))
		"Vector2i":
			return Document.success(Vector2i(numbers[0], numbers[1]))
		"Vector3":
			return Document.success(Vector3(numbers[0], numbers[1], numbers[2]))
		"Vector3i":
			return Document.success(Vector3i(numbers[0], numbers[1], numbers[2]))
		"Color":
			return Document.success(Color(numbers[0], numbers[1], numbers[2], numbers[3] if numbers.size() == 4 else 1.0))
	var points := PackedVector2Array()
	for index in range(0, numbers.size(), 2):
		points.append(Vector2(numbers[index], numbers[index + 1]))
	return Document.success(points)


static func _insert(source: String, header_end: int, assignment: String) -> Dictionary:
	var newline := "\r\n" if source.get_slice("\n", 0).ends_with("\r") else "\n"
	var line_end := source.find("\n", header_end)
	if line_end < 0:
		var end := source.length()
		return {"start": end, "end": end, "text": newline + assignment + newline}
	return {"start": line_end + 1, "end": line_end + 1, "text": assignment + newline}
