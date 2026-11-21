extends RefCounted

const ExecutionContext = preload(
	"res://Framework/Infrastructure/API/Gameplay/Executors/execution_context.gd"
)


func describe() -> Dictionary:
	return {"label": "", "description": "", "supports_effects": false, "arguments": []}


func execute(
	_context: ExecutionContext,
	_definition: Dictionary,
	_bindings: Dictionary,
	_arguments: Dictionary
) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": "Gameplay executor execute() is not implemented.",
	}
