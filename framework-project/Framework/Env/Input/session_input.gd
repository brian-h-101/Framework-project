extends Node

signal command_requested(command_id: StringName)

var _controls: Dictionary[StringName, Dictionary] = {}


func configure_controls(controls: Dictionary[StringName, Dictionary]) -> void:
	_controls = controls


func _unhandled_input(event: InputEvent) -> void:
	for input_action in _controls:
		var control: Dictionary = _controls[input_action]
		if not control.has("command"):
			continue

		if not event.is_action_pressed(input_action, false):
			continue

		get_viewport().set_input_as_handled()
		command_requested.emit(StringName(control["command"]))
		return


func _exit_tree() -> void:
	_controls = {}