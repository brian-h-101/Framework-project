extends SceneTree

const Inspection = preload("res://Framework/Env/Authoring/Resources/Inspection/behavior_inspection.gd")
const Editing = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_editing.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Behavior = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd")
const Config = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_configuration_resource.gd")

var passed := true
var path := ""

func check(label: String, valid: bool) -> void:
	print("[sequence-editing] %s: %s" % [label, valid])
	passed = passed and valid

func edit(request: Dictionary) -> Dictionary:
	var inspected := Inspection.graph(path)
	if not inspected["ok"]:
		return inspected
	var graph: Dictionary = inspected["value"]
	request.merge({"expected_hashes": graph["dependency_hashes"], "catalog_paths": graph["catalog_paths"], "catalog_seed": path, "executor_snapshot": graph["executor_snapshot"]})
	return Editing.edit(path, request)

func _initialize() -> void:
	var folder := "res://.godot/diagnostics/sequence_" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(folder)
	path = folder.path_join("behavior.tres")
	var resource := Behavior.new()
	resource.id = &"editing_probe"
	resource.configuration = Config.new()
	check("Empty Behavior saved", ResourceSaver.save(resource, path) == OK)
	var uid := ResourceUID.create_id()
	ResourceSaver.set_uid(path, uid)
	var shared := "res://Framework/Content/Behavior/Condition/actor_strength.tres"
	var shared_hash := FileAccess.get_sha256(shared)
	check("Group added", edit({"operation": "sequence_add", "step_id": "", "step_kind": "group", "new_id": "strong_attack", "label": "Strong Attack"})["ok"])
	check("Nested Action and typed arguments added", edit({"operation": "sequence_add", "step_id": "strong_attack", "step_kind": "action", "new_id": "damage", "label": "Damage", "executor_id": "change_health", "arguments": [{"name": "amount", "value_type": "int", "value_text": "-10"}]})["ok"])
	check("Typed nested argument container added", edit({"operation": "add", "step_id": "damage", "path": [{"kind": "String", "text": "arguments"}], "key": {"kind": "StringName", "text": "settings"}, "value_type": "Dictionary", "value_text": "{}"})["ok"])
	check("Typed nested argument value added", edit({"operation": "add", "step_id": "damage", "path": [{"kind": "String", "text": "arguments"}, {"kind": "StringName", "text": "settings"}], "key": {"kind": "StringName", "text": "enabled"}, "value_type": "bool", "value_text": "true"})["ok"])
	check("Executor edits preserve unselected nested arguments", edit({"operation": "sequence_executor", "step_id": "damage", "executor_id": "change_health", "arguments": [{"name": "amount", "value_type": "int", "value_text": "-10"}]})["ok"] and ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP).steps[0].steps[0].arguments[&"settings"][&"enabled"] == true)
	check("Shared condition assigned", edit({"operation": "sequence_condition", "step_id": "damage", "condition_path": shared})["ok"])
	var inspected := Inspection.graph(path)
	check("Virtual hierarchy belongs to one file", inspected["ok"] and inspected["value"]["nodes"].size() == 1 and inspected["value"]["nodes"][path]["data"]["children"][1]["label"] == "Steps [SEQUENCE]")
	check("Boolean inline requirement added", edit({"operation": "sequence_condition", "step_id": "strong_attack", "condition_id": "alive", "requirement": {"entity": "target", "container": "health", "path": ["alive"], "operator": "==", "value_type": "bool", "value_text": "true"}})["ok"])
	check("Nested label renamed", edit({"operation": "sequence_rename", "step_id": "damage", "label": "Damage Renamed"})["ok"])
	check("Second sibling added", edit({"operation": "sequence_add", "step_id": "strong_attack", "step_kind": "group", "new_id": "critical", "label": "Critical Effect"})["ok"])
	check("Authored sibling order changes", edit({"operation": "sequence_move", "step_id": "critical", "direction": -1})["ok"])
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check("Embedded values, order and references survive reload", loaded.steps[0].steps[0].id == &"critical" and loaded.steps[0].steps[1].id == &"damage" and loaded.steps[0].steps[1].arguments[&"amount"] == -10 and loaded.steps[0].steps[1].requirements.conditions[0].resource_path == shared)
	check("Configuration editable", edit({"operation": "sequence_configure", "field": "targeting", "value_type": "String", "value_text": "selected"})["ok"])
	var hash := FileAccess.get_sha256(path)
	check("Duplicate step rejected without publishing", not edit({"operation": "sequence_add", "step_kind": "group", "new_id": "damage", "label": "Duplicate"})["ok"] and FileAccess.get_sha256(path) == hash)
	check("Bad executor arguments preserve file", not edit({"operation": "sequence_executor", "step_id": "damage", "executor_id": "change_health", "arguments": [{"name": "amount", "value_type": "String", "value_text": "bad"}]})["ok"] and FileAccess.get_sha256(path) == hash)
	check("Boolean ordering is rejected", not edit({"operation": "sequence_condition", "step_id": "damage", "condition_id": "bad_bool", "requirement": {"entity": "target", "container": "health", "path": ["alive"], "operator": ">", "value_type": "bool", "value_text": "true"}})["ok"] and FileAccess.get_sha256(path) == hash)
	check("Condition unlinked without changing shared file", edit({"operation": "sequence_remove_condition", "step_id": "damage", "condition_index": 0})["ok"] and FileAccess.get_sha256(shared) == shared_hash)
	check("Nested Group removed", edit({"operation": "sequence_remove", "step_id": "critical"})["ok"])
	check("UID preserved through all edits", Files.resource_uid(path) == uid)
	var stale: Dictionary = Inspection.graph(path)["value"]
	var request := {"operation": "sequence_rename", "step_id": "damage", "label": "Stale", "expected_hashes": stale["dependency_hashes"], "catalog_paths": stale["catalog_paths"], "catalog_seed": path, "executor_snapshot": stale["executor_snapshot"]}
	check("Another edit succeeds", edit({"operation": "sequence_rename", "step_id": "damage", "label": "Current"})["ok"])
	hash = FileAccess.get_sha256(path)
	check("Stale edit rejected", not Editing.edit(path, request)["ok"] and FileAccess.get_sha256(path) == hash)
	check("Temporary Resource removed", DirAccess.remove_absolute(path) == OK)
	check("Temporary directory removed", DirAccess.remove_absolute(folder) == OK)
	print("[sequence-editing] Checks passed: %s" % passed)
	quit(0 if passed else 1)
