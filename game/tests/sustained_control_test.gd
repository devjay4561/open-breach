extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Field = preload("res://scripts/visibility_field.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture() -> Dictionary:
	return {"id":"M01", "seed":51, "bounds":[12,12], "walls":[], "props":[], "doors":[], "rooms":[], "units":[{"id":"alpha","x":2.0,"z":6.0,"facing":0.0,"ammo":0,"stuns":2}], "enemies":[], "civilians":[], "win":[{"type":"reach_zone","zone":[10,10,1,1]}], "fail":[{"type":"no_civilian_loss"}]}

func simulation(data: Dictionary = {}) -> RefCounted:
	var sim := Simulation.new()
	sim.load_mission(fixture() if data.is_empty() else data)
	return sim

func run() -> void:
	_rules()
	_seed()
	_commands()
	_doors()
	_loadout()
	_smoke()
	print("BREACH_SUSTAINED_CONTROL_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _rules() -> void:
	var data: Dictionary = fixture()
	data.win = [{"type":"reach_zone","zone":[2,6,1,1]},{"type":"before_alert"},{"type":"time_limit","seconds":2}]
	var sim: RefCounted = simulation(data)
	sim.step(STEP)
	check(bool(sim.result.get("success", false)), "Zone + before-alert + deadline win uses authored rules")
	for key: String in ["stuns_used","reloads","hits_taken","units_deployed","first_alert_time","arrests","kills","unlawful_shots","seed","variant","modifiers"]:
		check(sim.result.has(key), "Result includes " + key)
	data.win = [{"type":"reach_zone","zone":[10,10,1,1]}]
	data.fail = [{"type":"time_limit","seconds":0.1}]
	sim = simulation(data)
	for i: int in range(5): sim.step(STEP)
	check(not bool(sim.result.get("success", true)) and sim.result.get("reason", "") == "제한 시간 초과", "Deadline failure is independent of kill count")
	data.fail = [{"type":"before_alert"}]
	sim = simulation(data)
	sim.first_alert_time = 0.0
	sim.step(STEP)
	check(not bool(sim.result.get("success", true)), "Previously alerted mission fails infiltration")
	data.fail = [{"type":"no_civilian_loss"}]
	data.civilians = [{"id":"c1","x":3,"z":6,"hp":0}]
	sim = simulation(data)
	sim.step(STEP)
	check(sim.result.get("reason", "") == "필수 민간인 목표 실패", "Civilian loss rule fails")
	data.civilians = [{"id":"c1","x":3,"z":6,"secured":true}]
	data.win = [{"type":"escort_to_zone","zone":[3,6,2,2]}]
	sim = simulation(data)
	sim.step(STEP)
	check(bool(sim.result.get("success", false)), "Escorted civilians in zone satisfy escort goal")
	data.enemies = [{"id":"e1","x":4,"z":6,"arrested":true}]
	data.win = [{"type":"neutralize_all"},{"type":"secure_all_civilians"}]
	sim = simulation(data)
	sim.step(STEP)
	check(bool(sim.result.get("success", false)) and sim.result.neutralized == 1, "Arrest counts as neutralized without a kill")
	check(sim.result.kills == 0, "Arrest success has zero kills")

func _seed() -> void:
	for id: String in ["M01","M02","M03"]:
		var data: Dictionary = Catalog.load(id)
		var a := simulation(data)
		for i: int in range(a.enemies.size()):
			check(a.enemies[i].x == data.enemies[i].x and a.enemies[i].z == data.enemies[i].z, id+" fixed seed preserves original spawn")
		data.seed = 7331
		var b := simulation(data)
		var c := simulation(data)
		check(JSON.stringify(b.snapshot(true)) == JSON.stringify(c.snapshot(true)), id+" seeded initial state deterministic")
		check(JSON.stringify(a.enemies) != JSON.stringify(b.enemies), id+" different seed changes enemy candidates")
		for i: int in range(60):
			b.step(STEP)
			c.step(STEP)
		check(JSON.stringify(b.snapshot(true)) == JSON.stringify(c.snapshot(true)), id+" same seed same commands deterministic ticks")

func _commands() -> void:
	var duplicate_sim: RefCounted = simulation()
	var inserted: Dictionary = duplicate_sim.insert_command("alpha", 0, "WAIT", {"duration":5,"request_id":"insert-once"})
	var before_duplicate: String = JSON.stringify(duplicate_sim.snapshot())
	check(duplicate_sim.insert_command("alpha", 0, "WAIT", {"duration":5,"request_id":"insert-once"}) == inserted, "Repeated insertion returns cached response")
	check(JSON.stringify(duplicate_sim.snapshot()) == before_duplicate, "Repeated insertion preserves entire queue")
	var sim: RefCounted = simulation()
	check(bool(sim.plan_move("alpha", {"target":[4,6]}, true).ok), "Initial move accepted")
	check(bool(sim.insert_command("alpha", 1, "WAIT", {"duration":3}).ok), "Wait insertion accepted")
	check(bool(sim.insert_command("alpha", 1, "FACE", {"target":[4,7]}).ok), "Face inserts directly after waypoint")
	check(sim.units[0].commands[1].type == "FACE" and sim.units[0].commands[2].type == "WAIT", "Inserted queue order preserved")
	for i: int in range(3): check(sim.units[0].commands[i].sequence == i + 1, "Insertion resequences commands")
	check(bool(sim.update_command_args("alpha", 0, {"target":[4,8]}).ok), "Pending destination edit accepted")
	check(sim.units[0].commands[0].path.back() == [4.0,8.0], "Destination edit recalculates preview")
	var previous: String = JSON.stringify(sim.snapshot())
	check(not bool(sim.update_command_args("alpha", 0, {"target":[20,20]}).ok), "Outside-map update rejected")
	check(JSON.stringify(sim.snapshot()) == previous, "Rejected update preserves exact state")
	check(not bool(sim.insert_command("alpha", 99, "WAIT", {}).ok), "Outside-index insertion rejected")
	check(not bool(sim.insert_command("alpha", 0, "UNKNOWN", {}).ok), "Unknown insertion rejected")
	sim.step(STEP)
	check(sim.plan_revisions == 0, "Initial planning excluded from revision star")
	check(sim.units_deployed == 1, "Deployed counts participants rather than selected roster")
	check(not bool(sim.insert_command("alpha", 0, "WAIT", {}).ok), "Cannot insert before running command")
	check(not bool(sim.update_command_args("alpha", 0, {"target":[5,8]}).ok), "Cannot edit running args")
	sim.issue("alpha", "WAIT", {"duration":1})
	check(sim.plan_revisions == 1, "Live edit counts one plan revision")
	sim = simulation()
	for i: int in range(32): sim.issue("alpha", "WAIT", {"duration":1})
	check(not bool(sim.insert_command("alpha", 32, "WAIT", {}).ok), "32-command upper limit on insertion")
	var data: Dictionary = fixture()
	data.walls = [{"x":6,"z":6,"w":1,"d":3}]
	sim = simulation(data)
	sim.plan_move("alpha", {"target":[4,6]}, true)
	previous = JSON.stringify(sim.snapshot())
	check(not bool(sim.update_command_args("alpha", 0, {"target":[6,6]}).ok), "Wall destination rejected")
	check(JSON.stringify(sim.snapshot()) == previous, "Wall rejection preserves arguments and preview")
	var points: Array = []
	for i: int in range(100): points.append([2.0 + float(i) * 0.08, 6.0])
	sim = simulation(data)
	var response: Dictionary = sim.plan_drag("alpha", points, true)
	check(bool(response.ok) and int(response.accepted) <= 32, "Dense drawn path simplifies to at most32 commands")
	for command: Dictionary in sim.units[0].commands:
		var origin := Vector2(2,6)
		for point: Array in command.path:
			check(sim.nav.segment_clear(origin, Vector2(point[0],point[1]), sim.nav.RADIUS), "Drawn route uses validated wall detour")
			origin = Vector2(point[0],point[1])
	sim = simulation()
	response = sim.plan_drag("alpha", [[3,6],[4,7],[20,6]], true)
	check(not bool(response.ok) and response.accepted == 2, "Partially invalid drawn route stops with accepted count")

func door_fixture() -> Dictionary:
	var data: Dictionary = fixture()
	data.units[0].x = 5.544
	data.units[0].z = 6.4
	data.units[0].facing = -PI * 0.5
	# P1: preserve successful interaction timing/navigation independently of
	# the kick probability experiment in the doctrine suite.
	data.doors = [{"id":"d1","x":5,"z":6,"w":1.6,"d":0.2,"axis":"x","state":"CLOSED","kick_resistance":1.0}]
	return data

func _doors() -> void:
	var elapsed: Dictionary = {}
	for type: String in ["OPEN_DOOR","KICK_DOOR","PEEK_DOOR"]:
		var sim: RefCounted = simulation(door_fixture())
		sim._door_observations["d1"] = sim.doors[0].duplicate(true)
		var context: Dictionary = sim.context_actions("alpha","door","d1")
		# P1 adds one primitive while preserving every existing context action.
		check(context.actions == ["OPEN_DOOR","OPEN_AND_FLASH","KICK_DOOR","PEEK_DOOR","HOLD_AT_DOOR","SHOTGUN_BREACH"], "Closed door context preserves existing actions and offers shotgun breaching")
		check(context.disabled.has("SHOTGUN_BREACH") and not str(context.disabled.SHOTGUN_BREACH).is_empty(), "Standard weapon exposes the shotgun breach requirement as a disabled reason")
		check(bool(sim.issue("alpha",type,{"door_id":"d1"}).ok), type+" accepted")
		for i: int in range(120):
			sim.step(STEP)
			if sim.units[0].commands[0].state == "SUCCEEDED": break
		check(sim.units[0].commands[0].state == "SUCCEEDED", type+" finishes timed interaction")
		elapsed[type] = sim.time
		if type == "PEEK_DOOR":
			check(sim.doors[0].state == "AJAR" and float(sim.doors[0].progress) > 0.22, "Peek physically opens a partial gap")
			check(sim.events.any(func(event: Dictionary) -> bool: return event.type == "DOOR_ACTION" and float(event.radius) == 2.0), "Peek produces the quiet physical latch sound")
		else:
			check(sim.doors[0].state == "OPEN", type+" opens door")
			var radius: float = 2.0 if type == "OPEN_DOOR" else 9.0
			check(sim.events.any(func(event: Dictionary) -> bool: return event.type == "DOOR_ACTION" and float(event.radius) == radius), type+" distinct sound radius")
	check(elapsed.KICK_DOOR < elapsed.OPEN_DOOR and elapsed.OPEN_DOOR < elapsed.PEEK_DOOR, "Kick/open/peek timings differ")
	var sim: RefCounted = simulation(door_fixture())
	check(sim.context_actions("","door","d1").actions.is_empty(), "No selected unit context refuses")
	sim._door_observations.clear()
	check(sim.context_actions("alpha","door","d1").actions.is_empty(), "Unobserved door has no context")
	sim.doors[0].state = "OPEN"
	sim._door_observations.d1 = sim.doors[0].duplicate(true)
	check(sim.context_actions("alpha","door","d1").disabled.has("PEEK_DOOR"), "Open-door peek disabled reason")
	for type: String in ["OPEN_DOOR","KICK_DOOR","PEEK_DOOR"]:
		var data: Dictionary = Catalog.load("M01")
		# This case retains the real authored approach geometry and isolates its
		# handle-gap contract from P1's probabilistic first kick.
		data.doors[0].kick_resistance = 1.0
		var authored: RefCounted = simulation(data)
		check(bool(authored.issue("alpha",type,{"door_id":"d1"}).ok), "M01 " + type + " initial approach accepted")
		for i: int in range(30 * 8):
			authored.step(STEP)
			if authored.units[0].commands[0].state == "SUCCEEDED": break
		check(authored.units[0].commands[0].state == "SUCCEEDED", "M01 " + type + " closes precise handle gap after navigation arrival")

func _loadout() -> void:
	var data: Dictionary = fixture()
	data.roster = [{"id":"raven","name":"레이븐","base_id":"alpha","trait":"breacher"}]
	data.loadout = {"alpha":{"weapon":"suppressed","equipment":{"stun":0,"smoke":1,"breach":1}}}
	data.modifiers = ["night","low_ammo","fast_reaction","no_stun"]
	var sim: RefCounted = simulation(data)
	var unit: Dictionary = sim.units[0]
	check(unit.id == "alpha" and unit.roster_id == "raven", "Roster identity preserves map unit ID")
	check(unit.weapon == "suppressed" and unit.smokes == 1 and unit.breaches == 1, "Weapon/equipment selection applied")
	check(unit.ammo == 9 and sim.mission.environment.time_of_day == "night" and sim.effective_vision_range(unit) < unit.vision_range and unit.stuns == 0, "Combined modifiers applied once")
	check(sim.enemy_rules.reaction_max == 0.26, "Fast reaction modifier uses real reaction fields")
	check(Simulation.WEAPONS.suppressed.ammo < Simulation.WEAPONS.standard.ammo and Simulation.WEAPONS.suppressed.reload > Simulation.WEAPONS.standard.reload, "Suppressed quiet benefit has capacity/reload costs")
	data.loadout = {"alpha":{"equipment":{}}}
	data.modifiers = []
	sim = simulation(data)
	check(sim.units[0].stuns == 0 and sim.units[0].smokes == 0 and sim.units[0].breaches == 0, "Explicit empty equipment clears legacy stock")
	data.units[0].ammo = 5
	data.modifiers = ["low_ammo"]
	sim = simulation(data)
	check(sim.units[0].ammo == 2, "Low-ammo halves authored stock rather than full capacity")

func _smoke() -> void:
	var data: Dictionary = fixture()
	data.loadout = {"alpha":{"equipment":{"smoke":1}}}
	var sim: RefCounted = simulation(data)
	check(bool(sim.issue("alpha","THROW_SMOKE",{"target":[5,6]}).ok), "Smoke equipment command accepted")
	for i: int in range(15): sim.step(STEP)
	check(sim.units[0].smokes == 0 and sim.snapshot().smoke_zones.size() == 1, "Smoke consumes inventory and records zone")
	check(not sim.can_see(sim.units[0], {"x":8,"z":6,"hp":100}), "Smoke blocks observation")
	var field := Field.new()
	field.build(data)
	field.update(sim.snapshot().units, [], sim.snapshot().smoke_zones)
	check(not field.contains(Vector2(8,6)), "Floor observation mask also blocks smoke")
	for i: int in range(122): sim.step(STEP)
	check(sim.snapshot().smoke_zones.is_empty(), "Smoke expires after4 seconds")
	check(sim.can_see(sim.units[0], {"x":8,"z":6,"hp":100}), "Visibility restored after smoke expiry")
