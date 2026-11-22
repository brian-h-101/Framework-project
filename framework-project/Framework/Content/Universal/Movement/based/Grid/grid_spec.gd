extends "res://Framework/Content/Universal/Movement/based/Physics2D/physics_2d_spec.gd"

const GridDriver = preload("res://Framework/Content/Universal/Movement/based/Grid/grid_driver.gd")

@export var board_size := Vector2i(12, 8)
@export var cell_size_pixels := 32
@export var blocked_cells: Array[Vector2i] = []


func environment_id() -> String:
	return "grid"


func create_driver(body: Node, map: Node, bridge: RefCounted, entity: Node) -> Driver:
	var body_2d := body as CharacterBody2D
	var map_2d := map as Node2D
	if body_2d == null or map_2d == null:
		return null
	return GridDriver.new(body_2d, bridge, entity, units_per_gameplay_unit, map_2d, to_definition())


func to_definition() -> Dictionary:
	var definition := super()
	definition.merge({"board_size": board_size, "cell_size_pixels": cell_size_pixels, "blocked_cells": blocked_cells.duplicate()})
	return definition


func validation_error() -> String:
	var error := super()
	if not error.is_empty():
		return error
	if board_size.x <= 0 or board_size.y <= 0 or cell_size_pixels <= 0:
		return "Grid dimensions and cell size must be positive."
	if not is_finite(float(cell_size_pixels) / units_per_gameplay_unit):
		return "Grid cell size in gameplay units must be finite."
	var seen := {}
	var board := Rect2i(Vector2i.ZERO, board_size)
	for cell in blocked_cells:
		if not board.has_point(cell) or seen.has(cell):
			return "Each blocked grid cell must be unique and inside the board."
		seen[cell] = true
	return ""
