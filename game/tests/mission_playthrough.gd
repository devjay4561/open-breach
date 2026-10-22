extends SceneTree

# Full-mission smoke tests through the same public command API as the player.
# Routes refer only to floor coordinates/known doors. No actor state is changed.
const Simulation = preload("res://scripts/simulation.gd")
const STEP: float = 1.0 / 30.0
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _tutorial()
	await _tutorial_browser_controls()
	await _house()
	await _failure_pause()
	print("BREACH_PLAYTHROUGH_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func mission(filename: String) -> RefCounted:
	var sim: RefCounted = Simulation.new()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % filename))
	sim.load_mission(data)
	return sim

func issue(sim: RefCounted, unit: String, type: String, args: Dictionary = {}) -> bool:
	var response: Dictionary = sim.issue(unit, type, args, true)
	check(bool(response.get("ok", false)), "%s: %s %s rejected: %s" % [sim.mission.id, unit, type, response])
	return bool(response.get("ok", false))

func move(sim: RefCounted, unit: String, x: float, z: float) -> void:
	issue(sim, unit, "FACE", {"unlock": true})
	issue(sim, unit, "MOVE", {"target": [x, z]})

func face(sim: RefCounted, unit: String, x: float, z: float) -> void:
	issue(sim, unit, "FACE", {"target": [x, z]})

func door(sim: RefCounted, unit: String, id: String) -> void:
	issue(sim, unit, "FACE", {"unlock": true})
	issue(sim, unit, "OPEN_DOOR", {"door_id": id})

func advance(sim: RefCounted, seconds: float, phase: String) -> bool:
	for index: int in range(ceili(seconds / STEP)):
		if not sim.result.is_empty():
			break
		if sim.pause_requested:
			check(false, "%s/%s: command failure requested pause" % [sim.mission.id, phase])
			diagnostic(sim, phase)
			return false
		arrest_observed(sim)
		sim.step(STEP)
	if sim.pause_requested:
		check(false, "%s/%s: command failure requested pause" % [sim.mission.id, phase])
		diagnostic(sim, phase)
		return false
	print("PHASE %s/%s t=%.2f objectives=%s" % [sim.mission.id, phase, sim.time, JSON.stringify(sim.snapshot().objectives)])
	return true

func diagnostic(sim: RefCounted, phase: String) -> void:
	var state: Dictionary = sim.snapshot()
	var actors: Array = []
	for unit: Dictionary in state.units:
		var pending: Array = []
		for command: Dictionary in unit.commands:
			if command.state not in ["SUCCEEDED", "CANCELLED"]:
				pending.append(command)
		actors.append({"id": unit.id, "x": unit.x, "z": unit.z, "facing": unit.facing, "hp": unit.hp, "status": unit.status, "commands": pending})
	print("DIAGNOSTIC %s %s" % [phase, JSON.stringify({"units": actors, "enemies": state.enemies, "civilians": state.civilians, "events": state.events})])

func result_check(sim: RefCounted, expected_threats: int, expected_civilians: int) -> void:
	check(not sim.result.is_empty(), "%s: mission never reached a result" % sim.mission.id)
	if sim.result.is_empty():
		diagnostic(sim, "INCOMPLETE")
		return
	var result: Dictionary = sim.result
	print("MISSION_RESULT %s %s" % [sim.mission.id, JSON.stringify(result)])
	check(bool(result.get("success", false)), "%s: mission was lost" % sim.mission.id)
	check(int(result.get("neutralized", -1)) == expected_threats, "%s: not all threats cleared" % sim.mission.id)
	check(int(result.get("rescued", -1)) == expected_civilians, "%s: not all civilians secured" % sim.mission.id)
	check(int(result.get("losses", -1)) == 0, "%s: sensible route lost a squad member" % sim.mission.id)
	check(int(result.get("command_failures", -1)) == 0, "%s: successful route contained command failures" % sim.mission.id)
	check(int(result.get("score", 0)) >= 80, "%s: route scored below A rank" % sim.mission.id)
	var finished: String = JSON.stringify(sim.snapshot())
	for index: int in range(30):
		sim.step(STEP)
	check(JSON.stringify(sim.snapshot()) == finished, "%s: finished result continued changing" % sim.mission.id)

