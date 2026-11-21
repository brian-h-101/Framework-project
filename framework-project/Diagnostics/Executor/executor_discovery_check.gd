extends SceneTree

const Paths = preload(
	"res://Framework/Env/Setup/library_path_policy.gd"
)


func _initialize() -> void:
	var scripts := Paths.paths_in(
		"res://Framework/Content/Executor",
		"gd"
	)
	var actions := Paths.paths_in(
		"res://Framework/Content/Behavior/Action"
	)

	print("[executor-discovery] Script paths: ", scripts)
	print("[executor-discovery] Default resource paths: ", actions)

	var passed: bool = (
		scripts["ok"]
		and actions["ok"]
		and scripts["value"].has(
			"res://Framework/Content/Executor/change_health_executor.gd"
		)
		and actions["value"].has(
			"res://Framework/Content/Behavior/Action/change_health.tres"
		)
		and not actions["value"].has(
			"res://Framework/Content/Behavior/Action/actions.gd"
		)
	)

	print("[executor-discovery] Checks passed: ", passed)
	quit(0 if passed else 1)