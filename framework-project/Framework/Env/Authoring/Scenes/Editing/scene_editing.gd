extends RefCounted
const UnifiedBehavior = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd")
const UNIFIED_SCRIPT = "res://Framework/Content/Universal/Interaction/based/Bindings/behavior_binding.gd"
const AutomationResource = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Automation/automation_resource.gd")
const AUTOMATION_SCRIPT = "res://Framework/Content/Universal/Interaction/based/Legacy/automation_behavior.gd"

const Document = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_document.gd")
const SceneGraph = preload("res://Framework/Env/Authoring/Scenes/Inspection/scene_graph.gd")
const References = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_references.gd")
const SceneScript = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_script.gd")
const SceneProperties = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_properties.gd")
const LayoutBuilder = preload("res://Framework/Env/Authoring/Scenes/Creation/scene_layout_builder.gd")
const MovementCatalog = preload(
	"res://Framework/Env/Authoring/Scenes/Configuration/movement_configuration_catalog.gd"
)
const ControllerCatalog = preload(
	"res://Framework/Env/Authoring/Scenes/Configuration/movement_controller_catalog.gd"
)
const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Interactions/interaction_resource.gd"
)
const BEHAVIOR_SCRIPT = (
	"res://Framework/Content/Universal/Interaction/based/Legacy/interaction_behavior.gd"
)
const ADD_OPERATIONS = [
	"add_node",
	"add_instance",
	"attach_behavior",
]
const MAX_BYTES = 8 * 1024 * 1024
const SCRIPT_OPERATIONS = ["attach_script", "remove_script"]
const MOVEMENT_OPERATIONS = ["assign_movement", "assign_movement_controller"]


static func node_types() -> Dictionary:
	var types: Array[String] = []
	for native_type in ClassDB.get_class_list():
		if _allowed_type(native_type):
			types.append(String(native_type))
	types.sort()
	return Document.success(types)


static func node_properties(scene_path: String, path: String) -> Dictionary:
	var checked := _check_path(scene_path)
	if not checked["ok"]:
		return checked
	var inspected := SceneGraph.read(scene_path)
	if not inspected["ok"]:
		return inspected
	var node: Dictionary = inspected["value"]["nodes"].get(path, {})
	if node.is_empty() or not SceneProperties.can_edit(node, scene_path):
		return Document.failure("Choose a locally declared node to set its properties.")
	return SceneProperties.inspect(scene_path, path, node["type"])


