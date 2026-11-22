extends SceneTree

const Graph = preload("res://Framework/Env/Authoring/Scenes/Inspection/scene_graph.gd")
const Editing = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_editing.gd")
const Document = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_document.gd")
const BASE = "res://Diagnostics/Fixtures/SceneGraph/base.tscn"
const INHERITED = "res://Diagnostics/Fixtures/SceneGraph/inherited.tscn"
const COMPOSED = "res://Diagnostics/Fixtures/SceneGraph/composed.tscn"
const PROBE = "res://Diagnostics/Fixtures/SceneGraph/node_init_probe.gd"

var _passed := true
var _folder: String
var _files: Array[String] = []
var _hashes := {}


func _initialize() -> void:
	for path in [BASE, INHERITED, COMPOSED, PROBE]:
		_hashes[path] = FileAccess.get_sha256(path)
	for path in [BASE, INHERITED, COMPOSED, "res://Framework/Content/Gameplay/Maps/city_recreated.tscn", "res://Framework/Content/Gameplay/Presentation/Entity/Player/player_2d.tscn", "res://Framework/Content/Gameplay/UI/HUD/ui_root.tscn"]:
		_check("Document parser accepts existing scene: %s" % String(path).get_file(), Document.parse(FileAccess.get_file_as_string(path))["ok"])
	var inherited := Graph.read(INHERITED)
	var composed := Graph.read(COMPOSED)
	_check("Inherited overrides do not acquire structural ownership", (
		inherited["ok"] and inherited["value"]["nodes"]["Overridden"]["source_path"] == INHERITED
		and inherited["value"]["nodes"]["Overridden"]["structural_scene"] == BASE
		and not inherited["value"]["nodes"]["Overridden"]["can_rename"]
		and inherited["value"]["nodes"]["Kept/Added"]["can_rename"]
	))
	_check("Instance roots and local additions are editable", (
		composed["ok"] and composed["value"]["nodes"]["Left"]["can_rename"]
		and not composed["value"]["nodes"]["Left/Overridden"]["can_remove"]
		and composed["value"]["nodes"]["Left/Inserted"]["can_remove"]
		and composed["value"]["nodes"]["Left/Overridden"]["instance_boundary"] == "Left"
	))
	var types := Editing.node_types()
	_check("Native type catalogue supports 2D, 3D and plain nodes", types["ok"] and types["value"].has("Node") and types["value"].has("Node2D") and types["value"].has("Node3D") and types["value"].has("Control") and not types["value"].has("RefCounted"))
	_folder = "res://.godot/diagnostics/scene_editing_" + Crypto.new().generate_random_bytes(12).hex_encode()
	if DirAccess.make_dir_recursive_absolute(_folder) != OK:
		_check("Fixture folder created", false)
		_finish()
		return
	var scene := _folder.path_join("scene.tscn")
	var uid := ResourceUID.id_to_text(ResourceUID.create_id())
	var source := "[gd_scene load_steps=2 format=3 uid=\"%s\"]\n\n[ext_resource type=\"Script\" path=\"%s\" id=\"probe\"]\n\n[node name=\"Scene\" type=\"Node2D\" unique_id=101]\nscript = ExtResource(\"probe\")\nmetadata/entity_key = &\"stable_identity\"\nmetadata/message = \"Lamp and [node fake] stay text\"\n\n[node name=\"Props\" type=\"Node2D\" parent=\".\" unique_id=102]\n\n[node name=\"Lamp\" type=\"Node2D\" parent=\"Props\" unique_id=103 groups=[\"lights\"]]\nposition = Vector2(12, 34)\n\n[node name=\"Shade\" type=\"Marker2D\" parent=\"Props/Lamp\" unique_id=104]\nmetadata/up = NodePath(\"..:position\")\n\n[node name=\"Watcher\" type=\"RemoteTransform2D\" parent=\".\" unique_id=105]\nremote_path = NodePath(\"../Props/Lamp\")\nmetadata/links = {\"nested\": [NodePath(\"../Props/Lamp/Shade\")]}\n\n[connection signal=\"tree_entered\" from=\"Props/Lamp\" to=\"Watcher\" method=\"show\"]\n" % [uid, PROBE]
	_write(scene, source.replace("\n", "\r\n"))
	_edit("Nested native node insertion", scene, "add_node", "Props", {"name": "New Point 雨", "node_type": "Marker2D"})
	_reject("Duplicate sibling", scene, "add_node", "Props", {"name": "Lamp", "node_type": "Node2D"})
	_reject("Non-node native type", scene, "add_node", ".", {"name": "Bad", "node_type": "Resource"})
	_reject("Invalid node name", scene, "add_node", ".", {"name": "bad/name", "node_type": "Node"})
	_reject("Root rename", scene, "rename", ".", {"name": "Other"})
	_reject("Root removal", scene, "remove", ".")
	_edit("Subtree rename", scene, "rename", "Props/Lamp", {"name": "Lantern"})
	var text := FileAccess.get_file_as_string(scene)
	_check("Rename repairs descendant, connection and nested NodePaths", (
		text.contains("parent=\"Props/Lantern\"") and text.contains("from=\"Props/Lantern\"")
		and text.contains("NodePath(\"../Props/Lantern\")")
		and text.contains("NodePath(\"../Props/Lantern/Shade\")")
	))
	_check("UID, node IDs, metadata and geometry remain intact", (
		text.contains("uid=\"%s\"" % uid) and text.contains("unique_id=103")
		and text.contains("metadata/entity_key = &\"stable_identity\"")
		and text.contains("metadata/message = \"Lamp and [node fake] stay text\"")
		and text.contains("position = Vector2(12, 34)") and text.contains("\r\n")
	))
	_reject("Dangling reference on removal", scene, "remove", "Props/Lantern")
	_edit("Remove reference owner", scene, "remove", "Watcher")
	_edit("Remove nested subtree", scene, "remove", "Props/Lantern")
	text = FileAccess.get_file_as_string(scene)
	_check("Removed subtree and associated connections disappear", not text.contains("name=\"Shade\"") and not text.contains("[connection"))
	_edit("External scene placement", scene, "add_instance", "Props", {"name": "Guard", "instance_scene": BASE})
	_edit("Local child under an instance root", scene, "add_node", "Props/Guard", {"name": "LocalTag", "node_type": "Marker2D"})
	_reject("Borrowed descendant rename", scene, "rename", "Props/Guard/Kept", {"name": "Other"})
	_edit("Scene instance placement rename", scene, "rename", "Props/Guard", {"name": "Sentinel"})
	var graph := Graph.read(scene)
	_check("Renaming placement preserves its shared scene and local child", graph["ok"] and graph["value"]["nodes"]["Props/Sentinel"]["instance_path"] == BASE and graph["value"]["nodes"].has("Props/Sentinel/LocalTag"))
	_reject("Direct instance cycle", scene, "add_instance", ".", {"name": "Cycle", "instance_scene": scene})
	_edit("Remove scene instance and its local additions", scene, "remove", "Props/Sentinel")

	var derived := _folder.path_join("derived.tscn")
	_write(derived, "[gd_scene format=3]\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"base\"]\n[node name=\"Derived\" instance=ExtResource(\"base\")]\n[node name=\"Overridden\" parent=\".\"]\nposition = Vector2(5, 6)\n[node name=\"Local\" type=\"Marker2D\" parent=\"Kept\"]\n" % BASE)
	_reject("Inherited structural edit", derived, "remove", "Overridden")
	_edit("Add child to inherited scene root", derived, "add_node", ".", {"name": "Added", "node_type": "Node3D"})
	_edit("Rename local addition under inherited parent", derived, "rename", "Kept/Local", {"name": "Renamed"})
	var indexed := _folder.path_join("indexed.tscn")
	_write(indexed, "[gd_scene format=3]\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"base\"]\n[node name=\"Root\" type=\"Node2D\"]\n[node name=\"Placement\" parent=\".\" instance=ExtResource(\"base\")]\n[node name=\"Inserted\" type=\"Marker2D\" parent=\"Placement\" index=\"1\"]\n[editable path=\"Placement\"]\n" % BASE)
	_edit("Rename indexed local child without reordering", indexed, "rename", "Placement/Inserted", {"name": "Renamed"})
	_edit("Rename editable scene placement", indexed, "rename", "Placement", {"name": "Moved"})
	_check("Editable paths are repaired", FileAccess.get_file_as_string(indexed).contains("[editable path=\"Moved\"]"))
	var real_map := _folder.path_join("map_environment.tscn")
	var city := "res://Framework/Content/Gameplay/Maps/city_recreated.tscn"
	_hashes[city] = FileAccess.get_sha256(city)
	_write(real_map, "[gd_scene format=3]\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"map\"]\n[node name=\"CheckMap\" instance=ExtResource(\"map\")]\n[node name=\"LocalProbe\" type=\"Marker2D\" parent=\".\"]\n" % city)
	_edit("Rename local addition alongside real map dependencies", real_map, "rename", "LocalProbe", {"name": "RenamedProbe"})

	var template := _folder.path_join("template.tscn")
	_write(template, "[gd_scene format=3]\n[node name=\"Template\" type=\"Node2D\"]\n[node name=\"Remote\" type=\"RemoteTransform2D\" parent=\".\"]\nremote_path = NodePath(\"../../Lamp\")\n")
	var borrowed := _folder.path_join("borrowed.tscn")
	_write(borrowed, "[gd_scene format=3]\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"template\"]\n[node name=\"Root\" type=\"Node2D\"]\n[node name=\"Lamp\" type=\"Node2D\" parent=\".\"]\n[node name=\"Placement\" parent=\".\" instance=ExtResource(\"template\")]\n" % template)
	_reject("Foreign reference cannot be repaired by changing shared source", borrowed, "rename", "Lamp", {"name": "Renamed"})
	var stale := Graph.read(borrowed)
	var previous := FileAccess.get_file_as_string(template)
	_write(template, previous + "\n; external dependency changed\n", false)
	_reject("Changed dependency", borrowed, "add_node", ".", {"name": "New", "node_type": "Node", "expected_hashes": stale["value"]["dependency_hashes"]})
	_edit("Fresh inspection permits retry", borrowed, "add_node", ".", {"name": "New", "node_type": "Node"})

	var animated := _folder.path_join("animated.tscn")
	_write(animated, "[gd_scene format=3]\n[sub_resource type=\"Animation\" id=\"anim\"]\ntracks/0/type = \"value\"\ntracks/0/path = NodePath(\"Lamp:position\")\n[node name=\"Root\" type=\"Node2D\"]\nmetadata/animation = SubResource(\"anim\")\n[node name=\"Lamp\" type=\"Node2D\" parent=\".\"]\n")
	_reject("Unresolved animation reference", animated, "rename", "Lamp", {"name": "Other"})
	var unique := _folder.path_join("unique.tscn")
	_write(unique, "[gd_scene format=3]\n[node name=\"Root\" type=\"Node2D\"]\nmetadata/path = NodePath(\"%Lamp\")\n[node name=\"Lamp\" type=\"Node2D\" parent=\".\"]\nunique_name_in_owner = true\n")
	_reject("Unique-name reference", unique, "rename", "Lamp", {"name": "Other"})
	_check("Editing never instantiates gameplay nodes", not Engine.has_meta(&"scene_graph_node_was_instantiated"))
	for path: String in _hashes:
		_check("Production fixture unchanged: %s" % path.get_file(), FileAccess.get_sha256(path) == _hashes[path])
	_finish()


