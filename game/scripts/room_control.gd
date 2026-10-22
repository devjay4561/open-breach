class_name BreachRoomControl
extends RefCounted
## Authoritative room control and a separate memory of owned observations.
## This helper never reads render frames, actors, navigation or random streams.
const Spatial = preload("res://scripts/spatial_profile.gd")
const Door = preload("res://scripts/door_geometry.gd")
const STATES: Array[String] = ["UNKNOWN", "CONTACT", "DOMINATED", "CLEAR", "MARKED"]
const CALL_TYPES: Array[String] = ["CALL_CLEAR", "CALL_ROOM_CLEAR", "CALL_SHORT_ROOM", "CALL_RELOADING", "CALL_GUN_UP", "CALL_MAN_DOWN"]
const SEARCH_SECONDS := 1.5
const EPSILON := 0.0001

var room_states: Dictionary = {}
var room_states_observed: Dictionary = {}
var _rooms: Array = []
var _room_index: Dictionary = {}
var _room_bounds: Dictionary = {}
var _door_index: Dictionary = {}
var _entries: Dictionary = {}
var _search: Dictionary = {}
var _clearers: Dictionary = {}
var _observed_clearers: Dictionary = {}
var _previous_units: Dictionary = {}
var _last_tick := -1
var _last_time := -1.0

func reset(mission: Dictionary) -> void:
	room_states = {}
	room_states_observed = {}
	_rooms = mission.get("rooms", []).duplicate(true)
	_room_index = {}
	_room_bounds = {}
	_door_index = {}
	_entries = {}
	_search = {}
	_clearers = {}
	_observed_clearers = {}
	_previous_units = {}
	_last_tick = -1
	_last_time = -1.0
	for room: Dictionary in _rooms:
		var id := str(room.get("id", ""))
		if id.is_empty(): continue
		_room_index[id] = room
		_room_bounds[id] = _rect(room)
		room_states[id] = {"state":"UNKNOWN", "changed_tick":0, "changed_at":0.0, "observed":false}
		room_states_observed[id] = room_states[id].duplicate(true)
	for door: Dictionary in mission.get("doors", []):
		_door_index[str(door.get("id", ""))] = door.duplicate(true)

func room_at(point: Variant, floor_height: float = NAN) -> String:
	var location := _point(point)
	if not _finite(location): return ""
	var floor := Spatial.floor_base_at(_rooms, location) if is_nan(floor_height) else floor_height
	var best: Dictionary = {}
	for room: Dictionary in _rooms:
		if not _room_bounds[str(room.id)].has_point(location) or absf(float(room.get("base_height", 0.0)) - floor) > EPSILON: continue
		if best.is_empty() or _room_before(room, best): best = room
	return str(best.get("id", ""))

func register_entry(contract: Dictionary) -> void:
	var room_id := str(contract.get("room_id", ""))
	var door_id := str(contract.get("door_id", ""))
	if not _room_index.has(room_id) or not _door_index.has(door_id): return
	var participants: Variant = contract.get("participants", [])
	var targets: Variant = contract.get("targets", {})
	if not participants is Array or participants.is_empty() or participants.size() > 4 or not targets is Dictionary: return
	var ids: Array[String] = []
	var goals: Dictionary = {}
	for value: Variant in participants:
		if not value is String or str(value).is_empty() or ids.has(str(value)): return
		var target := _point(targets.get(value))
		# Edited primitive goals may deliberately lie outside the draft room.
		# Keep the entry contract so such a plan cannot silently fall back to
		# manual dominance; arrival still requires the actor to be in this room.
		if not _finite(target): return
		ids.append(str(value))
		goals[str(value)] = [target.x, target.y]
	var entry := {"sync_id":str(contract.get("sync_id", "")), "door_id":door_id, "room_id":room_id, "participants":ids, "targets":goals}
	var previous: Dictionary = _entries.get(room_id, {})
	if not previous.is_empty() and previous.get("contract", {}) == entry: return
	_entries[room_id] = {"contract":entry, "pending":true}
	_search.erase(room_id)

