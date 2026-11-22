extends RefCounted

const Schema = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_schema.gd")
const Library = preload("res://Framework/Env/Authoring/Resources/Library/behavior_library.gd")
const Files = preload("res://Framework/Env/Authoring/Shared/resource_files.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const InteractionContent = preload("res://Framework/Env/Setup/Definitions/interactions.gd")
const Executors = preload("res://Framework/Env/Authoring/Resources/Inspection/executor_catalog.gd")
const StartingPresets = preload("res://Framework/Env/Authoring/Resources/Presentation/starting_preset_authoring.gd")
const Configurations = preload("res://Framework/Env/Authoring/Resources/Configuration/configuration_inspection.gd")


static func browse(selected: String) -> Dictionary:
	# Browsing follows only this Resource's dependencies. Full inspection remains
	# the authority for edits and retains all catalogue/source snapshot guards.
	var checked := Files.check_path(selected)
	if not checked["ok"]:
		return checked
	var hashes := {}
	checked = Library._hash_resources(selected, hashes, 0)
	if not checked["ok"]:
		return checked
	var resource := ResourceLoader.load(selected, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if resource == null:
		return Values.failure("Could not load the selected Resource: " + selected)
	if Configurations.supports(selected, resource):
		return Configurations.graph(selected, resource, hashes, true)
	if StartingPresets.supports(selected, resource):
		return StartingPresets.graph(selected, resource, hashes, true)
	if Schema.kind(resource).is_empty():
		return Values.success({"version": 2, "mode": "browse", "supported": false, "source_path": selected,
			"roots": [], "nodes": {}, "dependency_hashes": {selected: hashes[selected]}, "catalog_paths": []})
	var catalogue := Executors.begin_browse()
	if not catalogue["ok"]:
		Executors.end_browse()
		return catalogue
	var nodes := {}
	var error := _collect(resource, nodes, hashes, 0)
	Executors.end_browse()
	if not error.is_empty():
		return Values.failure(error)
	checked = Files.check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked
	return Values.success({"version": 2, "mode": "browse", "roots": [selected], "nodes": nodes,
		"dependency_hashes": hashes, "catalog_paths": [], "executors": catalogue["value"]["executors"]})


static func graph(selected: String = "") -> Dictionary:
	if not selected.is_empty():
		var checked := Files.check_path(selected)
		if not checked["ok"]:
			return checked
		var before := FileAccess.get_sha256(selected)
		var resource := ResourceLoader.load(selected, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if resource == null:
			return Values.failure("Could not load the selected Resource: " + selected)
		if FileAccess.get_sha256(selected) != before:
			return Values.failure("Resource changed during inspection: %s. Refresh and retry." % selected)
		if Configurations.supports(selected, resource):
			var hashes := {}
			checked = Library._hash_resources(selected, hashes, 0)
			if not checked["ok"]:
				return checked
			resource = ResourceLoader.load(selected, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			return Configurations.graph(selected, resource, hashes, false)
		if StartingPresets.supports(selected, resource):
			var hashes := {}
			checked = Library._hash_resources(selected, hashes, 0)
			if not checked["ok"]:
				return checked
			resource = ResourceLoader.load(selected, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			if not StartingPresets.supports(selected, resource):
				return Values.failure("The starting attributes Resource changed. Refresh and retry.")
			return StartingPresets.graph(selected, resource, hashes, false)
		if Schema.kind(resource).is_empty():
			return Values.success({"version": 2, "supported": false, "source_path": selected,
				"roots": [], "nodes": {}, "dependency_hashes": {selected: before}, "catalog_paths": []})
	var executors := Executors.refresh()
	if not executors["ok"]:
		return executors
	var loaded := Library.load_library(selected)
	if not loaded["ok"]:
		return loaded
	var library: Dictionary = loaded["value"]
	var roots: Array[String] = []
	if selected.is_empty():
		var discovered := InteractionContent.definitions()
		if not discovered["ok"]:
			return discovered
		for path in discovered["sources"].values():
			roots.append(String(path))
		roots.sort()
	else:
		roots.append(selected)
	var nodes := {}
	var hashes: Dictionary = library["hashes"]
	for path in roots:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var error := _collect(resource, nodes, hashes, 0)
		if not error.is_empty():
			return Values.failure(error)
	var checked := Files.check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked
	checked = Executors.unchanged(executors["value"]["executor_snapshot"])
	if not checked["ok"]:
		return checked
	return Values.success({"version": 2, "roots": roots, "nodes": nodes, "dependency_hashes": hashes, "catalog_paths": Array(library["paths"]),
		"executors": executors["value"]["executors"], "executor_snapshot": executors["value"]["executor_snapshot"]})


static func _collect(resource: Resource, nodes: Dictionary, hashes: Dictionary, depth: int) -> String:
	if resource == null:
		return "Missing required behavior Resource reference."
	var path := resource.resource_path
	var checked := Files.check_path(path)
	if not checked["ok"]:
		return checked["error"]
	if nodes.has(path):
		return ""
	if depth > 64 or nodes.size() > 10000:
		return "Behavior graph exceeds 64 levels or 10000 Resources."
	var kind := Schema.kind(resource)
	if kind.is_empty() or String(resource.id).is_empty():
		return "Unsupported behavior Resource or empty authored ID: %s." % path
	if not hashes.has(path) or FileAccess.get_sha256(path) != hashes[path]:
		return "Resource changed during inspection: %s. Refresh and retry." % path
	var tree := Schema.tree(resource)
	if not tree["ok"]:
		return tree["error"]
	var record := {"id": String(resource.id), "kind": kind, "source_path": path, "content_hash": hashes[path], "links": [], "data": tree["value"]}
	nodes[path] = record
	if resource is Schema.Action:
		record["behavior_id"] = String(resource.behavior_id)
		var description := Executors.describe(resource.behavior_id)
		record["supports_effects"] = description.get("ok", false) and description["value"]["supports_effects"]
		var prepared := Executors.arguments_for(resource)
		record["argument_specs"] = prepared["value"] if prepared["ok"] else []
		record["behavior_error"] = "" if prepared["ok"] else prepared["error"]
	elif resource is Schema.Interaction and resource.action != null:
		var prepared := Executors.arguments_for(resource.action)
		record["argument_specs"] = prepared["value"] if prepared["ok"] else []
	var links: Array[Dictionary] = []
	if resource is Schema.Automation:
		if resource.interaction == null:
			return "Missing Interaction reference in %s" % path
		links.append({"role": "interaction", "resource": resource.interaction, "index": -1})
	elif resource is Schema.Interaction:
		if resource.action == null:
			return "Missing action reference in %s" % path
		links.append({"role": "action", "resource": resource.action, "index": -1})
		if resource.requirements != null:
			links.append({"role": "requirements", "resource": resource.requirements, "index": -1})
	elif resource is Schema.Group:
		record["operator"] = String(Schema.Group.OPERATOR)
		for index in resource.conditions.size():
			links.append({"role": "condition", "resource": resource.conditions[index], "index": index})
	elif resource is Schema.Condition:
		record["operator"] = str(resource.requirement.get("operator", ""))
		record["value_text"] = Values.value_text(resource.requirement.get("value"))
	for link in links:
		var error := _collect(link["resource"], nodes, hashes, depth + 1)
		if not error.is_empty():
			return error
		record["links"].append({"role": link["role"], "target": link["resource"].resource_path, "index": link["index"]})
	return ""
