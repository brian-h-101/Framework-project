extends SceneTree

const Graph = preload("res://Framework/Env/Authoring/Scenes/scene_graph.gd")
const Editing = preload("res://Framework/Env/Authoring/Scenes/scene_editing.gd")
const Catalog = preload("res://Framework/Env/Authoring/Scenes/movement_configuration_catalog.gd")
const Entry = preload("res://Framework/Infrastructure/API/Runtime/game_entry.gd")
const Setup = preload("res://Framework/Env/Setup/game_setup.gd")
const CONFIG := "res://Framework/Content/Configuration/Movement/player_movement.tres"
const ADAPTER := "res://Framework/Content/God/Movement/movement_2d.gd"
const PLAYER := "res://Framework/Content/Presentation/Entity/Player/player_2d.tscn"
const MAP := "res://Framework/Content/Maps/city_recreated.tscn"
const WRONG_TYPE := "res://Framework/Content/Behavior/Condition/actor_strength.tres"

var _passed := true
var _folder := ""
var _files: Array[String] = []
var _originals := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in [CONFIG, ADAPTER, PLAYER, MAP, WRONG_TYPE]:
		_originals[path] = FileAccess.get_sha256(path)
	var catalog := Catalog.read()
	_check("Catalogue includes only typed movement configurations", catalog["ok"])
	if catalog["ok"]:
		var paths: Array[String] = []
		for entry: Dictionary in catalog["value"]["configurations"]:
			paths.append(entry["source_path"])
			_check("Catalogue tracks the chosen Action", entry["action_id"] == "move" and entry["behavior_id"] == "movement_2d")
		var sorted := paths.duplicate()
		sorted.sort()
		_check("Catalogue is sorted and finds the nested movement folder", paths == sorted and paths.has(CONFIG))
	_folder = "res://.godot/diagnostics/movement_assignment_" + Crypto.new().generate_random_bytes(12).hex_encode()
	if DirAccess.make_dir_recursive_absolute(_folder) != OK:
		_check("Temporary folder created", false)
		_finish()
		return
	var first := _folder.path_join("first.tres")
	var second := _folder.path_join("second.tres")
	var action_path := _folder.path_join("move.tres")
	var invalid_path := _folder.path_join("invalid.tres")
	var authored: Resource = load(CONFIG)
	var local_action: Resource = authored.movement_action.duplicate(true)
	_save(action_path, local_action)
	var first_config: Resource = authored.duplicate(true)
	first_config.movement_action = ResourceLoader.load(action_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	first_config.pixels_per_unit = 10.0
	_save(first, first_config)
	var second_config: Resource = first_config.duplicate(true)
	second_config.pixels_per_unit = 20.0
	_save(second, second_config)
	var invalid: Resource = first_config.duplicate(true)
	invalid.pixels_per_unit = 0.0
	_save(invalid_path, invalid)
	var scene := _folder.path_join("entity.tscn")
	var uid := ResourceUID.id_to_text(ResourceUID.create_id())
	var original := ("[gd_scene load_steps=2 format=3 uid=\"%s\"]\n\n" % uid
		+ "[ext_resource type=\"Script\" path=\"%s\" id=\"adapter\"]\n\n" % ADAPTER
		+ "[node name=\"Entity\" type=\"Node2D\" unique_id=101]\nmetadata/entity_key = &\"player\"\n\n"
		+ "[node name=\"Locomotion\" type=\"CharacterBody2D\" parent=\".\" unique_id=102]\n"
		+ "script = ExtResource(\"adapter\")\nposition = Vector2(17, 23) ; keep this comment\nmetadata/entity_spatial_root = true\n\n"
		+ "[node name=\"Status\" type=\"Marker2D\" parent=\"Locomotion\" unique_id=103]\nposition = Vector2(0, -20)\n")
	_write(scene, original.replace("\n", "\r\n"))
	var request := _request(scene, "Locomotion", first)
	var assigned := Editing.edit(scene, request)
	_check("Assigns configuration without adding or renaming nodes", assigned["ok"])
	if not assigned["ok"]:
		print(assigned["error"])
		_finish()
		return
	var saved := FileAccess.get_file_as_string(scene)
	_check("UID, node IDs, transforms, metadata and comments survive", saved.contains("uid=\"%s\"" % uid)
		and saved.contains("unique_id=102") and saved.contains("unique_id=103")
		and saved.contains("position = Vector2(17, 23) ; keep this comment")
		and saved.contains("metadata/entity_key = &\"player\"") and saved.contains("metadata/entity_spatial_root = true")
		and saved.contains("load_steps=3") and saved.contains("\r\n") and not saved.replace("\r\n", "").contains("\n"))
	_reject("Repeated assignment", scene, _request(scene, "Locomotion", first))
	_reject("Unrelated node", scene, _request(scene, "Locomotion/Status", second))
	_reject("Wrong Resource type", scene, _request(scene, "Locomotion", WRONG_TYPE))
	_reject("Invalid movement settings", scene, _request(scene, "Locomotion", invalid_path))
	_reject("Traversal path", scene, _request(scene, "Locomotion", "res://../outside.tres"))
	var missing := _request(scene, "Locomotion", second)
	missing["expected_hashes"].erase(ADAPTER)
	_reject("Uninspected adapter", scene, missing)
	missing = _request(scene, "Locomotion", second)
	missing["expected_hashes"].erase(action_path)
	_reject("Uninspected Action dependency", scene, missing)
	var stale := _request(scene, "Locomotion", second)
	_write(action_path, FileAccess.get_file_as_string(action_path) + "\n; changed Action dependency\n", false)
	_reject("Changed Action dependency", scene, stale)
	stale = _request(scene, "Locomotion", second)
	_write(second, FileAccess.get_file_as_string(second) + "\n; changed configuration\n", false)
	_reject("Changed configuration", scene, stale)
	var replacement := Editing.edit(scene, _request(scene, "Locomotion", second))
	_check("A different configuration replaces the reference", replacement["ok"])
	var graph := Graph.read(scene)
	_check("Reloaded graph reports the replacement and original hierarchy", graph["ok"]
		and graph["value"]["nodes"].size() == 3
		and graph["value"]["nodes"]["Locomotion"]["movement_configuration_path"] == second)
	var before_reuse := FileAccess.get_file_as_string(scene)
	var reused := Editing.edit(scene, _request(scene, "Locomotion", first))
	_check("Existing resource declaration is reused", reused["ok"]
		and FileAccess.get_file_as_string(scene).count("[ext_resource") == before_reuse.count("[ext_resource"))
	var root_body := _folder.path_join("root_body.tscn")
	_write(root_body, "[gd_scene load_steps=2 format=3]\n[ext_resource type=\"Script\" path=\"%s\" id=\"adapter\"]\n[node name=\"Body\" type=\"CharacterBody2D\"]\nscript = ExtResource(\"adapter\")" % ADAPTER)
	var root_assigned := Editing.edit(root_body, _request(root_body, ".", first))
	_check("Root movement body supports a source without a final newline", root_assigned["ok"])
	var wrapper := _folder.path_join("wrapper.tscn")
	_write(wrapper, "[gd_scene format=3]\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"entity\"]\n[node name=\"Map\" type=\"Node2D\"]\n[node name=\"Placed\" parent=\".\" instance=ExtResource(\"entity\")]\n" % scene)
	_reject("Instanced body remains owned by its source", wrapper, _request(wrapper, "Placed/Locomotion", second))
	await _check_runtime(scene, first, second)
	_finish()


func _check_runtime(scene: String, first: String, second: String) -> void:
	var entry := Entry.new()
	var started := entry.start(Setup.new())
	_check("Runtime starts with the Content executor", started["ok"])
	if not started["ok"]:
		return
	var velocities: Array[float] = []
	for configuration in [first, second]:
		var graph := Graph.read(scene)
		if graph["value"]["nodes"]["Locomotion"]["movement_configuration_path"] != configuration:
			var assigned := Editing.edit(scene, _request(scene, "Locomotion", configuration))
			_check("Runtime fixture assignment succeeds", assigned["ok"])
		var packed := ResourceLoader.load(scene, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		var entity := packed.instantiate()
		var body := entity.get_node("Locomotion") as CharacterBody2D
		body.call("configure_entity", entry.world_bridge, entity)
		var bound := entry.world_bridge.bind_entity(entry.entity_ids[&"player"], entity)
		_check("Saved entity binds to its persistent runtime identity", bound["ok"])
		root.add_child(entity)
		body.set_physics_process(false)
		var calculated: Dictionary = body.call("_execute_movement", Vector2.RIGHT)
		_check("Saved configuration invokes the movement Action", calculated["ok"])
		if calculated["ok"]:
			velocities.append(calculated["value"].x)
		entry.world_bridge.unbind_entity(entry.entity_ids[&"player"])
		entity.free()
	_check("Changing the assigned configuration changes runtime pixel velocity", velocities.size() == 2
		and velocities[0] > 0.0 and is_equal_approx(velocities[1], velocities[0] * 2.0))
	entry.stop()
	await process_frame


func _request(scene: String, target: String, configuration: String) -> Dictionary:
	var graph := Graph.read(scene)
	var hashes: Dictionary = graph["value"]["dependency_hashes"].duplicate()
	hashes[ADAPTER] = FileAccess.get_sha256(ADAPTER)
	var current: String = graph["value"]["nodes"][target]["movement_configuration_path"]
	if not current.is_empty():
		hashes[current.get_slice("::", 0)] = FileAccess.get_sha256(current.get_slice("::", 0))
	var inspected := Catalog.inspect(configuration)
	if inspected["ok"]:
		hashes.merge(inspected["value"]["dependency_hashes"], true)
	return {"operation": "assign_movement", "path": target, "movement_configuration": configuration, "expected_hashes": hashes}


func _reject(label: String, scene: String, request: Dictionary) -> void:
	var hash := FileAccess.get_sha256(scene)
	var result := Editing.edit(scene, request)
	_check(label + " rejected without writing", not result["ok"] and FileAccess.get_sha256(scene) == hash)
	if result["ok"]:
		print("Unexpected success: ", result)


func _save(path: String, resource: Resource) -> void:
	_check("Fixture saved: %s" % path.get_file(), ResourceSaver.save(resource, path) == OK)
	_files.append(path)


func _write(path: String, text: String, track: bool = true) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("Fixture written", false)
		return
	file.store_string(text)
	file.close()
	if track:
		_files.append(path)


func _finish() -> void:
	for path: String in _originals:
		_check("Production source unchanged: %s" % path.get_file(), FileAccess.get_sha256(path) == _originals[path])
	for path in _files:
		_check("Temporary file removed: %s" % path.get_file(), DirAccess.remove_absolute(path) == OK)
	if not _folder.is_empty():
		var directory := DirAccess.open(_folder)
		_check("No pending files remain", directory != null and directory.get_files().is_empty())
		_check("Temporary folder removed", DirAccess.remove_absolute(_folder) == OK)
	print("[movement-assignment] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[movement-assignment] ", label, ": ", passed)
	_passed = _passed and passed
