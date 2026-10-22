extends SceneTree
## P2 saves expanded primitives in the existing plan/replay formats. All
## simulation advances use fixed seeds and STEP; scene frames initialize UI.
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const MainScene = preload("res://main.tscn")
const STEP := 1.0 / 30.0
# This save/replay fixture includes an all-left approach and optional GO_LONG.
# Cohort routing expanded its original 29 primitives to 48: at STEP=1/30,
# seed 0 releases ready at tick 344, opens the door at 399, finishes primary
# goals at 580 and the last GO_LONG primitive at 631 (21.033 seconds).
# Thirty seconds covers that actual route; the standard room performance gate
# still measures <=3 seconds after door OPEN in room_drill_test.gd.
const TICKS := 900
const ORDER := ["delta", "bravo", "alpha", "charlie"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	_test_contracts()
	_test_sync_coherence()
	_test_legacy()
	_test_boundaries()
	for seed_value: int in range(30): _test_runtime(seed_value)
	await _test_main_plans()
	print("BREACH_ROOM_DRILL_REPLAY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _fixture(seed_value: int) -> Dictionary:
	var units: Array = []
	for index: int in range(4):
		var id: String = ["alpha", "bravo", "charlie", "delta"][index]
		# Authored mission numbers use ordinary JSON decimals. Irrational
		# geometry remains in the generated macro, where round trips are tested.
		units.append({"id":id, "name":id.to_upper(), "role":"Assault", "weapon":"standard", "x":7.1, "z":9.5 + index * 0.7, "facing":-1.57})
	var mission := {"schema_version":3, "id":"ROOM_DRILL_REPLAY", "revision":1, "custom":true, "title":"Drill replay fixture", "seed":seed_value, "variant":"normal", "bounds":[16,16], "focus":[8,8], "rooms":[{"id":"room", "x":8.0, "z":6.0, "w":5.0, "d":5.0}, {"id":"hidden", "x":13.0, "z":3.0, "w":2.0, "d":2.0}], "walls":[{"id":"left", "x":5.4, "z":6.0, "w":0.2, "d":5.4}, {"id":"right", "x":10.6, "z":6.0, "w":0.2, "d":5.4}, {"id":"top", "x":8.0, "z":3.4, "w":5.4, "d":0.2}, {"id":"bottom_left", "x":6.15, "z":8.5, "w":1.3, "d":0.2}, {"id":"bottom_right", "x":9.85, "z":8.5, "w":1.3, "d":0.2}, {"id":"hidden_left", "x":11.9, "z":3.0, "w":0.2, "d":2.4}, {"id":"hidden_right", "x":14.1, "z":3.0, "w":0.2, "d":2.4}, {"id":"hidden_top", "x":13.0, "z":1.9, "w":2.4, "d":0.2}, {"id":"hidden_bottom_left", "x":12.1, "z":4.1, "w":0.4, "d":0.2}, {"id":"hidden_bottom_right", "x":13.9, "z":4.1, "w":0.4, "d":0.2}], "doors":[{"id":"door", "x":8.0, "z":8.5, "w":2.4, "d":0.24, "axis":"x", "state":"CLOSED", "hinge_side":-1.0, "swing_sign":-1.0, "locked":false}, {"id":"hidden_door", "x":13.0, "z":4.1, "w":1.4, "d":0.24, "axis":"x", "state":"CLOSED", "hinge_side":-1.0, "swing_sign":-1.0, "locked":false}], "props":[], "units":units, "enemies":[{"id":"hidden_enemy", "x":12.5, "z":2.7, "facing":0.0, "ammo":0, "training":true, "passive":true}], "civilians":[{"id":"hidden_civilian", "x":13.6, "z":3.2}], "objectives":["Enter the room"], "win":[{"type":"reach_zone", "zone":[15.0,15.0,0.2,0.2]}], "fail":[], "stars":[]}
	# Match the real mission-file path: JSON numbers load as floats, including
	# schema integers. This keeps strict Main plan equality about saved data.
	return JSON.parse_string(JSON.stringify(mission))

func _drill(stage: String) -> Dictionary:
	return {"sync_id":"drill-1", "door_id":"d1", "room_id":"hall", "order":1, "stage":stage}

func _contract_state(mission: Dictionary) -> Dictionary:
	var room_id := str(mission.rooms[0].id)
	var door_id := str(mission.doors[0].id)
	var commands: Array = [
		{"id":"stack", "type":"MOVE", "args":{"target":[12.0,18.0], "drill":_drill("stack")}, "state":"PENDING"},
		{"id":"ready", "type":"WAIT_FOR_SIGNAL", "args":{"signal":"B", "sync_id":"drill-1:ready", "auto_signal":false, "delay_ticks":3, "drill":_drill("ready")}, "state":"PENDING"},
		{"id":"open", "type":"OPEN_DOOR", "args":{"door_id":door_id, "drill":_drill("door")}, "state":"PENDING"},
		{"id":"entry", "type":"WAIT_FOR_SIGNAL", "args":{"signal":"B", "sync_id":"drill-1:entry", "auto_signal":true, "delay_ticks":0, "drill":_drill("entry")}, "state":"PENDING"},
		{"id":"move", "type":"MOVE", "args":{"target":[12.0,14.0], "sector":{"start":2.8,"end":-2.8,"duration":120.0}, "drill":_drill("entry")}, "state":"PENDING"},
		{"id":"face", "type":"FACE", "args":{"target":[12.0,11.0], "persistent":true, "sector":{"start":-PI,"end":PI,"duration":0.0}, "drill":_drill("domination")}, "state":"PENDING"},
		{"id":"long", "type":"WAIT_FOR_SIGNAL", "args":{"signal":"B", "sync_id":"drill-1:go_long", "auto_signal":true, "delay_ticks":3600, "drill":_drill("go_long")}, "state":"PENDING"}]
	for command: Dictionary in commands:
		command.args.drill.room_id = room_id
		command.args.drill.door_id = door_id
	return {"time":0.0, "tick":0, "units":[{"id":mission.units[0].id, "kind":"unit", "x":mission.units[0].x, "z":mission.units[0].z, "hp":100.0, "sector":{}, "commands":commands}], "enemies":[{"id":mission.enemies[0].id, "kind":"enemy", "x":mission.enemies[0].x, "z":mission.enemies[0].z, "hp":72.0, "visible":false}], "civilians":[{"id":mission.civilians[0].id, "kind":"civilian", "x":mission.civilians[0].x, "z":mission.civilians[0].z, "visible":false}], "doors":[{"id":door_id, "x":mission.doors[0].x, "z":mission.doors[0].z, "state":"CLOSED"}], "events":[]}

func _record(mission: Dictionary, initial: Dictionary, final: Dictionary) -> Dictionary:
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(initial)
	recorder.finish(final)
	return JSON.parse_string(JSON.stringify(recorder.export_data()))

func _test_contracts() -> void:
	var mission: Dictionary = Catalog.load("M01")
	var state := _contract_state(mission)
	state.time_to_dominate = {str(mission.doors[0].id):{"room_id":mission.rooms[0].id, "opened_at":0.0, "participants":[mission.units[0].id], "arrived":[], "seconds":-1.0, "observed":false, "targets":{str(mission.units[0].id):[12.0,14.0]}}}
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(state)
	state.time = STEP
	state.tick = 1
	state.units[0].sector = {"start":2.8, "end":-2.8, "until":120.0}
	recorder.capture(state)
	check(recorder.frames.size() == 2, "Sector activation records at its exact tick below the sample interval")
	state.time = STEP * 2.0
	state.tick = 2
	state.units[0].sector.start = -PI
	state.units[0].sector.end = PI
	recorder.capture(state)
	check(recorder.frames.size() == 3, "In-place sector expansion does not mutate the previous discrete signature")
	state.time = STEP * 3.0
	state.tick = 3
	state.units[0].sector = {}
	state.events = [{"seq":1, "tick":3, "time":state.time, "type":"SIGNAL", "channel":"B", "released":1, "sync_id":"drill-1:ready", "auto_signal":false}, {"seq":2, "tick":3, "time":state.time, "type":"SIGNAL", "channel":"B", "released":1, "sync_id":"drill-1:entry", "auto_signal":true}]
	recorder.finish(state)
	var candidate: Dictionary = JSON.parse_string(JSON.stringify(recorder.export_data()))
	var restored := Replay.new()
	var loaded: Dictionary = restored.load_data(candidate)
	check(loaded.get("ok", false), "P2 optional serialization contract accepted: " + str(loaded.get("message", "")))
	if not loaded.get("ok", false): return
	check(candidate.schema_version == 1 and candidate.encoding == "numeric-state-v1", "P2 preserves the replay envelope and numeric encoding")
	check(restored.seek(STEP, true).units[0].sector == {"start":2.8, "end":-2.8, "until":120.0}, "Sector activation is not interpolated from a future expansion")
	check(restored.seek(STEP * 2.0, true).units[0].sector == JSON.parse_string(JSON.stringify({"start":-PI, "end":PI, "until":120.0})), "Sector expansion retains its exact serialized angles and clock")
	check(restored.seek(STEP * 3.0, true).units[0].sector.is_empty(), "Sector expiry remains discrete")
	check(restored.seek(STEP * 3.0, false).enemies.is_empty() and restored.seek(STEP * 3.0, false).civilians.is_empty(), "Drill metadata does not expose hidden NPCs")
	check(restored.seek(STEP * 3.0, false).time_to_dominate.is_empty(), "Domination targets do not reveal unobserved room state")
	check(restored.events_since(0, STEP * 3.0) == candidate.events, "Delta event playback preserves grouped manual and automatic signals")
	check(restored.events_since(1, STEP * 3.0).size() == 1 and restored.events_since(2, STEP * 3.0).is_empty(), "Grouped signal deltas do not repeat prior events")
	check(restored.seek(0.0, true).units[0].sector.is_empty(), "Seeking backward resets presentation to its initial sector")
	var before := JSON.stringify(restored.export_data())
	for mutation: String in ["drill_extra", "drill_missing", "drill_id", "drill_large", "drill_door", "drill_room", "drill_order", "drill_fraction", "drill_stage", "sync_id", "sync_group", "sync_stage", "sync_missing", "auto_type", "auto_ungrouped", "entry_manual", "delay_negative", "delay_fraction", "delay_large", "delay_nan", "delay_ungrouped", "delay_zero_ungrouped", "sector_extra", "sector_missing", "sector_nan", "sector_angle", "sector_duration", "sector_owner", "unlock_sector", "runtime_owner", "runtime_shape", "runtime_nan", "runtime_until", "event_id", "event_owner", "event_auto", "event_group", "target_owner", "target_nan", "target_count"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		match mutation:
			"drill_extra": corrupt.commands[0].args.drill.command_id = "open"
			"drill_missing": corrupt.commands[0].args.drill.erase("order")
			"drill_id": corrupt.commands[0].args.drill.sync_id = "unsafe group"
			"drill_large": corrupt.commands[0].args.drill.sync_id = "x".repeat(56)
			"drill_door": corrupt.commands[0].args.drill.door_id = "missing"
			"drill_room": corrupt.commands[0].args.drill.room_id = "missing"
			"drill_order": corrupt.commands[0].args.drill.order = 5
			"drill_fraction": corrupt.commands[0].args.drill.order = 1.5
			"drill_stage": corrupt.commands[0].args.drill.stage = "execute"
			"sync_id": corrupt.commands[1].args.sync_id = "x".repeat(65)
			"sync_group": corrupt.commands[1].args.sync_id = "other:ready"
			"sync_stage": corrupt.commands[1].args.sync_id = "drill-1:entry"
			"sync_missing": corrupt.commands[3].args.erase("sync_id")
			"auto_type": corrupt.commands[1].args.auto_signal = "false"
			"auto_ungrouped": corrupt.commands[1].args.erase("sync_id"); corrupt.commands[1].args.erase("drill"); corrupt.commands[1].args.erase("delay_ticks")
			"entry_manual": corrupt.commands[3].args.auto_signal = false
			"delay_negative": corrupt.commands[1].args.delay_ticks = -1
			"delay_fraction": corrupt.commands[1].args.delay_ticks = 0.5
			"delay_large": corrupt.commands[1].args.delay_ticks = 3601
			"delay_nan": corrupt.commands[1].args.delay_ticks = NAN
			"delay_ungrouped": corrupt.commands[1].args.erase("sync_id"); corrupt.commands[1].args.erase("drill")
			"delay_zero_ungrouped": corrupt.commands[1].args.erase("sync_id"); corrupt.commands[1].args.erase("drill"); corrupt.commands[1].args.erase("auto_signal"); corrupt.commands[1].args.delay_ticks = 0
			"sector_extra": corrupt.commands[4].args.sector.origin = [12,18]
			"sector_missing": corrupt.commands[4].args.sector.erase("end")
			"sector_nan": corrupt.commands[4].args.sector.start = NAN
			"sector_angle": corrupt.commands[4].args.sector.end = PI + 0.01
			"sector_duration": corrupt.commands[4].args.sector.duration = 120.01
			"sector_owner": corrupt.commands[2].args.sector = corrupt.commands[4].args.sector.duplicate(true)
			"unlock_sector": corrupt.commands[5].args.erase("target"); corrupt.commands[5].args.erase("persistent"); corrupt.commands[5].args.unlock = true
			"runtime_owner": _mutate_static(corrupt, "enemies", "sector", {})
			"runtime_shape": _mutate_static(corrupt, "units", "sector", {"start":0.0,"end":1.0,"duration":1.0})
			"runtime_nan": _mutate_static(corrupt, "units", "sector", {"start":0.0,"end":1.0,"until":NAN})
			"runtime_until": _mutate_static(corrupt, "units", "sector", {"start":0.0,"end":1.0,"until":720.01})
			"event_id": corrupt.events[0].sync_id = "unsafe group"
			"event_owner": corrupt.events[0].type = "RELOAD"
			"event_auto": corrupt.events[0].auto_signal = 1
			"event_group": corrupt.events[1].erase("sync_id")
			"target_owner": corrupt.metadata[0].time_to_dominate[mission.doors[0].id].targets = {str(mission.enemies[0].id):[12.0,14.0]}
			"target_nan": corrupt.metadata[0].time_to_dominate[mission.doors[0].id].targets[mission.units[0].id][0] = NAN
			"target_count": corrupt.metadata[0].time_to_dominate[mission.doors[0].id].targets = {}
		check(not restored.load_data(corrupt).get("ok", true), "Malformed P2 record rejected: " + mutation)
		check(JSON.stringify(restored.export_data()) == before, "Rejected P2 record leaves active presentation unchanged: " + mutation)

func _mutate_static(candidate: Dictionary, group: String, key: String, value: Variant) -> void:
	for definition: Dictionary in candidate.states:
		if definition.group == group:
			definition.base[key] = value
			return

func _test_sync_coherence() -> void:
	var mission: Dictionary = Catalog.load("M01")
	var state := _contract_state(mission)
	var participant: Dictionary = state.units[0].duplicate(true)
	participant.id = mission.units[1].id
	participant.x = mission.units[1].x
	participant.z = mission.units[1].z
	participant.commands = [state.units[0].commands[1].duplicate(true)]
	participant.commands[0].id = "other-ready"
	participant.commands[0].args.drill.order = 2
	state.units.append(participant)
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(state)
	state.time = STEP
	state.tick = 1
	for unit: Dictionary in state.units:
		for command: Dictionary in unit.commands:
			if command.type == "WAIT_FOR_SIGNAL" and command.args.sync_id == "drill-1:ready":
				command.args.signal = "C"
				command.args.auto_signal = true
				command.args.delay_ticks = 7
	recorder.capture(state)
	check(recorder.frames.size() == 2, "Atomic pending-group edits capture the changed barrier at its exact tick")
	state.time = STEP * 2.0
	state.tick = 2
	recorder.finish(state)
	var candidate: Dictionary = JSON.parse_string(JSON.stringify(recorder.export_data()))
	var restored := Replay.new()
	check(restored.load_data(candidate).get("ok", false), "Replay accepts coherent pending-group revisions across different frames")
	check(restored.seek(0.0, true).units[1].commands[0].args.signal == "B" and restored.seek(STEP, true).units[1].commands[0].args.signal == "C", "Barrier edits do not rewrite earlier signal presentation")
	var before := JSON.stringify(restored.export_data())
	for mutation: String in ["channel", "delay", "auto", "drill_absent", "drill_door", "drill_room"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		var changed := false
		for command: Dictionary in corrupt.commands:
			if command.id != "other-ready": continue
			match mutation:
				"channel": command.args.signal = "A"
				"delay": command.args.delay_ticks = 100
				"auto": command.args.auto_signal = not bool(command.args.auto_signal)
				"drill_absent": command.args.erase("drill")
				"drill_door": command.args.drill.door_id = mission.doors[1].id
				"drill_room": command.args.drill.room_id = mission.rooms[1].id
			changed = true
		check(changed, "Group mismatch mutation reaches a serialized participant")
		check(not restored.load_data(corrupt).get("ok", true), "Same-frame group mismatch is rejected: " + mutation)
		check(JSON.stringify(restored.export_data()) == before, "Rejected group mismatch preserves prior replay: " + mutation)

func _test_legacy() -> void:
	var mission: Dictionary = Catalog.load("M01")
	var initial := _contract_state(mission)
	initial.units[0].erase("sector")
	initial.units[0].commands = [{"id":"legacy", "type":"WAIT_FOR_SIGNAL", "args":{"signal":"A"}, "state":"WAITING"}, {"id":"legacy-move", "type":"MOVE", "args":{"target":[12.0,18.0]}, "state":"PENDING"}]
	var final: Dictionary = initial.duplicate(true)
	final.time = STEP
	final.tick = 1
	final.events = [{"seq":1,"tick":1,"time":STEP,"type":"SIGNAL","channel":"A","released":1}]
	var restored := Replay.new()
	check(restored.load_data(_record(mission, initial, final)).get("ok", false), "Schema1 records with legacy primitive arguments and SIGNAL events remain readable")
	var decoded: Dictionary = restored.seek(STEP, true)
	check(not decoded.units[0].has("sector"), "Legacy records do not fabricate a sector or hidden doctrine state")
	check(decoded.units[0].commands == final.units[0].commands, "Legacy commands retain their original argument shape")
	check(decoded.events == JSON.parse_string(JSON.stringify(final.events)), "Legacy signal events retain their original serialized shape")

func _test_boundaries() -> void:
	var mission: Dictionary = Catalog.load("M01")
	var initial := _contract_state(mission)
	initial.units[0].sector = {"start":PI,"end":-PI,"until":720.0}
	var final: Dictionary = initial.duplicate(true)
	final.time = 600.0
	final.tick = 18000
	var restored := Replay.new()
	check(restored.load_data(_record(mission, initial, final)).get("ok", false), "Inclusive sector angle, duration, delay and late-expiry bounds remain valid")
	check(restored.seek(INF, true).is_empty() and restored.seek(NAN, true).is_empty(), "Nonfinite seeks do not expose stale presentation")
	check(restored.seek(-1.0, true).time == 0.0 and restored.seek(601.0, true).time == 600.0, "Seek clamps to the recorded prefix at both boundaries")
	check(restored.seek(600.0, true).units[0].sector.until == 720.0, "A valid sector active near the recording limit keeps its full expiry clock")
	for stage: String in Replay.DRILL_STAGES:
		initial.units[0].commands[0].args.drill.stage = stage
		initial.units[0].commands[0].args.drill.sync_id = "x".repeat(55)
		final = initial.duplicate(true)
		final.time = STEP
		final.tick = 1
		check(restored.load_data(_record(mission, initial, final)).get("ok", false), "Common metadata accepts each defined stage and the group ID boundary: " + stage)

func _run_simulation(sim: RefCounted, recorder: RefCounted = null) -> Array:
	var transitions: Array = []
	var previous := ""
	if recorder != null: recorder.capture(sim.snapshot(true))
	for tick_index: int in range(TICKS):
		sim.step(STEP)
		if recorder != null:
			var state: Dictionary = sim.snapshot(true)
			recorder.capture(state)
			var sectors: Array = state.units.map(func(unit: Dictionary) -> Dictionary: return unit.get("sector", {}).duplicate(true))
			var signature := JSON.stringify(sectors)
			if signature != previous:
				transitions.append({"time":sim.time, "tick":sim.tick, "sectors":JSON.parse_string(signature)})
				previous = signature
	if recorder != null: recorder.finish(sim.snapshot(true))
	return transitions

func _test_runtime(seed_value: int) -> void:
	var mission := _fixture(seed_value)
	var validation: Dictionary = Catalog.validate_custom(mission)
	check(validation.get("ok", false), "Actual drill fixture is valid, seed %d: %s" % [seed_value, validation.get("message", "")])
	if not validation.get("ok", false): return
	var sim := Simulation.new()
	sim.load_mission(mission)
	var planned: Dictionary = sim.plan_room_entry("door", "OPEN_DOOR", ORDER, {"delay_ticks":3,"go_long":true})
	check(planned.get("ok", false), "Actual drill expands to primitives, seed %d: %s" % [seed_value, planned.get("message", "")])
	if not planned.get("ok", false): return
	var recorder := Replay.new()
	recorder.begin(mission)
	var transitions: Array = _run_simulation(sim, recorder)
	var final: Dictionary = sim.snapshot(true)
	var candidate: Dictionary = JSON.parse_string(JSON.stringify(recorder.export_data()))
	var restored := Replay.new()
	var loaded: Dictionary = restored.load_data(candidate)
	check(loaded.get("ok", false), "Actual drill replay loads, seed %d: %s" % [seed_value, loaded.get("message", "")])
	if not loaded.get("ok", false): return
	check(candidate.schema_version == 1 and candidate.encoding == "numeric-state-v1", "Actual drill records preserve the existing schema")
	check(final.units.all(func(unit: Dictionary) -> bool: return unit.commands.all(func(command: Dictionary) -> bool: return command.state == "SUCCEEDED")), "All actual drill primitives finish successfully, seed %d" % seed_value)
	check(not candidate.commands.any(func(command: Dictionary) -> bool: return command.type == "ENTER_ROOM"), "Saved macro contains existing primitive types only")
	var go_long_units: Array = final.units.filter(func(unit: Dictionary) -> bool: return unit.commands.any(func(command: Dictionary) -> bool: return command.type == "MOVE" and command.args.get("drill", {}).get("stage", "") == "go_long"))
	check(go_long_units.size() == 2, "Actual GO_LONG retains its two advancing participants")
	for unit: Dictionary in go_long_units:
		var go_long_faces: Array = unit.commands.filter(func(command: Dictionary) -> bool: return command.type == "FACE" and command.args.get("drill", {}).get("stage", "") == "go_long")
		check(go_long_faces.size() == 1 and go_long_faces[0].state == "SUCCEEDED", "Actual GO_LONG finishes its advancing participant's watch command")
		if not go_long_faces.is_empty():
			var expected_sector: Dictionary = go_long_faces[0].args.sector
			check(unit.get("sector", {}).get("start") == expected_sector.start and unit.get("sector", {}).get("end") == expected_sector.end, "Final GO_LONG sector retains the authored watch fan")
	check(candidate.events.any(func(event: Dictionary) -> bool: return event.type == "SIGNAL" and event.get("auto_signal", false) and event.get("sync_id", "").ends_with(":entry")), "Actual entry barrier emits its scoped automatic signal")
	check(transitions.size() > 1, "Actual drill activates and expands sector presentation")
	for transition: Dictionary in transitions:
		var sampled: Dictionary = restored.seek(float(transition.time), true)
		check(sampled.tick == transition.tick, "Actual sector transition is sampled at its authoritative tick")
		check(sampled.units.map(func(unit: Dictionary) -> Dictionary: return unit.get("sector", {})) == transition.sectors, "Every actual sector transition survives seeking exactly")
	var decoded: Dictionary = restored.seek(recorder.duration, true)
	for index: int in range(final.units.size()):
		check(decoded.units[index].commands == JSON.parse_string(JSON.stringify(final.units[index].commands)), "Every final primitive retains metadata and runtime state, seed %d unit %d" % [seed_value,index])
		check(decoded.units[index].get("sector", {}) == JSON.parse_string(JSON.stringify(final.units[index].get("sector", {}))), "Final actor sector matches serialized authoritative state")
		check(is_equal_approx(float(decoded.units[index].x), float(final.units[index].x)) and is_equal_approx(float(decoded.units[index].z), float(final.units[index].z)), "Final domination position is preserved")
	check(restored.seek(recorder.duration, false).enemies.is_empty() and restored.seek(recorder.duration, false).civilians.is_empty(), "Actual player replay omits isolated hidden NPCs, seed %d" % seed_value)
	check(not JSON.stringify(candidate).contains("_sync_") and not JSON.stringify(candidate).contains("_drill_"), "Private readiness/request clocks are not serialized")
	var prior_events: Array = restored.events_since(-1, 0.0)
	var last_seq := int(prior_events[-1].seq) if not prior_events.is_empty() else -1
	var tail: Array = restored.events_since(last_seq, recorder.duration)
	check(prior_events + tail == candidate.events, "Actual replay signal deltas reconstruct the complete event sequence")
	var repeated := Simulation.new()
	repeated.load_mission(mission)
	check(repeated.plan_room_entry("door", "OPEN_DOOR", ORDER, {"delay_ticks":3,"go_long":true}).get("ok", false), "Repeated actual drill accepted")
	var repeated_record := Replay.new()
	repeated_record.begin(mission)
	_run_simulation(repeated, repeated_record)
	check(JSON.stringify(repeated.snapshot(true)) == JSON.stringify(final), "Same seed and expanded drill produce identical full snapshots, seed %d" % seed_value)
	check(JSON.stringify(repeated_record.export_data()) == JSON.stringify(recorder.export_data()), "Same seed and expanded drill produce byte-identical replay content, seed %d" % seed_value)

func _test_main_plans() -> void:
	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	await process_frame
	# Existing plans save the current primitive graph, not the editing history.
	# configure_unit()/issue()/update_command_args() count planning edits, and
	# step() clears them on the first authoritative tick. Demonstrate that
	# pre-existing contract before checking every drill runtime tick exactly.
	session._action({"action":"start", "mission":"M01", "seed":0})
	check(session.sim.issue("alpha", "WAIT", {"duration":3.0}).get("ok", false), "Baseline ordinary primitive accepted")
	check(session.sim.update_command_args("alpha", 0, {"duration":2.0}).get("ok", false), "Baseline ordinary plan edit accepted")
	var baseline: Dictionary = session.sim.snapshot(true)
	var baseline_plan: Dictionary = session._export_plan()
	session.sim.step(STEP)
	var baseline_tick: String = JSON.stringify(session.sim.snapshot(true))
	session._import_plan(JSON.parse_string(JSON.stringify(baseline_plan)), false)
	var imported_baseline: Dictionary = session.sim.snapshot(true)
	check(imported_baseline.plan_revisions != baseline.plan_revisions, "Existing primitive plans do not persist pre-execution editing history")
	baseline.erase("plan_revisions")
	imported_baseline.erase("plan_revisions")
	check(JSON.stringify(imported_baseline) == JSON.stringify(baseline), "Existing fresh-plan authorititative state matches apart from editing history")
	session.sim.step(STEP)
	check(JSON.stringify(session.sim.snapshot(true)) == baseline_tick, "Existing fresh-plan history resets at the first fixed authoritative tick")
	for seed_value: int in range(30):
		var registered: Dictionary = session._register_custom(_fixture(seed_value))
		check(not registered.is_empty(), "Main accepts the actual drill custom mission, seed %d" % seed_value)
		if registered.is_empty(): continue
		session._action({"action":"start","mission":"ROOM_DRILL_REPLAY","seed":seed_value})
		var planned: Dictionary = session.sim.plan_room_entry("door", "OPEN_DOOR", ORDER, {"delay_ticks":3,"go_long":true})
		check(planned.get("ok", false), "Main simulation creates a saveable drill, seed %d" % seed_value)
		if not planned.get("ok", false): continue
		var fresh: Dictionary = session.sim.snapshot(true)
		var exported: Dictionary = session._export_plan()
		check(exported.schema_version == 1 and exported.kind == "breach-plan", "Expanded drill preserves the existing plan format")
		var expected_ticks: Array[String] = []
		for tick_index: int in range(TICKS):
			session.sim.step(STEP)
			expected_ticks.append(JSON.stringify(session.sim.snapshot(true)))
		session._import_plan(JSON.parse_string(JSON.stringify(exported)), false)
		var imported: Dictionary = session.sim.snapshot(true)
		fresh.erase("plan_revisions")
		imported.erase("plan_revisions")
		check(JSON.stringify(imported) == JSON.stringify(fresh), "Mission-roster issuance preserves full initial state apart from existing edit history, seed %d" % seed_value)
		check(session._export_plan() == exported, "Main plan import/export preserves all expanded primitive arguments")
		for tick_index: int in range(TICKS):
			session.sim.step(STEP)
			check(JSON.stringify(session.sim.snapshot(true)) == expected_ticks[tick_index], "Imported plan preserves the complete authoritative tick, seed %d tick %d" % [seed_value,tick_index+1])
		session._import_plan(exported, false)
		var before := JSON.stringify(session.sim.snapshot(true))
		for mutation: String in ["group", "room", "sector", "delay", "entry_manual"]:
			var invalid: Dictionary = exported.duplicate(true)
			var changed := false
			for unit_plan: Dictionary in invalid.units:
				for command: Dictionary in unit_plan.commands:
					if changed: break
					match mutation:
						"group":
							if command.type == "WAIT_FOR_SIGNAL": command.args.sync_id = "wrong:ready"; changed = true
						"room": command.args.drill.room_id = "missing"; changed = true
						"sector":
							if command.args.has("sector"): command.args.sector.start = NAN; changed = true
						"delay":
							if command.type == "WAIT_FOR_SIGNAL": command.args.delay_ticks = 1.5; changed = true
						"entry_manual":
							if command.type == "WAIT_FOR_SIGNAL" and command.args.drill.stage == "entry": command.args.auto_signal = false; changed = true
			check(changed, "Invalid plan mutation reaches its intended metadata: " + mutation)
			session._import_plan(invalid, false)
			check(JSON.stringify(session.sim.snapshot(true)) == before, "Invalid drill plan preserves the active Main simulation: " + mutation)
		var legacy: Dictionary = exported.duplicate(true)
		for unit_plan: Dictionary in legacy.units:
			for command: Dictionary in unit_plan.commands:
				for key: String in ["drill", "sector", "sync_id", "auto_signal", "delay_ticks"]: command.args.erase(key)
		session._import_plan(legacy, false)
		check(session._export_plan() == legacy, "Existing metadata-free primitive plans remain readable, seed %d" % seed_value)
	session.queue_free()
	await process_frame
