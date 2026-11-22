extends TileMapLayer

const Configuration = preload("res://Framework/Content/Universal/Map/based/Configuration/ground_resource.gd")

@export var content: Configuration


func _ready() -> void:
	if content == null:
		push_error("TileMapLayer has no content definition.")
		return

	var checked := content.read()
	if not checked["ok"]:
		push_error(checked["error"])
		return
	var definition: Dictionary = checked["value"]
	_build(definition)


func _build(definition: Dictionary) -> void:
	var cell_size: Vector2i = definition["tile_size"]
	var dimensions: Vector2i = definition["dimensions"]

	var atlas := TileSetAtlasSource.new()
	atlas.texture = definition["texture"]
	atlas.texture_region_size = cell_size
	atlas.create_tile(Vector2i.ZERO)

	var generated_tiles := TileSet.new()
	generated_tiles.tile_size = cell_size
	var source_id := generated_tiles.add_source(atlas)

	clear()
	tile_set = generated_tiles

	for y in range(dimensions.y):
		for x in range(dimensions.x):
			set_cell(
				Vector2i(x, y),
				source_id,
				Vector2i.ZERO
			)

	print("[tiles] %s cells: %s" % [name, get_used_cells().size()])
