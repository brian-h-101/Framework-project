extends SceneTree

const ConditionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_resource.gd"
)

const CLI_PATH := "res://Framework/Env/Authoring/Resources/Conditions/condition_editing_cli.gd"
const RESULT_PREFIX := "[condition-editing-result] "
const TEST_ROOT := "res://.godot/diagnostics/condition_editing_cli_"

const SOURCE_PATHS := [
	"res://Framework/Content/Behavior/Condition/actor_strength.tres",
	"res://Framework/Content/Behavior/Condition/can_strike.tres",
]

const ORIGINAL_REQUIREMENT := {
	"entity": &"actor",
	"container": &"strength",
	"path": ["current"],
	"operator": ">=",
	"value": 10,
	"message": "Strike requires at least 10 strength.",
	"metadata": {
		"tags": ["cli-preserved"],
		"enabled": true,
	},
}

var _test_directory: String = ""
var _owns_directory: bool = false
var _owned_files: PackedStringArray = PackedStringArray(["condition.tres"])
var _cli_index: int = 0
var _source_bytes: Dictionary = {}
var _completed: bool = false
var _passed: bool = true


func _initialize() -> void:
	_run_check()
	_expect("All behavior checks completed", _completed)
	_check_sources()
	_cleanup()

	print("[condition-cli] Checks passed: ", _passed)
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
	condition.id = &"condition_editing_cli_check"
	condition.requirement = ORIGINAL_REQUIREMENT.duplicate(true)

	if not _expect(
		"Temporary condition saved",
		ResourceSaver.save(condition, condition_path) == OK
	):
		return

	var cases: Array[Dictionary] = [
		{
			"label": "Integer",
			"operator": ">=",
			"kind": "int",
			"text": "20",
			"expected": 20,
		},
		{
			"label": "Fractional float",
			"operator": "<",
			"kind": "float",
			"text": "7.5",
			"expected": 7.5,
		},
		{
			"label": "Integral float",
			"operator": "==",
			"kind": "float",
			"text": "20",
			"expected": 20.0,
		},
		{
			"label": "Maximum integer",
			"operator": "<=",
			"kind": "int",
			"text": "9223372036854775807",
			"expected": 9223372036854775807,
		},
		{
			"label": "Minimum integer",
			"operator": ">=",
			"kind": "int",
			"text": "-9223372036854775808",
			"expected": -9223372036854775807 - 1,
		},
	]

	for test_case in cases:
		if not _check_edit(condition_path, test_case):
			return

	var before_rejection: PackedByteArray = FileAccess.get_file_as_bytes(
		condition_path
	)

	var rejected: Dictionary = _invoke_cli(
		"Rejected edit",
		condition_path,
		"approximately",
		"int",
		"0",
		"Rejected edit",
		1
	)

	if rejected.is_empty():
		return

	_expect("Helper rejection reaches the CLI", (
		not rejected["ok"]
		and rejected["value"] == null
		and rejected["error"]
		== "Unsupported comparison operator: approximately"
	))

	_expect("Rejected CLI edit preserves file bytes", (
		FileAccess.get_file_as_bytes(condition_path) == before_rejection
	))

	var recovery_case: Dictionary = {
		"label": "Zero after rejection",
		"operator": "!=",
		"kind": "int",
		"text": "0",
		"expected": 0,
	}

	if not _check_edit(condition_path, recovery_case):
		return

	_completed = true


func _check_edit(
	condition_path: String,
	test_case: Dictionary
) -> bool:
	var label: String = test_case["label"]
	var operator: String = test_case["operator"]
	var number_type: String = test_case["kind"]
	var number_text: String = test_case["text"]
	var expected_value: Variant = test_case["expected"]
	var message: String = "CLI check for " + label

	var packet: Dictionary = _invoke_cli(
		label,
		condition_path,
		operator,
		number_type,
		number_text,
		message,
		0
	)

	if packet.is_empty():
		return false

	if not _expect(
		label + " edit succeeds",
		packet["ok"] and packet["error"] == ""
	):
		return false

	var response_ok: bool = _expect(
		label + " reply preserves typed numeric text",
		packet["value"] == {
			"condition_path": condition_path,
			"operator": operator,
			"value_type": number_type,
			"value_text": number_text.strip_edges(),
			"message": message,
		}
	)

	var saved: ConditionResource = ResourceLoader.load(
		condition_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as ConditionResource

	if not _expect(
		label + " reloads with comparison fields",
		saved != null
		and saved.requirement.has_all(["operator", "value", "message"])
	):
		return false

	var saved_value: Variant = saved.requirement["value"]

	var id_ok: bool = _expect(
		label + " preserves the condition ID",
		saved.id == &"condition_editing_cli_check"
	)

	var fields_ok: bool = _expect(
		label + " persists comparison and message",
		saved.requirement["operator"] == operator
		and saved_value == expected_value
		and saved.requirement["message"] == message
	)

	var type_ok: bool = _expect(
		label + " persists the numeric type",
		typeof(saved_value) == typeof(expected_value)
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


func _invoke_cli(
	label: String,
	condition_path: String,
	operator: String,
	number_type: String,
	number_text: String,
	message: String,
	expected_exit: int
) -> Dictionary:
	var log_name: String = "cli_%d.log" % _cli_index
	_cli_index += 1
	_owned_files.append(log_name)

	var arguments := PackedStringArray([
		"--headless",
		"--path",
		ProjectSettings.globalize_path("res://"),
		"--log-file",
		ProjectSettings.globalize_path(_test_directory.path_join(log_name)),
		"--script",
		CLI_PATH,
		"--",
		"set-comparison",
		condition_path,
		operator,
		number_type,
		number_text,
		message,
	])

	var output: Array = []
	var exit_code: int = OS.execute(
		OS.get_executable_path(),
		arguments,
		output,
		true,
		false
	)

	var output_text: String = ""
	var result_lines := PackedStringArray()
	var engine_error: bool = false

	for block in output:
		var block_text: String = String(block)
		output_text += block_text + "\n"

		for raw_line in block_text.split("\n"):
			var line: String = raw_line.trim_suffix("\r")

			if line.begins_with(RESULT_PREFIX):
				result_lines.append(
					line.substr(RESULT_PREFIX.length())
				)

			if (
				line.begins_with("SCRIPT ERROR:")
				or line.begins_with("ERROR:")
			):
				engine_error = true

	if not _expect(
		label + " CLI completes cleanly",
		exit_code == expected_exit
		and not engine_error
		and result_lines.size() == 1
	):
		print(output_text)
		return {}

	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(result_lines[0])

	if not _expect(label + " reply is valid JSON", parse_error == OK):
		print(output_text)
		return {}

	var decoded: Variant = parser.data
	var envelope_ok: bool = (
		decoded is Dictionary
		and decoded.has_all(["ok", "value", "error"])
		and typeof(decoded["ok"]) == TYPE_BOOL
		and typeof(decoded["error"]) == TYPE_STRING
	)

	if not _expect(label + " reply has a valid envelope", envelope_ok):
		print(output_text)
		return {}

	var packet: Dictionary = decoded
	return packet


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
		if file_name not in _owned_files:
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
	print("[condition-cli] ", label, ": ", condition)
	_passed = _passed and condition
	return condition