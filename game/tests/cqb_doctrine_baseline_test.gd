extends SceneTree
## P0 controlled measurements on M01's unchanged house geometry. These are
## reproducibility checks, not thresholds that would lock later balancing to P0.
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Door = preload("res://scripts/door_geometry.gd")
class ResultPayloadProbe extends "res://scripts/main.gd":
	var captured_payload: Dictionary = {}
	func _emit(message: Dictionary) -> void:
		captured_payload = message.duplicate(true)
const STEP := 1.0 / 30.0
const FRAMES := 360
const SCENARIOS := ["frontal_kick", "quiet_open", "flash_entry", "doorway_stop", "corridor_move"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture(scenario: String, seed_value: int) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	# Keep every authored wall, furniture item, room and door. The front-door
	# cases use the authored four-unit exterior start and one ordinary enemy
	# four metres inside d1, facing the entrance. Remove alternative spawns,
	# other combatants and civilians so the measured contact is the same one.
	var enemy: Dictionary = data.enemies[0].duplicate(true)
	enemy.erase("spawns")
	enemy.erase("patrol")
	enemy.x = 12.0
	enemy.z = 13.0
	enemy.facing = PI * 0.5
	enemy.response_role = "guard"
	data.enemies = [enemy]
	data.civilians = []
	data.seed = seed_value
	data.modifiers = []
	data.stars = []
	data.fail = []
	# No participant travels to this sentinel goal. An early neutralization
	# therefore cannot truncate the fixed twelve-second observation horizon.
	data.win = [{"type":"reach_zone", "zone":[23.0, 1.0, 0.2, 0.2]}]
	if scenario == "corridor_move":
		# M01 has a central entry passage rather than a separate corridor room.
		# Start inside that passage, open its living-room side door and place
		# the contact on legal living-room floor with a view across the passage.
		for index: int in range(data.units.size()):
			data.units[index].x = 11.4 + index * 0.7
			data.units[index].z = 15.7
			data.units[index].facing = -PI * 0.5
		enemy.id = "e2"
		enemy.x = 7.8
		enemy.z = 13.6
		enemy.facing = 0.0
		for door: Dictionary in data.doors:
			if door.id in ["d1", "d2"]: door.state = "OPEN"
	return data

func issue(sim: BreachSimulation, unit_id: String, type: String, args: Dictionary) -> void:
	var response: Dictionary = sim.issue(unit_id, type, args)
	check(bool(response.get("ok", false)), "%s seed %d: %s %s accepted: %s" % [sim.mission.id, sim.mission.seed, unit_id, type, response.get("message", "")])

func plan(sim: BreachSimulation, scenario: String) -> void:
	var destinations := [[11.0, 14.5], [13.0, 14.5], [11.0, 12.7], [13.0, 12.7]]
	for index: int in range(sim.units.size()):
		var unit_id: String = str(sim.units[index].id)
		if scenario == "corridor_move":
			issue(sim, unit_id, "MOVE", {"target":[10.8 + index * 0.8, 10.8]})
			continue
		if scenario == "flash_entry":
			if index == 0:
				issue(sim, unit_id, "OPEN_AND_FLASH", {"door_id":"d1", "target":[12.0, 13.0]})
			else:
				issue(sim, unit_id, "WAIT", {"duration":4.0})
				issue(sim, unit_id, "OPEN_DOOR", {"door_id":"d1"})
		else:
			issue(sim, unit_id, "KICK_DOOR" if scenario == "frontal_kick" else "OPEN_DOOR", {"door_id":"d1"})
		if scenario == "doorway_stop" and index == 0:
			issue(sim, unit_id, "MOVE", {"target":[12.3, 16.8]})
			issue(sim, unit_id, "WAIT", {"duration":1.0})
		issue(sim, unit_id, "MOVE", {"target":destinations[index]})

func metric(sim: BreachSimulation, hostile_shots: int) -> Dictionary:
	var stats: Dictionary = sim._statistics()
	for key: String in ["doorway_dwell", "time_to_dominate", "enemy_first_shot", "threat_order_violations", "rear_hits"]:
		check(stats.has(key), "P0 statistic is present: " + key)
	var dwell := 0.0
	for value: Variant in stats.get("doorway_dwell", {}).values(): dwell += float(value)
	var entry: Dictionary = stats.get("time_to_dominate", {}).get("d1", {})
	var first_enemy: bool = stats.get("enemy_first_shot", []).any(func(contact: Dictionary) -> bool: return bool(contact.enemy_first))
	return {"doctrine":{
		"doorway_dwell":stats.get("doorway_dwell", {}),
		"time_to_dominate":stats.get("time_to_dominate", {}),
		"enemy_first_shot":stats.get("enemy_first_shot", []),
		"threat_order_violations":stats.get("threat_order_violations", 0),
		"rear_hits":stats.get("rear_hits", 0)},
		"mean_unit_dwell":dwell / sim.units.size(),
		"dominate_seconds":float(entry.get("seconds", -1.0)),
		"enemy_first":first_enemy, "hostile_shots":hostile_shots,
		"hits_taken":sim.hits_taken, "kills":sim.kills,
		"survivors":sim.units.filter(func(unit: Dictionary) -> bool: return float(unit.hp) > 0.0).size(),
		"command_failures":sim.command_failures}

func run_case(scenario: String, seed_value: int) -> Dictionary:
	var sim := Simulation.new()
	var data := fixture(scenario, seed_value)
	sim.load_mission(data)
	sim.enemy_rules = Catalog.NORMAL.duplicate(true)
	check(sim.units.size() == 4 and sim.enemies.size() == 1, scenario + ": controlled four-unit, one-enemy fixture")
	for actor: Dictionary in sim.units + sim.enemies:
		check(sim.nav.walkable(sim._position(actor)), scenario + ": legal authored-geometry spawn " + str(actor.id))
	plan(sim, scenario)
	var hostile_shots := 0
	for frame: int in range(FRAMES):
		var before: int = int(sim.enemies[0].ammo)
		var was_surrendered: bool = bool(sim.enemies[0].get("surrendered", false))
		sim.step(STEP)
		# Hidden attackers publish only coarse sounds; authoritative ammunition
		# measures their fire without changing the player-observation contract.
		# P1 enables surrender before combat in step(): discarding the magazine
		# on that transition is not a shot. P0's archived results stay unchanged.
		if was_surrendered or not bool(sim.enemies[0].get("surrendered", false)):
			hostile_shots += maxi(0, before - int(sim.enemies[0].ammo))
	check(sim.tick == FRAMES, scenario + ": every case reaches the fixed-step horizon")
	return {"seed":seed_value, "scenario":scenario, "metrics":metric(sim, hostile_shots), "snapshot":sim.snapshot(true)}

func aggregate(cases: Array) -> Dictionary:
	var row: Dictionary = {"cases":cases.size(), "mean_unit_dwell":0.0, "mean_dominate_seconds":0.0, "dominated_cases":0, "enemy_first_cases":0, "hostile_firing_cases":0, "friendly_hit_cases":0, "threat_order_violations":0, "rear_hits":0, "kills":0, "survivors":0, "command_failures":0}
	for item: Dictionary in cases:
		var value: Dictionary = item.metrics
		row.mean_unit_dwell += float(value.mean_unit_dwell)
		if float(value.dominate_seconds) >= 0.0:
			row.dominated_cases += 1
			row.mean_dominate_seconds += float(value.dominate_seconds)
		row.enemy_first_cases += int(bool(value.enemy_first))
		row.hostile_firing_cases += int(int(value.hostile_shots) > 0)
		row.friendly_hit_cases += int(int(value.hits_taken) > 0)
		row.threat_order_violations += int(value.doctrine.threat_order_violations)
		row.rear_hits += int(value.doctrine.rear_hits)
		row.kills += int(value.kills)
		row.survivors += int(value.survivors)
		row.command_failures += int(value.command_failures)
	row.mean_unit_dwell /= cases.size()
	row.mean_dominate_seconds = float(row.mean_dominate_seconds) / int(row.dominated_cases) if int(row.dominated_cases) > 0 else -1.0
	return row

func _instrumentation_contracts() -> void:
	var axis_x := Door.funnel_rect({"x":5.0, "z":6.0, "w":1.8, "d":0.24, "axis":"x"})
	var axis_z := Door.funnel_rect({"x":5.0, "z":6.0, "w":0.24, "d":1.8, "axis":"z"})
	check(axis_x.size.is_equal_approx(Vector2(1.8, 2.4)), "Horizontal doorway uses authored width and 1.2m depth on each side")
	check(axis_z.size.is_equal_approx(Vector2(2.4, 1.8)), "Vertical doorway rotates the same funnel dimensions")
	var sim := Simulation.new()
	sim.load_mission({"id":"P0_CONTRACT", "seed":0, "bounds":[12,12], "walls":[], "props":[], "doors":[], "rooms":[{"id":"room", "x":6.0, "z":6.0, "w":10.0, "d":10.0}], "units":[{"id":"alpha", "x":6.0, "z":6.0, "facing":0.0}], "enemies":[{"id":"near", "x":8.0, "z":6.0, "facing":0.0}, {"id":"ready", "x":10.0, "z":6.0, "facing":PI}]})
	var unit: Dictionary = sim.units[0]
	var near: Dictionary = sim.enemies[0]
	var ready: Dictionary = sim.enemies[1]
	ready.aim_facing = PI
	ready.aim_progress = 1.0
	ready.aim_state = "ready"
	unit._reaction = 0.0
	unit._observed = [{"id":"near", "identified":true, "time":sim.time}, {"id":"ready", "identified":true, "time":sim.time}]
	sim.doctrine.record_shot(sim, unit, near, false, true)
	check(sim._statistics().threat_order_violations == 1, "A shot at the nearer unready enemy records the observed ready threat it bypassed")
	sim.doctrine.record_shot(sim, unit, ready, false, true)
	check(sim._statistics().threat_order_violations == 1, "Shooting the ready immediate threat adds no ordering violation")
	check(sim._statistics().enemy_first_shot.size() == 1 and not bool(sim._statistics().enemy_first_shot[0].enemy_first), "An engagement records its first shot once")
	# Rear means the ninety-degree cone centered on the body's back, including
	# its 45-degree boundary. A miss or a hit just outside it is not counted.
	unit.body_facing = 0.0
	for angle: float in [PI, PI * 0.75, PI * 0.75 - 0.01]:
		near.x = 6.0 + cos(angle) * 2.0
		near.z = 6.0 + sin(angle) * 2.0
		sim.doctrine.record_shot(sim, near, unit, true, true)
	check(sim._statistics().rear_hits == 2, "Rear-hit metric honors the ninety-degree body-relative boundary")
	sim.doctrine.record_shot(sim, near, unit, true, false)
	check(sim._statistics().rear_hits == 2, "Missed hostile shots do not increment rear hits")
	sim.time = 3.0
	sim.tick = 90
	sim.doctrine.record_shot(sim, near, unit, true, false)
	check(sim._statistics().enemy_first_shot.size() == 2 and bool(sim._statistics().enemy_first_shot[1].enemy_first), "Three seconds without shots starts a new engagement with its own first shooter")
	var detached: Dictionary = sim._statistics()
	detached.enemy_first_shot.clear()
	check(sim._statistics().enemy_first_shot.size() == 2, "Returned statistics are detached from authoritative instrumentation")
	sim.load_mission(fixture("quiet_open", 0))
	var reset: Dictionary = sim._statistics()
	check(reset.enemy_first_shot.is_empty() and reset.threat_order_violations == 0 and reset.rear_hits == 0, "Loading a mission resets the passive metrics")

func _threat_priority_case(seed_value: int) -> Dictionary:
	# Auxiliary two-contact fixture for the P1 80% reduction comparison. The
	# five one-contact house cases cannot exhibit a target-order violation.
	var sim := Simulation.new()
	sim.load_mission({"id":"P0_THREAT", "seed":seed_value, "bounds":[12,12], "walls":[], "props":[], "doors":[], "rooms":[{"id":"room", "x":6.0, "z":6.0, "w":10.0, "d":10.0}], "units":[{"id":"alpha", "x":6.0, "z":6.0, "facing":0.0}], "enemies":[{"id":"near", "x":8.0, "z":6.0, "facing":0.0}, {"id":"ready", "x":10.0, "z":6.0, "facing":PI}], "win":[{"type":"reach_zone", "zone":[1.0,1.0,0.2,0.2]}]})
	var unit: Dictionary = sim.units[0]
	var ready: Dictionary = sim.enemies[1]
	ready.aim_facing = PI
	ready.aim_progress = 1.0
	ready.aim_state = "ready"
	unit._reaction = 0.0
	sim._remember_aim(unit, sim.enemies[0])
	unit.aim_progress = 1.0
	unit.aim_state = "ready"
	for frame: int in range(30):
		sim.tick += 1
		sim.time += STEP
		unit._observed = [{"id":"near", "identified":true, "time":sim.time}, {"id":"ready", "identified":true, "time":sim.time}]
		sim._combat(unit, sim.enemies, false)
		if sim.shots_fired > 0: break
	check(sim.shots_fired == 1, "Threat comparison emits exactly its first ordinary unit shot")
	var target_id := ""
	for event: Dictionary in sim.events:
		if event.type == "SHOT": target_id = str(event.target_id)
	return {"seed":seed_value, "target_id":target_id, "threat_order_violations":sim._statistics().threat_order_violations, "tick":sim.tick}

func _replay_contracts() -> void:
	var data := fixture("quiet_open", 0)
	var sim := Simulation.new()
	sim.load_mission(data)
	plan(sim, "quiet_open")
	var record := Replay.new()
	record.begin(data)
	var initial_state: Dictionary = sim.snapshot(true)
	record.capture(initial_state)
	for frame: int in range(180):
		sim.step(STEP)
		if frame % 3 == 0: record.capture(sim.snapshot(true))
	record.finish(sim.snapshot(true))
	var exported: Dictionary = record.export_data()
	var restored := Replay.new()
	var answer: Dictionary = restored.load_data(exported)
	check(bool(answer.get("ok", false)), "P0 metrics round-trip in replay schema 1: " + str(answer.get("message", "")))
	if bool(answer.get("ok", false)):
		var end: Dictionary = restored.seek(restored.duration)
		for key: String in ["doorway_dwell", "time_to_dominate", "enemy_first_shot", "threat_order_violations", "rear_hits"]:
			check(JSON.stringify(end.get(key)) == JSON.stringify(sim._statistics()[key]), "Replay preserves final doctrine metric: " + key)
	var bad_numeric: Dictionary = exported.duplicate(true)
	bad_numeric.metadata.back().doorway_dwell.alpha = NAN
	check(not bool(Replay.new().load_data(bad_numeric).get("ok", false)), "Replay rejects nonfinite doctrine dwell")
	var bad_nested: Dictionary = exported.duplicate(true)
	if not bad_nested.metadata.back().time_to_dominate.is_empty():
		bad_nested.metadata.back().time_to_dominate.values()[0]["unknown"] = true
		check(not bool(Replay.new().load_data(bad_nested).get("ok", false)), "Replay rejects unknown nested domination fields")
	else:
		check(false, "Replay fixture records a doorway-open domination entry")
	var legacy: Dictionary = exported.duplicate(true)
	for meta: Dictionary in legacy.metadata:
		for key: String in ["doorway_dwell", "time_to_dominate", "enemy_first_shot", "threat_order_violations", "rear_hits"]: meta.erase(key)
	check(bool(Replay.new().load_data(legacy).get("ok", false)), "Replay still loads old schema 1 records without optional doctrine metrics")

func _observation_contracts() -> void:
	var data := fixture("quiet_open", 0)
	# Place the observing unit on legal study-room floor, facing away from d6.
	# This isolates the single connecting doorway without projecting a chain
	# of future operator clearances from the exterior through other rooms.
	data.units[0].x = 12.0
	data.units[0].z = 7.0
	data.units[0].facing = PI
	var sim := Simulation.new()
	sim.load_mission(data)
	var door: Dictionary = sim._find(sim.doors, "d6")
	check(sim.nav.walkable(sim._position(sim.units[0])), "Hidden-door unit starts on legal study-room floor")
	check(not sim._door_observations.has("d6"), "Observation fixture starts without sight of the northern connecting door")
	# Build a legal conditional route through the unseen door. P0 now only
	# attributes entrants whose actual planned path crosses this doorway.
	issue(sim, "alpha", "OPEN_DOOR", {"door_id":"d6"})
	issue(sim, "alpha", "MOVE", {"target":[18.0, 7.0]})
	var planned_path: Array = sim.units[0].commands.back().path
	check(not planned_path.is_empty(), "Hidden-door fixture has a legal conditional move path")
	check(sim.doctrine._route_crosses_door(sim, sim._position(sim.units[0]), planned_path, door), "Hidden-door fixture actually enters through d6")
	# Model an unseen enemy opening its own room's door while a future player
	# MOVE happens to cross that plane. Passive metrics still record it for
	# authority, but no current hidden state is allowed into player snapshots.
	var record := Replay.new()
	record.begin(data)
	var initial_state: Dictionary = sim.snapshot(true)
	record.capture(initial_state)
	sim.tick = 2
	sim.time = STEP * 2.0
	door.state = "OPEN"
	door.progress = 1.0
	sim.doctrine.update(sim, 0.0)
	check(sim._statistics().time_to_dominate.has("d6"), "An unseen opened door can still have authoritative measurement")
	check(not sim.snapshot(false).time_to_dominate.has("d6"), "Ordinary player snapshot conceals unseen door-open measurements")
	var pair: Dictionary = sim.snapshot_pair()
	check(pair.record.time_to_dominate.has("d6") and not pair.observed.time_to_dominate.has("d6"), "Paired recording and player snapshots independently filter door observation")
	record.finish(sim.snapshot(true))
	var restored := Replay.new()
	var answer: Dictionary = restored.load_data(record.export_data())
	check(bool(answer.get("ok", false)), "Hidden-door metric replay preserves the optional observed marker")
	if bool(answer.get("ok", false)):
		check(not restored.seek(restored.duration, false).time_to_dominate.has("d6"), "Player replay seek conceals unseen door-open measurements")
		check(restored.seek(restored.duration, true).time_to_dominate.has("d6"), "Explicit authoritative replay inspection retains hidden-door measurements")
	# Complete through the real victory evaluator while the opened door is
	# still unseen. Result review must not silently override this metric's
	# observation contract at either the top level or inside result metadata.
	sim.mission.win = [{"type":"reach_zone", "zone":[12.0, 7.0, 1.0, 1.0]}]
	var completed_record := Replay.new()
	completed_record.begin(data)
	completed_record.capture(initial_state)
	completed_record.capture(sim.snapshot(true))
	sim.tick += 1
	sim.time += STEP
	sim._check_result()
	check(bool(sim.result.get("success", false)), "Hidden-door result fixture completes through the real reached-zone rule")
	var completed: Dictionary = sim.snapshot(false)
	check(not completed.time_to_dominate.has("d6") and not completed.result.time_to_dominate.has("d6"), "Completed player snapshot conceals hidden metrics in both state and result")
	var completed_pair: Dictionary = sim.snapshot_pair()
	check(not completed_pair.observed.time_to_dominate.has("d6") and not completed_pair.observed.result.time_to_dominate.has("d6"), "Completed paired player state conceals top-level and nested result metrics")
	check(completed_pair.record.time_to_dominate.has("d6") and completed_pair.record.result.time_to_dominate.has("d6") and sim.result.time_to_dominate.has("d6"), "Filtering completed paired state preserves both authoritative recording and simulation result")
	completed_record.finish(sim.snapshot(true))
	var completed_replay := Replay.new()
	var completed_answer: Dictionary = completed_replay.load_data(completed_record.export_data())
	check(bool(completed_answer.get("ok", false)), "Completed hidden-door state and result round-trip through validated replay: " + str(completed_answer.get("message", "")))
	if bool(completed_answer.get("ok", false)):
		var public_end: Dictionary = completed_replay.seek(completed_replay.duration, false)
		var authority_end: Dictionary = completed_replay.seek(completed_replay.duration, true)
		check(not public_end.time_to_dominate.has("d6") and not public_end.result.time_to_dominate.has("d6"), "Completed ordinary replay seek conceals top-level and nested hidden metrics")
		check(authority_end.time_to_dominate.has("d6") and authority_end.result.time_to_dominate.has("d6"), "Explicit completed replay reveal preserves top-level and nested authoritative metrics")
	# A script-only controller probe exercises the exact bridge payload path
	# without constructing the scene, rendering, or waiting on wall-clock time.
	sim.take_record_events()
	var bridge := ResultPayloadProbe.new()
	bridge.sim = sim
	bridge.recorder = completed_record
	bridge.active_mission = data
	bridge.mode = "RESULT"
	# P3 normally builds an observed RESULT presentation. Supply the full
	# recording explicitly so this original test still exercises filtering
	# without mutating its authoritative input, rather than relying on the
	# former automatic RESULT reveal policy.
	bridge.shown = sim.snapshot(true)
	bridge._remember_shown()
	var original_shown := bridge.shown.duplicate(true)
	bridge._send_state()
	check(bridge.captured_payload.mode == "RESULT" and not bridge.captured_payload.time_to_dominate.has("d6") and not bridge.captured_payload.result.time_to_dominate.has("d6"), "Main RESULT bridge payload conceals unseen metrics at both levels")
	check(bridge.shown.time_to_dominate.has("d6") and bridge.shown.result.time_to_dominate.has("d6") and sim.result.time_to_dominate.has("d6"), "Main payload filtering preserves its source snapshot and authoritative result")
	check(bridge.shown == original_shown, "Main payload filtering preserves every field of the supplied authoritative snapshot")
	bridge.free()
	var observation: Dictionary = door.duplicate(true)
	observation["observed"] = true
	observation["_observed_at"] = sim.time
	sim._door_observations["d6"] = observation
	sim.doctrine.update(sim, 0.0)
	check(sim.snapshot(false).time_to_dominate.has("d6"), "The measurement becomes public after the opening is actually observed")

func _route_fixture(unit_position: Array, first_door_x: float) -> BreachSimulation:
	var sim := Simulation.new()
	sim.load_mission({"id":"PROJECTED_ROUTE_PROBE", "seed":0, "bounds":[14,12], "walls":[], "props":[], "rooms":[{"id":"north", "x":7.0, "z":3.5, "w":14.0, "d":5.0}, {"id":"south", "x":7.0, "z":8.5, "w":14.0, "d":5.0}], "doors":[{"id":"a", "x":first_door_x, "z":6.0, "w":1.8, "d":0.24, "axis":"x", "state":"OPEN"}, {"id":"b", "x":9.0, "z":6.0, "w":1.8, "d":0.24, "axis":"x", "state":"OPEN"}], "units":[{"id":"alpha", "x":unit_position[0], "z":unit_position[1]}], "enemies":[]})
	return sim

func _measure_route(sim: BreachSimulation, false_label: String) -> void:
	sim.doctrine._begin_entry(sim, sim.doors[0])
	sim.doctrine._begin_entry(sim, sim.doors[1])
	check(not sim.doctrine.time_to_dominate.has("a"), false_label)
	check(sim.doctrine.time_to_dominate.has("b") and sim.doctrine.time_to_dominate.b.participants == ["alpha"], "Actual remaining route through b is retained")

func _projected_path_contracts() -> void:
	# Measurements inspect each order from its real projected start. Passed
	# waypoints and connectors invented from the actor's current position must
	# not create doorway entries that its remaining plan never traverses.
	for state: String in ["RUNNING", "WAITING"]:
		var sim := _route_fixture([9.0,5.0], 5.0)
		sim.units[0].commands = [{"type":"MOVE", "state":state, "_started":true, "args":{"target":[9.0,8.0]}, "path":[[5.0,8.0],[5.0,5.0],[9.0,5.0],[9.0,8.0]], "path_cursor":3}]
		_measure_route(sim, state + " ignores the already-travelled a crossing")
	for preceding_type: String in ["MOVE", "OPEN_DOOR"]:
		var sim := _route_fixture([5.0,4.0], 23.0 / 3.0)
		var args := {"target":[9.0,4.0]} if preceding_type == "MOVE" else {"door_id":"b"}
		sim.units[0].commands = [{"type":preceding_type, "state":"PENDING", "args":args, "path":[[9.0,4.0]], "path_cursor":0}, {"type":"MOVE", "state":"PENDING", "args":{"target":[9.0,8.0]}, "path":[[9.0,7.0],[9.0,8.0]], "path_cursor":0}]
		_measure_route(sim, preceding_type + " endpoint avoids a fabricated current-position connector through a")
	var blocked := _route_fixture([9.0,5.0], 5.0)
	blocked.units[0].commands = [{"type":"MOVE", "state":"FAILED", "args":{"target":[9.0,5.0]}, "path":[]}, {"type":"MOVE", "state":"PENDING", "args":{"target":[9.0,8.0]}, "path":[[9.0,8.0]]}]
	blocked.doctrine._begin_entry(blocked, blocked.doors[1])
	check(blocked.doctrine.time_to_dominate.is_empty(), "Failed preceding order does not contribute impossible future entry")

func run() -> void:
	_instrumentation_contracts()
	_observation_contracts()
	_projected_path_contracts()
	if OS.get_cmdline_user_args().has("--contracts-only"):
		var count := 0
		for seed_value: int in range(30): count += int(_threat_priority_case(seed_value).threat_order_violations)
		_replay_contracts()
		print("BREACH_CQB_THREAT_PRIORITY violations=%d cases=30" % count)
		print("BREACH_CQB_DOCTRINE_BASELINE_RESULT checks=%d failures=%d" % [checks, failures.size()])
		for failure: String in failures: push_error(failure)
		quit(0 if failures.is_empty() else 1)
		return
	var report: Dictionary = {"scope":"M01 unchanged geometry; controlled four-unit/one-enemy contacts; 12 seconds at 30 Hz", "seeds":[], "scenarios":{}, "cases":[]}
	for seed_value: int in range(30): report.seeds.append(seed_value)
	for scenario: String in SCENARIOS:
		var cases: Array = []
		for seed_value: int in range(30):
			var first := run_case(scenario, seed_value)
			var second := run_case(scenario, seed_value)
			check(JSON.stringify(first.metrics) == JSON.stringify(second.metrics), "%s seed %d: repeated doctrine measurements match" % [scenario, seed_value])
			check(JSON.stringify(first.snapshot) == JSON.stringify(second.snapshot), "%s seed %d: instrumentation preserves deterministic full snapshots" % [scenario, seed_value])
			first.erase("snapshot")
			cases.append(first)
			report.cases.append(first)
		report.scenarios[scenario] = aggregate(cases)
		print("BREACH_CQB_BASELINE_SCENARIO " + scenario + " " + JSON.stringify(report.scenarios[scenario]))
	var threat_cases: Array = []
	var threat_total := 0
	for seed_value: int in range(30):
		var first := _threat_priority_case(seed_value)
		var second := _threat_priority_case(seed_value)
		check(JSON.stringify(first) == JSON.stringify(second), "Auxiliary threat-order fixture is deterministic for seed %d" % seed_value)
		threat_cases.append(first)
		threat_total += int(first.threat_order_violations)
	report["threat_priority"] = {"scope":"one unit, nearer back-turned enemy at 2m, farther ready enemy aimed at unit at 4m; first shot only", "cases":threat_cases, "threat_order_violations":threat_total}
	_replay_contracts()
	print("BREACH_CQB_DOCTRINE_BASELINE " + JSON.stringify({"scope":report.scope, "seeds":report.seeds, "scenarios":report.scenarios, "threat_priority_violations":threat_total}))
	var artifact_dir: String = ProjectSettings.globalize_path("res://../tests/artifacts")
	DirAccess.make_dir_recursive_absolute(artifact_dir)
	var artifact := FileAccess.open(artifact_dir.path_join("cqb-doctrine-baseline.json"), FileAccess.WRITE)
	check(artifact != null, "Baseline case evidence can be written")
	if artifact != null: artifact.store_string(JSON.stringify(report, "\t") + "\n")
	print("BREACH_CQB_DOCTRINE_BASELINE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