func tick(context: Dictionary) -> Dictionary:
	var output := {"private_transitions":[], "public_transitions":[]}
	var step_tick := int(context.get("tick", -1))
	var step_time := float(context.get("time", -1.0))
	var dt := float(context.get("dt", 0.0))
	if step_tick <= _last_tick or step_tick < 0 or not is_finite(step_time) or step_time < 0.0 or step_time <= _last_time or not is_finite(dt) or dt <= 0.0 or dt > 0.1 + EPSILON: return output
	if _last_tick >= 0 and step_tick != _last_tick + 1: _search.clear()
	_last_tick = step_tick
	_last_time = step_time
	for update: Dictionary in context.get("entry_updates", []): register_entry(update)
	var units: Dictionary = {}
	var units_by_room: Dictionary = {}
	for source: Dictionary in context.get("units", []):
		var unit := source.duplicate(true)
		var id := str(unit.get("id", ""))
		if id.is_empty() or not _finite(_point(unit.get("position"))): continue
		unit["room_id"] = _actor_room(unit)
		units[id] = unit
		if not units_by_room.has(unit.room_id): units_by_room[unit.room_id] = []
		units_by_room[unit.room_id].append(id)
	for room_id: String in units_by_room: units_by_room[room_id].sort()
	var blocked: Dictionary = {}
	for enemy: Dictionary in context.get("enemies", []):
		var room_id := _actor_room(enemy)
		# A surrendered corpse is not a substitute for an arrest. The control
		# predicates deliberately do not use alive or the action predicate.
		if bool(enemy.get("can_act", false)) or (bool(enemy.get("surrendered", false)) and not bool(enemy.get("arrested", false))): blocked[room_id] = true
	for civilian: Dictionary in context.get("civilians", []):
		if not bool(civilian.get("secured", false)): blocked[_actor_room(civilian)] = true
	var contacts: Dictionary = {}
	for contact: Dictionary in context.get("contacts", []):
		var room_id := str(contact.get("room_id", ""))
		if _room_index.has(room_id): contacts[room_id] = true
	var observation: Dictionary = context.get("observation", {})
	var ordered: Array = room_states.keys()
	ordered.sort()
	for room_id: String in ordered:
		var old_state := str(room_states[room_id].state)
		var owned_observation := _observed_room(observation.get(room_id, {}))
		var owned_unit := _eligible_unit(room_id, units, units_by_room)
		var entry: Dictionary = _entries.get(room_id, {})
		var entry_pending := bool(entry.get("pending", false))
		var arrived := not entry.is_empty() and _entry_arrived(room_id, entry.contract, units)
		var dominated := arrived if entry_pending else (arrived or (not owned_unit.is_empty() and owned_observation))
		var domination_unit := str(entry.get("contract", {}).get("participants", [""])[0]) if arrived else owned_unit
		var public_state := str(room_states_observed[room_id].state)
		# Repeated sight of a stunned/arrested person does not undo a lawful
		# clearance. A known cleared room needs actual recontamination as well
		# as owned contact evidence before its memory can regress.
		var fresh_contact := bool(contacts.get(room_id, false)) and (public_state == "UNKNOWN" or (public_state in ["CLEAR", "MARKED"] and bool(blocked.get(room_id, false))))
		var clear_unit := ""
		var marked_door := ""
		# An owned CLEAR declaration records who will mark its exit. Hidden
		# recontamination can invalidate authority without changing that memory.
		var observed_clearer := str(_observed_clearers.get(room_id, ""))
		var observed_exit := _clearer_exit(room_id, observed_clearer, context.get("exits", []), units) if public_state == "CLEAR" and not fresh_contact else ""
		# Recontamination and interrupted search win over every lower phase.
		if bool(blocked.get(room_id, false)) or owned_unit.is_empty() or entry_pending: _search.erase(room_id)
		if old_state in ["CLEAR", "MARKED"] and bool(blocked.get(room_id, false)):
			_clearers.erase(room_id)
			_change_private(room_id, "CONTACT", step_tick, step_time, output)
		elif old_state == "UNKNOWN" and bool(contacts.get(room_id, false)):
			_search.erase(room_id)
			_change_private(room_id, "CONTACT", step_tick, step_time, output)
		elif old_state in ["UNKNOWN", "CONTACT"]:
			if dominated and not fresh_contact:
				if entry_pending: _entries[room_id]["pending"] = false
				_search.erase(room_id)
				_change_private(room_id, "DOMINATED", step_tick, step_time, output)
		elif old_state == "DOMINATED":
			if entry_pending:
				if arrived: _entries[room_id]["pending"] = false
			elif not bool(blocked.get(room_id, false)) and not owned_unit.is_empty() and not fresh_contact:
				clear_unit = _search_step(room_id, owned_unit, dt, step_tick)
				if not clear_unit.is_empty():
					_clearers[room_id] = clear_unit
					_change_private(room_id, "CLEAR", step_tick, step_time, output)
		elif old_state == "CLEAR":
			marked_door = _clearer_exit(room_id, str(_clearers.get(room_id, "")), context.get("exits", []), units)
			if not marked_door.is_empty(): _change_private(room_id, "MARKED", step_tick, step_time, output, marked_door)
		# A completed search may have happened under smoke or poor lighting.
		# Its own living operator can declare it on a later fresh observation
		# while still inside; current CONTACT or an exit cannot donate evidence.
		var declaration_unit := clear_unit
		if declaration_unit.is_empty() and str(room_states[room_id].state) == "CLEAR":
			var prior_clearer := str(_clearers.get(room_id, ""))
			var clearer: Dictionary = units.get(prior_clearer, {})
			if bool(clearer.get("alive", false)) and str(clearer.get("room_id", "")) == room_id: declaration_unit = prior_clearer
		# Public memory follows evidence for this phase, never a raw row refresh.
		if fresh_contact:
			_search.erase(room_id)
			_publish(room_id, "CONTACT", step_tick, step_time, output)
		elif str(room_states[room_id].state) == "DOMINATED" and dominated and owned_observation and public_state in ["UNKNOWN", "CONTACT"]:
			_publish(room_id, "DOMINATED", step_tick, step_time, output, domination_unit)
		elif not declaration_unit.is_empty() and owned_observation and public_state in ["UNKNOWN", "CONTACT", "DOMINATED"]:
			_publish(room_id, "CLEAR", step_tick, step_time, output, declaration_unit)
		elif not observed_exit.is_empty() and public_state == "CLEAR":
			_publish(room_id, "MARKED", step_tick, step_time, output, observed_clearer, observed_exit)
	_previous_units = units.duplicate(true)
	return output

