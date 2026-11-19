extends SceneTree

const GameHost = preload(
	"res://Framework/Env/Host/game_host.gd"
)
const EntityStatusLayer2D = preload(
	"res://Framework/Env/Presentation/entity_status_layer_2d.gd"
)
const CityMap = preload(
	"res://Games/ExampleGame/World/city.tscn"
)
const SessionStore = preload(
	"res://Framework/Infrastructure/API/Persistence/session_store.gd"
)
const SpatialRoot2D = preload(
	"res://Framework/Env/Map/spatial_root_2d.gd"
)

const TEST_ROOT := "res://.godot/diagnostics/host_persistence_"
const TEST_FILE := "slot_01.fws"
const TEST_CORRUPT_FILE := "corrupt.fws"

const TEST_LEGACY_FILE := "legacy.fws"
const TEST_MAPLESS_FILE := "mapless.fws"
const TEST_MISSING_MAP_FILE := "missing_map.fws"
const TEST_POSITION_FAILURE_FILE := "invalid_positions.fws"

const TEST_OWNED_FILES := [
	TEST_FILE,
	TEST_CORRUPT_FILE,
	TEST_LEGACY_FILE,
	TEST_MAPLESS_FILE,
	TEST_MISSING_MAP_FILE,
	TEST_POSITION_FAILURE_FILE,
]

