extends SceneTree

const GameHost = preload(
	"res://Framework/Env/Host/game_host.gd"
)
const CityMap = preload(
	"res://Framework/Content/Maps/city.tscn"
)
const EntityStatusLayer2D = preload(
	"res://Framework/Content/God/UI/entity_status_layer_2d.gd"
)
const UIAnchor2D = preload(
	"res://Framework/Env/Presentation/ui_anchor_2d.gd"
)
const TargetPoint2D = preload(
	"res://Framework/Env/Targeting/target_point_2d.gd"
)
var _host := GameHost.new()
var _bound_events: Array[int] = []
var _unbound_events: Array[int] = []


func _initialize() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	var started := _host.start(root)
	if not started.ok:
		push_error(started.error)
		quit(1)
		return

	var fixture_loaded := _host.maps.load_map(CityMap)
	if not fixture_loaded["ok"]:
		push_error(String(fixture_loaded["error"]))
		quit(1)
		return

	print("[fixture] Original City loaded: ", fixture_loaded["ok"])

	var ui := _host.ui
	var initial_map := _host.maps.get_active_map() as CanvasItem
	var separate_canvas: bool = ui.get_canvas() != initial_map.get_canvas()
	print("[ui] Separate canvas: ", separate_canvas)

	var ui_surface := ui.get_node("Root") as Control
	var ui_material := ui_surface.material as CanvasItemMaterial
	var unshaded: bool = (
		ui_material != null
		and ui_material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED
	)
	print("[ui] Unshaded root material: ", unshaded)

	var runtime := _host.entry.runtime
	var player_id: int = _host.entry.entity_ids[&"player"]
	var bridge := _host.entry.world_bridge
	bridge.entity_bound.connect(_on_entity_bound)
	bridge.entity_unbound.connect(_on_entity_unbound)

	var initial_bound_ids := bridge.bound_entity_ids()
	print("[binding] Existing IDs: ", initial_bound_ids)

	var statuses := ui.get_node("Root/EntityStatuses") as EntityStatusLayer2D
	var expected_widget_count: int = initial_bound_ids.size()
	var initial_widgets_match: bool = (
		statuses.get_child_count() == expected_widget_count
	)

	for entity_id in initial_bound_ids:
		initial_widgets_match = (
			initial_widgets_match
			and is_instance_valid(statuses.widget_for(entity_id))
		)

	var initial_listener_count: int = (
		runtime.attribute_written.get_connections().size()
	)

	print("[auto-ui] Initial widgets match bindings: ", initial_widgets_match)
	print("[view] Initial listeners: ", initial_listener_count)
	var player_status := statuses.widget_for(player_id)
	var initial_label := player_status.get_node("Health") as Label

	print("[view] Initial text: ", initial_label.text)
	print("[map] Set player health: ",
		runtime.write_attribute(player_id, &"health", ["current"], 42))

	print("[view] After write: ", initial_label.text)
	var health_updates: bool = initial_label.text == "Health: 42"

	var loaded := _host.maps.load_map(CityMap)
	print("[map] Load: ", loaded)

	if not loaded.ok:
		push_error(loaded.error)
		quit(1)
		return

	_bound_events.sort()
	_unbound_events.sort()
	var binding_events_ok: bool = (
		_bound_events == initial_bound_ids
		and _unbound_events == initial_bound_ids
	)
	print("[binding] Reload notifications correct: ", binding_events_ok)

	var same_ui: bool = _host.ui == ui
	print("[ui] Same instance after reload: ", same_ui)

	var map_node: Node = loaded.value
	var player_node := map_node.get_node("Player")
	var health_label := statuses.widget_for(player_id).get_node("Health") as Label
	var same_label: bool = health_label == initial_label
	var no_map_labels: bool = map_node.find_children("*", "Label", true, false).is_empty()
	print("[ui] Same health label after reload: ", same_label)
	print("[ui] Map contains no labels: ", no_map_labels)

	print("[entity] Player root type: ", player_node.get_class())
	print("[entity] Enemy root type: ", map_node.get_node("Enemy").get_class())

	print("[view] After reload: ", health_label.text)
	var health_survives_reload: bool = health_label.text == "Health: 42"
	var listeners_after_reload: int = runtime.attribute_written.get_connections().size()
	print("[view] Listeners after reload: ",
		listeners_after_reload)

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

	var player_view := player_node.get_node("View2D") as Node2D
	var player_anchor_result := UIAnchor2D.find_for(player_node)

	if not player_anchor_result["ok"]:
		push_error(String(player_anchor_result["error"]))
		quit(1)
		return

	var player_anchor := player_anchor_result["value"] as Node2D

	player_view.name = &"RenamedPresentation"
	player_anchor.name = &"IndependentLabelPoint"

	var anchor_rig := Node2D.new()
	anchor_rig.name = &"MarkerRig"
	player_view.add_child(anchor_rig)

	player_anchor.get_parent().remove_child(player_anchor)
	anchor_rig.add_child(player_anchor)

	await process_frame
	await process_frame

	var status_parent := player_status.get_parent() as CanvasItem
	var expected_status_position := status_parent.make_canvas_position_local(
		player_anchor.get_global_transform_with_canvas().origin
		+ player_status.screen_offset
	)

	var uses_role_anchor: bool = (
		player_status.visible
		and player_status.position.is_equal_approx(expected_status_position)
	)
	print("[anchor] Renamed hierarchy tracks marker: ", uses_role_anchor)

	var previous_status_position := player_status.position
	var anchor_shift := Vector2(12, -18)
	player_anchor.position += anchor_shift

	await process_frame
	await process_frame

	var follows_anchor_offset: bool = (
		player_status.visible
		and player_status.position.is_equal_approx(
			previous_status_position + anchor_shift
		)
	)
	print("[anchor] Moving marker moves labels: ", follows_anchor_offset)

	var camera := player_view.get_node_or_null("FollowCamera") as Camera2D
	var movement := Vector2(40, 15)
	player_view.position += movement

	await process_frame
	await process_frame

	expected_status_position = status_parent.make_canvas_position_local(
		player_anchor.get_global_transform_with_canvas().origin
		+ player_status.screen_offset
	)

	var follows_movement: bool = (
		player_status.visible
		and player_status.position.is_equal_approx(expected_status_position)
	)
	print("[ui] Labels follow reloaded entity: ", follows_movement)

	var camera_follows: bool = (
		camera != null
		and camera.is_current()
		and camera.get_screen_center_position().is_equal_approx(
			player_view.global_position
		)
	)
	print("[camera] Player remains centered: ", camera_follows)

	var enemy_id: int = _host.entry.entity_ids[&"enemy"]
	var enemy_node := map_node.get_node("Enemy")
	enemy_node.name = &"RenamedTarget"

	var disabled_points: Array[Node2D] = []
	for entity_id in bridge.bound_entity_ids():
		if entity_id == player_id or entity_id == enemy_id:
			continue

		var point_result := TargetPoint2D.find_for(bridge.node_for(entity_id))
		if point_result["ok"]:
			var point := point_result["value"] as Node2D
			point.set_meta(TargetPoint2D.TARGET_META, false)
			disabled_points.append(point)

	var input_event := InputEventAction.new()
	input_event.action = &"primary_interaction"
	input_event.pressed = true
	root.push_input(input_event)

	print("[controls] Enemy health after configured input: ",
		bridge.read_attribute(enemy_node, &"health", ["current"]))
	var enemy_label := statuses.widget_for(enemy_id).get_node("Health") as Label
	var interaction_updates_ui: bool = enemy_label.text == "Health: 90"
	print("[ui] Interaction updates enemy label: ", interaction_updates_ui)

	input_event.pressed = false
	root.push_input(input_event)

	for disabled_point in disabled_points:
		disabled_point.set_meta(TargetPoint2D.TARGET_META, true)

	_host.maps.unload_map()
	var bindings_cleared: bool = bridge.bound_entity_ids().is_empty()
	print("[binding] Bindings cleared on unload: ", bindings_cleared)

	var listeners_after_unload: int = runtime.attribute_written.get_connections().size()
	print("[view] Listeners after unload: ",
		listeners_after_unload)
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

	var survived_unload: bool = (
		is_instance_valid(ui)
		and ui.get_parent() == root
	)
	print("[ui] Parent survived unload: ", survived_unload)

	var hidden_without_map: bool = not player_status.visible
	var written_without_map := runtime.write_attribute(
		player_id,
		&"health",
		["current"],
		41
	)
	var updated_without_map: bool = (
		written_without_map.ok
		and health_label.text == "Health: 41"
	)
	print("[ui] Floating labels hidden without map: ", hidden_without_map)
	print("[ui] Health updates without map: ", updated_without_map)

	var restored := _host.maps.load_map(CityMap)
	if not restored.ok:
		push_error(restored.error)
		quit(1)
		return

	await process_frame
	await process_frame

	var reappears: bool = (
		_host.ui == ui
		and player_status.visible
		and health_label.text == "Health: 41"
	)
	print("[ui] Labels reappear after map returns: ", reappears)

	var no_duplicate_widgets: bool = (
		statuses.get_child_count() == expected_widget_count
	)
	print("[auto-ui] Reload preserves widget count: ", no_duplicate_widgets)

	var placed_guard_ok: bool = await _check_placed_guard()

	var extra_id: int = _host.entry.entity_ids[&"second_player"]
	var extra_entity := Node.new()
	var extra_view := Node2D.new()
	var extra_anchor := Marker2D.new()

	extra_view.name = &"DifferentPresentation"
	extra_view.position = Vector2(480, 240)

	extra_anchor.name = &"StatusPoint"
	extra_anchor.set_meta(UIAnchor2D.ROLE_META, &"status")

	extra_view.add_child(extra_anchor)
	extra_entity.add_child(extra_view)
	root.add_child(extra_entity)

	var extra_bound := bridge.bind_entity(extra_id, extra_entity)
	var extra_widget := statuses.widget_for(extra_id)

	await process_frame
	await process_frame

	var discovers_new_binding: bool = (
		extra_bound.ok
		and is_instance_valid(extra_widget)
		and extra_widget.visible
		and statuses.get_child_count() == expected_widget_count + 1
	)
	print("[auto-ui] New binding creates a widget: ", discovers_new_binding)

	bridge.unbind_entity(extra_id)
	var hides_unbound_widget: bool = (
		is_instance_valid(extra_widget)
		and not extra_widget.visible
	)
	print("[auto-ui] Unbinding hides its widget: ", hides_unbound_widget)

	extra_entity.free()

	_host.stop()
	var layer_disconnected: bool = (
		bridge.entity_bound.get_connections().size() == 1
		and bridge.entity_unbound.get_connections().size() == 1
	)
	print("[auto-ui] Layer disconnects on session stop: ", layer_disconnected)

	var listeners_cleared: bool = runtime.attribute_written.get_connections().is_empty()
	print("[view] Listeners after session stop: ",
		runtime.attribute_written.get_connections().size())
	var detached_on_stop: bool = (
		_host.ui == null
		and ui.get_parent() == null
	)
	print("[ui] Parent detached on stop: ", detached_on_stop)

	await process_frame

	var freed_on_stop: bool = not is_instance_valid(ui)
	print("[ui] Parent freed on stop: ", freed_on_stop)

	var passed: bool = (
		separate_canvas
		and unshaded
		and same_ui
		and binding_events_ok
		and bindings_cleared
		and same_label
		and no_map_labels
		and health_updates
		and health_survives_reload
		and initial_widgets_match
		and listeners_after_reload == initial_listener_count
		and listeners_after_unload == initial_listener_count
		and uses_role_anchor
		and follows_anchor_offset
		and follows_movement
		and camera_follows
		and interaction_updates_ui
		and survived_unload
		and hidden_without_map
		and updated_without_map
		and reappears
		and no_duplicate_widgets
		and placed_guard_ok
		and discovers_new_binding
		and hides_unbound_widget
		and layer_disconnected
		and listeners_cleared
		and detached_on_stop
		and freed_on_stop
	)
	print("[ui] Checks passed: ", passed)

	if not passed:
		push_error("Persistent UI lifecycle check failed.")

	quit(0 if passed else 1)


