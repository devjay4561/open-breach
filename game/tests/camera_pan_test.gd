extends SceneTree
const MainScene = preload("res://main.tscn")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func press(session: Node, button: int, at: Vector2, alt: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.pressed = true
	event.alt_pressed = alt
	session._unhandled_input(event)

func motion(session: Node, at: Vector2, button: int = MOUSE_BUTTON_MIDDLE) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.button_mask = 1 << (button - 1)
	session._unhandled_input(event)

func release(session: Node, button: int, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	session._unhandled_input(event)

func _run() -> void:
	root.size = Vector2i(1440, 900)
	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	await process_frame
	session._action({"action":"start", "mission":"T01"})
	session.world.set_safe_area({"left":250.0,"right":270.0,"top":48.0,"bottom":72.0})
	var start := Vector2(650, 460)
	var end := start + Vector2(160, -90)
	var baseline: String = JSON.stringify(session.sim.snapshot(true))
	for zoom: float in [-3.0, 0.0, 4.0]:
		session.world.reset_camera()
		session.world.zoom(zoom)
		var ground: Vector2 = session.world.screen_to_ground(start)
		press(session, MOUSE_BUTTON_MIDDLE, start)
		motion(session, end)
		var projected: Vector2 = session.world.camera.unproject_position(Vector3(ground.x, 0.2, ground.y))
		check(projected.distance_to(end) < 0.1, "Grab follows cursor exactly at zoom %s" % zoom)
		release(session, MOUSE_BUTTON_MIDDLE, end)
		var position: Vector3 = session.world.camera.position
		motion(session, start)
		check(session.world.camera.position.is_equal_approx(position), "Release stops panning")
	check(JSON.stringify(session.sim.snapshot(true)) == baseline, "Camera gestures do not alter orders, actors or simulation time")
	session.world.reset_camera()
	var origin: Vector3 = session.world.camera.position
	press(session, MOUSE_BUTTON_LEFT, start, true)
	motion(session, end, MOUSE_BUTTON_LEFT)
	release(session, MOUSE_BUTTON_LEFT, end)
	check(not session.world.camera.position.is_equal_approx(origin), "Alt-left drag pans without issuing a command")
	check(JSON.stringify(session.sim.snapshot(true)) == baseline, "Alt-left drag leaves the plan unchanged")
	session._action({"action":"tool","tool":"pan"})
	press(session, MOUSE_BUTTON_LEFT, start)
	motion(session, end, MOUSE_BUTTON_LEFT)
	check(session.camera_drag_button == MOUSE_BUTTON_LEFT and session.drag.is_empty(), "Pan tool uses a camera grab, not a unit path")
	session._action({"action":"input_focus","blocked":true})
	check(session.camera_drag_button == 0, "Text input cancels a camera grab")
	session._action({"action":"input_focus","blocked":false})
	session.mode = "EXECUTING"
	press(session, MOUSE_BUTTON_MIDDLE, start)
	motion(session, end)
	check(session.mode == "EXECUTING", "Panning does not pause execution")
	session._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(session.camera_drag_button == 0, "Application blur releases camera drag")
	session.mode = "REPLAY"
	session._action({"action":"ui_focus","data":{"active":true}})
	session.replay_follow = "alpha"
	press(session, MOUSE_BUTTON_MIDDLE, start)
	check(session.camera_drag_button == MOUSE_BUTTON_MIDDLE, "Replay HUD does not block map grabs")
	check(session.replay_follow.is_empty(), "Manual panning releases replay follow")
	motion(session, end)
	session._escape()
	check(session.camera_drag_button == 0 and session.mode == "REPLAY", "Escape cancels the camera gesture in replay")
	session.mode = "PLANNING"
	session._action({"action":"ui_focus","data":{"active":true}})
	press(session, MOUSE_BUTTON_MIDDLE, start)
	check(session.camera_drag_button == 0, "UI overlays cannot initiate map grabs")
	session._action({"action":"ui_focus","data":{"active":false}})
	for i in range(100): session.world.drag_pan(start, end)
	check(absf(session.world._pan.x) <= session.world.bounds().x * 0.65 + 0.001 and absf(session.world._pan.y) <= session.world.bounds().y * 0.65 + 0.001, "Repeated grabs stay within map pan bounds")
	session._action({"action":"reset_camera"})
	check(session.world._pan == Vector2.ZERO and is_equal_approx(session.world._zoom, 1.0), "Reset restores whole-map framing and zoom")
	session.queue_free()
	await process_frame
	print("BREACH_CAMERA_PAN_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
