extends SceneTree

const AutomationContent = preload(
	"res://Framework/Content/Behavior/Automation/automations.gd"
)

var _passed := true


func _initialize() -> void:
	var result := AutomationContent.definitions()

	_check("Discovery succeeds", result["ok"])

	if not result["ok"]:
		print(result["error"])
		quit(1)
		return

	var definitions: Array[Dictionary] = result["value"]
	var sources: Dictionary = result["sources"]
	var discovered_paths: Array[String] = []
	var auto_strike: Dictionary = {}
	var valid_definitions := true

	for definition: Dictionary in definitions:
		var automation_id: StringName = StringName(definition["id"])
		discovered_paths.append(String(sources[automation_id]))

		valid_definitions = (
			valid_definitions
			and definition.get("trigger") == &"interval"
			and definition.get("targeting") == &"nearest"
			and definition.has("interaction")
			and definition.has("interval_seconds")
			and definition.has("cooldown_seconds")
		)

		if automation_id == &"auto_strike":
			auto_strike = definition

	var sorted_paths := discovered_paths.duplicate()
	sorted_paths.sort()

	var expected := {
		"id": &"auto_strike",
		"interaction": &"strike",
		"trigger": &"interval",
		"targeting": &"nearest",
		"interval_seconds": 0.25,
		"cooldown_seconds": 1.0,
	}

	_check("Only Automation definitions are returned", valid_definitions)
	_check("Auto Strike matches authored settings", auto_strike == expected)
	_check(
		"Source path is preserved",
		sources.get(&"auto_strike", "")
		== "res://Framework/Content/Behavior/Automation/auto_strike.tres"
	)
	_check("Discovery order follows sorted paths", discovered_paths == sorted_paths)

	print("[automation-discovery] Definitions: ", definitions)
	print("[automation-discovery] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[automation-discovery] ", label, ": ", passed)
	_passed = _passed and passed
