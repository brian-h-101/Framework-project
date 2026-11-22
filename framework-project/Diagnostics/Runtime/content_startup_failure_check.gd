extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/Bootstrap/game_setup.gd"
)
const FailureSetup = preload(
	"res://Diagnostics/Fixtures/Setup/content_failure_setup.gd"
)

var _entry := GameEntry.new()
var _passed: bool = true


func _initialize() -> void:
	var failure_setup := FailureSetup.new()
	var rejected := _entry.start(failure_setup)

	print("[startup-failure] Rejected start: ", rejected)

	var error_message := String(rejected["error"])

	_expect("Duplicate error reaches GameEntry", (
		not rejected["ok"]
		and error_message.contains("Duplicate ID 'change_health'")
		and error_message.contains("first.gd")
		and error_message.contains("second.gd")
	))

	_expect(
		"Entity creation was skipped",
		not failure_setup.create_entities_called
	)
	_expect(
		"Runtime reference cleared",
		_entry.runtime == null
	)
	_expect(
		"World bridge was not created",
		_entry.world_bridge == null
	)
	_expect(
		"Entity IDs remain empty",
		_entry.entity_ids.is_empty()
	)

	var previous_runtime_closed := false

	if failure_setup.captured_runtime != null:
		var previous_read := failure_setup.captured_runtime.read_time()

		previous_runtime_closed = (
			not previous_read["ok"]
			and previous_read["error"] == "Game runtime is closed."
		)

	_expect(
		"Previous runtime is closed",
		previous_runtime_closed
	)

	var restarted := _entry.start(EnvironmentSetup.new())

	_expect(
		"Retry succeeds on the same GameEntry",
		restarted["ok"]
	)

	if restarted["ok"]:
		_expect(
			"Retry creates a new runtime",
			_entry.runtime != failure_setup.captured_runtime
		)

		var player_id: int = _entry.entity_ids[&"player"]
		var enemy_id: int = _entry.entity_ids[&"enemy"]

		var health := _entry.runtime.read_attribute(
			enemy_id,
			&"health",
			["current"]
		)

		_expect("Fresh enemy health is 100", (
			health["ok"]
			and health["value"] == 100
		))

		var strike := _entry.runtime.interact(
			&"strike",
			player_id,
			enemy_id
		)

		_expect("Strike works after retry", (
			strike["ok"]
			and strike["value"] == 90
		))

	_entry.stop()

	print("[startup-failure] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _expect(description: String, condition: bool) -> void:
	_passed = _passed and condition
	print("[startup-failure] %s: %s" % [description, condition])


func _finalize() -> void:
	_entry.stop()
