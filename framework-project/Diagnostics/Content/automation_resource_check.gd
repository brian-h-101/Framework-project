extends SceneTree

const AutomationResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Automation/automation_resource.gd"
)
const InteractionResource = preload(
	"res://Framework/Infrastructure/API/Gameplay/Resources/Interactions/interaction_resource.gd"
)

var _passed := true


func _initialize() -> void:
	var automation := ResourceLoader.load(
		"res://Framework/Content/Behavior/Automation/auto_strike.tres"
	) as AutomationResource

	_check("Automation resource loads", automation != null)

	if automation == null:
		quit(1)
		return

	var result := automation.read()
	_check("Authored configuration is valid", result["ok"])

	if not result["ok"]:
		print(result["error"])
		quit(1)
		return

	var expected := {
		"id": &"auto_strike",
		"interaction": &"strike",
		"trigger": &"interval",
		"targeting": &"nearest",
		"interval_seconds": 0.25,
		"cooldown_seconds": 1.0,
	}

	_check("Definition matches authored settings", result["value"] == expected)
	_check(
		"Interaction reference resolves",
		automation.interaction.resource_path
		== "res://Framework/Content/Behavior/Interaction/strike.tres"
	)

	var definition: Dictionary = result["value"]
	definition["interaction"] = &"diagnostic_only"
	definition["interval_seconds"] = 99.0

	_check(
		"Converted data is independent",
		automation.read()["value"] == expected
		and automation.interaction.id == &"strike"
	)

	_reject(automation, &"id", &" ")
	_reject(automation, &"interaction", null)
	_reject(automation, &"interaction", InteractionResource.new())
	_reject(automation, &"trigger", &"event")
	_reject(automation, &"targeting", &"cursor")

	for value in [0.0, -1.0, INF, NAN]:
		_reject(automation, &"interval_seconds", value)

	for value in [-1.0, INF, NAN]:
		_reject(automation, &"cooldown_seconds", value)

	var zero_cooldown := automation.duplicate() as AutomationResource
	zero_cooldown.cooldown_seconds = 0.0
	_check("Zero cooldown is accepted", zero_cooldown.read()["ok"])

	print("[automation-resource] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _reject(
	source: AutomationResource,
	property: StringName,
	value: Variant
) -> void:
	var invalid := source.duplicate() as AutomationResource
	invalid.set(property, value)
	var result := invalid.read()

	_check(
		"Invalid %s is rejected" % property,
		not result["ok"]
		and result["value"] == null
		and not String(result["error"]).is_empty()
	)


func _check(label: String, passed: bool) -> void:
	print("[automation-resource] ", label, ": ", passed)
	_passed = _passed and passed
