extends SceneTree
## P6 controller contracts: real fixed-step motion, exact replay ticks, and
## a detached own-only overlay. Scene frames only initialize native nodes.
const MainScene = preload("res://main.tscn")
const Fixture = preload("res://tests/roe_browser_preflight_test.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

class RecordingMain extends "res://scripts/main.gd":
	var messages: Array[Dictionary] = []
	func _emit(message: Dictionary) -> void:
		messages.append(message.duplicate(true))

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func bridge(session: Node, action: Dictionary) -> void:
	session._on_web_message([JSON.stringify(action)])
	session._flush_inputs()

func settle_loading(session: Node) -> void:
	for _frame: int in range(8):
		await process_frame
		session._process(0.0)
		if session._loading_request.is_empty() and not session._loading_finished: return
	check(false, "Replay transition settles within bounded zero-delta scene frames")

func run() -> void:
	var session: Node = MainScene.instantiate()
	session.set_script(RecordingMain)
	root.add_child(session)
	session.set_process(false)
	await process_frame
	var mission := Fixture.fixture("precision")
	mission["id"] = "P6_PRIOR_MAIN"
	mission["win"] = [{"type":"reach_zone", "zone":[5.0,5.8,0.4,0.4]}]
	check(not session._register_custom(mission).is_empty(), "Authored overlay fixture passes strict schema")
	session._load_mission(mission.id, true)
	check(session.prior_attempt.is_empty(), "Fresh mission has no invented previous run")
	bridge(session, {"action":"command", "unit_id":"alpha", "type":"MOVE", "args":{"target":[5.0,5.8]}})
	var initial: Dictionary = session._export_plan()
	session._toggle()
	for _step: int in range(180):
		if not session.sim.result.is_empty(): break
		session.sim.step(STEP)
		session.recorder.capture(session.sim.snapshot(true), session.sim.take_record_events())
	check(not session.sim.result.is_empty() and session.sim.result.success, "Actual MOVE completes the authored objective")
	session._finish_mission()
	var recorded: Dictionary = session.recorder.data.duplicate(true)
	var terminal_tick: int = session.sim.tick
	check(terminal_tick > 0 and session.recorder.frames.back()[1] == terminal_tick, "Finished recorder retains the real terminal tick")
	bridge(session, {"action":"replay"})
	await settle_loading(session)
	check(session.mode == "REPLAY", "Actual replay transition acknowledges before seeking")
	bridge(session, {"action":"replay_seek", "tick":terminal_tick, "time":0.0})
	check(session.shown.tick == terminal_tick and session.replay_time == float(terminal_tick) * STEP, "Tick takes precedence over a conflicting time and seeks the exact retained frame")
	check(not session.replay_playing, "Evidence link pauses on its exact tick")
	for invalid: Variant in [-1,0.5,"1",true,terminal_tick+1]:
		bridge(session, {"action":"replay_seek", "tick":invalid, "time":0.0})
		check(session.shown.tick == terminal_tick, "Invalid evidence tick cannot fall back to a valid time")
	bridge(session, {"action":"replay_seek", "time":0.0})
	check(session.shown.tick == 0, "Legacy time-only replay seek remains supported")
	session._import_plan(initial, false)
	check(session.mode == "PLANNING" and session.sim.tick == 0, "Retry plan starts a fresh simulation")
	check(not session.prior_attempt.is_empty() and not session.prior_attempt.paths.is_empty(), "Retry copied the actual prior run before resetting the recorder")
	check(not JSON.stringify(session.prior_attempt).contains("unseen"), "Prior overlay contains no hidden NPC identity")
	var prior: Dictionary = session.prior_attempt.duplicate(true)
	var authority: Dictionary = session.sim.snapshot(true)
	var random_states: Array = [session.sim._rng.state,session.sim._hit_region_rng.state,session.sim._breach_rng.state,session.sim._surrender_rng.state]
	session.world.display(session.shown, "alpha", true, 0.0)
	check(session.world._prior_attempt_node.visible and session.world._prior_attempt_mesh.get_surface_count() == 1, "Planning draws the faded owned path")
	bridge(session, {"action":"prior_attempt_visible", "value":false})
	session.world.display(session.shown, "alpha", true, 0.0)
	check(not session.world._prior_attempt_node.visible and not session.prior_attempt_visible, "Native acknowledgement hides the planning overlay")
	bridge(session, {"action":"prior_attempt_visible", "value":true})
	session.world.display(session.shown, "alpha", true, 0.0)
	check(session.world._prior_attempt_node.visible, "Overlay can be restored without changing the attempt")
	check(authority == session.sim.snapshot(true) and random_states == [session.sim._rng.state,session.sim._hit_region_rng.state,session.sim._breach_rng.state,session.sim._surrender_rng.state], "Presentation toggles preserve simulation and all RNG streams")
	session.world.display(session.shown, "alpha", false, 0.0)
	check(not session.world._prior_attempt_node.visible, "Execution and replay do not draw a planning overlay")
	session.recorder.data["frames"].clear()
	check(session.prior_attempt == prior and session.world._prior_attempt == prior, "Recorder reset or mutation cannot alter copied prior poses")
	check(recorded.frames.size() > 1, "Original evidence copy also remains independently owned")
	session._load_mission(mission.id, true, {"seed":43})
	check(session.prior_attempt.is_empty() and session.world._prior_attempt.is_empty(), "Different seed clears the previous attempt")
	session.queue_free()
	await process_frame
	print("BREACH_PRIOR_ATTEMPT_MAIN_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
