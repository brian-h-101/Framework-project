extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"primary_interaction": {
			"keys": [KEY_SPACE],
			"interaction": &"strike",
			"targeting": &"nearest",
		},
		&"move_left": {
			"keys": [KEY_A, KEY_LEFT],
		},
		&"move_right": {
			"keys": [KEY_D, KEY_RIGHT],
		},
		&"move_up": {
			"keys": [KEY_W, KEY_UP],
		},
		&"move_down": {
			"keys": [KEY_S, KEY_DOWN],
		},
		&"save_game": {
			"keys": [KEY_F5],
			"command": &"save_session",
		},
	}