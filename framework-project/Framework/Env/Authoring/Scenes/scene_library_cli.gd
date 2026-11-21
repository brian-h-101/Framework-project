extends SceneTree

const Library = preload("res://Framework/Env/Authoring/Scenes/scene_library.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var result := Values.failure("Expected catalogue, draft <path>, or deletion-preview <path>.")
	if args.size() == 1 and args[0] == "catalogue":
		result = Library.catalogue()
	elif args.size() == 2 and args[0] in ["draft", "deletion-preview"]:
		var input := OS.read_string_from_stdin(1024 * 1024 + 1)
		var parsed: Variant = JSON.parse_string(input)
		if input.to_utf8_buffer().size() > 1024 * 1024 or not parsed is Dictionary:
			result = Values.failure("Expected a JSON request no larger than 1 MiB.")
		else:
			result = Library.draft(args[1], parsed) if args[0] == "draft" else Library.deletion_preview(args[1], parsed)
	print("[scene-library] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)
