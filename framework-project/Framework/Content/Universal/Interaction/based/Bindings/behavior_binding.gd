extends Node

const Behavior = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd")
const WorldBridge = preload("res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd")

@export var content: Behavior
@export var enabled: bool = true

func configure_entity(bridge: WorldBridge, entity: Node) -> void:
	if content == null:
		push_error("Behavior binding requires content.")
		return
	var checked := content.read()
	if checked["ok"]:
		checked = bridge.bind_behavior(entity, content.id, enabled)
	if not checked["ok"]:
		push_error("Behavior '%s': %s" % [content.id, checked["error"]])
