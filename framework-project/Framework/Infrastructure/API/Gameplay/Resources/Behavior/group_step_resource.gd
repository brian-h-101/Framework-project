extends "res://Framework/Infrastructure/API/Gameplay/Resources/Behavior/behavior_step_resource.gd"

# Resource avoids a cyclic GDScript type dependency. BehaviorResource.read validates each entry.
@export var steps: Array[Resource] = []
