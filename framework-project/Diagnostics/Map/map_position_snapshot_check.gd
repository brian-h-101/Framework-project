extends SceneTree

const GameHost = preload(
	"res://Framework/Env/Host/game_host.gd"
)
const SpatialRoot2D = preload(
	"res://Framework/Content/Universal/Map/based/Spatial2D/spatial_root_2d.gd"
)
const SessionCodec = preload(
	"res://Framework/Infrastructure/API/Persistence/session_codec.gd"
)

var _host := GameHost.new()
var _passed: bool = true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_snapshot()
	_host.stop()

	await process_frame

	print("[map-snapshot] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_snapshot() -> void:
	var started := _host.start(root)
	if not _expect("Fresh host started", started["ok"]):
		return

	var map_root := _host.maps.get_active_map() as Node2D
	if not _expect("Active map is 2D", map_root != null):
		return

	var player_id: int = _host.entry.entity_ids[&"player"]
	var player_node := _host.entry.world_bridge.node_for(player_id)
	var discovered := SpatialRoot2D.find_for(player_node)

	if not _expect("Player spatial root found", (
		discovered["ok"] and discovered["value"] is Node2D
	)):
		return

	var body: Node2D = discovered["value"]
	var expected := Vector2(416, 392)
	body.global_position = map_root.to_global(expected)

	var captured := _host.maps.snapshot_map()
	if not _expect("Map snapshot captured", captured["ok"]):
		return

	var record: Dictionary = captured["value"]
	var positions: Dictionary = record["positions_2d"]
	var keys := positions.keys()

	_expect(
		"Scene path is preserved",
		record["scene_path"] == map_root.scene_file_path
	)
	_expect(
		"Positions use stable map entity keys",
		keys == [&"enemy", &"player"]
	)
	_expect(
		"Unbound startup entity is excluded",
		not positions.has(&"second_player")
	)

	if not _expect("Player position is available", positions.has(&"player")):
		return

	var player_position: Vector2 = positions[&"player"]
	_expect(
		"Snapshot contains the moved Player position",
		player_position.is_equal_approx(expected)
	)

	var session := _host.entry.snapshot_session()
	if not _expect("Session snapshot captured", session["ok"]):
		return

	var snapshot: Dictionary = session["value"]
	snapshot["environment"] = {"map": record}

	var encoded := SessionCodec.encode(snapshot)
	if not _expect("Snapshot with positions encodes", encoded["ok"]):
		return

	var decoded := SessionCodec.decode(encoded["value"])
	if not _expect("Snapshot with positions decodes", decoded["ok"]):
		return

	_expect(
		"Codec preserves the complete snapshot",
		decoded["value"] == snapshot
	)

	var later_position := expected + Vector2(16, 0)
	body.global_position = map_root.to_global(later_position)

	var retained_position: Vector2 = positions[&"player"]
	_expect(
		"Later movement leaves the captured position unchanged",
		retained_position.is_equal_approx(expected)
	)

	var latest := _host.maps.snapshot_map()
	if not _expect("Another map snapshot succeeds", latest["ok"]):
		return

	var latest_record: Dictionary = latest["value"]
	var latest_positions: Dictionary = latest_record["positions_2d"]
	var latest_player_position: Vector2 = latest_positions[&"player"]
	_expect(
		"New snapshot captures later movement",
		latest_player_position.is_equal_approx(later_position)
	)

	positions[&"player"] = Vector2.ZERO
	_expect(
		"Editing the snapshot leaves the live position unchanged",
		map_root.to_local(body.global_position).is_equal_approx(later_position)
	)


func _expect(description: String, condition: bool) -> bool:
	print("[map-snapshot] ", description, ": ", condition)
	_passed = _passed and condition
	return condition