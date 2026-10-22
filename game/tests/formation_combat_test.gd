extends SceneTree
## P4 compares public primitive plans on P0's unchanged M01 corridor fixture.
## The observer calls each normal combat/solution function exactly once and
## reads actual ammunition consumption; it never supplies a target or a pose.
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Navigation = preload("res://scripts/navigation.gd")
const CombatSpatial = preload("res://scripts/spatial_profile.gd")
const STEP := 1.0 / 30.0
const TICKS := 360
const SEEDS := 30
const ORDER: Array[String] = ["alpha", "bravo", "charlie", "delta"]
const FORMATION_ORDER: Array[String] = ["alpha", "charlie", "bravo", "delta"]
const TARGET := [12.0, 10.8]
const P0_FRIENDLY_FIRST_CASES := 0
const STACK_ARRIVAL_TOLERANCE := 0.08
const DISTANCE_EPSILON := 0.00001

class PassiveCombatProbe extends "res://scripts/simulation.gd":
	var actual_shots: Array = []
	var chosen_solutions: Dictionary = {}
	var actual_targets: Dictionary = {}
	var combat_trace: Array = []
	var target_calls := 0
	var solution_calls := 0
	func _combat_target(attacker: Dictionary, candidates: Array, hostile: bool, forced_target: String = "") -> Dictionary:
		var answer: Dictionary = super._combat_target(attacker,candidates,hostile,forced_target)
		target_calls += 1
		actual_targets[str(attacker.id)] = {"tick":tick,"target_id":str(answer.get("id",""))}
		return answer
	func _shot_solution(attacker: Dictionary, target: Dictionary, choose_hit: bool = false) -> Dictionary:
		var answer: Dictionary = super._shot_solution(attacker, target, choose_hit)
		if choose_hit:
			solution_calls += 1
			chosen_solutions[str(attacker.id)] = {"solution":answer.duplicate(true),"target_id":str(target.id),"visible":bool(target.get("visible",false)),"seen":can_see(attacker,target),"identified":observation_ready(attacker,target)}
		return answer
	func _combat(attacker: Dictionary, candidates: Array, hostile: bool, forced_target: String = "") -> void:
		var before := int(attacker.ammo)
		var target_before := target_calls
		var solution_before := solution_calls
		super._combat(attacker, candidates, hostile, forced_target)
		if "--probe-only" in OS.get_cmdline_user_args() and tick<=35:
			# Read the results of the normal target/shot calls made by super;
			# this observer never performs a second acquisition or shot attempt.
			combat_trace.append({"tick":tick,"attacker_id":str(attacker.id),"hostile":hostile,"position":[attacker.x,attacker.z],"facing":attacker.facing,"body_facing":attacker.body_facing,"aim_facing":attacker.aim_facing,"aim_progress":attacker.aim_progress,"aim_state":attacker.aim_state,"status":attacker.status,"reaction":attacker.get("_reaction",0.0),"target_scanned":target_calls>target_before,"target":actual_targets.get(str(attacker.id),{}).duplicate(true),"physical_shot_attempt":solution_calls>solution_before,"solution":chosen_solutions.get(str(attacker.id),{}).duplicate(true) if solution_calls>solution_before else {},"fired":before-int(attacker.ammo)==1})
		if before - int(attacker.ammo) != 1: return
		var chosen: Dictionary = chosen_solutions.get(str(attacker.id), {})
		var solution: Dictionary = chosen.get("solution",{})
		var friends: Array = enemies if hostile else units
		actual_shots.append({"index":actual_shots.size(),"tick":tick,"time":time,"hostile":hostile,
			"attacker_id":str(attacker.id),"target_id":str(chosen.get("target_id","")),"grip":[attacker.x,attacker.z],"solution":solution.duplicate(true),"aim_state":str(attacker.aim_state),"visible":bool(chosen.get("visible",false)),"seen":bool(chosen.get("seen",false)),"identified":bool(chosen.get("identified",false)),
			"friends":friends.filter(func(actor: Dictionary) -> bool: return str(actor.id)!=str(attacker.id) and float(actor.hp)>0.0).map(func(actor: Dictionary) -> Dictionary: return {"id":str(actor.id),"position":[actor.x,actor.z],"height":CombatSpatial.body_height(actor),"base_height":float(actor.get("base_height",0.0))})})

