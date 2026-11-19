extends SceneTree

const SessionStore = preload(
	"res://Framework/Infrastructure/API/Persistence/session_store.gd"
)

const TEST_ROOT := "res://.godot/diagnostics/session_store_failure_"
const TEST_FILES := ["valid.fws", "empty.fws", "truncated.fws", "corrupt.fws"]

var _test_directory: String = ""
var _owns_directory: bool = false
var _passed: bool = true


func _initialize() -> void:
	_run_check()
	_cleanup()

	print("[store-failure] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _run_check() -> void:
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

	_owns_directory = true

	var snapshot := {"entities": {}}
	var valid_path := _test_directory.path_join("valid.fws")
	var saved := SessionStore.save_file(valid_path, snapshot)
	if not _expect("Valid save created", saved["ok"]):
		push_error(String(saved["error"]))
		return

	var valid_bytes := FileAccess.get_file_as_bytes(valid_path)
	if not _expect("Valid save bytes available", valid_bytes.size() > 1):
		return

	_check_rejected_file(
		"Empty file",
		"empty.fws",
		PackedByteArray(),
		"Save file is empty or unreadable."
	)

	_check_rejected_file(
		"Truncated file",
		"truncated.fws",
		valid_bytes.slice(0, valid_bytes.size() - 1),
		"Encoded session frame length does not match its payload."
	)

	var changed_bytes := valid_bytes.duplicate()
	var last_index := changed_bytes.size() - 1
	changed_bytes[last_index] = changed_bytes[last_index] ^ 1

	_check_rejected_file(
		"Corrupted file",
		"corrupt.fws",
		changed_bytes,
		"Encoded session payload checksum does not match."
	)

	var loaded := SessionStore.load_file(valid_path)
	_expect("Valid save loads after rejected requests", (
		loaded["ok"]
		and loaded["value"] == snapshot
	))


func _check_rejected_file(
	label: String,
	file_name: String,
	bytes: PackedByteArray,
	expected_error: String
) -> void:
	var path := _test_directory.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_expect(label + " fixture opened", false)
		push_error(error_string(FileAccess.get_open_error()))
		return

	var stored := file.store_buffer(bytes)
	file.flush()
	var written_size := file.get_length()
	var write_error := file.get_error()
	file.close()

	var written: bool = (
		stored
		and write_error == OK
		and written_size == bytes.size()
	)
	if not _expect(label + " fixture written", written):
		return

	var result := SessionStore.load_file(path)
	var rejected: bool = (
		not result["ok"]
		and result["value"] == null
		and result["error"] == expected_error
	)
	if not _expect(label + " rejected", rejected):
		print("[store-failure] Unexpected result: ", result)

	_expect(label + " remains unchanged", (
		FileAccess.file_exists(path)
		and FileAccess.get_file_as_bytes(path) == bytes
	))


func _cleanup() -> void:
	if not _owns_directory:
		return

	_owns_directory = false
	if not DirAccess.dir_exists_absolute(_test_directory):
		return

	var directory := DirAccess.open(_test_directory)
	if not _expect("Cleanup directory is readable", directory != null):
		return

	for file_name in directory.get_files():
		var owned: bool = (
			file_name in TEST_FILES
			or file_name.begins_with("valid.fws.pending-")
		)
		if not owned:
			_expect("Unexpected file preserved: " + file_name, false)
			return

		var remove_error := directory.remove(file_name)
		if not _expect("Removed " + file_name, remove_error == OK):
			return

	if not directory.get_directories().is_empty():
		_expect("Unexpected subdirectory preserved", false)
		return

	directory = null
	var directory_error := DirAccess.remove_absolute(_test_directory)
	_expect("Diagnostic folder removed", directory_error == OK)


func _expect(label: String, condition: bool) -> bool:
	print("[store-failure] ", label, ": ", condition)
	_passed = _passed and condition
	return condition