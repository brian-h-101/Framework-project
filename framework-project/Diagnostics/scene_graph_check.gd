extends SceneTree

const SceneGraph = preload("res://Framework/Env/Authoring/Scenes/scene_graph.gd")
const CITY := "res://Games/ExampleGame/World/city_recreated.tscn"
const PLAYER := "res://Framework/Content/Presentation/Entity/Player/player_2d.tscn"
const CAMERA := "res://Framework/Content/Camera/player_camera_2d.tscn"
const INHERITED := "res://Diagnostics/Fixtures/SceneGraph/inherited.tscn"
const BASE := "res://Diagnostics/Fixtures/SceneGraph/base.tscn"
const COMPOSED := "res://Diagnostics/Fixtures/SceneGraph/composed.tscn"

var _passed := true


func _initialize() -> void:
	var scene_paths := [CITY, PLAYER, CAMERA, INHERITED, BASE, COMPOSED]
	var hashes: Dictionary = {}
	for scene_path: String in scene_paths:
		hashes[scene_path] = FileAccess.get_sha256(scene_path)
	var city := SceneGraph.read(CITY)
	_check("Map hierarchy loads", city["ok"])
	if city["ok"]:
		var graph: Dictionary = city["value"]
		var nodes: Dictionary = graph["nodes"]
		_check("Selected scene is the single root", graph["source_path"] == CITY and graph["root"] == ".")
		_check("Map children retain their order", nodes["."]["children"] == ["Ground", "Lighting", "Player", "Enemy"])
		_check("Entity instance identifies its source", nodes["Player"]["instance_path"] == PLAYER)
		_check("Nested moving body is expanded", nodes["Player/View2D"]["type"] == "CharacterBody2D")
		_check("Nested scene expands its own children", nodes["Player/View2D"]["children"].has("Player/View2D/Body"))
		_check("Camera instance identifies its source", nodes["Player/View2D/FollowCamera"]["instance_path"] == CAMERA)
		_check("Camera native type is preserved", nodes["Player/View2D/FollowCamera"]["type"] == "Camera2D")
		_check("Local instance declaration belongs to the map", nodes["Player"]["source_path"] == CITY and nodes["Player"]["source_node_path"] == "Player")
		_check("Nested declaration belongs to the presentation", nodes["Player/View2D/Body"]["source_path"] == PLAYER and nodes["Player/View2D/Body"]["source_node_path"] == "View2D/Body")
		_check("Attached script is available for navigation", nodes["Player/View2D"]["script_path"] == "res://Framework/Env/Movement/movement_2d.gd")
		_check("Dependencies include the nested camera", graph["dependencies"].has(CAMERA))

	var inherited := SceneGraph.read(INHERITED)
	_check("Inherited scene loads", inherited["ok"])
	if inherited["ok"]:
		var nodes: Dictionary = inherited["value"]["nodes"]
		_check("Inherited root can be renamed", nodes["."]["name"] == "Derived")
		_check("Base scene is available for navigation", nodes["."]["base_scene_path"] == BASE)
		_check("Unchanged base nodes remain visible", nodes["Kept"]["source_path"] == BASE)
		_check("Local override points to its declaring scene", nodes["Overridden"]["source_path"] == INHERITED and nodes["Overridden"]["type"] == "Node2D")
		_check("Local additions under base nodes remain visible", nodes["Kept/Added"]["type"] == "Marker2D")
	var composed := SceneGraph.read(COMPOSED)
	_check("Repeated scene instances load", composed["ok"])
	if composed["ok"]:
		var nodes: Dictionary = composed["value"]["nodes"]
		_check("Repeated instances have independent node paths", nodes.has("Left/Kept") and nodes.has("Right/Kept"))
		_check("Editable instance override retains its type", nodes["Left/Overridden"]["type"] == "Node2D")
		_check("Editable override navigates to its local declaration", nodes["Left/Overridden"]["source_path"] == COMPOSED and nodes["Right/Overridden"]["source_path"] == BASE)
		_check("Explicit sibling insertion is preserved", nodes["Left"]["children"] == ["Left/Kept", "Left/Inserted", "Left/Overridden"])
	_check("Reading scenes never instantiates gameplay nodes", not Engine.has_meta(&"scene_graph_node_was_instantiated"))
	_check("Traversal outside the project is rejected", not SceneGraph.read("res://../outside.tscn")["ok"])
	_check("Resources cannot be used as scenes", not SceneGraph.read("res://Framework/Content/Behavior/Action/change_health.tres")["ok"])
	_check("Missing scene is rejected", not SceneGraph.read("res://Diagnostics/Fixtures/SceneGraph/missing.tscn")["ok"])
	for scene_path: String in scene_paths:
		_check("Source unchanged: %s" % scene_path.get_file(), FileAccess.get_sha256(scene_path) == hashes[scene_path])
	print("[scene-graph-check] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[scene-graph-check] ", label, ": ", passed)
	_passed = _passed and passed
