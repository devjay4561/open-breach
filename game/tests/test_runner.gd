extends SceneTree

const STEP: float = 1.0 / 30.0
const SIMULATION_PATH: String = "res://scripts/simulation.gd"
const NAVIGATION_PATH: String = "res://scripts/navigation.gd"
const DoorGeometry = preload("res://scripts/door_geometry.gd")
var checks: int = 0
var failures: Array[String] = []
var simulation_script: Script
var navigation_script: Script
var tutorial_recording: Dictionary = {}
var tutorial_final: Dictionary = {}
var case_reached_end: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	navigation_script = load(NAVIGATION_PATH)
	var navigation_only: bool = OS.get_cmdline_user_args().has("--navigation-only")
	if not navigation_only:
		simulation_script = load(SIMULATION_PATH)
	if (not navigation_only and simulation_script == null) or navigation_script == null:
		push_error("Regression runner could not load simulation/navigation scripts")
		quit(2)
		return
	var cases: Array[String] = [
		"_test_navigation_obstacles", "_test_door_navigation_states", "_test_mission_reachability",
		"_test_command_sequence", "_test_failure_blocks_queue",
		"_test_signal_pulses", "_test_door_execution", "_test_malformed_commands",
		"_test_civilian_idempotence", "_test_allied_line_safety",
		"_test_reload_and_stun", "_test_hidden_information", "_test_mission_results",
		"_test_tutorial_completion", "_test_pause_without_ticks"
	]
	if FileAccess.file_exists("res://scripts/replay.gd"):
		cases.append("_test_replay_contract")
	if navigation_only:
		cases = ["_test_navigation_obstacles", "_test_door_navigation_states", "_test_mission_reachability"]
	for method: String in cases:
		var before: int = failures.size()
		case_reached_end = false
		await call(method)
		check(case_reached_end, "%s aborted before reaching its final assertion" % method)
		print("%s %s" % ["PASS" if before == failures.size() else "FAIL", method.trim_prefix("_test_")])
	print("BREACH_REGRESSION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func fixture() -> Dictionary:
	return {
		"id": "T01", "revision": 1, "title": "Regression fixture", "seed": 42,
		"bounds": [16, 12], "rooms": [], "walls": [], "doors": [], "props": [],
		"units": [{"id": "alpha", "name": "ALPHA", "role": "선봉", "x": 2.0, "z": 5.0, "facing": 0.0, "weapon": "standard"}],
		"enemies": [], "civilians": [], "objectives": []
	}

func simulation(data: Dictionary = {}) -> RefCounted:
	var instance: RefCounted = simulation_script.new()
	instance.load_mission(fixture() if data.is_empty() else data)
	return instance

func advance(sim: RefCounted, seconds: float) -> void:
	for index: int in range(ceili(seconds / STEP)):
		sim.step(STEP)

func command_states(sim: RefCounted, unit_index: int = 0) -> Array:
	var result: Array = []
	for command: Dictionary in sim.units[unit_index].get("commands", []):
		result.append(command.get("state", ""))
	return result

func position(entity: Dictionary) -> Vector2:
	return Vector2(float(entity.get("x", 0.0)), float(entity.get("z", 0.0)))

func _test_navigation_obstacles() -> void:
	var data: Dictionary = fixture()
	data.walls = [{"x": 6.0, "z": 5.0, "w": 0.5, "d": 6.0}, {"x": 8.0, "z": 8.0, "w": 4.5, "d": 0.5}]
	var nav: RefCounted = navigation_script.new()
	nav.build(data, [])
	check(not nav.segment_clear(Vector2(4, 5), Vector2(8, 5)), "AC07: a ray through a solid wall was accepted")
	check(not nav.walkable(Vector2(6, 5)), "AC07: wall interior was walkable")
	check(not nav.walkable(Vector2(-1, 5)), "AC07: outside-map destination was walkable")
	var path: Array = nav.path(Vector2(3, 5), Vector2(11, 5))
	check(not path.is_empty(), "AC07: reachable destination around L-shaped wall had no path")
	var previous: Vector2 = Vector2(3, 5)
	for waypoint: Array in path:
		var current: Vector2 = Vector2(float(waypoint[0]), float(waypoint[1]))
		check(nav.segment_clear(previous, current, 0.23), "AC07: smoothed path clips an expanded wall/corner")
		previous = current
	case_reached_end = true

func doorway_fixture() -> Dictionary:
	var data: Dictionary = fixture()
	data.units[0].x = 7.0
	data.units[0].z = 4.0
	data.units[0].facing = PI / 2.0
	data.walls = [{"x": 3.0, "z": 6.0, "w": 6.0, "d": 0.3}, {"x": 11.0, "z": 6.0, "w": 10.0, "d": 0.3}]
	data.doors = [{"id": "door_1", "x": 7.0, "z": 6.0, "w": 2.0, "d": 0.3, "axis": "x", "state": "CLOSED", "progress": 0.0}]
	# Correct second wall starts at x=8, leaving precisely the door aperture 6..8.
	data.walls[1].x = 12.0
	data.walls[1].w = 8.0
	return data

func _test_door_navigation_states() -> void:
	var data: Dictionary = doorway_fixture()
	var nav: RefCounted = navigation_script.new()
	nav.build(data, data.doors)
	for state: String in ["CLOSED", "OPENING"]:
		data.doors[0].state = state
		nav.rebuild()
		check(not nav.segment_clear(Vector2(7, 4), Vector2(7, 8)), "AC09: %s door allowed LOS" % state)
		check(nav.path(Vector2(7, 4), Vector2(7, 8)).is_empty(), "AC09: %s door allowed crossing path" % state)
	data.doors[0].state = "OPEN"
	nav.rebuild()
	check(nav.segment_clear(Vector2(7, 4), Vector2(7, 8)), "AC09: OPEN door still blocked LOS")
	check(not nav.path(Vector2(7, 4), Vector2(7, 8)).is_empty(), "AC09: OPEN door still blocked route")
	case_reached_end = true

func _test_mission_reachability() -> void:
	for filename: String in ["tutorial", "house"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % filename))
		var initial_nav: RefCounted = navigation_script.new()
		initial_nav.build(data, data.doors)
		var nav: RefCounted = navigation_script.new()
		var doors: Array = data.doors.duplicate(true)
		for door: Dictionary in doors:
			door.state = "OPEN"
			# The authored hinge stays fixed. Opening can sweep the initial
			# operator position, so actors retreat before the door finishes.
		nav.build(data, doors)
		var origin: Vector2 = _open_layout_position(position(data.units[0]), initial_nav, nav)
		check(origin.x >= 0.0, "AC15: %s has no locally reachable insertion after opening" % filename)
		for category: String in ["units", "enemies", "civilians"]:
			for entity: Dictionary in data.get(category, []):
				check(initial_nav.walkable(position(entity)), "AC07: %s/%s spawns inside an obstacle" % [filename, entity.id])
				var destination := _open_layout_position(position(entity), initial_nav, nav)
				check(destination.x >= 0.0 and not nav.path(origin, destination).is_empty(), "AC15: %s/%s is unreachable even with every door open" % [filename, entity.id])
		for door: Dictionary in doors:
			check(not nav.approach(origin, door).is_empty(), "AC09: %s/%s has no reachable approach" % [filename, door.id])
	case_reached_end = true

