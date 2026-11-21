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

	var result := _execute_movement(direction)

	if not result["ok"]:
		velocity = Vector2.ZERO
		push_error(result["error"])
		set_physics_process(false)
		return

	velocity = result["value"]
	move_and_slide()


func _execute_movement(direction: Vector2) -> Dictionary:
	if _bridge == null or not is_instance_valid(_entity_node):
		return _failure("Movement has no entity context.")

	if _definition.is_empty():
		return _failure("Movement configuration has not been read.")

	var speed: Dictionary = _definition["speed"]
	var result := _bridge.execute_action(
		StringName(_definition["action_id"]),
		_entity_node,
		_entity_node,
		{
			&"direction_x": direction.x,
			&"direction_y": direction.y,
			&"speed_container": StringName(speed["container"]),
			&"speed_path": speed["path"],
		}
	)

	if not result["ok"]:
		return result

	var calculated: Variant = result["value"]

	if not calculated is Dictionary:
		return _failure(
			"Movement Action must return a velocity dictionary."
		)

	if (
		typeof(calculated.get("x")) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(calculated.get("y")) not in [TYPE_INT, TYPE_FLOAT]
	):
		return _failure(
			"Movement Action velocity requires numeric x and y values."
		)

	var pixels_per_unit := float(speed["pixels_per_unit"])
	var pixel_velocity := Vector2(
		float(calculated["x"]) * pixels_per_unit,
		float(calculated["y"]) * pixels_per_unit
	)

	if not pixel_velocity.is_finite():
		return _failure(
			"Movement Action produced an invalid pixel velocity."
		)

	return {
		"ok": true,
		"value": pixel_velocity,
		"error": "",
	}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}


func _exit_tree() -> void:
	_bridge = null
	_entity_node = null
	_definition = {}
