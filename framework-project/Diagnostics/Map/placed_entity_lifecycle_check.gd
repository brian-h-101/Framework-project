extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/Bootstrap/game_setup.gd"
)
const MapCoordinator = preload(
	"res://Framework/Env/Map/map_coordinator.gd"
)
const GuardScene = preload(
	"res://Framework/Content/Gameplay/Presentation/Entity/TownGuard/town_guard_2d.tscn"
)

var _entry := GameEntry.new()
var _maps: MapCoordinator
var _passed: bool = true


func _initialize() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	var started := _entry.start(EnvironmentSetup.new())
	if not started["ok"]:
		push_error(String(started["error"]))
		quit(1)
		return

	var controls: Dictionary[StringName, Dictionary] = {}
	_maps = MapCoordinator.new(
		root, _entry.world_bridge, _entry.entity_ids, controls, _entry.runtime
	)

	var initial_count := _entry.entity_ids.size()
	var original_map := _make_map([&"town_guard_01", &"town_guard_02"])
	var loaded := _maps.load_map(original_map)

	if not loaded["ok"]:
		push_error(String(loaded["error"]))
		quit(1)
		return

	var first_id: int = _entry.entity_ids[&"town_guard_01"]
	var second_id: int = _entry.entity_ids[&"town_guard_02"]
	var first_node := _entry.world_bridge.node_for(first_id)

	_expect("Placements enter the session lookup", (
		_entry.entity_ids.size() == initial_count + 2
		and first_id > 0
		and second_id > 0
		and first_id != second_id
	))

	var written := _entry.runtime.write_attribute(
		first_id, &"health", ["current"], 42
	)
	_expect("First guard health changes", written["ok"] and written["value"] == 42)

	var second_health := _entry.runtime.read_attribute(
		second_id, &"health", ["current"]
	)
	_expect("Second guard has independent health", (
		second_health["ok"] and second_health["value"] == 100
	))

	_maps.unload_map()

	_expect("Unload clears bindings and preserves entities", (
		_entry.world_bridge.node_for(first_id) == null
		and _entry.world_bridge.node_for(second_id) == null
		and _entry.runtime.has_entity(first_id)
		and _entry.runtime.has_entity(second_id)
	))

	await process_frame
	_expect("Previous world node is freed", not is_instance_valid(first_node))

	var other_map := _make_map([&"town_guard_01"])
	var changed_map := _maps.load_map(other_map)
	if not changed_map["ok"]:
		push_error(String(changed_map["error"]))
		quit(1)
		return

	var restored_health := _entry.runtime.read_attribute(
		first_id, &"health", ["current"]
	)
	_expect("Another map reuses the same individual", (
		_entry.entity_ids[&"town_guard_01"] == first_id
		and _entry.world_bridge.node_for(first_id) != null
		and restored_health["ok"]
		and restored_health["value"] == 42
	))

	_expect("Absent guard remains in the session", (
		_entry.entity_ids[&"town_guard_02"] == second_id
		and _entry.runtime.has_entity(second_id)
		and _entry.world_bridge.node_for(second_id) == null
	))

	var returned := _maps.load_map(original_map)
	_expect("Returning to the original map reuses both IDs", (
		returned["ok"]
		and _entry.entity_ids[&"town_guard_01"] == first_id
		and _entry.entity_ids[&"town_guard_02"] == second_id
		and _entry.world_bridge.node_for(first_id) != null
		and _entry.world_bridge.node_for(second_id) != null
		and _entry.entity_ids.size() == initial_count + 2
	))

	_expect_rejected(
		"Duplicate keys preserve the active map",
		_make_map([&"duplicate_guard", &"duplicate_guard"]),
		"Duplicate map entity key"
	)
	_expect_rejected(
		"Unknown definitions preserve the active map",
		_make_map([&"unknown_guard"], &"missing_definition"),
		"Unknown entity definition"
	)
	_expect_rejected(
		"Changing a persistent key's definition is rejected",
		_make_map([&"town_guard_01"], &"enemy"),
		"different definition"
	)

	_maps.unload_map()
	await process_frame
	_entry.stop()

	print("[placement] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _make_map(
	keys: Array,
	definition_id: StringName = &"town_guard"
) -> PackedScene:
	var map_root := Node2D.new()
	map_root.name = &"PlacementCheck"

	for index in keys.size():
		var guard := GuardScene.instantiate() as Node2D
		guard.name = StringName(keys[index])
		guard.position = Vector2(80 * index, 0)
		guard.set_meta(&"entity_key", StringName(keys[index]))
		guard.set_meta(&"entity_definition", definition_id)
		map_root.add_child(guard)
		guard.owner = map_root

	var packed := PackedScene.new()
	var error := packed.pack(map_root)
	map_root.free()

	if error != OK:
		push_error("Could not build diagnostic map: %s" % error_string(error))
		return null

	return packed


func _expect_rejected(
	description: String,
	scene: PackedScene,
	error_fragment: String
) -> void:
	var previous_map := _maps.get_active_map()
	var previous_count := _entry.entity_ids.size()
	var previous_bindings := _entry.world_bridge.bound_entity_ids()
	var result := _maps.load_map(scene)

	_expect(description, (
		not result["ok"]
		and String(result["error"]).contains(error_fragment)
		and _maps.get_active_map() == previous_map
		and _entry.entity_ids.size() == previous_count
		and _entry.world_bridge.bound_entity_ids() == previous_bindings
	))


func _expect(description: String, condition: bool) -> void:
	_passed = _passed and condition
	print("[placement] %s: %s" % [description, condition])


func _finalize() -> void:
	if _maps != null:
		_maps.unload_map()
	_entry.stop()
