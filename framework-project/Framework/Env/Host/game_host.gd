extends RefCounted

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/game_setup.gd"
)
const MapCoordinator = preload(
	"res://Framework/Env/Map/map_coordinator.gd"
)
const Controls = preload(
	"res://Framework/Content/Configuration/Input/controls.gd"
)
const InputConfiguration = preload(
	"res://Framework/Env/Input/input_configuration.gd"
)
const Displays = preload(
	"res://Framework/Content/Configuration/Presentation/displays.gd"
)
const SessionDriver = preload(
	"res://Framework/Env/Session/session_driver.gd"
)
const UIRootScene = preload(
	"res://Framework/Content/UI/HUD/ui_root.tscn"
)
const SessionStore = preload(
	"res://Framework/Infrastructure/API/Persistence/session_store.gd"
)
const SessionInput = preload(
	"res://Framework/Env/Input/session_input.gd"
)
const SessionPersistence = preload(
	"res://Framework/Content/Configuration/Persistence/session_persistence.gd"
)
var entry := GameEntry.new()
var maps: MapCoordinator
var ui: CanvasLayer
var _driver: SessionDriver
var _session_input: SessionInput

func start_configured(map_parent: Node) -> Dictionary:
	var settings := SessionPersistence.defaults()
	var startup_mode := StringName(settings["startup_mode"])

	match startup_mode:
		&"new":
			return start(map_parent)
		&"restore":
			return restore_session(
				map_parent,
				String(settings["save_path"])
			)

	return {
		"ok": false,
		"value": null,
		"error": "Unknown startup mode: %s" % startup_mode,
	}

func start(map_parent: Node) -> Dictionary:
	if not is_instance_valid(map_parent):
		return {
			"ok": false,
			"value": null,
			"error": "Map parent is invalid.",
		}

	var setup := EnvironmentSetup.new()
	var started := entry.start(setup)
	if not started["ok"]:
		return started

	return _start_environment(map_parent, setup)


func save_session(path: String) -> Dictionary:
	var captured := entry.snapshot_session()
	if not captured["ok"]:
		return captured

	var map_state: Variant = null
	if maps != null:
		var captured_map := maps.snapshot_map()
		if not captured_map["ok"]:
			return captured_map
		map_state = captured_map["value"]

	var snapshot: Dictionary = captured["value"]
	snapshot["environment"] = {
		"map": map_state,
	}

	var saved := SessionStore.save_file(path, snapshot)

	if saved["ok"] and snapshot.has("clock"):
		print("[clock] Saved state: ", snapshot["clock"])

	return saved

func restore_session(map_parent: Node, path: String) -> Dictionary:
	if entry.runtime != null:
		return _failure("Game session has already started.")

	if not is_instance_valid(map_parent):
		return _failure("Map parent is invalid.")

	var loaded := SessionStore.load_file(path)
	if not loaded["ok"]:
		return loaded

	var snapshot: Dictionary = loaded["value"]
	var saved_environment: Variant = snapshot.get("environment", {})
	if not saved_environment is Dictionary:
		return _failure("Saved environment must be a dictionary.")

	var environment: Dictionary = saved_environment
	var setup := EnvironmentSetup.new()

	var restored := entry.restore_session(setup, snapshot)
	if not restored["ok"]:
		return restored

	return _start_environment(map_parent, setup, environment)

func stop() -> void:
	if is_instance_valid(_session_input):
		_session_input.set_process_unhandled_input(false)

		if _session_input.command_requested.is_connected(
			_on_session_command_requested
		):
			_session_input.command_requested.disconnect(
				_on_session_command_requested
			)

		var input_parent := _session_input.get_parent()
		if input_parent != null:
			input_parent.remove_child(_session_input)

		_session_input.queue_free()

	_session_input = null

	if is_instance_valid(_driver):
		_driver.set_process(false)

		var parent := _driver.get_parent()
		if parent != null:
			parent.remove_child(_driver)

		_driver.queue_free()

	_driver = null

	if is_instance_valid(ui):
		var ui_parent := ui.get_parent()
		if ui_parent != null:
			ui_parent.remove_child(ui)

		ui.queue_free()

	ui = null

	if maps != null:
		maps.unload_map()
		maps = null

	entry.stop()