var checks := 0
var failures: Array[String] = []
var report: Dictionary = {"step":STEP,"ticks":TICKS,"seeds":[0,29],"p0_friendly_first_cases":P0_FRIENDLY_FIRST_CASES,
	"scope":"M01 P0 central h_entry passage: every authored wall/prop/room/door and original four loadouts; d1/d2 OPEN; normal guard e2 at [7.8,13.6] east; starts [11.4+0.7*rank,15.7] north. Manual is the exact P0 MOVE target [10.8+0.8*rank,10.8]. The fixed player plan selects SERPENTINE with alpha/charlie/bravo/delta, assigning the existing light weapon to left cover, and targets the original representative point [12,10.8]. Wide-corridor AUTO still recommends ROLLING_T. Each executes 360 fixed STEP, twice per seed. A separately labelled authored patrol case uses AUTO and original alpha/bravo/charlie/delta order to test an actual side-door crossing."}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

func position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x),float(actor.z))

func _state_fingerprint(sim: Simulation) -> String:
	return JSON.stringify({"state":sim.snapshot(true),"rng":[sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]}).sha256_text()

func _passive_observer_contract() -> void:
	# The probe's extra LOS reads must not change combat, caches exposed in the
	# replay, or any of the four independent random streams.
	var normal := Simulation.new()
	var observed := PassiveCombatProbe.new()
	normal.load_mission(fixture(0))
	observed.load_mission(fixture(0))
	normal.enemy_rules = Catalog.NORMAL.duplicate(true)
	observed.enemy_rules = Catalog.NORMAL.duplicate(true)
	for index: int in range(4):
		var args := {"target":[10.8+index*0.8,10.8]}
		check(bool(normal.issue(ORDER[index],"MOVE",args).get("ok",false)) and bool(observed.issue(ORDER[index],"MOVE",args).get("ok",false)),"Passive observer receives the exact public manual plan")
	var same := true
	for frame: int in range(TICKS):
		normal.step(STEP)
		observed.step(STEP)
		same = same and _state_fingerprint(normal)==_state_fingerprint(observed)
	check(not observed.actual_shots.is_empty(),"Passive observer equivalence exercises actual ammunition-consuming combat")
	check(same,"Passive observation preserves every fixed STEP's full state and all four RNG streams")

func fixture(seed_value: int, patrol: bool = false) -> Dictionary:
	if patrol: return patrol_fixture(seed_value)
	# This is the exact P0 corridor fixture, including P0's ordinary e1 profile
	# renamed e2. Removing other encounters prevents an early result or another
	# room's later engagement from changing the first-contact comparison.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var enemy: Dictionary = data.enemies[0].duplicate(true)
	enemy.erase("spawns")
	enemy.erase("patrol")
	enemy.id = "e2"
	enemy.x = 7.8
	enemy.z = 13.6
	enemy.facing = 0.0
	enemy.response_role = "guard"
	data.enemies = [enemy]
	data.civilians = []
	data.seed = seed_value
	data.modifiers = []
	data.stars = []
	data.fail = []
	data.win = [{"type":"reach_zone","zone":[23.0,1.0,0.2,0.2]}]
	for index: int in range(data.units.size()):
		data.units[index].x = 11.4 + index * 0.7
		data.units[index].z = 15.7
		data.units[index].facing = -PI * 0.5
	for door: Dictionary in data.doors:
		if str(door.id) in ["d1","d2"]: door.state = "OPEN"
	return data

