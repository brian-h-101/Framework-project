extends SceneTree

const MovementConfiguration = preload("res://Framework/Env/Configuration/Resources/movement_resource.gd")

const EntityContent = preload(
	"res://Framework/Env/Setup/entity_definitions.gd"
)
const UIAnchor2D = preload(
	"res://Framework/Env/Presentation/ui_anchor_2d.gd"
)
const TargetPoint2D = preload(
	"res://Framework/Env/Targeting/target_point_2d.gd"
)
const SpatialRoot2D = preload(
	"res://Framework/Env/Map/spatial_root_2d.gd"
)
const Presentation2DResource = preload(
	"res://Framework/Env/Presentation/Resources/presentation_2d_resource.gd"
)
const Movement2D = preload(
	"res://Framework/Env/Movement/movement_2d.gd"
)
const InteractionInput = preload(
	"res://Framework/Env/Input/interaction_input.gd"
)
const StartingContent = preload(
	"res://Framework/Env/Setup/starting_definitions.gd"
)
const PRESENTATION_ROOT: String = "res://Framework/Content/Presentation/"

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var result: Dictionary

	if arguments.size() == 1 and arguments[0] == "list":
		result = _list_definitions()
	elif arguments.size() == 1 and arguments[0] == "catalogue":
		result = _list_presentations()
	elif arguments.size() == 3 and arguments[0] == "assemble":
		result = _assemble(arguments[1], arguments[2])
	elif arguments.size() == 5 and arguments[0] == "append":
		result = _append_placement(
			arguments[1],
			arguments[2],
			arguments[3],
			arguments[4]
		)
	else:
		result = _failure(
			"Expected list, catalogue, assemble <definition_id> <output_path>, "
			+ "or append <presentation_path> <map_path> <entity_key> <output_path>."
		)

	print("[authoring-result] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)


func _list_presentations() -> Dictionary:
	var discovered := StartingContent.definitions()
	if not discovered["ok"]:
		return discovered

	var source_paths: Dictionary = discovered["sources"]
	var records: Array[Dictionary] = []

	for definition in discovered["value"]:
		var definition_id := String(definition["id"])
		var source_path := String(source_paths[StringName(definition_id)])

		if not source_path.begins_with(PRESENTATION_ROOT):
			return _failure(
				"Starting definition is outside presentation content: %s"
				% source_path
			)

		var folder_path: String = source_path.get_base_dir()
		var category: String = folder_path.trim_prefix(
			PRESENTATION_ROOT
		).get_slice("/", 0)

		records.append({
			"id": definition_id,
			"category": category,
			"folder_path": folder_path,
			"profile_path": folder_path.path_join("presentation.tres"),
			"scene_path": folder_path.path_join(
				definition_id + "_2d.tscn"
			),
		})

	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["id"]) < String(right["id"])
	)

	return _success(records)


func _list_definitions() -> Dictionary:
	var discovered := EntityContent.definitions()
	if not discovered["ok"]:
		return discovered

	var ids: Array[String] = []
	for definition in discovered["value"]:
		ids.append(String(definition["id"]))

	ids.sort()
	return _success(ids)


func _presentation_record_for(definition_id: String) -> Dictionary:
	var catalogue := _list_presentations()
	if not catalogue["ok"]:
		return catalogue

	for record in catalogue["value"]:
		if String(record["id"]) == definition_id:
			return _success(record)

	return _failure("Unknown starting definition: %s" % definition_id)


