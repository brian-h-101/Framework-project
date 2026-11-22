extends SceneTree

const StartingAttributesResource = preload(
	"res://Framework/Infrastructure/API/Entity/Resources/starting_attributes_resource.gd"
)
const Presentation2DResource = preload(
	"res://Framework/Content/Universal/Presentation/based/Configuration/presentation_2d_resource.gd"
)
const StartingContent = preload(
	"res://Framework/Env/Setup/Definitions/starting_definitions.gd"
)
const ContainerFragmentResource = preload(
	"res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd"
)
const Movement2DProfile = preload(
	"res://Framework/Content/Gameplay/Profiles/Movement/Shared/movement_2d.tres"
)

const PROFILES := {
	"Entity/Enemy": &"enemy",
	"Entity/Player": &"player",
}

var _passed := true


func _initialize() -> void:
	var discovered := StartingContent.definitions()
	_check("Starting resources are discovered", discovered["ok"])
	if not discovered["ok"]:
		print(discovered)
		quit(1)
		return
	for relative_folder: String in PROFILES:
		var folder := "res://Framework/Content/Gameplay/Presentation/".path_join(relative_folder)
		var preset_path := folder.path_join("starting_attributes.tres")
		var preset := load(preset_path) as StartingAttributesResource
		_check("Starting attributes load: %s" % relative_folder, preset != null)
		if preset == null:
			continue
		var expected_id: StringName = PROFILES[relative_folder]
		_check("Fragment references use the resource schema: %s" % expected_id,
			preset.fragments.get_typed_script() == ContainerFragmentResource)
		_check("ID and source preserved: %s" % expected_id, (
			preset.id == expected_id
			and discovered["sources"].get(expected_id, "") == preset_path
		))
		var overrides_before := var_to_bytes(preset.overrides)
		var first := preset.to_definition()
		var second := preset.to_definition()
		var original_name: String = second["containers"][&"identity"]["name"]
		first["containers"][&"identity"]["name"] = "Changed only in this conversion"
		_check("Conversions own their containers: %s" % expected_id, (
			second["containers"][&"identity"]["name"] == original_name
			and preset.to_definition()["containers"][&"identity"]["name"] == original_name
			and var_to_bytes(preset.overrides) == overrides_before
		))

	var nested := StartingAttributesResource.new()
	nested.id = &"nested_probe"
	nested.overrides = {&"inventory": {"items": {"medicine": [1, 2]}}}
	var nested_definition := nested.to_definition()
	nested_definition["containers"][&"inventory"]["items"]["medicine"].append(3)
	_check("Nested override arrays stay independent", nested.overrides[&"inventory"]["items"]["medicine"] == [1, 2])
	_check("Empty IDs are rejected", not StartingAttributesResource.new().to_definition().get("ok", true))
	nested.overrides = {&"inventory": 1}
	_check("Malformed override containers are rejected", not nested.to_definition().get("ok", true))
	nested.overrides = {}
	nested.fragments = [null]
	var missing := nested.to_definition()
	_check("Missing fragment references are rejected", (
		not missing.get("ok", true)
		and String(missing.get("error", "")).contains("Missing starting fragment resource")
	))

	var defaults := Presentation2DResource.new().to_definition()
	_check("Shared presentation defaults have one resource schema", (
		defaults["body_size"] == Vector2(32, 32)
		and defaults["casts_shadow"] == true
		and defaults["movement_content"] == null
		and defaults["camera_scene"] == null
		and defaults["interaction_input"] == false
	))
	var invalid := Presentation2DResource.new()
	invalid.body_size = Vector2(0, 32)
	_check("Invalid presentation dimensions are rejected", not invalid.to_definition().get("ok", true))
	var presentation := Presentation2DResource.new()
	var camera := Camera2D.new()
	var camera_scene := PackedScene.new()
	_check("Test camera packs", camera_scene.pack(camera) == OK)
	camera.free()
	presentation.movement_content = Movement2DProfile
	presentation.camera_scene = camera_scene
	presentation.interaction_input = true
	var definition := presentation.to_definition()
	_check("Custom presentation retains movement, camera and input", (
		definition.get("movement_content") == Movement2DProfile
		and definition.get("camera_scene") == camera_scene
		and definition.get("interaction_input") == true
	))
	print("[profile-resource] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[profile-resource] ", label, ": ", passed)
	_passed = _passed and passed
