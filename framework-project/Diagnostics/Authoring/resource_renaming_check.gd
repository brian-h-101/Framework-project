extends SceneTree

const Renaming = preload("res://Framework/Env/Authoring/Resources/Library/behavior_renaming.gd")
var _passed := true


func _initialize() -> void:
	var old := "res://Framework/Content/Behavior/Action/old.tres"
	var replacement := "res://Framework/Content/Behavior/Action/new.tres"
	var consumer := "res://Framework/Content/Behavior/Action/consumer.gd"
	var source := "extends RefCounted\r\nconst Saved = preload(\"old.tres\")\r\nconst FilenameLabel = \"old.tres\"\r\n# Keep \"%s\" as a comment\r\nconst Absolute = preload(\"%s\")\r\n" % [old, old]
	var result := Renaming._rewrite(source, consumer, old, replacement, "")
	_check("Literal relative preload updates", result["ok"] and String(result["value"]).contains('preload("' + replacement + '")'))
	_check("Filename labels remain unchanged", result["value"].contains('const FilenameLabel = "old.tres"'))
	_check("Comments remain unchanged", result["value"].contains('# Keep "' + old + '" as a comment'))
	_check("CRLF is preserved", not String(result["value"]).replace("\r\n", "").contains("\n"))
	source = '[gd_resource format=3]\n[ext_resource type="Resource" path="old.tres" id="1"]\n[resource]\nresource_name = "old.tres"\n'
	result = Renaming._rewrite(source, consumer.get_base_dir().path_join("consumer.tres"), old, replacement, "")
	_check("Relative resource declaration updates", result["ok"] and result["value"].contains('path="' + replacement + '"'))
	_check("Resource display name remains unchanged", result["value"].contains('resource_name = "old.tres"'))
	source = '[gd_resource format=3]\n[resource]\nresource_name = "' + old + '"\n'
	result = Renaming._rewrite(source, consumer.get_base_dir().path_join("consumer.tres"), old, replacement, "")
	_check("Path-shaped display names remain unchanged", result["ok"] and result["value"] == source)
	source = '[gd_resource format=3]\n[resource]\nid = &"' + old + '"\n'
	result = Renaming._rewrite(source, consumer.get_base_dir().path_join("consumer.tres"), old, replacement, "")
	_check("Ambiguous path-shaped authored IDs are rejected", not result["ok"])
	source = '[gd_resource format=3]\n[resource]\nbehavior_id = &"' + old + '"\n'
	result = Renaming._rewrite(source, consumer.get_base_dir().path_join("consumer.tres"), old, replacement, "")
	_check("Executor IDs are protected from path rewrites", not result["ok"])
	result = Renaming._rewrite('const Path = "prefix ' + old + '"', consumer, old, replacement, "")
	_check("Composed literal reference is rejected", not result["ok"])
	result = Renaming._rewrite('const Path = "uid://abc"', consumer, old, replacement, "uid://abc")
	_check("UID-only reference is rejected", not result["ok"])
	print("[resource-renaming] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _check(label: String, passed: bool) -> void:
	print("[resource-renaming] ", label, ": ", passed)
	_passed = _passed and passed
