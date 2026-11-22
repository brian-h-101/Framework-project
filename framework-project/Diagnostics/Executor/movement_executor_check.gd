extends SceneTree

const Runtime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const Core = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd"
)
const Discovery = preload(
	"res://Framework/Env/Setup/Discovery/executor_discovery.gd"
)
const Executor = preload(
	"res://Framework/Content/Gameplay/Profiles/Movement/Executor/movement_2d_executor.gd"
)
const Intent = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_intent.gd")
const VelocityCalculator = preload("res://Framework/Content/Universal/Movement/based/Execution/velocity_calculator.gd")
var _passed := true


func _initialize() -> void:
	_check_calculator()
	var runtime := Runtime.new(Core.new())
	_run_check(runtime)
	runtime.close()

	print("[movement-executor] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_calculator() -> void:
	var normalized := VelocityCalculator.calculate(Intent.axes(1, 1, 1), 12)
	_expect("Universal calculator normalizes a three-axis intent without a runtime",
		normalized["ok"] and is_equal_approx(normalized["value"][&"vertical"], 12.0 / sqrt(3.0)))
	var partial := VelocityCalculator.calculate(Intent.axes(0, -0.5), 20)
	_expect("Universal calculator preserves partial input",
		partial["ok"] and partial["value"] == Intent.axes(0, -10))
	_expect("Universal calculator rejects invalid intent axes and speed", (
		not VelocityCalculator.calculate(Intent.axes(0, INF), 20)["ok"]
		and not VelocityCalculator.calculate(Intent.axes(1.01, 0), 20)["ok"]
		and not VelocityCalculator.calculate(Intent.axes(0, 1), -1)["ok"]
	))


func _run_check(runtime: Runtime) -> void:
	var discovered := Discovery.register_all(runtime)

	if not _expect(
		"Content executor discovered",
		discovered["ok"] and runtime.has_executor(Executor.BEHAVIOR_ID)
	):
		return

	var defined := runtime.define_behavior({
		"id": &"move_probe",
		"configuration": {
			"trigger": "manual",
			"targeting": "self",
			"interval_seconds": 1.0,
			"cooldown_seconds": 0.0,
		},
		"steps": [{
			"id": &"calculate_velocity",
			"label": "Calculate Velocity",
			"kind": "action",
			"requirements": [],
			"executor_id": Executor.BEHAVIOR_ID,
			"arguments": {
				&"direction_x": 0.0,
				&"direction_y": 0.0,
				&"speed_container": &"speed",
				&"speed_path": ["current"],
			},
			"effects": [],
		}],
	})
	if not _expect("Movement Behavior registered", defined["ok"]):
		return

	var containers: Dictionary[StringName, Dictionary] = {
		&"speed": {"current": 20, "maximum": 50},
	}
	runtime.define_attributes(&"movement_probe", containers)
	var entity_id: int = runtime.spawn(&"movement_probe")
	var bound := runtime.bind_behavior(entity_id, &"move_probe")
	if not _expect("Movement Behavior bound", bound["ok"]):
		return

	var writes: Array = []
	runtime.attribute_written.connect(
		func(
			written_id: int,
			container_id: StringName,
			attribute_name: StringName
		) -> void:
			writes.append([written_id, container_id, attribute_name])
	)

	var before := runtime.snapshot_entity(entity_id)

	var cases: Array[Dictionary] = [
		{"label": "Idle", "input": [0.0, 0.0], "expected": [0.0, 0.0]},
		{"label": "Right", "input": [1.0, 0.0], "expected": [20.0, 0.0]},
		{"label": "Up", "input": [0.0, -1.0], "expected": [0.0, -20.0]},
		{"label": "Partial input", "input": [0.5, 0.0], "expected": [10.0, 0.0]},
		{"label": "Diagonal", "input": [1.0, 1.0], "expected": [sqrt(200.0), sqrt(200.0)]},
	]

	for test_case: Dictionary in cases:
		var result := _move(
			runtime, entity_id,
			test_case["input"][0], test_case["input"][1]
		)
		_expect(
			test_case["label"],
			_velocity_is(
				result,
				test_case["expected"][0],
				test_case["expected"][1]
			)
		)

	var idle := runtime.invoke_behavior(&"move_probe", entity_id, _self_target)
	_expect(
		"Invocation preserves the authored direction defaults",
		idle["ok"] and _velocity_is(idle["value"]["steps"][0]["result"], 0.0, 0.0)
	)

	var unknown_step := runtime.invoke_behavior(
		&"move_probe", entity_id, _self_target, &"missing", {&"direction_x": 1.0}
	)
	_expect("Unknown step is rejected", not unknown_step["ok"])

	var unknown_argument := runtime.invoke_behavior(
		&"move_probe", entity_id, _self_target, &"calculate_velocity", {&"missing": 1.0}
	)
	_expect("Unknown argument is rejected", not unknown_argument["ok"])

	var after := runtime.snapshot_entity(entity_id)
	_expect(
		"Calculations preserve entity state",
		before["ok"] and after["ok"]
		and before["value"] == after["value"]
	)
	_expect("Calculations emit no writes", writes.is_empty())

	var changed := runtime.write_attribute(
		entity_id, &"speed", ["current"], 10
	)
	_expect(
		"Runtime speed changes affect the next calculation",
		changed["ok"]
		and _velocity_is(_move(runtime, entity_id, 1.0, 0.0), 10.0, 0.0)
	)

	changed = runtime.write_attribute(
		entity_id, &"speed", ["current"], 0
	)
	_expect(
		"Zero speed produces zero velocity",
		changed["ok"]
		and _velocity_is(_move(runtime, entity_id, 1.0, 0.0), 0.0, 0.0)
	)

	_expect(
		"Out-of-range direction is rejected",
		not _move(runtime, entity_id, 1.1, 0.0)["ok"]
	)
	_expect(
		"Nonnumeric direction is rejected",
		not _move(runtime, entity_id, "invalid", 0.0)["ok"]
	)
	_expect(
		"Nonfinite direction is rejected",
		not _move(runtime, entity_id, NAN, 0.0)["ok"]
	)

	for invalid_speed in [-1.0, INF, "invalid"]:
		changed = runtime.write_attribute(
			entity_id, &"speed", ["current"], invalid_speed
		)
		_expect(
			"Invalid speed is rejected",
			changed["ok"]
			and not _move(runtime, entity_id, 1.0, 0.0)["ok"]
		)


func _move(
	runtime: Runtime,
	entity_id: int,
	x: Variant,
	y: Variant
) -> Dictionary:
	var result := runtime.invoke_behavior(
		&"move_probe", entity_id, _self_target, &"calculate_velocity",
		{&"direction_x": x, &"direction_y": y}
	)
	if not result["ok"]:
		return result
	return result["value"]["steps"][0]["result"]


func _self_target(entity_id: int, _mode: StringName) -> Dictionary:
	return {"ok": true, "value": entity_id, "error": ""}


func _velocity_is(result: Dictionary, x: float, y: float) -> bool:
	if not result["ok"] or not result["value"] is Dictionary:
		return false

	var velocity: Dictionary = result["value"]
	if (
		typeof(velocity.get("x")) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(velocity.get("y")) not in [TYPE_INT, TYPE_FLOAT]
	):
		return false

	return (
		is_equal_approx(float(velocity["x"]), x)
		and is_equal_approx(float(velocity["y"]), y)
	)


func _expect(label: String, passed: bool) -> bool:
	_passed = passed and _passed
	print("[movement-executor] %s: %s" % [label, passed])
	return passed