func _open_layout_position(initial: Vector2, initial_nav: RefCounted, opened_nav: RefCounted) -> Vector2:
	if opened_nav.walkable(initial): return initial
	# Only a swept door leaf permits local retreat in this synthetic all-open
	# layout. A wall/furniture overlap remains an invalid endpoint and failure.
	if not opened_nav.blocked_by_leaf(initial): return Vector2(-1, -1)
	for radius: float in [0.35, 0.5, 0.75, 1.0, 1.5]:
		for angle_index in range(16):
			var candidate := initial + Vector2.from_angle(angle_index * TAU / 16.0) * radius
			if opened_nav.walkable(candidate) and initial_nav.segment_clear(initial, candidate, initial_nav.RADIUS):
				return candidate
	return Vector2(-1, -1)

func _test_command_sequence() -> void:
	var sim: RefCounted = simulation()
	check(sim.issue("alpha", "MOVE", {"target": [4.0, 5.0]}, true).get("ok", false), "AC04: MOVE registration failed")
	check(sim.issue("alpha", "FACE", {"target": [4.0, 2.0]}, true).get("ok", false), "AC04: FACE registration failed")
	check(sim.issue("alpha", "WAIT", {"duration": 0.7}, true).get("ok", false), "AC04: WAIT registration failed")
	var completion_ticks: Array = [-1, -1, -1]
	for index: int in range(240):
		sim.step(STEP)
		var states: Array = command_states(sim)
		for command_index: int in range(mini(3, states.size())):
			if states[command_index] == "SUCCEEDED" and completion_ticks[command_index] < 0:
				completion_ticks[command_index] = sim.tick
	check(command_states(sim) == ["SUCCEEDED", "SUCCEEDED", "SUCCEEDED"], "AC04: MOVE→FACE→WAIT did not each finish once")
	check(completion_ticks[0] > 0 and completion_ticks[0] <= completion_ticks[1] and completion_ticks[1] < completion_ticks[2], "AC04: completion order changed")
	check(completion_ticks[2] - completion_ticks[1] >= 20, "AC04: WAIT did not honor simulation duration")
	check(position(sim.units[0]).distance_to(Vector2(4, 5)) < 0.3, "AC04: MOVE completed away from destination")
	check(absf(angle_difference(float(sim.units[0].facing), -PI / 2.0)) < 0.15, "AC04: FACE completed with wrong orientation")
	case_reached_end = true

