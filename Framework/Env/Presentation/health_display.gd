extends Label

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)

var _bridge: WorldBridge
var _entity_node: Node


func configure_entity(bridge: WorldBridge, entity_node: Node) -> void:
	_bridge = bridge
	_entity_node = entity_node


func _ready() -> void:
	if _bridge == null or not is_instance_valid(_entity_node):
		push_error("Health display has no entity context.")
		return

	_bridge.attribute_written.connect(_on_attribute_written)
	_refresh_health()


func _exit_tree() -> void:
	if _bridge != null:
		if _bridge.attribute_written.is_connected(_on_attribute_written):
			_bridge.attribute_written.disconnect(_on_attribute_written)

	_bridge = null
	_entity_node = null


func _on_attribute_written(
	world_node: Node,
	container_id: StringName,
	attribute_name: StringName
) -> void:
	if world_node != _entity_node:
		return

	if container_id != &"health" or attribute_name != &"current":
		return

	_refresh_health()


func _refresh_health() -> void:
	var result := _bridge.read_attribute(
		_entity_node, &"health", ["current"]
	)

	if not result.ok:
		text = "Health: ?"
		push_error(result.error)
		return

	text = "Health: %s" % result.value