func _tutorial() -> void:
	var sim: RefCounted = mission("tutorial")
	move(sim, "alpha", 6.0, 12.0)
	face(sim, "alpha", 6.0, 6.0)
	move(sim, "bravo", 7.3, 13.5)
	face(sim, "bravo", 6.0, 6.0)
	if not advance(sim, 6.0, "movement_and_fov"):
		return
	check(int(sim.snapshot().objectives.neutralized) == 1, "T01: first target not cleared from first room")
	door(sim, "alpha", "d1")
	move(sim, "alpha", 12.0, 10.5)
	face(sim, "alpha", 12.0, 7.0)
	if not advance(sim, 7.5, "first_breach"):
		return
	check(int(sim.snapshot().objectives.neutralized) == 2, "T01: second target not cleared through first door")
	move(sim, "bravo", 11.0, 11.5)
	face(sim, "bravo", 14.0, 8.0)
	door(sim, "alpha", "d2")
	move(sim, "alpha", 18.0, 10.3)
	face(sim, "alpha", 18.0, 6.0)
	if not advance(sim, 10.0, "second_breach"):
		return
	result_check(sim, 3, 0)
	print("TUTORIAL_BROWSER_ROUTE alpha MOVE(6,12), FACE(6,6), execute 6s; OPEN_DOOR(d1), MOVE(12,10.5), FACE(12,7), execute 7.5s; OPEN_DOOR(d2), MOVE(18,10.3), FACE(18,6), execute until result")

func _tutorial_browser_controls() -> void:
	# Also prove the shortest onboarding route without the optional FACE-unlock
	# command, so every action maps directly to a visible floor/door control.
	var sim: RefCounted = mission("tutorial")
	issue(sim, "alpha", "MOVE", {"target": [6.0, 12.0]})
	face(sim, "alpha", 6.0, 6.0)
	if not advance(sim, 6.0, "browser_floor_click"):
		return
	issue(sim, "alpha", "OPEN_DOOR", {"door_id": "d1"})
	issue(sim, "alpha", "MOVE", {"target": [12.0, 10.5]})
	face(sim, "alpha", 12.0, 7.0)
	if not advance(sim, 7.5, "browser_first_door_click"):
		return
	issue(sim, "alpha", "OPEN_DOOR", {"door_id": "d2"})
	issue(sim, "alpha", "MOVE", {"target": [18.0, 10.3]})
	face(sim, "alpha", 18.0, 6.0)
	if not advance(sim, 10.0, "browser_second_door_click"):
		return
	result_check(sim, 3, 0)

