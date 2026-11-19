extends SceneTree

const ConditionAssignment = preload(
	"res://Framework/Env/Authoring/condition_assignment.gd"
)

const RESULT_PREFIX := "[condition-assignment-result] "


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var result: Dictionary

	if arguments.size() == 3 and arguments[0] == "add-condition":
		result = ConditionAssignment.add_condition(
			arguments[1],
			arguments[2]
		)
	elif arguments.size() == 3 and arguments[0] == "set-requirements":
		result = ConditionAssignment.set_requirements(
			arguments[1],
			arguments[2]
		)
	elif arguments.size() == 3 and arguments[0] == "set-action":
		result = ConditionAssignment.set_action(
			arguments[1],
			arguments[2]
		)
	elif (
		arguments.size() == 3
		and arguments[0] == "resolve-interaction-source"
	):
		result = ConditionAssignment.resolve_interaction_source(
			arguments[1],
			arguments[2]
		)
	else:
		result = {
			"ok": false,
			"value": null,
			"error": (
				"Expected add-condition <group_path> <condition_path>, "
				+ "set-requirements <interaction_path> <group_path>, "
				+ "set-action <interaction_path> <action_path>, "
				+ "or resolve-interaction-source "
				+ "<interaction_path> <source_path>."
			),
		}

	print(RESULT_PREFIX, JSON.stringify(result))
	quit(0 if result["ok"] else 1)
