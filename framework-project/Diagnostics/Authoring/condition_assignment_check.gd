extends SceneTree

const ConditionAssignment = preload(
	"res://Framework/Env/Authoring/Resources/Conditions/condition_assignment.gd"
)
const ConditionGroupResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_group_resource.gd"
)

const CONDITION_PATH := (
	"res://Framework/Content/Behavior/Condition/actor_strength.tres"
)
const PRODUCTION_GROUP_PATH := (
	"res://Framework/Content/Behavior/Condition/can_strike.tres"
)
const TEST_ROOT := "res://.godot/diagnostics/condition_assignment_"
const TEST_FILE := "assignment_group.tres"

var _test_directory: String = ""
var _owns_directory: bool = false
var _source_bytes: Dictionary = {}
var _passed: bool = true


func _initialize() -> void:
	_run_check()
	_check_sources()
	_cleanup()

	print("[condition-assignment] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _run_check() -> void:
	for source_path in [CONDITION_PATH, PRODUCTION_GROUP_PATH]:
		if not _expect(
			"Production resource exists: " + source_path,
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

	var group_path: String = _test_directory.path_join(TEST_FILE)
	var group := ConditionGroupResource.new()
	group.id = &"assignment_check"

	var create_error: Error = ResourceSaver.save(group, group_path)
	if not _expect("Empty group saved", create_error == OK):
		return

	var cached_group: ConditionGroupResource = ResourceLoader.load(
		group_path
	) as ConditionGroupResource

	if not _expect(
		"Initial group is empty",
		cached_group != null and cached_group.conditions.is_empty()
	):
		return

	var assigned: Dictionary = ConditionAssignment.add_condition(
		group_path,
		CONDITION_PATH
	)
	print("[condition-assignment] Assignment result: ", assigned)

	if not _expect("Condition assigned", assigned["ok"]):
		return

	_expect(
		"Reports one assigned condition",
		assigned["value"]["condition_count"] == 1
	)

	var reloaded: ConditionGroupResource = ResourceLoader.load(
		group_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as ConditionGroupResource

	if not _expect("Saved group reloads", reloaded != null):
		return

	_expect("Group ID is preserved", reloaded.id == &"assignment_check")

	var reference_saved: bool = (
		reloaded.conditions.size() == 1
		and reloaded.conditions[0] != null
		and reloaded.conditions[0].resource_path == CONDITION_PATH
	)
	if not _expect("Condition reference persisted", reference_saved):
		return

	_expect(
		"Previously cached group stays unchanged",
		cached_group.conditions.is_empty()
	)

	var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		group_path
	)

	var duplicate: Dictionary = ConditionAssignment.add_condition(
		group_path,
		CONDITION_PATH
	)
	print("[condition-assignment] Duplicate result: ", duplicate)

	_expect("Duplicate assignment rejected", (
		not duplicate["ok"]
		and String(duplicate["error"]).contains("already assigned")
	))
	_expect("Duplicate rejection leaves file unchanged", (
		FileAccess.get_file_as_bytes(group_path) == saved_bytes
	))

	var wrong_condition: Dictionary = ConditionAssignment.add_condition(
		group_path,
		group_path
	)

	_expect("Group cannot be assigned as a condition", (
		not wrong_condition["ok"]
		and wrong_condition["error"]
		== "Expected a condition: %s" % group_path
	))
	_expect("Type rejection leaves file unchanged", (
		FileAccess.get_file_as_bytes(group_path) == saved_bytes
	))

	var wrong_group: Dictionary = ConditionAssignment.add_condition(
		CONDITION_PATH,
		CONDITION_PATH
	)

	_expect("Condition cannot be used as the destination group", (
		not wrong_group["ok"]
		and wrong_group["error"]
		== "Expected a condition group: %s" % CONDITION_PATH
	))


func _check_sources() -> void:
	for source_path in _source_bytes:
		_expect(
			"Production resource unchanged: %s" % source_path,
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

	for file_name in directory.get_files():
		if file_name != TEST_FILE:
			_expect("Unexpected file preserved: " + file_name, false)
			return

	if not directory.get_directories().is_empty():
		_expect("Unexpected subdirectory preserved", false)
		return

	if FileAccess.file_exists(_test_directory.path_join(TEST_FILE)):
		var file_error: Error = directory.remove(TEST_FILE)
		if not _expect("Temporary group removed", file_error == OK):
			return

	directory = null

	var directory_error: Error = DirAccess.remove_absolute(
		_test_directory
	)
	_expect("Diagnostic folder removed", directory_error == OK)


func _expect(label: String, condition: bool) -> bool:
	print("[condition-assignment] ", label, ": ", condition)
	_passed = _passed and condition
	return condition