func _test_failure_blocks_queue() -> void:
	var data: Dictionary = fixture()
	data.walls = [{"x": 8.0, "z": 6.0, "w": 0.4, "d": 12.0}]
	var sim: RefCounted = simulation(data)
	check(sim.issue("alpha", "MOVE", {"target": [12.0, 5.0]}, true).get("ok", false), "AC05: valid but unreachable MOVE was not queued")
	sim.issue("alpha", "WAIT", {"duration": 0.1}, true)
	advance(sim, 5.0)
	var states: Array = command_states(sim)
	check(states == ["FAILED", "PENDING"], "AC05: failed route did not stop following commands: %s" % str(states))
	check(position(sim.units[0]).distance_to(Vector2(2, 5)) < 0.05, "AC07: unreachable MOVE teleported through wall")
	check(not str(sim.units[0].commands[0].get("reason", "")).is_empty(), "AC05: failed command omitted explanatory reason")
	case_reached_end = true

func _test_signal_pulses() -> void:
	var data: Dictionary = fixture()
	data.units.append({"id": "bravo", "name": "BRAVO", "x": 3.0, "z": 7.0, "facing": 0.0, "weapon": "light"})
	var sim: RefCounted = simulation(data)
	sim.issue("alpha", "WAIT_FOR_SIGNAL", {"signal": "A"}, true)
	sim.issue("alpha", "WAIT", {"duration": 0.1}, true)
	sim.issue("bravo", "WAIT", {"duration": 0.6}, true)
	sim.issue("bravo", "WAIT_FOR_SIGNAL", {"signal": "A"}, true)
	advance(sim, 0.1)
	check(command_states(sim)[0] == "WAITING", "AC06: signal command did not register as waiting")
	sim.release_signal("A")
	advance(sim, 1.0)
	check(command_states(sim, 0) == ["SUCCEEDED", "SUCCEEDED"], "AC06: waiting alpha was not released")
	check(command_states(sim, 1)[1] == "WAITING", "AC06: later arrival consumed a historical signal")
	sim.release_signal("A")
	sim.step(STEP)
	check(command_states(sim, 1)[1] == "SUCCEEDED", "AC06: next pulse failed to release later waiter")
	var simultaneous: RefCounted = simulation(data)
	for unit: Dictionary in simultaneous.units:
		simultaneous.issue(str(unit.id), "WAIT_FOR_SIGNAL", {"signal": "B"}, true)
	advance(simultaneous, 0.1)
	simultaneous.release_signal("B")
	simultaneous.step(STEP)
	check(command_states(simultaneous, 0)[0] == "SUCCEEDED" and command_states(simultaneous, 1)[0] == "SUCCEEDED", "AC06: concurrent waiters not released by one pulse")
	case_reached_end = true

