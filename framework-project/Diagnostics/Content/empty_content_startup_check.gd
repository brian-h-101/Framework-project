extends SceneTree

const Host = preload("res://Framework/Env/Host/game_host.gd")
const Setup = preload("res://Framework/Env/Setup/Bootstrap/game_setup.gd")
const Startup = preload("res://Framework/Env/Configuration/Resources/Session/startup_resource.gd")
const Paths = preload("res://Framework/Env/Setup/Library/library_path_policy.gd")
const Definitions = preload("res://Framework/Env/Setup/Definitions/starting_definitions.gd")
const BehaviorLibrary = preload("res://Framework/Env/Authoring/Resources/Library/behavior_library_authoring.gd")
const SceneLibrary = preload("res://Framework/Env/Authoring/Scenes/Library/scene_library.gd")
const Controllers = preload("res://Framework/Env/Authoring/Scenes/Configuration/movement_controller_catalog.gd")
const Templates = preload("res://Framework/Env/Authoring/Scenes/Creation/scene_templates.gd")
const Shared = preload("res://Framework/Env/Authoring/Shared/resource_library_files.gd")
const Inspection = preload("res://Framework/Env/Authoring/Resources/Inspection/behavior_inspection.gd")

class SceneSetup:
	extends "res://Framework/Env/Setup/Bootstrap/game_setup.gd"
	var map_scene: PackedScene
	var hud_scene: PackedScene

	func get_initial_map_result() -> Dictionary:
		return {"ok": true, "value": map_scene, "error": ""}

	func get_ui_scene_result() -> Dictionary:
		return {"ok": true, "value": hud_scene, "error": ""}

var _passed := true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for source in [["Gameplay/Presentation", "tres"], ["Gameplay/Profiles", "tres"], ["Gameplay/Profiles", "gd"]]:
		var listed := Paths.paths_in("res://Framework/Content/" + source[0], source[1])
		_check("%s contains no authored .%s definitions" % source, listed["ok"] and listed["value"].is_empty())
	var scenes := Paths.paths_in("res://Framework/Content", "tscn")
	_check("Content contains no scenes", scenes["ok"] and scenes["value"].is_empty())
	var authored := Paths.paths_in("res://Framework/Content/Gameplay/Authored")
	_check("Authored attribute library remains available", authored["ok"] and not authored["value"].is_empty())
	var definitions := Definitions.definitions()
	_check("Starting definition discovery accepts empty libraries", definitions["ok"] and definitions["value"].is_empty())
	var behaviors := BehaviorLibrary.catalogue()
	_check("Behavior library management opens without game Resources", behaviors["ok"])
	var libraries := SceneLibrary.catalogue()
	_check("Scene library management opens without example scenes", libraries["ok"])
	var controllers := Controllers.read()
	_check("Movement controller discovery accepts an empty folder", controllers["ok"] and controllers["value"].is_empty())
	var inspected := Inspection.graph()
	_check("Resource graph accepts an empty Behavior library", inspected["ok"] and inspected["value"]["roots"].is_empty())
	var setup := Setup.new()
	var map_result := setup.get_initial_map_result()
	var ui_result := setup.get_ui_scene_result()
	_check("Blank startup intentionally selects no map or HUD", map_result["ok"] and map_result["value"] == null and ui_result["ok"] and ui_result["value"] == null)
	var invalid := Startup.new()
	invalid.initial_map = "res://Framework/Content/Gameplay/Maps/not_created.tscn"
	_check("A nonempty missing map is still rejected", not invalid.read()["ok"])
	invalid.initial_map = ""
	invalid.ui_scene = "res://Framework/Content/Gameplay/UI/HUD/not_created.tscn"
	_check("A nonempty missing HUD is still rejected", not invalid.read()["ok"])
	var host := Host.new()
	var started := host.start_configured(root)
	_check("Configured startup starts a fresh empty session", started["ok"])
	if not started["ok"]:
		print(started)
		host.stop()
		quit(1)
		return
	_check("No example entities are spawned", host.entry.entity_ids.is_empty())
	_check("No map or HUD is attached", host.maps.get_active_map() == null and host.ui == null)
	_check("Gameplay executor scripts are absent",
		not host.entry.runtime.has_executor(&"change_health") and not host.entry.runtime.has_executor(&"movement")
		and not host.entry.runtime.has_executor(&"movement_2d"))
	_check("Built-in framework execution remains available", host.entry.runtime.has_executor(&"attribute_effects"))
	var captured := host.entry.snapshot_session()
	_check("Empty session snapshots remain valid", captured["ok"] and captured["value"]["entities"].is_empty())
	await process_frame
	host.stop()
	await process_frame
	_check("Empty host stops cleanly", host.entry.runtime == null and host.maps == null and host.ui == null)
	var target := "res://Framework/Content/Gameplay/Maps/EmptyContentDraftCheck.tscn"
	var drafted := SceneLibrary.draft(target, {"template": "map_2d", "node_name": "EmptyContentDraftCheck",
		"expected_parent": Shared.fingerprint(target.get_base_dir())})
	_check("Map authoring produces a verified draft without example scenes", drafted["ok"])
	_check("Drafting leaves the Content library empty", not FileAccess.file_exists(target))
	var presentation := Templates.create("presentation", "NewEntity", "CharacterBody2D")
	var hud := Templates.create("hud", "NewHUD", "")
	var map_scene := Templates.create("empty_2d", "NewMap", "")
	_check("Presentation and HUD templates remain available", presentation["ok"] and hud["ok"] and map_scene["ok"])
	if presentation["ok"] and hud["ok"] and map_scene["ok"]:
		var scene_setup := SceneSetup.new()
		scene_setup.map_scene = map_scene["value"]
		scene_setup.hud_scene = hud["value"]
		var scene_host := Host.new()
		var registered := scene_host.entry.start(scene_setup)
		var attached := scene_host._start_environment(root, scene_setup) if registered["ok"] else registered
		_check("Host attaches explicitly supplied replacement map and HUD", attached["ok"] and scene_host.maps.get_active_map() != null and scene_host.ui != null)
		scene_host.stop()
		await process_frame
		var wrong_ui := Templates.create("control", "WrongHUD", "")
		scene_setup.hud_scene = wrong_ui["value"]
		registered = scene_host.entry.start(scene_setup)
		var retained_runtime = scene_host.entry.runtime
		attached = scene_host._start_environment(root, scene_setup) if registered["ok"] else registered
		_check("Invalid HUD root is rejected and cleans up the session", not attached["ok"] and scene_host.entry.runtime == null and not retained_runtime.snapshot_time()["ok"])
		scene_host.stop()
		await process_frame
	print("[empty-content] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, valid: bool) -> void:
	_passed = _passed and valid
	print("[empty-content] %s: %s" % [label, valid])
