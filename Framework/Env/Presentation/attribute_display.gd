extends Label

const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)

@export var display_id: StringName = &""

var _runtime: GameRuntime
var _entity_id: int = 0
var _definition: Dictionary = {}


func configure_display(
	runtime: GameRuntime,
	entity_id: int,
	definition: Dictionary
) -> void:
	_runtime = runtime
	_entity_id = entity_id
	_definition = definition


func _ready() -> void:
	if _runtime == null or _definition.is_empty():
		push_error("Attribute display has no runtime context.")
		return

	if not _runtime.has_entity(_entity_id):
		push_error("Attribute display has an unknown entity ID.")
		return

	var path: Array = _definition["path"]
	if path.is_empty():
		push_error("Attribute display path is empty.")
		return

	_runtime.attribute_written.connect(_on_attribute_written)
	_refresh_attribute()


func _exit_tree() -> void:
	if _runtime != null:
		if _runtime.attribute_written.is_connected(_on_attribute_written):
			_runtime.attribute_written.disconnect(_on_attribute_written)

	_runtime = null
	_entity_id = 0
	_definition = {}


func _on_attribute_written(
	entity_id: int,
	container_id: StringName,
	attribute_name: StringName
) -> void:
	if entity_id != _entity_id:
		return

	if container_id != StringName(_definition["container"]):
		return

	var path: Array = _definition["path"]
	if attribute_name != StringName(path[0]):
		return

	_refresh_attribute()


func _refresh_attribute() -> void:
	var result := _runtime.read_attribute(
		_entity_id,
		StringName(_definition["container"]),
		_definition["path"]
	)

	if not result.ok:
		if _definition.get("optional", false):
			text = ""
			hide()
			return

		text = "?"
		push_error(result.error)
		return

	text = String(_definition["format"]) % [result.value]
	show()