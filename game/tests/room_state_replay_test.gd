extends SceneTree
## P3 records authority and last-observed room memory independently. Every
## transition uses fixed ticks; hidden re-entry never refreshes public clocks.
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Door = preload("res://scripts/door_geometry.gd")
const STEP := 1.0 / 30.0
const TICKS := 240
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	_test_room_contract()
	_test_same_tick_acknowledgement()
	_test_legacy()
	_test_room_limit()
	_test_rules()
	_test_boundaries()
	_test_reload_cover_record()
	_test_operator_casualty_records()
	for seed_value: int in range(30):
		_test_runtime(seed_value)
		_test_actual_result(seed_value)
	print("BREACH_ROOM_STATE_REPLAY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _mission() -> Dictionary:
	var mission: Dictionary = Catalog.load("M01")
	mission.schema_version = 4
	mission.id = "ROOM_STATE_REPLAY"
	mission.custom = true
	return mission

func _row(state: String = "UNKNOWN", tick: int = 0, observed: bool = false) -> Dictionary:
	return {"state":state, "changed_tick":tick, "changed_at":tick * STEP, "observed":observed}

func _state(mission: Dictionary) -> Dictionary:
	var rooms: Dictionary = {}
	for room: Dictionary in mission.rooms: rooms[str(room.id)] = _row()
	var own: Array = []
	for index: int in range(2):
		var unit: Dictionary = mission.units[index]
		own.append({"id":unit.id, "kind":"unit", "x":unit.x, "z":unit.z, "hp":100.0, "commands":[]})
	return {"time":0.0, "tick":0, "units":own, "enemies":[{"id":mission.enemies[0].id, "kind":"enemy", "x":mission.enemies[0].x, "z":mission.enemies[0].z, "hp":72.0, "visible":false}], "civilians":[], "doors":[{"id":mission.doors[0].id, "x":mission.doors[0].x, "z":mission.doors[0].z, "state":"CLOSED"}], "events":[], "room_states":rooms, "room_states_observed":rooms.duplicate(true), "pause_requested":false, "pause_reason":"", "pause_unit_id":""}

func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _record(mission: Dictionary, initial: Dictionary, final: Dictionary) -> Dictionary:
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(initial)
	recorder.finish(final)
	return _json(recorder.export_data())

func _test_room_contract() -> void:
	var mission := _mission()
	var state := _state(mission)
	var room_id := str(mission.rooms[0].id)
	var door_id := str(mission.doors[0].id)
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(state)
	for tick: int in range(1, 7):
		state.time = tick * STEP
		state.tick = tick
		if tick <= 4:
			var next: String = ["CONTACT", "DOMINATED", "CLEAR", "MARKED"][tick - 1]
			# Mutate the original nested row deliberately: previous interned
			# metadata and the previous signature must own their history.
			state.room_states[room_id].merge(_row(next, tick, true), true)
			if next == "MARKED": state.room_states[room_id].door_id = door_id
			state.room_states_observed[room_id] = state.room_states[room_id].duplicate(true)
		elif tick == 5:
			state.room_states[room_id] = _row("CONTACT", tick, false)
		var type: String = ["CALL_RELOADING", "CALL_CLEAR", "CALL_ROOM_CLEAR", "CALL_GUN_UP", "CALL_SHORT_ROOM", "CALL_MAN_DOWN"][tick - 1]
		state.events.append({"seq":tick, "tick":tick, "time":state.time, "type":type, "observed":true, "unit_id":mission.units[0].id, "room_id":room_id, "cover_unit_id":mission.units[1].id})
		if tick == 6:
			state.events.append({"seq":7, "tick":tick, "time":state.time, "type":"CALL_ROOM_CLEAR", "observed":false, "unit_id":mission.units[0].id, "room_id":room_id})
			state.events.append({"seq":8, "tick":tick, "time":state.time, "type":"CONTACT", "enemy_id":mission.enemies[0].id})
			state.result = {"success":false, "status":"FAILED", "room_states":state.room_states.duplicate(true), "room_states_observed":state.room_states_observed.duplicate(true)}
		recorder.capture(state)
	check(recorder.frames.size() == 7, "Every discrete room transition records at its exact tick below the sample interval")
	recorder.finish(state)
	state.result.room_states_observed[room_id].state = "UNKNOWN"
	var candidate: Dictionary = _json(recorder.export_data())
	var restored := Replay.new()
	var loaded := restored.load_data(candidate)
	check(bool(loaded.get("ok", false)), "P3 authority/memory/CALL record accepted: " + str(loaded.get("message", "")))
	if not loaded.get("ok", false): return
	check(candidate.schema_version == 1 and candidate.encoding == "numeric-state-v1", "Room doctrine preserves replay schema1 and numeric encoding")
	for tick: int in range(7):
		var full := restored.seek(tick * STEP, true)
		var observed := restored.seek(tick * STEP, false)
		check(full.tick == tick, "Exact room seek restores authoritative tick %d" % tick)
		check(observed.room_states == full.room_states_observed and not observed.has("room_states_observed"), "Player seek copies only independent memory, tick %d" % tick)
		check(observed.enemies.is_empty(), "A room observation never reveals its hidden NPC, tick %d" % tick)
	check(restored.seek(0.0, true).room_states[room_id].state == "UNKNOWN", "Reused input rows cannot rewrite initial UNKNOWN metadata")
	var between := restored.seek(2.5 * STEP, false)
	check(between.room_states[room_id].state == "DOMINATED" and not between.events.any(func(event: Dictionary) -> bool: return event.type == "CALL_ROOM_CLEAR"), "CLEAR and its event cannot run ahead of their recorded clock")
	var full_final := restored.seek(6.0 * STEP, true)
	var public_final := restored.seek(6.0 * STEP, false)
	check(full_final.room_states[room_id].state == "CONTACT" and public_final.room_states[room_id].state == "MARKED", "Hidden re-entry leaves last-observed MARKED memory intact")
	check(public_final.room_states[room_id].changed_tick == 4 and full_final.room_states[room_id].changed_tick == 5, "Authority and memory retain independent transition clocks")
	check(public_final.result.room_states == public_final.room_states and not public_final.result.has("room_states_observed"), "RESULT nested metadata obeys the same observation boundary")
	check(restored.events_since(0, 6.0 * STEP).size() == 8, "Legacy two-argument event delta still returns the full stream")
	var public_events := restored.events_since(0, 6.0 * STEP, false)
	check(public_events.size() == 7 and public_events[-1].type == "CONTACT", "Occurrence filter removes only unobserved new CALLs, preserving legacy events")
	check(public_final.events == public_events, "Observed seek and observed delta use the same CALL filter")
	var first_call: Dictionary = public_events[2]
	check(first_call == candidate.events[2] and first_call.seq == 3 and first_call.time == 3.0 * STEP, "ROOM CLEAR retains its original occurrence fields after later hidden contact")
	public_final.room_states[room_id].state = "CLEAR"
	public_final.result.room_states[room_id].changed_tick = 0
	public_events[0].unit_id = "edited"
	check(restored.seek(6.0 * STEP, false).room_states[room_id].state == "MARKED" and restored.seek(6.0 * STEP, false).result.room_states[room_id].changed_tick == 4, "Returned room maps and nested result cannot mutate replay history")
	check(restored.events_since(0, 6.0 * STEP, false)[0].unit_id == mission.units[0].id, "Returned event dictionaries independently own their contents")
	_test_malformed(restored, candidate, room_id)

func _test_malformed(restored: RefCounted, candidate: Dictionary, room_id: String) -> void:
	var before := JSON.stringify(restored.export_data())
	for mutation: String in ["map_array", "memory_null", "unknown_room", "extra", "missing", "state", "state_array", "tick_negative", "tick_fraction", "tick_nan", "tick_future", "at_negative", "at_nan", "at_future", "observed", "memory_unobserved", "door_unknown", "door_owner", "result_private", "result_future", "result_unobserved", "call_unit", "call_cover", "call_room", "call_observed", "call_missing", "legacy_call_key", "pause_reason", "pause_unit", "pause_type", "pause_missing_down_unit"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		var row: Dictionary = corrupt.metadata[0].room_states[room_id]
		match mutation:
			"map_array": corrupt.metadata[0].room_states = []
			"memory_null": corrupt.metadata[0].room_states_observed = null
			"unknown_room": corrupt.metadata[0].room_states.unknown = _row()
			"extra": row.enemy_id = candidate.events[-1].enemy_id
			"missing": row.erase("changed_tick")
			"state": row.state = "SEARCHING"
			"state_array": row.state = ["CLEAR"]
			"tick_negative": row.changed_tick = -1
			"tick_fraction": row.changed_tick = 0.5
			"tick_nan": row.changed_tick = NAN
			"tick_future": row.changed_tick = 1
			"at_negative": row.changed_at = -0.1
			"at_nan": row.changed_at = NAN
			"at_future": row.changed_at = STEP
			"observed": row.observed = 1
			"memory_unobserved": corrupt.metadata[1].room_states_observed[room_id].observed = false
			"door_unknown": row.state = "MARKED"; row.door_id = "unknown"
			"door_owner": row.door_id = candidate.mission_data.doors[0].id
			"result_private": corrupt.metadata[-1].result.room_states[room_id].actor = "hidden"
			"result_future": corrupt.metadata[-1].result.room_states_observed[room_id].changed_tick = 7
			"result_unobserved": corrupt.metadata[-1].result.room_states_observed[room_id].observed = false
			"call_unit": corrupt.events[0].unit_id = candidate.events[-1].enemy_id
			"call_cover": corrupt.events[0].cover_unit_id = candidate.events[-1].enemy_id
			"call_room": corrupt.events[0].room_id = "unknown"
			"call_observed": corrupt.events[0].observed = "true"
			"call_missing": corrupt.events[0].erase("observed")
			"legacy_call_key": corrupt.events[-1].observed = true
			"pause_reason": corrupt.metadata[0].pause_reason = "combat"
			"pause_unit": corrupt.metadata[0].pause_unit_id = candidate.events[-1].enemy_id
			"pause_type": corrupt.metadata[0].pause_requested = 1
			"pause_missing_down_unit": corrupt.metadata[0].pause_reason = "man_down"; corrupt.metadata[0].erase("pause_unit_id")
		check(not restored.load_data(corrupt).get("ok", true), "Malformed P3 record rejected: " + mutation)
		check(JSON.stringify(restored.export_data()) == before, "Rejected P3 record preserves active replay: " + mutation)

func _test_same_tick_acknowledgement() -> void:
	var mission := _mission()
	var state := _state(mission)
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(state)
	state.time = STEP
	state.tick = 1
	state.units[0].hp = 0.0
	state.units[0].status = "INCAPACITATED"
	state.pause_requested = true
	state.pause_reason = "man_down"
	state.pause_unit_id = state.units[0].id
	var death_events := [{"seq":1, "tick":1, "time":STEP, "type":"INCAPACITATED", "entity_id":state.units[0].id, "kind":"unit"}, {"seq":2, "tick":1, "time":STEP, "type":"CALL_MAN_DOWN", "unit_id":state.units[0].id, "observed":true}]
	state.events = death_events
	recorder.capture(state, death_events)
	check(recorder.frames.size() == 2, "MAN DOWN pause request records immediately")
	state.pause_requested = false
	state.pause_reason = ""
	state.pause_unit_id = ""
	recorder.capture(state, [])
	check(recorder.frames.size() == 2, "Controller acknowledgement replaces only the existing same-tick frame")
	var acknowledged := recorder.seek(STEP, true)
	check(not acknowledged.pause_requested and acknowledged.pause_reason == "" and acknowledged.pause_unit_id == "", "Same-tick final frame matches cleared post-controller pause state")
	check(recorder.events_since(0, STEP) == death_events, "Empty acknowledgement event batch preserves first capture's death and CALL events")
	state.tick = 2
	state.time = 2.0 * STEP
	recorder.finish(state)
	var restored := Replay.new()
	check(restored.load_data(_json(recorder.export_data())).get("ok", false), "Acknowledged same-tick replay passes strict validation")
	check(restored.events_since(0, STEP, false) == _json(death_events), "Death and MAN DOWN original occurrence fields survive save and load")

func _test_legacy() -> void:
	var mission := _mission()
	mission.schema_version = 3
	var state := _state(mission)
	for key: String in Replay.ROOM_STATE_KEYS + ["pause_reason", "pause_unit_id"]: state.erase(key)
	var final: Dictionary = state.duplicate(true)
	final.tick = 1
	final.time = STEP
	final.result = {"success":true, "status":"SUCCESS"}
	var restored := Replay.new()
	check(restored.load_data(_record(mission, state, final)).get("ok", false), "Legacy records without new room and pause metadata remain readable")
	var observed := restored.seek(STEP, false)
	check(observed.room_states.is_empty() and observed.result.get("room_states", {}).is_empty() and not observed.has("room_states_observed"), "Legacy public state safely defaults to UNKNOWN without fabricated clear markers")
	check(not observed.result.has("room_states"), "Legacy result fields retain their original shape when no room metadata existed")
	check(not restored.seek(STEP, true).has("room_states") and not restored.seek(STEP, true).result.has("room_states"), "Explicit full legacy seek preserves original absent-field shape")
	check(not observed.has("pause_reason") and not observed.has("pause_unit_id"), "Legacy pause metadata remains optional")

func _test_room_limit() -> void:
	var mission := _mission()
	mission.bounds = [32,32]
	# Keep original door references. These legal overlapping floor-plan rows
	# share the clear insertion floor: this stresses metadata, not navigation.
	for index: int in range(64 - mission.rooms.size()): mission.rooms.append({"id":"room_%02d" % index, "x":mission.units[0].x, "z":mission.units[0].z, "w":1.0, "d":1.0})
	var validated := Catalog.validate_custom(mission)
	check(validated.get("ok", false), "64-room mission uses valid authored references: " + str(validated.get("message", "")))
	var initial := _state(mission)
	var final: Dictionary = initial.duplicate(true)
	final.tick = 1
	final.time = STEP
	final.result = {"success":true, "status":"SUCCESS", "room_states":final.room_states.duplicate(true), "room_states_observed":final.room_states_observed.duplicate(true)}
	var candidate := _record(mission, initial, final)
	var restored := Replay.new()
	var response := restored.load_data(candidate)
	check(response.get("ok", false), "Dedicated room validator accepts all64 authored rows and nested result beyond generic dict32: " + str(response.get("message", "")))
	if not response.get("ok", false): return
	check(restored.seek(STEP, false).room_states.size() == 64 and restored.seek(STEP, false).result.room_states.size() == 64, "All64 observed UNKNOWN rows survive projection")
	var corrupt: Dictionary = candidate.duplicate(true)
	corrupt.metadata[0].room_states["room_64"] = _row()
	check(not restored.load_data(corrupt).get("ok", true), "A65th room row is rejected without relaxing generic metadata limits")

func _test_rules() -> void:
	var mission := _mission()
	var state := _state(mission)
	state.win = [{"type":"rooms_cleared"}, {"type":"rooms_cleared", "room_ids":[mission.rooms[0].id]}]
	var final: Dictionary = state.duplicate(true)
	final.tick = 1
	final.time = STEP
	var candidate := _record(mission, state, final)
	var restored := Replay.new()
	check(restored.load_data(candidate).get("ok", false), "Missionv4 room clear rules preserve optional omission and explicit room IDs")
	for mutation: String in ["empty", "duplicate", "unknown", "extra", "other_rule", "legacy"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		match mutation:
			"empty": corrupt.metadata[0].win[1].room_ids = []
			"duplicate": corrupt.metadata[0].win[1].room_ids.append(corrupt.metadata[0].win[1].room_ids[0])
			"unknown": corrupt.metadata[0].win[1].room_ids = ["unknown"]
			"extra": corrupt.metadata[0].win[0].seconds = 1.0
			"other_rule": corrupt.metadata[0].win[1].type = "neutralize_all"
			"legacy": corrupt.mission_data.schema_version = 3
		check(not restored.load_data(corrupt).get("ok", true), "Malformed or premature room clear rule rejected: " + mutation)

func _test_boundaries() -> void:
	var mission := _mission()
	var initial := _state(mission)
	var final: Dictionary = initial.duplicate(true)
	final.time = 600.0
	final.tick = 18000
	var room_id := str(mission.rooms[0].id)
	final.room_states[room_id] = {"state":"MARKED", "changed_tick":18000, "changed_at":600.0, "observed":false, "door_id":mission.doors[0].id}
	var restored := Replay.new()
	var candidate := _record(mission,initial,final)
	check(restored.load_data(candidate).get("ok",false), "Inclusive600-second room transition retains older independent memory clocks")
	check(restored.seek(600.0,false).room_states[room_id].state == "UNKNOWN", "Authority observedfalse MARKED does not manufacture public knowledge")
	for field: String in ["changed_tick","changed_at"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		corrupt.metadata[-1].room_states[room_id][field] = 36000001 if field == "changed_tick" else 600.01
		check(not restored.load_data(corrupt).get("ok",true), "Room transition hard bound is strict: " + field)
	check(restored.events_since(0,NAN,false).is_empty() and restored.seek(INF,false).is_empty(), "Nonfinite room replay clocks return no stale observations")

func _runtime_mission(seed_value: int) -> Dictionary:
	var mission := {"schema_version":4, "id":"ROOM_STATE_LIVE", "revision":1, "custom":true, "title":"Room state replay fixture", "seed":seed_value, "variant":"normal", "bounds":[14,14], "focus":[6,6], "rooms":[{"id":"room","x":6.0,"z":6.0,"w":5.0,"d":5.0}, {"id":"hidden","x":11.0,"z":4.0,"w":2.0,"d":2.0}], "units":[{"id":"alpha","name":"ALPHA","weapon":"standard","x":6.0,"z":6.0,"facing":-1.57}], "enemies":[{"id":"hidden_enemy","x":11.0,"z":4.0,"facing":0.0,"ammo":0,"training":true,"passive":true}], "civilians":[{"id":"hidden_civilian","x":11.6,"z":4.3}], "walls":[{"id":"left","x":3.4,"z":6.0,"w":0.2,"d":5.4}, {"id":"right","x":8.6,"z":6.0,"w":0.2,"d":5.4}, {"id":"top","x":6.0,"z":3.4,"w":5.4,"d":0.2}, {"id":"bottom_left","x":4.25,"z":8.5,"w":1.7,"d":0.2}, {"id":"bottom_right","x":7.75,"z":8.5,"w":1.7,"d":0.2}, {"id":"hidden_left","x":9.9,"z":4.0,"w":0.2,"d":2.4}, {"id":"hidden_right","x":12.1,"z":4.0,"w":0.2,"d":2.4}, {"id":"hidden_top","x":11.0,"z":2.9,"w":2.4,"d":0.2}, {"id":"hidden_bottom_left","x":10.05,"z":5.1,"w":0.3,"d":0.2}, {"id":"hidden_bottom_right","x":11.95,"z":5.1,"w":0.3,"d":0.2}], "doors":[{"id":"door","x":6.0,"z":8.5,"w":1.8,"d":0.24,"axis":"x","state":"OPEN","locked":false,"hinge_side":-1,"swing_sign":-1}, {"id":"hidden_door","x":11.0,"z":5.1,"w":1.6,"d":0.24,"axis":"x","state":"CLOSED","locked":false,"hinge_side":-1,"swing_sign":-1}], "props":[], "win":[{"type":"reach_zone","zone":[13.0,13.0,0.2,0.2]}], "fail":[], "stars":[]}
	mission["objectives"] = ["Search, mark and preserve last-observed room memory"]
	mission.units[0]["role"] = "Assault"
	return _json(mission)

func _simulate(seed_value: int, validate: bool) -> Dictionary:
	var mission := _runtime_mission(seed_value)
	var sim := Simulation.new()
	sim.load_mission(mission)
	var face_order := sim.issue("alpha", "FACE", {"target":[6.0,4.0]})
	var wait_order := sim.issue("alpha", "WAIT", {"duration":3.0})
	if validate:
		check(face_order.get("ok",false) and wait_order.get("ok",false), "Actual search plan contains only accepted primitives")
	var recorder := Replay.new()
	recorder.begin(mission)
	var initial := sim.snapshot(true)
	recorder.capture(initial, sim.take_record_events())
	if validate:
		var owned_pair := sim.snapshot_pair()
		owned_pair.observed.room_states.room.state = "CLEAR"
		check(owned_pair.record.room_states.room.state == "UNKNOWN" and owned_pair.record.room_states_observed.room.state == "UNKNOWN" and sim.snapshot(false).room_states.room.state == "UNKNOWN", "Public snapshot_pair room edits cannot mutate record or authority")
	var snapshots: Dictionary = {0:initial}
	var transitions: Array = []
	var previous: Dictionary = initial.room_states.duplicate(true)
	var marked_memory: Dictionary = {}
	for tick: int in range(1, TICKS + 1):
		if tick == 61:
			var move_order := sim.issue("alpha", "MOVE", {"target":[6.0,10.0]})
			var exit_order := sim.issue("alpha", "FACE", {"target":[6.0,12.0], "persistent":true})
			if validate: check(move_order.get("ok",false) and exit_order.get("ok",false), "Actual exit plan contains only accepted primitives")
		if tick == 161:
			# Controlled hidden re-entry changes authoritative actor position.
			# The operative faces away outside the room; the sealed civilian
			# remains unseen. No new observation or CALL may refresh its marker.
			sim.enemies[0].x = 6.0
			sim.enemies[0].z = 5.0
		sim.step(STEP)
		var pair := sim.snapshot_pair()
		var full: Dictionary = pair.record
		var observed: Dictionary = pair.observed
		recorder.capture(full, sim.take_record_events())
		snapshots[tick] = full
		if full.room_states != previous:
			transitions.append({"tick":tick, "time":sim.time, "authority":full.room_states.duplicate(true), "memory":full.room_states_observed.duplicate(true)})
			previous = full.room_states.duplicate(true)
		if tick == 160: marked_memory = full.room_states_observed.room.duplicate(true)
		if validate:
			check(observed.room_states == full.room_states_observed and not observed.has("room_states_observed"), "Actual observed pair uses recorded memory, seed%d/tick%d" % [seed_value,tick])
			check(observed.enemies.is_empty() and observed.civilians.is_empty(), "Actual room state keeps hidden NPCs private, seed%d/tick%d" % [seed_value,tick])
			check(observed.room_states.hidden.state == "UNKNOWN", "Unobserved room cannot gain a marker, seed%d/tick%d" % [seed_value,tick])
	var final := sim.snapshot(true)
	recorder.finish(final)
	if validate:
		check(final.tick == TICKS and final.result.is_empty(), "Runtime remains at its fixed240-tick horizon without premature result")
		check(marked_memory.get("state", "") == "MARKED", "Actual clearer crosses its doorway and leaves a marker")
		check(final.room_states.room.state == "CONTACT" and final.room_states_observed.room == marked_memory, "Actual hidden re-entry changes authority while preserving the complete observed row")
		check(final.units[0].commands.all(func(command: Dictionary) -> bool: return command.state == "SUCCEEDED"), "Actual search-and-exit primitive plan completes")
		check(final.events.any(func(event: Dictionary) -> bool: return event.type == "CALL_ROOM_CLEAR" and event.get("observed",false)), "Actual fixed-step search emits an observed ROOM CLEAR call")
	return {"mission":mission,"data":_json(recorder.export_data()),"snapshots":snapshots,"transitions":transitions,"final":final}

func _project_like(value: Variant, shape: Variant) -> Variant:
	if shape is Dictionary:
		if not value is Dictionary: return null
		var projected: Dictionary = {}
		for key: Variant in shape: projected[key] = _project_like(value.get(key), shape[key])
		return projected
	if shape is Array:
		if not value is Array or value.size() != shape.size(): return null
		var projected: Array = []
		for index: int in range(shape.size()): projected.append(_project_like(value[index], shape[index]))
		return projected
	return value

func _same_snapshot(decoded: Dictionary, actual: Dictionary) -> bool:
	# Replay adds convenience fields such as neutralized_ids and numeric
	# weapon-origin components. Compare every original snapshot field after
	# ordinary JSON serialization, retaining all actor/command/room metadata.
	return JSON.stringify(_json(_project_like(decoded, actual)), "", true) == JSON.stringify(_json(actual), "", true)

func _test_runtime(seed_value: int) -> void:
	var mission := _runtime_mission(seed_value)
	var validation := Catalog.validate_custom(mission)
	check(validation.get("ok", false), "Actual runtime mission schema valid, seed%d: %s" % [seed_value,str(validation.get("message",""))])
	if not validation.get("ok", false): return
	var run := _simulate(seed_value, true)
	var repeat := _simulate(seed_value, false)
	check(JSON.stringify(run.data) == JSON.stringify(repeat.data) and _same_snapshot(repeat.final,run.final), "Same seed and plan reproduce the complete room replay and final snapshot")
	var restored := Replay.new()
	var loaded := restored.load_data(run.data)
	check(loaded.get("ok", false), "Actual room replay loads, seed%d: %s" % [seed_value,str(loaded.get("message",""))])
	if not loaded.get("ok", false): return
	for frame: Array in run.data.frames:
		var actual: Dictionary = run.snapshots[int(frame[1])]
		check(_same_snapshot(restored.seek(float(frame[0]),true),actual), "Every retained frame restores the complete authoritative snapshot, seed%d/tick%d" % [seed_value,int(frame[1])])
	for transition: Dictionary in run.transitions:
		var full := restored.seek(float(transition.time),true)
		var observed := restored.seek(float(transition.time),false)
		check(full.tick == transition.tick and full.room_states == _json(transition.authority), "Actual room transition survives exact-tick seek")
		check(observed.room_states == _json(transition.memory), "Actual transition player seek restores independent memory")
		var before := restored.seek(float(transition.time) - STEP * 0.5,false)
		check(before.tick < transition.tick, "An upcoming room transition cannot move into earlier replay time")
	for rate: int in [1,4]:
		var sequence := 0
		var gathered: Array = []
		for tick: int in range(rate, TICKS + 1, rate):
			var observed := restored.seek(tick * STEP,false)
			var events := restored.events_since(sequence,tick * STEP,false)
			gathered.append_array(events)
			if not events.is_empty(): sequence = int(events[-1].seq)
			check(observed.room_states == _json(run.snapshots[tick].room_states_observed), "Observed live replay%dx preserves discrete memory, seed%d/tick%d" % [rate,seed_value,tick])
			check(observed.enemies.is_empty() and observed.civilians.is_empty(), "Replay%dx does not expose hidden NPCs" % rate)
		check(gathered == run.data.events, "Replay%dx delivers each original observed CALL/event exactly once" % rate)
	var final := restored.seek(float(run.final.time),false)
	final.room_states.room.state = "UNKNOWN"
	check(restored.seek(float(run.final.time),false).room_states.room.state == "MARKED", "Actual replay returned memory cannot mutate future seeks")

func _test_actual_result(seed_value: int) -> void:
	var mission := _runtime_mission(seed_value)
	mission.win = [{"type":"rooms_cleared", "room_ids":["room"]}]
	var sim := Simulation.new()
	sim.load_mission(mission)
	check(sim.issue("alpha","FACE",{"target":[6.0,4.0]}).get("ok",false), "Terminal search FACE uses a valid primitive")
	check(sim.issue("alpha","WAIT",{"duration":3.0}).get("ok",false), "Terminal search WAIT uses a valid primitive")
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(sim.snapshot(true),sim.take_record_events())
	for tick: int in range(60):
		if not sim.result.is_empty(): break
		sim.step(STEP)
		recorder.capture(sim.snapshot(true),sim.take_record_events())
	var full := sim.snapshot(true)
	var observed := sim.snapshot(false)
	check(sim.tick == 46 and full.result.get("success",false), "Actual room rule succeeds afterDOM plus45 fixed eligible search steps")
	check(full.result.room_states.room.state == "CLEAR" and full.result.room_states.hidden.state == "UNKNOWN", "Terminal result retains authority without fabricating hidden-room clearance")
	check(observed.enemies.is_empty() and observed.civilians.is_empty() and not observed.result.has("room_states_observed"), "Terminal live UI retains the observation boundary")
	recorder.finish(full)
	var restored := Replay.new()
	var loaded := restored.load_data(_json(recorder.export_data()))
	check(loaded.get("ok",false), "Actual terminalRESULT record loads, seed%d: %s" % [seed_value,str(loaded.get("message",""))])
	if not loaded.get("ok",false): return
	check(_same_snapshot(restored.seek(sim.time,true),full), "Actual terminal whole snapshot survives full replay")
	var shown := restored.seek(sim.time,false)
	check(shown.result.room_states == _json(observed.result.room_states) and shown.enemies.is_empty() and shown.civilians.is_empty(), "Recorded terminal result projects the same safe room memory as live UI")
	var pair := sim.snapshot_pair()
	pair.observed.result.room_states.room.state = "UNKNOWN"
	pair.observed.room_states.room.state = "UNKNOWN"
	check(pair.record.result.room_states.room.state == "CLEAR" and pair.record.room_states_observed.room.state == "CLEAR" and sim.result.room_states.room.state == "CLEAR", "Nested terminal snapshot_pair outputs independently own room metadata")
	shown.result.room_states.room.changed_tick = 0
	check(restored.seek(sim.time,false).result.room_states.room.changed_tick == 46, "Mutating observed terminal result cannot rewrite stored transition clocks")

func _test_reload_cover_record() -> void:
	var mission := _runtime_mission(42)
	mission.units[0].ammo = 1
	mission.units[0].reserve_ammo = 30
	var cover: Dictionary = mission.units[0].duplicate(true)
	cover.id = "bravo"
	cover.name = "BRAVO"
	cover.x = 6.8
	cover.ammo = 30
	mission.units.append(cover)
	var sim := Simulation.new()
	sim.load_mission(mission)
	sim.units[0].sector = {"start":-2.0,"end":-1.0,"until":10.0}
	check(sim.issue("alpha","RELOAD",{}).get("ok",false), "Reload record uses the existing primitive")
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(sim.snapshot(true),sim.take_record_events())
	var covering: Dictionary = {}
	for tick: int in range(120):
		sim.step(STEP)
		var full := sim.snapshot(true)
		recorder.capture(full,sim.take_record_events())
		if full.units[1].status == "COVERING_RELOAD" and covering.is_empty(): covering = full
	var final := sim.snapshot(true)
	recorder.finish(final)
	check(not covering.is_empty(), "Actual nearest teammate visibly takes the reloader sector")
	check(final.events.any(func(event: Dictionary) -> bool: return event.type == "CALL_RELOADING" and event.get("cover_unit_id") == "bravo") and final.events.any(func(event: Dictionary) -> bool: return event.type == "CALL_GUN_UP"), "Actual reload records both ownership-transfer calls")
	var restored := Replay.new()
	var loaded := restored.load_data(_json(recorder.export_data()))
	check(loaded.get("ok",false), "Actual COVERING_RELOAD status/sector/CALL record loads: " + str(loaded.get("message","")))
	if not loaded.get("ok",false) or covering.is_empty(): return
	check(_same_snapshot(restored.seek(float(covering.time),true),covering), "Actual temporary reload coverage restores the complete frame")
	check(_same_snapshot(restored.seek(float(final.time),true),final), "Actual reload completion and sector restoration survive replay")

func _operator_casualty_mission(seed_value: int, method: String) -> Dictionary:
	# Author a wounded operator at the actual handle and a normal exterior
	# guard with physical LOS. No runtime HP, hit, aim, shot or alert injection
	# is used: the guard's ordinary reaction/accuracy/damage causes the loss.
	var door := {"id":"door","x":8.0,"z":10.5,"axis":"x","w":1.8,"d":0.2,"state":"CLOSED","hinge_side":-1.0,"swing_sign":1.0}
	var handle: Vector2 = Door.handle_floor(door) + Vector2.DOWN * 0.4
	var order: Array[String] = ["alpha","bravo","charlie","delta"]
	var positions: Array = [[handle.x,handle.y],[6.7,12.8],[6.7,13.6],[5.9,13.6]]
	var own: Array = []
	for index: int in range(4):
		own.append({"id":order[index],"name":order[index].to_upper(),"role":"Assault","x":positions[index][0],"z":positions[index][1],"facing":-PI*0.5,"weapon":"shotgun" if index==0 and method=="SHOTGUN_BREACH" else "standard","hp":1.0 if index==0 else 100.0,"armor":"none","helmet":"none","ammo":1 if index==0 and method=="SHOTGUN_BREACH" else 0,"reserve_ammo":0,"breaches":2})
	return _json({"schema_version":4,"id":"ROOM_OPERATOR_CASUALTY","revision":1,"custom":true,"title":"Actual operator casualty","objectives":["Prove door action casualty safety"],"focus":[8,10],"seed":seed_value,"variant":"normal","bounds":[16,16],"rooms":[{"id":"room","x":8.0,"z":8.0,"w":5.0,"d":5.0,"indoor":true}],"walls":[{"id":"left","x":5.5,"z":8.0,"w":0.2,"d":5.0},{"id":"right","x":10.5,"z":8.0,"w":0.2,"d":5.0},{"id":"top","x":8.0,"z":5.5,"w":5.0,"d":0.2},{"id":"bottom_left","x":6.25,"z":10.5,"w":1.5,"d":0.2},{"id":"bottom_right","x":9.75,"z":10.5,"w":1.5,"d":0.2}],"doors":[door],"props":[],"units":own,"enemies":[{"id":"shooter","x":9.5,"z":12.5,"facing":(handle-Vector2(9.5,12.5)).angle(),"response_role":"guard","reserve_ammo":0}],"civilians":[],"win":[{"type":"reach_zone","zone":[15.0,15.0,0.1,0.1]}],"fail":[],"stars":[]})

func _operator_casualty_run(seed_value: int, method: String, automatic_pause: bool) -> Dictionary:
	var mission := _operator_casualty_mission(seed_value,method)
	var validation := Catalog.validate_custom(mission)
	check(validation.get("ok",false), "Actual door casualty fixture is schema-valid: " + str(validation.get("message","")))
	if not validation.get("ok",false): return {}
	var sim := Simulation.new()
	check(sim.configure_team_settings({"auto_pause_man_down":automatic_pause}).get("ok",false), "Door casualty uses the public team preference API")
	sim.load_mission(mission)
	var order: Array[String] = ["alpha","bravo","charlie","delta"]
	var base := "operator_loss"
	check(sim.issue("alpha",method,{"door_id":"door","drill":{"sync_id":base,"door_id":"door","room_id":"room","order":1,"stage":"door"}}).get("ok",false), "Actual casualty starts a valid owned door primitive")
	for index: int in range(1,4):
		check(sim.issue(order[index],"WAIT_FOR_SIGNAL",{"signal":"A","sync_id":base+":entry","auto_signal":true,"drill":{"sync_id":base,"door_id":"door","room_id":"room","order":index+1,"stage":"entry"}}).get("ok",false), "Actual followers use the public automatic entry barrier")
	var initial_ids: Array = sim.units.map(func(unit: Dictionary) -> Array: return unit.commands.map(func(command: Dictionary) -> String: return str(command.id)))
	var recorder := Replay.new()
	recorder.begin(mission)
	var snapshots: Dictionary = {0:sim.snapshot(true)}
	recorder.capture(snapshots[0],sim.take_record_events())
	var before: Dictionary = {}
	var casualty: Dictionary = {}
	for frame: int in range(180):
		before = sim.snapshot(true)
		sim.step(STEP)
		var full := sim.snapshot(true)
		recorder.capture(full,sim.take_record_events())
		snapshots[sim.tick] = full
		if float(sim.units[0].hp)<=0.0:
			casualty = full
			break
	var label := "%s seed%d auto%s" % [method,seed_value,str(automatic_pause)]
	check(not casualty.is_empty() and sim.hits_taken>0 and int(sim.enemies[0].ammo)<int(before.enemies[0].ammo), label + " actual hostile gunfire incapacitates the wounded operator")
	if casualty.is_empty(): return {}
	var prior: Dictionary = before.units[0].commands[0]
	var cancelled: Dictionary = casualty.units[0].commands[0]
	check(prior.state=="RUNNING" and prior.started_tick<casualty.tick and cancelled.state=="CANCELLED" and cancelled.reason=="대원 행동 불능", label + " casualty cancels an already-started unfinished door action")
	if method=="OPEN_DOOR":
		check(before.doors[0].state=="OPENING" and float(before.doors[0].progress)>0.0 and float(before.doors[0].progress)<1.0, label + " ordinary leaf is physically opening when its operator is hit")
	elif method=="BREACH_DOOR":
		# Commands advance before gunfire in the same tick; inspect the phase
		# actually cancelled, not the snapshot before the charge was planted.
		check(cancelled.phase=="BREACH_RETREAT" and sim.breaches_used==1 and sim.units[0].breaches==1 and not sim.doors[0].destroyed, label + " casualty retains one consumed planted charge without detonation or reissue")
	else:
		var spent := seed_value==6
		check(cancelled.phase==("SHOTGUN_RETREAT" if spent else "SHOTGUN_PREPARE") and sim.units[0].ammo==(0 if spent else 1) and bool(sim.doors[0].destroyed)==spent, label + " preparing and consumed shotgun resources retain their exact execution state")
	check(sim.pause_requested and sim.pause_reason=="command_failure" and sim.pause_unit_id.is_empty() and sim.command_failures==1, label + " unsafe entry reports command failure with precedence over optional man-down pause")
	check(casualty.units[1].commands[0].state=="FAILED" and casualty.units[1].commands[0].reason=="문 조작 대원이 행동 불능이 되어 진입을 안전하게 중단했습니다", label + " surviving automatic barrier fails visibly instead of silently waiting forever")
	check(sim._room_registered.is_empty() and sim.doors[0].owner_id.is_empty() and sim.doors[0].owner_command_id.is_empty(), label + " loss releases the door and cannot register the incomplete entry")
	var final_ids: Array = sim.units.map(func(unit: Dictionary) -> Array: return unit.commands.map(func(command: Dictionary) -> String: return str(command.id)))
	check(final_ids==initial_ids and sim.units.slice(1).all(func(unit: Dictionary) -> bool: return unit.commands.all(func(command: Dictionary) -> bool: return command.type=="WAIT_FOR_SIGNAL")) and sim.units.slice(1).all(func(unit: Dictionary) -> bool: return int(unit.breaches)==2 and int(unit.ammo)==0), label + " casualty never clones a door tool or spends another operator's inventory")
	var down_calls: Array = casualty.events.filter(func(event: Dictionary) -> bool: return event.type=="CALL_MAN_DOWN" and event.unit_id=="alpha")
	check(down_calls.size()==1 and down_calls[0].get("observed",false) and int(down_calls[0].tick)==sim.tick and casualty.events.any(func(event: Dictionary) -> bool: return event.type=="INCAPACITATED" and event.entity_id=="alpha") and casualty.events.any(func(event: Dictionary) -> bool: return event.type=="COMMAND_FAILED" and event.unit_id=="bravo"), label + " death and safety failure preserve their single actual team call")
	check(not casualty.events.any(func(event: Dictionary) -> bool: return event.type=="SIGNAL" and event.get("sync_id","")==base+":entry"), label + " unfinished entry cannot emit an automatic release")
	# This is the real controller ACK, after real engine damage. Its second
	# capture has no events; the death/CALL/failure from the first capture must
	# survive while the same tick's stored state becomes the acknowledged one.
	sim.pause_requested = false
	sim.pause_reason = ""
	sim.pause_unit_id = ""
	var acknowledged := sim.snapshot(true)
	recorder.capture(acknowledged,[])
	snapshots[sim.tick] = acknowledged
	recorder.finish(acknowledged)
	var candidate: Dictionary = _json(recorder.export_data())
	check(candidate.frames.filter(func(frame: Array) -> bool: return int(frame[1])==sim.tick).size()==1, label + " same-tick ACK replaces only the frame")
	var restored := Replay.new()
	var loaded := restored.load_data(candidate)
	check(loaded.get("ok",false), label + " actual unfinished door casualty replay loads: " + str(loaded.get("message","")))
	if not loaded.get("ok",false): return {}
	for frame: Array in candidate.frames:
		check(_same_snapshot(restored.seek(float(frame[0]),true),snapshots[int(frame[1])]), label + " every retained casualty frame preserves the complete authoritative snapshot")
	var exact := restored.seek(sim.time,true)
	check(not exact.pause_requested and exact.pause_reason.is_empty() and not exact.has("pause_unit_id") and _same_snapshot(exact,acknowledged), label + " exact-tick replay retains controller ACK and all casualty/resource facts")
	check(restored.seek(sim.time-STEP*0.5,true).units[0].hp>0.0, label + " casualty cannot appear before its actual fixed tick")
	check(restored.events_since(0,sim.time,false)==_json(casualty.events) and restored.events_since(0,sim.time,false).filter(func(event: Dictionary) -> bool: return event.type=="CALL_MAN_DOWN" and event.unit_id=="alpha")==_json(down_calls), label + " ACK preserves original death/CALL/failure event occurrence fields without duplication")
	var observed := restored.seek(sim.time,false)
	check(observed.room_states==_json(acknowledged.room_states_observed) and not observed.has("room_states_observed"), label + " casualty replay retains the observed room-memory boundary")
	return {"data":candidate,"final":acknowledged,"tick":sim.tick,"phase":prior.get("phase","")}

func _test_operator_casualty_records() -> void:
	# Seeds 0/17 cover opening, charge consumption and shotgun preparation.
	# Seed 6 lands a real shot during shotgun retreat after the round is spent;
	# seed 29 still covers the longer preparation before consumption.
	for method: String in ["OPEN_DOOR","BREACH_DOOR","SHOTGUN_BREACH"]:
		var seeds: Array = [0,17,29,6] if method=="SHOTGUN_BREACH" else [0,17]
		for seed_value: int in seeds:
			var manual := _operator_casualty_run(seed_value,method,false)
			var automatic := _operator_casualty_run(seed_value,method,true)
			check(not manual.is_empty() and not automatic.is_empty() and JSON.stringify(manual.data)==JSON.stringify(automatic.data) and _same_snapshot(manual.final,automatic.final), "%s seed%d man-down preference cannot override the deterministic door safety halt" % [method,seed_value])
			if not manual.is_empty(): print("ROOM_OPERATOR_CASUALTY " + JSON.stringify({"method":method,"seed":seed_value,"tick":manual.tick,"phase":manual.phase}))