func _request(path: String, operation: String, target: String, extras: Dictionary) -> Dictionary:
	var read := Graph.read(path)
	if not read["ok"]:
		return {"operation": operation, "path": target, "expected_hashes": {}}
	var hashes: Dictionary = read["value"]["dependency_hashes"].duplicate()
	if operation == "add_instance":
		var instance := Graph.read(String(extras.get("instance_scene", "")))
		if instance["ok"]:
			hashes.merge(instance["value"]["dependency_hashes"])
	var request := {"operation": operation, "path": target, "expected_hashes": hashes}
	request.merge(extras, true)
	return request


func _edit(label: String, path: String, operation: String, target: String, extras: Dictionary = {}) -> void:
	var result := Editing.edit(path, _request(path, operation, target, extras))
	_check(label, result["ok"])
	if not result["ok"]:
		print(result["error"])


func _reject(label: String, path: String, operation: String, target: String, extras: Dictionary = {}) -> void:
	var hash := FileAccess.get_sha256(path)
	var result := Editing.edit(path, _request(path, operation, target, extras))
	_check(label + " rejected without writing", not result["ok"] and FileAccess.get_sha256(path) == hash)
	if result["ok"]:
		print("Unexpected success: ", result)


func _write(path: String, source: String, add: bool = true) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("Fixture write", false)
		return
	file.store_string(source)
	file.close()
	if add:
		_files.append(path)


func _finish() -> void:
	for path in _files:
		if FileAccess.file_exists(path):
			_check("Temporary scene removed: %s" % path.get_file(), DirAccess.remove_absolute(path) == OK)
	if not _folder.is_empty() and DirAccess.dir_exists_absolute(_folder):
		var directory := DirAccess.open(_folder)
		_check("No staging files remain", directory != null and directory.get_files().is_empty())
		_check("Temporary folder removed", DirAccess.remove_absolute(_folder) == OK)
	print("[scene-editing] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[scene-editing] ", label, ": ", passed)
	_passed = _passed and passed
