extends RefCounted

const TargetPoint2D = preload(
	"res://Framework/Content/Universal/Targeting/based/Spatial2D/target_point_2d.gd"
)


static func resolve_entity(
	bridge: RefCounted,
	entity_id: int,
	mode: StringName
) -> Dictionary:
	var actor: Node = bridge.node_for(entity_id)
	if not is_instance_valid(actor):
		return _failure("Actor is not represented in the active map.")
	var result := resolve(bridge, actor, mode)
	if not result["ok"]:
		return result
	return {"ok": true, "value": bridge.entity_for(result["value"]), "error": ""}


static func resolve(
	bridge: RefCounted,
	actor_node: Node,
	mode: StringName
) -> Dictionary:
	if bridge == null or not is_instance_valid(actor_node) or bridge.entity_for(actor_node) == 0:
		return _failure("Behavior actor is not bound.")
	if mode == &"self":
		return {"ok": true, "value": actor_node, "error": ""}
	if mode == &"selected":
		var selected: Node = bridge.selected_behavior_target(actor_node)
		if not is_instance_valid(selected):
			return _failure("No selected target is bound in the active map.")
		var found := TargetPoint2D.find_for(selected)
		if not found["ok"] or not found["value"].is_inside_tree():
			return _failure("Selected entity has no enabled target point in the active map.")
		return {"ok": true, "value": selected, "error": ""}
	if mode == &"nearest":
		return nearest(bridge, actor_node)

	return _failure("Unknown targeting mode: %s" % mode)

static func nearest(
	bridge: RefCounted,
	actor_node: Node
) -> Dictionary:
	if bridge == null:
		return _failure("World bridge is missing.")

	if not is_instance_valid(actor_node):
		return _failure("Actor node is invalid.")

	var actor_id: int = bridge.entity_for(actor_node)
	if actor_id == 0:
		return _failure("Actor node is not bound to a runtime entity.")

	var actor_result := TargetPoint2D.find_for(actor_node)
	if not actor_result["ok"]:
		return _failure(
			"Actor targeting failed: %s" % actor_result["error"]
		)

	var actor_point := actor_result["value"] as Node2D
	if not actor_point.is_inside_tree():
		return _failure("Actor targeting point is outside the scene tree.")

	var closest_node: Node = null
	var closest_distance_squared: float = INF

	for entity_id in bridge.bound_entity_ids():
		if entity_id == actor_id:
			continue

		var candidate: Node = bridge.node_for(entity_id)
		if not is_instance_valid(candidate):
			continue

		var candidate_result := TargetPoint2D.find_for(candidate)
		if not candidate_result["ok"]:
			continue

		var candidate_point := candidate_result["value"] as Node2D
		if not candidate_point.is_inside_tree():
			continue

		var distance_squared := actor_point.global_position.distance_squared_to(
			candidate_point.global_position
		)

		if distance_squared < closest_distance_squared:
			closest_node = candidate
			closest_distance_squared = distance_squared

	if closest_node == null:
		return _failure("No targetable entity is available.")

	return {"ok": true, "value": closest_node, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
