extends SceneTree

const GameRuntime = preload(
	"res://Framework/Runtime/game_runtime.gd"
)
const ExampleGameSetup = preload(
	"res://Games/ExampleGame/game_setup.gd"
)

func _initialize() -> void:
	var game := GameRuntime.new()
	var setup := ExampleGameSetup.new()
	setup.register_content(game)
	var entity_ids := setup.create_entities(game)
	var player_id: int = entity_ids[&"player"]
	var enemy_id: int = entity_ids[&"enemy"]

	_show_attribute_writes(game, player_id, enemy_id)
	_show_effects(game, player_id, enemy_id)
	_show_interactions(game, player_id, enemy_id)
	_show_requirements(game, player_id, enemy_id)

	game.print_entities()
	_show_attribute_reads(game, player_id, enemy_id)
	var comparison := game.compare_attributes(
		player_id, &"abilities", ["precognition"],
		">=",
		enemy_id, &"abilities", ["reflex"]
	)
	print("[connector] Precognition >= reflex: ", comparison)
	quit()


func _show_attribute_reads(game: GameRuntime, player_id: int, enemy_id: int) -> void:
	var results := {
		"Player precognition": game.read_attribute(player_id, &"abilities", ["precognition"]),
		"Enemy reflex": game.read_attribute(enemy_id, &"abilities", ["reflex"]),
		"Player survival rank": game.read_attribute(player_id, &"skills", ["survival", "rank"]),
		"Player injury severity": game.read_attribute(player_id, &"injuries", ["active", 0, "severity"]),
		"Player met_guard flag": game.read_attribute(player_id, &"narrative", ["met_guard"]),
		"Player main-hand slot": game.read_attribute(player_id, &"equipment", ["slots", "main_hand"]),
		"Missing player ability": game.read_attribute(player_id, &"abilities", ["missing_ability"]),
	}
	for label in results:
		print("[connector] %s: %s" % [label, results[label]])

func _show_attribute_writes(game: GameRuntime, player_id: int, enemy_id: int) -> void:
	print("[write] Enemy health before: ",
		game.read_attribute(enemy_id, &"health", ["current"]))

	print("[write] Enemy health update: ",
		game.write_attribute(enemy_id, &"health", ["current"], 90))

	print("[write] Enemy health after: ",
		game.read_attribute(enemy_id, &"health", ["current"]))

	print("[write] Survival before: ",
		game.read_attribute(player_id, &"skills", ["survival"]))

	print("[write] Survival rank update: ",
		game.write_attribute(player_id, &"skills", ["survival", "rank"], 3))

	print("[write] Survival after: ",
		game.read_attribute(player_id, &"skills", ["survival"]))

	print("[write] Missing skill update: ",
		game.write_attribute(player_id, &"skills", ["survival", "missing"], 99))

	print("[write] Survival after rejected update: ",
		game.read_attribute(player_id, &"skills", ["survival"]))


func _show_effects(
	game: GameRuntime,
	player_id: int,
	enemy_id: int
) -> void:
	print("[effect] Enemy health before: ",
		game.read_attribute(enemy_id, &"health", ["current"]))

	print("[effect] Subtract 10 health: ",
		game.execute_effect(
			&"add", enemy_id, &"health", ["current"], -10
		))

	print("[effect] Enemy health after: ",
		game.read_attribute(enemy_id, &"health", ["current"]))

	print("[effect] Set met_guard: ",
		game.execute_effect(
			&"set", player_id, &"narrative", ["met_guard"], true
		))

	print("[effect] Reject text amount: ",
		game.execute_effect(
			&"add", enemy_id, &"health", ["current"], "-10"
		))

	print("[effect] Health after rejected effect: ",
		game.read_attribute(enemy_id, &"health", ["current"]))



func _show_interactions(
	game: GameRuntime,
	player_id: int,
	enemy_id: int
) -> void:
	print("[interaction] Player available: ",
		game.read_attribute(player_id, &"interactions", ["available"]))

	print("[interaction] Enemy available: ",
		game.read_attribute(enemy_id, &"interactions", ["available"]))

	print("[interaction] Enemy health before: ",
		game.read_attribute(enemy_id, &"health", ["current"]))

	print("[interaction] Player strikes enemy: ",
		game.interact(&"strike", player_id, enemy_id))

	print("[interaction] Enemy health after: ",
		game.read_attribute(enemy_id, &"health", ["current"]))

	print("[interaction] Player health before rejected strike: ",
		game.read_attribute(player_id, &"health", ["current"]))

	print("[interaction] Enemy strikes player: ",
		game.interact(&"strike", enemy_id, player_id))

	print("[interaction] Player health after rejected strike: ",
		game.read_attribute(player_id, &"health", ["current"]))

func _show_requirements(
	game: GameRuntime,
	player_id: int,
	enemy_id: int
) -> void:
	print("[requirement] Enemy health before: ",
		game.read_attribute(enemy_id, &"health", ["current"]))

	print("[requirement] Set strength to 9: ",
		game.write_attribute(player_id, &"strength", ["current"], 9))

	print("[requirement] Strike at strength 9: ",
		game.interact(&"strike", player_id, enemy_id))

	print("[requirement] Enemy health after rejected strike: ",
		game.read_attribute(enemy_id, &"health", ["current"]))

	print("[requirement] Set strength to 10: ",
		game.write_attribute(player_id, &"strength", ["current"], 10))

	print("[requirement] Strike at strength 10: ",
		game.interact(&"strike", player_id, enemy_id))

	print("[requirement] Enemy health after permitted strike: ",
		game.read_attribute(enemy_id, &"health", ["current"]))

	print("[requirement] Strength after permitted strike: ",
		game.read_attribute(player_id, &"strength", ["current"]))