func patrol_fixture(seed_value: int) -> Dictionary:
	# Separate completion evidence: a normal patrol physically leaves a side
	# room through d2, then follows the authored return screen to its north
	# end. Unlike a short mouth wing, it keeps both matched plans' real body
	# samples occluded until the NPC physically crosses the door plane.
	# hides the approach until AFTER the real door-plane crossing. It prevents
	# a pre-crossing surprise surrender from substituting for an emerging NPC;
	# normal surrender, hit, aim and reaction rules remain enabled throughout.
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var units: Array = authored.units.duplicate(true)
	for index: int in range(4):
		units[index].x = 11.4 + index*0.7
		units[index].z = 13.6
		units[index].facing = -PI*0.5
	var enemy: Dictionary = authored.enemies[0].duplicate(true)
	enemy.erase("spawns")
	enemy.id = "e2"
	enemy.x = 8.0
	enemy.z = 7.0
	enemy.facing = 0.0
	enemy.response_role = "patrol"
	enemy.patrol = [[10.35,7.0],[10.35,6.4],[11.7,6.4],[11.7,8.2]]
	return {"id":"P4_SIDE_PATROL","seed":seed_value,"variant":"normal","bounds":[16,16],
		"rooms":[{"id":"corridor","x":12.0,"z":8.0,"w":4.0,"d":14.0,"floor_surface":"wood"},{"id":"side","x":7.5,"z":7.0,"w":5.0,"d":4.0,"floor_surface":"wood"}],
		"walls":[{"id":"west_north","x":10.0,"z":3.55,"w":0.2,"d":5.1},{"id":"west_south","x":10.0,"z":11.45,"w":0.2,"d":7.1},{"id":"east","x":14.0,"z":8.0,"w":0.2,"d":14.0},{"id":"side_north","x":7.5,"z":5.0,"w":5.0,"d":0.2},{"id":"side_south","x":7.5,"z":9.0,"w":5.0,"d":0.2},{"id":"side_west","x":5.0,"z":7.0,"w":0.2,"d":4.0},{"id":"screen","x":10.8,"z":10.9,"w":0.2,"d":8.2}],
		"doors":[{"id":"d2","x":10.0,"z":7.0,"w":0.2,"d":1.8,"axis":"z","state":"OPEN","hinge_side":-1.0,"swing_sign":-1.0,"material":"wood"}],
		"props":[],"units":units,"enemies":[enemy],"civilians":[],"win":[{"type":"reach_zone","zone":[15.5,15.5,0.1,0.1]}],"fail":[]}

func _fixture_contracts() -> void:
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var data := fixture(0)
	for field: String in ["bounds","walls","props","rooms"]:
		check(JSON.stringify(data[field])==JSON.stringify(authored[field]),"P0 corridor preserves every authored " + field)
	for index: int in range(4):
		var unit: Dictionary = data.units[index].duplicate(true)
		var original: Dictionary = authored.units[index].duplicate(true)
		for field: String in ["x","z","facing"]:
			unit.erase(field)
			original.erase(field)
		check(JSON.stringify(unit)==JSON.stringify(original),"P0 original equipment/stance/pace preserved: " + str(unit.id))
	for index: int in range(data.doors.size()):
		var expected: Dictionary = authored.doors[index].duplicate(true)
		if str(expected.id) in ["d1","d2"]: expected.state = "OPEN"
		check(JSON.stringify(data.doors[index])==JSON.stringify(expected),"Only P0's initial d1/d2 opening changes authored door " + str(expected.id))

func _shot_safe(shot: Dictionary) -> bool:
	var solution: Dictionary = shot.solution
	if solution.is_empty(): return false
	var origin: Vector2 = solution.origin
	var end: Vector2 = solution.point
	var grip := point(shot.grip)
	for actor: Dictionary in shot.friends:
		var body := point(actor.position)
		var base := float(actor.base_height)
		var top := base + float(actor.height)
		var prefix := Geometry2D.get_closest_point_to_segment(body,grip,origin)
		if prefix.distance_to(body)<0.29 and float(solution.origin_height)>=base and float(solution.origin_height)<=top: return false
		var nearest := Geometry2D.get_closest_point_to_segment(body,origin,end)
		if nearest.distance_to(body)<0.29 and origin.distance_to(body)<origin.distance_to(end):
			var ratio := origin.distance_to(nearest)/maxf(0.001,origin.distance_to(end))
			var height := lerpf(float(solution.origin_height),float(solution.target_height),ratio)
			if height>=base and height<=top: return false
	return true

