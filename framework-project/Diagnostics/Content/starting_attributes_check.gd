extends SceneTree

const EntityContent = preload("res://Framework/Env/Setup/entity_definitions.gd")
const Baseline = preload("res://Diagnostics/Fixtures/Baselines/entity_starting_baseline.gd")
const StartingAttributes = preload("res://Framework/Env/Setup/starting_attributes.gd")
const ContentDiscovery = preload("res://Framework/Env/Setup/content_discovery.gd")
const GameEntry = preload("res://Framework/Infrastructure/API/Runtime/game_entry.gd")
const EnvironmentSetup = preload("res://Framework/Env/Setup/game_setup.gd")
const Startup = preload("res://Framework/Content/Configuration/Session/startup.tres")
const ContainerFragmentResource = preload(
	"res://Framework/Infrastructure/API/Entity/Resources/container_fragment_resource.gd"
)
const Health = preload(
	"res://Framework/Content/Authored/Entity/Attributes/Statistics/health.tres"
)
const OutsideLibrary = preload(
	"res://Diagnostics/Fixtures/ContainerFragments/outside_library.tres"
)
const BASELINE_IDS: Array[StringName] = [&"enemy", &"player", &"town_guard"]

var _entry := GameEntry.new()
var _passed: bool = true


func _initialize() -> void:
	var discovered := EntityContent.definitions()
	if not discovered["ok"]:
		push_error(String(discovered["error"]))
		quit(1)
		return

	var ids: Array[StringName] = []
	for definition in discovered["value"]:
		var preset_id := StringName(definition["id"])
		ids.append(preset_id)
		if not BASELINE_IDS.has(preset_id):
			continue
		_expect(
			"%s full starting data preserved" % preset_id,
			definition == Baseline.definition(preset_id)
		)

	_expect("The three existing presets are registered",
		BASELINE_IDS.all(func(preset_id: StringName) -> bool: return ids.has(preset_id)))

	var headless := ContentDiscovery.entity_definitions_in(
		"res://Diagnostics/Fixtures/StartingPresetDiscovery"
	)
	var headless_ok: bool = (
		headless["ok"]
		and headless["value"].size() == 1
		and headless["value"][0]["id"] == &"headless_probe"
	)
	_expect("Discovery ignores presentation definitions", headless_ok)

	var selection := StartingAttributes.define(
		&"library_probe",
		[Health],
		{&"health": {"current": 75}}
	)
	_expect("Resource selections preserve composition and overrides", (
		selection.has("containers")
		and selection["containers"][&"health"] == {"current": 75, "maximum": 100}
	))

	var outside := StartingAttributes.define(
		&"outside_library",
		[OutsideLibrary]
	)
	_expect("Selected resources stay inside Authored", (
		not outside.get("ok", true)
	))

	var missing_path := "res://Framework/Content/Authored/Entity/Attributes/Missing/missing.tres"
	var missing_resource := ContainerFragmentResource.new()
	missing_resource.take_over_path(missing_path)
	var missing := StartingAttributes.define(
		&"missing_fragment",
		[missing_resource]
	)
	_expect("Missing selected fragments report their path", (
		not missing.get("ok", true)
		and String(missing["error"]).contains(missing_path)
	))

	var inline := StartingAttributes.define(
		&"inline_fragment",
		[ContainerFragmentResource.new()]
	)
	_expect("Starting fragments require external library resources", not inline.get("ok", true))

	var started := _entry.start(EnvironmentSetup.new())
	if not started["ok"]:
		push_error(String(started["error"]))
		quit(1)
		return

	var specifications: Dictionary = Startup.to_definition()["entities"]
	for entity_key in specifications:
		var specification: Dictionary = specifications[entity_key]
		var expected: Dictionary = (
			Baseline.definition(StringName(specification["definition"]))["containers"]
		)
		var overrides: Dictionary = specification.get("overrides", {})
		for container_id in overrides:
			if not expected.has(container_id):
				expected[container_id] = {}
			expected[container_id].merge(overrides[container_id].duplicate(true), true)

		var runtime_matches := true
		var entity_id: int = _entry.entity_ids[entity_key]
		for container_id in expected:
			for attribute_name in expected[container_id]:
				var actual := _entry.runtime.read_attribute(
					entity_id, StringName(container_id), [attribute_name]
				)
				if not actual["ok"] or actual["value"] != expected[container_id][attribute_name]:
					runtime_matches = false
					print("[starting] Mismatch: ", entity_key, "/", container_id, "/", attribute_name)
		_expect("%s runtime values and spawn overrides preserved" % entity_key, runtime_matches)

	var player_id: int = _entry.entity_ids[&"player"]
	var second_id: int = _entry.entity_ids[&"second_player"]
	var written := _entry.runtime.write_attribute(
		player_id, &"inventory", ["items"], {"probe": 1}
	)
	var second_items := _entry.runtime.read_attribute(second_id, &"inventory", ["items"])
	_expect("Instances own their nested inventory data", (
		written["ok"] and second_items["ok"] and second_items["value"] == {}
	))

	var unchanged := EntityContent.definitions()
	var templates_unchanged: bool = unchanged["ok"]
	if templates_unchanged:
		for definition in unchanged["value"]:
			var preset_id := StringName(definition["id"])
			if BASELINE_IDS.has(preset_id) and definition != Baseline.definition(preset_id):
				templates_unchanged = false
	_expect("Runtime changes leave authored starting values unchanged", templates_unchanged)

	_check_registered_libraries()

	_entry.stop()
	print("[starting] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check_registered_libraries() -> void:
	var collision := ContentDiscovery.starting_definitions_in(
		PackedStringArray([
			"res://Framework/Content/Presentation/Items",
			"res://Diagnostics/Fixtures/DuplicateStartingDefinitions/Objects",
		])
	)
	var collision_error := String(collision.get("error", ""))

	_expect("Duplicate IDs across libraries are rejected", (
		not collision["ok"]
		and collision_error.contains("Duplicate ID 'iron_sword'")
		and collision_error.contains("IronSword/starting_attributes.tres")
		and collision_error.contains("DuplicateSword/starting_attributes.tres")
	))

	for definition_id: StringName in [&"iron_sword", &"wooden_chest"]:
		_expect(
			"%s definition registered" % definition_id,
			_entry.runtime.has_definition(definition_id)
		)

	var sword_id := _entry.runtime.spawn(&"iron_sword")
	var chest_id := _entry.runtime.spawn(&"wooden_chest")
	var spawned: bool = sword_id != 0 and chest_id != 0
	_expect("Item and Object instances spawn", spawned)
	if not spawned:
		return

	_entry.entity_ids[&"checkpoint_sword"] = sword_id
	_entry.entity_ids[&"checkpoint_chest"] = chest_id

	var changed := _entry.runtime.write_attribute(
		sword_id, &"condition", ["current"], 60
	)
	_expect("Item attributes are writable", (
		changed["ok"] and changed["value"] == 60
	))
	if not changed["ok"]:
		return

	var locked := _entry.runtime.read_attribute(
		chest_id, &"access", ["locked"]
	)
	_expect("Object starting overrides are readable", (
		locked["ok"] and locked["value"] == true
	))

	var captured := _entry.snapshot_session()
	_expect("Session captures the additional instances", captured["ok"])
	if not captured["ok"]:
		return

	var snapshot: Dictionary = captured["value"]
	var records: Dictionary = snapshot["entities"]
	_expect("Additional instances have stable save keys", (
		records.has(&"checkpoint_sword")
		and records.has(&"checkpoint_chest")
	))

	_entry.stop()

	var restored := _entry.restore_session(EnvironmentSetup.new(), snapshot)
	_expect("Session restores the additional instances", restored["ok"])
	if not restored["ok"]:
		return

	var recaptured := _entry.snapshot_session()
	_expect("Restored state matches captured state", (
		recaptured["ok"] and recaptured["value"] == snapshot
	))


func _expect(label: String, condition: bool) -> void:
	print("[starting] ", label, ": ", condition)
	_passed = _passed and condition


func _finalize() -> void:
	_entry.stop()
