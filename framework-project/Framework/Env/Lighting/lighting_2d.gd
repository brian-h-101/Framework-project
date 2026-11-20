extends Node2D

const GameRuntime = preload(
	"res://Framework/Infrastructure/API/Runtime/game_runtime.gd"
)
const ShadowSystem2D = preload(
	"res://Framework/Env/Lighting/Shadows/shadow_system_2d.gd"
)
const SharedShadow2D = preload(
	"res://Framework/Env/Lighting/Shadows/shared_shadow_2d.gd"
)
const Configuration = preload("res://Framework/Env/Configuration/Resources/lighting_2d_resource.gd")

@export var content: Configuration

var _ambient: CanvasModulate
var _sun: DirectionalLight2D
var _runtime: GameRuntime
var _cycle: Dictionary = {}
var _shadow_profile: Dictionary = {}
var _map_root: Node

func configure_runtime(runtime: GameRuntime) -> void:
	_runtime = runtime

func configure_map(map_root: Node) -> void:
	_map_root = map_root

	var created := ShadowSystem2D.build_casters(map_root)
	print("[shadows] Created casters: ", created)

func _ready() -> void:
	if content == null:
		push_error("Lighting environment has no content definition.")
		set_process(false)
		return

	var checked := content.read()
	if not checked["ok"]:
		push_error(checked["error"])
		set_process(false)
		return
	var definition: Dictionary = checked["value"]
	_shadow_profile = definition["shadows"]

	ShadowSystem2D.configure_viewport(
		get_viewport(),
		_shadow_profile
	)

	var receivers := ShadowSystem2D.configure_receivers(
		_map_root,
		_shadow_profile
	)
	print("[shadows] Configured receivers: ", receivers)

	_ambient = CanvasModulate.new()
	_ambient.name = &"Ambient"
	_ambient.color = definition["ambient_color"]
	add_child(_ambient)

	_build_point_lights(definition.get("point_lights", []))

	_cycle = definition.get("day_night", {})
	if _cycle.is_empty():
		print("[lighting] Ambient: ", _ambient.color)
		_build_shared_shadows()
		set_process(false)
		return

	if _runtime == null:
		push_error("Day/night lighting has no runtime context.")
		set_process(false)
		return

	_build_sun(_cycle["sun"])

	if _refresh_day_night():
		print("[lighting] Day/night cycle ready.")
		print("[lighting] Initial ambient: ", _ambient.color)

	_build_shared_shadows()


func _build_point_lights(definitions: Array) -> void:
	var light_texture := _create_light_texture()

	for definition in definitions:
		var light := PointLight2D.new()
		light.name = StringName(definition["id"])
		light.position = definition["position"]
		light.color = definition["color"]
		light.energy = float(definition["energy"])
		light.shadow_enabled = false
		light.texture = light_texture
		light.texture_scale = (
			float(definition["radius"]) * 2.0 / float(light_texture.width)
		)
		add_child(light)

	print("[lighting] Point lights: ", definitions.size())


func _create_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color.BLACK)

	var texture := GradientTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	return texture

func _process(_delta: float) -> void:
	if _runtime == null:
		return

	_refresh_day_night()


func _build_sun(definition: Dictionary) -> void:
	_sun = DirectionalLight2D.new()
	_sun.name = &"Sun"
	_sun.color = definition["color"]
	_sun.energy = 0.0
	_sun.shadow_enabled = false
	add_child(_sun)

func _refresh_day_night() -> bool:
	var result := _runtime.read_time()
	if not result.ok:
		push_error(result.error)
		set_process(false)
		return false

	var fraction: float = float(result.value["day_fraction"])
	var sunrise: float = float(_cycle["sunrise"])
	var sunset: float = float(_cycle["sunset"])
	var progress := clampf(
		(fraction - sunrise) / (sunset - sunrise),
		0.0,
		1.0
	)

	var daylight: float = 0.0
	if fraction >= sunrise and fraction < sunset:
		daylight = sin(progress * PI)

	var night_color: Color = _cycle["night_ambient"]
	var day_color: Color = _cycle["day_ambient"]
	_ambient.color = night_color.lerp(day_color, daylight)

	var sun: Dictionary = _cycle["sun"]
	_sun.energy = float(sun["maximum_energy"]) * daylight
	_sun.enabled = daylight > 0.0
	_sun.rotation_degrees = lerpf(
		float(sun["sunrise_angle"]),
		float(sun["sunset_angle"]),
		progress
	)

	return true

func _build_shared_shadows() -> void:
	if bool(_shadow_profile.get("debug_sdf", false)):
		return

	var overlay := SharedShadow2D.new()
	overlay.name = &"SharedShadows"
	overlay.configure(self, _shadow_profile)
	add_child(overlay)

func _exit_tree() -> void:
	_runtime = null
	_map_root = null
	_cycle = {}
	_shadow_profile = {}
