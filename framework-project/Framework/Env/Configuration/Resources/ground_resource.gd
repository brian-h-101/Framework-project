extends "res://Framework/Env/Configuration/Resources/configuration_resource.gd"

@export var texture: Texture2D
@export var tile_size: Vector2i = Vector2i.ZERO
@export var dimensions: Vector2i = Vector2i.ZERO


func to_definition() -> Dictionary:
	return {"texture": texture, "tile_size": tile_size, "dimensions": dimensions}


func validation_error() -> String:
	if texture == null:
		return "Ground requires a tile texture."
	if tile_size.x <= 0 or tile_size.y <= 0 or dimensions.x <= 0 or dimensions.y <= 0:
		return "Tile size and map dimensions must be positive."
	if texture.get_width() < tile_size.x or texture.get_height() < tile_size.y:
		return "The texture must contain at least one complete tile."
	return ""
