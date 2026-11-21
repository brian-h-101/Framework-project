extends SceneTree

const Schema = preload("res://Framework/Env/Authoring/Resources/behavior_schema.gd")
const Inspection = preload("res://Framework/Env/Authoring/Resources/behavior_inspection.gd")
const Editing = preload("res://Framework/Env/Authoring/Resources/behavior_editing.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Library = preload("res://Framework/Env/Authoring/Resources/behavior_library.gd")
const RuntimeCore = preload("res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd")
const AttributeEffects = preload("res://Framework/Infrastructure/Implementation/Gameplay/Executors/attribute_effects_executor.gd")

var _passed := true
var _folder := ""
var _sources := {}
var _production := {}


func _initialize() -> void:
	Schema.Executors.use_setup(preload("res://Diagnostics/Fixtures/Setup/executor_authoring_setup.gd").new())
	var paths := Library.paths("")
	if not paths["ok"]:
		_check("Production catalogue is readable", false)
		quit(1)
		return
	for path in paths["value"]:
		_production[path] = FileAccess.get_sha256(path)
	_folder = "res://.godot/diagnostics/behavior_editing_" + Crypto.new().generate_random_bytes(12).hex_encode()
	if DirAccess.dir_exists_absolute(_folder) or DirAccess.make_dir_recursive_absolute(_folder) != OK:
		_check("Unique fixture folder created", false)
		quit(1)
		return
	_run()
	for path in _production:
		_check("Production file unchanged: " + path.get_file(), FileAccess.get_sha256(path) == _production[path])
	var directory := DirAccess.open(_folder)
	if directory != null:
		for name in directory.get_files():
			_check("No pending files remain: " + name, not name.begins_with(".behavior-pending-"))
			_check("Fixture removed: " + name, DirAccess.remove_absolute(_folder.path_join(name)) == OK)
		_check("Fixture folder removed", DirAccess.remove_absolute(_folder) == OK)
	print("[behavior-editing] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _run() -> void:
	var condition := Schema.Condition.new()
	condition.id = &"fixture_strength"
	condition.requirement = {"entity": &"actor", "container": &"strength", "path": ["current"], "operator": ">=", "value": 20, "message": "Needs strength."}
	var saved_condition := _save("condition", condition) as Schema.Condition
	var group := Schema.Group.new()
	group.id = &"fixture_group"
	group.conditions = [saved_condition]
	var saved_group := _save("group", group) as Schema.Group
	var shared := Schema.Group.new()
	shared.id = &"fixture_shared"
	shared.conditions = [saved_condition]
	_save("shared", shared)
	var action := Schema.Action.new()
	action.id = &"fixture_action"
	action.behavior_id = &"diagnostic_effects"
	action.effects = [{"operation": &"add", "entity": &"target", "container": &"health", "path": ["current"], "value_from": &"amount"}]
	var saved_action := _save("action", action) as Schema.Action
	var interaction := Schema.Interaction.new()
	interaction.id = &"fixture_interaction"
	interaction.action = saved_action
	interaction.requirements = saved_group
	var typed: Array[int] = [1, 2]
	interaction.arguments = {&"amount": -10, "unused": {"text": "雪\n  line\r\n\tend", &"name": &"original", "precise": 9223372036854775807, "typed": typed, "items": ["first"], "vector": Vector2(2, 3), "reference": preload("res://Games/ExampleGame/Tiles/ground.svg")}}
	_save("interaction", interaction)
	for resource in _sources:
		_check("Fixture created: " + resource, not _sources[resource].is_empty())
	var graph := Inspection.graph(_sources["interaction"])
	_check("Graph exports nested data and dependency hashes", graph["ok"] and graph["value"]["version"] == 2 and graph["value"]["nodes"].size() == 4 and graph["value"]["dependency_hashes"].has(_sources["shared"]))
	if not graph["ok"]:
		print(graph)
		return
	var leaf := _find(graph["value"]["nodes"][_sources["interaction"]]["data"], _path(["arguments", "unused", "precise"]))
	_check("Int64 values export without rounding", leaf["value_text"] == "9223372036854775807")
	_check("Dictionary key rename is available", leaf["can_rename"])
	var required := _find(graph["value"]["nodes"][_sources["action"]]["data"], _path(["effects", 0, "operation"]))
	_check("Required effect keys are protected", not required["can_rename"] and not required["can_remove"])
	var condition_hash := FileAccess.get_sha256(_sources["condition"])
	var shared_hash := FileAccess.get_sha256(_sources["shared"])
	_change("Group relationship is removed", "group", {"operation": "remove_condition", "condition_index": 0, "condition_path": _sources["condition"]})
	_check("Unlink preserves the shared condition and other group", FileAccess.get_sha256(_sources["condition"]) == condition_hash and FileAccess.get_sha256(_sources["shared"]) == shared_hash and (_load("group") as Schema.Group).conditions.is_empty())
	_reject("Repeated relationship removal is rejected", "group", {"operation": "remove_condition", "condition_index": 0, "condition_path": _sources["condition"]})
	_change("Optional requirements are cleared", "interaction", {"operation": "clear_requirements"})
	_check("Required action remains assigned", (_load("interaction") as Schema.Interaction).action.resource_path == _sources["action"] and (_load("interaction") as Schema.Interaction).requirements == null)
	_reject("Required action cannot be removed", "interaction", {"operation": "remove", "path": _path(["action"])})
	_reject("Resource ID cannot be renamed", "action", {"operation": "rename", "path": _path(["id"]), "key": Values.segment("renamed")})
	_reject("Required argument cannot be removed", "interaction", {"operation": "remove", "path": _path(["arguments", &"amount"])})
	_reject("Required argument cannot be renamed", "interaction", {"operation": "rename", "path": _path(["arguments", &"amount"]), "key": Values.segment(&"damage")})
	_reject("Add effect argument must stay numeric", "interaction", {"operation": "set", "path": _path(["arguments", &"amount"]), "value_type": "String", "value_text": "text"})
	_reject("Incomplete effects are rejected", "action", {"operation": "add_effect", "effect": {"operation": "add"}})
	_reject("Empty effects cannot be appended", "action", {"operation": "add", "path": _path(["effects"]), "value_type": "Dictionary", "value_text": "{}"})
	var effect := {"operation": "add", "entity": "target", "container": "health", "path": ["current"], "value_from": "missing"}
	_reject("Action edits protect interaction consumers", "action", {"operation": "add_effect", "effect": effect})
	effect["value_from"] = "amount"
	_change("Complete effect is added", "action", {"operation": "add_effect", "effect": effect})
	_check("Action conversion contains both effects", (_load("action") as Schema.Action).to_definition()["effects"].size() == 2)
	_reject("Required effect key cannot be removed", "action", {"operation": "remove", "path": _path(["effects", 0, "operation"])})
	_change("An effect can be removed", "action", {"operation": "remove", "path": _path(["effects", 1])})
	_change("Nested dictionary entry added", "interaction", {"operation": "add", "path": _path(["arguments", "unused"]), "key": Values.segment("new"), "value_type": "Dictionary", "value_text": "{}"})
	_change("Nested key renamed", "interaction", {"operation": "rename", "path": _path(["arguments", "unused", "new"]), "key": Values.segment(&"renamed")})
	_change("Array item appended", "interaction", {"operation": "add", "path": _path(["arguments", "unused", "items"]), "value_type": "StringName", "value_text": "second"})
	_change("Maximum integer edited", "interaction", {"operation": "set", "path": _path(["arguments", "unused", "precise"]), "value_type": "int", "value_text": "-9223372036854775808"})
	_change("StringName value edited", "interaction", {"operation": "set", "path": _path(["arguments", "unused", &"name"]), "value_type": "StringName", "value_text": "updated"})
	_change("Typed array append succeeds", "interaction", {"operation": "add", "path": _path(["arguments", "unused", "typed"]), "value_type": "int", "value_text": "3"})
	_reject("Typed array rejects text", "interaction", {"operation": "add", "path": _path(["arguments", "unused", "typed"]), "value_type": "String", "value_text": "bad"})
	_reject("Duplicate dictionary keys are rejected", "interaction", {"operation": "rename", "path": _path(["arguments", "unused", "precise"]), "key": Values.segment("items")})
	_reject("Malformed path is rejected", "interaction", {"operation": "remove", "path": [42]})
	_change("Array item removed", "interaction", {"operation": "remove", "path": _path(["arguments", "unused", "items", 0])})
	_change("Nested dictionary removed", "interaction", {"operation": "remove", "path": _path(["arguments", "unused", &"renamed"])})
	_change("Condition numeric value edited", "condition", {"operation": "set", "path": _path(["requirement", "value"]), "value_type": "float", "value_text": "25.5"})
	_reject("Condition rejects text comparisons", "condition", {"operation": "set", "path": _path(["requirement", "value"]), "value_type": "String", "value_text": "25"})
	_reject("Condition operator is validated", "condition", {"operation": "set", "path": _path(["requirement", "operator"]), "value_type": "String", "value_text": "contains"})
	_reject("Required condition keys are protected", "condition", {"operation": "remove", "path": _path(["requirement", "path"])})
	_change("Optional message can be removed", "condition", {"operation": "remove", "path": _path(["requirement", "message"])})
	var before_stale := _request(_sources["interaction"], {"operation": "set", "path": _path(["arguments", &"amount"]), "value_type": "int", "value_text": "-5"})
	_change("A newer edit succeeds", "interaction", {"operation": "set", "path": _path(["arguments", &"amount"]), "value_type": "int", "value_text": "-7"})
	var hash_before := FileAccess.get_sha256(_sources["interaction"])
	_check("Stale inspection is rejected without a write", not Editing.edit(_sources["interaction"], before_stale)["ok"] and FileAccess.get_sha256(_sources["interaction"]) == hash_before)
	var membership := _request(_sources["interaction"], {"operation": "set", "path": _path(["arguments", &"amount"]), "value_type": "int", "value_text": "-5"})
	var another := Schema.Group.new()
	another.id = &"new_catalog_member"
	_save("new_member", another)
	_check("New catalogue members invalidate inspected edits", not Editing.edit(_sources["interaction"], membership)["ok"] and FileAccess.get_sha256(_sources["interaction"]) == hash_before)
	var current := _load("interaction") as Schema.Interaction
	var unused: Dictionary = current.arguments["unused"]
	_check("Multiline Unicode and native references survive", unused["text"] == "雪\n  line\r\n\tend" and unused["vector"] == Vector2(2, 3) and unused["reference"].resource_path == "res://Games/ExampleGame/Tiles/ground.svg")
	_check("Native integer, StringName and typed array values survive", unused["precise"] == -9223372036854775808 and typeof(unused[&"name"]) == TYPE_STRING_NAME and unused["typed"].get_typed_builtin() == TYPE_INT and unused["typed"] == [1, 2, 3])
	_check("Runtime conversion uses saved edits", current.to_definition()["arguments"][&"amount"] == -7)
	_check("Authoring edits preserve the custom behavior ID", current.action.behavior_id == &"diagnostic_effects" and current.action.to_definition()["behavior_id"] == &"diagnostic_effects")
	var runtime := RuntimeCore.new()
	runtime.define_attributes(&"actor", {&"interactions": {"available": [current.id]}})
	runtime.define_attributes(&"target", {&"health": {"current": 100}})
	_check("Saved custom behavior registers before its action", runtime.register_executor(&"diagnostic_effects", AttributeEffects.new())["ok"])
	_check("Saved action registers with its custom behavior", runtime.define_action(current.action.to_definition())["ok"])
	runtime.define_interaction(current.to_definition())
	var executed := runtime.interact(current.id, runtime.spawn(&"actor"), runtime.spawn(&"target"))
	_check("Saved structural edits execute through the gameplay runtime", executed["ok"] and executed["value"] == [93])
	runtime.close()


func _save(name: String, resource: Resource) -> Resource:
	var path := _folder.path_join(name + ".tres")
	if ResourceSaver.save(resource, path) != OK:
		_check("Fixture saved: " + name, false)
		return null
	ResourceSaver.set_uid(path, ResourceUID.create_id())
	_sources[name] = path
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)


func _load(name: String) -> Resource:
	return ResourceLoader.load(_sources[name], "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)


func _request(path: String, operation: Dictionary) -> Dictionary:
	var inspected := Inspection.graph(path)
	if not inspected["ok"]:
		_check("Inspection before edit", false)
		print(inspected)
		return operation
	var request := operation.duplicate(true)
	request["executor_snapshot"] = inspected["value"]["executor_snapshot"]
	request["expected_hashes"] = inspected["value"]["dependency_hashes"]
	request["catalog_paths"] = inspected["value"]["catalog_paths"]
	request["catalog_seed"] = path
	return JSON.parse_string(JSON.stringify(request))


func _change(label: String, name: String, operation: Dictionary) -> void:
	var path: String = _sources[name]
	var uid := Files.resource_uid(path)
	var result := Editing.edit(path, _request(path, operation))
	_check(label, result["ok"])
	if not result["ok"]:
		print(result)
	_check("UID preserved", uid == Files.resource_uid(path))


func _reject(label: String, name: String, operation: Dictionary) -> void:
	var path: String = _sources[name]
	var before := FileAccess.get_sha256(path)
	var result := Editing.edit(path, _request(path, operation))
	_check(label, not result["ok"] and FileAccess.get_sha256(path) == before)


func _path(parts: Array) -> Array:
	var output := []
	for part in parts:
		output.append(Values.segment(part, part is int))
	return output


func _find(node: Dictionary, path: Array) -> Dictionary:
	if node["path"] == path:
		return node
	for child in node["children"]:
		var found := _find(child, path)
		if not found.is_empty():
			return found
	return {}


func _check(label: String, condition: bool) -> void:
	_passed = _passed and condition
	print("[behavior-editing] ", label, ": ", condition)
