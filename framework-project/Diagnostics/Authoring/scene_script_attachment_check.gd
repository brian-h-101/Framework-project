extends SceneTree

const Graph = preload("res://Framework/Env/Authoring/Scenes/Inspection/scene_graph.gd")
const Editing = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_editing.gd")
const SceneScript = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_script.gd")
const PLAYER := "res://Framework/Content/Gameplay/Presentation/Entity/Player/player_2d.tscn"
const MAP := "res://Framework/Content/Gameplay/Maps/city.tscn"
const EXECUTOR := "res://Framework/Content/Gameplay/Profiles/Movement/Executor/movement_2d_executor.gd"
const FLAG := &"script_attachment_node_instantiated"

var _passed := true
var _folder := ""
var _files: Array[String] = []
var _hashes := {}


func _initialize() -> void:
	for path in [PLAYER, MAP, EXECUTOR]:
		_hashes[path] = FileAccess.get_sha256(path)
	_folder = "res://.godot/diagnostics/script_attachment_" + Crypto.new().generate_random_bytes(12).hex_encode()
	if DirAccess.make_dir_recursive_absolute(_folder) != OK:
		_check("Fixture folder created", false)
		_finish()
		return
	var base := _folder.path_join("base.gd")
	var script := _folder.path_join("attached.gd")
	_write(base, "extends Node2D\n@export var authored_note: String = \"default\"\nfunc _init() -> void:\n\tEngine.set_meta(&\"script_attachment_node_instantiated\", true)\n")
	_write(script, "extends \"%s\"\n" % base)
	var scene := _folder.path_join("entity.tscn")
	var uid := ResourceUID.id_to_text(ResourceUID.create_id())
	_write(scene, ("[gd_scene load_steps=1 format=3 uid=\"%s\"]\n\n" % uid
		+ "[node name=\"Entity\" type=\"Node2D\" unique_id=101]\nauthored_note = \"retained value\" ; keep comment\nposition = Vector2(12, 34)\nmetadata/entity_key = &\"stable_key\"\n\n"
		+ "[node name=\"Other\" type=\"Node2D\" parent=\".\" unique_id=102]\n\n"
		+ "[node name=\"Plain\" type=\"Node\" parent=\".\" unique_id=103]\n").replace("\n", "\r\n"))
	var inspected := SceneScript.inspect(script, "Node2D")
	_check("Inspection reports native base and inherited script hashes", inspected["ok"]
		and inspected["value"]["base_type"] == "Node2D"
		and inspected["value"]["dependency_hashes"].has(base))
	_check("Inspection does not instantiate the script", not Engine.has_meta(FLAG))
	_edit("Attach script to the scene root", scene, "attach_script", ".", script)
	var saved := FileAccess.get_file_as_string(scene)
	var graph := Graph.read(scene)
	_check("Graph reports attached script and switches available operations", graph["ok"]
		and graph["value"]["nodes"]["."]["script_path"] == script
		and graph["value"]["nodes"]["."]["has_script"]
		and graph["value"]["nodes"]["."]["can_remove_script"]
		and not graph["value"]["nodes"]["."]["can_attach_script"])
	_check("UID, node IDs, metadata, transforms and exported values survive", saved.contains("uid=\"%s\"" % uid)
		and saved.contains("unique_id=101") and saved.contains("unique_id=102")
		and saved.contains("metadata/entity_key = &\"stable_key\"") and saved.contains("position = Vector2(12, 34)")
		and saved.contains("authored_note = \"retained value\" ; keep comment") and saved.contains("\r\n"))
	_reject("Existing attachment", scene, _request(scene, "attach_script", ".", script))
	_reject("Incompatible native base", scene, _request(scene, "attach_script", "Plain", script))
	_reject("RefCounted gameplay executor", scene, _request(scene, "attach_script", "Other", EXECUTOR))
	_reject("Traversal script path", scene, _request(scene, "attach_script", "Other", "res://../outside.gd"))
	_reject("Node without an attachment", scene, _request(scene, "remove_script", "Other"))
	var uninspected := _request(scene, "attach_script", "Other", script)
	uninspected["expected_hashes"].erase(base)
	_reject("Uninspected base script", scene, uninspected)
	var stale := _request(scene, "attach_script", "Other", script)
	_write(base, FileAccess.get_file_as_string(base) + "\n# changed base script\n", false)
	_reject("Changed base script", scene, stale)
	_edit("Attach same script to another node", scene, "attach_script", "Other", script)
	_check("Existing script declaration is reused", FileAccess.get_file_as_string(scene).count("[ext_resource") == 1)
	var wrapper := _folder.path_join("wrapper.tscn")
	_write(wrapper, "[gd_scene format=3]\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"entity\"]\n[node name=\"Map\" type=\"Node2D\"]\n[node name=\"Placed\" parent=\".\" instance=ExtResource(\"entity\")]\n" % scene)
	_reject("Script inherited by a placement root", wrapper, _request(wrapper, "remove_script", "Placed"))
	_reject("Script on a borrowed descendant", wrapper, _request(wrapper, "remove_script", "Placed/Other"))
	_edit("Remove attached script", scene, "remove_script", ".")
	graph = Graph.read(scene)
	_check("Removal clears the attachment and preserves another node's shared script", graph["ok"]
		and not graph["value"]["nodes"]["."]["has_script"] and graph["value"]["nodes"]["."]["can_attach_script"]
		and graph["value"]["nodes"]["Other"]["script_path"] == script)
	_check("Removal retains saved exported values", FileAccess.get_file_as_string(scene).contains("authored_note = \"retained value\""))
	_edit("Reattach script using the retained declaration", scene, "attach_script", ".", script)
	_check("Editing never instantiated gameplay nodes", not Engine.has_meta(FLAG))
	var packed := ResourceLoader.load(scene, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var entity := packed.instantiate()
	_check("Reattached script receives retained exported values", entity.get("authored_note") == "retained value")
	entity.free()
	Engine.remove_meta(FLAG)
	var inline_scene := _folder.path_join("inline.tscn")
	_write(inline_scene, "[gd_scene load_steps=2 format=3]\n[sub_resource type=\"GDScript\" id=\"inline\"]\nscript/source = \"extends Node2D\\n\"\n[node name=\"Inline\" type=\"Node2D\"]\nscript = SubResource(\"inline\")\n")
	_edit("Remove an embedded script", inline_scene, "remove_script", ".")
	_finish()


func _request(scene: String, operation: String, target: String, script: String = "") -> Dictionary:
	var graph := Graph.read(scene)
	var hashes: Dictionary = graph["value"]["dependency_hashes"].duplicate()
	var selected: String = script if operation == "attach_script" else graph["value"]["nodes"][target]["script_path"]
	if not selected.is_empty():
		var inspected := SceneScript.inspect(selected, graph["value"]["nodes"][target]["type"])
		if inspected["ok"]:
			hashes.merge(inspected["value"]["dependency_hashes"], true)
	return {"operation": operation, "path": target, "script_path": script, "expected_hashes": hashes}


func _edit(label: String, scene: String, operation: String, target: String, script: String = "") -> void:
	var result := Editing.edit(scene, _request(scene, operation, target, script))
	_check(label, result["ok"])
	if not result["ok"]:
		print(result["error"])


func _reject(label: String, scene: String, request: Dictionary) -> void:
	var hash := FileAccess.get_sha256(scene)
	var result := Editing.edit(scene, request)
	_check(label + " rejected without writing", not result["ok"] and FileAccess.get_sha256(scene) == hash)


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
	for path: String in _hashes:
		_check("Production file preserved: %s" % path.get_file(), FileAccess.get_sha256(path) == _hashes[path])
	for path in _files:
		_check("Fixture removed: %s" % path.get_file(), DirAccess.remove_absolute(path) == OK)
	if not _folder.is_empty():
		var directory := DirAccess.open(_folder)
		_check("No pending files remain", directory != null and directory.get_files().is_empty())
		_check("Fixture folder removed", DirAccess.remove_absolute(_folder) == OK)
	print("[scene-script] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[scene-script] ", label, ": ", passed)
	_passed = _passed and passed
