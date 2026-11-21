extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/game_setup.gd"
)
const TargetPoint2D = preload(
	"res://Framework/Env/Targeting/target_point_2d.gd"
)
const TargetResolver2D = preload(
	"res://Framework/Env/Targeting/target_resolver_2d.gd"
)

var _entry := GameEntry.new()
var _world: Node
var _passed: bool = true


func _initialize() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	var started := _entry.start(EnvironmentSetup.new())
	if not started["ok"]:
		push_error(started["error"])
		quit(1)
		return

	_world = Node.new()
	root.add_child(_world)

	var bridge := _entry.world_bridge
	var actor_id: int = _entry.entity_ids[&"player"]
	var enemy_id: int = _entry.entity_ids[&"enemy"]
	var second_id: int = _entry.entity_ids[&"second_player"]

	var actor := _make_entity(&"player", Vector2.ZERO)
	var enemy := _make_entity(&"enemy", Vector2(80, 0))
	var second := _make_entity(&"second_player", Vector2(160, 0))

	var actor_bound := bridge.bind_entity(actor_id, actor)
	var enemy_bound := bridge.bind_entity(enemy_id, enemy)
	var second_bound := bridge.bind_entity(second_id, second)

	_expect("Fixture bindings succeed", (
		actor_bound["ok"]
		and enemy_bound["ok"]
		and second_bound["ok"]
	))

	var actor_result := TargetPoint2D.find_for(actor)
	var enemy_result := TargetPoint2D.find_for(enemy)
	var second_result := TargetPoint2D.find_for(second)

	var actor_point := actor_result["value"] as Node2D
	var enemy_point := enemy_result["value"] as Node2D
	var second_point := second_result["value"] as Node2D

	var actor_view := actor_point.get_parent() as Node2D
	var enemy_view := enemy_point.get_parent() as Node2D
	var second_view := second_point.get_parent() as Node2D

	_expect_target("Chooses nearest other entity root", actor, enemy)

	enemy_view.position = Vector2(240, 0)
	_expect_target("Moving target changes selection", actor, second)

	actor_view.position = Vector2(300, 0)
	_expect_target("Moving actor changes selection", actor, enemy)

	actor_view.position = Vector2.ZERO
	enemy_view.position = Vector2(80, 0)
	second_view.position = Vector2(-80, 0)

	var lower_id_node: Node = second if second_id < enemy_id else enemy
	_expect_target("Equal distances choose lower ID", actor, lower_id_node)

	second_point.set_meta(TargetPoint2D.TARGET_META, false)
	_expect_target("Disabled target point is skipped", actor, enemy)

	second_point.set_meta(TargetPoint2D.TARGET_META, true)
	bridge.unbind_entity(second_id)
	_expect_target("Unbound entity is excluded", actor, enemy)

	enemy.free()

	var empty := TargetResolver2D.nearest(bridge, actor)

	_expect("Freed candidate leaves no target", (
		not empty["ok"]
		and String(empty["error"]).contains("No targetable entity")
	))

	_expect("Freed binding is pruned",
		not bridge.bound_entity_ids().has(enemy_id))

	var rebound := bridge.bind_entity(second_id, second)
	_expect("New binding is accepted", rebound["ok"])
	_expect_target("New binding is discovered", actor, second)

	bridge.unbind_entity(actor_id)

	var rejected := TargetResolver2D.nearest(bridge, actor)

	_expect("Unbound actor is rejected", (
		not rejected["ok"]
		and String(rejected["error"]).contains("Actor node is not bound")
	))

	print("[nearest] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _make_entity(
	entity_key: StringName,
	at_position: Vector2
) -> Node:
	var entity := Node.new()
	entity.name = entity_key
	entity.set_meta(&"entity_key", entity_key)

	var view := Node2D.new()
	view.name = &"Representation"
	view.position = at_position
	entity.add_child(view)

	var point := Marker2D.new()
	point.name = &"InteractionPoint"
	point.set_meta(TargetPoint2D.TARGET_META, true)
	view.add_child(point)

	_world.add_child(entity)
	return entity


func _expect_target(
	description: String,
	actor: Node,
	expected: Node
) -> void:
	var result := TargetResolver2D.nearest(_entry.world_bridge, actor)

	_expect(description, (
		result["ok"]
		and result["value"] == expected
	))


func _expect(description: String, condition: bool) -> void:
	_passed = _passed and condition
	print("[nearest] %s: %s" % [description, condition])


func _finalize() -> void:
	_entry.stop()

	if is_instance_valid(_world):
		_world.free()

	_world = null