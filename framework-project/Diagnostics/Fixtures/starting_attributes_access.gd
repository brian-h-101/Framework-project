extends RefCounted

const Baseline = preload(
	"res://Diagnostics/Fixtures/entity_starting_baseline.gd"
)


static func category(
	preset: Resource,
	preset_id: StringName,
	category_name: String
) -> Dictionary:
	var definition: Dictionary = preset.call(&"to_definition")
	if definition.get("ok", true) == false:
		return definition

	var containers: Dictionary = definition["containers"]
	var expected := Baseline.category(preset_id, category_name)
	var selected: Dictionary[StringName, Dictionary] = {}
	for container_id in expected:
		if containers.has(container_id):
			selected[container_id] = containers[container_id].duplicate(true)

	return {"ok": true, "value": selected, "error": ""}
