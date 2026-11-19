extends SceneTree

const PresetData = preload(
	"res://Diagnostics/Fixtures/starting_attributes_access.gd"
)

const PlayerAttributes = preload(
	"res://Framework/Content/Presentation/Entity/Player/starting_attributes.gd"
)
const PlayerBaseline = preload(
	"res://Diagnostics/Fixtures/player_attributes_baseline.gd"
)
const EnemyAttributes = preload(
	"res://Framework/Content/Presentation/Entity/Enemy/starting_attributes.gd"
)
const EnemyBaseline = preload(
	"res://Diagnostics/Fixtures/enemy_attributes_baseline.gd"
)
const ContentDiscovery = preload(
	"res://Framework/Env/Setup/content_discovery.gd"
)
const Precognition = preload(
	"res://Framework/Content/Authored/Entity/Attributes/Abilities/precognition.gd"
)
const Reflex = preload(
	"res://Framework/Content/Authored/Entity/Attributes/Abilities/reflex.gd"
)
const Health = preload(
	"res://Framework/Content/Authored/Entity/Attributes/Statistics/health.gd"
)
const Speed = preload(
	"res://Framework/Content/Authored/Entity/Attributes/Statistics/speed.gd"
)
const TownGuardAttributes = preload(
	"res://Framework/Content/Presentation/Entity/TownGuard/starting_attributes.gd"
)


func _initialize() -> void:
	var player_result := PresetData.category(PlayerAttributes, &"player", "Attributes")

	if not player_result["ok"]:
		push_error(String(player_result["error"]))
		quit(1)
		return

	var player_actual: Dictionary[StringName, Dictionary] = player_result["value"]
	var player_expected := PlayerBaseline.defaults()
	var player_matches: bool = player_actual == player_expected

	var enemy_result := PresetData.category(EnemyAttributes, &"enemy", "Attributes")

	if not enemy_result["ok"]:
		push_error(String(enemy_result["error"]))
		quit(1)
		return

	var enemy_actual: Dictionary[StringName, Dictionary] = enemy_result["value"]
	var enemy_expected := EnemyBaseline.defaults()
	var enemy_matches: bool = enemy_actual == enemy_expected

	var guard_result := PresetData.category(TownGuardAttributes, &"town_guard", "Attributes")
	if not guard_result["ok"]:
		push_error(String(guard_result["error"]))
		quit(1)
		return

	var guard_actual: Dictionary[StringName, Dictionary] = guard_result["value"]

	var statistics_preserved: bool = (
		player_actual[&"health"] == {"current": 150, "maximum": 150}
		and player_actual[&"speed"] == {"current": 20, "maximum": 50}
		and enemy_actual[&"health"] == {"current": 100, "maximum": 100}
		and enemy_actual[&"speed"] == {"current": 10, "maximum": 50}
		and guard_actual[&"health"] == {"current": 100, "maximum": 100}
		and guard_actual[&"speed"] == {"current": 20, "maximum": 50}
	)

	var shared_statistics_unchanged: bool = (
		Health.defaults()[&"health"] == {"current": 100, "maximum": 100}
		and Speed.defaults()[&"speed"] == {"current": 20, "maximum": 50}
	)

	var ability_selections_preserved: bool = (
		player_actual[&"abilities"] == {"precognition": 5}
		and enemy_actual[&"abilities"] == {"reflex": 12}
	)

	var shared_defaults_unchanged: bool = (
		Precognition.defaults()[&"abilities"] == {"precognition": 0}
		and Reflex.defaults()[&"abilities"] == {"reflex": 0}
	)

	var rejected := ContentDiscovery.definitions_in(
		"res://Diagnostics/Fixtures/FragmentFailure"
	)
	var error_message := String(rejected["error"])

	var failure_preserved: bool = (
		not rejected["ok"]
		and error_message.contains("Fragment folder does not exist:")
		and error_message.contains("/FragmentFailure/Missing")
		and error_message.contains("failing_definition.gd")
	)

	print("[fragments] Player matches baseline: ", player_matches)
	print("[fragments] Player health: ", player_actual[&"health"]["current"])
	print("[fragments] Enemy matches baseline: ", enemy_matches)
	print("[fragments] Enemy health: ", enemy_actual[&"health"]["current"])
	print("[fragments] Enemy speed: ", enemy_actual[&"speed"])
	print("[fragments] Enemy reflex: ", enemy_actual[&"abilities"]["reflex"])
	print("[fragments] Rejected definition: ", rejected)
	print("[fragments] Composition failure preserved: ", failure_preserved)

	print("[fragments] Ability selections preserved: ",
		ability_selections_preserved)
	print("[fragments] Shared ability defaults unchanged: ",
		shared_defaults_unchanged)

	print("[fragments] Statistics preserved: ", statistics_preserved)
	print("[fragments] Shared statistics defaults unchanged: ",
		shared_statistics_unchanged)

	var passed: bool = (
		player_matches
		and enemy_matches
		and failure_preserved
		and ability_selections_preserved
		and shared_defaults_unchanged
		and statistics_preserved
		and shared_statistics_unchanged
	)

	print("[fragments] Checks passed: ", passed)
	quit(0 if passed else 1)
