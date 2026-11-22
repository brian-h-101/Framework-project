extends SceneTree

const ConditionAssignment = preload(
	"res://Framework/Env/Authoring/Resources/Conditions/condition_assignment.gd"
)
const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Interactions/interaction_resource.gd"
)
const ConditionGroupResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_group_resource.gd"
)
const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Actions/action_resource.gd"
)

const ACTION_PATH := "res://Framework/Content/Behavior/Action/change_health.tres"
const GROUP_PATH := "res://Framework/Content/Behavior/Condition/can_strike.tres"

const SOURCE_PATHS := [
	ACTION_PATH,
	GROUP_PATH,
	"res://Framework/Content/Behavior/Condition/actor_strength.tres",
	"res://Framework/Content/Behavior/Interaction/strike.tres",
]

const TEST_ROOT := "res://.godot/diagnostics/action_assignment_"
const TEST_FILES := [
	"interaction.tres",
	"replacement_action.tres",
]

const EXPECTED_ARGUMENTS := {
	&"amount": -10,
	&"diagnostic": {
		"tags": ["preserved"],
		"enabled": true,
	},
}

var _test_directory: String = ""
var _owns_directory: bool = false
var _source_bytes: Dictionary = {}
var _completed: bool = false
var _passed: bool = true


func _initialize() -> void:
	_run_check()
	_expect("All behavior checks completed", _completed)
	_check_sources()
	_cleanup()

	print("[action-assignment] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _run_check() -> void:
	for source_path in SOURCE_PATHS:
		if not _expect(
			"Source exists: %s" % source_path,
			FileAccess.file_exists(source_path)
		):
			return

		_source_bytes[source_path] = FileAccess.get_file_as_bytes(
			source_path
		)

	var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(8)
	if not _expect("Unique folder name generated", random_bytes.size() == 8):
		return

	_test_directory = TEST_ROOT + random_bytes.hex_encode()

	var unused: bool = (
		not DirAccess.dir_exists_absolute(_test_directory)
		and not FileAccess.file_exists(_test_directory)
	)
	if not _expect("Diagnostic folder is unused", unused):
		return

	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		_test_directory
	)
	if not _expect("Diagnostic folder created", directory_error == OK):
		return

	_owns_directory = true

	var interaction_path: String = _test_directory.path_join(
		"interaction.tres"
	)
	var replacement_path: String = _test_directory.path_join(
		"replacement_action.tres"
	)

	var authored_action: ActionResource = ResourceLoader.load(
		ACTION_PATH
	) as ActionResource

	var group: ConditionGroupResource = ResourceLoader.load(
		GROUP_PATH
	) as ConditionGroupResource

	if not _expect(
		"Authored action and group load",
		authored_action != null and group != null
	):
		return

	var expected_requirements: Array[Dictionary] = group.to_requirements()

	var replacement: ActionResource = ActionResource.new()
	replacement.id = &"replacement_action"
	replacement.effects = authored_action.effects.duplicate(true)

	if not _expect(
		"Replacement action saved",
		ResourceSaver.save(replacement, replacement_path) == OK
	):
		return

	var replacement_bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		replacement_path
	)

	var interaction: InteractionResource = InteractionResource.new()
	interaction.id = &"action_assignment_check"
	interaction.requirements = group
	interaction.arguments = EXPECTED_ARGUMENTS.duplicate(true)

	if not _expect(
		"Temporary interaction saved",
		ResourceSaver.save(interaction, interaction_path) == OK
	):
		return

	var cached: InteractionResource = ResourceLoader.load(
		interaction_path
	) as InteractionResource

	if not _expect(
		"Interaction starts without an action",
		cached != null and cached.action == null
	):
		return

	var assigned: Dictionary = ConditionAssignment.set_action(
		interaction_path,
		ACTION_PATH
	)
	print("[action-assignment] Assignment result: ", assigned)

	if not _expect("Initial assignment succeeds", assigned["ok"]):
		return

	_expect("Assignment reports the selected paths", assigned["value"] == {
		"interaction_path": interaction_path,
		"action_path": ACTION_PATH,
	})

	var first_saved: InteractionResource = _load_interaction(
		interaction_path
	)
	if not _expect("Assigned interaction reloads", first_saved != null):
		return

	_expect("First action reference persists", (
		first_saved.action != null
		and first_saved.action.resource_path == ACTION_PATH
	))

	_check_other_fields(
		"Initial assignment",
		first_saved,
		expected_requirements
	)

	if not _expect("First action is available for conversion", (
		first_saved.action != null
	)):
		return

	_expect("Definition uses the assigned action ID", (
		first_saved.to_definition()["action"] == &"change_health"
	))

	_expect(
		"Previously cached interaction stays unchanged",
		cached.action == null
	)

	var replaced: Dictionary = ConditionAssignment.set_action(
		interaction_path,
		replacement_path
	)
	print("[action-assignment] Replacement result: ", replaced)

	if not _expect("Different action replaces the reference", replaced["ok"]):
		return

	_expect("Replacement reports the selected paths", replaced["value"] == {
		"interaction_path": interaction_path,
		"action_path": replacement_path,
	})

	var second_saved: InteractionResource = _load_interaction(
		interaction_path
	)
	if not _expect("Replaced interaction reloads", second_saved != null):
		return

	_expect("Replacement reference persists", (
		second_saved.action != null
		and second_saved.action.resource_path == replacement_path
	))

	_check_other_fields(
		"Replacement",
		second_saved,
		expected_requirements
	)

	if not _expect("Replacement action is available for conversion", (
		second_saved.action != null
	)):
		return

	_expect("Definition now uses the replacement action ID", (
		second_saved.to_definition()["action"] == &"replacement_action"
	))

	var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		interaction_path
	)

	var duplicate: Dictionary = ConditionAssignment.set_action(
		interaction_path,
		replacement_path
	)

	_expect("Repeated assignment is rejected", (
		not duplicate["ok"]
		and duplicate["value"] == null
		and duplicate["error"] == (
			"Action 'replacement_action' is already assigned "
			+ "to interaction 'action_assignment_check'."
		)
	))
	_expect("Duplicate rejection preserves the file", (
		FileAccess.get_file_as_bytes(interaction_path) == saved_bytes
	))

	var wrong_action: Dictionary = ConditionAssignment.set_action(
		interaction_path,
		GROUP_PATH
	)

	_expect("Group cannot be assigned as an action", (
		not wrong_action["ok"]
		and wrong_action["error"]
		== "Expected an action: %s" % GROUP_PATH
	))
	_expect("Type rejection preserves the interaction", (
		FileAccess.get_file_as_bytes(interaction_path) == saved_bytes
	))

	var wrong_interaction: Dictionary = ConditionAssignment.set_action(
		GROUP_PATH,
		ACTION_PATH
	)

	_expect("Group cannot be the destination interaction", (
		not wrong_interaction["ok"]
		and wrong_interaction["error"]
		== "Expected an interaction: %s" % GROUP_PATH
	))

	_expect("Replacement action itself remains unchanged", (
		FileAccess.get_file_as_bytes(replacement_path) == replacement_bytes
	))

	_completed = true


