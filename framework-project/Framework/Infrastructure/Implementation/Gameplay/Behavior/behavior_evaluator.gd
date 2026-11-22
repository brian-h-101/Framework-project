extends RefCounted

# Requirements read live state as each step is reached. A false predicate skips its
# branch; an invalid address or executor failure stops the invocation, without rollback.
static func execute(steps: Array, bindings: Dictionary, connector: RefCounted,
		action_executor: RefCounted, before_attempt: Callable) -> Dictionary:
	var report := {"steps": [], "attempted": 0, "executed": 0, "skipped": 0}
	var error := _sequence(steps, bindings, connector, action_executor, before_attempt, report)
	return {"ok": error.is_empty(), "value": report, "error": error}

static func _sequence(steps: Array, bindings: Dictionary, connector: RefCounted,
		action_executor: RefCounted, before_attempt: Callable, report: Dictionary) -> String:
	for step: Dictionary in steps:
		var row := {"id": step["id"], "kind": step["kind"], "status": "", "result": null}
		report["steps"].append(row)
		var eligible := true
		for condition: Dictionary in step["requirements"]:
			var address: RefCounted = connector.make_reference(bindings[StringName(condition["entity"])], StringName(condition["container"]), condition["path"])
			var compared: Dictionary = connector.compare(address, String(condition["operator"]), condition["value"])
			if not compared["ok"]:
				row["status"] = "error"
				return "Step '%s': %s" % [step["id"], compared["error"]]
			if not compared["value"]:
				eligible = false
				row["reason"] = condition.get("message", "Requirement not met.")
				break
		if not eligible:
			row["status"] = "skipped"
			report["skipped"] += 1
			continue
		if step["kind"] == "group":
			row["status"] = "entered"
			var error := _sequence(step["steps"], bindings, connector, action_executor, before_attempt, report)
			if not error.is_empty():
				return error
		else:
			if report["attempted"] == 0:
				before_attempt.call()
			report["attempted"] += 1
			var definition := step.duplicate(true)
			definition["behavior_id"] = step["executor_id"]
			var result: Dictionary = action_executor.execute(definition, bindings, step["arguments"])
			row["result"] = result
			row["status"] = "executed" if result["ok"] else "error"
			if not result["ok"]:
				return "Step '%s': %s" % [step["id"], result["error"]]
			report["executed"] += 1
	return ""
