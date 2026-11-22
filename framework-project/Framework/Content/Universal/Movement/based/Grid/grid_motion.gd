extends RefCounted

var _board: Rect2i
var _cell_pixels: float
var _pixels_per_unit: float
var _blocked := {}
var _direction := Vector2i.ZERO
var _progress := 0.0


func _init(definition: Dictionary, pixels_per_unit: float) -> void:
	_board = Rect2i(Vector2i.ZERO, definition["board_size"])
	_cell_pixels = float(definition["cell_size_pixels"])
	_pixels_per_unit = pixels_per_unit
	for cell: Vector2i in definition["blocked_cells"]:
		_blocked[cell] = true


func advance(map_position: Vector2, lateral: float, forward: float, delta: float) -> Vector2:
	var horizontal := absf(lateral) >= absf(forward)
	var speed := lateral if horizontal else -forward
	var sign := int(signf(speed))
	var direction := Vector2i(sign, 0) if horizontal else Vector2i(0, sign)
	var cell := Vector2i((map_position / _cell_pixels).round())
	var destination := cell + direction
	if direction == Vector2i.ZERO or not _board.has_point(destination) or _blocked.has(destination):
		_direction = Vector2i.ZERO
		_progress = 0.0
		return map_position
	if _direction != direction:
		_direction = direction
		_progress = 0.0
	var travelled := absf(speed) * delta * (_pixels_per_unit / _cell_pixels)
	_progress += minf(travelled, 1.0)
	if _progress < 1.0:
		return map_position
	# A grid tick applies one cell. Extra whole cells cannot bypass obstacles.
	_progress = fposmod(_progress, 1.0)
	return Vector2(destination) * _cell_pixels