func _check_placed_guard() -> bool:
	var entity_key: StringName = &"town_guard_01"
	var runtime := _host.entry.runtime
	var bridge := _host.entry.world_bridge
	var statuses := (
		_host.ui.get_node("Root/EntityStatuses") as EntityStatusLayer2D
	)

	var guard_id: int = _host.entry.entity_ids.get(entity_key, 0)
	var guard_node := bridge.node_for(guard_id)
	var guard_widget := statuses.widget_for(guard_id)

	var guard_ready: bool = (
		runtime.has_entity(guard_id)
		and runtime.definition_id_for(guard_id) == &"town_guard"
		and is_instance_valid(guard_node)
		and guard_node.get_meta(&"entity_key", &"") == entity_key
		and is_instance_valid(guard_widget)
	)
	print("[placement] Guard binding and widget: ", guard_ready)

	if not guard_ready:
		push_error("City must contain a bound town_guard_01 placement and widget.")
		return false

	var guard_label := guard_widget.get_node_or_null("Health") as Label
	if guard_label == null:
		push_error("TownGuard's widget is missing its Health label.")
		return false

	var original_node_id: int = guard_node.get_instance_id()
	var widget_count_before: int = statuses.get_child_count()
	var listener_count_before: int = (
		runtime.attribute_written.get_connections().size()
	)

	var written := runtime.write_attribute(
		guard_id,
		&"health",
		["current"],
		63
	)
	var health_updates: bool = (
		written["ok"]
		and guard_label.text == "Health: 63"
	)
	print("[placement] Guard health updates: ", health_updates)

	_host.maps.unload_map()
	await process_frame

	var unloaded_health := runtime.read_attribute(
		guard_id,
		&"health",
		["current"]
	)
	var survives_unload: bool = (
		not is_instance_valid(guard_node)
		and runtime.has_entity(guard_id)
		and _host.entry.entity_ids.get(entity_key, 0) == guard_id
		and bridge.node_for(guard_id) == null
		and unloaded_health["ok"]
		and unloaded_health["value"] == 63
		and is_instance_valid(guard_widget)
		and not guard_widget.visible
	)
	print("[placement] Guard state survives unload: ", survives_unload)

	var restored := _host.maps.load_map(CityMap)
	if not restored["ok"]:
		push_error(String(restored["error"]))
		return false

	await process_frame
	await process_frame

	var restored_node := bridge.node_for(guard_id)
	var restored_health := runtime.read_attribute(
		guard_id,
		&"health",
		["current"]
	)

	var same_identity: bool = (
		_host.entry.entity_ids.get(entity_key, 0) == guard_id
		and is_instance_valid(restored_node)
		and bridge.entity_for(restored_node) == guard_id
		and restored_node.get_instance_id() != original_node_id
	)
	print("[placement] Guard runtime identity retained: ", same_identity)

	var health_retained: bool = (
		restored_health["ok"]
		and restored_health["value"] == 63
	)
	print("[placement] Guard health survives reload: ", health_retained)

	var same_widget: bool = (
		is_instance_valid(guard_widget)
		and statuses.widget_for(guard_id) == guard_widget
		and is_instance_valid(guard_label)
		and guard_widget.get_node("Health") == guard_label
		and guard_label.text == "Health: 63"
		and guard_widget.visible
	)
	print("[placement] Guard widget reused: ", same_widget)

	var counts_stable: bool = (
		statuses.get_child_count() == widget_count_before
		and runtime.attribute_written.get_connections().size()
			== listener_count_before
	)
	print("[placement] Guard widget and listener counts stable: ", counts_stable)

	return (
		guard_ready
		and health_updates
		and survives_unload
		and same_identity
		and health_retained
		and same_widget
		and counts_stable
	)


func _finalize() -> void:
	_host.stop()


func _on_entity_bound(entity_id: int, _world_node: Node) -> void:
	_bound_events.append(entity_id)


func _on_entity_unbound(entity_id: int) -> void:
	_unbound_events.append(entity_id)
