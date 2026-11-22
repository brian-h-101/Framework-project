extends SceneTree

const Host = preload("res://Framework/Env/Host/game_host.gd")
const Map = preload("res://Diagnostics/Fixtures/BehaviorSequence/automatic_map.tscn")

var _passed := true
var _host := Host.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check("Host starts", _host.start(root)["ok"])
	if _host.entry.runtime == null:
		_finish()
		return
	var driver := root.get_node("SessionDriver")
	driver.set_process(false)
	var loaded := _host.maps.load_map(Map)
	_check("Authored Behavior map loads", loaded["ok"])
	if not loaded["ok"]:
		_finish()
		return
	var runtime := _host.entry.runtime
	var actor: int = _host.entry.entity_ids[&"player"]
	var target: int = _host.entry.entity_ids[&"enemy"]
	_check("Scene attachment activates its entity", runtime.behavior_bindings(actor)["value"].has(&"auto_strike"))
	driver._process(0.25)
	_check("Session driver resolves and invokes nearest target", runtime.read_attribute(target, &"health", ["current"])["value"] == 90)
	var bridge := _host.entry.world_bridge
	var player := _host.maps.get_active_map().get_node("Player")
	var enemy := _host.maps.get_active_map().get_node("Enemy")
	_check("Selected target can be set through the world bridge", bridge.select_behavior_target(player, enemy)["ok"] and bridge.resolve_behavior_target(actor, &"selected")["value"] == target)
	var input := InputEventAction.new()
	input.action = &"primary_interaction"
	input.pressed = true
	root.push_input(input)
	_check("Named input event runs after map switch", runtime.read_attribute(target, &"health", ["current"])["value"] == 80)
	input.pressed = false
	root.push_input(input)
	var before := runtime.behavior_bindings(actor)
	_host.maps.unload_map()
	_check("Map unload preserves activation", runtime.behavior_bindings(actor) == before)
	driver._process(2.0)
	_check("Unrepresented entities do not attack", runtime.read_attribute(target, &"health", ["current"])["value"] == 80)
	before = runtime.behavior_bindings(actor)
	_check("Map reload succeeds", _host.maps.load_map(Map)["ok"])
	_check("Map reload preserves timers and creates no duplicate binding", runtime.behavior_bindings(actor) == before and before["value"].size() == 2)
	driver._process(0.25)
	_check("Behavior resumes after map returns", runtime.read_attribute(target, &"health", ["current"])["value"] == 70)
	runtime.set_behavior_enabled(actor, &"auto_strike", false)
	_host.maps.load_map(Map)
	_check("Reload does not re-enable a disabled binding", not runtime.behavior_bindings(actor)["value"][&"auto_strike"]["enabled"])
	var folder := "user://diagnostics/behavior_sequence_session_" + Crypto.new().generate_random_bytes(12).hex_encode()
	var save := folder.path_join("session.fws")
	_check("Host saves activated state", _host.save_session(save)["ok"])
	_host.stop()
	var restored := _host.restore_session(root, save)
	_check("Host restores Behavior map and activation", restored["ok"])
	if restored["ok"]:
		actor = _host.entry.entity_ids[&"player"]
		target = _host.entry.entity_ids[&"enemy"]
		_check("Restored component preserves disabled state", not _host.entry.runtime.behavior_bindings(actor)["value"][&"auto_strike"]["enabled"])
		_check("Restored entity has saved health", _host.entry.runtime.read_attribute(target, &"health", ["current"])["value"] == 70)
	_check("Diagnostic save removed", DirAccess.remove_absolute(save) == OK)
	_check("Diagnostic folder removed", DirAccess.remove_absolute(folder) == OK)
	_finish()


func _finish() -> void:
	_host.stop()
	print("[behavior-session] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[behavior-session] ", label, ": ", passed)
	_passed = _passed and passed
