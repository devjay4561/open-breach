extends SceneTree
## P6 consumes the existing fixed-STEP numeric record, without replay seek.
const Prior = preload("res://scripts/prior_attempt.gd")
const Replay = preload("res://scripts/replay.gd")
const STEP := 1.0 / 30.0
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func mission(count: int = 2) -> Dictionary:
	var units: Array = []
	for index: int in range(count): units.append({"id":["alpha", "bravo", "charlie", "delta"][index], "x":2.0 + index, "z":2.0, "hp":100.0})
	return {"id":"PRIOR_TEST", "seed":42, "variant":"normal", "bounds":[20.0,20.0],
		"rooms":[{"id":"room", "x":10.0,"z":10.0,"w":18.0,"d":18.0}],
		"walls":[], "doors":[], "props":[], "units":units,
		"enemies":[{"id":"SECRET_ENEMY", "x":18.0,"z":18.0}],
		"civilians":[{"id":"SECRET_CIVILIAN", "x":17.0,"z":18.0}]}

func raw_record(data: Dictionary, frames: int, dead_tick: int = -1) -> Dictionary:
	var states: Array = []
	for unit: Dictionary in data.units:
		states.append({"group":"units", "base":{"id":unit.id,"kind":"unit"},
			"fields":["base_height","hp","x","z"]})
	var record := {"map_id":data.id, "seed":data.seed, "variant":data.variant,
		"encoding":"numeric-state-v1", "states":states, "frames":[]}
	for tick: int in range(frames):
		var packed := PackedFloat64Array()
		for index: int in range(data.units.size()):
			# Alternate axes to make skipped-frame corner shortcuts observable.
			var x: float = 2.0 + index + floor(float(tick) / 2.0) * 0.0001
			var z: float = 2.0 + ceil(float(tick) / 2.0) * 0.0001
			packed.append_array(PackedFloat64Array([5.0,index,9.0,0.0 if index == 0 and tick >= dead_tick and dead_tick >= 0 else 100.0,x,z]))
		record.frames.append([tick * STEP, tick, packed])
	return record

