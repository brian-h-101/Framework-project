extends SceneTree

const ConfigurationResource = preload("res://Framework/Env/Configuration/Resources/Shared/configuration_resource.gd")
const GameHost = preload("res://Framework/Env/Host/game_host.gd")
const SpatialRoot2D = preload("res://Framework/Content/Universal/Map/based/Spatial2D/spatial_root_2d.gd")
const GameplayExecutor = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd"
)
const ExecutionContext = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/execution_context.gd"
)
const BehaviorResource = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd")
const ActionStep = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/action_step_resource.gd")
const Movement = preload("res://Framework/Content/Universal/Movement/based/Execution/movement_component.gd")
const SharedMovement = preload("res://Framework/Content/Gameplay/Profiles/Movement/Shared/movement_2d.tres")
const ROOT = "res://Framework/Content/Configuration/"
const CONFIGURATIONS = [
	"Session/startup", "Session/world_time", "Input/controls",
	"Map/city_ground", "Map/scene_defaults",
	"Lighting/shadows", "Lighting/city_lighting", "Presentation/displays",
	"Persistence/session_persistence",
]

class MovementProbe extends GameplayExecutor:
	var calls := 0
	var last_bindings: Dictionary = {}
	var last_arguments: Dictionary = {}
	var response: Variant = {&"lateral": 3.0, &"forward": 0.0, &"vertical": 0.0}

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
	var displays: Resource = configurations["Presentation/displays"]
	var lighting: Resource = configurations["Lighting/city_lighting"]
	var map_defaults: Resource = configurations["Map/scene_defaults"]
	var movement_checked := SharedMovement.read()
	_check("Shared movement profile validates", movement_checked["ok"])
	if not movement_checked["ok"]:
		print(movement_checked["error"])
		quit(1)
		return
	_check("Map and lighting retain external shared resources", (
		map_defaults.ground_content == configurations["Map/city_ground"]
		and map_defaults.lighting_content == lighting
		and lighting.shadows == configurations["Lighting/shadows"]
	))
	_check("Initial map remains a lazy file path", startup.initial_map is String)
	var startup_probe: Resource = startup.duplicate(true)
	startup_probe.entities.assign([
		{"key": &"player", "definition": &"player", "overrides": {&"health": {"current": 75}}},
		{"key": &"enemy", "definition": &"enemy"},
	])
	_check("Startup spawning follows authored order", (
		startup_probe.call("to_definition")["entities"].keys() == _names(startup_probe.entities, "key")
	))
	_check("Input routing follows authored order", controls.call("to_definition").keys() == _names(controls.bindings, "action"))
	_check("Display fields follow authored order", displays.call("to_definition").keys() == _names(displays.fields, "id"))

	var first: Dictionary = startup_probe.call("to_definition")
	var original: Variant = first["entities"][&"player"]["overrides"][&"health"]["current"]
	first["entities"][&"player"]["overrides"][&"health"]["current"] = -1
	_check("Startup snapshots own nested overrides", (
		startup_probe.call("to_definition")["entities"][&"player"]["overrides"][&"health"]["current"] == original
	))
	first = controls.call("to_definition")
	var original_keys: Array = first[&"move_right"]["keys"].duplicate()
	first[&"move_right"]["keys"].append(KEY_ENTER)
	_check("Input snapshots own key arrays", (
		controls.call("to_definition")[&"move_right"]["keys"] == original_keys
	))
	first = SharedMovement.velocity_step()
	var original_speed_path: Array = first["arguments"][&"speed_path"].duplicate()
	first["arguments"][&"speed_path"].append("changed")
	_check("Movement velocity step snapshots own their speed paths", (
		SharedMovement.velocity_step()["arguments"][&"speed_path"] == original_speed_path
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

	_reject(startup, &"initial_map", "outside_project.tscn")
	_reject(configurations["Session/world_time"], &"seconds_per_day", 0.0)
	_reject(SharedMovement, &"velocity_step_id", &"missing")
	_reject(SharedMovement, &"movement_behavior", null)
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
	var duplicate_entities: Resource = startup_probe.duplicate(true)
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
	_check("Player uses the shared movement profile", body.get("content") == SharedMovement)
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
		and is_equal_approx(
			body.velocity.x,
			float(speed["value"]) * SharedMovement.resolved_environment().units_per_gameplay_unit
		)
	))
	_check_movement_probe(host, map_node, player, body)
	var lighting_node := map_node.get_node("Lighting")
	_check("Shared shadow configuration reaches lighting", (
		lighting_node.get("_shadow_profile") == lighting_node.content.shadows.to_definition()
	))
	host.stop()
	await process_frame


func _check_movement_probe(host: GameHost, map_node: Node, player: Node, body: CharacterBody2D) -> void:
	var runtime := host.entry.runtime
	var bridge := host.entry.world_bridge
	var probe := MovementProbe.new()
	var registered := runtime.register_executor(&"movement_adapter_probe", probe)

	var step := ActionStep.new()
	step.id = SharedMovement.velocity_step_id
	step.executor_id = &"movement_adapter_probe"
	step.arguments = SharedMovement.velocity_step()["arguments"]
	var behavior := BehaviorResource.new()
	behavior.id = &"movement_adapter_probe_behavior"
	behavior.configuration = SharedMovement.movement_behavior.configuration
	behavior.steps.append(step)

	var defined := runtime.define_behavior(behavior.to_definition())
	var bound := bridge.bind_behavior(player, behavior.id)
	var available: bool = registered["ok"] and defined["ok"] and bound["ok"]
	_check("Diagnostic movement Behavior registers and binds", available)
	if not available:
		print(registered, defined, bound)
		return

	var profile := SharedMovement.duplicate()
	profile.movement_behavior = behavior
	var movement := Movement.new()
	movement.configure_entity(bridge, player)
	movement.configure_map(map_node)
	var started := movement.start(body, profile, body.get("controller"))
	_check("Movement runs the probe with the authored controller", started.is_empty())
	if not started.is_empty():
		print(started)
		return

	var delta := 1.0 / Engine.physics_ticks_per_second
	Input.action_press(&"move_right")
	var error := movement.advance(delta)
	Input.action_release(&"move_right")
	var player_id: int = host.entry.entity_ids[&"player"]
	_check("Movement invokes its configured step with entity bindings", (
		error.is_empty() and probe.calls == 1
		and probe.last_bindings.get(&"actor") == player_id
		and probe.last_bindings.get(&"target") == player_id
		and probe.last_arguments.get(&"lateral") == 1.0
		and probe.last_arguments.get(&"speed_container") == step.arguments[&"speed_container"]
		and probe.last_arguments.get(&"speed_path") == step.arguments[&"speed_path"]
	))
	var scale: float = SharedMovement.resolved_environment().units_per_gameplay_unit
	_check("The 2D driver applies Behavior velocity and pixel scaling", (
		body.velocity.is_equal_approx(Vector2(3.0 * scale, 0.0))
	))
	for invalid_output in [
		"invalid",
		{&"lateral": NAN, &"forward": 0.0, &"vertical": 0.0},
		{&"lateral": 1.0e40, &"forward": 0.0, &"vertical": 0.0},
	]:
		probe.response = invalid_output
		_check("Invalid movement output is rejected", not movement.advance(delta).is_empty())


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
