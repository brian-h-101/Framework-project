extends RefCounted

const GameRuntime = preload("res://Framework/Infrastructure/API/Runtime/game_runtime.gd")
const PlayerContent = preload(
	"res://Framework/Content/Authored/Entity/Player/player.gd"
)
const EnemyContent = preload(
	"res://Framework/Content/Authored/Entity/Enemy/enemy.gd"
)


static func define(game: GameRuntime) -> void:
	PlayerContent.define(game)
	EnemyContent.define(game)
