extends SceneTree

const Entry = preload("res://Framework/Infrastructure/API/Runtime/game_entry.gd")
const Setup = preload("res://Framework/Env/Setup/Bootstrap/game_setup.gd")
const Behavior = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_resource.gd")
const Group = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/group_step_resource.gd")
const Configuration = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_configuration_resource.gd")
const Strike = preload("res://Framework/Content/Behavior/Sequence/strike.tres")

var passed := true

func check(label: String, valid: bool) -> void:
	print("[behavior-sequence] %s: %s" % [label, valid])
	passed = passed and valid

func _initialize() -> void:
	var source := Entry.new()
	check("Content and nested Resource contract load", source.start(Setup.new())["ok"] and Strike.read()["ok"])
	var runtime := source.runtime
	var actor: int = source.entity_ids[&"player"]
	var target: int = source.entity_ids[&"enemy"]
	var resolve := func(_actor: int, mode: StringName) -> Dictionary:
		return {"ok": true, "value": runtime.selected_target(actor) if mode == &"selected" else target, "error": ""}
	var data: Dictionary = Strike.read()["value"]
	data["id"] = &"nested_probe"
	data["configuration"]["targeting"] = "selected"
	var action: Dictionary = data["steps"][0]
	action["requirements"] = [{"entity": &"target", "container": &"health", "path": ["alive"], "operator": "==", "value": true}]
	runtime.add_attribute(target, &"health", &"alive", true)
	var skipped := action.duplicate(true)
	skipped["id"] = &"skip"
	skipped["requirements"][0]["value"] = false
	data["steps"] = [skipped, {"id": &"group", "label": "Group", "kind": "group", "requirements": [], "steps": [action]}]
	check("Nested sequence registered", runtime.define_behavior(data)["ok"])
	check("Registration grants no activation", not runtime.invoke_behavior(&"nested_probe", actor, resolve)["ok"])
	check("Explicit entity activation succeeds", runtime.bind_behavior(actor, &"nested_probe")["ok"])
	runtime.select_target(actor, target)
	var result := runtime.invoke_behavior(&"nested_probe", actor, resolve)
	check("False branch skips and later nested action runs", result["ok"] and result["value"]["skipped"] == 1 and result["value"]["executed"] == 1 and runtime.read_attribute(target, &"health", ["current"])["value"] == 90)
	check("Manual and event calls share cooldown", not runtime.invoke_behavior(&"nested_probe", actor, resolve)["ok"] and not runtime.emit_behavior_event(actor, &"on_attack", resolve)["value"][0]["result"]["ok"])
	runtime.advance_behaviors(1.5, resolve)
	runtime.write_attribute(target, &"health", ["alive"], false)
	result = runtime.invoke_behavior(&"nested_probe", actor, resolve)
	check("Boolean conditions use current state", result["ok"] and result["value"]["executed"] == 1)
	runtime.advance_behaviors(1.5, resolve)
	var all_skipped := data.duplicate(true)
	all_skipped["id"] = &"all_skipped"
	all_skipped["steps"] = [action]
	runtime.define_behavior(all_skipped)
	runtime.bind_behavior(actor, &"all_skipped")
	result = runtime.invoke_behavior(&"all_skipped", actor, resolve)
	check("All-skipped invocation spends no cooldown", result["ok"] and result["value"]["attempted"] == 0 and runtime.behavior_bindings(actor)["value"][&"all_skipped"]["cooldown_remaining"] == 0)
	var invalid := data.duplicate(true)
	invalid["id"] = &"duplicate_step"
	invalid["steps"].append(action.duplicate(true))
	check("Duplicate step IDs rejected", not runtime.define_behavior(invalid)["ok"])
	invalid = data.duplicate(true)
	invalid["id"] = &"bad_address"
	invalid["steps"] = [action.duplicate(true)]
	invalid["steps"][0]["requirements"][0]["path"] = ["missing"]
	runtime.define_behavior(invalid)
	runtime.bind_behavior(actor, &"bad_address")
	check("Invalid addresses fail instead of skipping", not runtime.invoke_behavior(&"bad_address", actor, resolve)["ok"])
	check("Missing selected target rejected", runtime.select_target(actor, 0)["ok"] and not runtime.invoke_behavior(&"nested_probe", actor, resolve)["ok"])
	runtime.select_target(actor, target)
	var failed := data.duplicate(true)
	failed["id"] = &"partial_error"
	failed["steps"] = [action.duplicate(true), action.duplicate(true)]
	failed["steps"][0]["id"] = &"first"
	failed["steps"][0]["requirements"] = []
	failed["steps"][1]["id"] = &"failure"
	failed["steps"][1]["requirements"] = []
	failed["steps"][1]["arguments"][&"amount"] = "invalid"
	check("Executor argument contract rejects bad content", not runtime.define_behavior(failed)["ok"])
	# A later executor can fail on live data even when its authored arguments are valid.
	failed["steps"][1]["executor_id"] = &"attribute_effects"
	failed["steps"][1]["arguments"] = {&"amount": -1}
	failed["steps"][1]["effects"] = [{"operation": &"add", "entity": &"target", "container": &"missing", "path": ["current"], "value_from": &"amount"}]
	runtime.define_behavior(failed)
	runtime.bind_behavior(actor, &"partial_error")
	result = runtime.invoke_behavior(&"partial_error", actor, resolve)
	check("Partial failure retains report and consumes cooldown", not result["ok"] and result["value"]["executed"] == 1 and runtime.behavior_bindings(actor)["value"][&"partial_error"]["cooldown_remaining"] == 1.5)
	var cyclic := Behavior.new()
	cyclic.id = &"cycle"
	cyclic.configuration = Configuration.new()
	var group := Group.new()
	group.id = &"recursive"
	group.steps.append(group)
	cyclic.steps.append(group)
	check("Resource cycles rejected", not cyclic.read()["ok"] and cyclic.to_definition().is_empty())
	group.steps.clear()
	# Persist only registered production definitions into a fresh setup.
	for id in [&"nested_probe", &"all_skipped", &"bad_address", &"partial_error"]:
		runtime.unbind_behavior(actor, id)
	runtime.bind_behavior(actor, &"strike")
	runtime.invoke_behavior(&"strike", actor, resolve)
	runtime.advance_behaviors(0.5, resolve)
	runtime.set_behavior_enabled(actor, &"strike", false)
	var snapshot := source.snapshot_session()
	check("Stable keys capture remaining timers", snapshot["ok"] and snapshot["value"]["behaviors"][&"player"][&"strike"]["cooldown_remaining"] == 1.0)
	source.stop()
	var restored := Entry.new()
	check("Session restores Behavior state", restored.restore_session(Setup.new(), snapshot["value"])["ok"])
	var saved: Dictionary = restored.runtime.behavior_bindings(restored.entity_ids[&"player"])["value"][&"strike"]
	check("Disabled state and cooldown survive", not saved["enabled"] and saved["cooldown_remaining"] == 1.0)
	check("Selection stays transient", restored.runtime.selected_target(restored.entity_ids[&"player"]) == 0)
	check("Scene rebinding preserves disabled state", restored.runtime.bind_behavior(restored.entity_ids[&"player"], &"strike")["ok"] and not restored.runtime.behavior_bindings(restored.entity_ids[&"player"])["value"][&"strike"]["enabled"])
	restored.stop()
	var legacy: Dictionary = snapshot["value"].duplicate(true)
	legacy.erase("behaviors")
	var old_entry := Entry.new()
	check("Older entity snapshots remain compatible", old_entry.restore_session(Setup.new(), legacy)["ok"] and old_entry.runtime.behavior_bindings(old_entry.entity_ids[&"player"])["value"].is_empty())
	old_entry.stop()
	var malformed: Dictionary = snapshot["value"].duplicate(true)
	malformed["behaviors"][&"player"][&"strike"]["cooldown_remaining"] = -1
	var failed_entry := Entry.new()
	check("Malformed saved timer fails atomically", not failed_entry.restore_session(Setup.new(), malformed)["ok"] and failed_entry.runtime == null and failed_entry.entity_ids.is_empty())
	check("Restore can retry after rejection", failed_entry.restore_session(Setup.new(), snapshot["value"])["ok"])
	failed_entry.stop()
	check("Closed runtime rejects invocation", not runtime.invoke_behavior(&"strike", actor, resolve)["ok"])
	print("[behavior-sequence] Checks passed: %s" % passed)
	quit(0 if passed else 1)