func _assemble(definition_id: String, output_path: String) -> Dictionary:
	var selected := _presentation_record_for(definition_id)
	if not selected["ok"]:
		return selected

	var record: Dictionary = selected["value"]

	if not definition_id.is_valid_identifier():
		return _failure("Entity definition ID is not suitable for a node name.")

	if FileAccess.file_exists(output_path):
		return _failure("Output already exists: %s" % output_path)

	var profile_result := _presentation_for(record)
	if not profile_result["ok"]:
		return profile_result

	var presentation: Dictionary = profile_result["value"]

	var entity_node := Node2D.new()
	entity_node.name = StringName(definition_id.to_pascal_case())
	entity_node.set_meta(&"entity_definition", StringName(definition_id))

	var movement_content: MovementConfiguration = presentation["movement_content"]
	var view: Node2D

	if movement_content != null:
		var moving_view := Movement2D.new()
		moving_view.content = movement_content
		view = moving_view
	else:
		view = Node2D.new()

	view.name = &"View2D"
	view.set_meta(SpatialRoot2D.ROOT_META, true)
	_owned_child(entity_node, view, entity_node)

	if movement_content != null:
		var shape := RectangleShape2D.new()
		shape.size = presentation["body_size"]

		var collider := CollisionShape2D.new()
		collider.name = &"CollisionShape2D"
		collider.shape = shape
		_owned_child(view, collider, entity_node)

	var body := Polygon2D.new()
	body.name = &"Body"
	body.color = presentation["body_color"]
	body.polygon = _body_polygon(presentation["body_size"])
	body.set_meta(&"casts_shadow", presentation["casts_shadow"])
	_owned_child(view, body, entity_node)

	var status_anchor := Marker2D.new()
	status_anchor.name = &"StatusAnchor"
	status_anchor.set_meta(UIAnchor2D.ROLE_META, &"status")
	_owned_child(view, status_anchor, entity_node)

	var target_point := Marker2D.new()
	target_point.name = &"TargetPoint"
	target_point.set_meta(TargetPoint2D.TARGET_META, true)
	_owned_child(view, target_point, entity_node)

	var camera_scene: PackedScene = presentation["camera_scene"]
	if camera_scene != null:
		var camera := camera_scene.instantiate(
			PackedScene.GEN_EDIT_STATE_INSTANCE
		)

		if not camera is Camera2D:
			if camera != null:
				camera.free()
			entity_node.free()
			return _failure("Camera scene must instantiate a Camera2D.")

		camera.name = &"FollowCamera"
		_owned_child(view, camera, entity_node)

	if presentation["interaction_input"]:
		var interaction_input := InteractionInput.new()
		interaction_input.name = &"InteractionInput"
		_owned_child(entity_node, interaction_input, entity_node)

	var packed := PackedScene.new()
	var pack_error := packed.pack(entity_node)
	entity_node.free()

	if pack_error != OK:
		return _failure("Could not pack entity scene: %s" % error_string(pack_error))

	var save_error := ResourceSaver.save(packed, output_path)
	if save_error != OK:
		return _failure("Could not save entity scene: %s" % error_string(save_error))

	return _verify_saved_scene(output_path, definition_id, presentation)


func _presentation_for(record: Dictionary) -> Dictionary:
	var profile_path: String = record["profile_path"]

	if not ResourceLoader.exists(profile_path):
		return _success(Presentation2DResource.new().to_definition())

	var profile: Resource = ResourceLoader.load(profile_path)
	if not profile is Presentation2DResource:
		return _failure(
			"Expected a 2D presentation resource: %s"
			% profile_path
		)

	var definition: Dictionary = (profile as Presentation2DResource).to_definition()
	if definition.get("ok", true) == false:
		return _failure(
			"Presentation failed in %s: %s"
			% [profile_path, definition["error"]]
		)

	return _success(definition)


func _owned_child(
	parent_node: Node,
	child: Node,
	scene_root: Node
) -> void:
	parent_node.add_child(child)
	child.owner = scene_root


func _body_polygon(size: Vector2) -> PackedVector2Array:
	var half_size := size * 0.5

	return PackedVector2Array([
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
	])


