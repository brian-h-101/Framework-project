extends RefCounted

const AttributeConnector = preload(
	"res://Framework/Infrastructure/Implementation/Entity/attribute_connector.gd"
)
const EffectExecutor = preload(
	"res://Framework/Infrastructure/Implementation/Gameplay/effect_executor.gd"
)

var _connector: AttributeConnector
var _effect_executor: EffectExecutor


func _init(
	connector: AttributeConnector,
	effect_executor: EffectExecutor
) -> void:
	_connector = connector
	_effect_executor = effect_executor


func execute(
	definition: Dictionary,
	bindings: Dictionary,
	arguments: Dictionary
) -> Dictionary:
	var values: Array = []

	for effect in definition["effects"]:
		var role := StringName(effect["entity"])
		var argument_name := StringName(effect["value_from"])

		if not bindings.has(role):
			return _failure("Missing entity binding: %s" % role)

		if not arguments.has(argument_name):
			return _failure("Missing action argument: %s" % argument_name)

		var entity_id: int = bindings[role]
		var address := _connector.make_reference(
			entity_id,
			effect["container"],
			effect["path"]
		)

		var result := _effect_executor.execute(
			effect["operation"],
			address,
			arguments[argument_name]
		)

		if not result.ok:
			return result

		values.append(result.value)

	return {"ok": true, "value": values, "error": ""}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
