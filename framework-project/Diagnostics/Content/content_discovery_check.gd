extends SceneTree

const ActionContent = preload(
	"res://Framework/Env/Setup/Definitions/actions.gd"
)
const InteractionContent = preload(
	"res://Framework/Env/Setup/Definitions/interactions.gd"
)
const EntityContent = preload(
	"res://Framework/Env/Setup/Definitions/entity_definitions.gd"
)

func _initialize() -> void:
	var passed := true

	for folder_name in ["Action", "Interaction"]:
		var result: Dictionary = {}

		if folder_name == "Action":
			result = ActionContent.definitions()
		else:
			result = InteractionContent.definitions()

		if not result["ok"]:
			push_error(String(result["error"]))
			quit(1)
			return

		var definitions: Array[Dictionary] = result["value"]
		var discovered_ids: Array[StringName] = []

		for definition in definitions:
			discovered_ids.append(StringName(definition["id"]))

		print(
			"[discovery] %s IDs: %s"
			% [folder_name, discovered_ids]
		)

		if folder_name == "Action":
			var source_path: String = result["sources"].get(
				&"change_health",
				""
			)

			print("[discovery] Action source: ", source_path)

			passed = (
				passed
				and discovered_ids.has(&"change_health")
				and source_path
				== "res://Framework/Content/Behavior/Action/change_health.tres"
			)
		else:
			var interaction_source_path: String = result["sources"].get(
				&"strike",
				""
			)

			print(
				"[discovery] Interaction source: ",
				interaction_source_path
			)

			passed = (
				passed
				and discovered_ids.has(&"strike")
				and interaction_source_path
				== "res://Framework/Content/Behavior/Interaction/strike.tres"
			)

	var entity_result := EntityContent.definitions()

	if not entity_result["ok"]:
		push_error(String(entity_result["error"]))
		quit(1)
		return

	var entity_definitions: Array[Dictionary] = entity_result["value"]
	var entity_ids: Array[StringName] = []

	for definition in entity_definitions:
		entity_ids.append(StringName(definition["id"]))

	print("[discovery] Entity IDs: ", entity_ids)

	passed = (
		passed
		and entity_ids.has(&"player")
		and entity_ids.has(&"enemy")
	)
	print("[discovery] Checks passed: ", passed)
	quit(0 if passed else 1)