func measured_case(seed_value: int, method: String, patrol: bool = false) -> Dictionary:
	var sim := PassiveCombatProbe.new()
	var mission_data := fixture(seed_value,patrol)
	sim.load_mission(mission_data)
	sim.enemy_rules = Catalog.NORMAL.duplicate(true)
	check(sim.units.size()==4 and sim.enemies.size()==1,"seed %d %s controlled four-unit, normal enemy fixture" % [seed_value,method])
	for actor: Dictionary in sim.units+sim.enemies:
		check(sim.nav.walkable(position(actor)),"seed %d %s legal authored spawn %s" % [seed_value,method,str(actor.id)])
	var planned: Dictionary = {}
	var target: Array = [12.0,2.8] if patrol else TARGET
	if method=="formation":
		# The recommendation remains editable. This fixed plan uses only the
		# authored own loadouts and the public corridor, identically in every
		# seed; it never chooses ranks from a hidden enemy's current position.
		planned = sim.plan_formation(target,"AUTO" if patrol else "SERPENTINE",ORDER if patrol else FORMATION_ORDER,{"append":true,"signal":"AUTO"})
		check(bool(planned.get("ok",false)),"seed %d formation public macro accepted: %s" % [seed_value,str(planned.get("message",""))])
		check(str(planned.get("recommended_kind",""))=="ROLLING_T","P0 six-metre passage retains AUTO's ROLLING_T recommendation")
		check(str(planned.get("kind",""))==("ROLLING_T" if patrol else "SERPENTINE"),"Public macro honors the fixed player-selected formation kind")
	else:
		for index: int in range(4):
			var answer: Dictionary = sim.issue(ORDER[index],"MOVE",{"target":[10.8+index*0.8,2.8 if patrol else 10.8]})
			check(bool(answer.get("ok",false)),"seed %d exact P0 manual MOVE accepted for %s" % [seed_value,ORDER[index]])
	var continuous := true
	var separated := true
	var leaves_clear := true
	var minimum_spacing := INF
	var maximum_step := 0.0
	var crossing_tick := -1
	var crossing_position: Array = []
	var side_door: Dictionary = sim._find(sim.doors,"d2")
	var trace: Array = []
	var movement: Dictionary = {}
	var stack_ticks: Dictionary = {}
	var ready_signals: Array = []
	var event_cursor := sim.events.size()
	for id: String in ORDER: movement[id] = {"total":0.0,"stack":0.0,"advance":0.0,"move_started":false}
	for frame: int in range(TICKS):
		var previous: Array = sim.units.map(func(actor: Dictionary) -> Vector2: return position(actor))
		var previous_stages: Dictionary = {}
		for actor: Dictionary in sim.units:
			var active: Dictionary = sim._active(actor)
			previous_stages[str(actor.id)] = str(active.get("args",{}).get("formation",{}).get("stage",""))
		var enemy_before := position(sim.enemies[0])
		sim.step(STEP)
		for index: int in range(event_cursor,sim.events.size()):
			var event: Dictionary = sim.events[index]
			if event.type=="SIGNAL" and str(event.get("sync_id",""))==str(planned.get("sync_id",""))+":ready":
				var stack_receipt: Array = []
				for actor: Dictionary in sim.units:
					if float(actor.hp)<=0.0: continue
					var slots: Array = planned.get("slots",[]).filter(func(slot: Dictionary) -> bool: return str(slot.unit_id)==str(actor.id))
					var slot: Dictionary = slots[0] if not slots.is_empty() else {}
					var stack_moves: Array = actor.commands.filter(func(command: Dictionary) -> bool: return command.type=="MOVE" and str(command.args.get("formation",{}).get("sync_id",""))==str(planned.get("sync_id","")) and str(command.args.get("formation",{}).get("stage",""))=="stack")
					stack_receipt.append({"unit_id":str(actor.id),"position":[actor.x,actor.z],"stack":slot.get("stack",[]),"distance":position(actor).distance_to(point(slot.stack)) if not slot.is_empty() else INF,"stack_move_states":stack_moves.map(func(command: Dictionary) -> String: return str(command.state))})
				ready_signals.append({"event":event.duplicate(true),"living_ids":sim.units.filter(func(actor: Dictionary) -> bool: return float(actor.hp)>0.0).map(func(actor: Dictionary) -> String: return str(actor.id)),"stack_receipt":stack_receipt})
		event_cursor = sim.events.size()
		var enemy_after := position(sim.enemies[0])
		if crossing_tick<0 and enemy_before.x<float(side_door.x) and enemy_after.x>=float(side_door.x):
			var crossing := enemy_before.lerp(enemy_after,(float(side_door.x)-enemy_before.x)/maxf(0.000001,enemy_after.x-enemy_before.x))
			if absf(crossing.y-float(side_door.z))<=0.9:
				crossing_tick = sim.tick
				crossing_position = [crossing.x,crossing.y]
		for index: int in range(4):
			var unit: Dictionary = sim.units[index]
			var distance := position(unit).distance_to(previous[index])
			movement[str(unit.id)].total += distance
			if str(previous_stages[str(unit.id)])=="stack": movement[str(unit.id)].stack += distance
			if str(previous_stages[str(unit.id)])=="move": movement[str(unit.id)].advance += distance
			for command: Dictionary in unit.commands:
				if command.type=="MOVE" and str(command.args.get("formation",{}).get("stage",""))=="move" and bool(command.get("_started",false)): movement[str(unit.id)].move_started = true
			maximum_step = maxf(maximum_step,distance)
			continuous = continuous and distance<=0.115
			for door: Dictionary in sim.doors: leaves_clear = leaves_clear and not Door.overlaps_actor(door,-1.0,position(unit),Navigation.RADIUS)
			for other: int in range(index):
				if float(unit.hp)>0.0 and float(sim.units[other].hp)>0.0: minimum_spacing = minf(minimum_spacing,position(unit).distance_to(position(sim.units[other])))
		separated = separated and minimum_spacing>=Navigation.RADIUS*2.0-0.0001
		for slot: Dictionary in planned.get("slots",[]):
			if not stack_ticks.has(str(slot.unit_id)) and position(sim._find(sim.units,str(slot.unit_id))).distance_to(point(slot.stack))<=0.1: stack_ticks[str(slot.unit_id)] = sim.tick
		if "--probe-only" in OS.get_cmdline_user_args() and frame%15==0 and frame<240:
			trace.append({"tick":sim.tick,"enemy":{"position":[sim.enemies[0].x,sim.enemies[0].z],"status":sim.enemies[0].status,"visible":sim.enemies[0].visible},"units":sim.units.map(func(actor: Dictionary) -> Dictionary: return {"id":actor.id,"position":[actor.x,actor.z],"facing":actor.facing,"status":actor.status,"commands":actor.commands.duplicate(true),"detour":actor.get("_movement_detour",[]).duplicate(true),"recovery_at":actor.get("_movement_recovery_at",0),"traffic_wait":actor.get("_traffic_wait",0)})})
	var first_shot: Dictionary = sim.actual_shots[0] if not sim.actual_shots.is_empty() else {}
	var friendly_first := not first_shot.is_empty() and not bool(first_shot.hostile)
	var hostile_shots := 0
	var safe_fire := true
	var observed_fire := true
	for shot: Dictionary in sim.actual_shots:
		hostile_shots += int(bool(shot.hostile))
		if not bool(shot.hostile):
			safe_fire = safe_fire and _shot_safe(shot)
			observed_fire = observed_fire and shot.aim_state=="ready" and bool(shot.visible) and bool(shot.seen) and bool(shot.identified) and float(shot.solution.get("transmission",0.0))>0.0
	var arrived: Array = []
	if method=="formation":
		for slot: Dictionary in planned.get("slots",[]):
			if position(sim._find(sim.units,str(slot.unit_id))).distance_to(point(slot.target))<=0.1: arrived.append(str(slot.unit_id))
	check(sim.tick==TICKS,"seed %d %s completes exact 360 STEP without early termination" % [seed_value,method])
	check(continuous and separated and leaves_clear,"seed %d %s preserves continuous movement, body spacing and real leaves" % [seed_value,method])
	check(safe_fire,"seed %d %s actual muzzle/bullet paths clear every living teammate" % [seed_value,method])
	check(observed_fire,"seed %d %s every actual friendly shot uses fresh identified LOS and completed aim" % [seed_value,method])
	check(sim.command_failures==0,"seed %d %s public plan has no failed commands" % [seed_value,method])
	if method=="formation":
		# An early role FACE can shoot while the rest of a broken macro remains
		# idle. Such a sample does not establish formation movement. Use the
		# real named barrier and subsequent real MOVE nodes as causal evidence;
		# normal casualties need not finish future nodes or reach final goals.
		check(ready_signals.size()==1,"seed %d formation emits exactly one actual ready-cohort SIGNAL" % seed_value)
		if ready_signals.size()==1:
			var released: Array = ready_signals[0].event.get("receiver_unit_ids",[]).duplicate()
			var expected: Array = ready_signals[0].living_ids.duplicate()
			released.sort()
			expected.sort()
			check(released==expected and int(ready_signals[0].event.released)==expected.size(),"seed %d actual named signal releases the entire living formation cohort" % seed_value)
			var receipt: Array = ready_signals[0].stack_receipt
			check(receipt.size()==expected.size() and receipt.all(func(entry: Dictionary) -> bool: return float(entry.distance)<=0.1 and not entry.stack_move_states.is_empty() and entry.stack_move_states.all(func(state: String) -> bool: return state=="SUCCEEDED")),"seed %d every living participant physically occupies its stack and has succeeded every stack MOVE at the actual ready SIGNAL" % seed_value)
		for unit: Dictionary in sim.units:
			if float(unit.hp)<=0.0: continue
			var evidence: Dictionary = movement[str(unit.id)]
			var slots: Array = planned.get("slots",[]).filter(func(slot: Dictionary) -> bool: return str(slot.unit_id)==str(unit.id))
			var slot: Dictionary = slots[0] if not slots.is_empty() else {}
			# A near stack can legitimately finish after less than .05 m: the
			# existing MOVE arrival radius is .08 m. BRAVO's .1241 m origin-to-
			# stack distance needs only .0441 m, and actually travels .0467 m.
			# Require the geometry-derived physical lower bound instead, plus
			# all stack MOVEs succeeded at the real barrier and subsequent >.05
			# m advance. An initial FACE followed by an idle macro still fails.
			var required_stack_travel := maxf(0.0,point(slot.approach).distance_to(point(slot.stack))-STACK_ARRIVAL_TOLERANCE) if not slot.is_empty() else INF
			evidence["required_stack_travel"] = required_stack_travel
			check(stack_ticks.has(str(unit.id)) and float(evidence.stack)+DISTANCE_EPSILON>=required_stack_travel and bool(evidence.move_started) and float(evidence.advance)>0.05,"seed %d living %s physically reaches its stack and advances through a real formation MOVE" % [seed_value,str(unit.id)])
	if patrol: check(crossing_tick>=0,"seed %d %s normal patrol actually crosses authored side-door d2" % [seed_value,method])
	return {"seed":seed_value,"method":method,"patrol":patrol,"tick":sim.tick,"friendly_first":friendly_first,"first_tick":int(first_shot.get("tick",-1)),
		"first_hostile":bool(first_shot.get("hostile",false)),"friendly_shots":sim.shots_fired,"hostile_shots":hostile_shots,"hits_taken":sim.hits_taken,
		"minimum_spacing":minimum_spacing,"maximum_step":maximum_step,"safe_fire":safe_fire,"observed_fire":observed_fire,"continuous":continuous,"leaves_clear":leaves_clear,
		"crossing_tick":crossing_tick,"crossing_position":crossing_position,"arrivals":arrived,"plan":planned,"doctrine":sim._statistics(),"movement":movement,"stack_ticks":stack_ticks,"ready_signals":ready_signals,
		"primitive_results":sim.units.map(func(actor: Dictionary) -> Dictionary: return {"unit_id":str(actor.id),"hp":actor.hp,"position":[actor.x,actor.z],"commands":actor.commands.map(func(command: Dictionary) -> Dictionary: return {"id":str(command.id),"type":str(command.type),"state":str(command.state),"args":command.args.duplicate(true),"started":bool(command.get("_started",false)),"path_cursor":int(command.get("path_cursor",0))})}),
		"actual_shots":sim.actual_shots.duplicate(true),"trace":trace,"combat_trace":sim.combat_trace.duplicate(true),"mission_hash":JSON.stringify(mission_data).sha256_text(),"mission_definition":mission_data if "--probe-only" in OS.get_cmdline_user_args() else {},"state_hash":_state_fingerprint(sim)}