func _load_interaction(source_path: String) -> InteractionResource:
	return ResourceLoader.load(
		source_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as InteractionResource


func _check_other_fields(
	label: String,
	interaction: InteractionResource,
	expected_requirements: Array[Dictionary]
) -> void:
	_expect(label + " preserves the interaction ID", (
		interaction.id == &"action_assignment_check"
	))
	_expect(label + " preserves requirements", (
		interaction.requirements != null
		and interaction.requirements.resource_path == GROUP_PATH
		and interaction.requirements.to_requirements() == expected_requirements
	))
	_expect(
		label + " preserves nested arguments",
		interaction.arguments == EXPECTED_ARGUMENTS
	)


func _check_sources() -> void:
	for source_path in _source_bytes:
		_expect(
			"Source unchanged: %s" % source_path,
			FileAccess.get_file_as_bytes(String(source_path))
			== _source_bytes[source_path]
		)


func _cleanup() -> void:
	if not _owns_directory:
		return

	_owns_directory = false

	var directory: DirAccess = DirAccess.open(_test_directory)
	if not _expect("Cleanup directory is readable", directory != null):
		return

	var files: PackedStringArray = directory.get_files()

	for file_name in files:
		if file_name not in TEST_FILES:
			_expect("Unexpected file preserved: " + file_name, false)
			return

	if not directory.get_directories().is_empty():
		_expect("Unexpected subdirectory preserved", false)
		return

	for file_name in files:
		var remove_error: Error = directory.remove(file_name)
		if not _expect("Removed " + file_name, remove_error == OK):
			return

	directory = null

	var directory_error: Error = DirAccess.remove_absolute(
		_test_directory
	)
	_expect("Diagnostic folder removed", directory_error == OK)


func _expect(label: String, condition: bool) -> bool:
	print("[action-assignment] ", label, ": ", condition)
	_passed = _passed and condition
	return condition