func _house() -> void:
	var sim: RefCounted = mission("house")
	door(sim, "alpha", "d1")
	move(sim, "alpha", 11.2, 13.6)
	face(sim, "alpha", 12.0, 10.0)
	if not advance(sim, 5.5, "front_door"):
		return
	move(sim, "bravo", 13.2, 13.6)
	face(sim, "bravo", 15.0, 13.6)
	if not advance(sim, 4.5, "second_operator_entry"):
		return
	move(sim, "charlie", 11.8, 15.6)
	face(sim, "charlie", 9.0, 13.6)
	issue(sim, "delta", "WAIT", {"duration": 1.8})
	move(sim, "delta", 13.0, 15.6)
	face(sim, "delta", 15.0, 13.6)
	if not advance(sim, 5.0, "support_entry"):
		return
	issue(sim, "alpha", "FACE", {"unlock": true})
	issue(sim, "alpha", "OPEN_AND_FLASH", {"door_id": "d2", "target": [6.0, 12.0]})
	move(sim, "alpha", 7.7, 12.2)
	face(sim, "alpha", 4.8, 11.6)
	issue(sim, "bravo", "FACE", {"unlock": true})
	issue(sim, "bravo", "OPEN_AND_FLASH", {"door_id": "d3", "target": [18.0, 12.0]})
	move(sim, "bravo", 16.6, 12.1)
	face(sim, "bravo", 19.5, 12.0)
	if not advance(sim, 7.0, "living_and_kitchen"):
		return
	check(int(sim.snapshot().objectives.neutralized) >= 3, "M01: ground-floor rooms not cleared")
	door(sim, "alpha", "d7")
	# The open leaf now also occludes visibility. This fixture observes from
	# free floor beyond its silhouette instead of relying on rays through it.
	move(sim, "alpha", 6.6, 6.2)
	face(sim, "alpha", 4.4, 8.5)
	# P1 restores prepared doorway threats: an unsupported quiet entry after
	# the downstairs firefight leaves CHARLIE exposed to an alerted room. Pair
	# this entry with DELTA's covering fire and CHARLIE's authored flashbang.
	# Keep the original mission, loadout, seed and every route/result check.
	issue(sim, "charlie", "FACE", {"unlock": true})
	issue(sim, "charlie", "OPEN_AND_FLASH", {"door_id": "d4", "target": [13.0, 7.0]})
	move(sim, "charlie", 12.0, 7.0)
	face(sim, "charlie", 13.0, 4.8)
	door(sim, "delta", "d4")
	move(sim, "delta", 13.2, 8.0)
	face(sim, "delta", 13.6, 6.0)
	if not advance(sim, 10.0, "bedroom_and_study"):
		return
	# Mobile enemies can leave their authored room while the squad approaches.
	# This phase verifies both physical entries; the final result still requires
	# every threat neutralized, both civilians rescued and zero command failures.
	check(sim._find(sim.doors, "d7").state == "OPEN" and sim._find(sim.doors, "d4").state == "OPEN", "M01: bedroom and study door entries complete")
	# A real arrest can move ALPHA away from the room observation point. Return
	# through public movement commands before checking the original positions.
	move(sim, "alpha", 6.6, 6.2)
	face(sim, "alpha", 4.4, 8.5)
	move(sim, "charlie", 12.0, 7.0)
	face(sim, "charlie", 13.0, 4.8)
	if not advance(sim, 2.0, "room_observation_points"):
		return
	check(sim._position(sim._find(sim.units, "alpha")).distance_to(Vector2(6.6,6.2)) < 0.15 and sim._position(sim._find(sim.units, "charlie")).distance_to(Vector2(12,7)) < 0.15, "M01: both operators reach their room observation points")
	move(sim, "alpha", 7.5, 6.5)
	face(sim, "alpha", 7.5, 4.0)
	if not advance(sim, 2.5, "observe_first_civilian"):
		return
	if not secure_observed(sim, "alpha", "c1"):
		return
	door(sim, "charlie", "d6")
	move(sim, "charlie", 14.1, 6.3)
	issue(sim, "charlie", "THROW_STUN", {"target": [18.5, 8.0]})
	move(sim, "charlie", 17.0, 7.0)
	face(sim, "charlie", 19.3, 7.5)
	issue(sim, "delta", "WAIT", {"duration": 6.0})
	door(sim, "delta", "d6")
	move(sim, "delta", 17.4, 8.3)
	face(sim, "delta", 19.0, 7.5)
	if not advance(sim, 10.0, "guest_room"):
		return
	move(sim, "charlie", 19.2, 6.7)
	face(sim, "charlie", 19.8, 4.5)
	if not advance(sim, 2.5, "observe_second_civilian"):
		return
	check(int(sim.snapshot().objectives.neutralized) == 6, "M01: guest-room threat not cleared after the room sweep")
	if not secure_observed(sim, "charlie", "c2"):
		return
	if not advance(sim, 8.0, "rescue"):
		return
	result_check(sim, 6, 2)

