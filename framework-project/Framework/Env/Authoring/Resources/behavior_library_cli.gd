extends SceneTree

const Library = preload("res://Framework/Env/Authoring/Resources/behavior_library_authoring.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var result: Dictionary
	if arguments.size() == 1 and arguments[0] == "catalogue":
		result = Library.catalogue()
	elif arguments.size() == 2 and arguments[0] in ["draft", "deletion-preview"]:
		var input := OS.read_string_from_stdin(1024 * 1024 + 1)
		var parser := JSON.new()
		if input.to_utf8_buffer().size() > 1024 * 1024 or parser.parse(input) != OK or not parser.data is Dictionary:
			result = Values.failure("Expected a Behavior library JSON request of at most 1 MiB.")
		else:
			result = Library.draft(arguments[1], parser.data) if arguments[0] == "draft" else Library.deletion_preview(arguments[1], parser.data)
	else:
		result = Values.failure("Expected catalogue, draft <path>, or deletion-preview <path>.")
	print("[behavior-library] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)
