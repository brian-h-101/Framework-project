extends CharacterBody2D

const WorldBridge = preload("res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd")
const Configuration = preload("res://Framework/Content/Universal/Movement/based/Configuration/movement_profile.gd")
const Controller = preload("res://Framework/Content/Universal/Movement/based/Controllers/movement_controller.gd")
const Movement = preload("res://Framework/Content/Universal/Movement/based/Execution/movement_component.gd")

@export var content: Configuration
@export var controller: Controller

var _movement := Movement.new()


func configure_entity(bridge: WorldBridge, entity_node: Node) -> void:
	_movement.configure_entity(bridge, entity_node)


func configure_map(map_root: Node) -> void:
	_movement.configure_map(map_root)


func _ready() -> void:
	_check(_movement.start(self, content, controller))


func _physics_process(delta: float) -> void:
	_check(_movement.advance(delta))


func _check(error: String) -> void:
	if not error.is_empty():
		set_physics_process(false)
		push_error(error)


func _exit_tree() -> void:
	_movement = Movement.new()
