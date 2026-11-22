extends SceneTree

const GroundConfiguration = preload("res://Framework/Content/Universal/Map/based/Configuration/ground_resource.gd")
const LightingConfiguration = preload("res://Framework/Content/Universal/Lighting/based/Configuration/lighting_2d_resource.gd")

const SceneDefaults = preload(
	"res://Framework/Content/Configuration/Map/scene_defaults.tres"
)
const GroundLayer = preload(
	"res://Framework/Content/Universal/Map/based/Rendering2D/tile_map_layer_2d.gd"
)
const LightingEnvironment = preload(
	"res://Framework/Content/Universal/Lighting/based/Rendering2D/lighting_2d.gd"
)


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var result: Dictionary

	if arguments.size() == 3 and arguments[0] == "create":
		result = _create_map(arguments[1], arguments[2])
	else:
		result = _failure("Expected create <scene_name> <output_path>.")

	print("[authoring-result] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)


func _create_map(scene_name: String, output_path: String) -> Dictionary:
	if not scene_name.is_valid_identifier():
		return _failure("Scene name must be a valid identifier.")

	if output_path.get_extension().to_lower() != "tscn":
		return _failure("Output must be a .tscn file.")

	if FileAccess.file_exists(output_path):
		return _failure("Scene already exists: %s" % output_path)

	var checked := SceneDefaults.read()
	if not checked["ok"]:
		return checked
	var definition: Dictionary = checked["value"]
	var ground_content := definition["ground_content"] as GroundConfiguration
	var lighting_content := definition["lighting_content"] as LightingConfiguration

	if ground_content == null or lighting_content == null:
		return _failure("The map preset requires ground and lighting resources.")

	var scene_root := Node2D.new()
	scene_root.name = StringName(scene_name)

	var ground := GroundLayer.new()
	ground.name = &"Ground"
	ground.z_index = -1
	ground.content = ground_content
	ground.set_meta(&"receives_shadow", true)
	scene_root.add_child(ground)
	ground.owner = scene_root

	var lighting := LightingEnvironment.new()
	lighting.name = &"Lighting"
	lighting.content = lighting_content
	scene_root.add_child(lighting)
	lighting.owner = scene_root

	var packed := PackedScene.new()
	var pack_error := packed.pack(scene_root)
	scene_root.free()

	if pack_error != OK:
		return _failure("Could not pack map: %s" % error_string(pack_error))

	var save_error := ResourceSaver.save(packed, output_path)
	if save_error != OK:
		return _failure("Could not save map: %s" % error_string(save_error))

	var scene_uid := ResourceUID.create_id()
	var uid_error := ResourceSaver.set_uid(output_path, scene_uid)
	if uid_error != OK:
		return _failure("Could not assign map UID: %s" % error_string(uid_error))

	return _verify_saved_map(
		output_path,
		scene_name,
		ground_content,
		lighting_content,
		scene_uid
	)


func _verify_saved_map(
	path: String,
	scene_name: String,
	ground_content: GroundConfiguration,
	lighting_content: LightingConfiguration,
	expected_uid: int
) -> Dictionary:
	var saved := ResourceLoader.load(
		path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene

	if saved == null or not saved.can_instantiate():
		return _failure("Saved map could not be loaded.")

	var scene_root := saved.instantiate()
	if scene_root == null:
		return _failure("Saved map could not be instantiated.")

	var ground := scene_root.get_node_or_null("Ground") as TileMapLayer
	var lighting := scene_root.get_node_or_null("Lighting") as Node2D

	var structure_verified: bool = (
		scene_root is Node2D
		and scene_root.name == StringName(scene_name)
		and scene_root.get_child_count() == 2
		and scene_root.find_children("*", "", true, false).size() == 2
		and ground != null
		and lighting != null
	)

	var content_verified: bool = false
	if structure_verified:
		content_verified = (
			ground.owner == scene_root
			and lighting.owner == scene_root
			and ground.get_script() == GroundLayer
			and lighting.get_script() == LightingEnvironment
			and ground.get(&"content") == ground_content
			and lighting.get(&"content") == lighting_content
			and ground.z_index == -1
			and ground.get_meta(&"receives_shadow", false) == true
		)

	scene_root.free()

	if not structure_verified:
		return _failure("Saved map failed its node structure check.")

	if not content_verified:
		return _failure("Saved map failed its scripts or configuration check.")

	var scene_file := FileAccess.open(path, FileAccess.READ)
	if scene_file == null:
		return _failure("Could not read the saved map header.")

	var header := scene_file.get_line()
	scene_file.close()
	var uid_marker := "uid=\"%s\"" % ResourceUID.id_to_text(expected_uid)
	if not header.begins_with("[gd_scene ") or not header.contains(uid_marker):
		return _failure("Saved map did not retain its assigned UID.")

	return _success({
		"node_name": scene_name,
		"root_type": "Node2D",
		"structure_verified": structure_verified,
		"content_verified": content_verified,
		"uid": ResourceUID.id_to_text(expected_uid),
	})


func _success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
