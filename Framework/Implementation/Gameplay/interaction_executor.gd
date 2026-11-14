extends RefCounted

const AttributeConnector = preload(
	"res://Framework/Implementation/Entity/attribute_connector.gd"
)
const ActionExecutor = preload(
	"res://Framework/Implementation/Gameplay/action_executor.gd"
)

var _connector: AttributeConnector
var _action_executor: ActionExecutor


func _init(
	connector: AttributeConnector,
	action_executor: ActionExecutor
) -> void:
	_connector = connector
	_action_executor = action_executor


func execute(
	definition: Dictionary,
	action_definition: Dictionary,
	actor_id: int,
	target_id: int
) -> Dictionary:
	var availability_address := _connector.make_reference(
		actor_id,
		&"interactions",
		["available"]
	)

	var availability := _connector.read(availability_address)
	if not availability.ok:
		return availability

	var available: Array = availability.value
	var interaction_id := StringName(definition["id"])

	if not available.has(interaction_id):
		return _failure(
			"Entity %s cannot invoke interaction: %s" % [
				actor_id,
				interaction_id,
			]
		)

	var bindings := {
		&"actor": actor_id,
		&"target": target_id,
	}

	var requirements := _check_requirements(definition, bindings)
	if not requirements.ok:
		return requirements

	return _action_executor.execute(
		action_definition,
		bindings,
		definition["arguments"]
	)

func _check_requirements(
	definition: Dictionary,
	bindings: Dictionary
) -> Dictionary:
	for requirement in definition.get("requirements", []):
		var role := StringName(requirement["entity"])

		if not bindings.has(role):
			return _failure(
				"Missing requirement entity binding: %s" % role
			)

		var entity_id: int = bindings[role]
		var address := _connector.make_reference(
			entity_id,
			requirement["container"],
			requirement["path"]
		)

		var comparison := _connector.compare(
			address,
			requirement["operator"],
			requirement["value"]
		)

		if not comparison.ok:
			return comparison

		if not comparison.value:
			var message: String = requirement.get(
				"message",
				"Interaction requirement not met."
			)
			return _failure(message)

	return {"ok": true, "value": true, "error": ""}

func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
