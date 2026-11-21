extends SceneTree

const Host = preload("res://Framework/Env/Host/game_host.gd")
const Map = preload("res://Diagnostics/Fixtures/Automation/automation_map.tscn")

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
	_check("Authored Automation map loads", loaded["ok"])
	if not loaded["ok"]:
		_finish()
		return
	var runtime := _host.entry.runtime
	var actor: int = _host.entry.entity_ids[&"player"]
	var target: int = _host.entry.entity_ids[&"enemy"]
	_check("Scene attachment activates its entity", runtime.automation_bindings(actor)["value"].has(&"auto_strike"))
	driver._process(0.25)
	_check("Session driver resolves and invokes nearest target", runtime.read_attribute(target, &"health", ["current"])["value"] == 90)
	var before := runtime.automation_bindings(actor)
	_host.maps.unload_map()
	_check("Map unload preserves activation", runtime.automation_bindings(actor) == before)
	driver._process(2.0)
	_check("Unrepresented entities do not attack", runtime.read_attribute(target, &"health", ["current"])["value"] == 90)
	before = runtime.automation_bindings(actor)
	_check("Map reload succeeds", _host.maps.load_map(Map)["ok"])
	_check("Map reload preserves timers and creates no duplicate binding", runtime.automation_bindings(actor) == before and before["value"].size() == 1)
	driver._process(0.25)
	_check("Automation resumes after map returns", runtime.read_attribute(target, &"health", ["current"])["value"] == 80)
	runtime.set_automation_enabled(actor, &"auto_strike", false)
	_host.maps.load_map(Map)
	_check("Reload does not re-enable a disabled binding", not runtime.automation_bindings(actor)["value"][&"auto_strike"]["enabled"])
	var folder := "user://diagnostics/automation_session_" + Crypto.new().generate_random_bytes(12).hex_encode()
	var save := folder.path_join("session.fws")
	_check("Host saves activated state", _host.save_session(save)["ok"])
	_host.stop()
	var restored := _host.restore_session(root, save)
	_check("Host restores Automation map and activation", restored["ok"])
	if restored["ok"]:
		actor = _host.entry.entity_ids[&"player"]
		target = _host.entry.entity_ids[&"enemy"]
		_check("Restored component preserves disabled state", not _host.entry.runtime.automation_bindings(actor)["value"][&"auto_strike"]["enabled"])
		_check("Restored entity has saved health", _host.entry.runtime.read_attribute(target, &"health", ["current"])["value"] == 80)
	_check("Diagnostic save removed", DirAccess.remove_absolute(save) == OK)
	_check("Diagnostic folder removed", DirAccess.remove_absolute(folder) == OK)
	_finish()


func _finish() -> void:
	_host.stop()
	print("[automation-session] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[automation-session] ", label, ": ", passed)
	_passed = _passed and passed
