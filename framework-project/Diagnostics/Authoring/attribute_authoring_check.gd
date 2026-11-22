extends SceneTree

const FragmentResource = preload("res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd")
const Inspection = preload("res://Framework/Env/Authoring/Attributes/attribute_inspection.gd")
const Editing = preload("res://Framework/Env/Authoring/Attributes/attribute_editing.gd")
const Values = preload("res://Framework/Env/Authoring/Attributes/attribute_values.gd")
const NEEDS = "res://Framework/Content/Gameplay/Authored/Entity/Attributes/Needs/needs.tres"
const CONFIGURATION = "res://Framework/Content/Configuration/Map/city_ground.tres"

var _passed := true
var _folder: String
var _fixture: String


func _initialize() -> void:
	var needs_hash := FileAccess.get_sha256(NEEDS)
	var inspected := Inspection.inspect(NEEDS)
	_check("Production needs Resource is supported", inspected["ok"] and inspected["value"]["supported"])
	if not inspected["ok"]:
		_finish()
		return
	var leaf := _find(inspected["value"]["root"], _path([&"needs", "hunger", "current"]))
	_check("Nested keys retain native key and value types", leaf.get("kind") == "int" and leaf.get("value_text") == "0")
	var other := Inspection.inspect(CONFIGURATION)
	_check("Other Resource schemas are identified without a tree", other["ok"] and not other["value"]["supported"] and other["value"]["root"] == null)
	_check("Traversal paths are rejected", not Inspection.inspect("res://Framework/../project.godot")["ok"])

	_folder = "res://.godot/diagnostics/attribute_authoring_" + Crypto.new().generate_random_bytes(12).hex_encode()
	_check("Fixture folder is unused", not DirAccess.dir_exists_absolute(_folder))
	if DirAccess.make_dir_recursive_absolute(_folder) != OK:
		_check("Fixture folder created", false)
		_finish()
		return
	_fixture = _folder.path_join("attributes.tres")
	var fragment := FragmentResource.new()
	var typed: Array[int] = [1, 2]
	var typed_dictionary: Dictionary[StringName, int] = {&"first": 1}
	fragment.containers = {
		&"needs": {
			"hunger": {"current": 0, "maximum": 100},
			"text": "Quotes \" slash \\ tab\t newline\n Unicode: 雨",
			&"named": &"value",
			"flag": false, "empty": null, "number": 1.25,
			"precise": 9223372036854775807, "minimum": -9223372036854775808,
			"items": ["first", {"count": 2}], "typed": typed,
			"typed_dictionary": typed_dictionary,
			7: "integer key", "7": "text key",
			"vector": Vector2(2, 3), "color": Color(0.1, 0.2, 0.3),
			"reference": preload("res://Games/ExampleGame/Tiles/ground.svg"),
		},
		&"sibling": {"kept": 42},
	}
	if ResourceSaver.save(fragment, _fixture) != OK:
		_check("Fixture saved", false)
		_finish()
		return
	var uid := ResourceUID.create_id()
	_check("Fixture UID assigned", ResourceSaver.set_uid(_fixture, uid) == OK)
	var cached := load(_fixture) as FragmentResource
	var graph := Inspection.inspect(_fixture)
	_check("Full fixture graph exports", graph["ok"])
	if not graph["ok"]:
		print(graph)
		_finish()
		return
	_check("Maximum integer exports as exact text", _find(graph["value"]["root"], _path([&"needs", "precise"]))["value_text"] == "9223372036854775807")
	_check("Native vectors are displayed read-only", not _find(graph["value"]["root"], _path([&"needs", "vector"]))["editable"])

	_change("Nested integer edit", "set", _path([&"needs", "hunger", "current"]), {}, "int", "42")
	_check("Cached source Resource remains unchanged", cached.containers[&"needs"]["hunger"]["current"] == 0)
	_change("Maximum integer edit", "set", _path([&"needs", "precise"]), {}, "int", "9223372036854775807")
	_change("Minimum integer edit", "set", _path([&"needs", "minimum"]), {}, "int", "-9223372036854775808")
	_change("Float edit", "set", _path([&"needs", "number"]), {}, "float", "20")
	_change("Boolean edit", "set", _path([&"needs", "flag"]), {}, "bool", "true")
	_change("StringName edit", "set", _path([&"needs", &"named"]), {}, "StringName", "updated_name")
	var text := "New \"quote\" \\ slash\n  second line  \r\n\t雪"
	_change("Unicode and escaped string edit", "set", _path([&"needs", "text"]), {}, "String", text)
	_change("Null edit", "set", _path([&"needs", "empty"]), {}, "Nil", "null")
	_change("Array index edit", "set", _path([&"needs", "items", {"kind": "index", "text": "1"}, "count"]), {}, "int", "3")
	_change("Integer dictionary key edit", "set", _path([&"needs", 7]), {}, "String", "updated integer key")
	_change("Container insertion", "add", [], Values.segment(&"acquired"), "Dictionary", "{}")
	_change("Nested dictionary insertion", "add", _path([&"acquired"]), Values.segment("bag"), "Dictionary", "{}")
	_change("Nested array insertion", "add", _path([&"acquired", "bag"]), Values.segment("items"), "Array", "[]")
	_change("Array append", "add", _path([&"acquired", "bag", "items"]), {}, "String", "medicine")
	_change("Dictionary key rename", "rename", _path([&"acquired", "bag"]), Values.segment("inventory"))
	_change("Typed array append", "add", _path([&"needs", "typed"]), {}, "int", "3")
	_change("Typed dictionary insertion", "add", _path([&"needs", "typed_dictionary"]), Values.segment(&"second"), "int", "2")
	var saved := ResourceLoader.load(_fixture, "", ResourceLoader.CACHE_MODE_IGNORE) as FragmentResource
	_check("Edits preserve siblings and native values", (
		saved.containers[&"needs"]["hunger"] == {"current": 42, "maximum": 100}
		and saved.containers[&"sibling"] == {"kept": 42}
		and saved.containers[&"needs"]["vector"] == Vector2(2, 3)
		and saved.containers[&"needs"]["color"] == fragment.containers[&"needs"]["color"]
		and saved.containers[&"needs"]["reference"] == fragment.containers[&"needs"]["reference"]
		and saved.containers[&"needs"]["7"] == "text key"
		and saved.containers[&"needs"]["text"] == text
	))
	_check("Edited scalar types are retained", (
		typeof(saved.containers[&"needs"]["number"]) == TYPE_FLOAT
		and typeof(saved.containers[&"needs"][&"named"]) == TYPE_STRING_NAME
		and saved.containers[&"needs"]["precise"] == 9223372036854775807
		and saved.containers[&"needs"]["minimum"] == -9223372036854775808
		and saved.containers[&"needs"]["flag"] == true
		and saved.containers[&"needs"]["empty"] == null
	))
	_check("Resource UID is preserved", Inspection.resource_uid(_fixture) == uid)
	_check("Typed collections retain constraints", (
		saved.containers[&"needs"]["typed"].get_typed_builtin() == TYPE_INT
		and saved.containers[&"needs"]["typed_dictionary"].get_typed_key_builtin() == TYPE_STRING_NAME
	))

	_reject("Duplicate container", {"operation": "add", "path": [], "key": Values.segment("needs"), "value_type": "Dictionary", "value_text": "{}"})
	_reject("Scalar container", {"operation": "add", "path": [], "key": Values.segment("bad"), "value_type": "int", "value_text": "1"})
	_reject("Empty container name", {"operation": "rename", "path": _path([&"acquired"]), "key": Values.segment("")})
	_reject("Duplicate rename", {"operation": "rename", "path": _path([&"acquired"]), "key": Values.segment(&"needs")})
	_reject("Array index rename", {"operation": "rename", "path": _path([&"needs", "items", {"kind": "index", "text": "0"}]), "key": Values.segment("bad")})
	_reject("Missing typed key", {"operation": "set", "path": _path([&"needs", "named"]), "value_type": "int", "value_text": "1"})
	_reject("Wrong typed array value", {"operation": "add", "path": _path([&"needs", "typed"]), "value_type": "bool", "value_text": "true"})
	_reject("Wrong typed dictionary key", {"operation": "add", "path": _path([&"needs", "typed_dictionary"]), "key": Values.segment("third"), "value_type": "int", "value_text": "3"})
	_reject("Root replacement", {"operation": "set", "path": [], "value_type": "Nil", "value_text": "null"})
	_reject("Read-only native value replacement", {"operation": "set", "path": _path([&"needs", "vector"]), "value_type": "Nil", "value_text": "null"})
	_reject("Whole collection replacement", {"operation": "set", "path": _path([&"needs", "hunger"]), "value_type": "Nil", "value_text": "null"})
	_reject("Out of range array index", {"operation": "remove", "path": _path([&"needs", "items", {"kind": "index", "text": "999"}])})
	_reject("Stale file hash", {"operation": "remove", "path": _path([&"sibling"]), "expected_hash": "0".repeat(64)})
	for invalid_int in ["20.0", "9223372036854775808", "-9223372036854775809"]:
		_reject("Invalid integer %s" % invalid_int, {"operation": "set", "path": _path([&"needs", "precise"]), "value_type": "int", "value_text": invalid_int})
	_reject("Nonfinite float", {"operation": "set", "path": _path([&"needs", "number"]), "value_type": "float", "value_text": "1e999"})
	_change("Array removal", "remove", _path([&"acquired", "inventory", "items", {"kind": "index", "text": "0"}]))
	_change("Container removal", "remove", _path([&"acquired"]))
	_check("Rejections leave subsequent edits usable", Inspection.inspect(_fixture)["ok"])
	_check("Production Resource remains byte-for-byte unchanged", FileAccess.get_sha256(NEEDS) == needs_hash)
	_finish()


