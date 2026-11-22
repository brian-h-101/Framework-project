extends SceneTree

const GameHost = preload("res://Framework/Env/Host/game_host.gd")
const Movement = preload("res://Framework/Content/Universal/Movement/based/Configuration/movement_profile.gd")

var _passed := true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := GameHost.new()
	var started := host.start(root)
	if not started["ok"]:
		push_error(str(started["error"]))
		quit(1)
		return

	var bridge := host.entry.world_bridge
	var player_id: int = host.entry.entity_ids.get(&"player", 0)
	var player := bridge.node_for(player_id)

	var right := bridge.invoke_behavior(
		player, &"move", &"calculate_velocity",
		{&"lateral": 1.0}
	)
	var up := bridge.invoke_behavior(
		player, &"move", &"calculate_velocity",
		{&"forward": 1.0}
	)

	print("[bridge-movement] Right report: ", right)
	print("[bridge-movement] Up report: ", up)
	_check("Direct Behavior invocation returns gameplay velocity", _has_velocity(right, 20.0, 0.0) and _has_velocity(up, 0.0, 20.0))
	var diagonal := bridge.invoke_behavior(player, &"move", &"calculate_velocity", {
		&"lateral": 1.0, &"forward": 1.0, &"vertical": 1.0,
	})
	var diagonal_axis := 20.0 / sqrt(3.0)
	_check("Shared executor normalizes movement across all three axes",
		_has_velocity(diagonal, diagonal_axis, diagonal_axis, diagonal_axis))
	var invalid := bridge.invoke_behavior(player, &"move", &"calculate_velocity", {&"forward": 1.1})
	_check("Shared executor rejects intent outside the normalized range", not invalid["ok"])
	var enemy_id: int = host.entry.entity_ids.get(&"enemy", 0)
	var enemy := bridge.node_for(enemy_id)
	var player_body := player.get_node("View2D") as CharacterBody2D
	var enemy_body := enemy.get_node("View2D") as CharacterBody2D
	var player_profile := player_body.get("content") as Movement
	var enemy_profile := enemy_body.get("content") as Movement
	_check("Entities share the movement profile and Behavior", player_profile != null and enemy_profile != null
		and player_profile.resource_path == enemy_profile.resource_path
		and player_profile.movement_behavior.resource_path == enemy_profile.movement_behavior.resource_path)
	_check("Entities have separate controllers",
		player_body.get("controller").resource_path.ends_with("/player_keyboard.tres")
		and enemy_body.get("controller").resource_path.ends_with("/enemy_ai.tres"))

	var distance := enemy_body.global_position.distance_to(player_body.global_position)
	await _physics_steps()
	_check("Enemy approaches an eligible target while Player is idle", player_body.velocity == Vector2.ZERO
		and enemy_body.global_position.distance_to(player_body.global_position) < distance)
	_send_key(KEY_W, true)
	await _physics_steps()
	_check("W moves Player at 200 pixels per second", player_body.velocity.is_equal_approx(Vector2(0.0, -200.0)))
	_send_key(KEY_W, false)
	_send_key(KEY_RIGHT, true)
	await _physics_steps()
	_check("Right arrow also moves Player", player_body.velocity.is_equal_approx(Vector2(200.0, 0.0)))
	_send_key(KEY_RIGHT, false)
	await _physics_steps()
	_check("Release stops Player and the follow camera stays active", player_body.velocity == Vector2.ZERO
		and root.get_camera_2d() == player_body.get_node("FollowCamera"))

	enemy_body.global_position = player_body.global_position + Vector2(20.0, 0.0)
	await _physics_steps()
	_check("Enemy stops within its controller's authored distance", enemy_body.velocity == Vector2.ZERO)
	player_body.set_physics_process(false)
	bridge.unbind_entity(player_id)
	enemy_body.global_position += Vector2(200.0, 0.0)
	await _physics_steps()
	_check("Enemy idles after the last eligible target unbinds", enemy_body.velocity == Vector2.ZERO)

	host.stop()
	await process_frame
	print("[bridge-movement] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[bridge-movement] ", label, ": ", passed)
	_passed = _passed and passed


func _physics_steps() -> void:
	for frame in 3:
		await physics_frame


func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _has_velocity(report: Dictionary, lateral: float, forward: float, vertical: float = 0.0) -> bool:
	if not report["ok"]:
		return false
	for step: Dictionary in report["value"]["steps"]:
		if StringName(step["id"]) == &"calculate_velocity" and step["status"] == "executed":
			var velocity: Dictionary = step["result"]["value"]
			return (
				is_equal_approx(float(velocity[&"lateral"]), lateral)
				and is_equal_approx(float(velocity[&"forward"]), forward)
				and is_equal_approx(float(velocity[&"vertical"]), vertical)
			)
	return false
