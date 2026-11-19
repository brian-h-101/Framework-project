extends CanvasLayer

const MaskShader = preload(
	"res://Framework/Env/Lighting/Shadows/shared_shadow_2d.gdshader"
)

const MAX_POINT_LIGHTS: int = 8

var _lights_root: Node
var _profile: Dictionary = {}
var _sun: DirectionalLight2D
var _point_lights: Array[PointLight2D] = []
var _material: ShaderMaterial


func configure(lights_root: Node, profile: Dictionary) -> void:
	_lights_root = lights_root
	_profile = profile


func _ready() -> void:
	if not is_instance_valid(_lights_root):
		push_error("Shared shadow overlay has no lighting source.")
		set_process(false)
		return

	layer = 5
	follow_viewport_enabled = false
	process_priority = 50

	for child in _lights_root.get_children():
		if child is DirectionalLight2D:
			_sun = child as DirectionalLight2D
		elif child is PointLight2D:
			_point_lights.append(child as PointLight2D)

	if _point_lights.size() > MAX_POINT_LIGHTS:
		push_error("Shared shadow overlay supports at most 8 point lights.")
		set_process(false)
		return

	_material = ShaderMaterial.new()
	_material.shader = MaskShader

	_material.set_shader_parameter(
		&"density", float(_profile["density"])
	)
	_material.set_shader_parameter(
		&"debug_mask", bool(_profile["debug_shadow_mask"])
	)

	var blend: Dictionary = _profile["blend"]

	_material.set_shader_parameter(
		&"shadows_enabled", bool(_profile["shadow_enabled"])
	)
	_material.set_shader_parameter(
		&"debug_channels", bool(_profile["debug_shadow_channels"])
	)
	_material.set_shader_parameter(
		&"shadow_length_px", float(blend["length_px"])
	)
	_material.set_shader_parameter(
		&"fade_px", float(blend["fade_px"])
	)
	_material.set_shader_parameter(
		&"softness_px", float(blend["softness_px"])
	)

	var surface := ColorRect.new()
	surface.name = &"Mask"
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.material = _material
	add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_refresh_sources()

	print("[shadows] Shared overlay ready. Density: ",
		float(_profile["density"]),
		", sun: ", is_instance_valid(_sun),
		", point lights: ", _point_lights.size())


func _process(_delta: float) -> void:
	_refresh_sources()


func _refresh_sources() -> void:
	var sun_active: bool = (
		is_instance_valid(_sun)
		and _sun.enabled
		and _sun.is_visible_in_tree()
		and _sun.energy > 0.0
	)

	var direction := Vector2.UP

	if sun_active:
		direction = -_sun.get_global_transform_with_canvas().y.normalized()

	_material.set_shader_parameter(&"sun_enabled", sun_active)
	_material.set_shader_parameter(&"sun_direction", direction)

	var light_data: Array[Vector3] = []
	light_data.resize(MAX_POINT_LIGHTS)
	light_data.fill(Vector3.ZERO)

	var count: int = 0

	for light in _point_lights:
		if not is_instance_valid(light):
			continue

		if not light.enabled or not light.is_visible_in_tree():
			continue

		if light.energy <= 0.0 or light.texture == null:
			continue

		var screen_transform := light.get_global_transform_with_canvas()
		var screen_position := screen_transform.origin
		var radius_px: float = (
			float(light.texture.get_width())
			* absf(light.texture_scale)
			* screen_transform.x.length()
			* 0.5
		)

		light_data[count] = Vector3(
			screen_position.x,
			screen_position.y,
			radius_px
		)
		count += 1

	_material.set_shader_parameter(&"point_count", count)
	_material.set_shader_parameter(&"point_lights", light_data)


func _exit_tree() -> void:
	_lights_root = null
	_sun = null
	_point_lights.clear()
	_material = null
	_profile = {}
