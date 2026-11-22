extends SceneTree

const Inspection = preload("res://Framework/Env/Authoring/Resources/Inspection/behavior_inspection.gd")
const PREFIX = "[resource-browse] "
const MAX_REQUEST = 65536

func _initialize() -> void:
	# Pipe reads have an explicit byte count. A length-prefixed request avoids
	# waiting for EOF and preserves UTF-8 across multiple requests on one pipe.
	print(PREFIX, JSON.stringify({"protocol": 1, "ready": true}))
	while true:
		var header := OS.read_buffer_from_stdin(4)
		if header.is_empty():
			break
		if header.size() != 4:
			break
		var size := header.decode_u32(0)
		if size == 0 or size > MAX_REQUEST:
			break
		var payload := OS.read_buffer_from_stdin(size)
		if payload.size() != size:
			break
		var parser := JSON.new()
		if parser.parse(payload.get_string_from_utf8()) != OK or not parser.data is Dictionary:
			break
		var request: Dictionary = parser.data
		if typeof(request.get("id")) not in [TYPE_INT, TYPE_FLOAT] or not request.get("source") is String:
			break
		var result := Inspection.browse(request["source"])
		print(PREFIX, JSON.stringify({"protocol": 1, "id": request["id"], "result": result}))
	quit()
