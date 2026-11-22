extends Resource

const Configuration = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_configuration_resource.gd")
const ActionStep = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/action_step_resource.gd")
const GroupStep = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/group_step_resource.gd")
const Definition = preload("res://Framework/Infrastructure/Implementation/Gameplay/Behavior/behavior_definition.gd")

@export var id: StringName = &""
@export var configuration: Configuration
@export var steps: Array[Resource] = []

func read() -> Dictionary:
	if configuration != null and not configuration.resource_path.is_empty() and not configuration.resource_path.contains("::"):
		return Definition.failure("Behavior Configuration must be embedded in its owning file.")
	if configuration == null:
		return Definition.failure("Behavior requires Configuration.")
	var state := {"seen": {}, "count": 0, "error": ""}
	var converted := _steps(steps, state, 0)
	if not state["error"].is_empty():
		return Definition.failure(state["error"])
	var data := {"id": id, "configuration": configuration.to_definition(), "steps": converted}
	var error := Definition.validation_error(data)
	return Definition.success(data.duplicate(true)) if error.is_empty() else Definition.failure(error)

func to_definition() -> Dictionary:
	var checked := read()
	return checked["value"] if checked["ok"] else {}

static func _steps(entries: Array[Resource], state: Dictionary, depth: int) -> Array:
	var output := []
	if depth > 32:
		state["error"] = "Behavior exceeds 32 nested groups."
		return output
	for entry in entries:
		state["count"] += 1
		if entry == null or not (entry is ActionStep or entry is GroupStep):
			state["error"] = "Steps must be ActionStep or GroupStep Resources."
			return output
		if not entry.resource_path.is_empty() and not entry.resource_path.contains("::"):
			state["error"] = "Behavior steps must be embedded in their owning file."
			return output
		if state["seen"].has(entry.get_instance_id()) or state["count"] > 1024:
			state["error"] = "Behavior contains a cycle, reused step, or more than 1024 steps."
			return output
		state["seen"][entry.get_instance_id()] = true
		var requirements := []
		if entry.requirements != null:
			var condition_ids := {}
			for condition in entry.requirements.conditions:
				if condition == null or String(condition.id).is_empty() or condition_ids.has(condition.id):
					state["error"] = "Requirements contain a missing condition or duplicate condition ID."
					return output
				condition_ids[condition.id] = true
				requirements.append(condition.to_definition())
		var step := {"id": entry.id, "label": entry.label, "requirements": requirements}
		if entry is ActionStep:
			step.merge({"kind": "action", "executor_id": entry.executor_id,
				"arguments": entry.arguments, "effects": entry.effects})
		else:
			step.merge({"kind": "group", "steps": _steps(entry.steps, state, depth + 1)})
		output.append(step)
	return output