func _benchmark(patrol: bool = false) -> void:
	var rows: Array = []
	var summary := {"manual":{"friendly_first_cases":0},"formation":{"friendly_first_cases":0},"cases":SEEDS,"deterministic_repeats":0}
	for seed_value: int in range(SEEDS):
		for method: String in ["manual","formation"]:
			var measured := measured_case(seed_value,method,patrol)
			var repeated := measured_case(seed_value,method,patrol)
			check(JSON.stringify(measured)==JSON.stringify(repeated),"seed %d %s same fixed public plan preserves full state, RNG and measured evidence" % [seed_value,method])
			summary[method].friendly_first_cases += int(bool(measured.friendly_first))
			summary.deterministic_repeats += 1
			rows.append(measured)
	check(int(summary.formation.friendly_first_cases)>int(summary.manual.friendly_first_cases),"Formation wins first actual fire in more fixed seeds than matching individual movement")
	if not patrol: check(int(summary.formation.friendly_first_cases)>P0_FRIENDLY_FIRST_CASES,"Formation first-fire rate exceeds archived P0 corridor zero of thirty")
	report["patrol" if patrol else "p0_corridor"] = {"aggregate":summary,"cases":rows}
	print("FORMATION_COMBAT_%s %s" % ["PATROL" if patrol else "CORRIDOR",JSON.stringify(summary)])