static func edit(scene_path: String, request: Dictionary) -> Dictionary:
	var checked := _check_path(scene_path)
	if not checked["ok"]:
		return checked
	var hashes: Variant = request.get("expected_hashes")
	if not hashes is Dictionary:
		return Document.failure("Scene edits require dependency hashes from the inspected graph.")
	if not hashes.has(scene_path):
		return Document.failure("The selected scene must be included in the inspected dependency hashes.")
	var unchanged := _check_hashes(hashes, hashes)
	if not unchanged["ok"]:
		return unchanged
	var current := SceneGraph.read(scene_path)
	if not current["ok"]:
		return current
	var graph: Dictionary = current["value"]
	var guarded := _check_hashes(hashes, graph["dependency_hashes"])
	if not guarded["ok"]:
		return guarded
	var operation: Variant = request.get("operation")
	var path: Variant = request.get("path")
	if (
		operation not in ADD_OPERATIONS + ["rename", "remove", "set_property"] + SCRIPT_OPERATIONS + MOVEMENT_OPERATIONS
		or not path is String
		or not graph["nodes"].has(path)
	):
		return Document.failure("Choose a current scene node and a supported structural operation.")
	var capability: String = "can_add" if operation in ADD_OPERATIONS else "can_" + String(operation)
	if operation in MOVEMENT_OPERATIONS:
		capability = "can_assign_movement"
	var target_node: Dictionary = graph["nodes"][path]
	var permitted: bool = (
		SceneProperties.can_edit(target_node, scene_path)
		if operation == "set_property"
		else target_node[capability]
	)
	if not permitted:
		if operation == "set_property":
			return Document.failure("Choose a locally declared node to set its properties.")
		if operation == "attach_script" and graph["nodes"][path]["has_script"]:
			return Document.failure("This node already has an attached script. Remove it before attaching another.")
		if operation == "remove_script":
			return Document.failure("Choose a node with a locally declared script. Inherited scripts are edited in their declaring scene.")
		return Document.failure("This node's structure belongs to %s. Open that scene to edit it; the scene root cannot be renamed or removed." % graph["nodes"][path]["structural_scene"])
	var source := FileAccess.get_file_as_string(scene_path)
	var parsed := Document.parse(source)
	if not parsed["ok"]:
		return parsed
	var document: Dictionary = parsed["value"]
	var new_path := ""
	var name := ""
	if operation not in ["remove", "set_property"] + SCRIPT_OPERATIONS + MOVEMENT_OPERATIONS:
		if not request.get("name") is String:
			return Document.failure("A node name is required.")
		name = request["name"]
		if name.is_empty() or name in [".", ".."] or name.validate_node_name() != name:
			return Document.failure("Choose a nonempty valid Godot node name.")
		var parent: String = path if operation in ADD_OPERATIONS else path.get_base_dir()
		new_path = name if parent in ["", "."] else parent.path_join(name)
		if graph["nodes"].has(new_path):
			return Document.failure("A sibling node already has that name: %s." % name)
	var edits: Array[Dictionary] = []
	var verification := {"operation": operation, "path": path, "new_path": new_path, "added_count": 0}
	var all_hashes: Dictionary = hashes.duplicate()
	if operation == "add_instance" and request.has("layout_path"):
		if not request["layout_path"] is String or not request.get("layout_hashes") is Dictionary:
			return Document.failure("Choose an inspected Layout Preset.")
		var layout := LayoutBuilder.resolve(request["layout_path"])
		if not layout["ok"]:
			return layout
		if layout["value"]["scene_path"] != request.get("instance_scene"):
			return Document.failure("The selected Layout Preset does not match the generated scene.")
		var layout_hashes: Dictionary = layout["value"]["dependency_hashes"]
		guarded = LayoutBuilder.verify_hashes(request["layout_hashes"], layout_hashes)
		if not guarded["ok"]:
			return guarded
		verification["layout_hashes"] = layout_hashes
	if operation == "set_property":
		var property_edit := SceneProperties.edit(document, request, path, target_node["type"])
		if not property_edit["ok"]:
			return property_edit
		edits.append(property_edit["value"]["edit"])
		verification["property_name"] = property_edit["value"]["name"]
		verification["property_value"] = property_edit["value"]["value"]
	elif operation in SCRIPT_OPERATIONS:
		var script_edit := _edit_script(document, graph, request, path)
		if not script_edit["ok"]:
			return script_edit
		edits.assign(script_edit["value"]["edits"])
		verification["script_path"] = script_edit["value"]["script_path"]
	elif operation in MOVEMENT_OPERATIONS:
		var assignment := _assign_movement(document, graph, request, path)
		if not assignment["ok"]:
			return assignment
		edits.assign(assignment["value"]["edits"])
		verification[assignment["value"]["target_field"]] = assignment["value"]["resource_path"]
	elif operation in ADD_OPERATIONS:
		var insertion: Dictionary

		if operation == "attach_behavior":
			insertion = _add_behavior(
				document, graph, request, path, name, new_path
			)
		else:
			insertion = _add(
				document, graph, request, path, name, new_path
			)
		if not insertion["ok"]:
			return insertion
		edits.assign(insertion["value"]["edits"])
		verification["added_count"] = insertion["value"]["added_count"]
		verification["added_nodes"] = insertion["value"]["added_nodes"]
		guarded = _check_hashes(hashes, insertion["value"]["instance_hashes"])
		if not guarded["ok"]:
			return guarded
	else:
		var referenced := References.rewrite(document, graph, path, new_path, operation == "remove")
		if not referenced["ok"]:
			return referenced
		edits.assign(referenced["value"]["edits"])
		all_hashes.merge(referenced["value"]["resource_hashes"])
		for section: Dictionary in document["sections"]:
			if section["tag"] != "node":
				continue
			var node_path := Document.node_path(section)
			if operation == "remove" and References.inside(node_path, path):
				edits.append({"start": section["start"], "end": section["end"], "text": ""})
			elif operation == "rename" and node_path == path:
				edits.append(Document.replacement(section["attributes"]["name"], JSON.stringify(name)))
	var updated := Document.apply(source, edits)
	if not updated["ok"]:
		return updated
	return _publish(scene_path, updated["value"], graph, all_hashes, verification)


