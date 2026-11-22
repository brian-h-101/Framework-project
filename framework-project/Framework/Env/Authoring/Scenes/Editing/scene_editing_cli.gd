extends SceneTree

const Editing = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_editing.gd")
const Document = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_document.gd")
const SceneScript = preload("res://Framework/Env/Authoring/Scenes/Editing/scene_script.gd")
const MovementCapability = preload("res://Framework/Env/Authoring/Scenes/Configuration/movement_capability.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var result: Dictionary
	if arguments.size() == 1 and arguments[0] == "node-types":
		result = Editing.node_types()
	elif arguments.size() == 3 and arguments[0] == "inspect-script":
		result = SceneScript.inspect(arguments[1], arguments[2])
	elif arguments.size() == 3 and arguments[0] == "inspect-properties":
		result = Editing.node_properties(arguments[1], arguments[2])
	elif arguments.size() == 3 and arguments[0] == "inspect-movement":
		result = MovementCapability.inspect(arguments[1], arguments[2])
	elif arguments.size() == 2 and arguments[0] == "edit":
		var text := OS.read_string_from_stdin(1024 * 1024 + 1)
		var parser := JSON.new()
		if text.to_utf8_buffer().size() > 1024 * 1024 or parser.parse(text) != OK or not parser.data is Dictionary:
			result = Document.failure("Expected a scene edit JSON object of at most 1 MiB on standard input.")
		else:
			result = Editing.edit(arguments[1], parser.data)
	elif arguments.size() == 3 and arguments[0] in ["plan-movement", "apply-movement"]:
		var text := OS.read_string_from_stdin(1024 * 1024 + 1)
		var parser := JSON.new()
		if text.to_utf8_buffer().size() > 1024 * 1024 or parser.parse(text) != OK or not parser.data is Dictionary:
			result = Document.failure("Expected movement options as a JSON object of at most 1 MiB.")
		elif arguments[0] == "plan-movement":
			result = MovementCapability.plan(arguments[1], arguments[2], parser.data)
		else:
			result = MovementCapability.apply(arguments[1], arguments[2], parser.data, parser.data.get("token"))
	else:
		result = Document.failure("Expected node-types, inspect-script, inspect-properties, edit, or a movement capability command.")
	print("[scene-editing] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)
