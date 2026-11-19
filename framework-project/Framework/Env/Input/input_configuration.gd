extends RefCounted


static func apply(controls: Dictionary[StringName, Dictionary]) -> void:
	for input_action in controls:
		if not InputMap.has_action(input_action):
			InputMap.add_action(input_action)

		InputMap.action_erase_events(input_action)

		for key_code in controls[input_action]["keys"]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = key_code
			InputMap.action_add_event(input_action, key_event)