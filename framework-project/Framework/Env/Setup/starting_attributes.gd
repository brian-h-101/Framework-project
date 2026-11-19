extends RefCounted

const ROOT := "res://Framework/Content/Authored/Entity/"
const AUTHORED_ROOT := "res://Framework/Content/Authored/"
const LIBRARY_PREFIXES: Array[String] = [
	"Entity/",
	"Items/",
	"Objects/",
]

const FragmentComposition = preload(
	"res://Framework/Env/Setup/fragment_composition.gd"
)
const ContentComposition = preload(
	"res://Framework/Content/Authored/Entity/Shared/content_composition.gd"
)


# The authored order is preserved; starting overrides are applied last.
static func define(
	preset_id: StringName,
	fragments: Array[String],
	overrides: Dictionary = {}
) -> Dictionary:
	var paths := PackedStringArray()

	for fragment in fragments:
		var library_root: String = ROOT

		for prefix: String in LIBRARY_PREFIXES:
			if fragment.begins_with(prefix):
				library_root = AUTHORED_ROOT
				break

		var path: String = library_root.path_join(fragment).simplify_path()
		if not path.begins_with(library_root) or path.get_extension() != "gd":
			return {
				"ok": false,
				"value": null,
				"error": (
					"Expected a .gd fragment inside the authored library: %s"
					% fragment
				),
			}

		paths.append(path)

	var composed := FragmentComposition.compose_paths(paths)
	if not composed["ok"]:
		return composed

	var selected: Dictionary = composed["value"]
	var parts: Array[Dictionary] = [selected, overrides]
	var containers := ContentComposition.combine(parts)

	return {
		"id": preset_id,
		"containers": containers,
	}