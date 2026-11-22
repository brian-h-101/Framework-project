extends SceneTree

const GameHost = preload("res://Framework/Env/Host/game_host.gd")
const GRID_SCENE = preload("res://Diagnostics/Fixtures/Movement/Grid/grid_map.tscn")
const SharedMovement = preload("res://Framework/Content/Gameplay/Profiles/Movement/Behavior/move.tres")
const PhysicsProfile = preload("res://Framework/Content/Gameplay/Profiles/Movement/Shared/movement_2d.tres")
const SessionCodec = preload("res://Framework/Infrastructure/API/Persistence/session_codec.gd")

var _passed := true
var _host := GameHost.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if _check("Host starts", _host.start(root)["ok"]):
		await _check_grid()
	_host.stop()
	await process_frame
	print("[grid-movement] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_grid() -> void:
	var loaded := _host.maps.load_map(GRID_SCENE)
	if not _check("Grid map loads into the session", loaded["ok"]):
		return
	var map: Node2D = loaded["value"]
	var player := map.get_node("Player/View2D") as CharacterBody2D
	var enemy := map.get_node("Enemy/View2D") as CharacterBody2D
	_check("Both environments use the same authored Behavior and executor", (
		player.content.movement_behavior.resource_path == SharedMovement.resource_path
		and enemy.content.movement_behavior.resource_path == SharedMovement.resource_path
		and PhysicsProfile.movement_behavior.resource_path == SharedMovement.resource_path
		and player.content.velocity_step()["executor_id"] == &"movement"
	))

	var bridge := _host.entry.world_bridge
	var enemy_id: int = _host.entry.entity_ids[&"enemy"]
	var player_id: int = _host.entry.entity_ids[&"player"]
	var target := bridge.resolve_behavior_target(enemy_id, &"nearest")
	_check("Nearest targeting uses the grid scene's registered entities", target["ok"] and target["value"] == player_id)
	var enemy_start := _position(map, enemy)
	await _frames(45)
	_check("AI follows its target in whole cells", _position(map, enemy).x < enemy_start.x
		and absf(fposmod(_position(map, enemy).x, 32.0)) < 0.001)

	_press(KEY_D, true)
	await _frames(24)
	_press(KEY_D, false)
	_check("The authored blocked cell prevents moving right", _position(map, player).is_equal_approx(Vector2(32, 32)))

	_press(KEY_A, true)
	await _frames(24)
	_press(KEY_A, false)
	_check("Keyboard moves one cell left and stops at the board edge", _position(map, player).is_equal_approx(Vector2(0, 32)))
	await _frames(12)
	_check("Released input leaves the grid position unchanged", _position(map, player).is_equal_approx(Vector2(0, 32)))

	var captured := _host.maps.snapshot_map()
	if not _check("Grid positions capture in map coordinates", captured["ok"]
			and captured["value"]["positions_2d"][&"player"] == Vector2(0, 32)):
		return
	var encoded := SessionCodec.encode({"entities": {}, "environment": {"map": captured["value"]}})
	if not _check("Grid map records can be saved", encoded["ok"]):
		return
	var decoded := SessionCodec.decode(encoded["value"])
	if not _check("Saved grid positions decode", decoded["ok"]):
		return
	var restored := _host.maps.load_map(GRID_SCENE, decoded["value"]["environment"]["map"]["positions_2d"])
	if not _check("Grid map reloads with saved positions", restored["ok"]):
		return
	map = restored["value"]
	player = map.get_node("Player/View2D")
	await _frames(3)
	_check("The restored cell is stable while idle", _position(map, player).is_equal_approx(Vector2(0, 32)))
	_press(KEY_W, true)
	await _frames(24)
	_press(KEY_W, false)
	_check("Movement resumes from the restored cell", _position(map, player).is_equal_approx(Vector2.ZERO))


func _position(map: Node2D, body: CharacterBody2D) -> Vector2:
	return map.to_local(body.global_position)


func _press(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(label: String, passed: bool) -> bool:
	print("[grid-movement] ", label, ": ", passed)
	_passed = _passed and passed
	return passed
