extends SceneTree

const Host = preload("res://Framework/Env/Host/game_host.gd")
const MapScene = preload("res://Diagnostics/Fixtures/Movement/Physics3D/physics_3d_map.tscn")
const Move = preload("res://Framework/Content/Gameplay/Profiles/Movement/Behavior/move.tres")
const Store = preload("res://Framework/Infrastructure/API/Persistence/session_store.gd")

var _host := Host.new()
var _passed := true
var _save_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := _host.start(root)
	var loaded := _host.maps.load_map(MapScene) if started["ok"] else started
	if _check("Native 3D map loads", loaded["ok"], loaded["error"]):
		if "--play" in OS.get_cmdline_user_args():
			var session_input := root.get_node("SessionInput")
			session_input.set_process_unhandled_input(false)
			session_input.set_process_input(false)
			print("[physics-3d] Preview ready. Use WASD or arrow keys. The orange body follows Player.")
			return
		await _exercise(loaded["value"])
	_host.stop()
	if not _save_path.is_empty() and FileAccess.file_exists(_save_path):
		_check("Temporary save removed", DirAccess.remove_absolute(_save_path) == OK)
	await process_frame
	print("[physics-3d] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _finalize() -> void:
	_host.stop()


func _exercise(map: Node3D) -> void:
	var player := map.get_node("Player/Body3D") as CharacterBody3D
	var enemy := map.get_node("Enemy/Body3D") as CharacterBody3D
	var invalid_restore := _host.maps.load_map(MapScene, {&"player": Vector2.ZERO})
	_check("A 2D position is rejected before replacing the current 3D map",
		not invalid_restore["ok"] and _host.maps.get_active_map() == map)
	_check("Both bodies use the same authored move Behavior", (
		player.get("content").movement_behavior.resource_path == Move.resource_path
		and enemy.get("content").movement_behavior.resource_path == Move.resource_path
	))
	var bridge := _host.entry.world_bridge
	var player_id: int = _host.entry.entity_ids[&"player"]
	var enemy_id: int = _host.entry.entity_ids[&"enemy"]
	var nearest := bridge.resolve_behavior_target(enemy_id, &"nearest")
	_check("3D targeting resolves the nearest marked entity", nearest["ok"] and nearest["value"] == player_id)
	var selected := bridge.select_behavior_target(player.get_parent(), enemy.get_parent())
	var target := bridge.resolve_behavior_target(player_id, &"selected")
	_check("3D targeting resolves a selected entity", selected["ok"] and target["ok"] and target["value"] == enemy_id)

	var origin := enemy.global_position
	Input.action_press(&"move_up")
	await _frames(8)
	_check("Forward intent moves along negative Z", player.velocity.is_equal_approx(Vector3(0, 0, -2)))
	_check("AI pursues its target in native 3D", enemy.global_position.x < origin.x)
	enemy.set_physics_process(false)
	enemy.velocity = Vector3.ZERO

	await _frames(65)
	Input.action_release(&"move_up")
	await _frames(3)
	var saved_position := map.to_local(player.global_position)
	_check("Native collision stops movement at the wall", saved_position.z < -0.9 and saved_position.z > -1.2)
	_check("Released keyboard action stops the driver", player.velocity.is_zero_approx())

	var capture := _host.maps.snapshot_map()
	if not _check("Session captures map-relative Vector3 positions", capture["ok"]
			and capture["value"].get("positions_3d", {}).get(&"player") == saved_position):
		return
	var name := Crypto.new().generate_random_bytes(16).hex_encode()
	_save_path = ProjectSettings.globalize_path("res://.godot/diagnostics/physics_3d_" + name + ".fws")
	if not _check("3D session saves to a temporary file", _host.save_session(_save_path)["ok"]):
		return
	var read := Store.load_file(_save_path)
	_check("Session codec retains Vector3 coordinates", read["ok"]
		and read["value"]["environment"]["map"]["positions_3d"][&"player"] == saved_position)
	_host.stop()
	var restored := _host.restore_session(root, _save_path)
	if not _check("The host reopens the saved 3D map", restored["ok"], restored["error"]):
		return
	var restored_map := _host.maps.get_active_map() as Node3D
	var restored_player := restored_map.get_node("Player/Body3D") as CharacterBody3D
	_check("3D body is restored to its saved position", restored_map.to_local(restored_player.global_position).is_equal_approx(saved_position))
	Input.action_press(&"move_left")
	await _frames(8)
	Input.action_release(&"move_left")
	_check("Movement resumes from the restored position", restored_map.to_local(restored_player.global_position).x < saved_position.x)


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame


func _check(label: String, passed: bool, detail: String = "") -> bool:
	print("[physics-3d] ", label, ": ", passed)
	if not passed and not detail.is_empty():
		print("[physics-3d] ", detail)
	_passed = _passed and passed
	return passed