func path(attempt: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in attempt.get("paths", []):
		if row.unit_id == id: return row
	return {}

func wire_numbers(value: Variant) -> Variant:
	# Godot's JSON parser reads 7/30's full-precision decimal as the adjacent
	# float (0.23333333333333336). Preserve every field and tick/index type,
	# projecting only floating inputs through that exact existing wire format.
	if value is float: return JSON.parse_string(JSON.stringify(value, "", true, true))
	if value is Dictionary:
		var projected: Dictionary = {}
		for field: Variant in value: projected[field] = wire_numbers(value[field])
		return projected
	if value is Array: return value.map(func(item: Variant) -> Variant: return wire_numbers(item))
	return value

func run() -> void:
	# A dependency under concurrent editing must fail the suite, not silently
	# leave only its synthetic cases running after a failed Replay.new().
	if not (Replay as Script).can_instantiate():
		check(false, "The actual replay implementation must compile before its fixtures run")
		_finish()
		return
	_test_actual_record()
	_test_identity()
	_test_roster_and_legacy()
	_test_malformed_boundaries()
	_test_segment_budget()
	_test_frame_budget()
	_finish()

func _finish() -> void:
	print("BREACH_PRIOR_ATTEMPT_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_actual_record() -> void:
	var authored: Dictionary = mission()
	var recorder := Replay.new()
	recorder.begin(authored)
	var state := {"time":0.0, "tick":0, "units":[], "enemies":[], "civilians":[], "doors":[], "events":[]}
	for source: Dictionary in authored.units:
		state.units.append({"id":source.id, "kind":"unit", "x":source.x, "z":source.z, "hp":100.0, "base_height":9.0, "commands":[]})
	state.enemies = [{"id":"SECRET_ENEMY","x":18.0,"z":18.0,"hp":70.0,"visible":false}]
	state.civilians = [{"id":"SECRET_CIVILIAN","x":17.0,"z":18.0,"hp":80.0,"visible":false}]
	recorder.capture(state)
	for tick: int in range(1, 13):
		state.tick = tick
		state.time = tick * STEP
		if tick <= 3: state.units[0].x = 2.0 + tick * 0.01
		else: state.units[0].z = 2.0 + (tick - 3) * 0.01
		if tick == 7: state.units[0].hp = 0.0
		recorder.capture(state)
	recorder.finish(state)
	var input_before: Dictionary = recorder.export_data()
	var attempt: Dictionary = Prior.capture(recorder, authored.id, authored, [])
	check(Prior.matches(attempt, authored.id, authored, []), "Same mission condition accepts its previous attempt")
	check(attempt.paths.size() == 2 and path(attempt, "bravo").points.size() == 1, "Stationary own unit keeps one pose without redundant edges")
	check(path(attempt, "bravo").segments.is_empty(), "Stationary samples consume no segment budget")
	check(attempt.fallen == [{"x":state.units[0].x,"z":2.04,"base_height":9.0,"tick":7,"time":7 * STEP,"unit_id":"alpha"}], "First raw HP transition records the exact sub-sample death tick and elevated pose")
	check(recorder.export_data() == input_before, "Capture never mutates the source replay")
	var numeric_frames: Array = recorder.frames.map(func(frame: Array)->int: return int(frame[1]))
	var alpha: Dictionary = path(attempt, "alpha")
	for edge: Array in alpha.segments:
		var first: Dictionary = alpha.points[edge[0]]
		var last: Dictionary = alpha.points[edge[1]]
		check(numeric_frames.find(last.tick) == numeric_frames.find(first.tick) + 1, "Each real replay edge joins consecutive recorded frames")
		check(first.base_height == 9.0 and last.base_height == 9.0, "Recorded floor height survives without ground-plane projection")
	var wire: Dictionary = JSON.parse_string(JSON.stringify(input_before, "", true, true))
	var wire_attempt: Dictionary = Prior.capture(wire, authored.id, authored, [])
	check(wire_attempt == wire_numbers(attempt), "Imported JSON preserves the complete overlay at its exact wire numeric values")
	check(wire_attempt.fallen[0].time == wire.frames[3][0] and wire_attempt.fallen[0].tick == 7, "Imported fall retains its raw serialized sample clock and exact tick")
	var hostile: Dictionary = wire.duplicate(true)
	for definition: Dictionary in hostile.states:
		if definition.group != "units": definition.clear()
	for frame: Array in hostile.frames:
		for index: int in range(3, frame.size()): frame[index] = {"SECRET_UNKNOWN_POSITION":[999.0,999.0]}
	hostile["events"] = [{"type":"INCAPACITATED","kind":"enemy","entity_id":"SECRET_ENEMY","tick":1}]
	hostile["metadata"] = [{"room_states":{"sealed":{"state":"MARKED"}}}]
	check(Prior.capture(hostile, authored.id, authored, []) == wire_attempt, "NPC rows, hidden incapacitations and unobserved room metadata cannot affect own trails")
	var text: String = JSON.stringify(attempt)
	check(not text.contains("SECRET") and not text.contains("INCAPACITATED") and not text.contains("sealed"), "Overlay carries no hidden identity, location, event or room state")
	var detached: Dictionary = attempt.duplicate(true)
	recorder.frames[-1][2][4] = -500.0
	state.units[0].x = -999.0
	check(attempt == detached, "Later recorder and simulation edits cannot move prior attempt points")
	attempt.paths[0].points[0].x = -700.0
	check(wire.frames[0][2][4] != -700.0, "Overlay edits do not alias imported replay vectors")

func _test_identity() -> void:
	var authored: Dictionary = mission()
	var key: String = Prior.snapshot_key(authored.id, authored, [])
	check(key.length() == 64, "Condition uses a stable SHA256 rather than runtime hash")
	var reordered: Dictionary = {}
	var keys: Array = authored.keys()
	keys.reverse()
	for field: String in keys: reordered[field] = authored[field]
	check(Prior.snapshot_key(authored.id, reordered, []) == key, "Authored dictionary insertion order does not change the condition")
	var attempt := {"key":key}
	check(not Prior.matches(attempt, "OTHER", authored, []), "Changing mission identity clears the overlay")
	for field: String in ["seed", "variant", "bounds", "rooms", "walls", "doors", "props", "walkable_areas", "scenery", "units"]:
		var changed: Dictionary = authored.duplicate(true)
		match field:
			"seed": changed.seed = 43
			"variant": changed.variant = "hard"
			"bounds": changed.bounds[0] = 21.0
			"rooms": changed.rooms[0].w = 17.0
			"units": changed.units[0].x = 2.00000000000001
			_: changed[field] = [{"x":3.0,"z":3.0,"w":1.0,"d":1.0}]
		check(not Prior.matches(attempt, authored.id, changed, []), "Changing actual " + field + " invalidates the prior condition")
	var private_changes: Dictionary = authored.duplicate(true)
	private_changes.enemies = [{"id":"DIFFERENT_SECRET","x":0.0,"z":0.0}]
	private_changes.civilians.clear()
	check(Prior.matches(attempt, authored.id, private_changes, []), "Hidden actor definitions never participate in overlay matching")
	check(not Prior.matches(attempt, authored.id, authored, [{"id":"persistent-a","base_id":"alpha"}]), "Changing the deployed roster clears the overlay")
	check(not Prior.matches({}, authored.id, authored, []) and Prior.snapshot_key("", authored, []).is_empty(), "An absent prior attempt or mission cannot match")

func _test_roster_and_legacy() -> void:
	var authored: Dictionary = mission(4)
	var raw: Dictionary = raw_record(authored, 4, 2)
	var roster := [{"id":"persistent-bravo","base_id":"bravo"},{"id":"persistent-alpha","base_id":"alpha"}]
	var attempt: Dictionary = Prior.capture(raw, authored.id, authored, roster)
	check(attempt.paths.map(func(row: Dictionary)->String:return row.unit_id) == ["bravo","alpha"], "Persistent roster IDs resolve only to deployed authored own base IDs")
	check(attempt.fallen.size() == 1 and attempt.fallen[0].unit_id == "alpha", "Fallen markers remain tied to actual own base IDs")
	var record: Dictionary = raw_record(mission(1), 2)
	record.states[0].fields = ["hp","x","z"]
	for frame: Array in record.frames:
		frame[2] = PackedFloat64Array([4.0,0.0,100.0,2.0 + int(frame[1]) * 0.01,2.0])
	var legacy: Dictionary = Prior.capture(record, authored.id, mission(1), [])
	check(legacy.paths[0].points.all(func(point: Dictionary)->bool:return point.base_height == 0.0), "Legacy records without base_height use the existing ground default")
	var initial_dead: Dictionary = raw_record(mission(1), 4, 0)
	check(Prior.capture(initial_dead, authored.id, mission(1), []).fallen.is_empty(), "Already incapacitated first sample does not invent a fall")
	check(Prior.capture({"encoding":"legacy"}, authored.id, authored, []).is_empty(), "Unsupported record encodings cannot expose unrelated state")
	check(Prior.capture(null, authored.id, authored, []).is_empty(), "Missing recorder fails safely")
	var foreign: Dictionary = raw.duplicate(true)
	foreign.seed = 43
	check(Prior.capture(foreign, authored.id, authored, []).is_empty(), "A record from another seed is not relabeled as this condition")
	foreign.seed = 42
	foreign.map_id = "OTHER"
	check(Prior.capture(foreign, authored.id, authored, []).is_empty(), "A record from another mission cannot be relabeled")

func _test_malformed_boundaries() -> void:
	var authored: Dictionary = mission(1)
	for mode: String in ["missing", "nan", "truncated", "duplicate", "wrong_group", "time"]:
		var raw: Dictionary = raw_record(authored, 3)
		match mode:
			"missing": raw.frames[1][2] = []
			"nan": raw.frames[1][2][4] = NAN
			"truncated": raw.frames[1][2] = [99.0,0.0]
			"duplicate": raw.frames[1][2].append_array(raw.frames[1][2].duplicate())
			"wrong_group":
				raw.states.append({"group":"enemies","base":{"id":"alpha"},"fields":["base_height","hp","x","z"]})
				raw.frames[1][2][1] = 1.0
			"time": raw.frames[1][0] = -1.0
		var attempt: Dictionary = Prior.capture(raw, authored.id, authored, [])
		check(attempt.paths[0].segments.is_empty(), "Malformed " + mode + " sample cannot join poses across a recording gap")
		check(attempt.fallen.is_empty(), "Malformed " + mode + " cannot invent an incapacitation")
	var private_id: Dictionary = raw_record(authored, 3)
	private_id.states[0].base.id = "SECRET_ENEMY"
	check(Prior.capture(private_id, authored.id, authored, []).is_empty(), "An unknown row ID inside the own group is still excluded")

func _test_segment_budget() -> void:
	var authored: Dictionary = mission(4)
	var raw: Dictionary = raw_record(authored, 4001, 4000)
	var attempt: Dictionary = Prior.capture(raw, authored.id, authored, [])
	var total: int = 0
	var points: int = 0
	for row: Dictionary in attempt.paths:
		var unit_index: int = attempt.paths.find(row)
		total += row.segments.size()
		points += row.points.size()
		check(row.segments.size() == 3000, "Each of four moving own units receives its bounded segment share")
		var valid: bool = true
		var last_tick: int = -1
		for edge: Array in row.segments:
			var first: Dictionary = row.points[edge[0]]
			var last: Dictionary = row.points[edge[1]]
			valid = valid and last.tick == first.tick + 1 and first.tick > last_tick
			last_tick = first.tick
			valid = valid and first.x == 2.0 + unit_index + floor(float(first.tick) / 2.0) * 0.0001
			valid = valid and last.z == 2.0 + ceil(float(last.tick) / 2.0) * 0.0001
		check(valid, "Thinning retains exact original corner-adjacent endpoints without fabricated connections")
		check(row.points[-1].tick == 4000, "Bounded trails retain real edges through the end of the attempt")
	check(total == Prior.MAX_SEGMENTS and points <= Prior.MAX_SEGMENTS * 2 + 4, "Total output is capped at 12000 original segments and 24004 owned points")
	check(attempt.fallen[0].tick == 4000 and attempt.fallen[0].time == 4000 * STEP, "Late first fall survives path thinning with exact recorded tick/time")
	check(Prior.capture(raw, authored.id, authored, []) == attempt, "Segment allocation is deterministic across repeated captures")

func _test_frame_budget() -> void:
	check(Prior.MAX_FRAMES == Replay.MAX_FRAMES, "Overlay scan bound preserves the existing replay frame contract")
	var authored: Dictionary = mission(1)
	var raw: Dictionary = raw_record(authored, Prior.MAX_FRAMES + 1, Prior.MAX_FRAMES - 1)
	var attempt: Dictionary = Prior.capture(raw, authored.id, authored, [])
	check(attempt.fallen[0].tick == Prior.MAX_FRAMES - 1, "The last permitted recording sample can still record a fall")
	check(attempt.paths[0].points[-1].tick == Prior.MAX_FRAMES - 1, "Frames beyond the existing recording bound never enter the trail")
	check(attempt.paths[0].segments.size() == Prior.MAX_SEGMENTS, "Single-unit records reuse the full budget without an unbounded path")
	raw.frames[Prior.MAX_FRAMES - 1][2][3] = 100.0
	check(Prior.capture(raw, authored.id, authored, []).fallen.is_empty(), "A fall after the maximum retained frame is never inferred from discarded data")
