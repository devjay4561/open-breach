extends RefCounted
## P6 planning overlay: only recorded, owned poses leave this boundary.
## Every drawn edge joins adjacent retained frames, never skipped corners.
const ENCODING := "numeric-state-v1"
const MAX_FRAMES := 24001 # Existing Replay.MAX_FRAMES; no replay format change.
const MAX_SEGMENTS := 12000
const MAX_UNITS := 4
const MAX_PACKED_VALUES := 4096
const MAX_FIELDS := 256
const GEOMETRY_KEYS := ["bounds", "rooms", "walls", "doors", "props", "walkable_areas", "scenery"]

static func snapshot_key(mission_id: String, active_mission: Dictionary, roster: Array) -> String:
	if mission_id.is_empty(): return ""
	var geometry: Dictionary = {}
	for field: String in GEOMETRY_KEYS:
		if active_mission.has(field): geometry[field] = active_mission[field]
	# Authored own starts also invalidate a custom map whose ID stays the same.
	# NPCs, events and simulation metadata never participate in this key.
	var identity := {"mission_id":mission_id, "seed":active_mission.get("seed", 1),
		"variant":active_mission.get("variant", mission_id), "geometry":geometry,
		"units":active_mission.get("units", []), "roster":roster}
	return JSON.stringify(identity, "", true, true).sha256_text()

static func matches(attempt: Dictionary, mission_id: String, active_mission: Dictionary, roster: Array) -> bool:
	var candidate: String = snapshot_key(mission_id, active_mission, roster)
	return not candidate.is_empty() and attempt.get("key", "") == candidate

static func capture(recording: Variant, mission_id: String, active_mission: Dictionary, roster: Array) -> Dictionary:
	var data: Variant = recording if recording is Dictionary else (recording.get("data") if recording is RefCounted else null)
	if not data is Dictionary or data.get("encoding", "") != ENCODING: return {}
	if data.get("map_id", "") != mission_id or data.get("seed", 1) != active_mission.get("seed", 1): return {}
	if data.get("variant", mission_id) != active_mission.get("variant", mission_id): return {}
	if not data.get("frames") is Array or not data.get("states") is Array: return {}
	var ids: Array = _own_ids(active_mission, roster)
	if ids.is_empty(): return {}
	var summary: Dictionary = _summarize(data, ids)
	if summary.initial.is_empty(): return {}
	var quotas: Dictionary = _quotas(ids, summary.counts)
	var paths: Array = _paths(data, ids, summary, quotas)
	var fallen: Array = []
	for id: String in ids:
		if summary.fallen.has(id): fallen.append(summary.fallen[id])
	return {"key":snapshot_key(mission_id, active_mission, roster), "paths":paths, "fallen":fallen}

static func _own_ids(mission: Dictionary, roster: Array) -> Array:
	var authored: Array = []
	if not mission.get("units") is Array: return authored
	for row: Variant in mission.units:
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or authored.has(row.id): continue
		authored.append(row.id)
		if authored.size() == MAX_UNITS: break
	var selected: Array = []
	for member: Variant in roster:
		if not member is Dictionary: continue
		var id: Variant = member.get("base_id", member.get("id", ""))
		if id is String and authored.has(id) and not selected.has(id): selected.append(id)
		if selected.size() == MAX_UNITS: break
	return authored if selected.is_empty() else selected

static func _summarize(data: Dictionary, ids: Array) -> Dictionary:
	var summary := {"counts":{}, "initial":{}, "fallen":{}}
	var previous: Dictionary = {}
	var health: Dictionary = {}
	var previous_time: float = -1.0
	for index: int in range(mini(data.frames.size(), MAX_FRAMES)):
		var frame: Variant = data.frames[index]
		if not _frame_valid(frame, previous_time):
			previous.clear()
			continue
		previous_time = float(frame[0])
		var current: Dictionary = _own_rows(frame, data.states, ids)
		for id: String in ids:
			if not current.has(id): continue
			var sample: Dictionary = current[id]
			var point: Dictionary = _point(sample, frame)
			if not summary.initial.has(id): summary.initial[id] = point
			if not summary.fallen.has(id) and float(health.get(id, 0.0)) > 0.0 and float(sample.hp) <= 0.0:
				var fallen: Dictionary = point.duplicate()
				fallen["unit_id"] = id
				summary.fallen[id] = fallen
			health[id] = sample.hp
			if previous.has(id) and _moved(previous[id].point, point):
				summary.counts[id] = int(summary.counts.get(id, 0)) + 1
			current[id] = {"point":point}
		previous = current
	return summary

