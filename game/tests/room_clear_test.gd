extends SceneTree
## H1/M4 regression (redesign review findings): room_clear must never fire
## for a room the player has not actually observed, must never credit a
## kill made outside every room's walls to any room (including the enemy's
## spawn room), must require at least one player-observed enemy to exist in
## the room's old kill-only fixture, and must be evaluated in event order.
## P3 deliberately replaces immediate kill credit with actual simulation
## search/CALL_ROOM_CLEAR authority, preserving every visibility negative
## and the running death cursor while strengthening the late-event check.
const MainScene = preload("res://main.tscn")
const STEP := 1.0 / 30.0
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _start_session() -> Node:
	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	session._action({"action": "start", "mission": "T01", "seed": "room-clear-test"})
	return session

func _mark_fully_explored(session: Node, room_id: String) -> void:
	var mask: Array = session.world._room_seen_mask.get(room_id, [])
	for i in range(mask.size()):
		mask[i] = true
	# The v4 positive fixture uses the metre-map cached count. Keep this
	# existing fully-explored render fixture coherent with its unchanged grid.
	session.world._room_seen_count[room_id] = mask.size()

func _search_session(room_id: String, second_target: bool = false) -> Node:
	var session := _start_session()
	var mission: Dictionary = session.maps.T01.duplicate(true)
	mission["id"] = "ROOM_CLEAR_P3_" + room_id
	mission["schema_version"] = 4
	# Keep the original targets and equipment. The explicit search win prevents
	# the legacy last-kill win from freezing the simulation before 1.5s search.
	mission["win"] = [{"type":"rooms_cleared", "room_ids":[room_id]}]
	mission.units[0].x = 18.0 if room_id == "t_signal" else 6.0
	mission.units[0].z = 10.0
	mission.units[0].facing = -PI * 0.5
	if second_target:
		var target: Dictionary = mission.enemies[0].duplicate(true)
		target.id = "target1b"
		target.x = 7.0
		target.z = 8.0
		mission.enemies.append(target)
	session.maps[mission.id] = mission
	session._load_mission(mission.id)
	return session

func _actual_search(session: Node, room_id: String) -> Dictionary:
	var last_shot := -1.0
	var clear_call: Dictionary = {}
	for tick in range(600):
		session.sim.step(STEP)
		for event: Dictionary in session.sim.take_record_events():
			if event.get("type", "") == "SHOT" and event.get("attacker_id", "") == "alpha": last_shot = float(event.time)
			if event.get("type", "") == "CALL_ROOM_CLEAR" and event.get("room_id", "") == room_id: clear_call = event.duplicate(true)
		if last_shot >= 0.0 and session.sim.time < last_shot + 1.5 - 0.000001:
			check(str(session.sim.room_control.snapshot(true).get(room_id, {}).get("state", "")) not in ["CLEAR", "MARKED"], "P3: actual firing interrupts search; no CLEAR before 45 subsequent fixed steps")
		if not clear_call.is_empty(): break
	check(last_shot >= 0.0, "P3 fixture: the original passive target was actually shot; no injected death")
	check(not clear_call.is_empty(), "P3 fixture: the same stationary operator actually completes room search")
	if not clear_call.is_empty():
		check(float(clear_call.time) - last_shot >= 1.5 - 0.000001, "P3: actual search CALL follows the final shot by at least 1.5s")
		check(clear_call.get("observed", false) == true, "P3: actual search transition carries occurrence-time observation proof")
	return {"state": session.sim.snapshot(false), "call": clear_call}

