extends CharacterBody2D

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)

const Configuration = preload("res://Framework/Env/Configuration/Resources/movement_resource.gd")

@export var content: Configuration

var _bridge: WorldBridge
var _entity_node: Node
var _definition: Dictionary = {}


func configure_entity(bridge: WorldBridge, entity_node: Node) -> void:
	_bridge = bridge
	_entity_node = entity_node


func _ready() -> void:
	if content == null or _bridge == null or not is_instance_valid(_entity_node):
		push_error("Movement has no configuration or entity context.")
		set_physics_process(false)
		return

	var checked := content.read()
	if not checked["ok"]:
		push_error(checked["error"])
		set_physics_process(false)
		return
	_definition = checked["value"]
	motion_mode = MOTION_MODE_FLOATING


func _physics_process(_delta: float) -> void:
	var actions: Dictionary = _definition["actions"]
	var direction := Input.get_vector(
		actions["left"],
		actions["right"],
		actions["up"],
		actions["down"]
	)

	var speed: Dictionary = _definition["speed"]
	var result := _bridge.read_attribute(
		_entity_node,
		StringName(speed["container"]),
		speed["path"]
	)

	if not result.ok:
		velocity = Vector2.ZERO
		push_error(result.error)
		set_physics_process(false)
		return

	var pixels_per_second := float(result.value) * float(speed["pixels_per_unit"])
	velocity = direction * pixels_per_second
	move_and_slide()


func _exit_tree() -> void:
	_bridge = null
	_entity_node = null
	_definition = {}
