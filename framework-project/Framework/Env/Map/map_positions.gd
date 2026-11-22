extends RefCounted

const Positions2D = preload("res://Framework/Content/Universal/Map/based/Spatial2D/map_positions_2d.gd")
const Positions3D = preload("res://Framework/Content/Universal/Map/based/Spatial3D/map_positions_3d.gd")


static func read_saved_positions(map_record: Dictionary) -> Dictionary:
	if not map_record.has(Positions3D.RECORD_KEY):
		var result := Positions2D.read_saved_positions(map_record)
		if not result["ok"]:
			return result
		for position in result["value"].values():
			if not position is Vector2:
				return {"ok": false, "value": null, "error": "Saved positions_2d must contain Vector2 values."}
		return result
	var positions: Variant = map_record[Positions3D.RECORD_KEY]
	if map_record.has(Positions2D.RECORD_KEY) or not positions is Dictionary:
		return {"ok": false, "value": null, "error": "Saved 3D maps require a single positions_3d dictionary."}
	for position in positions.values():
		if not position is Vector3:
			return {"ok": false, "value": null, "error": "Saved positions_3d must contain Vector3 values."}
	return {"ok": true, "value": positions, "error": ""}


static func prepare_restores(map: Node, placements: Array[Dictionary], saved: Dictionary) -> Dictionary:
	if map is Node3D:
		return Positions3D.prepare_restores(map, placements, saved)
	return Positions2D.prepare_restores(map, placements, saved)


static func restore(map: Node, positions: Array[Dictionary]) -> Dictionary:
	if map is Node3D:
		return Positions3D.restore(map, positions)
	return Positions2D.restore(map, positions)


static func snapshot(map: Node, entity_ids: Dictionary[StringName, int], bound_ids: Array[int], node_for: Callable) -> Dictionary:
	if map is Node3D:
		return Positions3D.snapshot(map, entity_ids, bound_ids, node_for)
	return Positions2D.snapshot(map, entity_ids, bound_ids, node_for)