static func _edit_script(document: Dictionary, graph: Dictionary, request: Dictionary, path: String) -> Dictionary:
	var attaching: bool = request["operation"] == "attach_script"
	var script_path := ""
	if attaching:
		if not request.get("script_path") is String:
			return Document.failure("Choose a project .gd script to attach.")
		script_path = request["script_path"]
	else:
		script_path = graph["nodes"][path]["script_path"]
	if not script_path.is_empty():
		var inspected := SceneScript.inspect(script_path, graph["nodes"][path]["type"])
		if not inspected["ok"]:
			return inspected
		var guarded := _check_hashes(request["expected_hashes"], inspected["value"]["dependency_hashes"])
		if not guarded["ok"]:
			return guarded
	elif attaching:
		return Document.failure("Choose a project .gd script to attach.")
	var target: Dictionary = {}
	var property: Dictionary = {}
	var resource_id := ""
	var used_ids := {}
	var resource_count := 1
	var declaration_offset: int = document["source"].length()
	for section: Dictionary in document["sections"]:
		if section["tag"] == "ext_resource":
			var id := Document.attribute(section, "id")
			used_ids[id] = true
			if Document.attribute(section, "path") == script_path and Document.attribute(section, "type") == "Script":
				resource_id = id
		if section["tag"] in ["ext_resource", "sub_resource"]:
			resource_count += 1
		if section["tag"] in ["sub_resource", "node"]:
			declaration_offset = mini(declaration_offset, section["start"])
		if section["tag"] == "node" and Document.node_path(section) == path:
			target = section
			for candidate: Dictionary in section["properties"]:
				if candidate["name"] == "script":
					if not property.is_empty():
						return Document.failure("The selected node has duplicate script properties.")
					property = candidate
	if target.is_empty():
		return Document.failure("Open the node’s structure source scene to edit its script.")
	var edits: Array[Dictionary] = []
	var newline := "\r\n" if String(document["source"]).get_slice("\n", 0).ends_with("\r") else "\n"
	if not attaching:
		if property.is_empty():
			return Document.failure("The script is declared in another scene. Open its source scene.")
		edits.append({"start": property["value_start"], "end": property["value_end"], "text": "null"})
		return Document.success({"edits": edits, "script_path": ""})
	if resource_id.is_empty():
		resource_id = "attached_script"
		while used_ids.has(resource_id):
			resource_id += "_"
		edits.append({"start": declaration_offset, "end": declaration_offset,
			"text": "[ext_resource type=\"Script\" path=%s id=%s]%s%s" % [JSON.stringify(script_path), JSON.stringify(resource_id), newline, newline]})
		if document["sections"][0]["attributes"].has("load_steps"):
			edits.append(Document.replacement(document["sections"][0]["attributes"]["load_steps"], str(resource_count + 1)))
	# Apply the script before any retained exported properties when instantiating.
	edits.append({"start": target["header_end"], "end": target["header_end"],
		"text": newline + "script = ExtResource(%s)" % JSON.stringify(resource_id)})
	if not property.is_empty():
		edits.append({"start": property["start"], "end": property["value_end"], "text": ""})
	return Document.success({"edits": edits, "script_path": script_path})


