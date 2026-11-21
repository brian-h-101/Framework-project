extends SceneTree

const ConfigurationResource = preload("res://Framework/Env/Configuration/Resources/configuration_resource.gd")
const GameHost = preload("res://Framework/Env/Host/game_host.gd")
const SpatialRoot2D = preload("res://Framework/Env/Map/spatial_root_2d.gd")
const GameplayExecutor = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"
)
const ExecutionContext = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/execution_context.gd"
)
const ActionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/action_resource.gd"
)
const MovementAdapter = preload(
	"res://Framework/Content/God/Movement/movement_2d.gd"
)
const ROOT = "res://Framework/Content/Configuration/"
const CONFIGURATIONS = [
	"Session/startup", "Session/world_time", "Input/controls",
	"Movement/player_movement", "Map/city_ground", "Map/scene_defaults",
	"Lighting/shadows", "Lighting/city_lighting", "Presentation/displays",
	"Persistence/session_persistence",
]

class MovementProbe extends GameplayExecutor:
	var calls := 0
	var last_bindings: Dictionary = {}
	var last_arguments: Dictionary = {}
	var response: Variant = {"x": 3.0, "y": 0.0}

	func execute(
		_context: ExecutionContext,
		_definition: Dictionary,
		bindings: Dictionary,
		arguments: Dictionary
	) -> Dictionary:
		calls += 1
		last_bindings = bindings.duplicate(true)
		last_arguments = arguments.duplicate(true)

		return {
			"ok": true,
			"value": response,
			"error": "",
		}


