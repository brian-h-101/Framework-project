extends SceneTree

const PresetData = preload(
	"res://Diagnostics/Fixtures/starting_attributes_access.gd"
)

const PlayerContainers = preload(
	"res://Framework/Content/Presentation/Entity/Player/starting_attributes.tres"
)
const PlayerBaseline = preload(
	"res://Diagnostics/Fixtures/player_containers_baseline.gd"
)
const EnemyContainers = preload(
	"res://Framework/Content/Presentation/Entity/Enemy/starting_attributes.tres"
)
const EnemyBaseline = preload(
	"res://Diagnostics/Fixtures/enemy_containers_baseline.gd"
)
const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/game_setup.gd"
)
const TownGuard = preload(
	"res://Framework/Content/Presentation/Entity/TownGuard/starting_attributes.tres"
)
const Inventory = preload(
	"res://Framework/Content/Authored/Entity/Container/inventory.tres"
)

var _entry := GameEntry.new()


func _initialize() -> void:
	var player_result := PresetData.category(PlayerContainers, &"player", "Container")

	if not player_result["ok"]:
		push_error(String(player_result["error"]))
		quit(1)
		return

	var enemy_result := PresetData.category(EnemyContainers, &"enemy", "Container")

	if not enemy_result["ok"]:
		push_error(String(enemy_result["error"]))
		quit(1)
		return

	var player_actual: Dictionary[StringName, Dictionary] = player_result["value"]
	var player_expected := PlayerBaseline.defaults()
	var player_matches: bool = player_actual == player_expected

	var enemy_actual: Dictionary[StringName, Dictionary] = enemy_result["value"]
	var enemy_expected := EnemyBaseline.defaults()
	var enemy_matches: bool = enemy_actual == enemy_expected
	var guard_definition := TownGuard.to_definition()
	var inventory_preserved: bool = (
		player_actual[&"inventory"] == {"capacity": 10, "items": {}}
		and enemy_actual[&"inventory"] == {
			"capacity": 6, "items": {"ration": 1, "cloth": 2}
		}
		and not guard_definition["containers"].has(&"inventory")
		and Inventory.to_containers()["value"][&"inventory"] == {"capacity": 0, "items": {}}
	)

	print("[container] Player matches baseline: ", player_matches)
	print("[container] Player containers: ", player_actual.size())
	print("[container] Enemy matches baseline: ", enemy_matches)
	print("[container] Enemy containers: ", enemy_actual.size())
	print("[container] Inventory selections and starting values preserved: ",
		inventory_preserved)

	var started := _entry.start(EnvironmentSetup.new())

	if not started["ok"]:
		push_error(String(started["error"]))
		quit(1)
		return

	var player_runtime_matches: bool = _runtime_matches(
		&"player",
		player_expected
	)
	var enemy_runtime_matches: bool = _runtime_matches(
		&"enemy",
		enemy_expected
	)

	print(
		"[container] Player runtime matches baseline: ",
		player_runtime_matches
	)
	print(
		"[container] Enemy runtime matches baseline: ",
		enemy_runtime_matches
	)

	var passed: bool = (
		player_matches
		and enemy_matches
		and player_runtime_matches
		and enemy_runtime_matches
		and inventory_preserved
	)

	_entry.stop()

	print("[container] Checks passed: ", passed)
	quit(0 if passed else 1)


func _runtime_matches(
	entity_key: StringName,
	expected: Dictionary
) -> bool:
	var entity_id: int = _entry.entity_ids[entity_key]
	var matches: bool = true

	for container_id in expected:
		var fields: Dictionary = expected[container_id]

		for attribute_name in fields:
			var read_result := _entry.runtime.read_attribute(
				entity_id,
				StringName(container_id),
				[attribute_name]
			)

			var field_matches: bool = (
				read_result["ok"]
				and read_result["value"] == fields[attribute_name]
			)

			if not field_matches:
				matches = false
				print(
					"[container] %s mismatch at %s/%s: %s"
					% [
						entity_key,
						container_id,
						attribute_name,
						read_result,
					]
				)

	return matches


func _finalize() -> void:
	_entry.stop()
