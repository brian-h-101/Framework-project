extends SceneTree

const Runtime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const Core = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/runtime_core.gd"
)
const Discovery = preload(
	"res://Framework/Env/Setup/executor_discovery.gd"
)
const Executor = preload(
	"res://Framework/Content/Executor/movement_2d_executor.gd"
)
const Action = preload(
	"res://Framework/Content/Behavior/Action/move.tres"
)

var _passed := true


func _initialize() -> void:
	var runtime := Runtime.new(Core.new())
	_run_check(runtime)
	runtime.close()

	print("[movement-executor] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _run_check(runtime: Runtime) -> void:
	var discovered := Discovery.register_all(runtime)

	if not _expect(
		"Content executor discovered",
		discovered["ok"] and runtime.has_executor(Executor.BEHAVIOR_ID)
	):
		return

	var defined := runtime.define_action(Action.to_definition())
	if not _expect("Move Action registered", defined["ok"]):
		return

	var containers: Dictionary[StringName, Dictionary] = {
		&"speed": {"current": 20, "maximum": 50},
	}
	runtime.define_attributes(&"movement_probe", containers)
	var entity_id: int = runtime.spawn(&"movement_probe")

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
		{"label": "Right", "input": [1.0, 0.0], "expected": [20.0, 0.0]},
		{"label": "Up", "input": [0.0, -1.0], "expected": [0.0, -20.0]},
		{"label": "Partial input", "input": [0.5, 0.0], "expected": [10.0, 0.0]},
		{"label": "Diagonal", "input": [1.0, 1.0], "expected": [sqrt(200.0), sqrt(200.0)]},
		{"label": "Idle", "input": [0.0, 0.0], "expected": [0.0, 0.0]},
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
	return runtime.execute_action(
		Action.id,
		entity_id,
		entity_id,
		{
			&"direction_x": x,
			&"direction_y": y,
			&"speed_container": &"speed",
			&"speed_path": ["current"],
		}
	)


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