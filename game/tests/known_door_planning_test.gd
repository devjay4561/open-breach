extends SceneTree
## Known leaves on an entry route use observation snapshots, never live state.
const Simulation = preload("res://scripts/simulation.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Navigation = preload("res://scripts/navigation.gd")
const STEP := 1.0 / 30.0
const ORDER: Array[String] = ["alpha", "bravo", "charlie", "delta"]
const POSE_KEYS: Array[String] = ["state", "progress", "destroyed", "hp", "locked", "hinge_side", "swing_sign"]
const PRIMITIVES: Array[String] = ["MOVE", "FACE", "WAIT", "OPEN_DOOR", "KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "OPEN_AND_FLASH", "PEEK_CAMERA", "SWITCH_WEAPON", "RELOAD", "THROW_STUN", "THROW_SMOKE", "THROW_FRAG", "WAIT_FOR_SIGNAL", "SECURE_CIVILIAN", "ARREST", "CANCEL_PENDING"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture(route_portal: bool = false) -> Dictionary:
	var positions: Array = [[9.3, 10.95], [6.7, 10.95], [9.3, 11.65], [6.7, 11.65]]
	# Keep the prior opened leaf clear of all four next-door stack stations.
	# A 2.4m separation correctly rejects entry; this valid route uses 3.6m.
	if route_portal: positions = [[9.3, 14.9], [6.7, 14.9], [9.3, 15.6], [6.7, 15.6]]
	var units: Array = []
	for index: int in range(4):
		var origin := Vector2(float(positions[index][0]), float(positions[index][1]))
		units.append({"id":ORDER[index], "x":origin.x, "z":origin.y,
			"facing":(Vector2(8.0, 10.5) - origin).angle(), "weapon":"standard", "reserve_ammo":72, "breaches":2, "stuns":2})
	var data := {"id":"KNOWN_DOOR_PLANNING", "seed":17, "variant":"normal", "bounds":[16,16],
		"rooms":[{"id":"room", "x":8.0, "z":8.0, "w":5.0, "d":5.0, "indoor":true},
			{"id":"outside", "x":8.0, "z":13.25, "w":16.0, "d":5.5, "indoor":false}],
		"walls":[{"id":"west", "x":5.5, "z":8.0, "w":0.2, "d":5.0},
			{"id":"east", "x":10.5, "z":8.0, "w":0.2, "d":5.0},
			{"id":"north", "x":8.0, "z":5.5, "w":5.0, "d":0.2},
			{"id":"south_left", "x":6.25, "z":10.5, "w":1.5, "d":0.2},
			{"id":"south_right", "x":9.75, "z":10.5, "w":1.5, "d":0.2}],
		"doors":[{"id":"selected", "x":8.0, "z":10.5, "w":1.8, "d":0.2, "axis":"x", "state":"CLOSED", "progress":0.0,
			"hinge_side":-1.0, "swing_sign":1.0, "locked":false, "hp":100.0, "destroyed":false, "material":"wood"},
			{"id":"prior", "x":12.8, "z":13.0, "w":1.8, "d":0.2, "axis":"x", "state":"CLOSED", "progress":0.0,
				"hinge_side":-1.0, "swing_sign":1.0, "locked":false, "hp":100.0, "destroyed":false, "material":"wood"},
			{"id":"hidden", "x":2.0, "z":2.0, "w":1.8, "d":0.2, "axis":"x", "state":"AJAR", "progress":0.52,
				"hinge_side":-1.0, "swing_sign":-1.0, "locked":true, "hp":75.0, "destroyed":false, "material":"metal"}],
		"props":[], "units":units,
		"enemies":[{"id":"hidden_enemy", "x":2.0, "z":2.0, "vision":1.0, "ammo":0, "reserve_ammo":0}],
		"civilians":[{"id":"hidden_civilian", "x":2.5, "z":2.0}],
		"win":[{"type":"reach_zone", "zone":[15.0,15.0,0.1,0.1]}], "fail":[]}
	if route_portal:
		data.doors[1].x = 8.0
		data.doors[1].z = 14.1
		data.walls.append({"id":"prior_left", "x":3.55, "z":14.1, "w":7.1, "d":0.2})
		data.walls.append({"id":"prior_right", "x":12.45, "z":14.1, "w":7.1, "d":0.2})
	return data

func make(data: Dictionary) -> RefCounted:
	var sim: RefCounted = Simulation.new()
	sim.load_mission(data)
	return sim

func row(rows: Array, id: String) -> Dictionary:
	for value: Dictionary in rows:
		if str(value.get("id", "")) == id: return value
	return {}

func pose(state: String = "OPEN", progress: float = 1.0) -> Dictionary:
	return {"state":state, "progress":progress, "destroyed":false, "hp":35.0, "locked":false, "hinge_side":-1.0, "swing_sign":1.0}

func fingerprint(sim: RefCounted) -> String:
	return JSON.stringify({"time":sim.time, "tick":sim.tick, "mission":sim.mission, "units":sim.units, "enemies":sim.enemies,
		"civilians":sim.civilians, "doors":sim.doors, "observations":sim._door_observations, "events":sim.events, "result":sim.result,
		"sequence":sim._sequence, "command_sequence":sim._command_sequence, "drill_sequence":sim._drill_sequence,
		"requests":sim._requests, "revisions":sim.plan_revisions, "sync_waits":sim._sync_waits, "sync_requests":sim._sync_requests,
		"nav_revision":sim.nav.revision, "known_flash_key":sim._known_flash_key, "known_flash_doors":sim._known_flash_doors,
		"reservations":sim._reservations, "flash_barriers":sim._flash_door_barriers,
		"preview_depth":sim._preview_batch_depth, "preview_dirty":sim._preview_dirty_units,
		"insert_index":sim._insert_resource_index, "pause":sim.pause_requested,
		"rng":[sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]})

func _actual_observation() -> void:
	var sim := make(fixture())
	var visible := row(sim.snapshot(false).doors, "selected")
	check(bool(visible.get("observed", false)), "Actual own sight observes the selected door during mission load")
	check(sim._door_observations.has("selected"), "Ordinary perception creates the observed-door evidence")
	check(not sim._door_observations.has("hidden"), "The distant door remains unobserved")
	sim.step(STEP)
	check(sim.tick == 1 and sim.time == STEP, "Actual perception fixture advances exactly one fixed STEP")
	var geometry: Dictionary = sim._drill_geometry("selected")
	visible = row(sim.snapshot(false).doors, "selected")
	for key: String in POSE_KEYS:
		check(row(geometry.doors, "selected")[key] == visible[key], "Publicly observed selected door projects %s exactly" % key)
	check(not visible.has("_observed_at"), "The public door omits private observation bookkeeping")

func _projection_and_ownership() -> void:
	var sim := make(fixture())
	var variants: Array = [pose(), pose("AJAR", 0.52), {"destroyed":true}, {"hp":7.0}, {"locked":true}, {"hinge_side":1.0}, {"swing_sign":-1.0}]
	# Knowledge injection here tests the projection boundary; the preceding case
	# separately proves that ordinary perception supplies the same observations.
	for id: String in ["selected", "prior"]:
		for observation: Dictionary in variants:
			sim._door_observations = {id:observation.duplicate(true)}
			var expected: Dictionary = {}
			for key: String in ["bounds", "schema_version", "walkable_areas", "rooms", "walls", "props", "doors"]:
				if sim.mission.has(key): expected[key] = sim.mission[key].duplicate(true) if sim.mission[key] is Array or sim.mission[key] is Dictionary else sim.mission[key]
			for key: String in POSE_KEYS:
				if observation.has(key): row(expected.doors, id)[key] = observation[key]
			var before := fingerprint(sim)
			var geometry: Dictionary = sim._drill_geometry("selected")
			check(geometry == expected, "%s observation %s overlays only supplied pose keys, retaining authored defaults" % [id, str(observation)])
			check(Door.leaf_obstacle(row(geometry.doors, id)) == Door.leaf_obstacle(row(expected.doors, id)), "%s observed pose supplies the exact physical leaf" % id)
			check(fingerprint(sim) == before, "Geometry projection leaves clock, four RNG streams, queues and evidence unchanged")
			check(sim._drill_geometry() == geometry and sim._formation_geometry() == geometry, "Selected and formation callers share all known portal poses")
	var observation := pose("AJAR", 0.61)
	observation.merge({"x":0.0, "z":0.0, "w":12.0, "d":12.0, "axis":"z", "material":"metal", "owner_id":"hidden_enemy", "initial_states":["OPEN"], "_private":{"npc":[0,0]}})
	sim._door_observations = {"prior":observation}
	var geometry: Dictionary = sim._drill_geometry("selected")
	var prior := row(geometry.doors, "prior")
	var expected := row(sim.mission.doors, "prior").duplicate(true)
	for key: String in POSE_KEYS: expected[key] = observation[key]
	check(prior == expected, "Observation whitelist rejects location, dimensions, material, ownership and private payload")
	var before := fingerprint(sim)
	prior.state = "CLOSED"
	geometry.rooms[0].x = 0.0
	geometry.walls[0].w = 12.0
	geometry.bounds[0] = 999
	check(fingerprint(sim) == before, "Returned nested geometry is detached from observations, authored mission and live doors")

func _route_and_privacy() -> void:
	var sim := make(fixture(true))
	sim._door_observations = {"selected":pose("CLOSED", 0.0)}
	var closed_geometry: Dictionary = sim._drill_geometry("selected")
	var closed_nav: RefCounted = Navigation.new()
	closed_nav.build(closed_geometry, closed_geometry.doors)
	check(closed_nav.path(Vector2(8.0,14.9), Vector2(8.0,11.8)).is_empty(), "Authored closed prior portal seals the route to the next room")
	var rejected: Dictionary = sim.room_entry_preview("selected", "OPEN_DOOR", ORDER, {})
	check(not bool(rejected.get("ok",false)), "The sealed prior portal prevents next-room stack planning")
	sim._door_observations["prior"] = pose()
	var geometry: Dictionary = sim._drill_geometry("selected")
	var known_nav: RefCounted = Navigation.new()
	known_nav.build(geometry, geometry.doors)
	check(not known_nav.path(Vector2(8.0,14.9), Vector2(8.0,11.8)).is_empty(), "A known OPEN nonselected portal restores the actual approach route")
	var before := fingerprint(sim)
	var preview: Dictionary = sim.room_entry_preview("selected", "OPEN_DOOR", ORDER, {})
	check(bool(preview.get("ok",false)) and preview.get("slots",[]).size() == 4, "Known OPEN prior leaf permits four-person next-room entry: %s" % str(preview))
	check(fingerprint(sim) == before, "Successful public preview does not change clock, RNG, queues or any live state")
	check(sim.room_entry_preview("selected", "OPEN_DOOR", ORDER, {}) == preview and fingerprint(sim) == before, "Repeated same-seed knowledge produces an identical read-only draft")
	# No new perception tick follows these changes: the draft must retain the
	# last observed prior pose and the authored, never-observed hidden baseline.
	for door: Dictionary in sim.doors:
		for key: String in POSE_KEYS: door[key] = {"state":"OPEN", "progress":1.0, "destroyed":true, "hp":0.0, "locked":false, "hinge_side":1.0, "swing_sign":-1.0}[key]
		if str(door.id) == "prior":
			door.state = "CLOSED"
			door.progress = 0.0
			door.destroyed = false
	sim.enemies[0].x = 15.0
	sim.enemies[0].z = 1.0
	sim.enemies[0].hp = 1.0
	sim.enemies[0].facing = 2.0
	sim.enemies[0]._ai_state = "ALERT"
	sim.civilians[0].x = 14.0
	sim.civilians[0].hp = 0.0
	before = fingerprint(sim)
	check(sim._drill_geometry("selected") == geometry, "Hidden current poses and NPC state cannot change the known static geometry")
	check(sim.room_entry_preview("selected", "OPEN_DOOR", ORDER, {}) == preview, "Hidden movement, casualties and stale live prior pose cannot change the complete public draft")
	check(fingerprint(sim) == before, "Hidden-state preview remains strictly read-only")
	check(not sim._door_observations.has("hidden") and row(sim.snapshot(false).doors,"hidden").observed == false, "Changing an unknown door does not manufacture public observation")
	sim._door_observations.erase("selected")
	before = fingerprint(sim)
	var unknown: Dictionary = sim.room_entry_preview("selected", "OPEN_DOOR", ORDER, {})
	check(not bool(unknown.get("ok",false)) and unknown.get("message_key","") == "drill.unobserved" and fingerprint(sim) == before, "An unobserved selected portal is rejected atomically")

func _capacity_and_primitives() -> void:
	var sim := make(fixture())
	for index: int in range(32):
		var answer: Dictionary = sim.issue("delta", "WAIT", {"duration":0.0, "request_id":"known-cap-%d" % index}, true)
		check(bool(answer.get("ok",false)), "Capacity fixture retains pending primitive %d" % index)
	var before := fingerprint(sim)
	var answer: Dictionary = sim.plan_room_entry("selected", "OPEN_DOOR", ORDER, {})
	check(not bool(answer.get("ok",false)) and answer.get("message_key","") == "drill.capacity", "Known geometry preserves the strict 32-command cap")
	check(fingerprint(sim) == before and sim.units[3].commands.size() == 32, "Capacity rejection preserves all four queues, IDs, RNG streams and revision state")
	check(Simulation.COMMANDS == PRIMITIVES, "Known-door planning adds no macro primitive or replay command format")
	var planned := make(fixture())
	answer = planned.plan_room_entry("selected", "OPEN_DOOR", ORDER, {})
	check(bool(answer.get("ok",false)), "A normal known-door plan still expands successfully")
	for unit: Dictionary in planned.units:
		check(unit.commands.size() > 0 and unit.commands.size() <= 32, "Expanded own primitive queue stays within its cap")
		for command: Dictionary in unit.commands:
			check(PRIMITIVES.has(str(command.type)), "Every planned command retains an existing primitive type")

func run() -> void:
	_actual_observation()
	_projection_and_ownership()
	_route_and_privacy()
	_capacity_and_primitives()
	print("BREACH_KNOWN_DOOR_PLANNING_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
