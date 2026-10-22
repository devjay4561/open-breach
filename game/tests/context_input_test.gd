extends SceneTree
## Actual controller and presentation input, with no hidden enemy fixture data.
const MainScene = preload("res://main.tscn")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	await process_frame
	check(not Input.use_accumulated_input, "Drawing input still merges rapid key/mouse gestures between render frames")
	session._action({"action": "start", "mission": "M01", "seed": "shared-puzzle-2026"})
	var catalog: Dictionary = session._public_catalog()
	check(catalog.size() == session.maps.size() and catalog.M01.has("rooms") and not catalog.M01.has("enemies") and not catalog.M01.has("civilians") and not catalog.M01.has("spawns"), "Menu catalog leaked undiscovered actors or lost known layout")
	check(session.sim.mission.seed == session._seed_value("shared-puzzle-2026"), "String seed was not deterministically configured")
	check(session._seed_value("1234") == 1234 and session._seed_value(1234) == 1234, "Numeric seed formats differ")
	var before_options: String = JSON.stringify(session.sim.snapshot(true))
	session._action({"action": "start", "mission": "M01", "loadout": {"alpha": false}})
	check(JSON.stringify(session.sim.snapshot(true)) == before_options, "Malformed per-unit loadout changed the active mission")
	check(not session._options_error({"loadout": {"alpha": {"equipment": {"smoke": {"bad": 1}}}}}).is_empty(), "Non-numeric equipment stock was accepted")
	check(not session._options_error({"modifiers": ["unknown_condition"]}).is_empty(), "Unknown conditions were accepted")
	check(not session._options_error({"modifiers": ["night", "night"]}).is_empty(), "Duplicate conditions accepted a plan that replay import would reject")
	check(not session._options_error({"roster": [{"id": "대원", "base_id": "alpha"}]}).is_empty(), "Non-ASCII roster ID accepted a plan that replay import would reject")
	check(session._options_error({"roster": [{"id": "raven-1.slot:two_2", "base_id": "alpha"}]}).is_empty(), "Replay-compatible ASCII roster identifiers were rejected")
	session._action({"action": "start", "mission": "M01", "modifiers": ["night", "night"]})
	check(JSON.stringify(session.sim.snapshot(true)) == before_options, "Rejected duplicate conditions changed the active mission")
	session._action({"action": "start", "mission": "M01", "roster": [{"id": "대원", "base_id": "alpha"}]})
	check(JSON.stringify(session.sim.snapshot(true)) == before_options, "Rejected roster identifier changed the active mission")
	check(not session._options_error({"roster": [{"id": "raven", "base_id": "alpha"}, {"id": "raven", "base_id": "bravo"}]}).is_empty(), "Duplicate roster identities were accepted")
	session._action({"action": "command", "type": "MOVE", "args": {"target": [12.2, 14.6]}})
	session._process(0.1)
	var unit: Dictionary = session.sim.units[0]
	var index: int = unit.commands.size() - 1
	check(index >= 0 and unit.commands[index].type == "MOVE", "Input fixture move was rejected")
	if index < 0:
		quit(1)
		return
	var point: Vector2 = Vector2(float(unit.commands[index].args.target[0]), float(unit.commands[index].args.target[1]))
	var screen: Vector2 = session.world.camera.unproject_position(Vector3(point.x, 0.25, point.y))
	var picked: Dictionary = session.world.pick_waypoint(screen, session.selected)
	check(not picked.is_empty() and int(picked.get("index", -1)) == index, "Waypoint picking lost command list index")
	session._action({"action": "select_command", "index": index})
	check(session.selected_command == index and session.world._selected_waypoint == index, "Sidebar and map node selection diverged")
	var revisions: int = session.sim.plan_revisions
	var press := InputEventMouseButton.new()
	press.position = screen
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	session._arm_drag("waypoint", press, picked)
	var motion := InputEventMouseMotion.new()
	motion.position = screen + Vector2(5, 0)
	session._mouse_motion(motion)
	check(not bool(session.drag.active), "Drag started before the 6px threshold")
	motion.position = screen + Vector2(8, 0)
	session._mouse_motion(motion)
	check(bool(session.drag.active), "Drag did not start after the 6px threshold")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	session._unhandled_input(escape)
	check(session.drag.is_empty() and session.sim.plan_revisions == revisions, "Esc mutated an uncommitted waypoint drag")
	var target_before_escape: Array = unit.commands[index].args.target.duplicate()
	session._arm_drag("waypoint", press, picked)
	session._mouse_motion(motion)
	session.ui_inbox.append({"action": "escape"})
	var release := InputEventMouseButton.new()
	release.position = motion.position
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	session._unhandled_input(release)
	check(session.drag.is_empty() and unit.commands[index].args.target == target_before_escape and session.sim.plan_revisions == revisions, "Queued browser Escape did not precede the same-frame mouse release")
	var samples: Array = []
	for sample: int in range(180): samples.append([float(sample) * 0.05, sin(float(sample))])
	var simplified: Array = session._simplify_points(samples, 0.05)
	check(simplified.size() <= 32 and simplified[0] == samples[0] and simplified[-1] == samples[-1], "Drag simplification failed its cap or endpoints")
	var unobserved: String = ""
	for door: Dictionary in session.shown.doors:
		if not bool(door.get("observed", true)):
			var door_screen: Vector2 = session.world.camera.unproject_position(Vector3(float(door.x), 0.7, float(door.z)))
			check(session.world.pick_door(door_screen) != str(door.id), "An unobserved door can open a popover")
			unobserved = str(door.id)
	check(not unobserved.is_empty(), "Fixture contained no unobserved door for privacy check")
	var public_state: Dictionary = session.world._state.duplicate(true)
	var overlap_door: Dictionary = {}
	for door: Dictionary in public_state.doors:
		if str(door.id) == "d7": overlap_door = door.duplicate(true)
	overlap_door["observed"] = true
	overlap_door["state"] = "OPEN"
	overlap_door["progress"] = 1.0
	var overlap_actor: Dictionary = {"id": "e5", "x": 4.79128, "z": 7.97437, "hp": 28, "visible": true, "status": "SURRENDERED"}
	session.world._state = {"doors": [overlap_door], "enemies": [overlap_actor], "units": [], "civilians": []}
	var actor_screen: Vector2 = session.world.camera.unproject_position(Vector3(float(overlap_actor.x), 0.95, float(overlap_actor.z)))
	check(session.world.pick_door(actor_screen) == "d7", "Authored e5/d7 fixture no longer exercises an overlapping door hit")
	check(session._pick_context(actor_screen, false) == {"target": "enemy", "id": "e5"}, "An open door label stole the precise surrendered actor context click")
	session.world._state.enemies = []
	session.world._state.civilians = [overlap_actor]
	check(session._pick_context(actor_screen, false) == {"target": "civilian", "id": "e5"}, "An open door label stole the precise civilian context click")
	session.world._state = public_state
	session._action({"action": "toggle"})
	var unit_screen: Vector2 = session.world.camera.unproject_position(Vector3(float(unit.x), 0.95, float(unit.z)))
	session._open_context({"target": "unit", "id": session.selected}, unit_screen)
	check(session.mode == "PLANNING" and session.context_open, "Context opening did not pause execution")
	var frozen: float = session.sim.time
	session._process(0.1)
	check(session.sim.time == frozen, "Open popover advanced authoritative time")
	session._action({"action": "context_close"})
	session._action({"action": "retry"})
	check(session.sim.mission.seed == session._seed_value("shared-puzzle-2026"), "Fresh retry lost the current seed")
	var exported: Dictionary = session._export_plan()
	session._action({"action": "load_plan", "data": exported})
	check(session.sim.mission.seed == int(exported.seed), "Plan import lost seed metadata")
	for key: String in ["seed", "variant", "modifiers", "loadout", "roster"]: exported.erase(key)
	session._action({"action": "load_plan", "data": exported})
	check(session.sim.mission.seed == int(session.maps.M01.seed), "Schema 1 plan without metadata did not default to mission seed")
	session.mode = "REPLAY"
	session._open_context({"target": "unit", "id": session.selected}, unit_screen)
	check(not session.context_open, "Replay mode opened a command popover")
	session.queue_free()
	await process_frame
	print("BREACH_CONTEXT_INPUT_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
