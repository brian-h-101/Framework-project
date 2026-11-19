extends Resource

# identifies an entity definition, such as player
@export var id: StringName = &""
# maps container names to dictionaries of attribute values
@export var containers: Dictionary[StringName, Dictionary] = {}

