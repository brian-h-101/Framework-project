extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const RuntimeCore = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd"
)
const TrackingSetup = preload(
	"res://Diagnostics/Fixtures/Setup/restore_tracking_setup.gd"
)
const ContentFailureSetup = preload(
	"res://Diagnostics/Fixtures/Setup/content_failure_setup.gd"
)

var _entry := GameEntry.new()
var _passed: bool = true


func _initialize() -> void:
	var valid_snapshot := {
		"entities": {
			&"town_guard_01": {
				"definition": &"town_guard",
				"containers": {
					&"health": {"current": 42, "maximum": 100},
					&"empty_pack": {},
				},
			},
		},
	}
	var expected_after_legacy: Dictionary = valid_snapshot.duplicate(true)
	var clock_definition := TrackingSetup.new().get_clock_definition()
	expected_after_legacy["clock"] = {
		"total_hours": float(clock_definition["starting_hour"]),
	}

	var expected_empty: Dictionary = {
		"entities": {},
		"clock": expected_after_legacy["clock"],
	}

	var invalid_snapshot: Dictionary = valid_snapshot.duplicate(true)
	invalid_snapshot["entities"][&"zz_invalid_guard"] = {
		"definition": &"missing_restore_definition",
		"containers": {},
	}

	_check_batch_preparation(valid_snapshot, invalid_snapshot)

	var malformed_setup := TrackingSetup.new()
	var malformed := _entry.restore_session(
		malformed_setup, {"entities": []}
	)
	_expect("Malformed collection is rejected before registration", (
		not malformed["ok"]
		and malformed_setup.captured_runtime == null
		and _entry_is_stopped()
	))

	var failed_setup := TrackingSetup.new()
	var failed := _entry.restore_session(failed_setup, invalid_snapshot)
	_expect("Invalid entity error identifies its stable key", (
		not failed["ok"]
		and String(failed["error"]).contains("zz_invalid_guard")
	))
	_expect("Failed restore clears session state", _entry_is_stopped())
	_expect("Failed restore closes its runtime", (
		_runtime_is_closed(failed_setup.captured_runtime)
	))
	_expect("Failed restore skips startup spawning", (
		not failed_setup.create_entities_called
	))

	var retry_setup := TrackingSetup.new()
	var retry := _entry.restore_session(retry_setup, valid_snapshot)
	_expect("Retry succeeds on the same GameEntry", retry["ok"])
	if not retry["ok"]:
		push_error(String(retry["error"]))
		quit(1)
		return

	_expect("Retry creates a new runtime without startup spawning", (
		_entry.runtime != failed_setup.captured_runtime
		and not retry_setup.create_entities_called
	))
	var captured := _entry.snapshot_session()
	_expect("Retry restores the complete supplied state", (
		captured["ok"] and captured["value"] == expected_after_legacy
	))

	var previous_runtime := _entry.runtime
	var previous_bridge := _entry.world_bridge
	var active_setup := TrackingSetup.new()
	var active_rejected := _entry.restore_session(active_setup, valid_snapshot)
	var after_rejection := _entry.snapshot_session()
	_expect("Running session is protected", (
		not active_rejected["ok"]
		and active_setup.captured_runtime == null
		and _entry.runtime == previous_runtime
		and _entry.world_bridge == previous_bridge
		and after_rejection["ok"]
		and after_rejection["value"] == expected_after_legacy
	))
	_entry.stop()

	var registration_setup := ContentFailureSetup.new()
	var registration_failure := _entry.restore_session(
		registration_setup, valid_snapshot
	)
	_expect("Content registration errors propagate", (
		not registration_failure["ok"]
		and String(registration_failure["error"]).contains("Duplicate ID")
	))
	_expect("Registration failure clears and closes the session", (
		_entry_is_stopped()
		and _runtime_is_closed(registration_setup.captured_runtime)
		and not registration_setup.create_entities_called
	))

	var empty_setup := TrackingSetup.new()
	var empty_restored := _entry.restore_session(
		empty_setup, {"entities": {}}
	)
	var empty_snapshot := _entry.snapshot_session()
	_expect("Empty collection restores without startup entities", (
		empty_restored["ok"]
		and not empty_setup.create_entities_called
		and _entry.entity_ids.is_empty()
		and empty_snapshot["ok"]
		and empty_snapshot["value"] == expected_empty
	))
	_entry.stop()

	print("[session-restore-failure] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_batch_preparation(
	valid_snapshot: Dictionary,
	invalid_snapshot: Dictionary
) -> void:
	var core := RuntimeCore.new()
	var runtime := GameRuntime.new(core)
	var setup := TrackingSetup.new()

	var registered := setup.register_executors(runtime)
	if registered["ok"]:
		registered = setup.register_content(runtime)
	_expect("Batch probe content registered", registered["ok"])
	if not registered["ok"]:
		runtime.close()
		return

	var rejected := runtime.restore_entities(invalid_snapshot["entities"])
	_expect("Invalid batch creates no partial entities", (
		not rejected["ok"] and not runtime.has_entity(1)
	))

	var retried := runtime.restore_entities(valid_snapshot["entities"])
	_expect("Rejected batch consumes no entity IDs", (
		retried["ok"]
		and retried["value"][&"town_guard_01"] == 1
	))
	runtime.close()


func _entry_is_stopped() -> bool:
	return (
		_entry.runtime == null
		and _entry.world_bridge == null
		and _entry.entity_ids.is_empty()
	)


func _runtime_is_closed(runtime: GameRuntime) -> bool:
	if runtime == null:
		return false

	var result := runtime.snapshot_entity(0)
	return (
		not result["ok"]
		and result["error"] == "Game runtime is closed."
	)


func _expect(label: String, condition: bool) -> void:
	print("[session-restore-failure] ", label, ": ", condition)
	_passed = _passed and condition


func _finalize() -> void:
	_entry.stop()
