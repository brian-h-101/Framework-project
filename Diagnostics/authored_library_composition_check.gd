extends SceneTree

const StartingAttributes = preload(
	"res://Framework/Env/Setup/starting_attributes.gd"
)

var _passed: bool = true


func _initialize() -> void:
	_check_composition()

	print("[libraries] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_composition() -> void:
	var first := _chest_definition()
	var second := _chest_definition()

	if not _expect("Mixed-library definitions compose", (
		first.has("containers") and second.has("containers")
	)):
		print("[libraries] First result: ", first)
		print("[libraries] Second result: ", second)
		return

	var containers: Dictionary = first["containers"]
	var other_containers: Dictionary = second["containers"]
	var required_containers: Array[StringName] = [
		&"identity",
		&"inventory",
		&"physical",
		&"value",
		&"condition",
		&"structure",
		&"access",
	]

	var all_present: bool = true
	for container_id: StringName in required_containers:
		if (
			not containers.has(container_id)
			or not other_containers.has(container_id)
		):
			all_present = false

	if not _expect("All three libraries contribute containers", all_present):
		return

	_expect("Starting overrides are applied", (
		containers[&"identity"]["name"] == "Wooden Chest"
		and containers[&"inventory"]["capacity"] == 12
		and containers[&"physical"]["weight_kg"] == 8.0
		and containers[&"value"]["amount"] == 25
		and containers[&"condition"]["current"] == 75
		and containers[&"structure"]["material"] == "wood"
		and containers[&"access"]["locked"] == true
	))

	_expect("Partial overrides preserve sibling defaults", (
		containers[&"condition"]["maximum"] == 100
		and containers[&"value"]["currency"] == "coin"
		and containers[&"access"]["open"] == false
	))

	var items: Dictionary = containers[&"inventory"]["items"]
	items["probe"] = 1

	var other_items: Dictionary = other_containers[&"inventory"]["items"]
	_expect(
		"Separate compositions own their nested collections",
		other_items.is_empty()
	)


func _chest_definition() -> Dictionary:
	return StartingAttributes.define(
		&"library_chest_probe",
		[
			"Entity/Attributes/Identity/identity.gd",
			"Entity/Container/inventory.gd",
			"Items/Attributes/Physical/physical.gd",
			"Items/Attributes/Value/value.gd",
			"Items/State/Condition/condition.gd",
			"Objects/Attributes/Structure/structure.gd",
			"Objects/State/Access/access.gd",
		],
		{
			&"identity": {
				"name": "Wooden Chest",
			},
			&"inventory": {
				"capacity": 12,
			},
			&"physical": {
				"weight_kg": 8.0,
				"volume_liters": 30.0,
			},
			&"value": {
				"amount": 25,
			},
			&"condition": {
				"current": 75,
			},
			&"structure": {
				"material": "wood",
				"destructible": true,
			},
			&"access": {
				"locked": true,
			},
		}
	)


func _expect(description: String, condition: bool) -> bool:
	print("[libraries] ", description, ": ", condition)
	_passed = _passed and condition
	return condition
