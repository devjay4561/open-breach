extends SceneTree

const Presentation = preload("res://scripts/presentation_state.gd")
const Replay = preload("res://scripts/replay.gd")
const STEP: float = 1.0 / 30.0
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _state(at: float, x: float) -> Dictionary:
	return {"time": at, "tick": roundi(at / STEP), "units": [{"id": "alpha", "kind": "unit", "x": x, "z": 3.0, "facing": 0.0, "aim_facing": 0.0, "move_facing": 0.0, "travel_distance": x - 2.0, "hp": 100.0, "status": "MOVING", "visible": true, "commands": []}], "enemies": [], "civilians": [], "doors": [{"id": "d1", "x": 4.0, "z": 4.0, "state": "OPENING", "progress": 0.0}], "events": [], "sound_zones": []}

func _run() -> void:
	_test_continuity_and_events()
	_test_observation_boundaries()
	_test_reset_and_slow_frames()
	_test_replay_observation_and_metadata()
	print("BREACH_PRESENTATION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_continuity_and_events() -> void:
	var view = Presentation.new()
	var before: Dictionary = _state(0.0, 2.0)
	var after: Dictionary = _state(STEP, 2.12)
	before.units[0].facing = deg_to_rad(179.0)
	after.units[0].facing = deg_to_rad(-179.0)
	before.units[0].body_facing = deg_to_rad(179.0)
	after.units[0].body_facing = deg_to_rad(-179.0)
	after.units[0].aim_facing = 0.4
	after.units[0].move_facing = -0.8
	after.units[0].hp = 0.0
	after.units[0].status = "INCAPACITATED"
	after.doors[0].progress = 0.1
	after.events = [{"seq": 1, "type": "SHOT", "time": STEP, "tick": 1}]
	var original_before: String = JSON.stringify(before)
	var original_after: String = JSON.stringify(after)
	view.reset(before)
	view.capture(after)
	var last_x: float = 1.99
	for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var sample: Dictionary = view.sample(fraction)
		var actor: Dictionary = sample.units[0]
		_check(is_equal_approx(float(actor.x), 2.0 + 0.12 * fraction), "Intermediate render position follows observed segment")
		_check(float(actor.x) > last_x, "Every render subframe advances without a 30 Hz position hold")
		_check(float(sample.presentation_time) <= float(sample.time) and float(sample.time) - float(sample.presentation_time) <= STEP + 0.000001, "Presentation never extrapolates or adds more than one tick of latency")
		_check((sample.events.size() == 1) == (fraction == 1.0), "Shot enters the same continuous presentation timeline exactly once eligible")
		_check((float(actor.hp) == 0.0) == (fraction == 1.0), "Lethal result does not precede its shot event")
		last_x = float(actor.x)
	var middle: Dictionary = view.sample(0.5)
	_check(absf(absf(float(middle.units[0].facing)) - PI) < 0.001, "Facing interpolates across PI by the short arc")
	_check(absf(absf(float(middle.units[0].body_facing)) - PI) < 0.001, "Physical body yaw stays continuous across PI on live render subframes")
	_check(is_equal_approx(float(middle.units[0].aim_facing), 0.2), "Upper-body aim interpolates independently")
	_check(is_equal_approx(float(middle.units[0].move_facing), -0.4), "Lower-body travel facing interpolates independently")
	_check(is_equal_approx(float(middle.units[0].travel_distance), 0.06), "Travel distance advances continuously for distance-driven gait")
	_check(is_equal_approx(float(middle.doors[0].progress), 0.05), "Door progress shares the interpolation clock")
	_check(view.sample(-1.0).units[0].x == before.units[0].x and view.sample(2.0).units[0].x == after.units[0].x, "Out-of-range fractions cannot extrapolate through walls")
	_check(JSON.stringify(before) == original_before and JSON.stringify(after) == original_after, "Presentation leaves simulation and replay observations immutable")

func _test_observation_boundaries() -> void:
	var view = Presentation.new()
	var before: Dictionary = _state(0.0, 2.0)
	var after: Dictionary = _state(STEP, 2.1)
	before.enemies = [{"id": "target1", "x": 4.0, "z": 4.0, "visible": false, "last_seen": [4.0, 4.0]}]
	after.enemies = [{"id": "target1", "x": 5.0, "z": 4.0, "visible": true, "hp": 72.0}]
	view.reset(before)
	view.capture(after)
	_check(view.sample(0.0).enemies[0].x == 5.0, "New contact snaps to its first observed pose instead of revealing its hidden route")
	before = after.duplicate(true)
	after = _state(STEP * 2.0, 2.2)
	after.enemies = [{"id": "target1", "x": 5.0, "z": 4.0, "visible": false, "last_seen": [5.0, 4.0]}]
	view.reset(before)
	view.capture(after)
	var hidden: Dictionary = view.sample(0.0).enemies[0]
	_check(not hidden.visible and not hidden.has("hp"), "Loss of sight uses the latest filtered ghost record immediately")
	_check(hidden.x == 5.0 and hidden.last_seen == [5.0, 4.0], "Hidden marker remains at the observed location")
	before = after.duplicate(true)
	after = _state(STEP * 3.0, 2.3)
	view.reset(before)
	view.capture(after)
	_check(view.sample(0.0).enemies.is_empty(), "An entity removed from the observation cannot linger for an extra tick")
	after.enemies = [{"id": "target2", "x": 8.0, "z": 4.0, "visible": true}]
	view.reset(before)
	view.capture(after)
	_check(view.sample(0.5).enemies.size() == 1 and view.sample(0.5).enemies[0].id == "target2", "Interpolation pairs by ID rather than array order")

func _test_reset_and_slow_frames() -> void:
	var view = Presentation.new()
	view.reset(_state(0.0, 2.0))
	for tick: int in range(1, 5):
		view.capture(_state(STEP * tick, 2.0 + tick * 0.1))
	_check(is_equal_approx(float(view.sample(0.5).units[0].x), 2.35), "A slow frame uses the latest adjacent tick pair, not the last rendered frame")
	var paused: Dictionary = _state(STEP * 4.0, 2.4)
	view.reset(paused)
	_check(view.sample(0.0).units[0].x == 2.4 and view.sample(0.9).units[0].x == 2.4, "Pausing freezes the exact authoritative position without residual drift")
	view.capture(_state(STEP * 5.0, 2.5))
	_check(is_equal_approx(float(view.sample(0.5).units[0].x), 2.45), "Resume starts from the settled paused position")
	view.capture(_state(0.0, 2.0))
	_check(view.sample(0.5).units[0].x == 2.0 and view.sample(0.5).presentation_time == 0.0, "A rewind clears all prior motion and time")
	view.capture(_state(STEP * 10.0, 3.0))
	_check(view.sample(0.0).units[0].x == 3.0, "A discontinuous snapshot gap resets rather than introducing extra latency")
	view.capture(_state(STEP * 11.0, 20.0))
	_check(view.sample(0.5).units[0].x == 20.0, "Teleport discontinuities never sweep across a room")

func _test_replay_observation_and_metadata() -> void:
	var before: Dictionary = _state(0.0, 2.0)
	before.enemies = [{"id": "target1", "kind": "enemy", "x": 6.0, "z": 4.0, "visible": true, "facing": 0.0, "aim_facing": -0.3, "move_facing": -0.6, "travel_distance": 2.0}]
	var after: Dictionary = _state(0.1, 2.3)
	after.units[0].aim_facing = -0.4
	after.units[0].move_facing = -0.8
	after.enemies = [{"id": "target1", "kind": "enemy", "x": 7.0, "z": 4.0, "visible": false, "facing": 1.0, "aim_facing": 1.2, "move_facing": 1.4, "travel_distance": 3.0}]
	var replay = Replay.new()
	replay.begin(JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json")))
	replay.capture(before)
	replay.finish(after)
	var observed: Dictionary = replay.seek(0.05, false)
	_check(observed.enemies[0].x == 6.0 and observed.enemies[0].aim_facing == -0.3, "Observed replay never interpolates toward future hidden coordinates or aim")
	_check(replay.seek(0.1, false).enemies.is_empty(), "Observed replay hides the enemy at the recorded loss-of-sight boundary")
	_check(is_equal_approx(float(replay.seek(0.05, true).enemies[0].x), 6.5), "Explicit full-reveal replay can interpolate omniscient data")
	_check(is_equal_approx(float(observed.units[0].aim_facing), -0.2) and is_equal_approx(float(observed.units[0].move_facing), -0.4), "Replay preserves independently interpolated aim and movement angles")
	_check(is_equal_approx(float(observed.units[0].travel_distance), 0.15), "Replay keeps distance-driven gait continuous")
	var imported = Replay.new()
	var loaded: Dictionary = imported.load_data(JSON.parse_string(JSON.stringify(replay.export_data())))
	_check(bool(loaded.get("ok", false)), "Replay import accepts signed aim/movement angles and travel distance: " + str(loaded.get("message", "")))
	if bool(loaded.get("ok", false)):
		_check(is_equal_approx(float(imported.seek(0.05, false).units[0].aim_facing), -0.2), "Export/import retains animation presentation metadata")
	var original: String = JSON.stringify(replay.seek(0.05, false))
	replay.seek(0.1, true)
	replay.seek(0.0, false)
	_check(JSON.stringify(replay.seek(0.05, false)) == original, "Reveal switches and rewinds do not pollute observed replay state")
