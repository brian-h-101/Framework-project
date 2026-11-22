extends RefCounted

const Values = preload("res://Framework/Env/Authoring/Shared/resource_values.gd")
const Defaults = preload("res://Framework/Content/Configuration/Map/scene_defaults.tres")
const Ground = preload("res://Framework/Content/Universal/Map/based/Rendering2D/tile_map_layer_2d.gd")
const Lighting = preload("res://Framework/Content/Universal/Lighting/based/Rendering2D/lighting_2d.gd")


static func create(template: String, node_name: String, root_type: Variant, definition_id: String = "") -> Dictionary:
	var root: Node
	match template:
		"map_2d", "empty_2d":
			root = Node2D.new()
		"empty_3d":
			root = Node3D.new()
		"control":
			root = Control.new()
			_unshaded(root)
		"hud":
			var canvas := CanvasLayer.new()
			canvas.layer = 10
			root = canvas
			var control := Control.new()
			control.name = &"Root"
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
			control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_unshaded(control)
			root.add_child(control)
			control.owner = root
		"presentation", "entity_presentation":
			if not root_type is String or not ClassDB.class_exists(root_type) or not ClassDB.is_parent_class(root_type, "Node") or not ClassDB.can_instantiate(root_type) or ClassDB.class_get_api_type(root_type) != ClassDB.API_CORE:
				return Values.failure("Choose an instantiable native Node type.")
			root = ClassDB.instantiate(root_type) as Node
		_:
			return Values.failure("Unknown scene template.")
	root.name = StringName(node_name)
	if template == "entity_presentation":
		root.set_meta(&"entity_definition", StringName(definition_id))
	if template == "map_2d":
		var checked := Defaults.read()
		if not checked["ok"]:
			root.free()
			return checked
		var ground := Ground.new()
		ground.name = &"Ground"
		ground.z_index = -1
		ground.content = checked["value"]["ground_content"]
		ground.set_meta(&"receives_shadow", true)
		root.add_child(ground)
		ground.owner = root
		var lighting := Lighting.new()
		lighting.name = &"Lighting"
		lighting.content = checked["value"]["lighting_content"]
		root.add_child(lighting)
		lighting.owner = root
	var scene := PackedScene.new()
	var error := scene.pack(root)
	root.free()
	return Values.success(scene) if error == OK else Values.failure("Could not pack the new scene.")


static func _unshaded(control: Control) -> void:
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	control.material = material