var _passed := true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var configurations := {}
	for relative in CONFIGURATIONS:
		var configuration := load(ROOT + relative + ".tres") as ConfigurationResource
		_check("Typed configuration loads: %s" % relative, configuration != null)
		if configuration == null:
			quit(1)
			return
		var checked := configuration.read()
		_check("Configuration validates: %s" % relative, checked["ok"])
		if not checked["ok"]:
			print(checked["error"])
			quit(1)
			return
		configurations[relative] = configuration

	var startup: Resource = configurations["Session/startup"]
	var controls: Resource = configurations["Input/controls"]
	var movement: Resource = configurations["Movement/player_movement"]
	var displays: Resource = configurations["Presentation/displays"]
	var lighting: Resource = configurations["Lighting/city_lighting"]
	var map_defaults: Resource = configurations["Map/scene_defaults"]
	_check("Map and lighting retain external shared resources", (
		map_defaults.ground_content == configurations["Map/city_ground"]
		and map_defaults.lighting_content == lighting
		and lighting.shadows == configurations["Lighting/shadows"]
	))
	_check("Initial map remains a lazy file path", startup.initial_map is String)
	_check("Startup spawning follows authored order", startup.call("to_definition")["entities"].keys() == _names(startup.entities, "key"))
	_check("Input routing follows authored order", controls.call("to_definition").keys() == _names(controls.bindings, "action"))
	_check("Display fields follow authored order", displays.call("to_definition").keys() == _names(displays.fields, "id"))

	var first: Dictionary = startup.call("to_definition")
	var original: Variant = first["entities"][&"player"]["overrides"][&"health"]["current"]
	first["entities"][&"player"]["overrides"][&"health"]["current"] = -1
	_check("Startup snapshots own nested overrides", (
		startup.call("to_definition")["entities"][&"player"]["overrides"][&"health"]["current"] == original
	))
	first = controls.call("to_definition")
	first[&"primary_interaction"]["keys"].append(KEY_ENTER)
	_check("Input snapshots own key arrays", (
		controls.call("to_definition")[&"primary_interaction"]["keys"] == [KEY_SPACE]
	))
	first = movement.call("to_definition")
	first["speed"]["path"].append("changed")
	first["actions"]["left"] = &"changed"
	_check("Movement snapshots own paths and actions", (
		movement.call("to_definition")["speed"]["path"] == ["current"]
		and movement.call("to_definition")["actions"]["left"] == &"move_left"
	))
	first = displays.call("to_definition")
	first[&"health"]["path"].append("changed")
	_check("Display snapshots own attribute paths", (
		displays.call("to_definition")[&"health"]["path"] == ["current"]
	))
	first = lighting.call("to_definition")
	var original_energy: Variant = first["point_lights"][0]["energy"]
	var original_length: Variant = first["shadows"]["blend"]["length_px"]
	first["day_night"]["sun"]["maximum_energy"] = -1
	first["point_lights"][0]["energy"] = -1
	first["shadows"]["blend"]["length_px"] = -1
	var second: Dictionary = lighting.call("to_definition")
	_check("Lighting snapshots own nested light and shadow data", (
		second["day_night"]["sun"]["maximum_energy"] >= 0.0
		and second["point_lights"][0]["energy"] == original_energy
		and second["shadows"]["blend"]["length_px"] == original_length
	))

	_reject(startup, &"initial_map", "")
	_reject(configurations["Session/world_time"], &"seconds_per_day", 0.0)
	_reject(movement, &"actions", {})
	_reject(movement, &"movement_action", null)
	_reject(configurations["Map/city_ground"], &"dimensions", Vector2i.ZERO)
	_reject(configurations["Lighting/shadows"], &"density", 2.0)
	_reject(lighting, &"shadows", null)
	_reject(map_defaults, &"lighting_content", null)
	_reject(configurations["Persistence/session_persistence"], &"startup_mode", &"unknown")
	var invalid_controls: Resource = controls.duplicate(true)
	invalid_controls.bindings.append({"action": &"bad", "keys": ["Space"]})
	_check("Malformed key codes are rejected", not invalid_controls.call("read")["ok"])
	var invalid_displays: Resource = displays.duplicate(true)
	invalid_displays.fields.append({"id": &"bad", "container": &"health", "path": ["current"]})
	_check("Missing display format is rejected", not invalid_displays.call("read")["ok"])
	var duplicate_controls: Resource = controls.duplicate(true)
	duplicate_controls.bindings.append(duplicate_controls.bindings[0].duplicate(true))
	_check("Duplicate input action names are rejected", not duplicate_controls.call("read")["ok"])
	var duplicate_entities: Resource = startup.duplicate(true)
	duplicate_entities.entities.append(duplicate_entities.entities[0].duplicate(true))
	_check("Duplicate startup entity keys are rejected", not duplicate_entities.call("read")["ok"])

	await _check_live_environment()
	print("[configuration] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_live_environment() -> void:
	var host := GameHost.new()
	var started := host.start(root)
	_check("Fresh host starts using Resource configurations", started["ok"])
	if not started["ok"]:
		print(started["error"])
		return
	var map_node := host.maps.get_active_map()
	var player := host.entry.world_bridge.node_for(host.entry.entity_ids[&"player"])
	var found := SpatialRoot2D.find_for(player)
	_check("Player spatial body is discoverable", found["ok"] and found["value"] is CharacterBody2D)
	if not found["ok"] or not found["value"] is CharacterBody2D:
		host.stop()
		await process_frame
		return
	var body: CharacterBody2D = found["value"]
	var ground := map_node.get_node("Ground") as TileMapLayer
	var configured_dimensions: Vector2i = ground.content.dimensions
	_check("Ground uses configured tile dimensions", (
		ground.tile_set.tile_size == ground.content.tile_size
		and ground.get_used_cells().size() == configured_dimensions.x * configured_dimensions.y
	))
	body.set_physics_process(false)
	var before := body.position
	Input.action_press(&"move_right")
	body.call("_physics_process", 1.0 / Engine.physics_ticks_per_second)
	Input.action_release(&"move_right")
	_check("Configured input moves the Player smoothly", body.position.x > before.x and is_zero_approx(body.position.y - before.y))
	var speed := host.entry.runtime.read_attribute(host.entry.entity_ids[&"player"], &"speed", ["current"])
	_check("Movement still reads runtime speed", (
		speed["ok"]
		and is_equal_approx(body.velocity.x, float(speed["value"]) * body.content.pixels_per_unit)
	))
	var probe := MovementProbe.new()
	var probe_registered := host.entry.runtime.register_executor(
		&"movement_adapter_probe", probe
	)

	var probe_action := ActionResource.new()
	probe_action.id = &"movement_adapter_probe_action"
	probe_action.behavior_id = &"movement_adapter_probe"

	var probe_defined := host.entry.runtime.define_action(
		probe_action.to_definition()
	)

	_check(
		"Diagnostic movement Action registers",
		probe_registered["ok"] and probe_defined["ok"]
	)

	if probe_registered["ok"] and probe_defined["ok"]:
		var probe_configuration: Resource = body.content.duplicate(true)
		probe_configuration.movement_action = probe_action

		var probe_body := MovementAdapter.new()
		probe_body.content = probe_configuration
		probe_body.configure_entity(host.entry.world_bridge, player)

		player.add_child(probe_body)
		probe_body.set_physics_process(false)

		Input.action_press(&"move_right")
		probe_body.call(
			"_physics_process",
			1.0 / Engine.physics_ticks_per_second
		)
		Input.action_release(&"move_right")

		var player_id: int = host.entry.entity_ids[&"player"]

		_check(
			"Movement invokes its configured Action with entity bindings",
			probe.calls == 1
			and probe.last_bindings.get(&"actor") == player_id
			and probe.last_bindings.get(&"target") == player_id
			and probe.last_arguments.get(&"direction_x") == 1.0
			and probe.last_arguments.get(&"speed_container")
				== probe_configuration.speed_container
			and probe.last_arguments.get(&"speed_path")
				== probe_configuration.speed_path
		)

		_check(
			"Env applies Action velocity and pixel scaling",
			is_equal_approx(
				probe_body.velocity.x,
				3.0 * probe_configuration.pixels_per_unit
			)
			and is_zero_approx(probe_body.velocity.y)
		)

		for invalid_output in [
			"invalid",
			{"x": NAN, "y": 0.0},
			{"x": 1.0e40, "y": 0.0},
		]:
			probe.response = invalid_output
			var rejected: Dictionary = probe_body.call(
				"_execute_movement", Vector2.RIGHT
			)
			_check(
				"Invalid movement output is rejected",
				not rejected["ok"]
			)

		probe_body.free()
	var lighting_node := map_node.get_node("Lighting")
	_check("Shared shadow configuration reaches lighting", (
		lighting_node.get("_shadow_profile") == lighting_node.content.shadows.to_definition()
	))
	host.stop()
	await process_frame


func _reject(configuration: Resource, property: StringName, value: Variant) -> void:
	var invalid: Resource = configuration.duplicate(true)
	invalid.set(property, value)
	var checked: Dictionary = invalid.call("read")
	_check("Invalid %s is rejected" % property, not checked["ok"] and not String(checked["error"]).is_empty())


func _names(entries: Array[Dictionary], key_field: String) -> Array[StringName]:
	var names: Array[StringName] = []
	for entry in entries:
		names.append(StringName(entry[key_field]))
	return names


func _check(label: String, passed: bool) -> void:
	print("[configuration] ", label, ": ", passed)
	_passed = _passed and passed
