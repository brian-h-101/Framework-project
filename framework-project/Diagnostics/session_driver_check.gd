extends SceneTree

const GameHost = preload(
	"res://Framework/Env/Host/game_host.gd"
)
const CityMap = preload(
	"res://Games/ExampleGame/World/city.tscn"
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
	var driver := root.get_node_or_null("SessionDriver")
	var initial := runtime.read_time()

	await process_frame
	await process_frame

	var later := runtime.read_time()
	var automatic: bool = (
		initial.ok
		and later.ok
		and float(later.value["hour"]) > float(initial.value["hour"])
	)
	print("[driver] Advances automatically: ", automatic)

	_host.maps.unload_map()
	var before_without_map := runtime.read_time()

	await process_frame
	await process_frame

	var after_without_map := runtime.read_time()
	var without_map: bool = (
		before_without_map.ok
		and after_without_map.ok
		and float(after_without_map.value["hour"]) > float(before_without_map.value["hour"])
	)
	print("[driver] Advances without a map: ", without_map)

	var loaded := _host.maps.load_map(CityMap)
	if not loaded.ok:
		push_error(loaded.error)
		quit(1)
		return

	var same_driver: bool = (
		is_instance_valid(driver)
		and root.get_node_or_null("SessionDriver") == driver
	)
	print("[driver] Map reload keeps the driver: ", same_driver)

	_host.stop()

	var detached: bool = root.get_node_or_null("SessionDriver") == null
	print("[driver] Driver detached on stop: ", detached)

	await process_frame
	await process_frame

	var closed := runtime.read_time()
	var passed: bool = (
		automatic
		and without_map
		and same_driver
		and detached
		and not closed.ok
	)

	print("[driver] Checks passed: ", passed)

	if not passed:
		push_error("Session driver lifecycle check failed.")

	quit(0 if passed else 1)


func _finalize() -> void:
	_host.stop()