static func _assign_movement(document: Dictionary, graph: Dictionary, request: Dictionary, path: String) -> Dictionary:
	var assigning_controller: bool = request["operation"] == "assign_movement_controller"
	var property_name := "controller" if assigning_controller else "content"
	var request_field := "movement_controller" if assigning_controller else "movement_configuration"
	var target_field := "movement_controller_path" if assigning_controller else "movement_configuration_path"
	if not request.get(request_field) is String:
		return Document.failure("Choose a Movement resource for %s." % property_name)
	var resource_path: String = request[request_field]
	var inspected := ControllerCatalog.inspect(resource_path) if assigning_controller else MovementCatalog.inspect(resource_path)
	if not inspected["ok"]:
		return inspected
	var node: Dictionary = graph["nodes"][path]
	if not assigning_controller and inspected["value"]["body_type"] != node["type"]:
		return Document.failure("The movement environment is incompatible with %s." % node["type"])
	var required: Dictionary = inspected["value"]["dependency_hashes"].duplicate()
	required[node["script_path"]] = true
	var current_path: String = node[target_field]
	if not current_path.is_empty():
		required[current_path.get_slice("::", 0)] = true
	var guarded := _check_hashes(request["expected_hashes"], required)
	if not guarded["ok"]:
		return guarded
	if current_path == resource_path:
		return Document.failure("That movement resource is already assigned.")

	var target: Dictionary = {}
	var content: Dictionary = {}
	var resource_id := ""
	var used_ids := {}
	var resource_count := 1
	var declaration_offset: int = document["source"].length()
	for section: Dictionary in document["sections"]:
		if section["tag"] == "ext_resource":
			var id := Document.attribute(section, "id")
			used_ids[id] = true
			if Document.attribute(section, "path") == resource_path and Document.attribute(section, "type") == "Resource":
				resource_id = id
		if section["tag"] in ["ext_resource", "sub_resource"]:
			resource_count += 1
		if section["tag"] in ["sub_resource", "node"]:
			declaration_offset = mini(declaration_offset, section["start"])
		if section["tag"] == "node" and Document.node_path(section) == path:
			target = section
			for property: Dictionary in section["properties"]:
				if property["name"] == property_name:
					if not content.is_empty():
						return Document.failure("The movement body has duplicate %s properties." % property_name)
					content = property
	if target.is_empty():
		return Document.failure("Open the body’s structure source scene to assign movement.")
	var edits: Array[Dictionary] = []
	var newline := "\r\n" if String(document["source"]).get_slice("\n", 0).ends_with("\r") else "\n"
	if resource_id.is_empty():
		resource_id = "movement_" + property_name
		while used_ids.has(resource_id):
			resource_id += "_"
		edits.append({
			"start": declaration_offset, "end": declaration_offset,
			"text": "[ext_resource type=\"Resource\" path=%s id=%s]%s%s" % [
				JSON.stringify(resource_path), JSON.stringify(resource_id), newline, newline
			],
		})
		if document["sections"][0]["attributes"].has("load_steps"):
			edits.append(Document.replacement(
				document["sections"][0]["attributes"]["load_steps"], str(resource_count + 1)
			))
	var expression := "ExtResource(%s)" % JSON.stringify(resource_id)
	if content.is_empty():
		# Godot must attach the script before applying its exported content property.
		var offset: int = target["end"]
		var separator := "" if String(document["source"]).left(offset).ends_with("\n") else newline
		edits.append({"start": offset, "end": offset, "text": separator + property_name + " = " + expression + newline})
	else:
		edits.append({"start": content["value_start"], "end": content["value_end"], "text": expression})
	return Document.success({"edits": edits, "resource_path": resource_path, "target_field": target_field})