func _actor_room(actor: Dictionary) -> String:
	if actor.has("position"):
		return room_at(actor.position, float(actor.get("floor_height", NAN)))
	var room_id := str(actor.get("room_id", ""))
	return room_id if _room_index.has(room_id) else ""

func _eligible_unit(room_id: String, units: Dictionary, by_room: Dictionary) -> String:
	var prior := str(_search.get(room_id, {}).get("unit_id", ""))
	var ordered: Array = by_room.get(room_id, []).duplicate()
	if ordered.has(prior):
		ordered.erase(prior)
		ordered.push_front(prior)
	for id: String in ordered:
		var unit: Dictionary = units[id]
		if bool(unit.get("alive", false)) and bool(unit.get("can_act", false)) and bool(unit.get("search_eligible", false)): return id
	return ""

func _entry_arrived(room_id: String, entry: Dictionary, units: Dictionary) -> bool:
	for id: String in entry.participants:
		var unit: Dictionary = units.get(id, {})
		if unit.is_empty() or not bool(unit.get("alive", false)) or not bool(unit.get("can_act", false)) or str(unit.get("room_id", "")) != room_id: return false
		if _point(unit.get("position")).distance_to(_point(entry.targets[id])) > 0.1: return false
	return not entry.participants.is_empty()

func _search_step(room_id: String, unit_id: String, dt: float, step_tick: int) -> String:
	var search: Dictionary = _search.get(room_id, {})
	if str(search.get("unit_id", "")) != unit_id or int(search.get("tick", step_tick - 1)) != step_tick - 1:
		search = {"unit_id":unit_id, "elapsed":0.0}
	search["tick"] = step_tick
	search["elapsed"] = float(search.get("elapsed", 0.0)) + dt
	_search[room_id] = search
	return unit_id if float(search.elapsed) + 0.00000001 >= SEARCH_SECONDS else ""