func run() -> void:
	var args := OS.get_cmdline_user_args()
	_fixture_contracts()
	report["fixtures"] = {"p0_corridor":fixture(0),"patrol":patrol_fixture(0)}
	if "--observer-only" in args: _passive_observer_contract()
	elif "--probe-only" in args:
		print("FORMATION_COMBAT_PROBE " + JSON.stringify({"manual":measured_case(0,"manual"),"formation":measured_case(0,"formation"),"patrol_manual":measured_case(0,"manual",true),"patrol_formation":measured_case(0,"formation",true)}))
	elif "--corridor-only" in args: _benchmark()
	elif "--patrol-only" in args: _benchmark(true)
	else:
		_passive_observer_contract()
		_benchmark()
		_benchmark(true)
	if args.is_empty():
		var directory := ProjectSettings.globalize_path("res://../tests/artifacts/cqb-p4")
		DirAccess.make_dir_recursive_absolute(directory)
		var artifact := FileAccess.open(directory.path_join("formation-combat.json"),FileAccess.WRITE)
		check(artifact!=null,"P4 actual first-fire fixed-seed evidence is writable")
		report.checks = checks
		report.failures = failures.duplicate()
		if artifact!=null: artifact.store_string(JSON.stringify(report,"\t")+"\n")
	print("BREACH_FORMATION_COMBAT_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
