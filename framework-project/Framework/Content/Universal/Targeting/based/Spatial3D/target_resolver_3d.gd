extends RefCounted

const Roles = preload("res://Framework/Content/Universal/Map/based/Spatial3D/spatial_roles_3d.gd")


static func resolve_entity(bridge: RefCounted, entity_id: int, mode: StringName) -> Dictionary:
	var resolved := resolve(bridge, bridge.node_for(entity_id), mode)
	return Roles.success(bridge.entity_for(resolved["value"])) if resolved["ok"] else resolved


static func resolve(bridge: RefCounted, actor: Node, mode: StringName) -> Dictionary:
	if not is_instance_valid(actor) or bridge.entity_for(actor) == 0:
		return Roles.failure("Behavior actor is not bound.")
	match mode:
		&"self":
			return Roles.success(actor)
		&"selected":
			var selected: Node = bridge.selected_behavior_target(actor)
			return Roles.success(selected) if point_for(selected) != null else Roles.failure("No selected 3D target is available.")
		&"nearest":
			return _nearest(bridge, actor)
	return Roles.failure("Unknown targeting mode: %s" % mode)


static func point_for(entity: Node) -> Node3D:
	var found := Roles.find(entity, &"interaction_target")
	var point := found["value"] as Node3D if found["ok"] else null
	return point if point != null and point.is_inside_tree() else null


static func _nearest(bridge: RefCounted, actor: Node) -> Dictionary:
	var origin := point_for(actor)
	if origin == null:
		return Roles.failure("Actor has no enabled 3D target point.")
	var closest: Node
	var closest_id := 0
	var best := INF
	for id: int in bridge.bound_entity_ids():
		var candidate: Node = bridge.node_for(id)
		if candidate == actor:
			continue
		var point := point_for(candidate)
		if point == null or point.get_world_3d() != origin.get_world_3d():
			continue
		var distance := origin.global_position.distance_squared_to(point.global_position)
		if distance < best or (distance == best and id < closest_id):
			best = distance
			closest_id = id
			closest = candidate
	return Roles.success(closest) if closest != null else Roles.failure("No targetable 3D entity is available.")