func _verify_saved_scene(
	path: String,
	definition_id: String,
	presentation: Dictionary
) -> Dictionary:
	var saved := ResourceLoader.load(
		path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene

	if saved == null or not saved.can_instantiate():
		return _failure("Saved entity scene could not be loaded.")

	var reloaded_node := saved.instantiate()
	if reloaded_node == null:
		return _failure("Saved entity scene could not be instantiated.")

	var body := reloaded_node.get_node_or_null("View2D/Body") as Polygon2D
	var status := UIAnchor2D.find_for(reloaded_node)
	var target := TargetPoint2D.find_for(reloaded_node)
	var spatial := SpatialRoot2D.find_for(reloaded_node)
	var root_type := reloaded_node.get_class()

	var valid: bool = (
		reloaded_node is Node2D
		and reloaded_node.get_meta(&"entity_definition", &"") == StringName(definition_id)
		and body != null
		and body.color.is_equal_approx(presentation["body_color"])
		and body.polygon == _body_polygon(presentation["body_size"])
		and body.get_meta(&"casts_shadow", null) == presentation["casts_shadow"]
		and status["ok"]
		and target["ok"]
		and spatial["ok"]
		and spatial["value"] == body.get_parent()
	)

	var components_verified := _verify_components(reloaded_node, presentation)
	reloaded_node.free()

	if not valid:
		return _failure("Saved entity scene failed its body or marker check.")

	if not components_verified:
		return _failure("Saved entity scene failed its component check.")

	return _success({
		"root_type": root_type,
		"markers_verified": true,
		"components_verified": true,
	})


func _verify_components(
	entity_node: Node,
	presentation: Dictionary
) -> bool:
	var view := entity_node.get_node_or_null("View2D") as Node2D
	if view == null:
		return false

	var movement_content: MovementConfiguration = presentation["movement_content"]
	var collider := view.get_node_or_null("CollisionShape2D") as CollisionShape2D

	if movement_content != null:
		if (
			not view is CharacterBody2D
			or view.get_script() != Movement2D
			or view.get(&"content") != movement_content
			or collider == null
		):
			return false

		var shape := collider.shape as RectangleShape2D
		if shape == null or not shape.size.is_equal_approx(presentation["body_size"]):
			return false
	else:
		if view.get_class() != "Node2D" or view.get_script() != null or collider != null:
			return false

	var camera_scene: PackedScene = presentation["camera_scene"]
	var camera := view.get_node_or_null("FollowCamera")

	if camera_scene != null:
		if not camera is Camera2D or camera.scene_file_path != camera_scene.resource_path:
			return false
	elif camera != null:
		return false

	var interaction_input := entity_node.get_node_or_null("InteractionInput")
	var wants_input: bool = presentation["interaction_input"]

	if wants_input:
		return (
			interaction_input != null
			and interaction_input.get_script() == InteractionInput
		)

	return interaction_input == null


func _append_placement(
	presentation_path: String,
	map_path: String,
	entity_key: String,
	output_path: String
) -> Dictionary:
	if (
		not presentation_path.begins_with(PRESENTATION_ROOT)
		or presentation_path.simplify_path() != presentation_path
		or not map_path.begins_with("res://Games/")
		or map_path.simplify_path() != map_path
	):
		return _failure("Choose a presentation from Content and a map from Games.")

	if not entity_key.is_valid_identifier():
		return _failure("Placement key must be a valid identifier.")

	if FileAccess.file_exists(output_path):
		return _failure("Draft already exists: %s" % output_path)

	var presentation := load(presentation_path) as PackedScene
	var map_scene := load(map_path) as PackedScene

	if presentation == null or map_scene == null:
		return _failure("Presentation and map must both be PackedScene resources.")

	if not presentation.can_instantiate() or not map_scene.can_instantiate():
		return _failure("Presentation or map cannot be instantiated.")

	if map_scene.get_state().get_base_scene_state() != null:
		return _failure("This appender currently supports ordinary map scenes.")

	var map_node := map_scene.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	if map_node == null:
		return _failure("Map could not be instantiated.")

	if not map_node is Node2D or map_node.has_meta(&"entity_definition"):
		map_node.free()
		return _failure("Destination must be a Node2D map scene.")

	var result := _stage_placement(
		map_node as Node2D,
		map_scene,
		presentation,
		presentation_path,
		map_path,
		entity_key,
		output_path
	)

	map_node.free()
	return result


func _stage_placement(
	map_node: Node2D,
	map_scene: PackedScene,
	presentation: PackedScene,
	presentation_path: String,
	map_path: String,
	entity_key: String,
	output_path: String
) -> Dictionary:
	var before := _scene_layout(map_node)
	var key := StringName(entity_key)
	var node_name := entity_key.to_pascal_case()
	var nodes: Array[Node] = [map_node]
	nodes.append_array(map_node.find_children("*", "", true, false))

	for world_node in nodes:
		if world_node.get_meta(&"entity_key", &"") == key:
			return _failure("Duplicate map entity key: %s" % entity_key)

	if map_node.get_node_or_null(NodePath(node_name)) != null:
		return _failure("Map already contains a node named: %s" % node_name)

	var placement := presentation.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if placement == null:
		return _failure("Entity presentation could not be instantiated.")

	placement.name = StringName(node_name)
	map_node.add_child(placement)
	placement.owner = map_node

	if not placement is Node2D:
		return _failure("Entity presentation must have a Node2D root.")

	var definition_value: Variant = placement.get_meta(&"entity_definition", &"")
	if typeof(definition_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure("Presentation entity_definition must be text.")

	var definition_id := String(definition_value)
	var registered := _presentation_record_for(definition_id)
	if not registered["ok"]:
		return registered

	var startup_result: Dictionary = load(
		"res://Framework/Content/Configuration/Session/startup.tres"
	).call(&"read")
	if not startup_result["ok"]:
		return startup_result
	var startup: Dictionary = startup_result["value"]
	var startup_entities: Dictionary = startup["entities"]

	if startup_entities.has(key):
		var specification: Dictionary = startup_entities[key]
		if String(specification["definition"]) != definition_id:
			return _failure("Placement key conflicts with a startup entity: %s" % key)

	placement.set_meta(&"entity_key", key)

	var source_uid_result := _read_scene_uid(map_path)
	if not source_uid_result["ok"]:
		return source_uid_result

	var map_uid: int = source_uid_result["value"]

	var packed := PackedScene.new()
	var pack_error := packed.pack(map_node)
	if pack_error != OK:
		return _failure("Could not pack map: %s" % error_string(pack_error))

	var save_error := ResourceSaver.save(packed, output_path)
	if save_error != OK:
		return _failure("Could not save draft: %s" % error_string(save_error))

	var uid_error := ResourceSaver.set_uid(output_path, map_uid)
	if uid_error != OK:
		return _failure("Could not preserve map UID: %s" % error_string(uid_error))

	var saved_uid_result := _read_scene_uid(output_path)
	if not saved_uid_result["ok"]:
		return saved_uid_result

	if saved_uid_result["value"] != map_uid:
		return _failure("Draft changed the source map UID.")

	var saved := ResourceLoader.load(
		output_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene

	if saved == null or not saved.can_instantiate():
		return _failure("Draft could not be reloaded.")

	if (
		saved.get_state().get_connection_count()
		!= map_scene.get_state().get_connection_count()
	):
		return _failure("Draft changed the map's saved signal-connection count.")

	var reloaded := saved.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	if reloaded == null:
		return _failure("Draft could not be instantiated.")

	var after := _scene_layout(reloaded)
	for node_path in before:
		if not after.has(node_path) or before[node_path] != after[node_path]:
			reloaded.free()
			return _failure("Existing map node changed during save: %s" % node_path)

	var added := reloaded.get_node_or_null(NodePath(node_name))
	var valid: bool = false

	if added != null:
		var status := UIAnchor2D.find_for(added)
		var target := TargetPoint2D.find_for(added)
		valid = (
			added is Node2D
			and added.scene_file_path == presentation_path
			and added.get_meta(&"entity_key", &"") == key
			and String(added.get_meta(&"entity_definition", &"")) == definition_id
			and status["ok"]
			and target["ok"]
		)

	reloaded.free()

	if not valid:
		return _failure("Draft failed its placement or scene-instance check.")

	return _success({
		"node_name": node_name,
		"entity_key": entity_key,
		"definition_id": definition_id,
		"existing_nodes_verified": true,
		"instance_verified": true,
		"uid_verified": true,
		"uid": ResourceUID.id_to_text(map_uid),
	})

func _read_scene_uid(path: String) -> Dictionary:
	var scene_file := FileAccess.open(path, FileAccess.READ)
	if scene_file == null:
		return _failure("Could not read scene header: %s" % path)

	var header := scene_file.get_line()
	scene_file.close()

	if not header.begins_with("[gd_scene "):
		return _failure("Expected a scene header: %s" % path)

	var uid_marker := "uid=\""
	var uid_start := header.find(uid_marker)
	if uid_start == -1:
		return _failure("Scene header has no UID: %s" % path)

	uid_start += uid_marker.length()
	var uid_end := header.find("\"", uid_start)
	if uid_end == -1:
		return _failure("Scene header has an incomplete UID: %s" % path)

	var uid_text := header.substr(uid_start, uid_end - uid_start)
	if not uid_text.begins_with("uid://"):
		return _failure("Scene header has an invalid UID: %s" % path)

	var uid := ResourceUID.text_to_id(uid_text)
	if uid == ResourceUID.INVALID_ID:
		return _failure("Scene header has an invalid UID: %s" % path)

	return _success(uid)

func _scene_layout(scene_root: Node) -> Dictionary:
	var nodes: Array[Node] = [scene_root]
	nodes.append_array(scene_root.find_children("*", "", true, false))
	var layout: Dictionary = {}

	for world_node in nodes:
		var script := world_node.get_script() as Script
		var script_path: String = "" if script == null else script.resource_path
		var scene_path: String = (
			"" if world_node == scene_root else world_node.scene_file_path
		)

		var transform_value: Variant = null
		if world_node is Node2D:
			transform_value = (world_node as Node2D).transform

		var metadata: Dictionary = {}
		for metadata_key in world_node.get_meta_list():
			metadata[metadata_key] = world_node.get_meta(metadata_key)

		var content_path := ""
		for property in world_node.get_property_list():
			if StringName(property["name"]) == &"content":
				var content_resource := world_node.get(&"content") as Resource
				if content_resource != null:
					content_path = content_resource.resource_path
				break

		layout[String(scene_root.get_path_to(world_node))] = [
			world_node.get_class(),
			script_path,
			scene_path,
			transform_value,
			metadata,
			content_path,
		]

	return layout

func _success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
