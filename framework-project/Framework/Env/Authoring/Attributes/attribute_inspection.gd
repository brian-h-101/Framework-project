extends RefCounted

const FragmentResource = preload("res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd")
const Values = preload("res://Framework/Env/Authoring/Attributes/attribute_values.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const ValueTree = preload("res://Framework/Env/Authoring/Shared/value_tree.gd")


static func inspect(path: String) -> Dictionary:
	var checked := check_path(path)
	if not checked["ok"]:
		return checked
	var before := FileAccess.get_sha256(path)
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		return Values.failure("Could not load Resource: %s" % path)
	if FileAccess.get_sha256(path) != before:
		return Values.failure("The resource file changed while reading. Refresh and try again.")
	if not resource is FragmentResource:
		return Values.success({
			"version": 1, "source_path": path, "content_hash": before,
			"supported": false, "root": null,
		})
	return describe(path, before, resource.containers)


static func describe(path: String, content_hash: String, containers: Dictionary) -> Dictionary:
	var error := FragmentResource.container_error(containers)
	if not error.is_empty():
		return Values.failure(error)
	var state := {"count": 0, "error": ""}
	var root := ValueTree.build(containers, [], path.get_file(), true, state, 2)
	if not String(state["error"]).is_empty():
		return Values.failure(state["error"])
	return Values.success({
		"version": 1, "source_path": path, "content_hash": content_hash,
		"supported": true, "root": root,
	})


static func check_path(path: String) -> Dictionary:
	return Files.check_path(path)


static func resource_uid(path: String) -> int:
	return Files.resource_uid(path)
