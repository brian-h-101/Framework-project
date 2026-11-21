extends SceneTree

const SpatialRoot2D = preload(
	"res://Framework/Env/Map/spatial_root_2d.gd"
)

var _entity: Node
var _passed: bool = true


func _initialize() -> void:
	_entity = Node.new()
	_entity.set_meta(&"entity_key", &"player")

	var rig := Node.new()
	rig.name = &"PresentationRig"
	_entity.add_child(rig)

	var body := CharacterBody2D.new()
	body.name = &"MovingBody"
	body.set_meta(SpatialRoot2D.ROOT_META, true)
	rig.add_child(body)

	var discovered := SpatialRoot2D.find_for(_entity)
	_expect("Finds moving body before tree entry", (
		not _entity.is_inside_tree()
		and discovered["ok"]
		and discovered["value"] == body
	))

	rig.name = &"RenamedRig"
	body.name = &"RenamedBody"

	var renamed := SpatialRoot2D.find_for(_entity)
	_expect("Names do not affect discovery", (
		renamed["ok"] and renamed["value"] == body
	))

	body.set_meta(SpatialRoot2D.ROOT_META, false)

	var disabled := SpatialRoot2D.find_for(_entity)
	_expect("Entity without an enabled spatial root is valid", (
		disabled["ok"] and disabled["value"] == null
	))

	var nested_entity := Node.new()
	nested_entity.set_meta(&"entity_key", &"enemy")
	_entity.add_child(nested_entity)

	var nested_body := Node2D.new()
	nested_body.set_meta(SpatialRoot2D.ROOT_META, true)
	nested_entity.add_child(nested_body)

	var scoped := SpatialRoot2D.find_for(_entity)
	_expect("Nested placed entity is excluded", (
		scoped["ok"] and scoped["value"] == null
	))

	var nested_result := SpatialRoot2D.find_for(nested_entity)
	_expect("Nested entity finds its own spatial root", (
		nested_result["ok"]
		and nested_result["value"] == nested_body
	))

	nested_entity.remove_meta(&"entity_key")
	nested_entity.set_meta(&"entity_definition", &"enemy")

	var authored_scope := SpatialRoot2D.find_for(_entity)
	_expect("Nested authored entity is excluded", (
		authored_scope["ok"] and authored_scope["value"] == null
	))

	body.set_meta(SpatialRoot2D.ROOT_META, true)

	var duplicate := Node2D.new()
	duplicate.set_meta(SpatialRoot2D.ROOT_META, true)
	rig.add_child(duplicate)

	var ambiguous := SpatialRoot2D.find_for(_entity)
	_expect("Duplicate spatial roots are rejected", (
		not ambiguous["ok"]
		and String(ambiguous["error"]).contains("Multiple")
	))
	duplicate.free()

	var wrong_type := Node.new()
	wrong_type.set_meta(SpatialRoot2D.ROOT_META, true)
	rig.add_child(wrong_type)

	var invalid_type := SpatialRoot2D.find_for(_entity)
	_expect("Spatial root must be Node2D", (
		not invalid_type["ok"]
		and String(invalid_type["error"]).contains("must be Node2D")
	))
	wrong_type.free()

	body.set_meta(SpatialRoot2D.ROOT_META, "yes")

	var invalid_flag := SpatialRoot2D.find_for(_entity)
	_expect("Marker flag must be boolean", (
		not invalid_flag["ok"]
		and String(invalid_flag["error"]).contains("must be a bool")
	))

	var standalone := Node2D.new()
	standalone.set_meta(&"entity_definition", &"player")
	standalone.set_meta(SpatialRoot2D.ROOT_META, true)

	var self_result := SpatialRoot2D.find_for(standalone)
	_expect("Entity root itself can own the position", (
		self_result["ok"] and self_result["value"] == standalone
	))
	standalone.free()

	var invalid_entity := SpatialRoot2D.find_for(null)
	_expect("Invalid entity is rejected", (
		not invalid_entity["ok"]
		and String(invalid_entity["error"]).contains("Entity node is invalid")
	))

	_check_authored_scenes()

	print("[spatial-root] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _expect(description: String, condition: bool) -> void:
	_passed = _passed and condition
	print("[spatial-root] %s: %s" % [description, condition])


func _finalize() -> void:
	if is_instance_valid(_entity):
		_entity.free()

	_entity = null


func _check_authored_scenes() -> void:
	var fixtures: Dictionary = {
		"res://Framework/Content/Presentation/Entity/Player/player_2d.tscn": ["."],
		"res://Framework/Content/Presentation/Entity/Enemy/enemy_2d.tscn": ["."],
		"res://Framework/Content/Presentation/Entity/TownGuard/town_guard_2d.tscn": ["."],
		"res://Framework/Content/Maps/city.tscn": [
			"Player",
			"Enemy",
			"TownGuard01",
		],
	}

	for scene_path in fixtures:
		var scene := ResourceLoader.load(String(scene_path)) as PackedScene
		if scene == null or not scene.can_instantiate():
			_expect("Scene loads: %s" % scene_path, false)
			continue

		var scene_root := scene.instantiate()
		if scene_root == null:
			_expect("Scene instantiates: %s" % scene_path, false)
			continue

		for entity_path in fixtures[scene_path]:
			var entity_node := scene_root.get_node_or_null(NodePath(entity_path))
			var found := SpatialRoot2D.find_for(entity_node)

			_expect("Authored spatial root: %s:%s" % [
				scene_path, entity_path,
			], (
				found["ok"]
				and found["value"] != null
				and found["value"] == entity_node.get_node_or_null("View2D")
			))

		scene_root.free()
