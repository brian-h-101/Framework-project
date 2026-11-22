extends SceneTree

const Policy = preload("res://Framework/Env/Setup/Library/authored_library.gd")
const Starting = preload("res://Framework/Env/Setup/Composition/starting_attributes.gd")
const Fragment = preload("res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd")
const EntityContent = preload("res://Framework/Env/Setup/Definitions/entity_definitions.gd")

var _passed := true


func _initialize() -> void:
	_check("Existing library categories remain valid", ["Entity", "Items", "Objects"].all(func(name: String) -> bool:
		return Policy.resource_error(Policy.ROOT.path_join(name).path_join("nested/fragment.tres")).is_empty()
	))
	_check("Additional categories and nested folders are accepted", Policy.resource_error(Policy.ROOT + "/Vehicles/Statistics/durability.tres").is_empty())
	_check("Sibling prefixes and traversal are rejected", not Policy.resource_error(Policy.ROOT + "Extra/fragment.tres").is_empty() and not Policy.resource_error(Policy.ROOT + "/../fragment.tres").is_empty())
	_check("Embedded and external resources are rejected", not Policy.resource_error(Policy.ROOT + "/Entity/fragment.tres::Embedded").is_empty() and not Policy.resource_error("res://Diagnostics/fragment.tres").is_empty())
	_check("Windows reserved names are rejected", not Policy.name_error("CON.tres").is_empty() and not Policy.name_error("COM¹").is_empty() and not Policy.name_error("name.").is_empty())
	var discovered := EntityContent.definitions()
	_check("Existing entity starting definitions still compose", discovered["ok"])
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() == 1:
		var fragment := ResourceLoader.load(arguments[0], "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Fragment
		_check("New category fragment loads", fragment != null)
		if fragment != null:
			var composed := Starting.define(&"new_library_probe", [fragment])
			_check("New category fragment composes through starting attributes", composed.has("containers") and composed["containers"] == fragment.to_containers()["value"])
	print("[authored-library] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, condition: bool) -> void:
	_passed = _passed and condition
	print("[authored-library] ", label, ": ", condition)
