extends RefCounted

const ContainerFragmentResource = preload(
	"res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd"
)
const FragmentComposition = preload(
	"res://Framework/Env/Setup/fragment_composition.gd"
)
const ContentComposition = preload(
	"res://Framework/Env/Setup/content_composition.gd"
)
const LIBRARIES: Array[String] = [
	"res://Framework/Content/Authored/Entity/",
	"res://Framework/Content/Authored/Items/",
	"res://Framework/Content/Authored/Objects/",
]


# Resource selections retain their authored order; starting overrides apply last.
static func define(
	preset_id: StringName,
	fragments: Array[ContainerFragmentResource],
	overrides: Dictionary = {}
) -> Dictionary:
	if preset_id == &"":
		return _failure("Starting attribute ID cannot be empty.")
	var override_error := ContainerFragmentResource.container_error(overrides)
	if not override_error.is_empty():
		return _failure("Invalid starting overrides: %s" % override_error)
	for index in fragments.size():
		var fragment := fragments[index]
		if fragment == null:
			return _failure("Missing starting fragment resource at index %d." % index)
		var resource_path := fragment.resource_path
		if (
			resource_path.get_extension() != "tres"
			or resource_path.contains("\\")
			or resource_path.contains("::")
			or resource_path.simplify_path() != resource_path
			or not _inside_library(resource_path)
		):
			return _failure(
				"Expected an external .tres fragment inside the authored library: %s"
				% resource_path
			)
		if not FileAccess.file_exists(resource_path):
			return _failure("Fragment resource does not exist: %s" % resource_path)
	var composed := FragmentComposition.compose_resources(fragments)
	if not composed["ok"]:
		return composed
	var parts: Array[Dictionary] = [composed["value"], overrides]
	return {"id": preset_id, "containers": ContentComposition.combine(parts)}


static func _inside_library(resource_path: String) -> bool:
	for root in LIBRARIES:
		if resource_path.begins_with(root):
			return true
	return false


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
