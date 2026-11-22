extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/Bootstrap/game_setup.gd"
)
const SessionStore = preload(
	"res://Framework/Infrastructure/API/Persistence/session_store.gd"
)

const TEST_ROOT := "res://.godot/diagnostics/session_store_"
const TEST_FILE := "slot_01.fws"

var _entry := GameEntry.new()
var _test_directory: String = ""
var _owns_directory: bool = false
var _passed: bool = true


func _initialize() -> void:
	_run_check()
	_entry.stop()
	_cleanup()

	print("[store] Checks passed: ", _passed)
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
	var save_path := _test_directory.path_join(TEST_FILE)

	var started := _entry.start(EnvironmentSetup.new())
	if not _require("Source session started", started):
		return

	var player_id: int = _entry.entity_ids[&"player"]
	var health_changed := _entry.runtime.write_attribute(
		player_id, &"health", ["current"], 42
	)
	if not _require("Player health changed", health_changed):
		return

	var reflex_added := _entry.runtime.add_attribute(
		player_id, &"abilities", &"reflex", 12
	)
	if not _require("Runtime attribute added", reflex_added):
		return

	var captured := _entry.snapshot_session()
	if not _require("Session captured", captured):
		return

	var snapshot: Dictionary = captured["value"]
	var expected: Dictionary = snapshot.duplicate(true)

	var saved := SessionStore.save_file(save_path, snapshot)
	if not _require("Session saved", saved):
		return

	_expect("Save reports the requested path", saved["value"] == save_path)
	_expect("Save file exists", FileAccess.file_exists(save_path))

	snapshot.clear()
	_entry.stop()

	_expect("Source runtime is closed", _entry.runtime == null)

	var loaded := SessionStore.load_file(save_path)
	if not _require("File loaded after source session closes", loaded):
		return

	var loaded_snapshot: Dictionary = loaded["value"]
	_expect("Loaded state matches the captured state", loaded_snapshot == expected)
	_expect("Loading data does not start a session", (
		_entry.runtime == null
		and _entry.world_bridge == null
		and _entry.entity_ids.is_empty()
	))

	var restored := _entry.restore_session(
		EnvironmentSetup.new(), loaded_snapshot
	)
	if not _require("Loaded snapshot restored", restored):
		return

	var restored_snapshot := _entry.snapshot_session()
	if not _require("Restored session captured", restored_snapshot):
		return

	_expect("Restored entities match the saved state", (
		restored_snapshot["value"] == expected
	))

	var restored_player_id: int = _entry.entity_ids[&"player"]
	var later_change := _entry.runtime.write_attribute(
		restored_player_id, &"health", ["current"], 43
	)
	if not _require("Restored player health updated", later_change):
		return

	var updated_snapshot := _entry.snapshot_session()
	if not _require("Updated session captured", updated_snapshot):
		return

	var replacement_saved := SessionStore.save_file(
		save_path, updated_snapshot["value"]
	)
	if not _require("Existing save replaced", replacement_saved):
		return

	var replacement_loaded := SessionStore.load_file(save_path)
	if not _require("Replacement file loaded", replacement_loaded):
		return

	var replacement_snapshot: Dictionary = replacement_loaded["value"]
	_expect("Replacement contains latest session", (
		replacement_snapshot == updated_snapshot["value"]
	))

	var player_record: Dictionary = replacement_snapshot["entities"][&"player"]
	_expect("Saved player health is 43", (
		player_record["containers"][&"health"]["current"] == 43
	))

	var missing_path := _test_directory.path_join("missing.fws")
	var missing_load := SessionStore.load_file(missing_path)
	_expect("Missing save returns a failure", (
		not missing_load["ok"]
		and missing_load["value"] == null
		and not String(missing_load["error"]).is_empty()
	))
	_expect("Missing load creates no file", (
		not FileAccess.file_exists(missing_path)
	))

	var bytes_before := FileAccess.get_file_as_bytes(save_path)
	if not _expect("Valid save bytes are available", not bytes_before.is_empty()):
		return

	var rejected_save := SessionStore.save_file(save_path, {})
	_expect("Invalid snapshot save returns a failure", (
		not rejected_save["ok"]
		and rejected_save["value"] == null
		and not String(rejected_save["error"]).is_empty()
	))

	var bytes_after := FileAccess.get_file_as_bytes(save_path)
	_expect("Rejected save preserves the exact file bytes", (
		bytes_after == bytes_before
	))

	var preserved_load := SessionStore.load_file(save_path)
	if not _require("Previous save remains loadable", preserved_load):
		return

	_expect("Previous save retains the latest valid state", (
		preserved_load["value"] == updated_snapshot["value"]
	))

	var directory := DirAccess.open(_test_directory)
	if not _expect("Diagnostic directory is readable", directory != null):
		return

	_expect("Successful save leaves no pending files", (
		directory.get_files() == PackedStringArray([TEST_FILE])
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
			file_name == TEST_FILE
			or file_name.begins_with(TEST_FILE + ".pending-")
		)
		if not owned:
			_expect("Cleanup found an unexpected file; preserved it", false)
			return

		var remove_error := directory.remove(file_name)
		if not _expect("Diagnostic file removed", remove_error == OK):
			return

	if not directory.get_directories().is_empty():
		_expect("Cleanup found an unexpected subdirectory; preserved it", false)
		return

	directory = null
	var directory_error := DirAccess.remove_absolute(_test_directory)
	_expect("Diagnostic folder removed", directory_error == OK)


func _require(label: String, result: Dictionary) -> bool:
	var succeeded: bool = result["ok"]
	_expect(label, succeeded)
	if not succeeded:
		push_error(String(result["error"]))
	return succeeded


func _expect(label: String, condition: bool) -> bool:
	print("[store] ", label, ": ", condition)
	_passed = _passed and condition
	return condition