extends RefCounted


static func defaults() -> Dictionary:
	return {
		"texture": preload(
			"res://Games/ExampleGame/Tiles/ground.svg"
		),
		"tile_size": Vector2i(32, 32),
		"dimensions": Vector2i(40, 23),
	}