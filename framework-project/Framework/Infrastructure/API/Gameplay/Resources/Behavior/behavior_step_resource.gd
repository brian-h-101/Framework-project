extends Resource

const Requirements = preload("res://Framework/Infrastructure/API/Gameplay/Resources/Conditions/condition_group_resource.gd")

# Unique within the owning Behavior, independent of the display label and order.
@export var id: StringName = &""
@export var label: String = ""
@export var requirements: Requirements