static func _add_behavior(
	document: Dictionary,
	graph: Dictionary,
	request: Dictionary,
	parent: String,
	name: String,
	new_path: String
) -> Dictionary:
	if not graph["nodes"][parent]["is_entity"]:
		return Document.failure("Choose an entity root for the behavior.")

	var unified := request.has("behavior_resource")
	var automated := request.has("automation_resource")
	var resource_value: Variant = request.get("behavior_resource") if unified else request.get("automation_resource") if automated else request.get("interaction_resource")
	if not resource_value is String:
		return Document.failure("Choose a Behavior, Interaction or Automation resource.")

	var resource_path: String = resource_value
	var behavior_script: String = UNIFIED_SCRIPT if unified else AUTOMATION_SCRIPT if automated else BEHAVIOR_SCRIPT
	var id_field := "behavior_id" if unified else "automation_id" if automated else "interaction_id"
	var path_field := "behavior_resource_path" if unified else "automation_resource_path" if automated else "interaction_resource_path"
	var checked := _check_path(resource_path, "tres")

	if not checked["ok"]:
		return checked

	var required := {}
	required[resource_path] = true
	required[behavior_script] = true

	var attached_ids := {}
	var pending: Array[String] = [parent]

	while not pending.is_empty():
		var current_path: String = pending.pop_back()
		var current: Dictionary = graph["nodes"][current_path]

		if current_path != parent and current["is_entity"]:
			continue

		var interaction_id: String = current[id_field]
		var attached_path: String = current[path_field]

		if not interaction_id.is_empty():
			attached_ids[interaction_id] = current_path

			if not attached_path.is_empty():
				required[attached_path.get_slice("::", 0)] = true

		pending.append_array(current["children"])

	checked = _check_hashes(request["expected_hashes"], required)
	if not checked["ok"]:
		return checked

	var loaded := ResourceLoader.load(
		resource_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP
	)

	if (unified and not loaded is UnifiedBehavior) or (not unified and automated and not loaded is AutomationResource) or (not unified and not automated and not loaded is InteractionResource):
		return Document.failure(
			"Expected the selected behavior Resource type: %s." % resource_path
		)

	if (automated or unified) and not loaded.read()["ok"]:
		return Document.failure(loaded.read()["error"])
	var interaction: Resource = loaded
	var interaction_id := String(interaction.id)

	if interaction_id.strip_edges().is_empty():
		return Document.failure("The Interaction resource requires an ID.")

	if attached_ids.has(interaction_id):
		return Document.failure(
			"Interaction '%s' is already attached at %s."
			% [interaction_id, attached_ids[interaction_id]]
		)

	var insertion := _add(
		document,
		graph,
		{"operation": "add_node", "node_type": "Node"},
		parent,
		name,
		new_path
	)

	if not insertion["ok"]:
		return insertion

	var value: Dictionary = insertion["value"]
	var edits: Array[Dictionary] = value["edits"]
	var used_ids := {}
	var resource_count := 1
	var declaration_offset: int = document["source"].length()

	for section: Dictionary in document["sections"]:
		if section["tag"] == "ext_resource":
			used_ids[Document.attribute(section, "id")] = true

		if section["tag"] in ["ext_resource", "sub_resource"]:
			resource_count += 1

		if section["tag"] in ["sub_resource", "node"]:
			declaration_offset = mini(
				declaration_offset, section["start"]
			)

	var script_id := "behavior_script"
	while used_ids.has(script_id):
		script_id += "_"
	used_ids[script_id] = true

	var content_id := "behavior_content"
	while used_ids.has(content_id):
		content_id += "_"

	var newline := (
		"\r\n"
		if String(document["source"]).get_slice("\n", 0).ends_with("\r")
		else "\n"
	)

	var declaration := (
		"[ext_resource type=\"Script\" path=%s id=%s]"
		% [JSON.stringify(behavior_script), JSON.stringify(script_id)]
	)
	declaration += newline
	declaration += (
		"[ext_resource type=\"Resource\" path=%s id=%s]"
		% [JSON.stringify(resource_path), JSON.stringify(content_id)]
	)
	declaration += newline + newline

	edits.append({
		"start": declaration_offset,
		"end": declaration_offset,
		"text": declaration,
	})

	if document["sections"][0]["attributes"].has("load_steps"):
		edits.append(Document.replacement(
			document["sections"][0]["attributes"]["load_steps"],
			str(resource_count + 2)
		))

	var node_edit: Dictionary = edits[0]
	node_edit["text"] = String(node_edit["text"]).trim_suffix(newline)
	node_edit["text"] += (
		"script = ExtResource(%s)" % JSON.stringify(script_id)
	) + newline
	node_edit["text"] += (
		"content = ExtResource(%s)" % JSON.stringify(content_id)
	) + newline + newline

	value["added_nodes"][new_path]["script_path"] = behavior_script
	value["added_nodes"][new_path][path_field] = (
		resource_path
	)
	value["added_nodes"][new_path][id_field] = interaction_id
	value["instance_hashes"] = required

	return Document.success(value)


