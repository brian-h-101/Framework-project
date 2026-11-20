extends SceneTree

const ContainerFragmentResource = preload(
	"res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd"
)
const FragmentComposition = preload("res://Framework/Env/Setup/fragment_composition.gd")
const CommonAttributes = preload("res://Framework/Env/Setup/common_attributes.gd")
const Precognition = preload("res://Framework/Content/Authored/Entity/Attributes/Abilities/precognition.tres")
const Reflex = preload("res://Framework/Content/Authored/Entity/Attributes/Abilities/reflex.tres")

var _passed := true


func _initialize() -> void:
	var abilities := FragmentComposition.compose_resources([Precognition, Reflex])
	_check("Selected abilities share a container without losing siblings", (
		abilities["ok"] and abilities["value"][&"abilities"] == {"precognition": 0, "reflex": 0}
	))
	var first := ContainerFragmentResource.new()
	first.containers = {
		&"health": {"current": 10, "maximum": 100},
		&"inventory": {"capacity": 3, "items": {"old": [1]}},
	}
	var second := ContainerFragmentResource.new()
	second.containers = {
		&"health": {"current": 50},
		&"inventory": {"items": {"new": [2]}},
	}
	var forward := FragmentComposition.compose_resources([first, second])
	var reverse := FragmentComposition.compose_resources([second, first])
	_check("Authored order controls matching attributes", (
		forward["ok"] and reverse["ok"]
		and forward["value"][&"health"] == {"current": 50, "maximum": 100}
		and reverse["value"][&"health"] == {"current": 10, "maximum": 100}
	))
	_check("Collection attributes replace as a whole and preserve siblings", (
		forward["value"][&"inventory"] == {"capacity": 3, "items": {"new": [2]}}
	))
	forward["value"][&"inventory"]["items"]["new"].append(99)
	_check("Composed arrays cannot alter resource data", second.containers[&"inventory"]["items"]["new"] == [2])
	var fresh := FragmentComposition.compose_resources([first, second])
	_check("Separate compositions own nested collections", fresh["value"][&"inventory"]["items"]["new"] == [2])
	first.containers = {&"health": 100}
	_check("Malformed containers are rejected", not first.to_containers()["ok"])
	first.containers = {42: {}}
	_check("Non-text container names are rejected", not first.to_containers()["ok"])
	first.containers = {&"": {}}
	_check("Empty container names are rejected", not first.to_containers()["ok"])
	_check("Null fragment references are rejected", not FragmentComposition.compose_resources([null])["ok"])
	var wrong_type := FragmentComposition.compose_paths(PackedStringArray([
		"res://Framework/Content/Behavior/Action/change_health.tres",
	]))
	_check("Other resource types cannot act as fragments", not wrong_type["ok"])
	var missing := FragmentComposition.compose_paths(PackedStringArray([
		"res://Framework/Content/Authored/Entity/Attributes/Missing/missing.tres",
	]))
	_check("Missing resource paths are rejected", not missing["ok"])
	var legacy := FragmentComposition.compose_paths(PackedStringArray([
		"res://Framework/Env/Setup/common_attributes.gd",
	]))
	_check("Script files cannot act as data fragments", not legacy["ok"])
	var discovered := FragmentComposition.compose_in("res://Framework/Content/Authored/Entity/Attributes")
	_check("Folder composition discovers resource fragments", (
		discovered["ok"]
		and discovered["value"][&"abilities"] == {"precognition": 0, "reflex": 0}
		and discovered["value"][&"health"] == {"current": 100, "maximum": 100}
	))
	var common := CommonAttributes.defaults()
	_check("Shared composition helper retains health and speed", (
		common[&"health"] == {"current": 100, "maximum": 100}
		and common[&"speed"] == {"current": 20, "maximum": 50}
	))
	print("[container-fragment] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[container-fragment] ", label, ": ", passed)
	_passed = _passed and passed
