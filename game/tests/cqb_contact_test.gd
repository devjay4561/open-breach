extends SceneTree
## P1 checks execute player commands at fixed simulation ticks. Probability,
## contact response and whole-mission outcomes use separate controlled samples.
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Navigation = preload("res://scripts/navigation.gd")
const STEP := 1.0 / 30.0
const SEEDS := 30
class ThreatProbe extends "res://scripts/simulation.gd":
	var ready_at_first_shot := false
	func _combat(attacker: Dictionary, candidates: Array, hostile: bool, forced_target: String = "") -> void:
		var before := shots_fired
		var ready_threat := false
		if not hostile and before==0:
			for candidate: Dictionary in candidates:
				if candidate.id!="ready": continue
				var aimed_at_unit := absf(angle_difference(float(candidate.aim_facing),(_position(attacker)-_position(candidate)).angle()))<=deg_to_rad(18.0)
				ready_threat = float(candidate.hp)>0.0 and candidate.get("aim_state","")=="ready" and aimed_at_unit
		# Passive inspection only: the normal command/step pipeline selects and
		# fires its actual target, with no synthetic combat or perception calls.
		super._combat(attacker,candidates,hostile,forced_target)
		if not hostile and before==0 and shots_fired>0: ready_at_first_shot = ready_threat
