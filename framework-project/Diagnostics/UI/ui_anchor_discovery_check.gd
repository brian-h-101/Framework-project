extends SceneTree

const UIAnchor2D = preload(
	"res://Framework/Content/Universal/UI/based/Spatial2D/ui_anchor_2d.gd"
)

var _entity: Node
var _passed: bool = true


func _initialize() -> void:
	_entity = Node.new()
	_entity.name = &"Entity"
	_entity.set_meta(&"entity_key", &"player")

	var rig := Node.new()
	rig.name = &"VisualRig"
	_entity.add_child(rig)

	var pivot := Node2D.new()
	pivot.name = &"SpritePivot"
	rig.add_child(pivot)

	var anchor := Marker2D.new()
	anchor.name = &"FloatingTextPoint"
	anchor.set_meta(UIAnchor2D.ROLE_META, &"status")
	pivot.add_child(anchor)

	var discovered := UIAnchor2D.find_for(_entity)

	_expect("Finds nested marker before tree entry", (
		not _entity.is_inside_tree()
		and discovered["ok"]
		and discovered["value"] == anchor
	))

	pivot.name = &"RenamedPresentation"
	anchor.name = &"RenamedMarker"

	var renamed := UIAnchor2D.find_for(_entity)

	_expect("Names do not affect discovery", (
		renamed["ok"]
		and renamed["value"] == anchor
	))

	var dialogue_anchor := Marker2D.new()
	dialogue_anchor.set_meta(UIAnchor2D.ROLE_META, &"dialogue")
	pivot.add_child(dialogue_anchor)

	var dialogue := UIAnchor2D.find_for(_entity, &"dialogue")

	_expect("Selects the requested role", (
		dialogue["ok"]
		and dialogue["value"] == dialogue_anchor
	))

	anchor.remove_meta(UIAnchor2D.ROLE_META)

	var missing := UIAnchor2D.find_for(_entity)

	_expect("Missing role is rejected", (
		not missing["ok"]
		and String(missing["error"]).contains("Missing UI anchor")
	))

	var nested_entity := Node.new()
	nested_entity.set_meta(&"entity_key", &"enemy")
	_entity.add_child(nested_entity)

	var nested_anchor := Marker2D.new()
	nested_anchor.set_meta(UIAnchor2D.ROLE_META, &"status")
	nested_entity.add_child(nested_anchor)

	var scoped := UIAnchor2D.find_for(_entity)

	_expect("Nested entity anchor is excluded", (
		not scoped["ok"]
		and String(scoped["error"]).contains("Missing UI anchor")
	))

	var nested_result := UIAnchor2D.find_for(nested_entity)

	_expect("Nested entity finds its own anchor", (
		nested_result["ok"]
		and nested_result["value"] == nested_anchor
	))

	anchor.set_meta(UIAnchor2D.ROLE_META, &"status")

	var duplicate := Marker2D.new()
	duplicate.set_meta(UIAnchor2D.ROLE_META, &"status")
	pivot.add_child(duplicate)

	var ambiguous := UIAnchor2D.find_for(_entity)

	_expect("Duplicate role is rejected", (
		not ambiguous["ok"]
		and String(ambiguous["error"]).contains("Multiple UI anchors")
	))

	duplicate.free()

	var wrong_type := Node.new()
	wrong_type.set_meta(UIAnchor2D.ROLE_META, &"status")
	_entity.add_child(wrong_type)

	var invalid := UIAnchor2D.find_for(_entity)

	_expect("Anchor must be Node2D", (
		not invalid["ok"]
		and String(invalid["error"]).contains("must be Node2D")
	))

	print("[anchor] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _expect(description: String, condition: bool) -> void:
	_passed = _passed and condition
	print("[anchor] %s: %s" % [description, condition])


func _finalize() -> void:
	if is_instance_valid(_entity):
		_entity.free()

	_entity = null