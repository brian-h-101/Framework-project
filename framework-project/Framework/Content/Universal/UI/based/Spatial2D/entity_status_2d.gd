extends Control

const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)
const UIAnchor2D = preload(
	"res://Framework/Content/Universal/UI/based/Spatial2D/ui_anchor_2d.gd"
)
@export var anchor_role: StringName = &"status"
@export var screen_offset: Vector2 = Vector2.ZERO

var _bridge: WorldBridge
var _entity_id: int = 0


func configure_status(
	runtime: GameRuntime,
	bridge: WorldBridge,
	entity_id: int,
	displays: Dictionary[StringName, Dictionary]
) -> void:
	_bridge = bridge
	_entity_id = entity_id

	for component in find_children("*", "", true, false):
		if component.has_method(&"configure_display"):
			var display_id := StringName(component.get("display_id"))

			component.call(
				&"configure_display",
				runtime,
				_entity_id,
				displays[display_id]
			)

func _ready() -> void:
	process_priority = 100
	_refresh_position()


func _process(_delta: float) -> void:
	_refresh_position()


func _refresh_position() -> void:
	if _bridge == null:
		hide()
		return

	var entity_node := _bridge.node_for(_entity_id)
	if not is_instance_valid(entity_node):
		hide()
		return

	var anchor_result := UIAnchor2D.find_for(entity_node, anchor_role)
	if not anchor_result["ok"]:
		hide()
		return

	var anchor := anchor_result["value"] as Node2D
	if not is_instance_valid(anchor) or not anchor.is_visible_in_tree():
		hide()
		return

	var ui_parent := get_parent() as CanvasItem
	if ui_parent == null:
		hide()
		return

	var viewport_position := anchor.get_global_transform_with_canvas().origin

	position = ui_parent.make_canvas_position_local(
		viewport_position + screen_offset
	)

	show()


func _exit_tree() -> void:
	_bridge = null
	_entity_id = 0