func _test_door_execution() -> void:
	var sim: RefCounted = simulation(doorway_fixture())
	check(not sim.nav.segment_clear(Vector2(7, 4), Vector2(7, 8)), "AC09: closed leaf allowed zero-radius LOS")
	sim.issue("alpha", "OPEN_DOOR", {"door_id": "door_1"}, true)
	sim.issue("alpha", "MOVE", {"target": [7.0, 8.0]}, true)
	var saw_opening: bool = false
	var open_tick: int = -1
	for index: int in range(240):
		sim.step(STEP)
		var door: Dictionary = sim.doors[0]
		if door.state == "OPENING":
			saw_opening = true
			var leaf_distance: float = DoorGeometry.ray_distance(door, Vector2(7, 4), Vector2.DOWN, 4.0)
			check(sim.nav.segment_clear(Vector2(7, 4), Vector2(7, 8)) == (leaf_distance >= 4.0), "AC09: opening LOS disagrees with the actual rendered leaf pose")
			check(not sim.nav.segment_clear(Vector2(7, 4), Vector2(7, 8), sim.nav.RADIUS), "AC09: body crossed the unfinished doorway interaction gate")
		if door.state == "OPEN" and open_tick < 0:
			open_tick = sim.tick
			check(sim.nav.segment_clear(Vector2(7, 4), Vector2(7, 8)), "AC09: door state and LOS updated on different ticks")
		if open_tick < 0:
			check(float(sim.units[0].z) < 6.0, "AC09: unit crossed door while closed/opening")
	check(saw_opening and open_tick > 0, "AC09: OPEN_DOOR skipped opening state or never opened")
	check(position(sim.units[0]).distance_to(Vector2(7, 8)) < 0.3, "AC09: MOVE after OPEN_DOOR did not reach room")
	case_reached_end = true

func _test_malformed_commands() -> void:
	var sim: RefCounted = simulation()
	var invalid: Array = [
		["missing", "MOVE", {"target": [3, 3]}], ["alpha", "EXECUTE_CODE", {}],
		["alpha", "MOVE", {"target": [-10, 5]}], ["alpha", "MOVE", {"target": [NAN, 5]}],
		["alpha", "MOVE", {"target": [INF, 5]}], ["alpha", "MOVE", {"target": [3]}],
		["alpha", "WAIT", {"duration": -1}], ["alpha", "OPEN_DOOR", {"door_id": "missing"}],
		["alpha", "WAIT_FOR_SIGNAL", {"signal": "Z"}], ["alpha", "SECURE_CIVILIAN", {"civilian_id": "missing"}]
	]
	for item: Array in invalid:
		var response: Dictionary = sim.issue(str(item[0]), str(item[1]), item[2], true)
		check(not response.get("ok", true), "AC22: malformed command was accepted: %s %s" % [str(item[1]), str(item[2])])
	check(sim.units[0].commands.is_empty(), "AC22: rejected commands mutated queue")
	case_reached_end = true

func _test_civilian_idempotence() -> void:
	var data: Dictionary = fixture()
	data.civilians = [{"id": "civilian_1", "x": 2.8, "z": 5.0}, {"id": "civilian_2", "x": 12.0, "z": 10.0}]
	var sim: RefCounted = simulation(data)
	sim.issue("alpha", "SECURE_CIVILIAN", {"civilian_id": "civilian_1"}, true)
	sim.issue("alpha", "SECURE_CIVILIAN", {"civilian_id": "civilian_1"}, true)
	advance(sim, 5.0)
	check(bool(sim.civilians[0].get("secured", false)), "AC14: adjacent civilian not secured")
	var state: Dictionary = sim.snapshot(true)
	check(int(state.get("objectives", {}).get("rescued", -1)) == 1, "AC14: duplicate civilian secure inflated rescued count")
	check(sim.result.is_empty(), "AC15: mission ended with required civilian still unsecured")
	case_reached_end = true

func _test_allied_line_safety() -> void:
	var data: Dictionary = fixture()
	data.units.append({"id": "bravo", "name": "BRAVO", "x": 4.0, "z": 5.0, "facing": PI, "weapon": "light"})
	data.enemies = [{"id": "enemy_1", "x": 7.0, "z": 5.0, "facing": 0.0, "patrol": []}]
	var sim: RefCounted = simulation(data)
	var initial_ammo: int = int(sim.units[0].ammo)
	advance(sim, 0.7)
	check(int(sim.units[0].ammo) == initial_ammo, "AC11: alpha fired through allied unit in its line of fire")
	check(float(sim.units[1].hp) > 0.0, "AC11: friendly line safety damaged allied unit")
	case_reached_end = true

