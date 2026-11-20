extends SceneTree

const SceneGraph = preload("res://Framework/Env/Authoring/Scenes/scene_graph.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var result: Dictionary
	if arguments.size() == 1:
		result = SceneGraph.read(arguments[0])
	else:
		result = {
			"ok": false,
			"value": null,
			"error": "Expected one project-relative .tscn path.",
		}
	print("[scene-graph] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)
