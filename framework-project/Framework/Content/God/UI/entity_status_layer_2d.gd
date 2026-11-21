extends Control

const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)
const EntityStatus2D = preload(
	"res://Framework/Content/God/UI/entity_status_2d.gd"
)

@export var status_scene: PackedScene

var _runtime: GameRuntime
var _bridge: WorldBridge
var _displays: Dictionary[StringName, Dictionary] = {}
var _widgets: Dictionary[int, EntityStatus2D] = {}


func configure_session(
	runtime: GameRuntime,
	bridge: WorldBridge,
	_entity_ids: Dictionary[StringName, int],
	displays: Dictionary[StringName, Dictionary]
) -> void:
	_runtime = runtime
	_bridge = bridge
	_displays = displays


func _ready() -> void:
	if status_scene == null or _runtime == null or _bridge == null:
		push_error("Entity status layer has no scene or session context.")
		return

	_bridge.entity_bound.connect(_on_entity_bound)
	_bridge.entity_unbound.connect(_on_entity_unbound)

	for entity_id in _bridge.bound_entity_ids():
		_ensure_widget(entity_id)


func widget_for(entity_id: int) -> EntityStatus2D:
	return _widgets.get(entity_id)


func _ensure_widget(entity_id: int) -> void:
	if is_instance_valid(widget_for(entity_id)):
		return

	var instance := status_scene.instantiate()
	var widget := instance as EntityStatus2D

	if widget == null:
		if is_instance_valid(instance):
			instance.free()

		push_error("Status scene must use entity_status_2d.gd.")
		return

	widget.name = StringName("Status_%s" % entity_id)
	widget.configure_status(
		_runtime,
		_bridge,
		entity_id,
		_displays
	)

	_widgets[entity_id] = widget
	add_child(widget)

	print("[auto-ui] Created widget: ", entity_id)


func _on_entity_bound(entity_id: int, _world_node: Node) -> void:
	_ensure_widget(entity_id)


func _on_entity_unbound(entity_id: int) -> void:
	var widget := widget_for(entity_id)
	if is_instance_valid(widget):
		widget.hide()


func _exit_tree() -> void:
	if _bridge != null:
		if _bridge.entity_bound.is_connected(_on_entity_bound):
			_bridge.entity_bound.disconnect(_on_entity_bound)

		if _bridge.entity_unbound.is_connected(_on_entity_unbound):
			_bridge.entity_unbound.disconnect(_on_entity_unbound)

	_widgets.clear()
	_runtime = null
	_bridge = null
	_displays = {}