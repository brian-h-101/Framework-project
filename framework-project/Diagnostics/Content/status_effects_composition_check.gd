extends SceneTree

const PresetData = preload(
	"res://Diagnostics/Fixtures/Helpers/starting_attributes_access.gd"
)

const PlayerStatusEffects = preload(
	"res://Framework/Content/Gameplay/Presentation/Entity/Player/starting_attributes.tres"
)
const PlayerBaseline = preload(
	"res://Diagnostics/Fixtures/Baselines/player_status_effects_baseline.gd"
)
const EnemyStatusEffects = preload(
	"res://Framework/Content/Gameplay/Presentation/Entity/Enemy/starting_attributes.tres"
)
const EnemyBaseline = preload(
	"res://Diagnostics/Fixtures/Baselines/enemy_status_effects_baseline.gd"
)
const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const EnvironmentSetup = preload(
	"res://Framework/Env/Setup/Bootstrap/game_setup.gd"
)

var _entry := GameEntry.new()


func _initialize() -> void:
	var player_result := PresetData.category(PlayerStatusEffects, &"player", "StatusEffects")

	if not player_result["ok"]:
		push_error(String(player_result["error"]))
		quit(1)
		return

	var enemy_result := PresetData.category(EnemyStatusEffects, &"enemy", "StatusEffects")

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

	print("[status] Player matches baseline: ", player_matches)
	print("[status] Player StatusEffects containers: ", player_actual.size())
	print("[status] Enemy matches baseline: ", enemy_matches)
	print("[status] Enemy StatusEffects containers: ", enemy_actual.size())

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
		"[status] Player runtime matches baseline: ",
		player_runtime_matches
	)
	print(
		"[status] Enemy runtime matches baseline: ",
		enemy_runtime_matches
	)

	var passed: bool = (
		player_matches
		and enemy_matches
		and player_runtime_matches
		and enemy_runtime_matches
	)

	_entry.stop()

	print("[status] Checks passed: ", passed)
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
					"[status] %s mismatch at %s/%s: %s"
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