extends SceneTree

const GameHost = preload(
	"res://Framework/Env/Host/game_host.gd"
)
const CityMap = preload(
	"res://Games/ExampleGame/World/city.tscn"
)

var _host := GameHost.new()


func _initialize() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	var started := _host.start(root)
	if not started.ok:
		push_error(started.error)
		quit(1)
		return

	var runtime := _host.entry.runtime
	var player_id: int = _host.entry.entity_ids[&"player"]
	var bridge := _host.entry.world_bridge
	var initial_player := bridge.node_for(player_id)
	var initial_label := initial_player.get_node("View2D/Health") as Label

	print("[view] Initial text: ", initial_label.text)
	print("[map] Set player health: ",
		runtime.write_attribute(player_id, &"health", ["current"], 42))

	print("[view] After write: ", initial_label.text)

	var loaded := _host.maps.load_map(CityMap)
	print("[map] Load: ", loaded)

	if not loaded.ok:
		push_error(loaded.error)
		quit(1)
		return

	var map_node: Node = loaded.value
	var player_node := map_node.get_node("Player")
	var health_label := player_node.get_node("View2D/Health") as Label

	print("[entity] Player root type: ", player_node.get_class())
	print("[entity] Enemy root type: ", map_node.get_node("Enemy").get_class())

	print("[view] After reload: ", health_label.text)
	print("[view] Listeners after reload: ",
		bridge.attribute_written.get_connections().size())

	print("[map] Player binding correct: ",
		_host.entry.world_bridge.entity_for(player_node) == player_id)

	print("[map] Health through player node: ",
		_host.entry.world_bridge.read_attribute(
			player_node, &"health", ["current"]
		))

	print("[map] Attached to root: ",
		map_node.get_parent() == root)

	print("[map] Inside scene tree: ",
		map_node.is_inside_tree())

	await process_frame

	var input_event := InputEventAction.new()
	input_event.action = &"primary_interaction"
	input_event.pressed = true
	root.push_input(input_event)

	var enemy_node := map_node.get_node("Enemy")

	print("[controls] Enemy health after configured input: ",
		bridge.read_attribute(enemy_node, &"health", ["current"]))

	input_event.pressed = false
	root.push_input(input_event)

	_host.maps.unload_map()
	print("[view] Listeners after unload: ",
		bridge.attribute_written.get_connections().size())
	print("[map] Player binding cleared: ",
		_host.entry.world_bridge.node_for(player_id) == null)
	print("[map] Active map cleared: ",
		_host.maps.get_active_map() == null)

	print("[map] Map detached: ",
		map_node.get_parent() == null)

	await process_frame

	print("[map] Map node freed: ",
		not is_instance_valid(map_node))

	print("[map] Same runtime: ",
		_host.entry.runtime == runtime)

	print("[map] Player still exists: ",
		runtime.has_entity(player_id))

	print("[map] Player health after unload: ",
		runtime.read_attribute(player_id, &"health", ["current"]))

	quit()


func _finalize() -> void:
	_host.stop()