func _start_environment(
	map_parent: Node,
	setup: EnvironmentSetup,
	environment: Dictionary = {}
) -> Dictionary:
	var selected_map := _select_map_scene(setup, environment)
	if not selected_map["ok"]:
		stop()
		return selected_map

	var map_scene: PackedScene = selected_map["value"]
	var starting_clock := entry.runtime.snapshot_time()
	if starting_clock["ok"] and starting_clock["value"] != null:
		print("[clock] Session start: ", starting_clock["value"])
	var controls := Controls.defaults()
	InputConfiguration.apply(controls)
	var displays := Displays.defaults()

	maps = MapCoordinator.new(
		map_parent,
		entry.world_bridge,
		entry.entity_ids,
		controls,
		entry.runtime
	)

	if map_scene != null:
		var saved_positions: Dictionary = {}
		var saved_map: Variant = environment.get("map")

		if saved_map is Dictionary:
			var positions_value: Variant = saved_map.get("positions_2d", {})
			if not (positions_value is Dictionary):
				stop()
				return _failure(
					"Saved map positions_2d must be a dictionary."
				)

			saved_positions = positions_value

		var loaded := maps.load_map(map_scene, saved_positions)
		if not loaded["ok"]:
			stop()
			return loaded

	ui = UIRootScene.instantiate() as CanvasLayer

	for component in ui.find_children("*", "", true, false):
		if component.has_method(&"configure_session"):
			component.call(
				&"configure_session",
				entry.runtime,
				entry.world_bridge,
				entry.entity_ids,
				displays
			)

	map_parent.add_child(ui)

	_driver = SessionDriver.new(entry.runtime)
	_driver.name = &"SessionDriver"
	map_parent.add_child(_driver)
	_session_input = SessionInput.new()
	_session_input.name = &"SessionInput"
	_session_input.configure_controls(controls)
	_session_input.command_requested.connect(_on_session_command_requested)
	map_parent.add_child(_session_input)

	return {
		"ok": true,
		"value": true,
		"error": "",
	}

func _on_session_command_requested(command_id: StringName) -> void:
	match command_id:
		&"save_session":
			var settings := SessionPersistence.defaults()
			var result := save_session(String(settings["save_path"]))
			print("[session] %s: %s" % [command_id, result])
		_:
			push_warning("Unknown session command: %s" % command_id)

func _select_map_scene(
	setup: EnvironmentSetup,
	environment: Dictionary
) -> Dictionary:
	if not environment.has("map"):
		var initial_map := setup.get_initial_map()
		if initial_map == null or not initial_map.can_instantiate():
			return _failure("Initial map scene cannot be instantiated.")

		return {"ok": true, "value": initial_map, "error": ""}

	var saved_map: Variant = environment["map"]
	if saved_map == null:
		return {"ok": true, "value": null, "error": ""}

	if not saved_map is Dictionary:
		return _failure("Saved map must be a dictionary or null.")

	var map_record: Dictionary = saved_map
	var path_value: Variant = map_record.get("scene_path")
	if typeof(path_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure("Saved map scene_path must be text.")

	var scene_path := String(path_value)
	if scene_path.is_empty():
		return _failure("Saved map scene_path cannot be empty.")

	if not ResourceLoader.exists(scene_path):
		return _failure("Saved map scene does not exist: %s" % scene_path)

	var map_scene := ResourceLoader.load(scene_path) as PackedScene
	if map_scene == null or not map_scene.can_instantiate():
		return _failure(
			"Saved map scene cannot be instantiated: %s" % scene_path
		)

	return {"ok": true, "value": map_scene, "error": ""}


func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}