extends SceneTree
## P1 primitives keep the existing replay and fresh-plan formats. Runtime
## recordings use fixed seeds and fixed ticks; scene frames only initialize UI.
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const MainScene = preload("res://main.tscn")
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
	_test_serialization_contracts()
	_test_legacy_absence()
	_test_schema3_inheritance()
	for seed_value: int in range(30):
		_test_runtime(seed_value, "KICK_DOOR", {"door_id":"d1", "fallback":"breach"})
		_test_runtime(seed_value, "SHOTGUN_BREACH", {"door_id":"d1"})
	await _test_plan_roundtrip()
	print("BREACH_CQB_CONTACT_REPLAY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _fixture(seed_value: int) -> Dictionary:
	var mission: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	mission.schema_version = 3
	mission.id = "CQB_CONTACT_REPLAY"
	mission.custom = true
	mission.seed = seed_value
	mission.variant = "normal"
	mission.units = [mission.units[0]]
	mission.units[0].weapon = "shotgun"
	mission.units[0].breaches = 2
	mission.enemies = []
	mission.civilians = []
	mission.fail = []
	mission.stars = []
	mission.win = [{"type":"reach_zone", "zone":[23.0, 1.0, 0.2, 0.2]}]
	mission.doors[0].kick_resistance = 0.0
	mission.doors[0].reinforced = true
	mission.doors[0].locked = true
	return mission

func _test_runtime(seed_value: int, type: String, args: Dictionary) -> void:
	var mission := _fixture(seed_value)
	var validation: Dictionary = Catalog.validate_custom(mission)
	check(bool(validation.get("ok", false)), "Runtime fixture schema accepted, seed %d: %s" % [seed_value, validation.get("message", "")])
	if not validation.get("ok", false): return
	var sim := Simulation.new()
	sim.load_mission(mission)
	var unit_id := str(sim.units[0].id)
	var response: Dictionary = sim.issue(unit_id, type, args)
	check(bool(response.get("ok", false)), "%s runtime order accepted, seed %d: %s" % [type, seed_value, response.get("message", "")])
	if not response.get("ok", false): return
	var recording := Replay.new()
	recording.begin(mission)
	var initial: Dictionary = sim.snapshot(true)
	recording.capture(initial)
	var transitions: Array = []
	var previous_phase := ""
	for frame: int in range(TICKS):
		sim.step(STEP)
		var state: Dictionary = sim.snapshot(true)
		recording.capture(state)
		var command: Dictionary = state.units[0].commands[0]
		var phase := str(command.get("phase", ""))
		if phase != previous_phase:
			transitions.append({"time":sim.time, "tick":sim.tick, "phase":phase})
			previous_phase = phase
	var final: Dictionary = sim.snapshot(true)
	if type == "KICK_DOOR":
		check(final.units[0].commands[0].state == "SUCCEEDED" and final.doors[0].state == "OPEN" and int(final.units[0].breaches) == 1, "A valid forced-failure plan completes its reserved charge branch")
	else:
		check(final.units[0].commands[0].state in ["SUCCEEDED", "FAILED"] and int(final.units[0].ammo) == int(initial.units[0].ammo) - 1, "A shotgun attempt reaches its deterministic outcome and consumes one round")
	recording.finish(final)
	var exported: Dictionary = JSON.parse_string(JSON.stringify(recording.export_data()))
	var restored := Replay.new()
	var loaded: Dictionary = restored.load_data(exported)
	check(bool(loaded.get("ok", false)), "%s runtime replay accepted, seed %d: %s" % [type, seed_value, loaded.get("message", "")])
	if not loaded.get("ok", false): return
	check(exported.schema_version == 1 and exported.encoding == "numeric-state-v1", "P1 keeps replay schema and encoding")
	check(restored.seek(0.0, true).units[0].commands[0].args == args, "P1 command arguments survive initial frame")
	var decoded: Dictionary = restored.seek(recording.duration, true)
	check(decoded.units[0].commands[0] == JSON.parse_string(JSON.stringify(final.units[0].commands[0])), "P1 final primitive state survives replay, seed %d" % seed_value)
	for field: String in ["ammo", "breaches", "available_shotgun_breaches", "available_breaches"]:
		check(decoded.units[0].get(field) == final.units[0].get(field), "P1 actor resource retained: " + field)
	for field: String in ["state", "locked", "destroyed", "kick_resistance", "reinforced"]:
		check(decoded.doors[0].get(field) == final.doors[0].get(field), "P1 door property retained: " + field)
	check(sim.tick == TICKS, "Every runtime replay reaches its fixed tick horizon")
	check(not transitions.is_empty(), "P1 runtime traverses a public door-action phase")
	for transition: Dictionary in transitions:
		var sample: Dictionary = restored.seek(float(transition.time), true)
		check(sample.tick == transition.tick and sample.units[0].commands[0].get("phase", "") == transition.phase, "Door phase transition is captured at its actual tick: " + str(transition.phase))
	var recorded_events: Array = exported.events.filter(func(event: Dictionary) -> bool: return event.type in ["KICK_FAILED", "BREACH_RETREAT"])
	if type == "KICK_DOOR": check(recorded_events.any(func(event: Dictionary) -> bool: return event.type == "KICK_FAILED"), "Forced failed kick is retained as an event")
	check(not JSON.stringify(exported).contains("_breach_") and not JSON.stringify(exported).contains("_door_ready_"), "Runtime private door state is omitted from replay")

func _contract_state(mission: Dictionary) -> Dictionary:
	var unit: Dictionary = mission.units[0]
	var enemy: Dictionary = mission.enemies[0]
	var door: Dictionary = mission.doors[0]
	var commands: Array = []
	for index: int in range(Replay.DOOR_ACTION_PHASES.size()):
		var phase: String = Replay.DOOR_ACTION_PHASES[index]
		var type := "SHOTGUN_BREACH" if phase.begins_with("SHOTGUN") else "KICK_DOOR"
		commands.append({"id":"contact-%d" % index, "type":type, "args":{"door_id":door.id} if type == "SHOTGUN_BREACH" else {"door_id":door.id, "fallback":"breach"}, "state":"RUNNING", "phase":phase})
	return {"time":0.0, "tick":0, "units":[{"id":unit.id, "kind":"unit", "x":unit.x, "z":unit.z, "hp":100.0, "ammo":8, "available_shotgun_breaches":3, "available_breaches":2, "commands":commands}], "enemies":[{"id":enemy.id, "kind":"enemy", "x":enemy.x, "z":enemy.z, "hp":72.0, "visible":false, "door_ready":false}], "civilians":[], "doors":[{"id":door.id, "x":door.x, "z":door.z, "w":door.w, "d":door.d, "axis":door.axis, "state":"CLOSED", "kick_resistance":0.25, "reinforced":true}], "events":[]}

func _test_serialization_contracts() -> void:
	var mission: Dictionary = Catalog.load("M01")
	var state := _contract_state(mission)
	var recording := Replay.new()
	recording.begin(mission)
	recording.capture(state)
	state.time = STEP
	state.tick = 1
	state.enemies[0].door_ready = true
	recording.capture(state)
	check(recording.frames.size() == 2, "Readiness transition records immediately inside the 0.1s sample interval")
	state.time = 2.0 * STEP
	state.tick = 2
	state.units[0].commands[0].phase = "BREACH_INSTALL"
	recording.capture(state)
	check(recording.frames.size() == 3, "A RUNNING command phase transition records immediately")
	state.time = 3.0 * STEP
	state.tick = 3
	state.events = [{"seq":1, "tick":3, "time":state.time, "type":"KICK_FAILED", "door_id":mission.doors[0].id, "unit_id":mission.units[0].id, "kind":"KICK_DOOR", "radius":9.0}, {"seq":2, "tick":3, "time":state.time, "type":"BREACH_RETREAT", "door_id":mission.doors[0].id, "unit_id":mission.units[0].id, "kind":"SHOTGUN_BREACH", "from":[state.units[0].x, state.units[0].z], "to":[state.units[0].x, float(state.units[0].z) + 0.5]}]
	recording.finish(state)
	var candidate: Dictionary = JSON.parse_string(JSON.stringify(recording.export_data()))
	var restored := Replay.new()
	var response: Dictionary = restored.load_data(candidate)
	check(bool(response.get("ok", false)), "Complete P1 serialization contract accepted: " + str(response.get("message", "")))
	if not response.get("ok", false): return
	check(restored.seek(STEP, true).enemies[0].door_ready and not restored.seek(0.0, true).enemies[0].door_ready, "Replay preserves readiness without leaking it before the transition")
	check(restored.seek(STEP, false).enemies.is_empty(), "Hidden ready enemies stay absent from player replay")
	var before := JSON.stringify(restored.export_data())
	for mutation: String in ["fallback", "shotgun_args", "phase", "phase_owner", "phase_method", "shotgun_charge_phase", "missing_fallback", "ready_type", "ready_owner", "reinforced", "kick_probability", "kick_nan", "reserve_fraction", "reserve_large", "reserve_nan", "reserve_owner", "charge_fraction", "charge_large", "charge_owner", "event_kind", "event_door"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		match mutation:
			"fallback": corrupt.commands[0].args.fallback = "shotgun"
			"shotgun_args":
				for command: Dictionary in corrupt.commands:
					if command.type == "SHOTGUN_BREACH": command.args.fallback = "breach"; break
			"phase": corrupt.commands[0].phase = "EXECUTE_SCRIPT"
			"phase_owner": corrupt.commands[0].type = "WAIT"; corrupt.commands[0].args = {"duration":1.0}
			"phase_method": corrupt.commands[0].phase = "SHOTGUN_RETREAT"
			"shotgun_charge_phase": corrupt.commands[0].type = "SHOTGUN_BREACH"; corrupt.commands[0].phase = "BREACH_INSTALL"; corrupt.commands[0].args.erase("fallback")
			"missing_fallback": corrupt.commands[0].phase = "BREACH_INSTALL"; corrupt.commands[0].args.erase("fallback")
			"ready_type": _mutate_static(corrupt, "enemies", "door_ready", "true")
			"ready_owner": _mutate_static(corrupt, "units", "door_ready", true)
			"reinforced": _mutate_static(corrupt, "doors", "reinforced", "yes")
			"kick_probability": check(_mutate_number(corrupt, "doors", "kick_resistance", 1.01), "Probability corruption reaches a numeric sample")
			"kick_nan": check(_mutate_number(corrupt, "doors", "kick_resistance", NAN), "Nonfinite probability reaches a numeric sample")
			"reserve_fraction": check(_mutate_number(corrupt, "units", "available_shotgun_breaches", 1.5), "Reservation corruption reaches a numeric sample")
			"reserve_large": check(_mutate_number(corrupt, "units", "available_shotgun_breaches", 10001), "Reservation upper-bound corruption reaches a numeric sample")
			"reserve_nan": check(_mutate_number(corrupt, "units", "available_shotgun_breaches", NAN), "Nonfinite reservation reaches a numeric sample")
			"reserve_owner":
				for definition: Dictionary in corrupt.states:
					if definition.group == "enemies": definition.fields.append("available_shotgun_breaches"); break
			"charge_fraction": check(_mutate_number(corrupt, "units", "available_breaches", 0.5), "Fractional charge reservation reaches a numeric sample")
			"charge_large": check(_mutate_number(corrupt, "units", "available_breaches", 10001), "Charge reservation upper-bound corruption reaches a numeric sample")
			"charge_owner":
				for definition: Dictionary in corrupt.states:
					if definition.group == "enemies": definition.fields.append("available_breaches"); break
			"event_kind": corrupt.events[0].kind = "SHOTGUN_BREACH"
			"event_door": corrupt.events[0].door_id = "missing_door"
		check(not restored.load_data(corrupt).get("ok", true), "Malformed P1 replay is rejected: " + mutation)
		check(JSON.stringify(restored.export_data()) == before, "Rejected replay preserves the active record: " + mutation)
	# Reservation metadata retains the pre-existing replay resource upper bound.
	# A valid legacy inventory above ordinary loadout caps stays fully visible.
	state.units[0].ammo = 10000
	state.units[0].breaches = 10000
	state.units[0].available_shotgun_breaches = 10000
	state.units[0].available_breaches = 10000
	state.time = 0.0
	state.tick = 0
	state.events = []
	var inventory_record := Replay.new()
	inventory_record.begin(mission)
	inventory_record.capture(state)
	state.time = STEP
	state.tick = 1
	inventory_record.finish(state)
	var inventory := Replay.new()
	check(inventory.load_data(JSON.parse_string(JSON.stringify(inventory_record.export_data()))).get("ok", false), "Derived inventories preserve the existing replay resource upper bound")
	var inventory_state: Dictionary = inventory.seek(STEP, true)
	check(inventory_state.units[0].available_breaches == 10000 and inventory_state.units[0].available_shotgun_breaches == 10000, "Large valid legacy inventories are not truncated by availability metadata")

func _mutate_static(candidate: Dictionary, group: String, key: String, value: Variant) -> void:
	for definition: Dictionary in candidate.states:
		if definition.group == group:
			definition.base[key] = value
			return

func _mutate_number(candidate: Dictionary, group: String, key: String, value: Variant) -> bool:
	var group_index: int = Replay.GROUPS.find(group) + 2
	for frame: Array in candidate.frames:
		var packed: Array = frame[group_index]
		var cursor := 0
		while cursor < packed.size():
			var length := int(packed[cursor])
			var definition: Dictionary = candidate.states[int(packed[cursor + 1])]
			var field_index: int = definition.fields.find(key)
			if field_index >= 0:
				packed[cursor + 2 + field_index] = value
				return true
			cursor += length + 1
	return false

func _test_legacy_absence() -> void:
	var mission: Dictionary = Catalog.load("M01")
	var state := _contract_state(mission)
	state.units[0].commands = [{"id":"legacy-kick", "type":"KICK_DOOR", "args":{"door_id":mission.doors[0].id}, "state":"PENDING"}]
	state.units[0].erase("available_shotgun_breaches")
	state.units[0].erase("available_breaches")
	state.enemies[0].erase("door_ready")
	state.doors[0].erase("reinforced")
	state.doors[0].erase("kick_resistance")
	var recording := Replay.new()
	recording.begin(mission)
	recording.capture(state)
	state.time = STEP
	state.tick = 1
	recording.finish(state)
	var restored := Replay.new()
	check(restored.load_data(JSON.parse_string(JSON.stringify(recording.export_data()))).get("ok", false), "Existing schema1 records without P1 optional fields remain readable")
	var decoded: Dictionary = restored.seek(STEP, true)
	check(not decoded.enemies[0].door_ready, "Legacy records default readiness to false without reconstructing hidden state")
	check(not decoded.units[0].has("available_breaches"), "Legacy replay does not fabricate reserved charges")
	check(not decoded.units[0].has("available_shotgun_breaches"), "Legacy replay does not fabricate reserved ammunition")
	check(not decoded.units[0].commands[0].args.has("fallback"), "Legacy plain kicks remain plain kicks")

func _test_schema3_inheritance() -> void:
	# Adding door data in v3 must retain v2's large maps, elevated actors,
	# physical objectives and environment metadata in the same replay format.
	var mission := {"schema_version":3, "id":"CQB_V3_INHERITANCE", "revision":1, "custom":true, "seed":3, "title":"V3 inherited geometry", "variant":"normal", "bounds":[48,40], "focus":[24,20], "rooms":[{"id":"deck", "x":24.0, "z":20.0, "w":48.0, "d":40.0, "base_height":9.0}], "walls":[], "props":[], "doors":[], "units":[{"id":"alpha", "name":"Alpha", "role":"Assault", "weapon":"standard", "x":4.0, "z":4.0, "facing":0.0}], "enemies":[], "civilians":[], "objectives":["Inspect the objective"], "environment":{"biome":"harbour", "ground_color":"#637a6b", "ground_surface":"ship_deck", "water":false, "water_level":-1.0, "time_of_day":"day", "lighting":1.0}, "interactive_targets":[{"id":"radio", "x":4.0, "z":4.0, "w":2.0, "d":2.0, "label":"Radio", "action":"inspect", "duration":0.1}], "win":[{"type":"targets_complete", "targets":["radio"]}], "fail":[{"type":"no_shots"}]}
	var validation: Dictionary = Catalog.validate_custom(mission)
	check(bool(validation.get("ok", false)), "Schema3 inherits accepted v2 geometry: " + str(validation.get("message", "")))
	if not validation.get("ok", false): return
	var sim := Simulation.new()
	sim.load_mission(mission)
	check(is_equal_approx(float(sim.units[0].get("base_height", -1.0)), 9.0), "Schema3 keeps elevated actor geometry")
	var recording := Replay.new()
	recording.begin(mission)
	recording.capture(sim.snapshot(true))
	for frame: int in range(6):
		sim.step(STEP)
		recording.capture(sim.snapshot(true))
	var final: Dictionary = sim.snapshot(true)
	recording.finish(final)
	var restored := Replay.new()
	var loaded: Dictionary = restored.load_data(JSON.parse_string(JSON.stringify(recording.export_data())))
	check(bool(loaded.get("ok", false)), "Schema3 inherits v2 replay limits and objectives: " + str(loaded.get("message", "")))
	if not loaded.get("ok", false): return
	var decoded: Dictionary = restored.seek(recording.duration, true)
	check(decoded.interactive_targets == JSON.parse_string(JSON.stringify(final.interactive_targets)), "Schema3 physical target state survives replay")
	check(decoded.environment == mission.environment and decoded.units[0].base_height == 9.0, "Schema3 environment and actor floor survive replay")
	check(decoded.events.any(func(event: Dictionary) -> bool: return event.type == "TARGET_COMPLETE"), "Schema3 accepts the inherited target-completion event")

func _test_plan_roundtrip() -> void:
	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	await process_frame
	for seed_value: int in range(30):
		# The authored baseline has no charge in its default equipment. The
		# optional fallback reserves a real charge, so its fixture equips one.
		var loadout := {"alpha":{"weapon":"shotgun", "equipment":["breach"]}, "bravo":{"weapon":"shotgun"}}
		session._action({"action":"start", "mission":"M01", "seed":seed_value, "loadout":loadout})
		var kick: Dictionary = session.sim.issue("alpha", "KICK_DOOR", {"door_id":"d1", "fallback":"breach"})
		var shotgun: Dictionary = session.sim.issue("bravo", "SHOTGUN_BREACH", {"door_id":"d1"})
		check(kick.get("ok", false), "Plan kick fallback accepted, seed %d: %s" % [seed_value, kick.get("message", "")])
		check(shotgun.get("ok", false), "Plan shotgun primitive accepted, seed %d: %s" % [seed_value, shotgun.get("message", "")])
		var exported: Dictionary = session._export_plan()
		check(exported.units[0].commands.size() == 1 and exported.units[1].commands.size() == 1, "Both P1 primitives enter the saved fresh plan")
		if exported.units[0].commands.is_empty() or exported.units[1].commands.is_empty(): continue
		check(exported.schema_version == 1 and exported.kind == "breach-plan", "P1 keeps fresh-plan format")
		session._import_plan(JSON.parse_string(JSON.stringify(exported)), false)
		check(session.sim.time == 0.0 and session.sim.tick == 0, "Plan import is a fresh start")
		check(session._export_plan() == exported, "P1 fresh-plan round trip preserves every primitive argument, seed %d" % seed_value)
		var before: String = JSON.stringify(session.sim.snapshot(true))
		for mutation: String in ["fallback", "shotgun_args"]:
			var invalid: Dictionary = exported.duplicate(true)
			if mutation == "fallback": invalid.units[0].commands[0].args.fallback = "random"
			else: invalid.units[1].commands[0].args.fallback = "breach"
			session._import_plan(invalid, false)
			check(JSON.stringify(session.sim.snapshot(true)) == before, "Invalid P1 plan preserves active simulation: " + mutation)
		var legacy: Dictionary = exported.duplicate(true)
		legacy.units[0].commands[0].args.erase("fallback")
		legacy.units[1].commands = []
		session._import_plan(legacy, false)
		check(session._export_plan() == legacy, "Existing plain-kick plan remains readable, seed %d" % seed_value)
	session.queue_free()
	await process_frame
