extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/Bootstrap/game_setup.gd"
)

var _entry := GameEntry.new()
var _bound_events: Array[int] = []
var _unbound_events: Array[int] = []
var _passed: bool = true


func _initialize() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	var started := _entry.start(EnvironmentSetup.new())
	if not started.ok:
		push_error(started.error)
		quit(1)
		return

	var bridge := _entry.world_bridge
	var player_id: int = _entry.entity_ids[&"player"]
	var enemy_id: int = _entry.entity_ids[&"enemy"]
	var expected_ids: Array[int] = [player_id, enemy_id]
	expected_ids.sort()

	bridge.entity_bound.connect(_on_entity_bound)
	bridge.entity_unbound.connect(_on_entity_unbound)

	var player_node := Node2D.new()
	var enemy_node := Node3D.new()
	var player_bound := bridge.bind_entity(player_id, player_node)
	var enemy_bound := bridge.bind_entity(enemy_id, enemy_node)
	_expect("Live bindings discovered", (
		player_bound.ok
		and enemy_bound.ok
		and bridge.bound_entity_ids() == expected_ids
	))
	_expect("Successful binds notify once", (
		_bound_events.size() == 2
		and _bound_events.count(player_id) == 1
		and _bound_events.count(enemy_id) == 1
	))

	var snapshot := bridge.bound_entity_ids()
	snapshot.clear()
	_expect("Snapshot mutation leaves bindings intact",
		bridge.bound_entity_ids() == expected_ids)

	var duplicate := bridge.bind_entity(player_id, enemy_node)
	_expect("Rejected bind emits no notification", (
		not duplicate.ok
		and _bound_events.size() == 2
	))

	var removed := bridge.unbind_entity(player_id)
	var removed_again := bridge.unbind_entity(player_id)
	_expect("Explicit unbind notifies once", (
		removed
		and not removed_again
		and _unbound_events.size() == 1
		and _unbound_events[0] == player_id
	))

	var rebound := bridge.bind_entity(player_id, player_node)
	_expect("Rebinding publishes a new notification", (
		rebound.ok
		and _bound_events.size() == 3
		and _bound_events.count(player_id) == 2
	))

	if is_instance_valid(player_node):
		player_node.free()

	var after_free := bridge.bound_entity_ids()
	_expect("Freed node excluded from discovery", (
		after_free.size() == 1
		and after_free.has(enemy_id)
	))
	_expect("Expired binding notifies removal once", (
		_unbound_events.size() == 2
		and _unbound_events.count(player_id) == 2
	))

	bridge.bound_entity_ids()
	_expect("Repeated lookup emits no duplicate removal", (
		bridge.node_for(player_id) == null
		and _unbound_events.size() == 2
	))

	bridge.close()
	bridge.close()
	_expect("Close forwards remaining removal once", (
		_unbound_events.size() == 3
		and _unbound_events.count(enemy_id) == 1
	))
	_expect("Closed bridge has no discoverable bindings", (
		bridge.bound_entity_ids().is_empty()
		and bridge.node_for(enemy_id) == null
		and bridge.entity_for(enemy_node) == 0
	))
	_expect("Closing bridge preserves the world node",
		is_instance_valid(enemy_node))
	_expect("Closing bridge preserves runtime entities", (
		_entry.runtime.has_entity(player_id)
		and _entry.runtime.has_entity(enemy_id)
	))

	var rejected_after_close := bridge.bind_entity(enemy_id, enemy_node)
	_expect("Closed bridge rejects new bindings", (
		not rejected_after_close.ok
		and _bound_events.size() == 3
	))

	if is_instance_valid(enemy_node):
		enemy_node.free()

	_entry.stop()
	print("[binding-check] Checks passed: ", _passed)
	if not _passed:
		push_error("World bridge binding check failed.")

	quit(0 if _passed else 1)


func _expect(description: String, condition: bool) -> void:
	_passed = _passed and condition
	print("[binding-check] %s: %s" % [description, condition])


func _on_entity_bound(entity_id: int, _world_node: Node) -> void:
	_bound_events.append(entity_id)


func _on_entity_unbound(entity_id: int) -> void:
	_unbound_events.append(entity_id)


func _finalize() -> void:
	_entry.stop()
