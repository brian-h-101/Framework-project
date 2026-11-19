extends SceneTree

const SessionClock = preload(
	"res://Framework/Infrastructure/Implementation/Runtime/session_clock.gd"
)
const WorldTime = preload(
	"res://Framework/Content/Configuration/Session/world_time.gd"
)


func _initialize() -> void:
	var clock := SessionClock.new(WorldTime.defaults())

	print("[clock] Starting hour: ", clock.get_hour())
	var passed := is_equal_approx(clock.get_hour(), 8.0)

	clock.advance(30.0)
	print("[clock] After 30 seconds, hour: ", clock.get_hour())
	passed = passed and is_equal_approx(clock.get_hour(), 14.0)

	clock.advance(60.0)
	print("[clock] After 90 seconds, day: ", clock.get_day_number())
	print("[clock] After 90 seconds, hour: ", clock.get_hour())
	print("[clock] Day fraction: ", clock.get_day_fraction())

	passed = (
		passed
		and clock.get_day_number() == 2
		and is_equal_approx(clock.get_hour(), 2.0)
		and is_equal_approx(clock.get_day_fraction(), 2.0 / 24.0)
	)

	clock.advance(0.625)
	var saved_state := clock.snapshot_state()
	print("[clock] Saved state: ", saved_state)

	var receiving_clock := SessionClock.new(WorldTime.defaults())
	var restored := receiving_clock.restore_state(saved_state)

	var restored_ok: bool = (
		restored["ok"]
		and receiving_clock.get_day_number() == 2
		and is_equal_approx(receiving_clock.get_hour(), 2.125)
	)
	print("[clock] Calendar position restored: ", restored_ok)

	receiving_clock.advance(120.0)

	var continued_ok: bool = (
		receiving_clock.get_day_number() == 3
		and is_equal_approx(receiving_clock.get_hour(), 2.125)
	)
	print("[clock] Restored clock continues advancing: ", continued_ok)

	var before_rejection := receiving_clock.snapshot_state()
	var rejected := receiving_clock.restore_state({
		"total_hours": -1.0,
	})

	var rejection_ok: bool = (
		not rejected["ok"]
		and receiving_clock.snapshot_state() == before_rejection
	)
	print("[clock] Rejected restoration preserves time: ", rejection_ok)

	passed = passed and restored_ok and continued_ok and rejection_ok

	print("[clock] Checks passed: ", passed)

	if not passed:
		push_error("Session clock calculation check failed.")

	quit(0 if passed else 1)