var checks := 0
var failures: Array[String] = []
var report: Dictionary = {"step":STEP,"seeds":[0,29],"contact_seconds":12.0,"scope":{
	"contact":"P0 M01 geometry and plans; explicit kick_resistance=1 preserves P0's always-open frontal contact opportunity; default kick odds are tested separately.",
	"threat":"P0 two-contact geometry and initially ready distant threat; ordinary FACE and step replace P0's direct combat/observation instrumentation.",
	"house":"Complete authored normal M01, default kick probabilities and actor loadouts; common floor route and visible-only arrest/secure policy; mixed flash at d1 plus quiet internal doors.",
	"surrender":"Unique observed normal-house enemies that surrender at least once, divided by unique observed encounters in the mixed route."}}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or "--mechanics-only" in args:
		_kick_contracts()
		_wait_clearance_contracts()
		_shotgun_contracts()
		_shotgun_queue_contracts()
		_charge_contracts()
		_surrender_type_contracts()
		_rng_contracts()
	if args.is_empty() or "--contact-only" in args or "--benchmarks-only" in args:
		_contact_benchmarks()
	if args.is_empty() or "--contact-only" in args or "--threat-only" in args or "--benchmarks-only" in args:
		_threat_benchmark()
	if args.is_empty() or "--house-only" in args or "--benchmarks-only" in args:
		_house_benchmarks()
	if args.is_empty() or "--benchmarks-only" in args:
		report["checks"] = checks
		report["failures"] = failures.duplicate()
		var artifact_dir := ProjectSettings.globalize_path("res://../tests/artifacts")
		DirAccess.make_dir_recursive_absolute(artifact_dir)
		var artifact := FileAccess.open(artifact_dir.path_join("cqb-contact.json"),FileAccess.WRITE)
		check(artifact!=null,"P1 fixed-seed evidence can be written")
		if artifact!=null: artifact.store_string(JSON.stringify(report,"\t")+"\n")
	print("BREACH_CQB_CONTACT_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func simulation(data: Dictionary) -> BreachSimulation:
	var sim := Simulation.new()
	sim.load_mission(data)
	sim.enemy_rules = Catalog.NORMAL.duplicate(true)
	return sim

func issue(sim: BreachSimulation, id: String, type: String, args: Dictionary = {}) -> Dictionary:
	var answer: Dictionary = sim.issue(id, type, args)
	check(bool(answer.get("ok", false)), "seed %d %s %s accepted: %s" % [sim.mission.seed, id, type, answer.get("message", "")])
	return answer

func advance(sim: BreachSimulation, frames: int) -> void:
	for _frame: int in range(frames): sim.step(STEP)

func position(entity: Dictionary) -> Vector2:
	return Vector2(float(entity.x), float(entity.z))

func terminal(command: Dictionary) -> bool:
	return command.get("state", "") in ["SUCCEEDED", "FAILED", "CANCELLED"]

func command_events(sim: BreachSimulation, type: String, unit_id: String = "") -> Array:
	return sim.events.filter(func(event: Dictionary) -> bool:
		return str(event.type) == type and (unit_id.is_empty() or str(event.get("unit_id", "")) == unit_id))

func door_fixture(seed_value: int = 0) -> Dictionary:
	var door: Dictionary = {"id":"d1", "x":6.0, "z":6.0, "w":1.8, "d":0.24, "axis":"x", "state":"CLOSED", "hinge_side":-1.0, "swing_sign":-1.0, "hp":100.0, "locked":false}
	var origin := Door.handle_floor(door) - Vector2.DOWN * Door.APPROACH_DISTANCE
	return {"id":"CQB_CONTACT", "seed":seed_value, "bounds":[12,12],
		"walls":[{"x":2.5,"z":6.0,"w":5.2,"d":0.2}, {"x":9.5,"z":6.0,"w":5.2,"d":0.2}], "props":[],
		"rooms":[{"id":"outside","x":6.0,"z":3.0,"w":12.0,"d":6.0}, {"id":"inside","x":6.0,"z":9.0,"w":12.0,"d":6.0}], "doors":[door],
		"units":[{"id":"alpha","x":origin.x,"z":origin.y,"facing":PI*0.5,"breaches":2}], "enemies":[], "civilians":[],
		"win":[{"type":"reach_zone","zone":[11.0,11.0,0.2,0.2]}], "fail":[]}

func _kick_contracts() -> void:
	var data := door_fixture()
	data.doors[0].kick_resistance = 0.0
	var failed := simulation(data)
	var reaction_rng_before: int = failed._hit_region_rng.state
	var combat_rng_before: int = failed._rng.state
	issue(failed, "alpha", "KICK_DOOR", {"door_id":"d1"})
	var command: Dictionary = failed.units[0].commands[0]
	var started := -1.0
	var reserved := false
	for _frame: int in range(90):
		failed.step(STEP)
		if command.get("phase", "") == "KICK_RECOVER":
			if started < 0.0: started = float(command.get("_door_action_start", failed.time))
			reserved = reserved or str(failed.doors[0].owner_id) == "alpha"
		if terminal(command): break
	check(command.state == "FAILED" and started >= 0.0, "A zero-probability kick executes and fails through ordinary ticks")
	check(absf(failed.time - started - 0.6) <= STEP + 0.00001, "Failed kick spends exactly 0.6 seconds before failure")
	check(reserved and failed.doors[0].owner_id == "", "Failed kick reserves its door during recovery and releases ownership afterward")
	check(failed.doors[0].state == "CLOSED" and is_equal_approx(float(failed.doors[0].hp),100.0), "Failed kick preserves the closed leaf and its durability")
	var sounds := command_events(failed, "KICK_FAILED", "alpha")
	check(sounds.size() == 1 and is_equal_approx(float(sounds[0].get("radius",0.0)),9.0), "Failed kick publishes one nine-metre failure sound")
	check(failed._hit_region_rng.state == reaction_rng_before and failed._rng.state == combat_rng_before, "Door-only kick draws neither body-region nor accuracy/reaction randomness")
	data = door_fixture()
	data.doors[0].kick_resistance = 0.0
	var fallback := simulation(data)
	issue(fallback, "alpha", "KICK_DOOR", {"door_id":"d1", "fallback":"breach"})
	for _frame: int in range(240):
		fallback.step(STEP)
		if terminal(fallback.units[0].commands[0]): break
	check(fallback.units[0].commands[0].state == "SUCCEEDED" and bool(fallback.doors[0].destroyed), "Explicit failed-kick fallback completes the same command with a breach")
	check(int(fallback.units[0].breaches) == 1 and fallback.breaches_used == 1, "Fallback consumes exactly one owned charge")
	check(fallback.command_failures == 0 and fallback.doors[0].owner_id == "", "Successful fallback leaves no failed command or reserved door")
	data = door_fixture()
	data.units[0].breaches = 0
	var unequipped := simulation(data)
	check(not bool(unequipped.issue("alpha","KICK_DOOR",{"door_id":"d1","fallback":"breach"}).get("ok",false)), "Planning rejects a breach fallback without its owned charge")
	check(not bool(unequipped.issue("alpha","KICK_DOOR",{"door_id":"d1","fallback":"unknown"}).get("ok",false)), "Planning rejects unknown kick fallback modes")
	data = door_fixture()
	data.units[0].breaches = 1
	data.doors.append({"id":"d2","x":2.0,"z":2.0,"w":1.8,"d":0.24,"axis":"x"})
	var reservation := simulation(data)
	issue(reservation,"alpha","KICK_DOOR",{"door_id":"d1","fallback":"breach"})
	check(not bool(reservation.issue("alpha","KICK_DOOR",{"door_id":"d2","fallback":"breach"}).get("ok",false)),"A queued fallback reserves its charge against another fallback")
	check(not bool(reservation.insert_command("alpha",0,"BREACH_DOOR",{"door_id":"d2"}).get("ok",false)),"An inserted breach cannot borrow a charge reserved by a fallback")
	check(bool(reservation.update_command_args("alpha",0,{"door_id":"d1","fallback":"breach"}).get("ok",false)),"Updating the same fallback retains its existing reservation")
	issue(reservation,"alpha","CANCEL_PENDING")
	issue(reservation,"alpha","BREACH_DOOR",{"door_id":"d2"})
	data = door_fixture()
	data.doors[0].kick_resistance = 0.0
	data.units.append({"id":"bravo","x":7.0,"z":4.8,"facing":PI*0.5})
	var cooperative := simulation(data)
	issue(cooperative,"alpha","KICK_DOOR",{"door_id":"d1"})
	issue(cooperative,"bravo","OPEN_DOOR",{"door_id":"d1"})
	var premature_second_action := false
	for _frame: int in range(240):
		cooperative.step(STEP)
		if cooperative.units[0].commands[0].state != "FAILED":
			premature_second_action = premature_second_action or not command_events(cooperative,"DOOR_ACTION","bravo").is_empty()
		if terminal(cooperative.units[1].commands[0]): break
	check(not premature_second_action and cooperative.units[1].commands[0].state == "SUCCEEDED", "A second operator waits for failed-kick recovery, then can open the released door")
	for location: Array in [[6.2,6.8],[7.25,6.65]]:
		data = door_fixture()
		data.doors[0].kick_resistance = 1.0
		data.enemies = [{"id":"enemy","x":location[0],"z":location[1],"facing":-PI*0.5}]
		var swept := simulation(data)
		check(swept.nav.walkable(position(swept.enemies[0])),"Kick-sweep comparison enemy starts on legal floor")
		issue(swept,"alpha","KICK_DOOR",{"door_id":"d1"})
		swept.step(STEP)
		if float(location[0])<6.5:
			check(float(swept.enemies[0].stunned)>0.0,"A successful kick knocks down an enemy in the actual leaf sweep")
		else:
			check(float(swept.enemies[0].stunned)==0.0 and float(swept.enemies[0].get("_door_delay_until",0.0))<=swept.time,"A nearby enemy outside the leaf sweep receives no blanket kick delay")
	var totals: Dictionary = {}
	for kind: String in ["internal","external","locked"]:
		var successes := 0
		for seed_value: int in range(SEEDS):
			data = door_fixture(seed_value)
			if kind == "external": data.rooms.pop_front()
			if kind == "locked": data.doors[0].locked = true
			var sim := simulation(data)
			issue(sim,"alpha","KICK_DOOR",{"door_id":"d1"})
			for _frame: int in range(180):
				sim.step(STEP)
				if terminal(sim.units[0].commands[0]): break
			if sim.units[0].commands[0].state == "SUCCEEDED": successes += 1
			check(terminal(sim.units[0].commands[0]), kind + " kick reaches a terminal state")
		totals[kind] = successes
	check(int(totals.internal) > int(totals.external) and int(totals.external) > int(totals.locked), "Thirty fixed seeds preserve the internal/external/locked success ordering")
	check(int(totals.internal) < SEEDS and int(totals.locked) > 0, "Default kick samples include actual successes and failures")
	print("CQB_KICK_PROBABILITY " + JSON.stringify(totals))

func _wait_clearance_contracts() -> void:
	# The original flash plan's WAIT operators occupy d1's real swing. Check the
	# fix with this authored geometry rather than a synthetic movement helper.
	var data := contact_fixture("flash_entry",0)
	data.enemies = []
	var sim := simulation(data)
	contact_plan(sim,"flash_entry")
	var starts: Array[Vector2] = []
	for unit: Dictionary in sim.units: starts.append(position(unit))
	var moved := false
	var continuous := true
	var same_side := true
	var separated := true
	var timer_preserved := true
	var open_at := -1.0
	var flash_at := -1.0
	var seq := 0
	for _frame: int in range(180):
		var previous: Array[Vector2] = []
		for unit: Dictionary in sim.units: previous.append(position(unit))
		sim.step(STEP)
		for index: int in range(1,sim.units.size()):
			var unit: Dictionary = sim.units[index]
			var wait: Dictionary = unit.commands[0]
			if wait.state in ["RUNNING","WAITING"]:
				moved = moved or position(unit).distance_to(starts[index]) > 0.05
				timer_preserved = timer_preserved and absf(float(wait.remaining) - maxf(0.0,4.0-sim.time)) <= STEP + 0.00001
				same_side = same_side and float(unit.z) > 17.0
				separated = separated and not Door.overlaps_actor(sim._find(sim.doors,"d1"),-1.0,position(unit),Navigation.RADIUS)
			continuous = continuous and position(unit).distance_to(previous[index]) <= 0.081
		for event: Dictionary in sim.events:
			if int(event.seq) <= seq: continue
			if event.type == "DOOR_OPEN" and event.get("door_id","") == "d1" and open_at < 0.0: open_at = float(event.time)
			if event.type == "STUN" and flash_at < 0.0: flash_at = float(event.time)
			seq = maxi(seq,int(event.seq))
	check(moved, "An ordinary timed WAIT yields from the authored front-door swing")
	check(timer_preserved and sim.units[1].commands[0].state == "SUCCEEDED", "Door yielding never restarts or extends the four-second WAIT")
	check(continuous and same_side and separated, "WAIT yielding is continuous, stays outside, and never intersects the rotating leaf")
	check(open_at > 0.0 and open_at < 4.0 and flash_at > open_at and flash_at < 4.0, "The door and flash complete before the original four-second support WAIT expires")
	for hold: String in ["explicit","signal"]:
		data = contact_fixture("quiet_open",0)
		data.enemies = []
		data.units = data.units.slice(0,2)
		data.units[1].hold_position = hold=="explicit"
		var held := simulation(data)
		var origin := position(held.units[1])
		var in_sweep := false
		for sample: int in range(17):
			in_sweep = in_sweep or Door.overlaps_actor(held._find(held.doors,"d1"),float(sample)/16.0,origin,Navigation.RADIUS)
		check(in_sweep,hold + " wait actually occupies the authored door's future arc")
		issue(held,"bravo","WAIT" if hold=="explicit" else "WAIT_FOR_SIGNAL",{"duration":4.0} if hold=="explicit" else {"signal":"A"})
		issue(held,"alpha","OPEN_DOOR",{"door_id":"d1"})
		advance(held,105)
		check(position(held.units[1]).is_equal_approx(origin), hold + " waiting operator retains its exact held position")
		check(held.units[1].commands[0].state in ["RUNNING","WAITING"], hold + " wait is still active without elapsed duration or signal")
		check(held._find(held.doors,"d1").state!="OPEN",hold + " occupied swing prevents premature door opening")

func contact_fixture(scenario: String, seed_value: int) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var enemy: Dictionary = data.enemies[0].duplicate(true)
	enemy.erase("spawns")
	enemy.erase("patrol")
	enemy.x = 12.0
	enemy.z = 13.0
	enemy.facing = PI*0.5
	enemy.response_role = "guard"
	data.enemies = [enemy]
	data.civilians = []
	data.seed = seed_value
	data.modifiers = []
	data.stars = []
	data.fail = []
	data.win = [{"type":"reach_zone","zone":[23.0,1.0,0.2,0.2]}]
	# Isolate the guard's ability to fire from the operators' immediate return fire.
	if scenario in ["frontal_kick","default_frontal_kick"]:
		for unit: Dictionary in data.units:
			unit.ammo = 0
			unit.reserve_ammo = 0
	# P0 kicks always opened. Keep that same contact opportunity in all thirty
	# cases; default-probability failures are measured separately above and in
	# the whole-house comparison, not mixed into the door-ready response rate.
	for door: Dictionary in data.doors:
		if door.id == "d1":
			if scenario=="default_frontal_kick": door.erase("kick_resistance")
			else: door.kick_resistance = 1.0
	return data

func contact_plan(sim: BreachSimulation, scenario: String) -> void:
	var destinations := [[11.0,14.5],[13.0,14.5],[11.0,12.7],[13.0,12.7]]
	# Preserve P0's player plans, including the support WAIT before flash entry.
	for index: int in range(sim.units.size()):
		var id := str(sim.units[index].id)
		if scenario == "flash_entry":
			if index == 0: issue(sim,id,"OPEN_AND_FLASH",{"door_id":"d1","target":[12.0,13.0]})
			else:
				issue(sim,id,"WAIT",{"duration":4.0})
				issue(sim,id,"OPEN_DOOR",{"door_id":"d1"})
		else: issue(sim,id,"KICK_DOOR" if scenario in ["frontal_kick","default_frontal_kick"] else "OPEN_DOOR",{"door_id":"d1"})
		# Unarmed guard-response probes hold outside after opening the door.
		if scenario not in ["frontal_kick","default_frontal_kick"]:
			issue(sim,id,"MOVE",{"target":destinations[index]})

func contact_case(scenario: String, seed_value: int) -> Dictionary:
	var sim := simulation(contact_fixture(scenario,seed_value))
	contact_plan(sim,scenario)
	var hostile_shots := 0
	var ready_seen := false
	for _frame: int in range(360):
		var before := int(sim.enemies[0].ammo)
		sim.step(STEP)
		# Surrender discards the current magazine before combat in this tick.
		# That ammunition change is not a shot, including a final one-round mag.
		if not bool(sim.enemies[0].surrendered): hostile_shots += maxi(0,before-int(sim.enemies[0].ammo))
		ready_seen = ready_seen or bool(sim.enemies[0].get("door_ready",false))
	var opened: bool = sim._find(sim.doors,"d1").state=="OPEN"
	check(sim.tick==360 and (opened or scenario=="default_frontal_kick"),scenario + " completes its fixed contact horizon; controlled contacts all open")
	return {"shots":hostile_shots,"hits":sim.hits_taken,"ready":ready_seen,"opened":opened,"failures":sim.command_failures,"state":JSON.stringify(sim.snapshot(true)),"hit_region_rng":sim._hit_region_rng.state,"combat_rng":sim._rng.state,"breach_rng":sim._breach_rng.state,"surrender_rng":sim._surrender_rng.state}

func _contact_benchmarks() -> void:
	var summary: Dictionary = {}
	var cases: Dictionary = {}
	for scenario: String in ["frontal_kick","quiet_open","flash_entry","default_frontal_kick"]:
		var firing_cases := 0
		var hit_cases := 0
		var ready_cases := 0
		var opened_cases := 0
		var rows: Array = []
		for seed_value: int in range(SEEDS):
			var first := contact_case(scenario,seed_value)
			var second := contact_case(scenario,seed_value)
			check(first == second, scenario + " same seed repeats the complete state and four RNG streams")
			firing_cases += int(int(first.shots)>0)
			hit_cases += int(int(first.hits)>0)
			ready_cases += int(bool(first.ready))
			opened_cases += int(bool(first.opened))
			rows.append({"seed":seed_value,"shots":first.shots,"hits":first.hits,"door_ready":first.ready,"opened":first.opened,"command_failures":first.failures})
		summary[scenario] = {"firing_cases":firing_cases,"hit_cases":hit_cases,"ready_cases":ready_cases,"opened_cases":opened_cases,"cases":SEEDS}
		cases[scenario] = rows
		if scenario == "frontal_kick":
			check(firing_cases >= 18,"Heard-door four-metre frontal contact fires in at least 18/30 cases without return fire")
			check(ready_cases == SEEDS,"Every heard-door contact prepares a door-ready enemy")
		elif scenario=="default_frontal_kick":
			check(opened_cases>0 and firing_cases>=ceili(float(opened_cases)*0.6),"Default kicks permit enemy fire in at least 60% of actually opened contacts without return fire")
		else: check(hit_cases <= 4,scenario + " hits friendlies in at most 4/30 cases")
	print("CQB_CONTACT_BENCHMARK " + JSON.stringify(summary))
	report["contact"] = {"aggregate":summary,"cases":cases,"p0_firing_cases":{"frontal_kick":0,"quiet_open":0,"flash_entry":30},"p0_hit_cases":{"frontal_kick":0,"quiet_open":0,"flash_entry":19},"limits":{"frontal_min_firing_cases":18,"default_frontal_min_opened_fraction":0.6,"quiet_max_hit_cases":4,"flash_max_hit_cases":4}}

func _threat_benchmark() -> void:
	var violations := 0
	var shots := 0
	var ready_cases := 0
	var priority_cases := 0
	var rows: Array = []
	for seed_value: int in range(SEEDS):
		var sim := ThreatProbe.new()
		sim.load_mission({"id":"CQB_THREAT","seed":seed_value,"bounds":[12,12],"walls":[],"props":[],"doors":[],"rooms":[{"id":"room","x":6.0,"z":6.0,"w":10.0,"d":10.0}],"units":[{"id":"alpha","x":6.0,"z":6.0,"facing":0.0}],"enemies":[{"id":"near","x":8.0,"z":6.0,"facing":0.0},{"id":"ready","x":10.0,"z":6.0,"facing":PI}],"win":[{"type":"reach_zone","zone":[1.0,1.0,0.2,0.2]}],"fail":[]})
		sim.enemy_rules = Catalog.NORMAL.duplicate(true)
		# Match P0's auxiliary initial ready threat. There are no combat calls,
		# synthetic observations or disabled enemies: subsequent sight, reaction,
		# target selection and firing all advance through normal sim.step.
		var ready: Dictionary = sim.enemies[1]
		ready.aim_facing = PI
		ready.aim_progress = 1.0
		ready.aim_state = "ready"
		issue(sim,"alpha","FACE",{"target":[10.0,6.0]})
		for _frame: int in range(120):
			sim.step(STEP)
			if sim.shots_fired > 0: break
		check(sim.shots_fired == 1,"Priority sample emits its first actual unit shot")
		shots += sim.shots_fired
		violations += int(sim._statistics().threat_order_violations)
		var target_id := ""
		for event: Dictionary in sim.events:
			if event.type=="SHOT" and not bool(event.get("hostile",false)): target_id = str(event.get("target_id",""))
		ready_cases += int(sim.ready_at_first_shot)
		priority_cases += int(target_id=="ready")
		rows.append({"seed":seed_value,"target_id":target_id,"ready_threat":sim.ready_at_first_shot,"tick":sim.tick,"violations":int(sim._statistics().threat_order_violations)})
	check(shots == SEEDS and violations <= 6,"Observed ready-threat ordering violations decrease at least 80% from P0's 30")
	# Normal enemy updates can interrupt aim in individual samples. Preserve
	# that evidence per seed and require at least the 80% comparison sample to
	# expose a real ready threat rather than pass through absent readiness.
	check(ready_cases>=24 and priority_cases>=24,"A real distant ready threat remains at first fire and is actually prioritized in at least 24/30 cases")
	print("CQB_THREAT_BENCHMARK " + JSON.stringify({"shots":shots,"violations":violations,"ready_cases":ready_cases,"priority_cases":priority_cases,"p0_violations":30,"cases":SEEDS}))
	report["threat"] = {"shots":shots,"violations":violations,"ready_cases":ready_cases,"priority_cases":priority_cases,"p0_violations":30,"max_violations":6,"cases":rows}

func _shotgun_contracts() -> void:
	var data := door_fixture()
	data.units.append({"id":"bravo","x":7.2,"z":4.7,"facing":PI*0.5,"weapon":"shotgun"})
	var rifle := simulation(data)
	check(not bool(rifle.issue("alpha","SHOTGUN_BREACH",{"door_id":"d1"}).get("ok",false)),"A rifle operator cannot borrow a teammate's shotgun for breaching")
	data.units[0].weapon = "shotgun"
	data.units[0].ammo = 0
	var empty := simulation(data)
	check(not bool(empty.issue("alpha","SHOTGUN_BREACH",{"door_id":"d1"}).get("ok",false)),"An empty shotgun cannot reserve a breach")
	data = door_fixture()
	data.units[0].weapon = "shotgun"
	data.units[0].ammo = 1
	data.doors.append({"id":"d2","x":2.0,"z":2.0,"w":1.8,"d":0.24,"axis":"x"})
	var reservation := simulation(data)
	issue(reservation,"alpha","SHOTGUN_BREACH",{"door_id":"d1"})
	check(not bool(reservation.issue("alpha","SHOTGUN_BREACH",{"door_id":"d2"}).get("ok",false)),"A queued shotgun breach reserves its single round against a second breach")
	check(not bool(reservation.insert_command("alpha",0,"SHOTGUN_BREACH",{"door_id":"d2"}).get("ok",false)),"An inserted shotgun breach cannot reuse a reserved round")
	check(bool(reservation.update_command_args("alpha",0,{"door_id":"d1"}).get("ok",false)),"Updating a shotgun breach keeps its own round reservation")
	issue(reservation,"alpha","CANCEL_PENDING")
	issue(reservation,"alpha","SHOTGUN_BREACH",{"door_id":"d2"})
	data = door_fixture()
	data.units[0].weapon = "shotgun"
	data.units[0].ammo = 2
	data.units.append({"id":"bravo","x":7.2,"z":4.7,"facing":PI*0.5})
	data.units.append({"id":"charlie","x":7.2,"z":3.9,"facing":PI*0.5})
	data.units.append({"id":"delta","x":7.2,"z":3.1,"facing":PI*0.5})
	var sim := simulation(data)
	issue(sim,"alpha","SHOTGUN_BREACH",{"door_id":"d1"})
	var command: Dictionary = sim.units[0].commands[0]
	var started := -1.0
	var discharged := -1.0
	var continuous := true
	var same_side := true
	var reserved := false
	for _frame: int in range(300):
		var before := position(sim.units[0])
		sim.step(STEP)
		if command.get("phase","") == "SHOTGUN_PREPARE":
			if started < 0.0: started = float(command.get("_door_action_start",sim.time))
			reserved = reserved or sim.doors[0].owner_id == "alpha"
		if discharged < 0.0 and int(sim.units[0].ammo) == 1: discharged = sim.time
		continuous = continuous and before.distance_to(position(sim.units[0])) <= 0.081
		same_side = same_side and float(sim.units[0].z) < 6.0
		if terminal(command): break
	check(started >= 0.0 and discharged >= 0.0 and absf(discharged-started-1.2) <= STEP+0.00001,"Shotgun breach exposes its shooter for 1.2 seconds before discharge")
	check(int(sim.units[0].ammo)==1 and reserved,"Shotgun breach consumes one owned round and reserves the door while preparing")
	check(command.state=="SUCCEEDED" and bool(sim.doors[0].destroyed) and not bool(sim.doors[0].locked),"Successful shotgun blast destroys and unlocks its physical leaf")
	check(continuous and same_side,"Shotgun shooter continuously retreats on the original entry side")
	check(float(sim.units[0].z) <= float(sim.units[3].z)-0.65,"Shotgun shooter finishes behind the fourth stack operator")
	check(sim.doors[0].owner_id=="","Completed shotgun breach releases its door")
	var actions := command_events(sim,"DOOR_ACTION","alpha")
	check(actions.any(func(event: Dictionary) -> bool: return event.get("kind","")=="SHOTGUN_BREACH" and is_equal_approx(float(event.get("radius",0.0)),14.0)),"Shotgun discharge uses the fourteen-metre door sound")
	var penetrating_cases := 0
	for seed_value: int in range(SEEDS):
		data = door_fixture(seed_value)
		data.doors[0].material = "drywall"
		data.doors[0].resistance = 0.2
		data.units[0].weapon = "shotgun"
		data.enemies = [{"id":"enemy","x":6.612,"z":9.0,"facing":-PI*0.5,"response_role":"guard"}]
		var exposed := simulation(data)
		issue(exposed,"alpha","SHOTGUN_BREACH",{"door_id":"d1"})
		var before_shot := false
		var before_ammo := int(exposed.enemies[0].ammo)
		for _frame: int in range(100):
			exposed.step(STEP)
			if not bool(exposed.doors[0].destroyed) and int(exposed.enemies[0].ammo)<before_ammo: before_shot = true
			if exposed.units[0].commands[0].get("phase","") != "SHOTGUN_PREPARE" and int(exposed.units[0].ammo)<int(exposed.units[0].max_ammo): break
		if before_shot: penetrating_cases += 1
	check(penetrating_cases>0,"A ready enemy actually fires through a thin intact leaf during shotgun exposure")
	print("CQB_SHOTGUN_EXPOSURE " + JSON.stringify({"penetrating_cases":penetrating_cases,"cases":SEEDS}))

func planning_fingerprint(sim: BreachSimulation) -> String:
	return JSON.stringify({"state":sim.snapshot(true),"commands":sim.units[0].commands,"doors":sim.doors,"revisions":sim.plan_revisions,"sequence":sim._command_sequence,"requests":sim._requests,"insert_index":sim._insert_resource_index})

func _shotgun_queue_contracts() -> void:
	var data := door_fixture()
	data.units[0].weapon = "shotgun"
	data.units[0].ammo = 1
	data.units[0].sidearm = "pico_p1"
	data.doors.append({"id":"d2","x":2.0,"z":2.0,"w":1.8,"d":0.24,"axis":"x"})
	var running := simulation(data)
	issue(running,"alpha","SHOTGUN_BREACH",{"door_id":"d1"})
	issue(running,"alpha","WAIT",{"duration":1.0})
	running.step(STEP)
	var active: Dictionary = running.units[0].commands[0]
	check(active.get("phase","")=="SHOTGUN_PREPARE" and running.doors[0].owner_id=="alpha","Queue cancellation fixture starts an actual reserved shotgun preparation")
	issue(running,"alpha","CANCEL_PENDING")
	check(active.state=="RUNNING" and running.units[0].commands[1].state=="CANCELLED" and running.doors[0].owner_id=="alpha","Pending-only cancellation preserves the running shotgun and its owner")
	var breach_state: int = running._breach_rng.state
	running.remove_command("alpha",0)
	check(active.state=="CANCELLED" and running.doors[0].owner_id=="" and int(running.units[0].ammo)==1 and running._breach_rng.state==breach_state,"Removing a preparing shotgun releases its owner without consuming a round or success draw")
	running = simulation(data)
	issue(running,"alpha","SHOTGUN_BREACH",{"door_id":"d1"})
	running.step(STEP)
	active = running.units[0].commands[0]
	var before := planning_fingerprint(running)
	check(not bool(running.issue("alpha","SHOTGUN_BREACH",{"door_id":"missing"},false).get("ok",false)) and planning_fingerprint(running)==before,"Rejected replacement preserves the active shotgun, queue, owner and revisions")
	var replaced: Dictionary = running.issue("alpha","SHOTGUN_BREACH",{"door_id":"d2"},false)
	check(bool(replaced.get("ok",false)) and active.state=="CANCELLED" and running.doors[0].owner_id=="" and int(running.units[0].ammo)==1,"Replace-plan shotgun reuses its unspent round after cancelling the previous running preparation")
	var reloading_data := data.duplicate(true)
	reloading_data.units[0].ammo = 0
	reloading_data.units[0].reserve_ammo = 8
	var reloading := simulation(reloading_data)
	issue(reloading,"alpha","RELOAD")
	issue(reloading,"alpha","SHOTGUN_BREACH",{"door_id":"d1"})
	before = planning_fingerprint(reloading)
	reloading.reorder_command("alpha",0,1)
	check(planning_fingerprint(reloading)==before,"Moving the required reload after its shotgun breach rejects the reorder atomically")
	breach_state = reloading._breach_rng.state
	reloading.remove_command("alpha",0)
	reloading.step(STEP)
	check(reloading.units[0].commands[0].state=="FAILED" and int(reloading.units[0].ammo)==0 and not bool(reloading.doors[0].destroyed) and reloading._breach_rng.state==breach_state,"Removing a required reload leaves the shotgun unable to execute, with no ammunition or success draw consumed")
	var switching := simulation(data)
	issue(switching,"alpha","SWITCH_WEAPON",{"slot":"secondary"})
	for _frame: int in range(90):
		switching.step(STEP)
		if terminal(switching.units[0].commands[0]): break
	check(switching.units[0].active_weapon=="secondary","Weapon reorder fixture actually equips its sidearm")
	issue(switching,"alpha","SWITCH_WEAPON",{"slot":"primary"})
	issue(switching,"alpha","SHOTGUN_BREACH",{"door_id":"d1"})
	before = planning_fingerprint(switching)
	switching.reorder_command("alpha",switching.units[0].commands.size()-2,1)
	check(planning_fingerprint(switching)==before,"Moving the required primary switch after its shotgun breach preserves commands and revisions")
	var sidearm_rounds := int(switching.units[0].ammo)
	breach_state = switching._breach_rng.state
	switching.remove_command("alpha",switching.units[0].commands.size()-2)
	switching.step(STEP)
	check(switching.units[0].commands.back().state=="FAILED" and int(switching.units[0].ammo)==sidearm_rounds and int(switching.units[0].primary_ammo)==1 and not bool(switching.doors[0].destroyed) and switching._breach_rng.state==breach_state,"Removing a required primary switch cannot fire the sidearm or spend the owned shotgun round")

func _charge_contracts() -> void:
	var data := door_fixture()
	data.units.append({"id":"bravo","x":5.5,"z":4.7,"facing":PI*0.5,"hold_position":true})
	var sim := simulation(data)
	issue(sim,"bravo","WAIT_FOR_SIGNAL",{"signal":"A"})
	var planned := issue(sim,"alpha","BREACH_DOOR",{"door_id":"d1"})
	check(planned.get("warning","")=="breach_safety" and "bravo" in planned.get("warning_units",[]),"Charge planning warns about the actual nearby friendly blast exposure")
	var command: Dictionary = sim.units[0].commands[0]
	var continuous := true
	var saw_wait := false
	for _frame: int in range(180):
		var before := position(sim.units[0])
		sim.step(STEP)
		continuous = continuous and before.distance_to(position(sim.units[0]))<=0.081
		if command.get("phase","") == "BREACH_SAFE_WAIT":
			saw_wait = true
			break
	check(saw_wait and sim.doors[0].state=="CLOSED" and not bool(sim.doors[0].destroyed),"An installed charge waits while another friendly remains within two metres")
	check(position(sim.units[0]).distance_to(position(sim.doors[0]))>=2.0 and continuous,"Charge installer reaches safety by continuous path movement")
	var waited_at := sim.time
	advance(sim,30)
	check(sim.doors[0].state=="CLOSED" and command.get("phase","")=="BREACH_SAFE_WAIT" and sim.time>waited_at,"Team safety wait persists through real simulation ticks")
	# Release the signal, then issue an ordinary MOVE to clear the blast area.
	sim.release_signal("A")
	check(bool(sim.configure_unit("bravo",{"hold_position":false}).get("ok",false)),"Teammate can release explicit position hold before moving")
	issue(sim,"bravo","MOVE",{"target":[4.0,3.5]})
	for _frame: int in range(180):
		sim.step(STEP)
		if terminal(command): break
	check(command.state=="SUCCEEDED" and bool(sim.doors[0].destroyed),"The installed charge detonates once the teammate actually moves to safety")
	check(sim.units.all(func(unit: Dictionary) -> bool: return is_equal_approx(float(unit.hp),100.0)),"Safe charge detonation inflicts no friendly blast damage")
	check(int(sim.units[0].breaches)==1 and sim.breaches_used==1,"Safety waiting does not repeatedly consume the installed charge")

func _surrender_type_contracts() -> void:
	for type: String in ["rusher","hostage_taker"]:
		var sim := simulation({"id":"CQB_SURRENDER_TYPE","seed":0,"bounds":[12,12],"walls":[],"props":[],"doors":[],"rooms":[],"units":[{"id":"alpha","x":4.0,"z":6.0,"facing":0.0}],"enemies":[{"id":"enemy","x":6.0,"z":6.0,"facing":PI,"enemy_type":type,"hp":30.0}],"win":[{"type":"reach_zone","zone":[1.0,1.0,0.2,0.2]}],"fail":[]})
		issue(sim,"alpha","WAIT",{"duration":1.0})
		advance(sim,30)
		check(not bool(sim.enemies[0].surrendered) and command_events(sim,"SURRENDER").is_empty(),type + " preserves its no-wounded-surrender rule")
	var hostage := simulation({"id":"CQB_HOSTAGE_SURPRISE","seed":0,"bounds":[12,12],"walls":[],"props":[],"doors":[],"rooms":[],"units":[{"id":"alpha","x":4.0,"z":5.5,"facing":0.0},{"id":"bravo","x":4.0,"z":6.5,"facing":0.0}],"enemies":[{"id":"enemy","x":6.0,"z":6.0,"facing":0.0,"enemy_type":"hostage_taker"}],"win":[{"type":"reach_zone","zone":[1.0,1.0,0.2,0.2]}],"fail":[]})
	issue(hostage,"alpha","WAIT",{"duration":1.0})
	issue(hostage,"bravo","WAIT",{"duration":1.0})
	hostage.step(STEP)
	check(bool(hostage.enemies[0].surrendered),"Two actual observing operators retain the hostage-taker surprise surrender rule")
	var crossfire_surrenders := 0
	for seed_value: int in range(SEEDS):
		# A normal light-weapon hit leaves 40 HP. The second observing operator
		# performs an ordinary reload, isolating cross-angle suppression from
		# simultaneous lethal fire without changing enemy health or AI behavior.
		# P3 reload handoff initially borrows ALPHA's view for BRAVO's northward
		# sector. An explicit public FACE edit releases that temporary lease and
		# restores this fixture's two independent viewing directions; the reload,
		# real light hit and original healthy-suppression assertions stay intact.
		var crossfire := simulation({"id":"CQB_SURRENDER_CROSSFIRE","seed":seed_value,"bounds":[12,12],"walls":[],"props":[],"doors":[],"rooms":[],"units":[{"id":"alpha","x":4.0,"z":6.0,"facing":0.0,"weapon":"light"},{"id":"bravo","x":6.0,"z":9.0,"facing":-PI*0.5,"ammo":1,"reserve_ammo":72}],"enemies":[{"id":"enemy","x":6.0,"z":6.0,"facing":PI,"response_role":"guard"}],"win":[{"type":"reach_zone","zone":[1.0,1.0,0.2,0.2]}],"fail":[]})
		issue(crossfire,"alpha","WAIT",{"duration":2.0})
		issue(crossfire,"bravo","RELOAD")
		for _frame: int in range(90):
			var had_contact: bool = not crossfire.enemies[0].get("_observed",[]).is_empty()
			crossfire.step(STEP)
			if _frame == 0:
				check(str(crossfire.units[0].get("_reload_cover_for", "")) == "bravo" and float(crossfire.units[1].reload_remaining) > 0.0, "Actual reload initially hands BRAVO's sector to ALPHA")
				var restore_view: Dictionary = crossfire.issue("alpha", "FACE", {"target":[6.0,6.0], "persistent":true}, false)
				check(bool(restore_view.get("ok", false)), "Public FACE edit restores the independent crossfire view during actual reload")
			var enemy: Dictionary = crossfire.enemies[0]
			if bool(enemy.surrendered):
				if float(enemy.hp)>30.0 and float(enemy.suppressed)>0.0 and had_contact: crossfire_surrenders += 1
				break
			if float(enemy.hp)<=0.0: break
	check(crossfire_surrenders>0,"Actual fire suppression with two observation directions can cause surrender before the wounded threshold")

func _rng_contracts() -> void:
	for seed_value: int in range(SEEDS):
		var data := door_fixture(seed_value)
		data.doors[0].kick_resistance = 0.0
		var kicked := simulation(data)
		var idle := simulation(data)
		issue(kicked,"alpha","KICK_DOOR",{"door_id":"d1"})
		issue(idle,"alpha","WAIT",{"duration":1.0})
		advance(kicked,30)
		advance(idle,30)
		check(kicked._hit_region_rng.state==idle._hit_region_rng.state and kicked._rng.state==idle._rng.state and kicked._surrender_rng.state==idle._surrender_rng.state,"seed %d kick draw isolates AI, combat and surrender streams"%seed_value)
		check(kicked._breach_rng.state!=idle._breach_rng.state,"seed %d kick advances only its breach stream"%seed_value)
		data.doors[0].kick_resistance = 1.0
		var successful := simulation(data)
		var still := simulation(data)
		issue(successful,"alpha","KICK_DOOR",{"door_id":"d1"})
		issue(still,"alpha","WAIT",{"duration":1.0})
		advance(successful,30)
		advance(still,30)
		check(successful.units[0].commands[0].state=="SUCCEEDED" and successful._rng.state==still._rng.state and successful._hit_region_rng.state==still._hit_region_rng.state and successful._surrender_rng.state==still._surrender_rng.state,"seed %d successful kick also isolates combat, body-region and surrender streams"%seed_value)
		data = door_fixture(seed_value)
		var empty := simulation(data)
		data.enemies = [{"id":"hidden","x":6.0,"z":9.0,"facing":PI*0.5,"response_role":"guard"}]
		var with_enemy := simulation(data)
		check(with_enemy._rng.state==empty._rng.state and with_enemy._hit_region_rng.state==empty._hit_region_rng.state and with_enemy._breach_rng.state==empty._breach_rng.state,"seed %d latent surrender selection isolates combat, body-region and breach streams"%seed_value)
		check(with_enemy._surrender_rng.state!=empty._surrender_rng.state,"seed %d loading an ordinary enemy draws only its susceptibility stream"%seed_value)

func house_issue(sim: BreachSimulation, id: String, type: String, args: Dictionary = {}) -> void:
	if not sim.result.is_empty() or sim.pause_requested: return
	# A lost operator is an actual benchmark outcome. Its subsequent route
	# cannot run, and the complete mission still must win to count as a clear.
	for unit: Dictionary in sim.units:
		if unit.id==id and float(unit.hp)<=0.0: return
	issue(sim,id,type,args)

func house_move(sim: BreachSimulation, id: String, target: Array) -> void:
	house_issue(sim,id,"FACE",{"unlock":true})
	house_issue(sim,id,"MOVE",{"target":target})

func house_face(sim: BreachSimulation, id: String, target: Array) -> void:
	house_issue(sim,id,"FACE",{"target":target})

func house_door(sim: BreachSimulation, id: String, door_id: String, strategy: String) -> void:
	house_issue(sim,id,"FACE",{"unlock":true})
	if strategy=="mixed" and door_id=="d1":
		house_issue(sim,id,"OPEN_AND_FLASH",{"door_id":door_id,"target":[12.0,13.0]})
	else: house_issue(sim,id,"KICK_DOOR" if strategy=="pure_kick" else "OPEN_DOOR",{"door_id":door_id})

func arrest_observed(sim: BreachSimulation, state: Dictionary) -> void:
	for enemy: Dictionary in state.enemies:
		if not bool(enemy.get("visible",false)) or enemy.get("status","")!="SURRENDERED" or bool(enemy.get("arrested",false)): continue
		var already := false
		for unit: Dictionary in state.units:
			for command: Dictionary in unit.commands:
				if command.type=="ARREST" and command.args.get("enemy_id","")==enemy.id and command.state in ["PENDING","RUNNING","WAITING"]: already = true
		if already: continue
		var operator: Dictionary = {}
		var shortest := INF
		for unit: Dictionary in state.units:
			if float(unit.hp)<=0.0 or float(unit.get("stunned",0.0))>0.0: continue
			if unit.commands.any(func(command: Dictionary) -> bool: return command.state=="FAILED" or (command.type=="ARREST" and command.state in ["PENDING","RUNNING","WAITING"])): continue
			var origin := position(unit)
			var route: Array = sim.nav.approach(origin,enemy,1.0)
			if route.is_empty(): continue
			var length := 0.0
			for coordinate: Array in route:
				var next := Vector2(float(coordinate[0]),float(coordinate[1]))
				length += origin.distance_to(next)
				origin = next
			if length<shortest:
				shortest = length
				operator = unit
		if not operator.is_empty():
			house_face(sim,str(operator.id),[enemy.x,enemy.z])
			house_issue(sim,str(operator.id),"ARREST",{"enemy_id":enemy.id})

func house_advance(sim: BreachSimulation, seconds: float, encountered: Dictionary, surrendered: Dictionary) -> void:
	for frame: int in range(ceili(seconds/STEP)):
		if not sim.result.is_empty() or sim.pause_requested: return
		if frame%3==0:
			var state := sim.snapshot(false)
			for enemy: Dictionary in state.enemies:
				if bool(enemy.get("visible",false)): encountered[str(enemy.id)] = true
				if bool(enemy.get("surrendered",false)): surrendered[str(enemy.id)] = true
			arrest_observed(sim,state)
		sim.step(STEP)

func house_secure(sim: BreachSimulation, id: String, civilian_id: String) -> void:
	if not sim.result.is_empty() or sim.pause_requested: return
	for civilian: Dictionary in sim.snapshot(false).civilians:
		if civilian.id==civilian_id and bool(civilian.get("visible",false)):
			house_issue(sim,id,"SECURE_CIVILIAN",{"civilian_id":civilian_id})
			return

func house_case(strategy: String, seed_value: int) -> Dictionary:
	# Preserve M01's complete authored mission, actors, equipment and rules. The
	# route is the existing full-house smoke route. Mixed uses a flash at d1 and
	# quiet internal openings; only the door method changes between strategies.
	# observed arrests use the same public API and policy in both strategies.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	data.seed = seed_value
	var sim := simulation(data)
	var encountered: Dictionary = {}
	var surrendered: Dictionary = {}
	house_door(sim,"alpha","d1",strategy)
	house_move(sim,"alpha",[11.2,13.6])
	house_face(sim,"alpha",[12.0,10.0])
	house_advance(sim,5.5,encountered,surrendered)
	house_move(sim,"bravo",[13.2,13.6])
	house_face(sim,"bravo",[15.0,13.6])
	house_advance(sim,4.5,encountered,surrendered)
	house_move(sim,"charlie",[11.8,15.6])
	house_face(sim,"charlie",[9.0,13.6])
	house_issue(sim,"delta","WAIT",{"duration":1.8})
	house_move(sim,"delta",[13.0,15.6])
	house_face(sim,"delta",[15.0,13.6])
	house_advance(sim,5.0,encountered,surrendered)
	house_door(sim,"alpha","d2",strategy)
	house_move(sim,"alpha",[7.7,12.2])
	house_face(sim,"alpha",[4.8,11.6])
	house_door(sim,"bravo","d3",strategy)
	house_move(sim,"bravo",[16.6,12.1])
	house_face(sim,"bravo",[19.5,12.0])
	house_advance(sim,7.0,encountered,surrendered)
	house_door(sim,"alpha","d7",strategy)
	house_move(sim,"alpha",[6.6,6.2])
	house_face(sim,"alpha",[4.4,8.5])
	house_door(sim,"charlie","d4",strategy)
	house_move(sim,"charlie",[12.0,7.0])
	house_face(sim,"charlie",[13.0,4.8])
	house_advance(sim,8.0,encountered,surrendered)
	house_move(sim,"alpha",[7.5,6.5])
	house_face(sim,"alpha",[7.5,4.0])
	house_advance(sim,2.5,encountered,surrendered)
	house_secure(sim,"alpha","c1")
	house_door(sim,"charlie","d6",strategy)
	house_move(sim,"charlie",[17.0,7.0])
	house_face(sim,"charlie",[19.3,7.5])
	house_advance(sim,7.0,encountered,surrendered)
	house_move(sim,"charlie",[19.2,6.7])
	house_face(sim,"charlie",[19.8,4.5])
	house_advance(sim,2.5,encountered,surrendered)
	house_secure(sim,"charlie","c2")
	house_advance(sim,18.0,encountered,surrendered)
	return {"seed":seed_value,"clear":bool(sim.result.get("success",false)),"encounters":encountered.size(),"surrenders":surrendered.size(),"neutralized":int(sim.snapshot().objectives.neutralized),"rescued":int(sim.snapshot().objectives.rescued),"failures":sim.command_failures,"time":sim.time}

func _house_benchmarks() -> void:
	var summary: Dictionary = {}
	var cases: Dictionary = {}
	for strategy: String in ["pure_kick","mixed"]:
		var clears := 0
		var encounters := 0
		var surrenders := 0
		var rows: Array = []
		for seed_value: int in range(SEEDS):
			var row := house_case(strategy,seed_value)
			rows.append(row)
			clears += int(bool(row.clear))
			encounters += int(row.encounters)
			surrenders += int(row.surrenders)
		summary[strategy] = {"clears":clears,"encounters":encounters,"surrenders":surrenders,"cases":SEEDS}
		cases[strategy] = rows
		print("CQB_HOUSE_CASES " + strategy + " " + JSON.stringify(rows))
	check(int(summary.mixed.clears)>int(summary.pure_kick.clears),"A complete authored-house route clears more often with mixed methods than default-probability kicks alone")
	var rate := float(summary.mixed.surrenders)/maxi(1,int(summary.mixed.encounters))
	check(int(summary.mixed.encounters)>0 and rate>=0.15 and rate<=0.30,"Actual normal-difficulty basic-house encounters surrender between 15% and 30%")
	print("CQB_HOUSE_BENCHMARK " + JSON.stringify(summary))
	report["house"] = {"aggregate":summary,"cases":cases,"surrender_rate":rate,"min_surrender_rate":0.15,"max_surrender_rate":0.30}
