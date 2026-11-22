extends SceneTree

const Setup = preload("res://Diagnostics/Fixtures/Setup/executor_authoring_setup.gd")
const Runtime = preload("res://Framework/Infrastructure/API/Runtime/game_runtime.gd")
const Core = preload("res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd")
const Executor = preload("res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd")
const Schema = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_schema.gd")
const Inspection = preload("res://Framework/Env/Authoring/Resources/Inspection/behavior_inspection.gd")
const Editing = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_editing.gd")
const Assignment = preload("res://Framework/Env/Authoring/Resources/Conditions/condition_assignment.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")

class MetadataExecutor extends Executor:
	var metadata: Dictionary = {}
	func describe() -> Dictionary:
		return metadata

var _passed := true
var _folder := ""
var _probe_folder := ""
var _setup := Setup.new()


func _initialize() -> void:
	Schema.Executors.use_setup(_setup)
	var suffix := Crypto.new().generate_random_bytes(8).hex_encode()
	_folder = "res://.godot/diagnostics/executor_authoring_" + suffix
	_probe_folder = "res://Diagnostics/ExecutorMetadata_" + suffix
	if DirAccess.make_dir_recursive_absolute(_folder) != OK or DirAccess.make_dir_absolute(_probe_folder) != OK:
		quit(1)
		return
	_write(_probe_folder.path_join("probe.gd"), "extends RefCounted\n")
	_runtime_checks()
	_authoring_checks()
	for folder in [_folder, _probe_folder]:
		var directory := DirAccess.open(folder)
		for name in directory.get_files():
			_check("Owned fixture removed: " + name, DirAccess.remove_absolute(folder.path_join(name)) == OK)
		_check("Owned fixture folder removed", DirAccess.remove_absolute(folder) == OK)
	Schema.Executors.use_setup(null)
	print("[executor-authoring] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _runtime_checks() -> void:
	var runtime := Runtime.new(Core.new())
	_check("Custom metadata registers", _setup.register_executors(runtime)["ok"])
	var catalogue := runtime.executor_catalogue()
	_check("Cataloguing never executes gameplay", catalogue["ok"] and _setup.health.calls == 0)
	catalogue["value"][0]["arguments"].append({"name": "changed"})
	_check("Catalogue callers own independent data", runtime.executor_catalogue()["value"] != catalogue["value"])
	for metadata in [{"supports_effects": "yes"}, {"arguments": [{"name": "a", "allowed_types": ["Node"]}]},
		{"arguments": [{"name": "a", "allowed_types": ["int"]}, {"name": "a", "allowed_types": ["int"]}]},
		{"arguments": [{"name": "a", "allowed_types": ["Variant", "int"]}]}]:
		var executor := MetadataExecutor.new()
		executor.metadata = metadata
		_check("Invalid metadata cannot register", not runtime.register_executor(&"invalid", executor)["ok"] and not runtime.has_executor(&"invalid"))
	var action := {"id": &"health", "behavior_id": &"direct_health", "effects": []}
	_check("Custom behavior accepts an effect-free action", runtime.define_action(action)["ok"])
	var effect := {"entity": &"target", "operation": &"add", "container": &"health", "path": ["current"], "value_from": &"amount"}
	_check("Unsupported effects fail runtime registration", not runtime.define_action({"id": &"bad", "behavior_id": &"direct_health", "effects": [effect]})["ok"])
	var interaction := {"id": &"health", "action": &"health", "arguments": {&"amount": 27}}
	_check("Optional argument can be omitted", runtime.define_interaction(interaction)["ok"])
	for arguments in [{}, {&"amount": "bad"}, {&"amount": INF}, {&"amount": 20, &"note": &"wrong_type"}]:
		var rejected := interaction.duplicate(true)
		rejected["arguments"] = arguments
		_check("Bad required or optional argument rejects without execution", not runtime.define_interaction(rejected)["ok"] and _setup.health.calls == 0)
	_check("Action replacement protects existing consumers", not runtime.define_action({"id": &"health", "behavior_id": &"named"})["ok"])
	runtime.define_attributes(&"fixture", {&"health": {"current": 100}, &"interactions": {"available": [&"health"]}})
	var actor := runtime.spawn(&"fixture")
	var target := runtime.spawn(&"fixture")
	var executed := runtime.interact(&"health", actor, target)
	_check("Typed custom behavior executes through the registry", executed["ok"] and _setup.health.calls == 1 and runtime.read_attribute(target, &"health", ["current"])["value"] == 27)
	interaction["arguments"][&"note"] = "optional"
	_check("Correct optional argument is accepted", runtime.define_interaction(interaction)["ok"])
	runtime.close()
	_check("Closed runtime releases its metadata", not runtime.executor_catalogue()["ok"])
	var description := Schema.Executors.refresh()
	_check("Editor bootstrap runs no content, entities, or gameplay", description["ok"] and _setup.content_calls == 0 and _setup.entity_calls == 0 and _setup.health.calls == 0)


func _authoring_checks() -> void:
	var action := Schema.Action.new()
	action.id = &"authoring_action"
	var action_path := _save("action", action)
	var interaction := Schema.Interaction.new()
	interaction.id = &"authoring_interaction"
	interaction.action = load(action_path)
	interaction.arguments = {&"amount": 31}
	var interaction_path := _save("interaction", interaction)
	var uid := Files.resource_uid(action_path)
	var selected := _edit(action_path, {"operation": "set_behavior", "behavior_id": "direct_health"})
	_check("Behavior reassignment saves with its original UID", selected["ok"] and Files.resource_uid(action_path) == uid)
	var graph := Inspection.graph(interaction_path)
	_check("Graph exports behavior and typed optional arguments", graph["ok"] and graph["value"]["nodes"][action_path]["behavior_id"] == "direct_health" and graph["value"]["nodes"][interaction_path]["argument_specs"].size() == 2)
	_reject(action_path, {"operation": "set_behavior", "behavior_id": "named"}, "Behavior switch protects interaction consumers")
	_reject(action_path, {"operation": "set_behavior", "behavior_id": "unknown"}, "Unknown behavior rejects without writing")
	_reject(action_path, {"operation": "add_effect", "effect": {}}, "Unsupported effect field rejects without writing")
	var path := [{"kind": "String", "text": "arguments"}, {"kind": "StringName", "text": "amount"}]
	_reject(interaction_path, {"operation": "set", "path": path, "value_type": "String", "value_text": "bad"}, "Editor rejects the same argument type as runtime")
	_reject(interaction_path, {"operation": "remove", "path": path}, "Required argument removal rejects without writing")
	var stale := _request(action_path, {"operation": "set_behavior", "behavior_id": "attribute_effects"})
	var before := FileAccess.get_sha256(action_path)
	_write(_probe_folder.path_join("probe.gd"), "extends RefCounted\n# changed\n")
	_check("Changed executor sources invalidate pending edits", not Editing.edit(action_path, stale)["ok"] and FileAccess.get_sha256(action_path) == before)
	stale = _request(action_path, {"operation": "set_behavior", "behavior_id": "attribute_effects"})
	_write(_probe_folder.path_join("added.gd"), "extends RefCounted\n")
	_check("New source files invalidate pending edits", not Editing.edit(action_path, stale)["ok"] and FileAccess.get_sha256(action_path) == before)
	_check("Fresh inspection permits an edit after stale rejection", _edit(action_path, {"operation": "set_behavior", "behavior_id": "attribute_effects"})["ok"])
	action = ResourceLoader.load(action_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	action.behavior_id = &"missing_executor"
	ResourceSaver.save(action, action_path)
	graph = Inspection.graph(action_path)
	_check("Unknown behavior stays visible for repair", graph["ok"] and not graph["value"]["nodes"][action_path]["behavior_error"].is_empty())
	_check("Unknown behavior can be repaired through selection", _edit(action_path, {"operation": "set_behavior", "behavior_id": "direct_health"})["ok"])
	var named := Schema.Action.new()
	named.id = &"named_action"
	named.behavior_id = &"named"
	var named_path := _save("named", named)
	before = FileAccess.get_sha256(interaction_path)
	_check("Action assignment checks the selected executor arguments", not Assignment.set_action(interaction_path, named_path)["ok"] and FileAccess.get_sha256(interaction_path) == before)


func _request(source: String, operation: Dictionary) -> Dictionary:
	var inspected := Inspection.graph(source)
	if not inspected["ok"]:
		_check("Resource inspection succeeds", false)
		print(inspected)
		return {}
	var graph: Dictionary = inspected["value"]
	var request := operation.duplicate(true)
	request.merge({"expected_hashes": graph["dependency_hashes"], "catalog_paths": graph["catalog_paths"],
		"catalog_seed": source, "executor_snapshot": graph["executor_snapshot"]})
	return JSON.parse_string(JSON.stringify(request))


func _edit(source: String, operation: Dictionary) -> Dictionary:
	return Editing.edit(source, _request(source, operation))


func _reject(source: String, operation: Dictionary, label: String) -> void:
	var before := FileAccess.get_sha256(source)
	_check(label, not _edit(source, operation)["ok"] and FileAccess.get_sha256(source) == before)


func _save(name: String, resource: Resource) -> String:
	var path := _folder.path_join(name + ".tres")
	_check("Fixture saved: " + name, ResourceSaver.save(resource, path) == OK)
	ResourceSaver.set_uid(path, ResourceUID.create_id())
	return path


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _check(label: String, passed: bool) -> void:
	_passed = _passed and passed
	print("[executor-authoring] ", label, ": ", passed)
