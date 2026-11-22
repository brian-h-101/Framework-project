extends SceneTree

const ConditionEditing = preload(
	"res://Framework/Env/Authoring/Resources/Conditions/condition_editing.gd"
)
const ConditionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_resource.gd"
)

const GROUP_PATH := "res://Framework/Content/Behavior/Condition/can_strike.tres"

const SOURCE_PATHS := [
	"res://Framework/Content/Behavior/Condition/actor_strength.tres",
	GROUP_PATH,
]

const TEST_ROOT := "res://.godot/diagnostics/condition_editing_"
const TEST_FILES := ["condition.tres"]

const ORIGINAL_REQUIREMENT := {
	"entity": &"actor",
	"container": &"strength",
	"path": ["current"],
	"operator": ">=",
	"value": 10,
	"message": "Strike requires at least 10 strength.",
	"metadata": {
		"tags": ["preserved"],
		"flags": {"enabled": true},
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

	print("[condition-edit] Checks passed: ", _passed)
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

	var condition_path: String = _test_directory.path_join(
		"condition.tres"
	)

	var condition: ConditionResource = ConditionResource.new()
	condition.id = &"condition_editing_check"
	condition.requirement = ORIGINAL_REQUIREMENT.duplicate(true)

	if not _expect(
		"Temporary condition saved",
		ResourceSaver.save(condition, condition_path) == OK
	):
		return

	var cached: ConditionResource = ResourceLoader.load(
		condition_path
	) as ConditionResource

	if not _expect("Original condition cached", cached != null):
		return

	var edits: Array[Dictionary] = [
		{
			"label": "Integer edit",
			"operator": ">=",
			"value": 20,
			"message": "Strike requires at least 20 strength.",
		},
		{
			"label": "Fractional edit",
			"operator": "<",
			"value": 7.5,
			"message": "Strike requires less than 7.5 strength.",
		},
		{
			"label": "Integral float edit",
			"operator": "==",
			"value": 20.0,
			"message": "Strike requires exactly 20 strength.",
		},
	]

	for edit in edits:
		if not _apply_edit(
			edit["label"],
			condition_path,
			edit["operator"],
			edit["value"],
			edit["message"]
		):
			return

	if not _expect_rejected(
		"Unsupported operator",
		condition_path,
		"approximately",
		20,
		"Unsupported comparison operator: approximately"
	):
		return

	if not _apply_edit("Boolean equality", condition_path, "==", true, "Boolean condition."):
		return
	var boolean_read := ConditionEditing.get_comparison(condition_path)
	if not _expect("Boolean type is available for editing", boolean_read["ok"] and boolean_read["value"]["value_type"] == "bool"):
		return
	if not _expect_rejected("Boolean ordering", condition_path, ">=", true, "Boolean comparisons support only == and !=."):
		return
	var non_numbers: Array[Dictionary] = [
		{"label": "Text value", "value": "20"},
		{"label": "Null value", "value": null},
	]

	for invalid in non_numbers:
		if not _expect_rejected(
			invalid["label"],
			condition_path,
			">=",
			invalid["value"],
			"Condition comparison value must be a number."
		):
			return

	var non_finite_values: Array[Dictionary] = [
		{"label": "Infinite value", "value": INF},
		{"label": "NaN value", "value": NAN},
	]

	for invalid in non_finite_values:
		if not _expect_rejected(
			invalid["label"],
			condition_path,
			">=",
			invalid["value"],
			"Condition comparison value must be finite."
		):
			return

	if not _expect_rejected(
		"Condition group destination",
		GROUP_PATH,
		">=",
		20,
		"Expected a condition: %s" % GROUP_PATH
	):
		return

	if not _apply_edit(
		"Valid edit after rejections",
		condition_path,
		"!=",
		0,
		"Strike requires nonzero strength."
	):
		return

	_expect(
		"Previously cached condition stays unchanged",
		cached.requirement == ORIGINAL_REQUIREMENT
	)

	_completed = true


func _apply_edit(
	label: String,
	condition_path: String,
	operator: String,
	value: Variant,
	message: String
) -> bool:
	var result: Dictionary = ConditionEditing.set_comparison(
		condition_path,
		operator,
		value,
		message
	)

	if not _expect(label + " succeeds", result["ok"]):
		return false

	var response_ok: bool = _expect(
		label + " reports requested fields",
		result["value"] == {
			"condition_path": condition_path,
			"operator": operator,
			"value": value,
			"message": message,
		}
	)

	var saved: ConditionResource = ResourceLoader.load(
		condition_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as ConditionResource

	if not _expect(label + " reloads", saved != null):
		return false

	if not _expect(
		label + " contains comparison fields",
		saved.requirement.has_all(["operator", "value", "message"])
	):
		return false

	var id_ok: bool = _expect(
		label + " preserves the condition ID",
		saved.id == &"condition_editing_check"
	)

	var fields_ok: bool = _expect(
		label + " persists comparison and message",
		saved.requirement["operator"] == operator
		and saved.requirement["value"] == value
		and saved.requirement["message"] == message
	)

	var type_ok: bool = _expect(
		label + " preserves native value type",
		typeof(saved.requirement["value"]) == typeof(value)
	)

	var remaining: Dictionary = saved.requirement.duplicate(true)
	var original: Dictionary = ORIGINAL_REQUIREMENT.duplicate(true)

	for field_name in ["operator", "value", "message"]:
		remaining.erase(field_name)
		original.erase(field_name)

	var preserved_ok: bool = _expect(
		label + " preserves remaining fields",
		remaining == original
	)

	return response_ok and id_ok and fields_ok and type_ok and preserved_ok


func _expect_rejected(
	label: String,
	condition_path: String,
	operator: String,
	value: Variant,
	expected_error: String
) -> bool:
	var before: PackedByteArray = FileAccess.get_file_as_bytes(
		condition_path
	)

	var result: Dictionary = ConditionEditing.set_comparison(
		condition_path,
		operator,
		value,
		"Rejected edit"
	)

	var rejected: bool = _expect(
		label + " rejected",
		not result["ok"]
		and result["value"] == null
		and result["error"] == expected_error
	)

	var unchanged: bool = _expect(
		label + " preserves file bytes",
		FileAccess.get_file_as_bytes(condition_path) == before
	)

	return rejected and unchanged


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
	print("[condition-edit] ", label, ": ", condition)
	_passed = _passed and condition
	return condition