func _clearer_exit(room_id: String, unit_id: String, exits: Array, units: Dictionary) -> String:
	var prior: Dictionary = _previous_units.get(unit_id, {})
	var current: Dictionary = units.get(unit_id, {})
	if prior.is_empty() or current.is_empty() or not bool(current.get("alive", false)) or str(prior.get("room_id", "")) != room_id or str(current.get("room_id", "")) == room_id: return ""
	for exit: Dictionary in exits:
		if str(exit.get("unit_id", "")) != unit_id or str(exit.get("room_id", "")) != room_id: continue
		var door_id := str(exit.get("door_id", ""))
		var door: Dictionary = _door_index.get(door_id, {})
		if door.is_empty(): continue
		var height := float(door.get("base_height", 0.0))
		if absf(float(prior.get("floor_height", height)) - height) > EPSILON or absf(float(current.get("floor_height", height)) - height) > EPSILON: continue
		var normal := Vector2.DOWN if str(door.get("axis", "x")) == "x" else Vector2.RIGHT
		var across := Vector2.RIGHT if str(door.get("axis", "x")) == "x" else Vector2.DOWN
		var center := Vector2(float(door.x), float(door.z))
		if not _room_bounds[room_id].grow(0.65).has_point(center): continue
		var before := _point(prior.get("position"))
		var after := _point(current.get("position"))
		var a := (before - center).dot(normal)
		var b := (after - center).dot(normal)
		if a * b > 0.0 or absf(a - b) <= EPSILON: continue
		var crossing := before.lerp(after, a / (a - b))
		if absf((crossing - center).dot(across)) <= Door.width(door) * 0.5 + EPSILON: return door_id
	return ""

func _change_private(room_id: String, state: String, step_tick: int, step_time: float, output: Dictionary, door_id: String = "") -> void:
	var row := {"state":state, "changed_tick":step_tick, "changed_at":step_time, "observed":false}
	if state == "MARKED": row["door_id"] = door_id
	room_states[room_id] = row
	output.private_transitions.append({"room_id":room_id, "state":state})

func _publish(room_id: String, state: String, step_tick: int, step_time: float, output: Dictionary, unit_id: String = "", door_id: String = "") -> void:
	if str(room_states_observed[room_id].state) == state: return
	if state == "CONTACT": _observed_clearers.erase(room_id)
	elif state == "CLEAR": _observed_clearers[room_id] = unit_id
	var row := {"state":state, "changed_tick":step_tick, "changed_at":step_time, "observed":true}
	if state == "MARKED": row["door_id"] = door_id
	room_states_observed[room_id] = row
	if str(room_states[room_id].state) == state: room_states[room_id]["observed"] = true
	var transition := row.duplicate(true)
	transition["room_id"] = room_id
	if not unit_id.is_empty(): transition["unit_id"] = unit_id
	output.public_transitions.append(transition)

static func _observed_room(observation: Dictionary) -> bool:
	var current := bool(observation.get("current", false)) or bool(observation.get("center", false))
	return current and (bool(observation.get("center", false)) or float(observation.get("fraction", 0.0)) >= 0.6)

func snapshot(reveal: bool = false) -> Dictionary:
	return room_states.duplicate(true) if reveal else room_states_observed.duplicate(true)

func cleared(room_ids: Array) -> bool:
	if room_ids.is_empty(): return false
	for room_id: Variant in room_ids:
		if str(room_states.get(str(room_id), {}).get("state", "UNKNOWN")) not in ["CLEAR", "MARKED"]: return false
	return true

static func project_observed_state(state: Dictionary) -> void:
	var memory: Variant = state.get("room_states_observed", {})
	state["room_states"] = memory.duplicate(true) if memory is Dictionary else {}
	state.erase("room_states_observed")
	if state.get("result") is Dictionary and not state.result.is_empty() and (state.result.has("room_states") or state.result.has("room_states_observed")):
		var result: Dictionary = state.result.duplicate(false)
		var result_memory: Variant = result.get("room_states_observed", {})
		result["room_states"] = result_memory.duplicate(true) if result_memory is Dictionary else {}
		result.erase("room_states_observed")
		state["result"] = result

static func filter_observed_call_events(events: Array) -> Array:
	var filtered: Array = []
	for event: Variant in events:
		if not event is Dictionary: continue
		if str(event.get("type", "")) in CALL_TYPES and (not event.get("observed", false) is bool or not bool(event.get("observed", false))): continue
		filtered.append(event.duplicate(true))
	return filtered

static func _point(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int): return Vector2(float(value[0]), float(value[1]))
	return Vector2(INF, INF)

static func _finite(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y)

static func _rect(room: Dictionary) -> Rect2:
	return Rect2(Vector2(float(room.x) - float(room.w) * 0.5, float(room.z) - float(room.d) * 0.5), Vector2(float(room.w), float(room.d)))

static func _room_before(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.get("indoor", true)) != bool(b.get("indoor", true)): return bool(a.get("indoor", true))
	var aa := float(a.w) * float(a.d)
	var ba := float(b.w) * float(b.d)
	if not is_equal_approx(aa, ba): return aa < ba
	return str(a.get("id", "")) < str(b.get("id", ""))
