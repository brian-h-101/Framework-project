extends SceneTree

const GameHost = preload(
	"res://Framework/Env/Host/game_host.gd"
)
const EntityStatusLayer2D = preload(
	"res://Framework/Env/Presentation/entity_status_layer_2d.gd"
)
const CheckMap = preload(
	"res://Games/ExampleGame/World/item_object_check.tscn"
)

var _host := GameHost.new()
var _passed: bool = true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_placements()
	_host.stop()

	await process_frame

	print("[item-object] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_placements() -> void:
	var started := _host.start(root)
	if not _expect("Fresh host started", started["ok"]):
		return

	var statuses := _host.ui.get_node(
		"Root/EntityStatuses"
	) as EntityStatusLayer2D
	if not _expect("Status layer exists", statuses != null):
		return

	var player_id: int = _host.entry.entity_ids[&"player"]
	var player_widget := statuses.widget_for(player_id)
	if not _expect("Existing Player status exists", is_instance_valid(player_widget)):
		return

	var player_health := player_widget.get_node("Health") as Label
	_expect("Existing health displays remain visible", (
		player_health.visible and not player_health.text.is_empty()
	))

	var loaded := _host.maps.load_map(CheckMap)
	if not _expect("Authored map loaded", loaded["ok"]):
		return

	if not _expect("Both placements enter the session lookup", (
		_host.entry.entity_ids.has(&"iron_sword_01")
		and _host.entry.entity_ids.has(&"wooden_chest_01")
	)):
		return

	var sword_id: int = _host.entry.entity_ids[&"iron_sword_01"]
	var chest_id: int = _host.entry.entity_ids[&"wooden_chest_01"]
	var runtime := _host.entry.runtime
	var bridge := _host.entry.world_bridge

	_expect("Placed nodes bind to their runtime instances", (
		bridge.node_for(sword_id) != null
		and bridge.node_for(chest_id) != null
		and runtime.definition_id_for(sword_id) == &"iron_sword"
		and runtime.definition_id_for(chest_id) == &"wooden_chest"
	))

	var sword_widget := statuses.widget_for(sword_id)
	var chest_widget := statuses.widget_for(chest_id)
	if not _expect("Both status widgets exist", (
		is_instance_valid(sword_widget)
		and is_instance_valid(chest_widget)
	)):
		return

	var sword_health := sword_widget.get_node("Health") as Label
	var chest_health := chest_widget.get_node("Health") as Label
	_expect("Absent optional health displays are hidden", (
		not sword_health.visible and not chest_health.visible
	))

	var sword_changed := runtime.write_attribute(
		sword_id, &"condition", ["current"], 60
	)
	var chest_changed := runtime.write_attribute(
		chest_id, &"access", ["locked"], false
	)
	_expect("Placed instance attributes are writable", (
		sword_changed["ok"] and chest_changed["ok"]
	))

	_host.maps.unload_map()
	_expect("Unloading clears bindings and preserves instances", (
		bridge.node_for(sword_id) == null
		and bridge.node_for(chest_id) == null
		and runtime.has_entity(sword_id)
		and runtime.has_entity(chest_id)
	))

	var reloaded := _host.maps.load_map(CheckMap)
	if not _expect("Authored map reloads", reloaded["ok"]):
		return

	_expect("Reload reuses the same runtime identities", (
		_host.entry.entity_ids[&"iron_sword_01"] == sword_id
		and _host.entry.entity_ids[&"wooden_chest_01"] == chest_id
		and bridge.node_for(sword_id) != null
		and bridge.node_for(chest_id) != null
	))

	var condition := runtime.read_attribute(
		sword_id, &"condition", ["current"]
	)
	var locked := runtime.read_attribute(
		chest_id, &"access", ["locked"]
	)
	_expect("Reload preserves the changed instance state", (
		condition["ok"] and condition["value"] == 60
		and locked["ok"] and locked["value"] == false
	))

	var captured := _host.entry.snapshot_session()
	_expect("Placements are included in session snapshots", (
		captured["ok"]
		and captured["value"]["entities"].has(&"iron_sword_01")
		and captured["value"]["entities"].has(&"wooden_chest_01")
	))

	var health_added := runtime.add_container(
		sword_id, &"health", {"current": 10, "maximum": 100}
	)
	_expect("Optional display appears when its data is added", (
		health_added["ok"]
		and sword_health.visible
		and sword_health.text == "Health: 10"
	))


func _expect(description: String, condition: bool) -> bool:
	print("[item-object] ", description, ": ", condition)
	_passed = _passed and condition
	return condition
