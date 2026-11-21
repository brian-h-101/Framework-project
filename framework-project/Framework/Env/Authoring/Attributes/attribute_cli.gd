extends SceneTree

const Inspection = preload("res://Framework/Env/Authoring/Attributes/attribute_inspection.gd")
const Editing = preload("res://Framework/Env/Authoring/Attributes/attribute_editing.gd")
const Values = preload("res://Framework/Env/Authoring/Attributes/attribute_values.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var result: Dictionary
	if arguments.size() == 2 and arguments[0] == "inspect":
		result = Inspection.inspect(arguments[1])
	elif arguments.size() == 2 and arguments[0] == "edit":
		var input := OS.read_string_from_stdin(1024 * 1024 + 1)
		var parser := JSON.new()
		if input.to_utf8_buffer().size() > 1024 * 1024:
			result = Values.failure("Attribute edit requests cannot exceed 1 MiB.")
		elif parser.parse(input) != OK or not parser.data is Dictionary:
			result = Values.failure("Expected an attribute edit JSON object on standard input.")
		else:
			result = Editing.edit(arguments[1], parser.data)
	else:
		result = Values.failure("Expected inspect <resource_path> or edit <resource_path> with JSON on standard input.")
	print("[resource-attribute] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)
