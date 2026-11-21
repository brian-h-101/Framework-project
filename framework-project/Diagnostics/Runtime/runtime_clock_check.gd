extends SceneTree

const GameHost = preload(
	"res://Framework/Env/Host/game_host.gd"
)
const CityMap = preload(
	"res://Framework/Content/Maps/city.tscn"
)

var _host := GameHost.new()


func _initialize() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	var started := _host.start(root)
	if not started.ok:
		push_error(started.error)
		quit(1)
		return

	var runtime := _host.entry.runtime
	var initial := runtime.read_time()
	var advanced := runtime.advance_time(30.0)

	print("[runtime-clock] Initial: ", initial)
	print("[runtime-clock] After advance: ", advanced)

	var rejected := runtime.advance_time(-1.0)
	var after_rejected := runtime.read_time()
	print("[runtime-clock] Rejected negative step: ", rejected)

	var loaded := _host.maps.load_map(CityMap)
	if not loaded.ok:
		push_error(loaded.error)
		quit(1)
		return

	var after_reload := runtime.read_time()
	var same_runtime := _host.entry.runtime == runtime

	print("[runtime-clock] After map reload: ", after_reload)
	print("[runtime-clock] Same runtime: ", same_runtime)

	_host.stop()

	var closed := runtime.read_time()
	var closed_advance := runtime.advance_time(1.0)
	print("[runtime-clock] Closed read: ", closed)
	print("[runtime-clock] Closed advance: ", closed_advance)

	var passed: bool = (
		initial.ok
		and advanced.ok
		and not rejected.ok
		and after_rejected.ok
		and after_reload.ok
		and same_runtime
		and is_equal_approx(float(initial.value["hour"]), 8.0)
		and is_equal_approx(float(advanced.value["hour"]), 14.0)
		and is_equal_approx(float(after_rejected.value["hour"]), 14.0)
		and is_equal_approx(float(after_reload.value["hour"]), 14.0)
		and not closed.ok
		and not closed_advance.ok
	)

	print("[runtime-clock] Checks passed: ", passed)

	if not passed:
		push_error("Runtime clock integration check failed.")

	quit(0 if passed else 1)


func _finalize() -> void:
	_host.stop()
