extends SceneTree

const Host = preload("res://Framework/Env/Host/game_host.gd")
const Preview = preload("res://Diagnostics/Fixtures/BehaviorSequence/nested_strike.tres")
var _host := Host.new()

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	var result := _host.start(root)
	if not result["ok"]:
		push_error(result["error"])
		quit(1)
		return
	var runtime := _host.entry.runtime
	var actor: int = _host.entry.entity_ids[&"player"]
	var target: int = _host.entry.entity_ids[&"enemy"]
	result = runtime.define_behavior(Preview.read()["value"])
	if not result["ok"]:
		push_error(result["error"])
		quit(1)
		return
	runtime.set_behavior_enabled(actor, &"strike", false)
	runtime.bind_behavior(actor, Preview.id)
	runtime.add_attribute(target, &"health", &"alive", true)
	runtime.write_attribute(actor, &"strength", ["current"], 45)
	runtime.select_target(actor, target)
	# Preview starts fresh; disable saving so the real save slot cannot be overwritten.
	root.get_node("SessionInput").set_process_unhandled_input(false)
	root.get_node("SessionInput").set_process_input(false)
	print("[behavior-visual] Preview ready. Space runs three ordered damage steps (-15 total), with a shared 1.5 second cooldown. WASD still moves Player. Click Enemy to select it; click empty space to clear selection. Saving is disabled.")

func _finalize() -> void:
	_host.stop()