static func _add(document: Dictionary, graph: Dictionary, request: Dictionary, parent: String, name: String, new_path: String) -> Dictionary:
	var edits: Array[Dictionary] = []
	var added_nodes := {}
	var instance_hashes := {}
	var node_id := _new_id(document)
	if node_id == 0:
		return Document.failure("Could not generate a unique node ID.")
	var header := "[node name=%s parent=%s unique_id=%s" % [JSON.stringify(name), JSON.stringify(parent), node_id]
	if request["operation"] == "add_node":
		if not request.get("node_type") is String or not _allowed_type(request["node_type"]):
			return Document.failure("Choose an instantiable built-in Godot Node type.")
		header += " type=%s]" % JSON.stringify(request["node_type"])
		added_nodes[new_path] = {"type": request["node_type"], "instance_path": ""}
	else:
		if not request.get("instance_scene") is String:
			return Document.failure("Choose a project .tscn scene to instance.")
		var instance_scene: String = request["instance_scene"]
		var checked := _check_path(instance_scene)
		if not checked["ok"]:
			return checked
		var loaded := SceneGraph.read(instance_scene)
		if not loaded["ok"]:
			return loaded
		var instance_graph: Dictionary = loaded["value"]
		if instance_graph["dependency_hashes"].has(graph["source_path"]):
			return Document.failure("Adding this instance would create a scene dependency cycle.")
		instance_hashes = instance_graph["dependency_hashes"]
		var id := "scene_edit_" + Crypto.new().generate_random_bytes(12).hex_encode()
		var offset: int = document["source"].length()
		var resource_count := 1
		for section: Dictionary in document["sections"]:
			if section["tag"] in ["ext_resource", "sub_resource"]:
				resource_count += 1
			if section["tag"] in ["sub_resource", "node"]:
				offset = mini(offset, section["start"])
		var newline := "\r\n" if String(document["source"]).get_slice("\n", 0).ends_with("\r") else "\n"
		var declaration := "[ext_resource type=\"PackedScene\" path=%s id=%s]%s%s" % [JSON.stringify(instance_scene), JSON.stringify(id), newline, newline]
		edits.append({"start": offset, "end": offset, "text": declaration})
		if document["sections"][0]["attributes"].has("load_steps"):
			edits.append(Document.replacement(document["sections"][0]["attributes"]["load_steps"], str(resource_count + 1)))
		header += " instance=ExtResource(%s)]" % JSON.stringify(id)
		for nested_path: String in instance_graph["nodes"]:
			var placed := new_path if nested_path == "." else new_path.path_join(nested_path)
			added_nodes[placed] = {"type": instance_graph["nodes"][nested_path]["type"], "instance_path": instance_scene if nested_path == "." else instance_graph["nodes"][nested_path]["instance_path"]}
	var offset := 0
	for section: Dictionary in document["sections"]:
		if section["tag"] == "node":
			offset = maxi(offset, section["end"])
	var newline := "\r\n" if String(document["source"]).get_slice("\n", 0).ends_with("\r") else "\n"
	edits.append({"start": offset, "end": offset, "text": newline + header + newline + newline})
	return Document.success({"edits": edits, "added_count": added_nodes.size(), "added_nodes": added_nodes, "instance_hashes": instance_hashes})


