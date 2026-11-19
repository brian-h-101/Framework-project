extends SceneTree

const Controls = preload(
	"res://Framework/Content/Configuration/Input/controls.gd"
)
const InputConfiguration = preload(
	"res://Framework/Env/Input/input_configuration.gd"
)


func _initialize() -> void:
	var controls := Controls.defaults()

	if InputMap.has_action(&"primary_interaction"):
		InputMap.erase_action(&"primary_interaction")

	InputConfiguration.apply(controls)

	print("[controls] Action registered: ",
		InputMap.has_action(&"primary_interaction"))

	var key_event := InputEventKey.new()
	key_event.physical_keycode = KEY_SPACE
	key_event.pressed = true

	print("[controls] Space matches action: ",
		InputMap.event_is_action(key_event, &"primary_interaction"))

	print("[controls] Requested interaction: %s" %
		controls[&"primary_interaction"]["interaction"])

	InputConfiguration.apply(controls)

	print("[controls] Events after reapply: ",
		InputMap.action_get_events(&"primary_interaction").size())

	quit()