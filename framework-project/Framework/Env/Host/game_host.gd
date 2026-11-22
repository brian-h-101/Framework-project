extends RefCounted

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/Bootstrap/game_setup.gd"
)
const MapCoordinator = preload(
	"res://Framework/Env/Map/map_coordinator.gd"
)
const MapPositions = preload(
	"res://Framework/Env/Map/map_positions.gd"
)
const Controls = preload(
	"res://Framework/Content/Configuration/Input/controls.tres"
)
const InputConfiguration = preload(
	"res://Framework/Env/Input/input_configuration.gd"
)
const Displays = preload(
	"res://Framework/Content/Configuration/Presentation/displays.tres"
)
const SessionDriver = preload(
	"res://Framework/Env/Session/session_driver.gd"
)
const SessionStore = preload(
	"res://Framework/Infrastructure/API/Persistence/session_store.gd"
)
const SessionInput = preload(
	"res://Framework/Env/Input/session_input.gd"
)
const SessionPersistence = preload(
	"res://Framework/Content/Configuration/Persistence/session_persistence.tres"
)
var entry := GameEntry.new()
var maps: MapCoordinator
var ui: CanvasLayer
var _driver: SessionDriver
var _session_input: SessionInput

func start_configured(map_parent: Node) -> Dictionary:
	var checked := SessionPersistence.read()
	if not checked["ok"]:
		return checked
	var settings: Dictionary = checked["value"]
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

	var selected_ui := setup.get_ui_scene_result()
	if not selected_ui["ok"]:
		stop()
		return selected_ui
	var ui_scene: PackedScene = selected_ui["value"]
	var map_scene: PackedScene = selected_map["value"]
	var starting_clock := entry.runtime.snapshot_time()
	if starting_clock["ok"] and starting_clock["value"] != null:
		print("[clock] Session start: ", starting_clock["value"])
	var controls_result := Controls.read()
	var displays_result := Displays.read()
	if not controls_result["ok"] or not displays_result["ok"]:
		stop()
		return controls_result if not controls_result["ok"] else displays_result
	var controls: Dictionary[StringName, Dictionary] = controls_result["value"]
	var displays: Dictionary[StringName, Dictionary] = displays_result["value"]
	InputConfiguration.apply(controls)

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
			var positions := MapPositions.read_saved_positions(saved_map)
			if not positions["ok"]:
				stop()
				return positions

			saved_positions = positions["value"]

		var loaded := maps.load_map(map_scene, saved_positions)
		if not loaded["ok"]:
			stop()
			return loaded

	if ui_scene != null:
		var ui_node := ui_scene.instantiate()
		if not ui_node is CanvasLayer:
			ui_node.free()
			stop()
			return _failure("The configured UI scene must have a CanvasLayer root.")
		ui = ui_node as CanvasLayer
		var components: Array[Node] = [ui]
		components.append_array(ui.find_children("*", "", true, false))
		for component in components:
			if component.has_method(&"configure_session"):
				component.call(
					&"configure_session",
					entry.runtime,
					entry.world_bridge,
					entry.entity_ids,
					displays
				)
		map_parent.add_child(ui)

	_driver = SessionDriver.new(entry.runtime, entry.world_bridge, maps.get_active_map)
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
			var checked := SessionPersistence.read()
			if not checked["ok"]:
				print("[session] %s: %s" % [command_id, checked])
				return
			var settings: Dictionary = checked["value"]
			var result := save_session(String(settings["save_path"]))
			print("[session] %s: %s" % [command_id, result])
		_:
			push_warning("Unknown session command: %s" % command_id)

func _select_map_scene(
	setup: EnvironmentSetup,
	environment: Dictionary
) -> Dictionary:
	if not environment.has("map"):
		return setup.get_initial_map_result()

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
		var settings := SessionPersistence.read()
		if not settings["ok"]:
			return settings
		var redirects: Dictionary = settings["value"].get("map_path_redirects", {})
		scene_path = String(redirects.get(scene_path, scene_path))
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
