extends Node

const WorldBridge = preload("res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd")
const AutomationResource = preload("res://Framework/Infrastructure/API/Gameplay/Resources/automation_resource.gd")

@export var content: AutomationResource
@export var enabled: bool = true


func configure_entity(bridge: WorldBridge, entity_node: Node) -> void:
	if content == null:
		push_error("Automation behavior requires a Resource.")
		return
	var checked := content.read()
	if checked["ok"]:
		checked = bridge.bind_automation(entity_node, content.id, enabled)
	if not checked["ok"]:
		push_error("Automation attachment failed: " + String(checked["error"]))