func _test_reload_and_stun() -> void:
	var reload_sim: RefCounted = simulation()
	reload_sim.units[0].ammo = 3
	var first: Dictionary = reload_sim.issue("alpha", "RELOAD", {"request_id": "reload-once"}, true)
	var repeated: Dictionary = reload_sim.issue("alpha", "RELOAD", {"request_id": "reload-once"}, true)
	check(first.get("id") == repeated.get("id") and reload_sim.units[0].commands.size() == 1, "AC13: duplicate browser request created a second reload")
	advance(reload_sim, 0.5)
	check(int(reload_sim.units[0].ammo) == 3, "AC13: reload updated ammunition before completion")
	advance(reload_sim, 3.0)
	check(int(reload_sim.units[0].ammo) == int(reload_sim.units[0].max_ammo), "AC13: reload did not replenish magazine")
	var reload_events: int = 0
	for event: Dictionary in reload_sim.events:
		if event.type == "RELOAD": reload_events += 1
	check(reload_events == 1, "AC13: one reload emitted multiple completion events")
	var data: Dictionary = fixture()
	data.units[0].ammo = 0
	data.enemies = [{"id": "target", "x": 6.0, "z": 5.0, "facing": 0.0, "passive": true, "hp": 10000.0}]
	var stun_sim: RefCounted = simulation(data)
	stun_sim.enemies[0].stunned = 8.0
	stun_sim.issue("alpha", "THROW_STUN", {"target": [6.0, 5.0], "request_id": "stun-once"}, true)
	stun_sim.issue("alpha", "THROW_STUN", {"target": [6.0, 5.0], "request_id": "stun-once"}, true)
	advance(stun_sim, 0.7)
	check(int(stun_sim.units[0].stuns) == 1, "AC13: stun consumed an item more than once")
	check(float(stun_sim.enemies[0].stunned) > 7.0, "AC13: short repeated stun shortened an existing longer effect")
	advance(stun_sim, 1.0)
	check(int(stun_sim.units[0].stuns) == 1, "AC13: completed stun continued consuming equipment")
	data.walls = [{"x": 4.0, "z": 6.0, "w": 0.4, "d": 12.0}]
	var wall_sim: RefCounted = simulation(data)
	wall_sim.issue("alpha", "THROW_STUN", {"target": [6.0, 5.0]}, true)
	advance(wall_sim, 1.0)
	check(command_states(wall_sim)[0] == "FAILED", "AC13: stun passed through a solid wall")
	check(int(wall_sim.units[0].stuns) == 2 and float(wall_sim.enemies[0].stunned) == 0.0, "AC13: blocked stun consumed equipment or affected enemy")
	case_reached_end = true

func _test_hidden_information() -> void:
	var data: Dictionary = fixture()
	data.units[0].ammo = 0
	data.walls = [{"x": 8.0, "z": 6.0, "w": 0.4, "d": 12.0}]
	data.enemies = [{"id": "target", "x": 4.0, "z": 5.0, "facing": PI, "passive": true}]
	var sim: RefCounted = simulation(data)
	check(bool(sim.snapshot().enemies[0].visible), "AC10: unobstructed enemy in facing cone not seen")
	# Move a previously seen target behind a wall to isolate the sensor contract.
	sim.enemies[0].x = 12.0
	sim.enemies[0].z = 9.0
	advance(sim, 0.2)
	var hidden: Dictionary = sim.snapshot().enemies[0]
	check(not bool(hidden.visible), "AC10: wall failed to hide a formerly observed enemy")
	check(position(hidden) == Vector2(4, 5), "AC10: last-seen marker followed hidden true coordinates")
	check(not hidden.has("ammo") and not hidden.has("_ai_state"), "AC10: hidden marker leaks combat/AI state")
	data.enemies[0].passive = false
	data.enemies[0].x = 6.0
	var ai_sim: RefCounted = simulation(data)
	advance(ai_sim, 0.1)
	var remembered: Array = ai_sim.enemies[0]._last_known.duplicate()
	ai_sim.units[0].x = 12.0
	advance(ai_sim, 0.2)
	check(ai_sim.enemies[0]._last_known == remembered, "AC12: AI refreshed last-known position through a wall")
	check(ai_sim.enemies[0]._observed.is_empty(), "AC12: AI observation retained a blocked target")
	check(not ai_sim.can_see(ai_sim.enemies[0], ai_sim.units[0]), "AC11: attack-time LOS admits wall obstruction")
	case_reached_end = true