static func _quotas(ids: Array, counts: Dictionary) -> Dictionary:
	var total: int = 0
	for id: String in ids: total += int(counts.get(id, 0))
	if total <= MAX_SEGMENTS: return counts.duplicate()
	var quotas: Dictionary = {}
	var remaining: int = MAX_SEGMENTS
	var share: int = floori(float(MAX_SEGMENTS) / float(ids.size()))
	for id: String in ids:
		quotas[id] = mini(int(counts.get(id, 0)), share)
		remaining -= int(quotas[id])
	while remaining > 0:
		for id: String in ids:
			if int(quotas[id]) < int(counts.get(id, 0)):
				quotas[id] += 1
				remaining -= 1
				if remaining == 0: break
	return quotas

static func _paths(data: Dictionary, ids: Array, summary: Dictionary, quotas: Dictionary) -> Array:
	var rows: Dictionary = {}
	for id: String in ids:
		if summary.initial.has(id): rows[id] = {"unit_id":id, "points":[summary.initial[id]], "segments":[]}
	var previous: Dictionary = {}
	var ordinal: Dictionary = {}
	var previous_time: float = -1.0
	for index: int in range(mini(data.frames.size(), MAX_FRAMES)):
		var frame: Variant = data.frames[index]
		if not _frame_valid(frame, previous_time):
			previous.clear()
			continue
		previous_time = float(frame[0])
		var current: Dictionary = _own_rows(frame, data.states, ids)
		for id: String in ids:
			if not current.has(id): continue
			var point: Dictionary = _point(current[id], frame)
			if previous.has(id) and _moved(previous[id].point, point):
				var edge: int = int(ordinal.get(id, 0))
				var count: int = int(summary.counts.get(id, 0))
				var quota: int = int(quotas.get(id, 0))
				# Select evenly across the whole record, but preserve both ends
				# of each selected original edge as a separate index pair.
				if quota > 0 and floori(float(edge + 1) * quota / count) > floori(float(edge) * quota / count):
					_append_edge(rows[id], previous[id].point, point)
				ordinal[id] = edge + 1
			current[id] = {"point":point}
		previous = current
	var paths: Array = []
	for id: String in ids:
		if rows.has(id): paths.append(rows[id])
	return paths

static func _append_edge(path: Dictionary, start: Dictionary, finish: Dictionary) -> void:
	var first: int = path.points.size() - 1
	if path.points[first] != start:
		first = path.points.size()
		path.points.append(start)
	var last: int = path.points.size()
	path.points.append(finish)
	path.segments.append([first, last])

static func _point(row: Dictionary, frame: Array) -> Dictionary:
	return {"x":row.x, "z":row.z, "base_height":row.base_height, "tick":int(frame[1]), "time":float(frame[0])}

static func _moved(first: Dictionary, second: Dictionary) -> bool:
	return first.x != second.x or first.z != second.z or first.base_height != second.base_height

static func _frame_valid(frame: Variant, previous_time: float) -> bool:
	return frame is Array and frame.size() >= 3 and _number(frame[0]) and float(frame[0]) >= 0.0 and float(frame[0]) > previous_time and _integer(frame[1]) and float(frame[1]) >= 0.0

static func _own_rows(frame: Array, states: Array, ids: Array) -> Dictionary:
	var packed: Variant = frame[2] # Never read enemy/civilian/door groups or metadata.
	if not (packed is Array or packed is PackedFloat64Array) or packed.size() > MAX_PACKED_VALUES: return {}
	var found: Dictionary = {}
	var duplicates: Dictionary = {}
	var cursor: int = 0
	var rows: int = 0
	while cursor < packed.size() and rows < MAX_UNITS:
		if not _integer(packed[cursor]): return {}
		var length: int = int(packed[cursor])
		cursor += 1
		if length < 1 or cursor + length > packed.size() or not _integer(packed[cursor]): return {}
		var state_index: int = int(packed[cursor])
		if state_index < 0 or state_index >= states.size(): return {}
		var definition: Variant = states[state_index]
		if not definition is Dictionary or definition.get("group", "") != "units": return {}
		var base: Variant = definition.get("base")
		var fields: Variant = definition.get("fields")
		if not base is Dictionary or not fields is Array or fields.size() > MAX_FIELDS or fields.size() + 1 > length: return {}
		var id: Variant = base.get("id")
		if id is String and ids.has(id) and base.get("kind", "unit") == "unit":
			var sample := {"base_height":base.get("base_height", 0.0)}
			for field: String in ["x", "z", "hp"]:
				if base.has(field): sample[field] = base[field]
			var seen: Dictionary = {}
			for field_index: int in range(fields.size()):
				var field: Variant = fields[field_index]
				if field in ["x", "z", "hp", "base_height"]:
					if seen.has(field): return {}
					seen[field] = true
					sample[field] = packed[cursor + 1 + field_index]
			if sample.has("x") and sample.has("z") and sample.has("hp") and sample.values().all(func(value: Variant) -> bool: return _number(value)):
				if found.has(id): duplicates[id] = true
				found[id] = sample
		cursor += length
		rows += 1
	if cursor != packed.size(): return {}
	for id: String in duplicates: found.erase(id)
	return found

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))
