extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/Bootstrap/game_setup.gd"
)
const Inventory = preload(
	"res://Framework/Content/Gameplay/Authored/Entity/Container/inventory.tres"
)

var _entry := GameEntry.new()
var _passed: bool = true


func _initialize() -> void:
	var started := _entry.start(EnvironmentSetup.new())
	if not started["ok"]:
		push_error(String(started["error"]))
		quit(1)
		return

	var runtime := _entry.runtime
	var guard_id := runtime.spawn(&"town_guard")
	_expect("TownGuard spawned", guard_id > 0)

	var before := runtime.read_attribute(
		guard_id, &"inventory", ["capacity"]
	)
	_expect("Starts without inventory", not before["ok"])

	var notified: Array[StringName] = []
	runtime.attribute_written.connect(
		func(entity_id: int, container_id: StringName, attribute_name: StringName):
			if entity_id == guard_id and container_id == &"inventory":
				notified.append(attribute_name)
	)

	var inventory: Dictionary = Inventory.to_containers()["value"][&"inventory"]
	inventory["capacity"] = 6
	inventory["items"]["ration"] = 1

	var added := runtime.add_container(guard_id, &"inventory", inventory)
	_expect("Inventory added", added["ok"] and added["value"] == true)

	var capacity := runtime.read_attribute(
		guard_id, &"inventory", ["capacity"]
	)
	var items := runtime.read_attribute(
		guard_id, &"inventory", ["items"]
	)
	_expect("Inserted values are readable", (
		capacity["ok"] and capacity["value"] == 6
		and items["ok"] and items["value"] == {"ration": 1}
	))
	_expect("Inserted attributes notify listeners", (
		notified.size() == 2
		and notified.has(&"capacity")
		and notified.has(&"items")
	))

	inventory["items"]["ration"] = 99
	var isolated := runtime.read_attribute(
		guard_id, &"inventory", ["items", "ration"]
	)
	_expect("Caller changes cannot alter stored data", (
		isolated["ok"] and isolated["value"] == 1
	))

	var duplicate := runtime.add_container(
		guard_id, &"inventory", {"capacity": 999, "items": {}}
	)
	var after_duplicate := runtime.read_attribute(
		guard_id, &"inventory", ["capacity"]
	)
	var items_after_duplicate := runtime.read_attribute(
		guard_id, &"inventory", ["items"]
	)
	_expect("Duplicate insertion preserves contents", (
		not duplicate["ok"]
		and after_duplicate["ok"] and after_duplicate["value"] == 6
		and items_after_duplicate["ok"]
		and items_after_duplicate["value"] == {"ration": 1}
	))
	_expect("Rejected insertion emits no notifications", notified.size() == 2)

	var updated := runtime.write_attribute(
		guard_id, &"inventory", ["items", "ration"], 2
	)
	var after_update := runtime.read_attribute(
		guard_id, &"inventory", ["items", "ration"]
	)
	_expect("Connector can update the new container", (
		updated["ok"] and after_update["ok"]
		and after_update["value"] == 2
	))

	var fresh_guard_id := runtime.spawn(&"town_guard")
	var fresh_inventory := runtime.read_attribute(
		fresh_guard_id, &"inventory", ["capacity"]
	)
	_expect("Another TownGuard still starts without inventory", (
		fresh_guard_id > 0 and not fresh_inventory["ok"]
	))
	_expect("Shared inventory defaults remain unchanged", (
		Inventory.to_containers()["value"][&"inventory"] == {"capacity": 0, "items": {}}
	))

	var unknown := runtime.add_container(0, &"inventory", {})
	_expect("Unknown entity is rejected", not unknown["ok"])

	_entry.stop()
	var closed := runtime.add_container(guard_id, &"inventory", {})
	_expect("Closed runtime is rejected", not closed["ok"])

	print("[container-add] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _expect(label: String, condition: bool) -> void:
	print("[container-add] ", label, ": ", condition)
	_passed = _passed and condition


func _finalize() -> void:
	_entry.stop()