static func _publish(path: String, source: String, before: Dictionary, hashes: Dictionary, operation: Dictionary) -> Dictionary:
	if source.to_utf8_buffer().size() > MAX_BYTES:
		return Document.failure("Edited scene exceeds 8 MiB.")
	var staged := path.get_base_dir().path_join(".scene-pending-" + Crypto.new().generate_random_bytes(16).hex_encode() + ".tscn")
	if FileAccess.file_exists(staged):
		return Document.failure("Scene staging path already exists.")
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return Document.failure("Could not create the scene staging file.")
	file.store_string(source)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _discard(staged, "Could not write the complete staged scene.")
	var loaded := SceneGraph.read(staged)
	if not loaded["ok"]:
		return _discard(staged, "Staged scene did not validate: %s" % loaded["error"])
	var verified := _verify(before, loaded["value"], operation)
	if not verified["ok"]:
		return _discard(staged, verified["error"])
	if operation["operation"] == "set_property":
		verified = SceneProperties.verify(staged, operation["path"], operation["property_name"], operation["property_value"])
		if not verified["ok"]:
			return _discard(staged, verified["error"])
	var checked := _check_hashes(hashes, hashes)
	if not checked["ok"]:
		return _discard(staged, checked["error"])
	if operation.has("layout_hashes"):
		checked = LayoutBuilder.verify_hashes(operation["layout_hashes"], operation["layout_hashes"])
		if not checked["ok"]:
			return _discard(staged, checked["error"])
	var published := DirAccess.rename_absolute(staged, path)
	if published != OK:
		return _discard(staged, "Could not publish the scene: %s" % error_string(published))
	return Document.success({"scene_path": path, "operation": operation["operation"], "path": operation["path"], "new_path": operation["new_path"], "content_hash": FileAccess.get_sha256(path)})


static func _verify(before: Dictionary, after: Dictionary, operation: Dictionary) -> Dictionary:
	var nodes: Dictionary = after["nodes"]
	var expected := {}
	for path: String in before["nodes"]:
		if operation["operation"] == "remove" and References.inside(path, operation["path"]):
			continue
		var mapped := References.mapped_path(path, operation["path"], operation["new_path"]) if operation["operation"] == "rename" else path
		expected[mapped] = true
		if not nodes.has(mapped):
			return Document.failure("Staged scene lost a surviving node: %s." % mapped)
		for field in ["type", "script_path", "instance_path", "base_scene_path"]:
			if field == "script_path" and operation["operation"] in SCRIPT_OPERATIONS and path == operation["path"]:
				if nodes[mapped][field] != operation["script_path"]:
					return Document.failure("The attached script failed verification.")
				continue
			if nodes[mapped][field] != before["nodes"][path][field]:
				return Document.failure("Staged scene changed %s on %s." % [field, path])
		var expected_script: bool = (
			operation["operation"] == "attach_script"
			if operation["operation"] in SCRIPT_OPERATIONS and path == operation["path"]
			else before["nodes"][path]["has_script"]
		)
		if nodes[mapped]["has_script"] != expected_script:
			return Document.failure("Staged scene changed an unexpected script at %s." % path)
		for field in ["movement_configuration_path", "movement_controller_path"]:
			var original: String = before["nodes"][path][field]
			var expected_resource: String = operation.get(field, original) if path == operation["path"] else original
			var actual_resource: String = nodes[mapped][field]
			if expected_resource.contains("::") and actual_resource.contains("::"):
				expected_resource = expected_resource.get_slice("::", 1)
				actual_resource = actual_resource.get_slice("::", 1)
			if actual_resource != expected_resource:
				return Document.failure("Staged scene changed an unexpected %s at %s." % [field, path])
		var children: Array[String] = []
		for child: String in before["nodes"][path]["children"]:
			if operation["operation"] == "remove" and References.inside(child, operation["path"]):
				continue
			children.append(References.mapped_path(child, operation["path"], operation["new_path"]) if operation["operation"] == "rename" else child)
		if operation["operation"] in ADD_OPERATIONS and path == operation["path"]:
			children.append(operation["new_path"])
		if nodes[mapped]["children"] != children:
			return Document.failure("Staged scene changed unrelated sibling ordering at %s." % path)
	for path: String in operation.get("added_nodes", {}):
		expected[path] = true
		if not nodes.has(path) or nodes[path]["type"] != operation["added_nodes"][path]["type"] or nodes[path]["instance_path"] != operation["added_nodes"][path]["instance_path"]:
			return Document.failure("The new node or scene instance failed verification.")
	if operation["operation"] == "attach_behavior":
		var added: Dictionary = operation["added_nodes"][
			operation["new_path"]
		]
		var actual: Dictionary = nodes[operation["new_path"]]

		for field in [
			"script_path",
			"interaction_resource_path",
			"interaction_id",
			"automation_resource_path",
			"automation_id",
			"behavior_id",
			"behavior_resource_path",
		]:
			if actual[field] != added.get(field, ""):
				return Document.failure(
					"The attached behavior failed verification: %s."
					% field
				)
	if expected.size() != nodes.size():
		return Document.failure("Staged scene contains unexpected nodes.")
	return Document.success(true)


