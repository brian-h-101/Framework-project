extends SceneTree

const Library = preload("res://Framework/Env/Authoring/Scenes/Library/scene_library.gd")
const EntityPreset = preload("res://Framework/Env/Authoring/Scenes/Creation/entity_preset.gd")
const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var result := Values.failure("Expected catalogue, attribute-fragments, draft <path>, verify-entity <path>, or deletion-preview <path>.")
	if args.size() == 1 and args[0] == "catalogue":
		result = Library.catalogue()
	elif args.size() == 1 and args[0] == "attribute-fragments":
		result = EntityPreset.fragments()
	elif args.size() == 2 and args[0] in ["draft", "verify-entity", "deletion-preview"]:
		var input := OS.read_string_from_stdin(1024 * 1024 + 1)
		var parsed: Variant = JSON.parse_string(input)
		if input.to_utf8_buffer().size() > 1024 * 1024 or not parsed is Dictionary:
			result = Values.failure("Expected a JSON request no larger than 1 MiB.")
		else:
			match args[0]:
				"draft":
					result = Library.draft(args[1], parsed)
				"verify-entity":
					result = Library.verify_entity(args[1], parsed)
				"deletion-preview":
					result = Library.deletion_preview(args[1], parsed)
	print("[scene-library] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)
