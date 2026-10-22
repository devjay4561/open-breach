extends SceneTree
const Main = preload("res://scripts/main.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func quiet(app: Node) -> void:
	app._update_idle_throttle(0.0)
	app._update_idle_throttle(0.6)
	check(Engine.max_fps == 60, "A short pause keeps the active frame cap")
	app._update_idle_throttle(0.5)
	check(Engine.max_fps == Main.IDLE_FPS, "A quiet planning/result/paused replay throttles after one second")
func run() -> void:
	check(Main.IDLE_FPS == 20, "Idle cap keeps the requested 20 fps wake latency")
	var original := Engine.max_fps
	Engine.max_fps = 60
	var app := Main.new()
	root.add_child(app)
	app.set_process(false)
	app._process(0.0)
	for frame: int in range(90): app._process(1.0 / 60.0)
	check(Engine.max_fps == Main.IDLE_FPS, "The real display/process path settles into idle without signature churn")
	app._wake_render()
	quiet(app)
	app._input(InputEventMouseMotion.new())
	check(Engine.max_fps == 60 and app._render_quiet == 0.0, "Any input restores the cap synchronously before the next frame")
	quiet(app)
	var command_count: int = app.sim.units[0].commands.size()
	app._action({"action":"command", "type":"WAIT", "args":{"duration":1.0}})
	check(Engine.max_fps == 60 and app.sim.units[0].commands.size() == command_count + 1, "An accepted plan edit via action wakes rendering synchronously")
	app._process(0.0)
	quiet(app)
	app.shown = app.shown.duplicate(false)
	app._update_idle_throttle(0.0)
	check(Engine.max_fps == 60, "A replacement snapshot wakes rendering even with identical values")
	quiet(app)
	app._shown_dirty = true
	app._update_idle_throttle(0.0)
	check(Engine.max_fps == 60, "An in-place edit marked dirty wakes rendering without scanning values")
	app._process(0.0)
	quiet(app)
	app.recorder.content_revision += 1
	app._update_idle_throttle(0.0)
	check(Engine.max_fps == 60, "Recorder revision changes wake rendering")
	quiet(app)
	var other_unit: String = str(app.shown.units[1].id)
	app._action({"action":"select", "unit_id":other_unit})
	check(Engine.max_fps == 60 and app.selected == other_unit, "Selection actions wake rendering synchronously")
	quiet(app)
	app._select(str(app.shown.units[0].id))
	app._update_idle_throttle(0.0)
	check(Engine.max_fps == 60, "Direct selection changes are covered by the small signature")
	quiet(app)
	var settings: Dictionary = app.settings
	app._action({"action":"settings", "settings":{"language":"en"}})
	check(Engine.max_fps == 60 and is_same(settings, app.settings) and app.settings.language == "en", "In-place settings actions wake rendering without hashing settings")
	app._process(0.0)
	quiet(app)
	app.world.pan(Vector2.RIGHT, 0.1)
	app._update_idle_throttle(0.0)
	check(Engine.max_fps == 60, "Camera pan wakes rendering")
	quiet(app)
	app.world.zoom(-0.2)
	app._update_idle_throttle(0.0)
	check(Engine.max_fps == 60, "Camera zoom wakes rendering")
	quiet(app)
	root.size_changed.emit()
	check(Engine.max_fps == 60, "Viewport resize wakes rendering synchronously")
	quiet(app)
	app._action({"action":"tool", "tool":"face"})
	check(Engine.max_fps == 60, "Toolbar actions wake rendering synchronously")
	quiet(app)
	app._on_web_message([JSON.stringify({"action":"tool", "tool":"select"})])
	check(Engine.max_fps == 60, "Web callbacks wake rendering before input is flushed")
	app._process(0.0)
	check(app.tool == "select" and app.ui_inbox.is_empty(), "The queued web action is applied before returning to idle")
	for next_mode: String in ["RESULT", "REPLAY"]:
		app.mode = next_mode
		app._update_idle_throttle(0.0)
		check(Engine.max_fps == 60, "Mode changes wake rendering")
		quiet(app)
	app._action({"action":"import_replay", "data":JSON.parse_string(FileAccess.get_file_as_string("res://../tests/artifacts/combat-benchmark.breach-replay.json"))})
	check(app.mode == "REPLAY" and app.recorder.duration == 40.0, "Replay seek test uses the real combat recording")
	app.replay_playing = false
	app._process(0.0)
	quiet(app)
	var before_seek: Dictionary = app.shown
	app._action({"action":"replay_seek", "time":8.0})
	check(Engine.max_fps == 60 and app.replay_time == 8.0 and not is_same(before_seek, app.shown), "Paused replay seek wakes synchronously and replaces the sampled snapshot")
	app._process(0.0)
	quiet(app)
	before_seek = app.shown
	app._action({"action":"replay_seek", "time":8.0})
	check(Engine.max_fps == 60 and is_same(before_seek, app.shown), "Same-time seek still wakes through the action revision")
	quiet(app)
	app.replay_playing = true
	app._update_idle_throttle(5.0)
	check(Engine.max_fps == 60, "Playing replay always runs at the active cap")
	app.mode = "EXECUTING"
	app._update_idle_throttle(5.0)
	check(Engine.max_fps == 60, "Executing always runs at the active cap")
	app.mode = "MENU"
	app._update_idle_throttle(5.0)
	check(Engine.max_fps == 30, "Menu drift keeps a smooth 30 fps cap")
	app.mode = "PLANNING"
	app._update_idle_throttle(0.0)
	quiet(app)
	app.world._shake_remaining = 0.2
	app._update_idle_throttle(2.0)
	check(Engine.max_fps == 60, "Real-time camera effects keep the active rate")
	app.world._shake_remaining = 0.0
	quiet(app)
	app._queue_loading({"action":"start", "mission":"M01"})
	check(Engine.max_fps == 60, "Loading restores the active rate synchronously")
	app._update_idle_throttle(5.0)
	check(Engine.max_fps == 60, "A pending load cannot enter idle")
	app._loading_request.clear()
	Engine.max_fps = 8
	app._update_idle_throttle(2.0)
	check(Engine.max_fps == 8, "Idle never raises an externally configured lower cap")
	app._wake_render()
	check(Engine.max_fps == 8, "Wake respects a cap changed while idle")
	app.queue_free()
	await process_frame
	check(Engine.max_fps == 8, "Freeing the controller restores its current configured cap")
	Engine.max_fps = original
	print("BREACH_IDLE_RENDER_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
