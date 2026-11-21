extends "res://Framework/Infrastructure/API/Runtime/game_setup.gd"

const Effects = preload("res://Framework/Infrastructure/Implementation/Gameplay/Executors/attribute_effects_executor.gd")
const Executor = preload("res://Framework/Infrastructure/API/Gameplay/Executors/gameplay_executor.gd")

class HealthExecutor extends Executor:
	var calls := 0

	func describe() -> Dictionary:
		return {"label": "Direct Health", "description": "Set target health using a typed argument.",
			"supports_effects": false, "arguments": [
				{"name": "amount", "allowed_types": ["int", "float"], "required": true},
				{"name": "note", "allowed_types": ["String"], "required": false}]}

	func execute(context: ExecutionContext, _definition: Dictionary, bindings: Dictionary, arguments: Dictionary) -> Dictionary:
		calls += 1
		return context.write_attribute(bindings[&"target"], &"health", ["current"], arguments[&"amount"])

class NamedExecutor extends Executor:
	func describe() -> Dictionary:
		return {"arguments": [{"name": "name", "allowed_types": ["StringName"], "required": true}]}

var health: HealthExecutor
var content_calls := 0
var entity_calls := 0


func register_executors(runtime: GameRuntime) -> Dictionary:
	health = HealthExecutor.new()
	var registered := runtime.register_executor(&"direct_health", health)
	if not registered["ok"]:
		return registered
	registered = runtime.register_executor(&"named", NamedExecutor.new())
	return runtime.register_executor(&"diagnostic_effects", Effects.new()) if registered["ok"] else registered


func register_content(_runtime: GameRuntime) -> Dictionary:
	content_calls += 1
	return {"ok": true, "value": true, "error": ""}


func create_entities(_runtime: GameRuntime) -> Dictionary[StringName, int]:
	entity_calls += 1
	return {}
