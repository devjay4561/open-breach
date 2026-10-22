extends SceneTree
class Harness extends "res://scripts/main.gd":
	var messages: Array = []
	func _emit(message: Dictionary) -> void:
		messages.append(message.duplicate(true))
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app := Harness.new()
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	var original: String = app.mission_id
	app.ui_inbox.append({"action":"start", "mission":"M06", "_loading_id":"test-start"})
	app.ui_inbox.append({"action":"tool", "tool":"face"})
	app._process(0.0)
	check(app.mission_id == original, "Loading announces before replacing the mission")
	check(app.messages.any(func(m): return m.type == "loading" and m.active), "Loading notification is emitted")
	await process_frame
	await process_frame
	await process_frame
	app._flush_inputs()
	check(app.mission_id == original, "Input callbacks cannot run pending scene loads")
	app._process(0.0)
	check(app.mission_id == "M06" and app.mode == "PLANNING", "Deferred mission load completes")
	check(app._loading_finished, "Completion waits for the loaded world to render")
	check(not app.messages.any(func(m): return m.type == "loading" and not m.active), "No premature completion event")
	app._process(0.4)
	check(app.messages.any(func(m): return m.type == "loading" and not m.active and m.id == "test-start"), "Matching completion event releases loading")
	check(app.tool == "face", "Intent after loading is preserved in order")
	check(app.sim.time == 0.0, "Loading does not advance mission time")
	app.ui_inbox.append({"action":"start", "mission":"INVALID", "_loading_id":"test-invalid"})
	app._process(0.0)
	await process_frame
	await process_frame
	await process_frame
	app._process(0.0)
	app._process(0.0)
	check(app.mission_id == "M06", "Invalid mission leaves the current mission intact")
	check(app.messages.any(func(m): return m.type == "loading" and not m.active and m.id == "test-invalid"), "Validation failure also completes loading")
	app.queue_free()
	await process_frame
	await process_frame
	print("BREACH_LOADING_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
