extends SceneTree

const Inspection = preload("res://Framework/Env/Authoring/Resources/behavior_inspection.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var result: Dictionary
	if arguments.size() <= 1:
		result = Inspection.graph(arguments[0] if arguments.size() == 1 else "")
	else:
		result = Values.failure("Expected zero arguments or one project-relative .tres path.")
	print("[resource-graph] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)
