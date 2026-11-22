extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/Bootstrap/game_setup.gd"
)
const MapCoordinator = preload(
	"res://Framework/Env/Map/map_coordinator.gd"
)

var _entry := GameEntry.new()
var _maps: MapCoordinator
var _passed: bool = true


func _initialize() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	var started := _entry.start(EnvironmentSetup.new())
	if not started["ok"]:
		push_error(String(started["error"]))
		quit(1)
		return

	var runtime := _entry.runtime
	var controls: Dictionary[StringName, Dictionary] = {}
	_maps = MapCoordinator.new(
		root, _entry.world_bridge, _entry.entity_ids, controls, runtime
	)

	var loaded := _maps.load_map(_make_map())
	if not loaded["ok"]:
		push_error(String(loaded["error"]))
		quit(1)
		return

	var player_id: int = _entry.entity_ids[&"player"]
	var guard_id: int = _entry.entity_ids[&"town_guard_01"]

	var player_changed := runtime.write_attribute(
		player_id, &"health", ["current"], 42
	)
	var guard_changed := runtime.write_attribute(
		guard_id, &"health", ["current"], 35
	)
	var inventory_added := runtime.add_container(
		guard_id, &"inventory",
		{"capacity": 6, "items": {"ration": 2}}
	)
	var prepared: bool = (
		player_changed["ok"]
		and guard_changed["ok"]
		and inventory_added["ok"]
	)
	_expect("Gameplay changes prepared", prepared)
	if not prepared:
		quit(1)
		return

	_maps.unload_map()
	await process_frame
	_expect("Guard survives map unloading without a binding", (
		_maps.get_active_map() == null
		and runtime.has_entity(guard_id)
		and _entry.world_bridge.node_for(guard_id) == null
	))

	var lookup_before: Dictionary = _entry.entity_ids.duplicate()
	var expected_keys: Array = lookup_before.keys()
	expected_keys.sort()

	var notified: Array[int] = []
	runtime.attribute_written.connect(
		func(entity_id: int, _container_id: StringName, _attribute_name: StringName):
			notified.append(entity_id)
	)

	var captured := _entry.snapshot_session()
	if not captured["ok"]:
		push_error(String(captured["error"]))
		quit(1)
		return

	var records: Dictionary = captured["value"]["entities"]
	var keys_match: bool = records.keys() == expected_keys
	_expect("Stable keys are captured in sorted order", keys_match)
	if not keys_match:
		quit(1)
		return

	_expect("Player state is captured under its key", (
		records[&"player"]["definition"] == &"player"
		and records[&"player"]["containers"][&"health"]["current"] == 42
	))
	_expect("Unloaded guard state and acquired inventory are captured", (
		records[&"town_guard_01"]["definition"] == &"town_guard"
		and records[&"town_guard_01"]["containers"][&"health"]["current"] == 35
		and records[&"town_guard_01"]["containers"][&"inventory"]["items"]
			== {"ration": 2}
	))

	records[&"town_guard_01"]["containers"][&"inventory"]["items"]["ration"] = 99
	records.erase(&"player")

	var live_items := runtime.read_attribute(
		guard_id, &"inventory", ["items"]
	)
	_expect("Snapshot edits leave live containers unchanged", (
		live_items["ok"] and live_items["value"] == {"ration": 2}
	))
	_expect("Snapshot edits leave the session lookup unchanged", (
		_entry.entity_ids == lookup_before
	))

	var invalid_lookups: Dictionary[StringName, int] = {
		&"player_alias": player_id,
		&"missing_entity": 0,
		&"": player_id,
	}
	for entity_key in invalid_lookups:
		_entry.entity_ids[entity_key] = invalid_lookups[entity_key]
		var rejected := _entry.snapshot_session()
		_expect("Invalid lookup [%s] is rejected" % entity_key, (
			not rejected["ok"] and rejected["value"] == null
		))
		_entry.entity_ids.erase(entity_key)

	var retry := _entry.snapshot_session()
	_expect("Capture succeeds after rejected requests", retry["ok"])
	if retry["ok"]:
		var fresh_records: Dictionary = retry["value"]["entities"]
		_expect("Fresh captures remain independent", (
			fresh_records.keys() == expected_keys
			and fresh_records[&"town_guard_01"]["containers"][&"inventory"]["items"]
				== {"ration": 2}
		))

	_expect("Capture emits no write notifications", notified.is_empty())

	_entry.stop()
	var stopped := _entry.snapshot_session()
	_expect("Stopped session is rejected", not stopped["ok"])

	print("[session-snapshot] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _make_map() -> PackedScene:
	var map_root := Node.new()
	map_root.name = &"SnapshotGuard"
	map_root.set_meta(&"entity_key", &"town_guard_01")
	map_root.set_meta(&"entity_definition", &"town_guard")

	var packed := PackedScene.new()
	var error := packed.pack(map_root)
	map_root.free()

	if error != OK:
		push_error("Could not build diagnostic map: %s" % error_string(error))
		return null

	return packed


func _expect(label: String, condition: bool) -> void:
	print("[session-snapshot] ", label, ": ", condition)
	_passed = _passed and condition


func _finalize() -> void:
	if _maps != null:
		_maps.unload_map()
	_entry.stop()