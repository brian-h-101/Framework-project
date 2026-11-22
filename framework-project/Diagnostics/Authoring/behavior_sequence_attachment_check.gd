extends SceneTree

const Graph = preload("res://Framework/Env/Authoring/Scenes/Inspection/scene_graph.gd")
const Editing = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_editing.gd")
const CONTENT = "res://Framework/Content/Gameplay/Profiles/Movement/Behavior/move.tres"
const COMPONENT = "res://Framework/Content/Universal/Interaction/based/Bindings/behavior_binding.gd"
var passed := true

func check(label: String, valid: bool) -> void:
	print("[sequence-attachment] %s: %s" % [label, valid])
	passed = passed and valid

func _initialize() -> void:
	var folder := "res://.godot/diagnostics/sequence_attach_" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("entity.tscn")
	var entity := Node2D.new()
	entity.name = "Entity"
	entity.set_meta(&"entity_definition", &"player")
	var scene := PackedScene.new()
	scene.pack(entity)
	entity.free()
	check("Temporary entity scene saved", ResourceSaver.save(scene, path) == OK)
	var graph: Dictionary = Graph.read(path)["value"]
	var hashes: Dictionary = graph["dependency_hashes"].duplicate()
	hashes[CONTENT] = FileAccess.get_sha256(CONTENT)
	hashes[COMPONENT] = FileAccess.get_sha256(COMPONENT)
	var request := {"operation": "attach_behavior", "path": ".", "name": "MoveBehavior", "behavior_resource": CONTENT, "expected_hashes": hashes}
	var result := Editing.edit(path, request)
	check("Unified Behavior attached through scene editor", result["ok"])
	if not result["ok"]:
		print(result)
	else:
		graph = Graph.read(path)["value"]
		check("Scene graph exposes binding identity and ownership", graph["nodes"]["MoveBehavior"]["behavior_id"] == "move" and graph["nodes"]["MoveBehavior"]["behavior_resource_path"] == CONTENT and graph["nodes"]["MoveBehavior"]["script_path"] == COMPONENT)
		hashes = graph["dependency_hashes"].duplicate()
		hashes[CONTENT] = FileAccess.get_sha256(CONTENT)
		hashes[COMPONENT] = FileAccess.get_sha256(COMPONENT)
		request["expected_hashes"] = hashes
		request["name"] = "DuplicateBehavior"
		var before := FileAccess.get_sha256(path)
		check("Duplicate activation rejected without changing scene", not Editing.edit(path, request)["ok"] and FileAccess.get_sha256(path) == before)
	check("Temporary scene removed", DirAccess.remove_absolute(path) == OK)
	check("Temporary directory removed", DirAccess.remove_absolute(folder) == OK)
	print("[sequence-attachment] Checks passed: %s" % passed)
	quit(0 if passed else 1)
