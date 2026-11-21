extends SceneTree

const Entry = preload("res://Framework/Infrastructure/API/Runtime/game_entry.gd")
const Setup = preload("res://Diagnostics/Fixtures/Setup/automation_setup.gd")
const AutoStrike = preload("res://Framework/Content/Behavior/Automation/auto_strike.tres")
const Codec = preload("res://Framework/Infrastructure/API/Persistence/session_codec.gd")
const System = preload("res://Framework/Infrastructure/Implementation/Gameplay/automation_system.gd")

var _passed := true
var _target := {"id": 0, "available": true}


func _initialize() -> void:
	_check_order()
	var entry := Entry.new()
	_run(entry)
	entry.stop()
	print("[automation-runtime] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _run(entry: Entry) -> void:
	if not _check("Session starts", entry.start(Setup.new())["ok"]):
		return
	var runtime := entry.runtime
	var expected: Dictionary = AutoStrike.read()["value"]
	_check("Startup registers Auto Strike", runtime.read_automation(&"auto_strike")["value"] == expected)
	_check("Duplicate registration rejected", not runtime.define_automation(expected)["ok"])
	var probe := expected.duplicate(true)
	probe["id"] = &"registration_probe"
	_check("Public registration succeeds", runtime.define_automation(probe)["ok"])
	probe["interval_seconds"] = 99.0
	var read := runtime.read_automation(&"registration_probe")
	_check("Input dictionary is independent", read["value"]["interval_seconds"] == 0.25)
	read["value"]["cooldown_seconds"] = 99.0
	_check("Read dictionary is independent", runtime.read_automation(&"registration_probe")["value"]["cooldown_seconds"] == 1.0)
	for field in ["id", "interaction", "trigger", "targeting", "interval_seconds", "cooldown_seconds"]:
		probe = expected.duplicate(true)
		probe["id"] = &"invalid_probe"
		probe[field] = null
		_check("Missing %s rejected" % field, not runtime.define_automation(probe)["ok"])
	for value in [0.0, -1.0, NAN, INF, true, "fast"]:
		probe = expected.duplicate(true)
		probe["id"] = &"invalid_probe"
		probe["interval_seconds"] = value
		_check("Invalid interval rejected", not runtime.define_automation(probe)["ok"])
	probe = expected.duplicate(true)
	probe["id"] = &"invalid_probe"
	probe["interaction"] = &"missing"
	_check("Unknown interaction rejected", not runtime.define_automation(probe)["ok"])
	runtime.define_attributes(&"automation_probe", {
		&"health": {"current": 100}, &"strength": {"current": 20},
		&"interactions": {"available": [&"strike"]}})
	var actor := runtime.spawn(&"automation_probe")
	var target := runtime.spawn(&"automation_probe")
	entry.entity_ids[&"automation_actor"] = actor
	entry.entity_ids[&"automation_target"] = target
	_target["id"] = target
	_check("Entities start without activations", runtime.automation_bindings(actor)["value"].is_empty())
	_check("Unknown entity rejected", not runtime.bind_automation(-1, &"auto_strike")["ok"])
	_check("Unknown automation rejected", not runtime.bind_automation(actor, &"missing")["ok"])
	_check("Activation succeeds", runtime.bind_automation(actor, &"auto_strike")["ok"])
	_check("Activation preserves health", runtime.read_attribute(target, &"health", ["current"])["value"] == 100)
	runtime.advance_automations(0.125, _resolve)
	var before := runtime.automation_bindings(actor)
	runtime.bind_automation(actor, &"auto_strike")
	_check("Repeated attachment preserves timing", runtime.automation_bindings(actor) == before)
	_check("Interval waits", runtime.read_attribute(target, &"health", ["current"])["value"] == 100)
	var step := runtime.advance_automations(0.125, _resolve)
	_check("Due rule invokes Strike once", step["ok"] and step["value"].size() == 1 and runtime.read_attribute(target, &"health", ["current"])["value"] == 90)
	runtime.advance_automations(0.25, _resolve)
	_check("Cooldown prevents another Strike", runtime.read_attribute(target, &"health", ["current"])["value"] == 90)
	runtime.advance_automations(0.75, _resolve)
	_check("Cooldown expiration permits Strike", runtime.read_attribute(target, &"health", ["current"])["value"] == 80)
	step = runtime.advance_automations(100.0, _resolve)
	_check("Large steps do not replay missed intervals", step["value"].size() == 1 and runtime.read_attribute(target, &"health", ["current"])["value"] == 70)
	_check("Zero step does not repeat execution", runtime.advance_automations(0.0, _resolve)["value"].is_empty())
	_check("Invalid time rejected", not runtime.advance_automations(NAN, _resolve)["ok"] and not runtime.advance_automations(-1.0, _resolve)["ok"])
	runtime.set_automation_enabled(actor, &"auto_strike", false)
	before = runtime.automation_bindings(actor)
	runtime.bind_automation(actor, &"auto_strike", true)
	runtime.advance_automations(50.0, _resolve)
	_check("Disabled state survives reattachment and freezes timers", runtime.automation_bindings(actor) == before)
	runtime.set_automation_enabled(actor, &"auto_strike", true)
	_target["available"] = false
	_check("Missing representation skips execution", runtime.advance_automations(10.0, _resolve)["value"].is_empty())
	_target["available"] = true
	runtime.write_attribute(actor, &"strength", ["current"], 19)
	step = runtime.advance_automations(1.0, _resolve)
	_check("Interaction requirements remain authoritative", not step["value"][0]["result"]["ok"] and runtime.read_attribute(target, &"health", ["current"])["value"] == 70)
	runtime.write_attribute(actor, &"strength", ["current"], 20)
	runtime.write_attribute(actor, &"interactions", ["available"], [])
	step = runtime.advance_automations(1.0, _resolve)
	_check("Activation does not grant interaction permission", not step["value"][0]["result"]["ok"] and runtime.read_attribute(target, &"health", ["current"])["value"] == 70)
	runtime.write_attribute(actor, &"interactions", ["available"], [&"strike"])
	runtime.advance_automations(1.0, _resolve)
	runtime.advance_automations(0.125, _resolve)
	var captured := entry.snapshot_session()
	_check("Snapshot uses stable entity keys", captured["ok"] and captured["value"]["automations"].has(&"automation_actor"))
	var packet := Codec.encode(captured["value"])
	_check("Automation snapshot encodes", packet["ok"])
	if not packet["ok"]:
		return
	var decoded := Codec.decode(packet["value"])
	_check("Automation snapshot round trips", decoded["ok"] and decoded["value"] == captured["value"])
	before = runtime.automation_bindings(actor)
	var bad_batch: Dictionary = captured["value"]["automations"].duplicate(true)
	bad_batch[&"automation_target"] = {&"missing": {"enabled": true, "interval_remaining": 0.0, "cooldown_remaining": 0.0}}
	_check("Invalid restore batch preserves all existing bindings", not runtime.restore_automations(bad_batch, entry.entity_ids)["ok"] and runtime.automation_bindings(actor) == before)
	entry.stop()
	_check("Closed runtime rejected", not runtime.read_automation(&"auto_strike")["ok"] and not runtime.advance_automations(1.0, _resolve)["ok"])
	_check("Session restores", entry.restore_session(Setup.new(), decoded["value"])["ok"])
	if entry.runtime == null:
		return
	actor = entry.entity_ids[&"automation_actor"]
	target = entry.entity_ids[&"automation_target"]
	_target["id"] = target
	runtime = entry.runtime
	_check("Activation and remaining cooldown restored", runtime.automation_bindings(actor) == before)
	_check("Restoration does not replay an attack", runtime.read_attribute(target, &"health", ["current"])["value"] == 60)
	decoded["value"]["automations"][&"automation_actor"][&"auto_strike"]["enabled"] = false
	_check("Restored state owns its data", runtime.automation_bindings(actor) == before)
	runtime.advance_automations(0.875, _resolve)
	_check("Restored cooldown expires normally", runtime.read_attribute(target, &"health", ["current"])["value"] == 50)
	_check("Unbinding succeeds", runtime.unbind_automation(actor, &"auto_strike")["ok"] and runtime.automation_bindings(actor)["value"].is_empty())
	entry.stop()
	var malformed: Dictionary = captured["value"].duplicate(true)
	malformed["automations"][&"automation_actor"][&"auto_strike"]["cooldown_remaining"] = -1.0
	_check("Malformed save closes the failed session", not entry.restore_session(Setup.new(), malformed)["ok"] and entry.runtime == null and entry.world_bridge == null)
	malformed.erase("automations")
	_check("Old save without Automations restores", entry.restore_session(Setup.new(), malformed)["ok"])
	if entry.runtime != null:
		_check("Old save starts without activations", entry.runtime.automation_bindings(entry.entity_ids[&"automation_actor"])["value"].is_empty())


func _check_order() -> void:
	var system := System.new()
	for id in [&"z_rule", &"a_rule"]:
		system.define_automation({"id": id, "interaction": id, "trigger": &"interval", "targeting": &"nearest",
			"interval_seconds": 0.25, "cooldown_seconds": 0.0}, func(_id: StringName) -> bool: return true)
	for entity in [5, 2]:
		for id in [&"z_rule", &"a_rule"]:
			system.bind_automation(entity, id)
	var order: Array[String] = []
	var guard := {"reentrant_rejected": false}
	var resolver := func(_entity: int, _mode: StringName) -> Dictionary: return {"ok": true, "value": 99}
	var invoke := func(id: StringName, entity: int, _target_id: int) -> Dictionary:
		order.append("%s:%s" % [entity, id])
		guard["reentrant_rejected"] = not system.advance(1.0, resolver, _unused_invoke)["ok"]
		return {"ok": true, "value": null, "error": ""}
	system.advance(0.25, resolver, invoke)
	_check("Evaluation is sorted by entity and Automation IDs", order == ["2:a_rule", "2:z_rule", "5:a_rule", "5:z_rule"])
	_check("Reentrant evaluation is rejected", guard["reentrant_rejected"])
	_check("Zero-cooldown rule still waits for its interval", system.advance(0.0, resolver, invoke)["value"].is_empty())
	system.close()


func _unused_invoke(_id: StringName, _entity: int, _target_id: int) -> Dictionary:
	return {"ok": true, "value": null, "error": ""}


func _resolve(_entity_id: int, _mode: StringName) -> Dictionary:
	return {"ok": _target["available"], "value": _target["id"], "error": ""}


func _check(label: String, passed: bool) -> bool:
	print("[automation-runtime] ", label, ": ", passed)
	_passed = _passed and passed
	return passed
