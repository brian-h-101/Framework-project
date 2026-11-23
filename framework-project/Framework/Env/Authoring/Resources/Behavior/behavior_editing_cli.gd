extends SceneTree

const Editing = preload("res://Framework/Env/Authoring/Resources/Behavior/behavior_editing.gd")
const StartingPresets = preload("res://Framework/Env/Authoring/Resources/Presentation/starting_preset_authoring.gd")
const InputConfiguration = preload("res://Framework/Env/Authoring/Resources/Configuration/input_configuration_authoring.gd")
const MovementConfiguration = preload("res://Framework/Env/Authoring/Resources/Configuration/movement_configuration_authoring.gd")
const MovementController = preload("res://Framework/Env/Authoring/Resources/Configuration/movement_controller_authoring.gd")
const CustomConfiguration = preload("res://Framework/Env/Authoring/Resources/Configuration/custom_configuration_authoring.gd")
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
			if parsed.data.get("operation") in InputConfiguration.OPERATIONS:
				result = InputConfiguration.edit(arguments[0], parsed.data)
			elif parsed.data.get("operation") in MovementConfiguration.OPERATIONS:
				result = MovementConfiguration.edit(arguments[0], parsed.data)
			elif parsed.data.get("operation") == MovementController.OPERATION:
				result = MovementController.draft(arguments[0], parsed.data)
			elif parsed.data.get("operation") in CustomConfiguration.OPERATIONS:
				result = CustomConfiguration.edit(arguments[0], parsed.data)
			elif parsed.data.get("presentation_preset") == true:
				result = StartingPresets.edit(arguments[0], parsed.data)
			else:
				result = Editing.edit(arguments[0], parsed.data)
	else:
		result = Values.failure("Expected a behavior Resource path with JSON on standard input.")
	print("[behavior-editing] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)