func secure_observed(sim: RefCounted, unit_id: String, civilian_id: String) -> bool:
	var observed: bool = false
	for civilian: Dictionary in sim.snapshot().civilians:
		if civilian.id == civilian_id and bool(civilian.get("visible", false)):
			observed = true
	check(observed, "%s: planned rescue has not visually identified %s" % [sim.mission.id, civilian_id])
	if not observed:
		diagnostic(sim, "CIVILIAN_NOT_OBSERVED")
		return false
	return issue(sim, unit_id, "SECURE_CIVILIAN", {"civilian_id": civilian_id})

func _failure_pause() -> void:
	# The controller owns the pause: once the sim requests it, do not call step.
	var sim: RefCounted = mission("tutorial")
	issue(sim, "alpha", "MOVE", {"target": [12.0, 10.0]})
	issue(sim, "alpha", "WAIT", {"duration": 0.1})
	for index: int in range(120):
		if sim.pause_requested:
			break
		sim.step(STEP)
	check(sim.pause_requested, "Failure pause: crossing closed door did not request pause")
	var state: Dictionary = sim.snapshot()
	check(state.units[0].commands[0].state == "FAILED", "Failure pause: command was not marked FAILED")
	check(state.units[0].commands[1].state == "PENDING", "Failure pause: following command advanced")
	check(not str(state.units[0].commands[0].reason).is_empty(), "Failure pause: missing actionable failure reason")
	var frozen: String = JSON.stringify(state)
	await create_timer(0.12).timeout
	check(JSON.stringify(sim.snapshot()) == frozen, "Failure pause: paused world advanced on wall-clock time")
	print("FAILURE_PAUSE verified tick=%d reason=%s" % [sim.tick, state.units[0].commands[0].reason])

func arrest_observed(sim: RefCounted) -> void:
	if not sim.result.is_empty():
		return
	var state: Dictionary = sim.snapshot()
	for enemy: Dictionary in state.enemies:
		if not bool(enemy.get("visible", false)) or enemy.get("status", "") != "SURRENDERED" or bool(enemy.get("arrested", false)):
			continue
		var already_planned: bool = false
		for unit: Dictionary in state.units:
			for command: Dictionary in unit.commands:
				if command.type == "ARREST" and command.args.get("enemy_id", "") == enemy.id and command.state in ["PENDING", "RUNNING", "WAITING"]:
					already_planned = true
		if already_planned:
			continue
		var operator: Dictionary = {}
		var shortest: float = INF
		for unit: Dictionary in state.units:
			if float(unit.hp) <= 0.0 or float(unit.get("stunned", 0.0)) > 0.0:
				continue
			var busy: bool = false
			for command: Dictionary in unit.commands:
				if command.state == "FAILED" or (command.type == "ARREST" and command.state in ["PENDING", "RUNNING", "WAITING"]):
					busy = true
			if busy:
				continue
			var origin := Vector2(float(unit.x), float(unit.z))
			var route: Array = sim.nav.approach(origin, enemy, 1.0)
			if route.is_empty():
				continue
			var length: float = 0.0
			for coordinate: Array in route:
				var next := Vector2(float(coordinate[0]), float(coordinate[1]))
				length += origin.distance_to(next)
				origin = next
			if length < shortest:
				shortest = length
				operator = unit
		if not operator.is_empty():
			# These are the currently observed coordinates, and every action goes
			# through the same commands available in the player's context menu.
			var face_answer: Dictionary = sim.issue(operator.id, "FACE", {"target": [enemy.x, enemy.z]})
			var arrest_answer: Dictionary = sim.issue(operator.id, "ARREST", {"enemy_id": enemy.id})
			check(bool(face_answer.get("ok", false)) and bool(arrest_answer.get("ok", false)), "%s: observed surrender arrest rejected" % sim.mission.id)
