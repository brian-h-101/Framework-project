extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/game_setup.gd"
)

var _entry := GameEntry.new()
var _passed: bool = true


func _initialize() -> void:
	var started := _entry.start(EnvironmentSetup.new())
	if not started["ok"]:
		push_error(String(started["error"]))
		quit(1)
		return

	var runtime := _entry.runtime
	var guard_id := runtime.spawn(&"town_guard")

	var health_update := runtime.write_attribute(
		guard_id, &"health", ["current"], 42
	)
	var title_added := runtime.add_attribute(
		guard_id, &"identity", &"title", "Scout"
	)
	var inventory_added := runtime.add_container(
		guard_id, &"inventory",
		{"capacity": 6, "items": {"ration": 2}}
	)
	var empty_added := runtime.add_container(guard_id, &"empty_pack")

	var prepared: bool = (
		guard_id > 0
		and health_update["ok"]
		and title_added["ok"]
		and inventory_added["ok"]
		and empty_added["ok"]
	)
	_expect("Runtime changes prepared", prepared)
	if not prepared:
		quit(1)
		return

	var notified: Array[StringName] = []
	runtime.attribute_written.connect(
		func(entity_id: int, _container_id: StringName, attribute_name: StringName):
			if entity_id == guard_id:
				notified.append(attribute_name)
	)

	var captured := runtime.snapshot_entity(guard_id)
	if not captured["ok"]:
		push_error(String(captured["error"]))
		quit(1)
		return

	var snapshot: Dictionary = captured["value"]
	var expected := {
		"definition": &"town_guard",
		"containers": {
			&"identity": {"name": "TownGuard", "title": "Scout"},
			&"health": {"current": 42, "maximum": 100},
			&"speed": {"current": 20, "maximum": 50},
			&"interactions": {"available": []},
			&"inventory": {"capacity": 6, "items": {"ration": 2}},
			&"empty_pack": {},
		},
	}
	_expect("Complete current state captured", snapshot == expected)
	_expect("Snapshot emits no write notifications", notified.is_empty())

	var health_changed := runtime.write_attribute(
		guard_id, &"health", ["current"], 43
	)
	var items_changed := runtime.write_attribute(
		guard_id, &"inventory", ["items", "ration"], 3
	)
	_expect("Later runtime updates succeed", (
		health_changed["ok"] and items_changed["ok"]
	))
	_expect("Captured snapshot stays unchanged", snapshot == expected)

	var expected_after: Dictionary = expected.duplicate(true)
	expected_after["containers"][&"health"]["current"] = 43
	expected_after["containers"][&"inventory"]["items"]["ration"] = 3

	var notification_count := notified.size()
	var latest := runtime.snapshot_entity(guard_id)
	_expect("New snapshot includes later values", (
		latest["ok"] and latest["value"] == expected_after
	))

	snapshot["containers"][&"health"]["current"] = 999
	snapshot["containers"][&"inventory"]["items"]["ration"] = 99
	snapshot["containers"][&"interactions"]["available"].append(&"strike")

	var live_health := runtime.read_attribute(
		guard_id, &"health", ["current"]
	)
	var live_items := runtime.read_attribute(
		guard_id, &"inventory", ["items"]
	)
	var live_interactions := runtime.read_attribute(
		guard_id, &"interactions", ["available"]
	)
	_expect("Snapshot changes leave live data unchanged", (
		live_health["ok"] and live_health["value"] == 43
		and live_items["ok"] and live_items["value"] == {"ration": 3}
		and live_interactions["ok"] and live_interactions["value"] == []
	))
	_expect("Separate snapshots remain independent", (
		latest["ok"] and latest["value"] == expected_after
	))

	var unknown := runtime.snapshot_entity(0)
	_expect("Unknown entity is rejected", not unknown["ok"])
	_expect("Further snapshot reads emit no notifications", (
		notified.size() == notification_count
	))

	_entry.stop()
	var closed := runtime.snapshot_entity(guard_id)
	_expect("Closed runtime is rejected", not closed["ok"])

	print("[snapshot] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _expect(label: String, condition: bool) -> void:
	print("[snapshot] ", label, ": ", condition)
	_passed = _passed and condition


func _finalize() -> void:
	_entry.stop()