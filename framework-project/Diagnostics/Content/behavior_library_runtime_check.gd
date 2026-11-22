extends SceneTree

const Entry = preload("res://Framework/Infrastructure/API/Runtime/game_entry.gd")
const Setup = preload("res://Framework/Env/Setup/Bootstrap/game_setup.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(1)
		return
	var entry := Entry.new()
	var started := entry.start(Setup.new())
	if args[0] == "expect-duplicate":
		var rejected: bool = not started["ok"] and String(started["error"]).contains("Duplicate")
		entry.stop()
		print("[behavior-library-runtime] Checks passed: ", rejected)
		quit(0 if rejected else 1)
		return
	var passed: bool = started["ok"]
	if passed:
		var runtime = entry.runtime
		var data: Dictionary[StringName, Dictionary] = {
			&"health": {"current": 100},
			&"interactions": {"available": [StringName(args[0])]},
		}
		runtime.define_attributes(&"library_probe", data)
		var actor: int = runtime.spawn(&"library_probe")
		var target: int = runtime.spawn(&"library_probe")
		var result: Dictionary = runtime.interact(StringName(args[0]), actor, target)
		passed = result["ok"] and runtime.read_attribute(target, &"health", ["current"])["value"] == 93
		print("[behavior-library-runtime] Nested interaction executes through GameSetup: ", passed)
		var denied: int = runtime.spawn(&"library_probe", {&"interactions": {"available": []}})
		passed = passed and not runtime.interact(StringName(args[0]), denied, target)["ok"]
		print("[behavior-library-runtime] Discovery preserves authored availability: ", passed)
	entry.stop()
	print("[behavior-library-runtime] Checks passed: ", passed)
	quit(0 if passed else 1)
