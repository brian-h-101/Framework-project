extends RefCounted

const Document = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_document.gd")
const Editing = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_editing.gd")
const SceneGraph = preload("res://Framework/Env/Authoring/Scenes/Inspection/scene_graph.gd")
const SceneScript = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_script.gd")
const SpatialRoot = preload("res://Framework/Content/Universal/Map/based/Spatial2D/spatial_root_2d.gd")
const SpatialRoles3D = preload("res://Framework/Content/Universal/Map/based/Spatial3D/spatial_roles_3d.gd")
const BehaviorBinding = preload("res://Framework/Content/Universal/Interaction/based/Bindings/behavior_binding.gd")
const Movement = preload("res://Framework/Content/Universal/Movement/based/Configuration/movement_profile.gd")
const Controls = preload("res://Framework/Env/Configuration/Resources/Input/controls_resource.gd")
const MovementCatalog = preload("res://Framework/Env/Authoring/Scenes/Configuration/movement_configuration_catalog.gd")
const ControllerCatalog = preload("res://Framework/Env/Authoring/Scenes/Configuration/movement_controller_catalog.gd")
const ConfigurationInspection = preload("res://Framework/Env/Authoring/Resources/Configuration/configuration_inspection.gd")
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const BehaviorPaths = preload("res://Framework/Env/Setup/Library/behavior_library_policy.gd")

const Intent = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_intent.gd")
const Executor = preload("res://Framework/Content/Gameplay/Profiles/Movement/Executor/movement_executor.gd")
const PlanarExecutor = preload("res://Framework/Content/Gameplay/Profiles/Movement/Executor/movement_2d_executor.gd")
const EXECUTOR_PATH := "res://Framework/Content/Gameplay/Profiles/Movement/Executor/movement_executor.gd"
const INPUT := "res://Framework/Content/Configuration/Input/controls.tres"
const LOCK := "res://.godot/authoring/movement_capability.lock"


static func inspect(scene: String, path: String) -> Dictionary:
	var resolved := _resolve(scene, path)
	if not resolved["ok"]:
		return resolved
	var state: Dictionary = resolved["value"]
	var configurations: Array[Dictionary] = []
	var found := MovementCatalog.paths()
	if not found["ok"]:
		return found
	for source: String in found["value"]:
		var profile := ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Movement
		if profile != null and _validate_profile(profile)["ok"] and _compatible(profile, state["body_type"]):
			configurations.append({
				"source_path": source,
				"behavior_id": String(profile.movement_behavior.id),
				"velocity_step_id": String(profile.velocity_step_id),
				"environment": profile.environment(),
			})

	var controllers := ControllerCatalog.read()
	if not controllers["ok"]:
		return controllers
	return Document.success({
		"scene_path": state["scene_path"],
		"body_path": state["body_path"],
		"current_configuration": state["current_configuration"],
		"current_controller": state["current_controller"],
		"configurations": configurations,
		"controllers": controllers["value"],
	})


static func plan(scene: String, path: String, options: Dictionary) -> Dictionary:
	var prepared := _prepare(scene, path, options)
	return prepared if not prepared["ok"] else Document.success(prepared["value"]["review"])


static func apply(scene: String, path: String, options: Dictionary, token: Variant) -> Dictionary:
	if not token is String or token.is_empty():
		return Document.failure("Review the movement changes before applying them.")
	var error := Paths.project_error(LOCK.get_base_dir())
	if not error.is_empty():
		return Document.failure(error)
	if DirAccess.make_dir_recursive_absolute(LOCK.get_base_dir()) != OK:
		return Document.failure("Could not open movement authoring staging.")
	if DirAccess.make_dir_absolute(LOCK) != OK:
		return Document.failure("Another movement capability edit has locked this project.")
	var prepared := _prepare(scene, path, options)
	var result := prepared
	if prepared["ok"]:
		var data: Dictionary = prepared["value"]
		result = (
			_commit(data)
			if data["review"]["token"] == token
			else Document.failure("Movement inputs or dependencies changed since review. Refresh and retry.")
		)
	if DirAccess.remove_absolute(LOCK) != OK:
		return Document.failure("Could not release the movement capability edit lock. Review the files before retrying.")
	return result