func _test_mission_results() -> void:
	var data: Dictionary = fixture()
	data.civilians = [{"id": "civilian", "x": 2.8, "z": 5.0}]
	var sim: RefCounted = simulation(data)
	sim.issue("alpha", "SECURE_CIVILIAN", {"civilian_id": "civilian"}, true)
	advance(sim, 3.0)
	check(bool(sim.result.get("success", false)), "AC15: secured final civilian did not complete objective")
	check(int(sim.result.get("score", -1)) == 100, "AC15: intact squad/all objectives did not receive 100 points")
	var ending_tick: int = sim.tick
	advance(sim, 2.0)
	check(sim.tick == ending_tick, "AC15: simulation continued after result")
	var failed: RefCounted = simulation(data)
	failed.units[0].hp = 0.0
	failed.step(STEP)
	check(not failed.result.is_empty() and not bool(failed.result.get("success", true)), "AC15: total squad loss did not fail mission")
	var civilian_failure: RefCounted = simulation(data)
	civilian_failure.civilians[0].hp = 0.0
	civilian_failure.step(STEP)
	check(not civilian_failure.result.is_empty() and not bool(civilian_failure.result.get("success", true)), "AC15: essential civilian loss did not fail mission")
	case_reached_end = true

func _test_tutorial_completion() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json"))
	var sim: RefCounted = simulation(data)
	var plan: Array = [
		["MOVE", {"target": [6.0, 12.0]}], ["FACE", {"target": [6.4, 7.5]}], ["WAIT", {"duration": 2.0}],
		["OPEN_DOOR", {"door_id": "d1"}], ["MOVE", {"target": [12.0, 11.0]}], ["FACE", {"target": [12.0, 8.0]}], ["WAIT", {"duration": 2.0}],
		["OPEN_DOOR", {"door_id": "d2"}], ["MOVE", {"target": [18.0, 10.0]}], ["FACE", {"target": [18.4, 7.7]}], ["WAIT", {"duration": 3.0}]
	]
	for item: Array in plan:
		check(sim.issue("alpha", str(item[0]), item[1], true).get("ok", false), "AC01: tutorial plan registration failed")
	var recording: RefCounted
	if FileAccess.file_exists("res://scripts/replay.gd"):
		recording = load("res://scripts/replay.gd").new()
		recording.begin(data)
		recording.capture(sim.snapshot(true))
	for index: int in range(1800):
		sim.step(STEP)
		if recording != null:
			recording.capture(sim.snapshot(true))
		if not sim.result.is_empty():
			break
	tutorial_final = sim.snapshot(true)
	if recording != null:
		recording.finish(tutorial_final)
		tutorial_recording = JSON.parse_string(JSON.stringify(recording.export_data()))
	check(bool(sim.result.get("success", false)), "AC01/15: authored tutorial did not complete using ordinary commands; states=%s" % str(command_states(sim)))
	check(int(sim.result.get("neutralized", -1)) == 3, "AC15: tutorial did not neutralize all three training targets")
	check(int(sim.result.get("score", -1)) == 100, "AC15: tutorial without damage did not normalize score to 100")
	check(sim.doors[0].state == "OPEN" and sim.doors[1].state == "OPEN", "AC09: tutorial completion skipped required door state transitions")
	check(int(sim.command_failures) == 0, "AC05: authored tutorial plan suffered a command failure")
	case_reached_end = true

func _test_pause_without_ticks() -> void:
	var sim: RefCounted = simulation()
	sim.issue("alpha", "WAIT", {"duration": 5.0}, true)
	advance(sim, 0.25)
	var before: String = JSON.stringify(sim.snapshot(true))
	await create_timer(0.15).timeout
	check(JSON.stringify(sim.snapshot(true)) == before, "AC02: simulation state advanced without simulation ticks")
	case_reached_end = true

