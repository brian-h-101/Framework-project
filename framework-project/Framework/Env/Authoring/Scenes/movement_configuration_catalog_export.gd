extends SceneTree

const Catalog = preload(
	"res://Framework/Env/Authoring/Scenes/movement_configuration_catalog.gd"
)


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var result: Dictionary
	if arguments.is_empty():
		result = Catalog.read()
	else:
		result = {"ok": false, "value": null, "error": "Movement catalogue expects no arguments."}
	print("[movement-configurations] ", JSON.stringify(result))
	quit(0 if result["ok"] else 1)
