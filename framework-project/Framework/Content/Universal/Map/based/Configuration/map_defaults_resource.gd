extends "res://Framework/Env/Configuration/Resources/Shared/configuration_resource.gd"

const GroundResource = preload("res://Framework/Content/Universal/Map/based/Configuration/ground_resource.gd")
const LightingResource = preload("res://Framework/Content/Universal/Lighting/based/Configuration/lighting_2d_resource.gd")

@export var ground_content: GroundResource
@export var lighting_content: LightingResource


func to_definition() -> Dictionary:
	return {"ground_content": ground_content, "lighting_content": lighting_content}


func validation_error() -> String:
	if ground_content == null or lighting_content == null:
		return "Map defaults require ground and lighting configurations."
	var ground_error := ground_content.validation_error()
	return ground_error if not ground_error.is_empty() else lighting_content.validation_error()
