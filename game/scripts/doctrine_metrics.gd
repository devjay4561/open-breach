extends RefCounted
## Passive fixed-step instrumentation. Never consumes a gameplay RNG.
const DoorGeometry = preload("res://scripts/door_geometry.gd")
const RoomDoctrine = preload("res://scripts/room_doctrine.gd")
var _room_doctrine: RefCounted = RoomDoctrine.new()
var doorway_dwell: Dictionary = {}
var time_to_dominate: Dictionary = {}
var enemy_first_shot: Array = []
var threat_order_violations: int = 0
var rear_hits: int = 0
var evidence: Array = []
var _door_open: Dictionary = {}
var _engagements: Dictionary = {}

func reset(mission: Dictionary = {}) -> void:
	doorway_dwell.clear()
	time_to_dominate.clear()
	enemy_first_shot.clear()
	evidence.clear()
	_door_open.clear()
	_engagements.clear()
	threat_order_violations = 0
	rear_hits = 0
	_room_doctrine.reset(mission)

func record_room_stack(context: Dictionary) -> void:
	_room_doctrine.record_stack(context)

func record_room_observation(fact: Dictionary) -> void:
	_room_doctrine.record_observation(fact)

func record_room_damage(fact: Dictionary) -> void:
	_room_doctrine.record_damage(fact)

func record_room_control(fact: Dictionary) -> void:
	_room_doctrine.record_control(fact)

func record_room_unlawful(fact: Dictionary) -> void:
	_room_doctrine.record_unlawful(fact)

func update_room_doctrine(sim: RefCounted, dt: float) -> void:
	_room_doctrine.update(sim, dt)

func room_at(sim: RefCounted, position: Vector2) -> String:
	for room: Dictionary in sim.mission.get("rooms", []):
		if Rect2(sim._position(room) - Vector2(float(room.w), float(room.d)) * 0.5, Vector2(float(room.w), float(room.d))).has_point(position):
			return str(room.id)
	return ""

func update(sim: RefCounted, dt: float) -> void:
	for unit: Dictionary in sim.units:
		if not doorway_dwell.has(unit.id): doorway_dwell[unit.id] = 0.0
		if float(unit.hp) <= 0.0: continue
		for door: Dictionary in sim.doors:
			if DoorGeometry.funnel_rect(door).has_point(sim._position(unit)):
				doorway_dwell[unit.id] += dt
	for door: Dictionary in sim.doors:
		var opened: bool = str(door.state) == "OPEN"
		if opened and not bool(_door_open.get(door.id, opened if sim.tick <= 1 else false)):
			_begin_entry(sim, door)
		_door_open[door.id] = opened
		if not time_to_dominate.has(door.id): continue
		var entry: Dictionary = time_to_dominate[door.id]
		var observation: Dictionary = sim._door_observations.get(str(door.id), {})
		if observation.get("state", "") == "OPEN" and float(observation.get("_observed_at", -1.0)) >= float(entry.opened_at): entry["observed"] = true
		if float(entry.seconds) >= 0.0: continue
		for id: String in entry.participants:
			if entry.arrived.has(id): continue
			var unit: Dictionary = sim._find(sim.units, id)
			if unit.is_empty() or float(unit.hp) <= 0.0: continue
			if entry.has("targets"):
				if sim._position(unit).distance_to(sim._point(entry.targets[id])) <= 0.1: entry.arrived.append(id)
				continue
			var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
			if room_at(sim, sim._position(unit)) == entry.room_id and absf((sim._position(unit) - sim._position(door)).dot(normal)) >= 1.0:
				entry.arrived.append(id)
		if not entry.participants.is_empty() and entry.arrived.size() == entry.participants.size():
			entry.seconds = sim.time - float(entry.opened_at)
			_add_evidence(sim, "DOMINATED", entry.room_id, {"door_id":door.id, "seconds":entry.seconds})

