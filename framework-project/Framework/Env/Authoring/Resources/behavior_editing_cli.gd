extends SceneTree

const Editing = preload("res://Framework/Env/Authoring/Resources/behavior_editing.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var result: Dictionary
	if arguments.size() == 1:
		var input := OS.read_string_from_stdin(1024 * 1024 + 1)
		var parsed := JSON.new()
		if input.to_utf8_buffer().size() > 1024 * 1024 or parsed.parse(input) != OK or not parsed.data is Dictionary:
			result = Values.failure("Expected a behavior edit JSON object of at most 1 MiB on standard input.")
		else:
			result = Editing.edit(arguments[0], parsed.data)
	else:
		result = Values.failure("Expected a behavior Resource path with JSON on standard input.")
	print("[behavior-editing] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)
