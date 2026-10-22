class_name BreachPresentationState
extends RefCounted
## One-tick interpolation of observations, never of hidden simulation data.
## The authoritative state/time stays untouched. presentation_time is shared by
## skeletal animation, effects and sound so events cannot run ahead of the image.

const Replay = preload("res://scripts/replay.gd")
const STEP: float = 1.0 / 30.0
const EPSILON: float = 0.000001
const TELEPORT_DISTANCE: float = 2.0
const GROUPS: Array[String] = ["units", "enemies", "civilians", "doors"]

var _previous: Dictionary = {}
var _current: Dictionary = {}
var _pending_events: Array = []
var _last_pending_seq: int = -1
var _previous_ids: Dictionary = {}
var _ids_dirty: bool = true

func reset(observation: Dictionary) -> void:
	_current = _own_room_doctrine(observation)
	_previous = _current
	_pending_events.clear()
	_last_pending_seq = -1
	_ids_dirty = true

func capture(observation: Dictionary, new_events: Variant = null) -> void:
	var next_time: float = float(observation.get("time", 0.0))
	var current_time: float = float(_current.get("time", 0.0))
	# Rewinds, mission changes and skipped observations must never blend across
	# unrelated state. A slow render frame still captures each simulation tick.
	if _current.is_empty() or next_time <= current_time + EPSILON or next_time - current_time > STEP + EPSILON:
		reset(observation)
	else:
		_previous = _current
		_current = _own_room_doctrine(observation)
		_ids_dirty = true
	queue_events(observation.get("events", []) if new_events == null else new_events)

func queue_events(events: Array) -> void:
	for event: Dictionary in events:
		var seq := int(event.get("seq", 0))
		if seq > _last_pending_seq:
			_pending_events.append(event)
			_last_pending_seq = seq

func settle(observation: Dictionary) -> Dictionary:
	var rendered: Dictionary = _own_room_doctrine(observation).duplicate(false)
	rendered["presentation_time"] = float(observation.get("time", 0.0))
	if not _pending_events.is_empty():
		var by_seq: Dictionary = {}
		for event: Dictionary in _pending_events + observation.get("events", []):
			by_seq[int(event.get("seq", 0))] = event
		var sequences := by_seq.keys()
		sequences.sort()
		var events: Array = []
		for seq: int in sequences: events.append(by_seq[seq])
		rendered["presentation_events"] = events
	reset(observation)
	return rendered