func _begin_entry(sim: RefCounted, door: Dictionary) -> void:
	if _begin_drill_entry(sim, door): return
	var entries: Dictionary = {}
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var adjacent: Array = [room_at(sim, sim._position(door) - normal * 0.65), room_at(sim, sim._position(door) + normal * 0.65)]
	for unit: Dictionary in sim.units:
		var projected_origin: Vector2 = sim._position(unit)
		for command: Dictionary in unit.commands:
			if command.state in ["SUCCEEDED", "CANCELLED"]: continue
			# Failed orders block the queue; later previews cannot represent a
			# currently executable entry until that failure is edited away.
			if command.state == "FAILED": break
			var route: Array = command.get("path", [])
			if bool(command.get("_started", false)) or command.state in ["RUNNING", "WAITING"]:
				# A yielded MOVE retains its cursor too. Passed waypoints must
				# never be joined back to the actor's live position.
				route = route.slice(clampi(int(command.get("path_cursor", 0)), 0, route.size()))
			if command.type == "MOVE":
				if route.is_empty(): break
				var destination: Vector2 = sim._point(command.args.target)
				var room_id: String = room_at(sim, destination)
				var crosses_plane: bool = (destination - sim._position(door)).dot(normal) * (projected_origin - sim._position(door)).dot(normal) < 0.0
				if not room_id.is_empty() and adjacent.has(room_id) and room_at(sim, projected_origin) != room_id and crosses_plane and _route_crosses_door(sim, projected_origin, route, door):
					if not entries.has(room_id): entries[room_id] = []
					if not entries[room_id].has(unit.id): entries[room_id].append(unit.id)
					break
			# Each future path was previewed from the preceding order's end,
			# including approaches to doors and protected people, not from
			# the unit's position at the moment a distant door opens.
			if not route.is_empty(): projected_origin = sim._point(route.back())
	if entries.is_empty(): return
	var room_ids: Array = entries.keys()
	room_ids.sort()
	var room_id: String = str(room_ids[0])
	time_to_dominate[door.id] = {"room_id":room_id, "opened_at":sim.time, "participants":entries[room_id], "arrived":[], "seconds":-1.0, "observed":false}

func _begin_drill_entry(sim: RefCounted, door: Dictionary) -> bool:
	var groups: Dictionary = {}
	for unit: Dictionary in sim.units:
		for command: Dictionary in unit.commands:
			var drill: Dictionary = command.args.get("drill", {})
			if str(drill.get("door_id", "")) != str(door.id) or command.type != "MOVE" or str(drill.get("stage", "")) not in ["entry", "domination"] or command.state == "CANCELLED": continue
			var base := str(drill.sync_id)
			if not groups.has(base): groups[base] = {"room_id": str(drill.room_id), "targets": {}, "participants": []}
			groups[base].targets[unit.id] = command.args.target.duplicate()
			if not groups[base].participants.has(str(unit.id)): groups[base].participants.append(str(unit.id))
	if groups.is_empty(): return false
	var ids: Array = groups.keys()
	ids.sort()
	var selected: Dictionary = groups[ids[0]]
	time_to_dominate[door.id] = {"room_id": selected.room_id, "opened_at": sim.time, "participants": selected.participants, "arrived": [], "seconds": -1.0, "observed": false, "targets": selected.targets}
	return true

func _route_crosses_door(sim: RefCounted, origin: Vector2, route: Array, door: Dictionary) -> bool:
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var across := Vector2.RIGHT if door.get("axis", "x") == "x" else Vector2.DOWN
	var center: Vector2 = sim._position(door)
	for raw: Array in route:
		var endpoint: Vector2 = sim._point(raw)
		var from_depth: float = (origin - center).dot(normal)
		var to_depth: float = (endpoint - center).dot(normal)
		if from_depth * to_depth <= 0.0 and absf(from_depth - to_depth) > 0.000001:
			var crossing: Vector2 = origin.lerp(endpoint, from_depth / (from_depth - to_depth))
			if absf((crossing - center).dot(across)) <= DoorGeometry.width(door) * 0.5: return true
		origin = endpoint
	return false

func aiming_at(sim: RefCounted, enemy: Dictionary, unit: Dictionary) -> bool:
	return str(enemy.get("aim_state", "idle")) == "ready" and int(enemy.get("ammo", 0)) > 0 and sim._can_act(enemy) and absf(angle_difference(float(enemy.get("aim_facing", enemy.facing)), (sim._position(unit) - sim._position(enemy)).angle())) <= PI / 12.0