func _run() -> void:
	await process_frame

	# --- H1: an enemy neutralized in a room the player has never observed
	# must not fire room_clear. T01's t_breach room (home of target2) has
	# had nothing look into it in this fresh session (set_process(false)
	# means world.display() never ran), so it starts unobserved.
	var unseen: Node = _start_session()
	await process_frame
	check(not unseen.world.is_room_sufficiently_observed("t_breach"), "Fixture: t_breach starts unobserved in a fresh session")
	unseen._fx_neutralized_ids["target2"] = true
	unseen._check_room_clear("target2", [12.0, 8.0], 1.0, {"enemies": [{"id": "target2", "x": 12.0, "z": 8.0, "status": "INCAPACITATED"}]})
	check(not bool(unseen._fx_room_cleared.get("t_breach", false)), "H1: room_clear does not fire for an unobserved room even though its only known enemy is down")
	unseen.queue_free()

	# --- H1: a kill made outside every room's walls (a hallway point -- T01's
	# three rooms all span z in [4,16), so z=2 sits outside every one of
	# them) must not be credited to any room, including the enemy's
	# original spawn room (t_ready, for target1).
	var hallway: Node = _start_session()
	await process_frame
	_mark_fully_explored(hallway, "t_ready")
	hallway._fx_neutralized_ids["target1"] = true
	hallway._check_room_clear("target1", [12.0, 2.0], 2.0, {"enemies": [{"id": "target1", "x": 12.0, "z": 2.0, "status": "INCAPACITATED"}]})
	var any_cleared := false
	for room_id: String in hallway._fx_room_map:
		if bool(hallway._fx_room_cleared.get(room_id, false)):
			any_cleared = true
	check(not any_cleared, "H1: a kill outside every room's walls (hallway) credits no room at all, not even the fully-explored spawn room")
	hallway.queue_free()

	# P3 legitimate rule change: a seen kill remains insufficient. Use real
	# combat followed by fixed-step search rather than fabricate authority.
	var observed: Node = _search_session("t_signal")
	await process_frame
	_mark_fully_explored(observed, "t_signal")
	check(observed.world.is_room_sufficiently_observed("t_signal"), "Fixture: t_signal reads as sufficiently observed once its sample grid is fully seen")
	observed._fx_neutralized_ids["target3"] = true
	observed._check_room_clear("target3", [18.4, 7.7], 3.0, {"enemies": [{"id": "target3", "x": 18.4, "z": 7.7, "status": "INCAPACITATED"}]})
	check(not bool(observed._fx_room_cleared.get("t_signal", false)), "P3: an observed kill and a fully explored render mask cannot manufacture CLEAR")
	var observed_search := _actual_search(observed, "t_signal")
	observed._dispatch_fx(observed_search.state)
	check(bool(observed._fx_room_cleared.get("t_signal", false)), "H1/P3: room_clear still fires for an observed room after actual control and 1.5s search")
	# A room with no observed enemy attributed to it at all must never read
	# as cleared, even if it is fully explored.
	_mark_fully_explored(observed, "t_breach")
	check(not bool(observed._fx_room_cleared.get("t_breach", false)), "H1: a fully-explored room with no observed enemy attributed to it never reads as cleared")
	observed.queue_free()

	# --- M4: room_clear must be checked in event order against a running
	# neutralized-id set, not a single end-of-frame snapshot of
	# state.enemies. Regression case for the exact old bug: dispatch only
	# target1's INCAPACITATED event (seq=1) while state.enemies already
	# shows a SECOND room-mate (target1b) as INCAPACITATED too -- exactly
	# what a frame that batched both deaths together (e.g. a 4x replay)
	# would look like. The old implementation read state.enemies' status
	# fields directly and would have cleared the room right here, one event
	# early, because it never looked at which events had actually been
	# reached yet.
	var m4: Node = _search_session("t_ready", true)
	await process_frame
	_mark_fully_explored(m4, "t_ready")
	var actual_search := _actual_search(m4, "t_ready")
	var state_with_both_down: Dictionary = {
		"time": actual_search.state.time,
		"room_states": actual_search.state.room_states,
		"events": [{"seq": 1, "type": "INCAPACITATED", "kind": "enemy", "entity_id": "target1", "time": 1.0, "to": [6.4, 7.5]}],
		"enemies": [
			{"id": "target1", "x": 6.4, "z": 7.5, "status": "INCAPACITATED"},
			{"id": "target1b", "x": 7.0, "z": 8.0, "status": "INCAPACITATED"},
		],
	}
	m4._dispatch_fx(state_with_both_down)
	check(bool(m4._fx_neutralized_ids.get("target1", false)), "M4 fixture: dispatching target1's event added it to the running neutralized set")
	check(not m4._fx_neutralized_ids.has("target1b"), "M4 fixture: target1b's own event was never dispatched, so it is not yet in the running neutralized set")
	check(not bool(m4._fx_room_cleared.get("t_ready", false)), "M4: the room does not clear after only target1's event is dispatched, even though the frame's state.enemies already shows target1b down too")

	# P3: even the second real death cursor cannot flash the future final
	# CLEAR map. Only the actual search CALL may complete this batch.
	var state_with_second_event: Dictionary = {
		"time": actual_search.state.time,
		"room_states": actual_search.state.room_states,
		"events": [
			{"seq": 1, "type": "INCAPACITATED", "kind": "enemy", "entity_id": "target1", "time": 1.0, "to": [6.4, 7.5]},
			{"seq": 2, "type": "INCAPACITATED", "kind": "enemy", "entity_id": "target1b", "time": 1.5, "to": [7.0, 8.0]},
		],
		"enemies": state_with_both_down.enemies,
	}
	m4._dispatch_fx(state_with_second_event)
	check(bool(m4._fx_neutralized_ids.get("target1b", false)), "M4: target1b's own event still advances the original death cursor")
	check(not bool(m4._fx_room_cleared.get("t_ready", false)), "M4/P3: both death events and a future CLEAR map still cannot flash early")
	state_with_second_event.events.append(actual_search.call)
	m4._dispatch_fx(state_with_second_event)
	check(bool(m4._fx_room_cleared.get("t_ready", false)), "M4/P3: the room clears on its actual search CALL, independent of batched deaths")
	m4.queue_free()

	await process_frame
	print("BREACH_ROOM_CLEAR_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