static func _check_path(path: String, extension: String = "tscn") -> Dictionary:
	if not path.begins_with("res://") or path.get_extension() != extension or path.simplify_path() != path:
		return Document.failure("Choose a project-relative .tscn scene.")
	var directory := DirAccess.open("res://")
	var current := "res://"
	for part in path.trim_prefix("res://").split("/"):
		if part.is_empty() or part in [".", ".."] or part.contains(":") or part.contains("\\") or part.to_utf8_buffer().has(0):
			return Document.failure("Invalid scene file path.")
		current = current.path_join(part)
		if directory == null or directory.is_link(current):
			return Document.failure("Scene editing does not follow symbolic links or junctions.")
	if not FileAccess.file_exists(path):
		return Document.failure("Scene file does not exist: %s." % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Document.failure("Scene file cannot be read.")
	var size := file.get_length()
	file.close()
	return Document.success(true) if size > 0 and size <= MAX_BYTES else Document.failure("Scene files must contain between 1 byte and 8 MiB.")


static func _check_hashes(expected: Dictionary, required: Dictionary) -> Dictionary:
	for path: String in required:
		var checked := _check_dependency_path(path)
		if not checked["ok"]:
			return checked
		if not expected.get(path) is String or String(expected[path]).length() != 64 or not String(expected[path]).is_valid_hex_number(false) or FileAccess.get_sha256(path) != expected[path]:
			return Document.failure("Scene dependency changed or was not inspected: %s. Refresh and retry." % path)
	return Document.success(true)


static func _check_dependency_path(path: String) -> Dictionary:
	if path.get_extension() not in ["tscn", "tres", "gd"]:
		return Document.failure("Invalid Resource dependency path.")
	return _check_path(path, path.get_extension())


static func _allowed_type(native_type: StringName) -> bool:
	return ClassDB.class_exists(native_type) and ClassDB.is_parent_class(native_type, &"Node") and ClassDB.can_instantiate(native_type) and ClassDB.class_get_api_type(native_type) == ClassDB.API_CORE


static func _new_id(document: Dictionary) -> int:
	var existing := {}
	for section: Dictionary in document["sections"]:
		if section["attributes"].has("unique_id"):
			existing[Document.attribute(section, "unique_id").to_int()] = true
	var id := 0
	while id == 0 or existing.has(id):
		var bytes := Crypto.new().generate_random_bytes(4)
		if bytes.size() != 4:
			return 0
		id = int(bytes.decode_u32(0)) & 0x7fffffff
	return id


static func _discard(path: String, message: String) -> Dictionary:
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		message += " Could not remove staging file: %s." % path
	return Document.failure(message)
