extends RefCounted


static func defaults() -> Dictionary:
	return {
		"startup_mode": &"restore",
		"save_path": "user://Saves/slot_01.fws",
	}