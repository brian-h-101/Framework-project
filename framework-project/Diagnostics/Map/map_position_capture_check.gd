extends SceneTree

const SpatialRoot2D = preload(
	"res://Framework/Content/Universal/Map/based/Spatial2D/spatial_root_2d.gd"
)

var _passed: bool = true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var map_root := Node2D.new()
	map_root.position = Vector2(100, 50)
	map_root.rotation = 0.4
	map_root.scale = Vector2(1.5, 0.75)

	var entity := Node2D.new()
	entity.set_meta(&"entity_key", &"player")
	entity.position = Vector2(20, 30)
	map_root.add_child(entity)

	var body := CharacterBody2D.new()
	body.set_meta(SpatialRoot2D.ROOT_META, true)
	body.position = Vector2(4, 8)
	entity.add_child(body)

	var before_entry := SpatialRoot2D.capture_position(entity, map_root)
	_expect("Capture waits for scene-tree entry", not before_entry["ok"])

	root.add_child(map_root)

	_expect_position(
		"Captures placement plus body offset",
		entity,
		map_root,
		Vector2(24, 38)
	)

	body.position += Vector2(12, -6)

	_expect_position(
		"Captures the moving body",
		entity,
		map_root,
		Vector2(36, 32)
	)
	_expect(
		"Outer entity placement stays unchanged",
		entity.position == Vector2(20, 30)
	)

	map_root.position = Vector2(-40, 80)
	map_root.rotation = -0.25
	map_root.scale = Vector2(0.8, 1.2)

	_expect_position(
		"Map transforms leave map-relative position unchanged",
		entity,
		map_root,
		Vector2(36, 32)
	)

	var restored_position := Vector2(60, 45)
	var restored := SpatialRoot2D.restore_position(
		entity,
		map_root,
		restored_position
	)
	_expect("Position restoration succeeds", restored["ok"])

	_expect_position(
		"Restores position within a transformed map",
		entity,
		map_root,
		restored_position
	)
	_expect(
		"Restoration preserves the outer entity placement",
		entity.position == Vector2(20, 30)
	)

	var rejected := SpatialRoot2D.restore_position(
		entity,
		map_root,
		Vector2(INF, 0)
	)
	_expect("Non-finite saved position is rejected", not rejected["ok"])

	_expect_position(
		"Rejected restoration preserves the current position",
		entity,
		map_root,
		restored_position
	)

	var neutral_entity := Node.new()
	neutral_entity.set_meta(&"entity_key", &"enemy")
	map_root.add_child(neutral_entity)

	var neutral_body := Node2D.new()
	neutral_body.set_meta(SpatialRoot2D.ROOT_META, true)
	neutral_entity.add_child(neutral_body)
	neutral_body.global_position = map_root.to_global(Vector2(-12, 7))

	_expect_position(
		"Supports an entity with a plain Node root",
		neutral_entity,
		map_root,
		Vector2(-12, 7)
	)

	var neutral_restored := SpatialRoot2D.restore_position(
		neutral_entity,
		map_root,
		Vector2(8, 11)
	)
	_expect(
		"Restores an entity with a plain Node root",
		neutral_restored["ok"]
	)

	_expect_position(
		"Plain Node entity receives the requested map position",
		neutral_entity,
		map_root,
		Vector2(8, 11)
	)

	var logical_entity := Node.new()
	map_root.add_child(logical_entity)

	var logical := SpatialRoot2D.capture_position(logical_entity, map_root)
	_expect(
		"Entity without a spatial root needs no position",
		logical["ok"] and logical["value"] == null
	)

	var logical_restore := SpatialRoot2D.restore_position(
		logical_entity,
		map_root,
		Vector2.ZERO
	)
	_expect(
		"Restoration requires a designated spatial root",
		not logical_restore["ok"]
	)

	var outside_entity := Node2D.new()
	outside_entity.set_meta(SpatialRoot2D.ROOT_META, true)
	root.add_child(outside_entity)

	var outside := SpatialRoot2D.capture_position(outside_entity, map_root)
	_expect("Entity outside this map is rejected", not outside["ok"])

	outside_entity.free()
	map_root.free()

	print("[position-capture] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _expect_position(
	description: String,
	entity: Node,
	map_root: Node2D,
	expected: Vector2
) -> void:
	var captured := SpatialRoot2D.capture_position(entity, map_root)
	var matches: bool = false

	if captured["ok"] and typeof(captured["value"]) == TYPE_VECTOR2:
		var actual: Vector2 = captured["value"]
		matches = actual.is_equal_approx(expected)

	_expect(description, matches)


func _expect(description: String, condition: bool) -> void:
	print("[position-capture] ", description, ": ", condition)
	_passed = _passed and condition