func _change(label: String, operation: String, path: Array, key: Dictionary = {}, kind: String = "", text: String = "") -> void:
	var result := Editing.edit(_fixture, {
		"operation": operation, "path": path, "key": key,
		"value_type": kind, "value_text": text, "expected_hash": FileAccess.get_sha256(_fixture),
	})
	_check(label, result["ok"])
	if not result["ok"]:
		print(result["error"])


func _reject(label: String, request: Dictionary) -> void:
	var before := FileAccess.get_sha256(_fixture)
	if not request.has("expected_hash"):
		request["expected_hash"] = before
	var result := Editing.edit(_fixture, request)
	_check(label + " is rejected without writing", not result["ok"] and FileAccess.get_sha256(_fixture) == before)


func _path(parts: Array) -> Array:
	var path: Array = []
	for part in parts:
		path.append(part if part is Dictionary else Values.segment(part))
	return path


func _find(node: Dictionary, path: Array) -> Dictionary:
	if node.get("path") == path:
		return node
	for child in node.get("children", []):
		var found := _find(child, path)
		if not found.is_empty():
			return found
	return {}


func _finish() -> void:
	if not _fixture.is_empty() and FileAccess.file_exists(_fixture):
		_check("Temporary fixture removed", DirAccess.remove_absolute(_fixture) == OK)
	if not _folder.is_empty() and DirAccess.dir_exists_absolute(_folder):
		var directory := DirAccess.open(_folder)
		_check("No staging files remain", directory != null and directory.get_files().is_empty())
		_check("Temporary folder removed", DirAccess.remove_absolute(_folder) == OK)
	print("[attribute-authoring] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[attribute-authoring] ", label, ": ", passed)
	_passed = _passed and passed
