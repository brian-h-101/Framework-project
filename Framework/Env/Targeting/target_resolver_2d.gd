extends RefCounted

const WorldBridge = preload(
	"res://Framework/Infrastructure/API/Bootstrap/world_bridge.gd"
)
const TargetPoint2D = preload(
	"res://Framework/Env/Targeting/target_point_2d.gd"
)

static func resolve(
	bridge: WorldBridge,
	actor_node: Node,
	mode: StringName
) -> Dictionary:
	if mode == &"nearest":
		return nearest(bridge, actor_node)

	return _failure("Unknown targeting mode: %s" % mode)

static func nearest(
	bridge: WorldBridge,
	actor_node: Node
) -> Dictionary:
	if bridge == null:
		return _failure("World bridge is missing.")

	if not is_instance_valid(actor_node):
		return _failure("Actor node is invalid.")

	var actor_id := bridge.entity_for(actor_node)
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

		var candidate := bridge.node_for(entity_id)
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