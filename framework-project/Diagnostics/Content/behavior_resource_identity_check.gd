extends SceneTree

const Schema = preload("res://Framework/Env/Authoring/Resources/behavior_schema.gd")
const Assignment = preload("res://Framework/Env/Authoring/Resources/condition_assignment.gd")
const Editing = preload("res://Framework/Env/Authoring/Resources/condition_editing.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")


func _initialize() -> void:
	var folder := "res://.godot/diagnostics/behavior_identity_" + Crypto.new().generate_random_bytes(8).hex_encode()
	if DirAccess.dir_exists_absolute(folder) or DirAccess.make_dir_recursive_absolute(folder) != OK:
		quit(1)
		return
	var action_path := "res://Framework/Content/Behavior/Action/change_health.tres"
	var replacement_path := "res://Framework/Content/Behavior/Action/drag_check_action.tres"
	var condition := Schema.Condition.new()
	condition.id = &"identity_condition"
	condition.requirement = {"entity": &"actor", "container": &"health", "path": ["current"], "operator": ">=", "value": 10}
	var group := Schema.Group.new()
	group.id = &"identity_group"
	var interaction := Schema.Interaction.new()
	interaction.id = &"identity_interaction"
	interaction.action = load(action_path)
	interaction.arguments = {&"amount": -10}
	var resources := {"condition": condition, "group": group, "interaction": interaction}
	var uids := {}
	var passed := true
	for name: String in resources:
		var path := folder.path_join(name + ".tres")
		var uid := ResourceUID.create_id()
		passed = ResourceSaver.save(resources[name], path, ResourceSaver.FLAG_CHANGE_PATH) == OK and passed
		passed = ResourceSaver.set_uid(path, uid) == OK and passed
		uids[name] = uid
		var text := Files.format(FileAccess.get_file_as_string(path), true)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			passed = false
		else:
			file.store_string(text)
			file.close()
	if passed:
		var checks := [
			Assignment.add_condition(folder.path_join("group.tres"), folder.path_join("condition.tres")),
			Editing.set_comparison(folder.path_join("condition.tres"), ">=", 20, "Requires health."),
			Assignment.set_requirements(folder.path_join("interaction.tres"), folder.path_join("group.tres")),
			Assignment.set_action(folder.path_join("interaction.tres"), replacement_path),
		]
		for index in checks.size():
			var result: Dictionary = checks[index]
			print("[behavior-identity] ", ["Add condition", "Edit comparison", "Set requirements", "Replace action"][index], ": ", result["ok"])
			if not result["ok"]:
				print("[behavior-identity] Rejected operation: ", result["error"])
			passed = result["ok"] and passed
	for name: String in resources:
		var path := folder.path_join(name + ".tres")
		var text := FileAccess.get_file_as_string(path)
		passed = Files.resource_uid(path) == uids[name] and passed
		print("[behavior-identity] ", name, " UID: ", Files.resource_uid(path) == uids[name])
		passed = not text.replace("\r\n", "").contains("\n") and passed
		passed = DirAccess.remove_absolute(path) == OK and passed
	passed = DirAccess.remove_absolute(folder) == OK and passed
	print("[behavior-identity] Assignments and comparison edits preserve UIDs and CRLF: ", passed)
	print("[behavior-identity] Checks passed: ", passed)
	quit(0 if passed else 1)
