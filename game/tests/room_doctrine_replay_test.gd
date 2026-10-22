extends SceneTree
## P6 evidence links are occurrence-owned, exact-tick receipts. Continuous
## values use the ordinary sample cadence; only changed evidence forces a frame.
const Replay = preload("res://scripts/replay.gd")
const Presentation = preload("res://scripts/presentation_state.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const STEP := 1.0 / 30.0
const ROWS := ["stealth", "doorway_dwell", "time_to_dominate", "threat_order_violations", "identification", "control", "marked", "rear_hits"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	if "--pair-only" in OS.get_cmdline_user_args():
		_test_actual_pair_only()
		_report()
		return
	_test_continuous_sampling()
	_test_validation_and_ownership()
	_test_room_limit()
	_test_legacy()
	_test_presentation()
	for seed_value: int in range(30): _test_roundtrip(seed_value)
	if not "--format-only" in OS.get_cmdline_user_args():
		for seed_value: int in [0, 17, 29]: _test_actual_room(seed_value)
	_report()

func _report() -> void:
	print("BREACH_ROOM_DOCTRINE_REPLAY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _project_like(value: Variant, shape: Variant) -> Variant:
	if shape is Dictionary:
		if not value is Dictionary: return null
		var output: Dictionary = {}
		for key: Variant in shape: output[key] = _project_like(value.get(key), shape[key])
		return output
	if shape is Array:
		if not value is Array or value.size() != shape.size(): return null
		var output: Array = []
		for index: int in range(shape.size()): output.append(_project_like(value[index], shape[index]))
		return output
	return value

func _same(decoded: Dictionary, actual: Dictionary) -> bool:
	return JSON.stringify(_json(_project_like(decoded,actual)),"",true) == JSON.stringify(_json(actual),"",true)

func _rng_states(sim: RefCounted) -> Array:
	return [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]

func _mission(seed_value: int = 0) -> Dictionary:
	var mission: Dictionary = Catalog.load("M01")
	mission.schema_version = 4
	mission.id = "ROOM_DOCTRINE_REPLAY"
	mission.custom = true
	mission.seed = seed_value
	return mission

func _empty_rows() -> Dictionary:
	var rows: Dictionary = {}
	for metric: String in ROWS: rows[metric] = {"value":null, "tick":null, "time":null}
	return rows

func _state(mission: Dictionary) -> Dictionary:
	var own: Dictionary = mission.units[0]
	var enemy: Dictionary = mission.enemies[0]
	return {"time":0.0, "tick":0, "units":[{"id":own.id,"kind":"unit","x":own.x,"z":own.z,"hp":100.0,"commands":[]}], "enemies":[{"id":enemy.id,"kind":"enemy","x":enemy.x,"z":enemy.z,"hp":100.0,"visible":false}], "civilians":[], "doors":[], "events":[], "result":{}, "room_doctrine":{mission.rooms[0].id:_empty_rows()}}

func _record(seed_value: int = 0) -> Dictionary:
	var mission := _mission(seed_value)
	var state := _state(mission)
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(state)
	var room_id: String = mission.rooms[0].id
	for tick: int in range(1, 9):
		state.tick = tick
		state.time = tick * STEP
		var metric: String = ROWS[tick - 1]
		var row: Dictionary = state.room_doctrine[room_id][metric]
		row.merge({"value":float(tick),"tick":tick,"time":state.time,"unit_id":mission.units[0].id,"door_id":mission.doors[0].id}, true)
		if metric == "identification": row.merge({"civilian_damage":1.25,"unlawful_shots":1})
		if metric == "control": row.merge({"arrested":1,"surrendered":2,"secured":1,"civilians":2})
		if tick == 8: state.result = {"success":false,"status":"FAILED","room_doctrine":state.room_doctrine.duplicate(true)}
		recorder.capture(state)
	recorder.finish(state)
	return {"data":_json(recorder.export_data()), "state":state, "recorder":recorder}

func _test_continuous_sampling() -> void:
	var mission := _mission()
	var state := _state(mission)
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(state)
	var row: Dictionary = state.room_doctrine[mission.rooms[0].id].doorway_dwell
	for tick: int in range(1, 8):
		state.tick = tick
		state.time = tick * STEP
		row.value = state.time
		if tick == 3: row.merge({"tick":tick,"time":state.time}, true)
		recorder.capture(state)
	recorder.finish(state)
	var ticks: Array = recorder.frames.map(func(frame: Array) -> int: return int(frame[1]))
	check(ticks == [0,3,6,7], "Dwell accumulation preserves the ordinary 0.1s cadence and forces only evidence tick3")
	var restored := Replay.new()
	check(restored.load_data(_json(recorder.export_data())).get("ok",false), "Finite continuous values with absent evidence links remain valid")
	check(restored.seek(3.0*STEP,true).room_doctrine[mission.rooms[0].id].doorway_dwell.tick == 3, "A failure evidence link targets the actual retained tick")

func _test_roundtrip(seed_value: int) -> void:
	var run := _record(seed_value)
	var repeat := _record(seed_value)
	check(JSON.stringify(run.data) == JSON.stringify(repeat.data), "Repeated fixed-seed receipt records serialize identically: seed%d" % seed_value)
	var restored := Replay.new()
	var loaded := restored.load_data(run.data)
	check(loaded.get("ok",false), "Exact8row record loads: seed%d %s" % [seed_value,loaded.get("message","")])
	if not loaded.get("ok",false): return
	check(run.data.schema_version == 1 and run.data.encoding == "numeric-state-v1", "P6 keeps schema1/numeric-state-v1")
	var room_id: String = run.data.mission_data.rooms[0].id
	for tick: int in [8,0,4,1,7,2,6,3,5]:
		var shown := restored.seek(tick*STEP,false)
		check(shown.tick == tick and shown.enemies.is_empty(), "Exact receipt seek stays observed-only: seed%d/tick%d" % [seed_value,tick])
		for index: int in range(8):
			var row: Dictionary = shown.room_doctrine[room_id][ROWS[index]]
			check(row.tick == (index+1 if index < tick else null), "Every metric preserves its original occurrence tick")
		if tick > 0:
			check(restored.seek((tick-0.5)*STEP,false).tick == tick-1, "Evidence cannot run ahead of a fractional replay clock")
	for speed: int in [1,4]:
		for tick: int in range(0,9,speed):
			check(restored.seek(tick*STEP,false).room_doctrine == restored.seek(tick*STEP,true).room_doctrine, "Public-only metrics stay identical at replay %dx" % speed)
	check(restored.seek(8.0*STEP,false).result.room_doctrine == _json(run.state.result.room_doctrine), "Terminal evidence links survive nested result roundtrip")

func _test_validation_and_ownership() -> void:
	var run := _record()
	var candidate: Dictionary = run.data
	var room_id: String = candidate.mission_data.rooms[0].id
	var restored := Replay.new()
	check(restored.load_data(candidate).get("ok",false), "Valid P6 record accepted before mutations")
	var immutable := JSON.stringify(restored.export_data())
	for mutation: String in ["array","null","unknown_room","missing_metric","extra_metric","row_array","missing_value","value_bool","value_nan","value_negative","value_overflow","extra_npc","extra_position","enemy_unit","unknown_unit","unknown_door","tick_only","time_only","null_value_evidence","tick_fraction","tick_negative","tick_overflow","time_nan","time_mismatch","future_tick","future_time","wrong_metric_extra","count_fraction","damage_bool","result_future","result_private"]:
		var bad: Dictionary = candidate.duplicate(true)
		var first: Dictionary = bad.metadata[0]
		var last: Dictionary = bad.metadata[-1]
		var row: Dictionary = first.room_doctrine[room_id].stealth
		match mutation:
			"array": first.room_doctrine = []
			"null": first.room_doctrine = null
			"unknown_room": first.room_doctrine.unknown = _empty_rows()
			"missing_metric": first.room_doctrine[room_id].erase("control")
			"extra_metric": first.room_doctrine[room_id].enemy_alert = {}
			"row_array": first.room_doctrine[room_id].stealth = []
			"missing_value": row.erase("value")
			"value_bool": row.value = true
			"value_nan": row.value = NAN
			"value_negative": row.value = -0.1
			"value_overflow": row.value = 10000001
			"extra_npc": row.enemy_id = candidate.mission_data.enemies[0].id
			"extra_position": row.position = [1,2]
			"enemy_unit": row.unit_id = candidate.mission_data.enemies[0].id
			"unknown_unit": row.unit_id = "unknown"
			"unknown_door": row.door_id = "unknown"
			"tick_only": row.tick = 0
			"time_only": row.time = 0.0
			"null_value_evidence": row.tick = 0; row.time = 0.0
			"tick_fraction": row.value = 1; row.tick = 0.5; row.time = STEP*0.5
			"tick_negative": row.value = 1; row.tick = -1; row.time = -STEP
			"tick_overflow": row.value = 1; row.tick = 18001; row.time = 18001*STEP
			"time_nan": row.value = 1; row.tick = 0; row.time = NAN
			"time_mismatch": row.value = 1; row.tick = 0; row.time = STEP
			"future_tick": row.value = 1; row.tick = 1; row.time = STEP
			"future_time": row.value = 1; row.tick = 1; row.time = STEP
			"wrong_metric_extra": row.civilian_damage = 1.0
			"count_fraction": last.room_doctrine[room_id].control.arrested = 0.5
			"damage_bool": last.room_doctrine[room_id].identification.civilian_damage = true
			"result_future": last.result.room_doctrine[room_id].stealth.merge({"value":1,"tick":9,"time":9.0*STEP},true)
			"result_private": last.result.room_doctrine[room_id].control.hostile_ids = []
		check(not restored.load_data(bad).get("ok",true), "Malformed doctrine record rejects: "+mutation)
	check(JSON.stringify(restored.export_data()) == immutable, "Malformed loads preserve the loaded graph and all nested receipt rows")
	var shown := restored.seek(8.0*STEP,false)
	shown.room_doctrine[room_id].control.value = 999
	shown.result.room_doctrine[room_id].control.tick = 0
	check(restored.seek(8.0*STEP,false).room_doctrine[room_id].control.value == 6 and restored.seek(8.0*STEP,false).result.room_doctrine[room_id].control.tick == 6, "Returned top/result receipt rows own independent replay history")
	run.state.room_doctrine[room_id].stealth.value = 999
	run.state.result.room_doctrine[room_id].stealth.value = 999
	check(run.recorder.seek(0.0,true).room_doctrine[room_id].stealth.value == null and run.recorder.seek(8.0*STEP,true).result.room_doctrine[room_id].stealth.value == 1, "Reused caller dictionaries cannot mutate interned top or nested result metadata")

func _test_room_limit() -> void:
	var mission := _mission()
	mission.bounds = [32,32]
	mission.walls = []
	mission.doors = []
	mission.props = []
	mission.rooms = []
	for index: int in range(64): mission.rooms.append({"id":"r%d"%index,"x":2.0+(index%8)*3.0,"z":2.0+floori(index/8.0)*3.0,"w":1.0,"d":1.0})
	var validation := Catalog.validate_custom(mission)
	check(validation.get("ok",false), "64room fixture schema: "+JSON.stringify(validation))
	if not validation.get("ok",false): return
	var state := _state(mission)
	state.room_doctrine.clear()
	for room: Dictionary in mission.rooms: state.room_doctrine[room.id] = _empty_rows()
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(state)
	recorder.finish(state)
	var restored := Replay.new()
	var candidate: Dictionary = _json(recorder.export_data())
	var loaded := restored.load_data(candidate)
	check(loaded.get("ok",false), "Dedicated room validator accepts64 rooms beyond generic small-tree32: "+str(loaded.get("message","")))
	if not loaded.get("ok",false): return
	check(restored.seek(0.0,false).room_doctrine.size() == 64, "All64 known public-room empty rows survive seek")
	candidate.metadata[0].room_doctrine.r64 = _empty_rows()
	check(not restored.load_data(candidate).get("ok",true), "A65th room is rejected")

func _test_legacy() -> void:
	var mission := _mission()
	var state := _state(mission)
	state.erase("room_doctrine")
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(state)
	recorder.finish(state)
	var restored := Replay.new()
	check(restored.load_data(_json(recorder.export_data())).get("ok",false), "Legacy record without room doctrine still loads")
	check(not restored.seek(0.0,false).has("room_doctrine"), "Legacy absence remains absent for N/A UI")
	var presentation := Presentation.new()
	presentation.reset(state)
	check(not presentation.sample(1.0).has("room_doctrine"), "Legacy presentation does not inject empty doctrine metadata")

func _test_presentation() -> void:
	var mission := _mission()
	var previous := _state(mission)
	var current: Dictionary = previous.duplicate(true)
	var room_id: String = mission.rooms[0].id
	current.time = STEP
	current.tick = 1
	current.room_doctrine[room_id].rear_hits = {"value":1,"tick":1,"time":STEP}
	previous.result = {"room_doctrine":previous.room_doctrine.duplicate(true)}
	current.result = {"room_doctrine":current.room_doctrine.duplicate(true)}
	var presentation := Presentation.new()
	presentation.reset(previous)
	presentation.capture(current)
	current.room_doctrine[room_id].rear_hits.value = 99
	current.result.room_doctrine[room_id].rear_hits.value = 99
	var between := presentation.sample(0.5)
	check(between.room_doctrine[room_id].rear_hits.value == null and between.result.room_doctrine[room_id].rear_hits.value == null, "Top/result metrics cannot run ahead of the rendered occurrence clock")
	var at_tick := presentation.sample(1.0)
	check(at_tick.room_doctrine[room_id].rear_hits.value == 1 and at_tick.result.room_doctrine[room_id].rear_hits.value == 1, "Presentation stores owned input receipt rows at the actual tick")
	at_tick.room_doctrine[room_id].rear_hits.value = 999
	at_tick.result.room_doctrine[room_id].rear_hits.value = 999
	check(presentation.sample(1.0).room_doctrine[room_id].rear_hits.value == 1 and presentation.sample(1.0).result.room_doctrine[room_id].rear_hits.value == 1, "Returned presentation receipt maps cannot rewrite its history")

func _actual_mission(seed_value: int) -> Dictionary:
	# One actual stationary team member searches its current room. The hidden
	# next room has a passive occupant; no HP/death/shot/room-state injection.
	var mission: Dictionary = {"schema_version":4,"id":"ROOM_DOCTRINE_LIVE","revision":1,"custom":true,"title":"Live room receipts","objectives":["Actual fixed-step search"],"focus":[6,6],"seed":seed_value,"bounds":[16,16],"rooms":[{"id":"room","x":6.0,"z":6.0,"w":5.0,"d":5.0},{"id":"hidden","x":12.0,"z":6.0,"w":4.0,"d":5.0}],"walls":[{"id":"divider","x":9.0,"z":8.0,"w":0.2,"d":16.0}],"doors":[],"props":[],"units":[{"id":"alpha","name":"ALPHA","role":"Assault","x":6.0,"z":6.0,"facing":-PI*0.5,"ammo":0,"reserve_ammo":0}],"enemies":[{"id":"hidden_enemy","x":12.0,"z":6.0,"facing":0.0,"ammo":0,"reserve_ammo":0,"passive":true}],"civilians":[],"win":[{"type":"rooms_cleared","room_ids":["room"]}],"fail":[],"stars":[]}
	mission.units[0].weapon = "standard"
	# Keep the next room physically reachable around the lower wall end,
	# while the stationary observer has no LOS through the opaque divider.
	mission.walls[0].z = 6.0
	mission.walls[0].d = 12.0
	return mission

func _test_actual_room(seed_value: int) -> void:
	var mission := _actual_mission(seed_value)
	var validation := Catalog.validate_custom(mission)
	check(validation.get("ok",false), "Actual room fixture schema: "+JSON.stringify(validation))
	if not validation.get("ok",false): return
	var sim := Simulation.new()
	sim.load_mission(mission)
	check(sim.issue("alpha","FACE",{"target":[6.0,4.0]}).get("ok",false) and sim.issue("alpha","WAIT",{"duration":3.0}).get("ok",false), "Actual room plan uses existing accepted primitives")
	var recorder := Replay.new()
	recorder.begin(mission)
	var initial := sim.snapshot(true)
	recorder.capture(initial,sim.take_record_events())
	var snapshots: Dictionary = {0:initial}
	var rng: Array = [_rng_states(sim)]
	for unused: int in range(60):
		if not sim.result.is_empty(): break
		sim.step(STEP)
		var pair := sim.snapshot_pair()
		recorder.capture(pair.record,sim.take_record_events())
		snapshots[sim.tick] = pair.record
		rng.append(_rng_states(sim))
		check(pair.observed.enemies.is_empty() and not pair.observed.room_doctrine.has("hidden"), "Actual room doctrine cannot reveal an unobserved next room")
	var final := sim.snapshot(true)
	recorder.finish(final)
	check(sim.tick == 46 and final.result.get("success",false), "Actual search reaches terminal CLEAR after45 eligible fixed steps")
	var repeat := Simulation.new()
	repeat.load_mission(mission)
	repeat.issue("alpha","FACE",{"target":[6.0,4.0]})
	repeat.issue("alpha","WAIT",{"duration":3.0})
	check(_same(repeat.snapshot(true),initial) and _rng_states(repeat) == rng[0], "Actual repeat begins with the same complete state and4 RNG streams")
	for tick: int in range(1,sim.tick+1):
		repeat.step(STEP)
		check(_same(repeat.snapshot(true),snapshots[tick]) and _rng_states(repeat) == rng[tick], "Every actual fixed tick repeats the complete authoritative state and4 RNG")
	var restored := Replay.new()
	var loaded := restored.load_data(_json(recorder.export_data()))
	check(loaded.get("ok",false), "Actual room doctrine record loads: "+str(loaded.get("message","")))
	if not loaded.get("ok",false): return
	check(final.room_doctrine.has("room") and final.result.room_doctrine == final.room_doctrine, "Actual terminal result owns the same public occurrence rows")
	var owned_pair := sim.snapshot_pair()
	var original_pair := JSON.stringify(owned_pair.record)
	owned_pair.observed.room_doctrine.room.marked.value = 999
	owned_pair.observed.result.room_doctrine.room.marked.value = 999
	check(JSON.stringify(owned_pair.record) == original_pair and _same(sim.snapshot(true),final), "Actual paired top/result receipt maps independently own their nested rows")
	for frame: Array in restored.frames:
		check(_same(restored.seek(float(frame[0]),true),snapshots[int(frame[1])]), "Every retained frame restores every authoritative snapshot field")
		var shown := restored.seek(float(frame[0]),false)
		check(shown.room_doctrine == _json(snapshots[int(frame[1])].room_doctrine), "Every retained actual frame restores exactly its public receipt rows")
	for metrics: Dictionary in final.room_doctrine.values():
		for row: Dictionary in metrics.values():
			if row.tick != null:
				check(restored.seek(float(row.time),false).tick == row.tick, "Every actual public receipt links to its exact retained tick")
	for speed: int in [1,4]:
		for tick: int in range(speed,sim.tick+1,speed):
			var shown := restored.seek(tick*STEP,false)
			check(shown.enemies.is_empty() and not shown.room_doctrine.has("hidden"), "Actual1x/4x replay preserves hidden-room privacy")

func _test_actual_pair_only() -> void:
	var sim := Simulation.new()
	sim.load_mission(_actual_mission(0))
	check(sim.issue("alpha","FACE",{"target":[6.0,4.0]}).get("ok",false) and sim.issue("alpha","WAIT",{"duration":3.0}).get("ok",false), "Ownership probe uses accepted actual primitives")
	for tick: int in range(60):
		if not sim.result.is_empty(): break
		sim.step(STEP)
	check(sim.tick == 46 and sim.result.get("success",false), "Ownership probe reaches the actual terminal room search")
	var pair := sim.snapshot_pair()
	var record_before := JSON.stringify(pair.record)
	var core_before := JSON.stringify(sim.snapshot(true))
	pair.observed.room_doctrine.room.marked.value = 999
	pair.observed.result.room_doctrine.room.marked.value = 999
	check(JSON.stringify(pair.record) == record_before and JSON.stringify(sim.snapshot(true)) == core_before, "Observed top/result nested receipt mutations leave recorded and authoritative snapshots unchanged")