func _test_replay_contract() -> void:
	var replay_script: Script = load("res://scripts/replay.gd")
	var replay: RefCounted = replay_script.new()
	check(not tutorial_recording.is_empty(), "AC16: no completed tutorial recording available")
	if tutorial_recording.is_empty(): return
	var imported: Dictionary = replay.load_data(tutorial_recording)
	check(imported.get("ok", false), "AC16/22: real exported tutorial replay was rejected: %s" % str(imported.get("message", "")))
	if not imported.get("ok", false): return
	check(bool(replay.complete), "AC16: completed tutorial was marked partial")
	var final_state: Dictionary = replay.seek(replay.duration, true)
	# JSON necessarily round-trips integer Variants as numeric values and rounds floats.
	# Compare discrete payloads to the same serialized boundary, then positions by tolerance.
	var serialized_final: Dictionary = JSON.parse_string(JSON.stringify(tutorial_final))
	check(final_state.result == serialized_final.result, "AC16: replay final objective/result differs from original")
	check(final_state.doors == serialized_final.doors, "AC16: replay door state differs from original")
	check(final_state.events == serialized_final.events, "AC16: replay event IDs/order differ from original")
	for group: String in ["units", "enemies", "civilians"]:
		check(final_state[group].size() == tutorial_final[group].size(), "AC16: replay lost an entity")
		for index: int in range(mini(final_state[group].size(), tutorial_final[group].size())):
			var before: Dictionary = tutorial_final[group][index]
			var after: Dictionary = final_state[group][index]
			check(position(before).distance_to(position(after)) < 0.00001, "AC16: recorded final entity position drifted")
			check(before.hp == after.hp and before.ammo == after.ammo and before.status == after.status, "AC16: recorded final combat state drifted")
	var baseline: String = JSON.stringify(replay.seek(replay.duration * 0.5, true))
	for index: int in range(20):
		replay.seek(0.0, false)
		replay.seek(replay.duration, true)
		check(JSON.stringify(replay.seek(replay.duration * 0.5, true)) == baseline, "AC17: repeated seek accumulated state/events")
	check(replay.seek(0.0, false).enemies.is_empty(), "AC18: initial observed replay revealed unseen training targets")
	check(replay.seek(0.0, true).enemies.size() == 3, "AC18: full review did not expose all three targets")
	var pristine: String = JSON.stringify(replay.export_data())
	for mutation: String in ["schema", "map", "catalog", "duration", "actor", "numeric", "row", "extra", "build_type", "encoding_type", "catalog_type"]:
		var corrupt: Dictionary = tutorial_recording.duplicate(true)
		match mutation:
			"schema": corrupt.schema_version = 999
			"map": corrupt.map_id = "UNKNOWN"
			"catalog": corrupt.asset_catalog_hash = "remote-assets"
			"duration": corrupt.duration = NAN
			"actor": corrupt.states[0].base.id = "unknown_actor"
			"numeric": corrupt.frames[0][2][2] = INF
			"row": corrupt.frames[0][2][0] = 999
			"extra": corrupt["script"] = "javascript:alert(1)"
			"build_type": corrupt.game_build_id = true
			"encoding_type": corrupt.encoding = INF
			"catalog_type": corrupt.asset_catalog_hash = {}
		var rejected: Dictionary = replay.load_data(corrupt)
		check(not rejected.get("ok", true), "AC22: malformed replay accepted: " + mutation)
		check(JSON.stringify(replay.export_data()) == pristine, "AC22: rejected replay changed existing record: " + mutation)
	var house: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var house_sim: RefCounted = simulation(house)
	var partial: RefCounted = replay_script.new()
	partial.begin(house)
	var state: Dictionary = house_sim.snapshot(true)
	partial.capture(state)
	var observed: Dictionary = partial.seek(0.0, false)
	for civilian: Dictionary in observed.civilians:
		check(bool(civilian.get("visible", false)) or civilian.has("last_seen"), "AC18: observed replay leaked an undiscovered civilian")
	state.time = 600.0
	state.tick = 18000
	partial.capture(state)
	state.time = 601.0
	state.tick = 18030
	partial.finish(state)
	check(not partial.complete and partial.duration <= 600.0, "AC16: over-limit recording claimed complete or exceeded ten minutes")
	check(partial.export_size_bytes() <= 20 * 1024 * 1024 and partial.estimate_memory_bytes() <= 40 * 1024 * 1024, "AC16: basic recording exceeded replay budgets")
	case_reached_end = true
