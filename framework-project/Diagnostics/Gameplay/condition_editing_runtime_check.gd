extends SceneTree

const GameEntry = preload(
	"res://Framework/Infrastructure/API/Runtime/game_entry.gd"
)
const GameSetup = preload(
	"res://Framework/Env/Setup/game_setup.gd"
)
const ConditionEditing = preload(
	"res://Framework/Env/Authoring/Resources/condition_editing.gd"
)

const CONDITION_PATH := (
	"res://Framework/Content/Behavior/Condition/actor_strength.tres"
)

const SOURCE_PATHS := [
	CONDITION_PATH,
	"res://Framework/Content/Behavior/Condition/can_strike.tres",
	"res://Framework/Content/Behavior/Interaction/strike.tres",
	"res://Framework/Content/Behavior/Action/change_health.tres",
]

var _entry: GameEntry = GameEntry.new()
var _source_bytes: Dictionary = {}
var _completed: bool = false
var _passed: bool = true


func _initialize() -> void:
	_run_check()
	_entry.stop()

	_expect("Session stopped", _entry.runtime == null)
	_expect("All gameplay checks completed", _completed)

	for source_path in _source_bytes:
		_expect(
			"Resource unchanged: %s" % source_path,
			FileAccess.get_file_as_bytes(String(source_path))
			== _source_bytes[source_path]
		)

	print("[condition-gameplay] Checks passed: ", _passed)
	quit(0 if _passed else 1)


func _run_check() -> void:
	for source_path in SOURCE_PATHS:
		if not _expect(
			"Source exists: %s" % source_path,
			FileAccess.file_exists(source_path)
		):
			return

		_source_bytes[source_path] = FileAccess.get_file_as_bytes(
			source_path
		)

	var read_result: Dictionary = ConditionEditing.get_comparison(
		CONDITION_PATH
	)

	if not _expect("Saved comparison is readable", read_result["ok"]):
		print(read_result)
		return

	var comparison: Dictionary = read_result["value"]

	if not _expect(
		"Comparison uses an integer minimum",
		comparison["operator"] == ">="
		and comparison["value_type"] == "int"
	):
		return

	var threshold: int = String(comparison["value_text"]).to_int()
	var rejection_message: String = String(comparison["message"])

	print("[condition-gameplay] Saved threshold: ", threshold)

	var started: Dictionary = _entry.start(GameSetup.new())
	print("[condition-gameplay] Start: ", started)

	if not _expect("Fresh session started", started["ok"]):
		return

	if not _expect(
		"Startup created Player and Enemy",
		_entry.entity_ids.has(&"player")
		and _entry.entity_ids.has(&"enemy")
	):
		return

	var player_id: int = _entry.entity_ids[&"player"]
	var enemy_id: int = _entry.entity_ids[&"enemy"]

	var cases: Array[Dictionary] = [
		{
			"strength": threshold - 1,
			"allowed": false,
		},
		{
			"strength": threshold,
			"allowed": true,
		},
		{
			"strength": 15,
			"allowed": 15 >= threshold,
		},
	]

	for test_case in cases:
		if not _check_strike(
			int(test_case["strength"]),
			bool(test_case["allowed"]),
			player_id,
			enemy_id,
			rejection_message
		):
			return

	_completed = true


func _check_strike(
	strength: int,
	allowed: bool,
	player_id: int,
	enemy_id: int,
	rejection_message: String
) -> bool:
	var before: Dictionary = _entry.runtime.read_attribute(
		enemy_id,
		&"health",
		["current"]
	)

	if not _expect("Enemy health is readable", before["ok"]):
		return false

	var written: Dictionary = _entry.runtime.write_attribute(
		player_id,
		&"strength",
		["current"],
		strength
	)

	if not _expect("Player strength updated", written["ok"]):
		return false

	var result: Dictionary = _entry.runtime.interact(
		&"strike",
		player_id,
		enemy_id
	)

	print(
		"[condition-gameplay] Strike at strength %d: " % strength,
		result
	)

	var expected_health: Variant = before["value"]
	var outcome_matches: bool

	if allowed:
		expected_health = expected_health - 10
		outcome_matches = (
			result["ok"]
			and result["error"] == ""
			and result["value"] == expected_health
		)
	else:
		outcome_matches = (
			not result["ok"]
			and result["value"] == null
			and result["error"] == rejection_message
		)

	var outcome_ok: bool = _expect(
		"Expected outcome at strength %d" % strength,
		outcome_matches
	)

	var after: Dictionary = _entry.runtime.read_attribute(
		enemy_id,
		&"health",
		["current"]
	)

	var health_ok: bool = _expect(
		"Correct health after strength %d strike" % strength,
		after["ok"] and after["value"] == expected_health
	)

	return outcome_ok and health_ok


func _expect(label: String, condition: bool) -> bool:
	print("[condition-gameplay] ", label, ": ", condition)
	_passed = _passed and condition
	return condition