func sample(fraction: float) -> Dictionary:
	if _current.is_empty():
		return {}
	var weight: float = clampf(fraction, 0.0, 1.0)
	var previous_time: float = float(_previous.get("time", 0.0))
	var current_time: float = float(_current.get("time", 0.0))
	var clock: float = lerpf(previous_time, current_time, weight)
	var rendered: Dictionary = _own_room_doctrine(_current).duplicate(false)
	rendered["presentation_time"] = clock
	if _ids_dirty:
		_previous_ids.clear()
		for group: String in GROUPS:
			var by_id: Dictionary = {}
			for entity: Dictionary in _previous.get(group, []): by_id[str(entity.get("id", ""))] = entity
			_previous_ids[group] = by_id
		_ids_dirty = false
	for group: String in GROUPS:
		rendered[group] = _sample_group(_current.get(group, []), weight, group)
	# Discrete feedback follows the same clock as movement and animation. Keep
	# original IDs/timestamps, allowing the ordinary event cursor to deduplicate.
	var events: Array = []
	for event: Dictionary in _current.get("events", []):
		if float(event.get("time", 0.0)) <= clock + EPSILON:
			events.append(event)
	var projectiles: Array = _current.get("flash_projectiles", [])
	if weight < 1.0:
		projectiles = _previous.get("flash_projectiles", []).duplicate()
		var ids: Dictionary = {}
		for projectile: Dictionary in projectiles: ids[str(projectile.get("id", ""))] = true
		for projectile: Dictionary in _current.get("flash_projectiles", []):
			if not ids.has(str(projectile.get("id", ""))) and float(projectile.get("released_at", current_time)) <= clock + EPSILON: projectiles.append(projectile)
	rendered["flash_projectiles"] = Replay.sample_flash_projectiles(projectiles, clock)
	if _current.has("frag_projectiles") or _previous.has("frag_projectiles"):
		var fragments: Array = _current.get("frag_projectiles", [])
		if weight < 1.0:
			fragments = _previous.get("frag_projectiles", []).duplicate()
			var fragment_ids: Dictionary = {}
			for projectile: Dictionary in fragments: fragment_ids[str(projectile.get("id", ""))] = true
			for projectile: Dictionary in _current.get("frag_projectiles", []):
				if not fragment_ids.has(str(projectile.get("id", ""))) and float(projectile.get("released_at", current_time)) <= clock + EPSILON: fragments.append(projectile)
		rendered["frag_projectiles"] = Replay.sample_frag_projectiles(fragments, clock)
	rendered["events"] = events
	var ready: Array = []
	var waiting: Array = []
	for event: Dictionary in _pending_events:
		if float(event.get("time", 0.0)) <= clock + EPSILON:
			ready.append(event)
		else:
			waiting.append(event)
	_pending_events = waiting
	rendered["presentation_events"] = ready
	if weight < 1.0:
		rendered["sound_zones"] = _previous.get("sound_zones", [])
		if _current.has("room_doctrine"):
			if _previous.has("room_doctrine"):
				rendered.room_doctrine = _previous.room_doctrine.duplicate(true)
			else:
				rendered.erase("room_doctrine")
		if rendered.get("result", {}).has("room_doctrine"):
			var doctrine_result: Dictionary = rendered.result.duplicate(false)
			if _previous.get("result", {}).has("room_doctrine"):
				doctrine_result.room_doctrine = _previous.result.room_doctrine.duplicate(true)
			else:
				doctrine_result.erase("room_doctrine")
			rendered.result = doctrine_result
		# Room control is discrete, like death. Never render next-tick CLEAR
		# while movement and the CALL event still use the previous tick.
		for key: String in ["room_states", "room_states_observed"]:
			if _current.has(key): rendered[key] = _previous.get(key, {}).duplicate(true)
		var current_result: Dictionary = rendered.get("result", {})
		if current_result.has("room_states"):
			var result: Dictionary = current_result.duplicate(true)
			result["room_states"] = _previous.get("result", {}).get("room_states", {}).duplicate(true)
			if result.has("room_states_observed"):
				result["room_states_observed"] = _previous.get("result", {}).get("room_states_observed", {}).duplicate(true)
			rendered["result"] = result
	return rendered

static func _own_room_doctrine(observation: Dictionary) -> Dictionary:
	var top_present: bool = observation.get("room_doctrine") is Dictionary
	var result_present: bool = observation.get("result", {}).get("room_doctrine") is Dictionary
	if not top_present and not result_present: return observation
	var owned: Dictionary = observation.duplicate(false)
	if top_present: owned.room_doctrine = observation.room_doctrine.duplicate(true)
	if result_present:
		owned.result = observation.result.duplicate(false)
		owned.result.room_doctrine = observation.result.room_doctrine.duplicate(true)
	return owned

func _sample_group(current: Array, weight: float, group: String) -> Array:
	var by_id: Dictionary = _previous_ids[group]
	var result: Array = []
	# Iterate the current observation only: disappeared actors cannot linger,
	# and a last-seen marker is never moved toward a hidden true position.
	for next: Dictionary in current:
		var before: Dictionary = by_id.get(str(next.get("id", "")), {})
		if not _can_blend(before, next, group) or weight >= 1.0:
			result.append(next.duplicate(false))
			continue
		# HP/status change when their event enters the presentation timeline,
		# avoiding a dead body appearing one frame before the impact itself.
		var entity: Dictionary = before.duplicate(false)
		for axis: String in ["x", "z", "progress", "travel_distance"]:
			if before.has(axis) and next.has(axis):
				entity[axis] = lerpf(float(before[axis]), float(next[axis]), weight)
		for angle: String in ["facing", "aim_facing", "move_facing", "body_facing"]:
			if before.has(angle) and next.has(angle):
				entity[angle] = lerp_angle(float(before[angle]), float(next[angle]), weight)
		# Queued plans are immediate input feedback, not animated gameplay state.
		if next.has("commands"):
			entity["commands"] = next.commands
		result.append(entity)
	return result

func _can_blend(before: Dictionary, next: Dictionary, group: String) -> bool:
	if before.is_empty():
		return false
	if group in ["enemies", "civilians"]:
		if not bool(before.get("visible", false)) or not bool(next.get("visible", false)):
			return false
	if before.has("x") and next.has("x") and before.has("z") and next.has("z"):
		var origin := Vector2(float(before.x), float(before.z))
		var destination := Vector2(float(next.x), float(next.z))
		if origin.distance_to(destination) > TELEPORT_DISTANCE:
			return false
	return true
