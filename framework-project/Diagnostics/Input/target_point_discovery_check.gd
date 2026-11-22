extends SceneTree

const TargetPoint2D = preload(
	"res://Framework/Content/Universal/Targeting/based/Spatial2D/target_point_2d.gd"
)

var _entity: Node
var _passed: bool = true


func _initialize() -> void:
	_entity = Node.new()
	_entity.set_meta(&"entity_key", &"player")

	var rig := Node.new()
	rig.name = &"PresentationRig"
	_entity.add_child(rig)

	var point := Marker2D.new()
	point.name = &"AimPoint"
	point.set_meta(TargetPoint2D.TARGET_META, true)
	rig.add_child(point)

	var discovered := TargetPoint2D.find_for(_entity)

	_expect("Finds nested marker before tree entry", (
		not _entity.is_inside_tree()
		and discovered["ok"]
		and discovered["value"] == point
	))

	rig.name = &"RenamedRig"
	point.name = &"RenamedPoint"

	var renamed := TargetPoint2D.find_for(_entity)

	_expect("Names do not affect discovery", (
		renamed["ok"]
		and renamed["value"] == point
	))

	point.set_meta(TargetPoint2D.TARGET_META, false)

	var disabled := TargetPoint2D.find_for(_entity)

	_expect("Disabled point is ignored", (
		not disabled["ok"]
		and String(disabled["error"]).contains("Missing")
	))

	var nested_entity := Node.new()
	nested_entity.set_meta(&"entity_key", &"enemy")
	_entity.add_child(nested_entity)

	var nested_point := Marker2D.new()
	nested_point.set_meta(TargetPoint2D.TARGET_META, true)
	nested_entity.add_child(nested_point)

	var scoped := TargetPoint2D.find_for(_entity)

	_expect("Nested entity point is excluded", (
		not scoped["ok"]
		and String(scoped["error"]).contains("Missing")
	))

	var nested_result := TargetPoint2D.find_for(nested_entity)

	_expect("Nested entity finds its own point", (
		nested_result["ok"]
		and nested_result["value"] == nested_point
	))

	point.set_meta(TargetPoint2D.TARGET_META, true)

	var duplicate := Marker2D.new()
	duplicate.set_meta(TargetPoint2D.TARGET_META, true)
	rig.add_child(duplicate)

	var ambiguous := TargetPoint2D.find_for(_entity)

	_expect("Duplicate point is rejected", (
		not ambiguous["ok"]
		and String(ambiguous["error"]).contains("Multiple")
	))

	duplicate.free()

	var wrong_type := Node.new()
	wrong_type.set_meta(TargetPoint2D.TARGET_META, true)
	rig.add_child(wrong_type)

	var invalid_type := TargetPoint2D.find_for(_entity)

	_expect("Point must be Node2D", (
		not invalid_type["ok"]
		and String(invalid_type["error"]).contains("must be Node2D")
	))

	wrong_type.free()

	point.set_meta(TargetPoint2D.TARGET_META, "yes")

	var invalid_flag := TargetPoint2D.find_for(_entity)

	_expect("Marker flag must be boolean", (
		not invalid_flag["ok"]
		and String(invalid_flag["error"]).contains("must be a bool")
	))

	var invalid_entity := TargetPoint2D.find_for(null)

	_expect("Invalid entity is rejected", (
		not invalid_entity["ok"]
		and String(invalid_entity["error"]).contains("Entity node is invalid")
	))

	print("[target-point] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _expect(description: String, condition: bool) -> void:
	_passed = _passed and condition
	print("[target-point] %s: %s" % [description, condition])


func _finalize() -> void:
	if is_instance_valid(_entity):
		_entity.free()

	_entity = null