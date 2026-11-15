extends Label

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)

@export var display_id: StringName = &""

var _bridge: WorldBridge
var _entity_node: Node
var _definition: Dictionary = {}


func configure_entity(bridge: WorldBridge, entity_node: Node) -> void:
	_bridge = bridge
	_entity_node = entity_node


func configure_displays(displays: Dictionary[StringName, Dictionary]) -> void:
	_definition = displays.get(display_id, {})


func _ready() -> void:
	if _bridge == null or not is_instance_valid(_entity_node):
		push_error("Attribute display has no entity context.")
		return

	if _definition.is_empty():
		push_error("Unknown attribute display: %s" % display_id)
		return

	var path: Array = _definition["path"]
	if path.is_empty():
		push_error("Attribute display path is empty.")
		return

	_bridge.attribute_written.connect(_on_attribute_written)
	_refresh_attribute()


func _exit_tree() -> void:
	if _bridge != null:
		if _bridge.attribute_written.is_connected(_on_attribute_written):
			_bridge.attribute_written.disconnect(_on_attribute_written)

	_bridge = null
	_entity_node = null
	_definition = {}


func _on_attribute_written(
	world_node: Node,
	container_id: StringName,
	attribute_name: StringName
) -> void:
	if world_node != _entity_node:
		return

	var path: Array = _definition["path"]

	if container_id != StringName(_definition["container"]):
		return

	if attribute_name != StringName(path[0]):
		return

	_refresh_attribute()


func _refresh_attribute() -> void:
	var result := _bridge.read_attribute(
		_entity_node,
		StringName(_definition["container"]),
		_definition["path"]
	)

	if not result.ok:
		text = "?"
		push_error(result.error)
		return

	text = String(_definition["format"]) % [result.value]