var _host := GameHost.new()
var _test_directory: String = ""
var _owns_directory: bool = false
var _passed: bool = true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_round_trip()
	_host.stop()

	await process_frame

	_cleanup()
	print("[host-persistence] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_round_trip() -> void:
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

	var started := _host.start(root)
	if not _require("Source host started", started):
		return

	var initial_map := _host.maps.get_active_map()
	var initial_map_path := initial_map.scene_file_path
	if not _expect("Fixture differs from configured initial map", (
		initial_map.scene_file_path != CityMap.resource_path
	)):
		return

	var switched := _host.maps.load_map(CityMap)
	if not _require("Alternate map loaded before saving", switched):
		return

	var source_runtime := _host.entry.runtime
	var player_id: int = _host.entry.entity_ids[&"player"]

	var changed := source_runtime.write_attribute(
		player_id, &"health", ["current"], 42
	)
	if not _require("Player health changed", changed):
		return

	var added := source_runtime.add_attribute(
		player_id, &"abilities", &"reflex", 12
	)
	if not _require("Runtime attribute acquired", added):
		return

	var time_advanced := source_runtime.advance_time(90.625)
	if not _require("Source clock advanced", time_advanced):
		return

	var captured := _host.entry.snapshot_session()
	if not _require("Expected state captured", captured):
		return

	var expected: Dictionary = captured["value"]

	var expected_player_position := Vector2(416, 392)
	var source_player_node := _host.entry.world_bridge.node_for(player_id)
	var source_map := _host.maps.get_active_map() as Node2D

	var positioned := SpatialRoot2D.restore_position(
		source_player_node,
		source_map,
		expected_player_position
	)
	if not _require("Player moved before saving", positioned):
		return

	var saved := _host.save_session(save_path)
	if not _require("Host saved the session", saved):
		return

	_check_rejected_restores(save_path, expected)

	_expect("Source host stopped", (
		_host.entry.runtime == null
		and _host.entry.entity_ids.is_empty()
		and _host.maps == null
		and _host.ui == null
	))

	_check_map_restore_cases(expected, initial_map_path)
	_check_position_restore_failures(save_path)

	var restored := _host.restore_session(root, save_path)
	if not _require(
		"Host restored the session after position rejections",
		restored
	):
		return

	_expect("Restored runtime is a new instance", (
		_host.entry.runtime != source_runtime
	))

	var restored_time := _host.entry.runtime.read_time()
	_expect("Saved day and time restored", (
		restored_time["ok"]
		and restored_time["value"]["day"] == 2
		and is_equal_approx(
			float(restored_time["value"]["hour"]), 2.125
		)
	))

	var restored_capture := _host.entry.snapshot_session()
	if not _require("Restored state captured", restored_capture):
		return

	_expect("Restored entities match the saved snapshot", (
		restored_capture["value"] == expected
	))

	if not _expect("Restored map coordinator exists", _host.maps != null):
		return

	var active_map := _host.maps.get_active_map()
	if not _expect("Restored map is attached", (
		is_instance_valid(active_map)
		and active_map.get_parent() == root
	)):
		return

	_expect("Saved map reopened", (
		active_map.scene_file_path == CityMap.resource_path
	))

	var restored_player_id: int = _host.entry.entity_ids[&"player"]
	var bridge := _host.entry.world_bridge
	var player_node := bridge.node_for(restored_player_id)

	if not _expect("Restored Player is bound within the map", (
		is_instance_valid(player_node)
		and active_map.is_ancestor_of(player_node)
	)):
		return

	var health := bridge.read_attribute(
		player_node, &"health", ["current"]
	)
	_expect("Bound Player reads saved health", (
		health["ok"] and health["value"] == 42
	))

	var restored_position := SpatialRoot2D.capture_position(
		player_node,
		active_map as Node2D
	)
	if not _expect("Restored Player position is available", (
		restored_position["ok"]
		and typeof(restored_position["value"]) == TYPE_VECTOR2
	)):
		return

	var actual_player_position: Vector2 = restored_position["value"]
	_expect(
		"Saved Player position restored",
		actual_player_position.is_equal_approx(expected_player_position)
	)

	if not _expect("Restored UI is attached", (
		is_instance_valid(_host.ui)
		and _host.ui.get_parent() == root
	)):
		return

	var statuses := _host.ui.get_node_or_null(
		"Root/EntityStatuses"
	) as EntityStatusLayer2D
	if not _expect("Restored status layer exists", statuses != null):
		return

	var widget := statuses.widget_for(restored_player_id)
	if not _expect("Restored Player widget exists", is_instance_valid(widget)):
		return

	var health_label := widget.get_node_or_null("Health") as Label
	if not _expect("Restored health label exists", health_label != null):
		return

	_expect("Restored UI shows saved health", health_label.text == "Health: 42")

	var later_change := _host.entry.runtime.write_attribute(
		restored_player_id, &"health", ["current"], 43
	)
	if not _require("Restored runtime remains writable", later_change):
		return

	_expect("Restored UI responds to new writes", (
		health_label.text == "Health: 43"
	))

func _check_rejected_restores(
	save_path: String,
	expected: Dictionary
) -> void:
	var previous_runtime := _host.entry.runtime
	var previous_bridge := _host.entry.world_bridge
	var previous_maps := _host.maps
	var previous_map := previous_maps.get_active_map()
	var previous_ui := _host.ui
	var previous_ids: Dictionary = _host.entry.entity_ids.duplicate()
	var player_id: int = previous_ids[&"player"]
	var previous_player := previous_bridge.node_for(player_id)
	var running_child_count := root.get_child_count()

	var running_restore := _host.restore_session(root, save_path)
	_expect("Running host rejects restoration", (
		not running_restore["ok"]
		and running_restore["value"] == null
		and running_restore["error"] == "Game session has already started."
	))

	_expect("Running environment remains unchanged", (
		_host.entry.runtime == previous_runtime
		and _host.entry.world_bridge == previous_bridge
		and _host.maps == previous_maps
		and _host.maps.get_active_map() == previous_map
		and _host.ui == previous_ui
		and previous_bridge.node_for(player_id) == previous_player
		and root.get_child_count() == running_child_count
	))

	var still_running := _host.entry.snapshot_session()
	_expect("Running entity state remains unchanged", (
		still_running["ok"]
		and still_running["value"] == expected
		and _host.entry.entity_ids == previous_ids
	))

	_host.stop()
	var stopped_child_count := root.get_child_count()

	var missing_path := _test_directory.path_join("missing.fws")
	var missing_restore := _host.restore_session(root, missing_path)
	_expect("Missing save restoration is rejected", (
		not missing_restore["ok"]
		and missing_restore["value"] == null
		and String(missing_restore["error"]).begins_with(
			"Save file does not exist:"
		)
	))
	_expect("Missing save leaves the host stopped", (
		_host_is_stopped()
		and root.get_child_count() == stopped_child_count
	))

	var corrupt_bytes := FileAccess.get_file_as_bytes(save_path)
	if not _expect("Corruption fixture bytes available", corrupt_bytes.size() > 1):
		return

	var last_index := corrupt_bytes.size() - 1
	corrupt_bytes[last_index] = corrupt_bytes[last_index] ^ 1

	var corrupt_path := _test_directory.path_join(TEST_CORRUPT_FILE)
	var file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	if not _expect("Corruption fixture opened", file != null):
		return

	var stored := file.store_buffer(corrupt_bytes)
	file.flush()
	var written: bool = (
		stored
		and file.get_error() == OK
		and file.get_length() == corrupt_bytes.size()
	)
	file.close()

	if not _expect("Corruption fixture written", written):
		return

	var corrupt_restore := _host.restore_session(root, corrupt_path)
	_expect("Corrupted save restoration is rejected", (
		not corrupt_restore["ok"]
		and corrupt_restore["value"] == null
		and corrupt_restore["error"] == (
			"Encoded session payload checksum does not match."
		)
	))
	_expect("Corrupted save leaves the host stopped", (
		_host_is_stopped()
		and root.get_child_count() == stopped_child_count
	))


func _host_is_stopped() -> bool:
	return (
		_host.entry.runtime == null
		and _host.entry.world_bridge == null
		and _host.entry.entity_ids.is_empty()
		and _host.maps == null
		and _host.ui == null
	)

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
		var owned: bool = file_name in TEST_OWNED_FILES
		for owned_file in TEST_OWNED_FILES:
			if file_name.begins_with(owned_file + ".pending-"):
				owned = true
		if not owned:
			_expect("Unexpected file preserved: " + file_name, false)
			return

		var remove_error := directory.remove(file_name)
		if not _expect("Diagnostic file removed", remove_error == OK):
			return

	if not directory.get_directories().is_empty():
		_expect("Unexpected subdirectory preserved", false)
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
	print("[host-persistence] ", label, ": ", condition)
	_passed = _passed and condition
	return condition

func _check_position_restore_failures(valid_save_path: String) -> void:
	if not _expect("Host is stopped before position failures", _host_is_stopped()):
		return

	var loaded := SessionStore.load_file(valid_save_path)
	if not _require("Position failure baseline loaded", loaded):
		return

	var baseline: Dictionary = loaded["value"]
	var failure_path := _test_directory.path_join(TEST_POSITION_FAILURE_FILE)

	var cases: Array[Dictionary] = [
		{
			"label": "Non-dictionary positions",
			"positions": [],
			"error": "Saved map positions_2d must be a dictionary.",
		},
		{
			"label": "Non-vector position",
			"positions": {&"player": "invalid"},
			"error": "Saved position for 'player' must be Vector2.",
		},
		{
			"label": "Non-finite position",
			"positions": {&"player": Vector2(INF, 0)},
			"error": "Saved position for 'player' must be finite.",
		},
		{
			"label": "Unplaced runtime entity",
			"positions": {&"second_player": Vector2.ZERO},
			"error": (
				"Saved position has no placement in this map: second_player"
			),
		},
		{
			"label": "Missing spatial marker",
			"scene_path": (
				"res://Diagnostics/Fixtures/PositionRestore/"
				+ "missing_spatial_root.tscn"
			),
			"positions": {&"player": Vector2(416, 392)},
			"error": "Entity 'player' has no enabled 2D spatial root.",
		},
	]

	for specification in cases:
		var label := String(specification["label"])
		var invalid_snapshot: Dictionary = baseline.duplicate(true)
		var map_record: Dictionary = invalid_snapshot["environment"]["map"]

		map_record["positions_2d"] = specification["positions"]
		if specification.has("scene_path"):
			map_record["scene_path"] = specification["scene_path"]

		var saved := SessionStore.save_file(failure_path, invalid_snapshot)
		if not _require(label + " fixture saved", saved):
			return

		var child_count := root.get_child_count()
		var rejected := _host.restore_session(root, failure_path)

		_expect(label + " rejected", (
			not rejected["ok"]
			and rejected["value"] == null
			and rejected["error"] == specification["error"]
		))
		_expect(label + " leaves host stopped", (
			_host_is_stopped()
			and root.get_child_count() == child_count
		))

		_host.stop()

func _check_map_restore_cases(
	expected: Dictionary,
	initial_map_path: String
) -> void:
	var legacy_snapshot: Dictionary = expected.duplicate(true)
	legacy_snapshot.erase("environment")

	var legacy_path := _test_directory.path_join(TEST_LEGACY_FILE)
	var legacy_saved := SessionStore.save_file(
		legacy_path, legacy_snapshot
	)
	if not _require("Legacy fixture saved", legacy_saved):
		return

	var legacy_restored := _host.restore_session(root, legacy_path)
	if not _require("Legacy save restored", legacy_restored):
		_host.stop()
		return

	var legacy_map := _host.maps.get_active_map()
	_expect("Legacy save uses configured initial map", (
		is_instance_valid(legacy_map)
		and legacy_map.scene_file_path == initial_map_path
	))
	_expect("Legacy save preserves entities and clock", (
		_runtime_state_matches(expected)
	))

	_host.maps.unload_map()

	var mapless_path := _test_directory.path_join(TEST_MAPLESS_FILE)
	var mapless_saved := _host.save_session(mapless_path)
	_host.stop()

	if not _require("Mapless fixture saved", mapless_saved):
		return

	var mapless_restored := _host.restore_session(root, mapless_path)
	if not _require("Mapless save restored", mapless_restored):
		_host.stop()
		return

	_expect("Explicit null map stays unloaded", (
		_host.maps != null
		and _host.maps.get_active_map() == null
		and _host.entry.world_bridge.bound_entity_ids().is_empty()
	))
	_expect("Mapless save preserves entities and clock", (
		_runtime_state_matches(expected)
	))

	_host.stop()
	var stopped_child_count := root.get_child_count()

	var missing_scene_path := _test_directory.path_join("absent_map.tscn")
	var missing_snapshot: Dictionary = expected.duplicate(true)
	missing_snapshot["environment"] = {
		"map": {
			"scene_path": missing_scene_path,
		},
	}

	var missing_path := _test_directory.path_join(TEST_MISSING_MAP_FILE)
	var missing_saved := SessionStore.save_file(
		missing_path, missing_snapshot
	)
	if not _require("Missing-map fixture saved", missing_saved):
		return

	var missing_restored := _host.restore_session(root, missing_path)
	_expect("Missing map scene is rejected", (
		not missing_restored["ok"]
		and missing_restored["value"] == null
		and missing_restored["error"] == (
			"Saved map scene does not exist: %s" % missing_scene_path
		)
	))
	_expect("Missing map leaves no partial environment", (
		_host_is_stopped()
		and root.get_child_count() == stopped_child_count
	))


func _runtime_state_matches(expected: Dictionary) -> bool:
	var captured := _host.entry.snapshot_session()
	return captured["ok"] and captured["value"] == expected