extends RefCounted

const PolygonOccluder = preload(
	"res://Framework/Env/Lighting/polygon_occluder_2d.gd"
)
const SDFDebugShader = preload(
	"res://Framework/Env/Lighting/Shadows/shadow_sdf_debug.gdshader"
)


static func build_casters(map_root: Node) -> int:
	var nodes: Array[Node] = [map_root]
	nodes.append_array(map_root.find_children("*", "", true, false))

	var created: int = 0

	for source in nodes:
		if not bool(source.get_meta(&"casts_shadow", false)):
			continue

		if not (source is Polygon2D):
			push_error(
				"Automatic shadows currently require Polygon2D: %s"
				% source.name
			)
			continue

		if source.get_node_or_null("ShadowCaster") != null:
			continue

		var caster := PolygonOccluder.new()
		caster.name = &"ShadowCaster"
		source.add_child(caster)
		created += 1

	return created


static func configure_receivers(
	map_root: Node,
	profile: Dictionary
) -> int:
	var material: ShaderMaterial = null

	if bool(profile.get("debug_sdf", false)):
		material = ShaderMaterial.new()
		material.shader = SDFDebugShader

	var nodes: Array[Node] = [map_root]
	nodes.append_array(map_root.find_children("*", "", true, false))

	var configured: int = 0

	for receiver in nodes:
		if not bool(receiver.get_meta(&"receives_shadow", false)):
			continue

		var surface := receiver as CanvasItem
		if surface == null:
			push_error(
				"Shadow receiver requires CanvasItem: %s"
				% receiver.name
			)
			continue

		surface.material = material
		configured += 1

	return configured

static func configure_viewport(
	viewport: Viewport,
	profile: Dictionary
) -> void:
	var sdf_scale: Viewport.SDFScale = profile["sdf_scale"]
	viewport.sdf_scale = sdf_scale

	print("[shadows] SDF scale enum: ", viewport.sdf_scale)