static func _resolve(from_scene: String, path: String) -> Dictionary:
	var error := Paths.project_error(from_scene)
	if not error.is_empty():
		return Document.failure(error)
	var selected := SceneGraph.read(from_scene)
	if not selected["ok"]:
		return selected
	var graph: Dictionary = selected["value"]
	var node: Dictionary = graph["nodes"].get(path, {})
	if not node.get("is_entity", false) or node["type"] == "InstancePlaceholder":
		return Document.failure("Choose an entity root in Framework Scenes.")
	var source: String = node["instance_path"] if not node["instance_path"].is_empty() else node["structural_scene"]
	var entity_path: String = "." if not node["instance_path"].is_empty() else node["structural_node_path"]
	error = Paths.project_error(source)
	if not error.is_empty():
		return Document.failure(error)
	var inspected := selected if source == from_scene else SceneGraph.read(source)
	if not inspected["ok"]:
		return inspected
	var authored: Dictionary = inspected["value"]
	var owned: Dictionary = authored["nodes"].get(entity_path, {})
	if not owned.get("is_entity", false) or not owned["can_add"]:
		return Document.failure("The entity must have an authored root in its source scene.")
	var packed := ResourceLoader.load(source, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if packed != null else null
	if root == null:
		return Document.failure("Could not instantiate the source scene for movement validation.")
	var result := _inspect_entity(root, entity_path, authored)
	root.free()
	if not result["ok"]:
		return result
	var hashes: Dictionary = graph["dependency_hashes"].duplicate()
	hashes.merge(authored["dependency_hashes"])
	result["value"]["hashes"] = hashes
	result["value"]["scene_path"] = source
	result["value"]["entity_path"] = entity_path
	return result


static func _inspect_entity(root: Node, path: String, graph: Dictionary) -> Dictionary:
	var entity := root.get_node_or_null(NodePath(path))
	var discovered := SpatialRoot.find_for(entity)
	if not discovered["ok"]:
		var native := SpatialRoles3D.find(entity, &"entity_spatial_root")
		if not native["ok"] or native["value"] == null:
			return discovered
		discovered = native
	var body: Node = discovered["value"]
	if body == null or not SceneGraph.MOVEMENT_SCRIPTS.has(body.get_class()):
		return Document.failure("Movement needs a CharacterBody2D or CharacterBody3D marked entity_spatial_root.")
	var body_type := body.get_class()
	var body_path := String(root.get_path_to(body))
	var record: Dictionary = graph["nodes"].get(body_path, {})
	if record.get("structural_scene") != graph["source_path"] or not record.get("instance_path", "").is_empty():
		return Document.failure("The movement body belongs to a shared scene. Open its structure source to configure it.")
	if record["has_script"] and record["script_path"] != SceneGraph.MOVEMENT_SCRIPTS[body_type]:
		return Document.failure("Movement cannot replace the existing script on %s." % body_path)
	var bindings := {}
	var pending: Array[Node] = [entity]
	while not pending.is_empty():
		var child: Node = pending.pop_back()
		if child != entity and (child.has_meta(&"entity_key") or child.has_meta(&"entity_definition")):
			continue
		if child is BehaviorBinding and child.content != null:
			var id := String(child.content.id)
			if not bindings.has(id):
				bindings[id] = []
			bindings[id].append({
				"path": String(root.get_path_to(child)),
				"resource": child.content.resource_path,
				"enabled": child.enabled,
			})
		pending.append_array(child.get_children())
	var binding_name := "MoveBehavior"
	var suffix := 2
	while entity.has_node(NodePath(binding_name)):
		binding_name = "MoveBehavior%d" % suffix
		suffix += 1
	return Document.success({
		"body_path": body_path,
		"body_type": body_type,
		"attach_script": not record["has_script"],
		"current_configuration": record["movement_configuration_path"],
		"current_controller": record["movement_controller_path"],
		"binding_name": binding_name,
		"bindings": bindings,
	})


static func _prepare(scene: String, path: String, options: Dictionary) -> Dictionary:
	var resolved := _resolve(scene, path)
	if not resolved["ok"]:
		return resolved
	var state: Dictionary = resolved["value"]
	var profile_path: Variant = options.get("configuration_path")
	var controller_path: Variant = options.get("controller_path")
	if not profile_path is String or not controller_path is String:
		return Document.failure("Choose an existing shared movement profile and controller in Framework Scenes.")
	var hashes: Dictionary = state["hashes"]
	var selected := _load_profile(profile_path, hashes)
	if not selected["ok"]:
		return selected
	var profile: Movement = selected["value"]
	var spec := profile.resolved_environment()
	if not _compatible(profile, state["body_type"]):
		return Document.failure("The movement environment is incompatible with %s." % state["body_type"])
	var environment := spec.environment_id()
	if options.get("environment", environment) != environment:
		return Document.failure("The shared movement profile uses a different movement environment.")
	var controller := ControllerCatalog.inspect(controller_path)
	if not controller["ok"]:
		return controller
	var intent: Dictionary = controller["value"]["definition"]
	if spec.body_type() == "CharacterBody3D" and intent.get("distance_unit") == "pixels":
		return Document.failure("3D targeting controllers require stopping distance in gameplay units.")
	hashes.merge(controller["value"]["dependency_hashes"])
	var actions: Array[String] = []
	if intent["kind"] == "keyboard":
		var controls := _check_input_actions(intent["actions"], hashes)
		if not controls["ok"]:
			return controls
		actions.assign(controls["value"])

	var behavior_path := profile.movement_behavior.resource_path
	var behavior_id := String(profile.movement_behavior.id)
	var matching: Array = state["bindings"].get(behavior_id, [])
	if matching.size() > 1:
		return Document.failure("Multiple bindings use Behavior '%s' on this entity." % behavior_id)
	if not matching.is_empty() and (not matching[0]["enabled"] or matching[0]["resource"] != behavior_path):
		return Document.failure("The '%s' binding is disabled or references a different resource. Check %s." % [behavior_id, matching[0]["path"]])
	var executor_path: String = _velocity_executor(profile).resource_path
	var dependency_paths: Array[String] = [executor_path, EXECUTOR_PATH]
	for original in [state["current_configuration"], state["current_controller"]]:
		if not String(original).is_empty():
			dependency_paths.append(String(original).get_slice("::", 0))
	for bindings: Array in state["bindings"].values():
		for binding: Dictionary in bindings:
			var bound_path: String = String(binding["resource"]).get_slice("::", 0)
			if not bound_path.is_empty():
				dependency_paths.append(bound_path)
	for dependency in dependency_paths:
		var hashed := MovementCatalog._collect_dependencies(dependency, hashes, 0)
		if not hashed["ok"]:
			return hashed
	var adapter: String = SceneGraph.MOVEMENT_SCRIPTS[spec.body_type()]
	var adapter_dependencies := MovementCatalog._collect_dependencies(adapter, hashes, 0)
	if not adapter_dependencies["ok"]:
		return adapter_dependencies
	for script in [adapter, Editing.UNIFIED_SCRIPT]:
		var inspected := SceneScript.inspect(script, spec.body_type() if script == adapter else "Node")
		if not inspected["ok"]:
			return inspected
		hashes.merge(inspected["value"]["dependency_hashes"])
	var checked := Editing._check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked

	var operations: Array[Dictionary] = []
	if state["attach_script"]:
		operations.append({"operation": "attach_script", "path": state["body_path"], "script_path": adapter})
	if state["current_configuration"] != profile_path:
		operations.append({"operation": "assign_movement", "path": state["body_path"], "movement_configuration": profile_path})
	if state["current_controller"] != controller_path:
		operations.append({"operation": "assign_movement_controller", "path": state["body_path"], "movement_controller": controller_path})
	if matching.is_empty():
		operations.append({"operation": "attach_behavior", "path": state["entity_path"], "name": state["binding_name"], "behavior_resource": behavior_path})
	var review := {
		"scene_path": state["scene_path"],
		"body_path": state["body_path"],
		"configuration_path": profile_path,
		"environment": environment,
		"controller_path": controller_path,
		"controller_kind": intent["kind"],
		"behavior_path": behavior_path,
		"binding_path": "" if matching.is_empty() else matching[0]["path"],
		"add_binding": matching.is_empty(),
		"attach_script": state["attach_script"],
		"assign_configuration": state["current_configuration"] != profile_path,
		"assign_controller": state["current_controller"] != controller_path,
		"input_actions": actions,
		"dependency_hashes": hashes,
	}
	review["token"] = JSON.stringify([review, operations]).sha256_text()
	return Document.success({"review": review, "operations": operations})


static func _load_profile(path: String, hashes: Dictionary) -> Dictionary:
	if not ConfigurationInspection.is_movement_path(path):
		return Document.failure("Choose a Movement profile under Content/Gameplay/Profiles or Content/Configuration.")
	var inspected := MovementCatalog.inspect(path)
	if not inspected["ok"]:
		return inspected
	hashes.merge(inspected["value"]["dependency_hashes"])
	var profile := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Movement
	var checked := _validate_profile(profile)
	return Document.success(profile) if checked["ok"] else checked


static func _compatible(profile: Movement, body_type: String) -> bool:
	return SceneGraph.MOVEMENT_SCRIPTS.has(body_type) and profile.resolved_environment().body_type() == body_type


static func _validate_profile(profile: Movement) -> Dictionary:
	if profile == null or profile.movement_behavior == null or not profile.actions.is_empty():
		return Document.failure("Choose a shared Movement profile with a Behavior and no keyboard actions.")
	var checked := profile.read()
	if not checked["ok"]:
		return checked
	var error := BehaviorPaths.resource_error(profile.movement_behavior.resource_path)
	if not error.is_empty():
		return Document.failure(error)
	if _velocity_executor(profile) == null:
		return Document.failure("The shared profile's velocity step must use the Movement executor or its legacy planar variant.")
	return Document.success(true)


static func _velocity_executor(profile: Movement) -> Script:
	var step := profile.velocity_step()
	var arguments: Dictionary = step.get("arguments", {})
	var semantic := Intent.has_axes(arguments, Intent.AXES)
	match step.get("executor_id"):
		Executor.BEHAVIOR_ID:
			return Executor if semantic else null
		PlanarExecutor.BEHAVIOR_ID:
			return PlanarExecutor if not semantic and Intent.has_axes(arguments, Intent.LEGACY_AXES) else null
	return null


static func _check_input_actions(mapping: Dictionary, hashes: Dictionary) -> Dictionary:
	var collected := MovementCatalog._collect_dependencies(INPUT, hashes, 0)
	if not collected["ok"]:
		return collected
	var controls := ResourceLoader.load(INPUT, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Controls
	if controls == null:
		return Document.failure("Could not load the project's Controls resource.")
	var checked := controls.read()
	if not checked["ok"]:
		return checked
	var bindings: Dictionary = checked["value"]
	var actions: Array[String] = []
	for direction in ["left", "right", "up", "down"]:
		var value: Variant = mapping.get(direction)
		if not Controls.is_text(value):
			return Document.failure("The keyboard controller must provide a %s action." % direction)
		var action := StringName(value)
		if not bindings.has(action) or bindings[action]["keys"].is_empty():
			return Document.failure("Keyboard action '%s' needs a binding in controls.tres. Edit it in Framework Resources." % action)
		actions.append(String(action))
	return Document.success(actions)


static func _commit(data: Dictionary) -> Dictionary:
	var review: Dictionary = data["review"]
	var scene: String = review["scene_path"]
	if data["operations"].is_empty():
		return Document.success({"scene_path": scene, "changed": false})
	var hashes: Dictionary = review["dependency_hashes"]
	var checked := Editing._check_hashes(hashes, hashes)
	if not checked["ok"]:
		return checked
	var staged := scene.get_base_dir().path_join(".movement-pending-" + Crypto.new().generate_random_bytes(16).hex_encode() + ".tscn")
	if FileAccess.file_exists(staged):
		return Document.failure("Movement staging path already exists.")
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return Document.failure("Could not open the staged movement scene.")
	file.store_buffer(FileAccess.get_file_as_bytes(scene))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return Editing._discard(staged, "Could not stage the entity scene: %s." % error_string(write_error))
	var expected := hashes.duplicate()
	for operation: Dictionary in data["operations"]:
		expected[staged] = FileAccess.get_sha256(staged)
		operation["expected_hashes"] = expected
		var edited := Editing.edit(staged, operation)
		if not edited["ok"]:
			return Editing._discard(staged, edited["error"])
	checked = Editing._check_hashes(hashes, hashes)
	if not checked["ok"]:
		return Editing._discard(staged, checked["error"])
	var published := DirAccess.rename_absolute(staged, scene)
	if published != OK:
		return Editing._discard(staged, "Could not publish the configured entity scene: %s." % error_string(published))
	return Document.success({"scene_path": scene, "changed": true})