func record_shot(sim: RefCounted, attacker: Dictionary, target: Dictionary, hostile: bool, hit: bool) -> void:
	var room_id: String = room_at(sim, sim._position(target if hostile else attacker))
	var key: String = room_id if not room_id.is_empty() else "exterior"
	var prior: Dictionary = _engagements.get(key, {})
	if prior.is_empty() or sim.time - float(prior.time) >= 3.0:
		enemy_first_shot.append({"room_id":room_id, "time":sim.time, "tick":sim.tick, "enemy_first":hostile})
	_engagements[key] = {"time":sim.time}
	if not hostile and not aiming_at(sim, target, attacker):
		for enemy: Dictionary in sim.enemies:
			if enemy.id != target.id and sim.observation_ready(attacker, enemy) and sim._can_engage_target(attacker, enemy, false) and sim._position(attacker).distance_to(sim._position(enemy)) <= sim._effective_weapon_range(attacker) and aiming_at(sim, enemy, attacker):
				threat_order_violations += 1
				_room_doctrine.record_threat(sim, attacker)
				_add_evidence(sim, "THREAT_ORDER", room_id, {"unit_id":attacker.id, "target_id":target.id, "ready_enemy_id":enemy.id})
				break
	if hostile and hit and target.get("kind", "") == "unit":
		var bearing: float = (sim._position(attacker) - sim._position(target)).angle()
		if absf(angle_difference(float(target.get("body_facing", target.facing)) + PI, bearing)) <= PI / 4.0:
			rear_hits += 1
			_room_doctrine.record_rear_hit(sim, target)
			_add_evidence(sim, "REAR_HIT", room_id, {"unit_id":target.id})

func _add_evidence(sim: RefCounted, kind: String, room_id: String, extra: Dictionary) -> void:
	var item: Dictionary = {"type":kind, "room_id":room_id, "time":sim.time, "tick":sim.tick}
	item.merge(extra)
	evidence.append(item)

func statistics() -> Dictionary:
	var stats := {"doorway_dwell":doorway_dwell.duplicate(true), "time_to_dominate":time_to_dominate.duplicate(true), "enemy_first_shot":enemy_first_shot.duplicate(true), "threat_order_violations":threat_order_violations, "rear_hits":rear_hits}
	if _room_doctrine.initialized: stats["room_doctrine"] = _room_doctrine.snapshot()
	return stats

static func observed_entries(entries: Dictionary) -> Dictionary:
	var known: Dictionary = {}
	for id: String in entries:
		if bool(entries[id].get("observed", false)): known[id] = entries[id].duplicate(true)
	return known

static func filter_observed_statistics(state: Dictionary) -> void:
	if state.get("room_doctrine") is Dictionary:
		state["room_doctrine"] = state.room_doctrine.duplicate(true)
	if state.get("result",{}).get("room_doctrine") is Dictionary:
		state["result"] = state.result.duplicate(false)
		state.result["room_doctrine"] = state.result.room_doctrine.duplicate(true)
	if state.has("time_to_dominate"):
		state["time_to_dominate"] = observed_entries(state.time_to_dominate)
	if state.get("result", {}).has("time_to_dominate"):
		# Paired snapshots share their common data. Keep the recording owned
		# result intact when filtering the copy sent to the player.
		state["result"] = state.result.duplicate(false)
		state.result["time_to_dominate"] = observed_entries(state.result.time_to_dominate)
	# P5 records retain authoritative outcomes separately from occurrence-time
	# observations. Filtering a shallow paired snapshot must never edit the
	# recorder's nested objectives, result, or star maps.
	var observed: Dictionary = state.get("stats_observed", {})
	if not observed.is_empty():
		_project_known_counters(state, observed)
		if state.get("objectives") is Dictionary:
			state["objectives"] = state.objectives.duplicate(false)
			for key: String in ["neutralized", "rescued"]:
				if state.objectives.has(key): state.objectives[key] = observed[key]
	state.erase("stats_observed")
	var result: Dictionary = state.get("result", {})
	if result.has("stats_observed") or result.has("stars_observed"):
		result = result.duplicate(false)
		state["result"] = result
		var terminal_observed: Dictionary = result.get("stats_observed", observed)
		if not terminal_observed.is_empty():
			_project_known_counters(result, terminal_observed)
			var score: int = int(terminal_observed.score)
			result["rank"] = ("S" if score >= 95 else ("A" if score >= 80 else ("B" if score >= 65 else "C"))) if bool(result.get("success", false)) else "—"
		if result.has("stars_observed"):
			result["stars"] = result.stars_observed.duplicate(true)
		result.erase("stats_observed")
		result.erase("stars_observed")

static func _project_known_counters(value: Dictionary, observed: Dictionary) -> void:
	for key: String in ["neutralized", "rescued", "kills", "arrests", "civilian_damage", "civilian_losses", "unlawful_shots", "score"]:
		if value.has(key): value[key] = observed[key]
