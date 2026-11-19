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

	var source_runtime := _entry.runtime
	var source_id := source_runtime.spawn(&"town_guard")

	var health_changed := source_runtime.write_attribute(
		source_id, &"health", ["current"], 42
	)
	var title_added := source_runtime.add_attribute(
		source_id, &"identity", &"title", "Scout"
	)
	var inventory_added := source_runtime.add_container(
		source_id, &"inventory",
		{"capacity": 6, "items": {"ration": 2}}
	)
	var empty_added := source_runtime.add_container(source_id, &"empty_pack")

	var prepared: bool = (
		source_id > 0
		and health_changed["ok"]
		and title_added["ok"]
		and inventory_added["ok"]
		and empty_added["ok"]
	)
	_expect("Source entity prepared", prepared)
	if not prepared:
		quit(1)
		return

	var captured := source_runtime.snapshot_entity(source_id)
	if not captured["ok"]:
		push_error(String(captured["error"]))
		quit(1)
		return

	var record: Dictionary = captured["value"]
	record["containers"].erase(&"speed")
	var expected: Dictionary = record.duplicate(true)

	_entry.stop()
	_expect("Source runtime is closed", (
		not source_runtime.has_entity(source_id)
	))

	var restarted := _entry.start(EnvironmentSetup.new())
	if not restarted["ok"]:
		push_error(String(restarted["error"]))
		quit(1)
		return

	var runtime := _entry.runtime
	_expect("Receiving runtime is a new instance", runtime != source_runtime)

	var notified: Array[int] = []
	runtime.attribute_written.connect(
		func(entity_id: int, _container_id: StringName, _attribute_name: StringName):
			notified.append(entity_id)
	)

	var restored := runtime.restore_entity(record)
	_expect("Snapshot restored", restored["ok"])
	if not restored["ok"]:
		push_error(String(restored["error"]))
		quit(1)
		return

	var restored_id: int = restored["value"]
	_expect("Restored entity has its definition association", (
		runtime.has_entity(restored_id)
		and runtime.definition_id_for(restored_id) == &"town_guard"
	))

	var round_trip := runtime.snapshot_entity(restored_id)
	_expect("Restored state matches the complete record", (
		round_trip["ok"] and round_trip["value"] == expected
	))
	_expect("Creation emits no attribute write notifications", notified.is_empty())

	record["containers"][&"health"]["current"] = 999
	record["containers"][&"inventory"]["items"]["ration"] = 99
	record["containers"][&"interactions"]["available"].append(&"strike")

	var after_input_changes := runtime.snapshot_entity(restored_id)
	_expect("Input changes leave restored data unchanged", (
		after_input_changes["ok"]
		and after_input_changes["value"] == expected
	))

	var updated := runtime.write_attribute(
		restored_id, &"health", ["current"], 43
	)
	var health_after := runtime.read_attribute(
		restored_id, &"health", ["current"]
	)
	_expect("Restored entity remains writable", (
		updated["ok"] and health_after["ok"]
		and health_after["value"] == 43
	))
	_expect("Runtime writes leave the supplied record unchanged", (
		record["containers"][&"health"]["current"] == 999
	))

	var fresh_id := runtime.spawn(&"town_guard")
	var fresh_speed := runtime.read_attribute(
		fresh_id, &"speed", ["current"]
	)
	var fresh_inventory := runtime.read_attribute(
		fresh_id, &"inventory", ["capacity"]
	)
	_expect("Fresh spawns retain their original defaults", (
		fresh_id > 0
		and fresh_speed["ok"] and fresh_speed["value"] == 20
		and not fresh_inventory["ok"]
	))

	var unknown := runtime.restore_entity({
		"definition": &"missing_restore_definition",
		"containers": {},
	})
	_expect("Unknown definition is rejected", not unknown["ok"])

	var malformed := runtime.restore_entity({
		"definition": &"town_guard",
		"containers": {&"inventory": 17},
	})
	_expect("Malformed container is rejected", not malformed["ok"])

	_entry.stop()
	var closed := runtime.restore_entity(expected)
	_expect("Closed runtime is rejected", not closed["ok"])

	print("[restore] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _expect(label: String, condition: bool) -> void:
	print("[restore] ", label, ": ", condition)
	_passed = _passed and condition


func _finalize() -> void:
	_entry.stop()