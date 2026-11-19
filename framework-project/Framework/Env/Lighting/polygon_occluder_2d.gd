extends LightOccluder2D


func _ready() -> void:
	var body := get_parent() as Polygon2D
	if body == null:
		push_error("Polygon occluder requires a Polygon2D parent.")
		return

	var shape := OccluderPolygon2D.new()
	shape.polygon = body.polygon

	position = body.offset
	occluder = shape

	print("[lighting] Shadow caster: ", get_path())