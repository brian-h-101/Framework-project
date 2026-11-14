extends "res://Framework/Runtime/game_setup.gd"

const EntityContent = preload(
	"res://Framework/Content/Authored/Entity/entities.gd"
)
const ChangeHealth = preload(
	"res://Framework/Content/Action/change_health.gd"
)
const Strike = preload(
	"res://Framework/Content/Interaction/strike.gd"
)


func register_content(runtime: GameRuntime) -> void:
	EntityContent.define(runtime)
	runtime.define_action(ChangeHealth.definition())
	runtime.define_interaction(Strike.definition())


func create_entities(
	runtime: GameRuntime
) -> Dictionary[StringName, int]:
	var player_id := runtime.spawn(&"player", {
		&"health": {"current": 75},
		&"strength": {"current": 80},
	})
	var second_player_id := runtime.spawn(&"player")
	var enemy_id := runtime.spawn(&"enemy")

	return {
		&"player": player_id,
		&"second_player": second_player_id,
		&"enemy": enemy_id,
	}
