extends SceneTree

const ConditionAssignment = preload(
	"res://Framework/Env/Authoring/Resources/condition_assignment.gd"
)
const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/interaction_resource.gd"
)
const ConditionGroupResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/condition_group_resource.gd"
)
const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/action_resource.gd"
)

const ACTION_PATH := "res://Framework/Content/Behavior/Action/change_health.tres"
const FIRST_GROUP_PATH := "res://Framework/Content/Behavior/Condition/can_strike.tres"

const SOURCE_PATHS := [
	ACTION_PATH,
	FIRST_GROUP_PATH,
	"res://Framework/Content/Behavior/Condition/actor_strength.tres",
	"res://Framework/Content/Behavior/Interaction/strike.tres",
]

const TEST_ROOT := "res://.godot/diagnostics/requirements_assignment_"
const TEST_FILES := [
	"interaction.tres",
	"replacement_group.tres",
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

	print("[requirements-assignment] Checks passed: ", _passed)
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

	var random_bytes := Crypto.new().generate_random_bytes(8)
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
		"replacement_group.tres"
	)

	var action: ActionResource = ResourceLoader.load(
		ACTION_PATH
	) as ActionResource

	var first_group: ConditionGroupResource = ResourceLoader.load(
		FIRST_GROUP_PATH
	) as ConditionGroupResource

	if not _expect(
		"Authored action and group load",
		action != null and first_group != null
	):
		return

	var replacement := ConditionGroupResource.new()
	replacement.id = &"replacement_requirements"

	if not _expect(
		"Empty replacement group saved",
		ResourceSaver.save(replacement, replacement_path) == OK
	):
		return

	var replacement_bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		replacement_path
	)

	var interaction := InteractionResource.new()
	interaction.id = &"requirements_assignment_check"
	interaction.action = action
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
		"Interaction starts without requirements",
		cached != null and cached.requirements == null
	):
		return

	var assigned: Dictionary = ConditionAssignment.set_requirements(
		interaction_path,
		FIRST_GROUP_PATH
	)
	print("[requirements-assignment] Assignment result: ", assigned)

	if not _expect("Initial assignment succeeds", assigned["ok"]):
		return

	_expect("Assignment reports the selected paths", assigned["value"] == {
		"interaction_path": interaction_path,
		"group_path": FIRST_GROUP_PATH,
	})

	var first_saved: InteractionResource = _load_interaction(
		interaction_path
	)
	if not _expect("Assigned interaction reloads", first_saved != null):
		return

	_expect("First group reference persists", (
		first_saved.requirements != null
		and first_saved.requirements.resource_path == FIRST_GROUP_PATH
	))

	_check_other_fields("Initial assignment", first_saved)

	var first_definition: Dictionary = first_saved.to_definition()
	_expect("Definition uses the first group's conditions", (
		first_definition["requirements"] == first_group.to_requirements()
	))

	_expect(
		"Previously cached interaction stays unchanged",
		cached.requirements == null
	)

	var replaced: Dictionary = ConditionAssignment.set_requirements(
		interaction_path,
		replacement_path
	)
	print("[requirements-assignment] Replacement result: ", replaced)

	if not _expect("Different group replaces the reference", replaced["ok"]):
		return

	var second_saved: InteractionResource = _load_interaction(
		interaction_path
	)
	if not _expect("Replaced interaction reloads", second_saved != null):
		return

	_expect("Replacement reference persists", (
		second_saved.requirements != null
		and second_saved.requirements.resource_path == replacement_path
	))

	_check_other_fields("Replacement", second_saved)

	var second_definition: Dictionary = second_saved.to_definition()
	_expect(
		"Definition now uses the empty replacement group",
		second_definition["requirements"].is_empty()
	)

	var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		interaction_path
	)

	var duplicate: Dictionary = ConditionAssignment.set_requirements(
		interaction_path,
		replacement_path
	)

	_expect("Repeated assignment is rejected", (
		not duplicate["ok"]
		and duplicate["value"] == null
		and duplicate["error"] == (
			"Condition group 'replacement_requirements' is already "
			+ "assigned to interaction 'requirements_assignment_check'."
		)
	))
	_expect("Duplicate rejection preserves the file", (
		FileAccess.get_file_as_bytes(interaction_path) == saved_bytes
	))

	var wrong_group: Dictionary = ConditionAssignment.set_requirements(
		interaction_path,
		ACTION_PATH
	)

	_expect("Action cannot be assigned as a group", (
		not wrong_group["ok"]
		and wrong_group["error"]
		== "Expected a condition group: %s" % ACTION_PATH
	))
	_expect("Type rejection preserves the interaction", (
		FileAccess.get_file_as_bytes(interaction_path) == saved_bytes
	))

	var wrong_interaction: Dictionary = ConditionAssignment.set_requirements(
		FIRST_GROUP_PATH,
		replacement_path
	)

	_expect("Group cannot be used as the destination interaction", (
		not wrong_interaction["ok"]
		and wrong_interaction["error"]
		== "Expected an interaction: %s" % FIRST_GROUP_PATH
	))

	_expect("Replacement group itself remains unchanged", (
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
	interaction: InteractionResource
) -> void:
	_expect(label + " preserves the interaction ID", (
		interaction.id == &"requirements_assignment_check"
	))
	_expect(label + " preserves the action reference", (
		interaction.action != null
		and interaction.action.resource_path == ACTION_PATH
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

	var directory := DirAccess.open(_test_directory)
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
	print("[requirements-assignment] ", label, ": ", condition)
	_passed = _passed and condition
	return condition
