extends SceneTree
## The actual first two SH05_HIGH_INTENSITY drills reproduce the outward open
## leaf and C/D crossing lanes. Authored actors and normal combat are unchanged;
## this controller uses only observed targets, public plans and fixed STEP.
## The stopped stack extension and timed-hold prediction override were removed
## after an isolated oracle preserved these two public macros, their four exact
## ready positions, and the original 27 approach checks. Their obsolete private
## branch assertions are replaced by the full public outcomes below; the actual
## already-inside departure is covered independently by a stopped-lane fixture.
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Door = preload("res://scripts/door_geometry.gd")
const AllLeftFixture = preload("res://tests/room_drill_all_left_fixture.gd")
const STEP := 1.0 / 30.0
const IDS: Array[String] = ["alpha", "bravo", "charlie", "delta"]

var checks: int = 0
var failures: Array[String] = []
var report: Dictionary = {"step":STEP,"cases":[]}

class RecoveryProbe extends "res://scripts/simulation.gd":
	var departures: Array = []
	var entry_checkpoint: Dictionary = {}
	var corners_followed: bool = true
	func _follow_command_path(actor: Dictionary, command: Dictionary, dt: float) -> bool:
		var before_position := _position(actor)
		var before_rng: Array = [_rng.state,_hit_region_rng.state,_breach_rng.state,_surrender_rng.state]
		var primitive: Dictionary = {"id":command.id,"args":command.args.duplicate(true)}
		var original_path: Array = command.get("path",[]).duplicate(true)
		var original_cursor: int = int(command.get("path_cursor",0))
		var guarded: bool = command.has("_drill_recovery_path") and command._drill_recovery_path==original_path
		var answer: bool = super._follow_command_path(actor,command,dt)
		if guarded and command.path==original_path:
			for index: int in range(original_cursor,int(command.path_cursor)):
				corners_followed = corners_followed and before_position.distance_to(_point(original_path[index]))<0.08
		return answer
	func _recover_formation_lane_hold(actor: Dictionary, command: Dictionary) -> bool:
		var original_position := _position(actor)
		var original_rng: Array = [_rng.state,_hit_region_rng.state,_breach_rng.state,_surrender_rng.state]
		var primitive: Dictionary = {"id":command.id,"args":command.args.duplicate(true)}
		var before: Dictionary = {"unit_id":str(actor.id),"time":time,"tick":tick,"units":units.duplicate(true),"doors":doors.duplicate(true),"rng":original_rng.duplicate()}
		var answer: bool = super._recover_formation_lane_hold(actor,command)
		if answer and command.args.has("drill"):
			if entry_checkpoint.is_empty(): entry_checkpoint = before
			departures.append({"tick":tick,"unit_id":str(actor.id),"branch":"held_entry","move_zero":original_position==_position(actor),"rng_unchanged":original_rng==[_rng.state,_hit_region_rng.state,_breach_rng.state,_surrender_rng.state],"primitive_unchanged":primitive=={"id":command.id,"args":command.args.duplicate(true)},"route_clear":_formation_recovery_route_clear(actor,command.path),"exact_goal":_point(command.path.back()).distance_to(_point(command.args.target))<0.00001})
		return answer

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _rng(sim: RefCounted) -> Array:
	return [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]

func _position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x),float(actor.z))

func fixture() -> Dictionary:
	return Catalog.load("SH05_HIGH_INTENSITY").duplicate(true)

func _issue(sim: RefCounted, id: String, type: String, args: Dictionary) -> void:
	var before := _rng(sim)
	var tick_before: int = sim.tick
	var answer: Dictionary = sim.issue(id,type,args,true)
	check(bool(answer.get("ok",false)),"Captured public primitive accepted: "+id+" "+type+" "+str(answer))
	check(sim.tick==tick_before and _rng(sim)==before,"Issuing a captured primitive consumes no time or RNG")

func _idle(sim: RefCounted) -> bool:
	return sim.units.all(func(unit: Dictionary)->bool:return sim._active(unit).is_empty())

func _step_actual(sim: RefCounted, physical: Dictionary) -> void:
	var origins: Array = sim.units.map(func(unit: Dictionary)->Vector2:return _position(unit))
	sim.step(STEP)
	for index: int in range(sim.units.size()):
		var point := _position(sim.units[index])
		physical.max_step = maxf(float(physical.max_step),point.distance_to(origins[index]))
		physical.static_clear = bool(physical.static_clear) and sim.nav.segment_clear(origins[index],point,Navigation.RADIUS)
		for door: Dictionary in sim.doors: physical.leaf_clear = bool(physical.leaf_clear) and not Door.overlaps_actor(door,-1.0,point,Navigation.RADIUS)
		for other: int in range(index): physical.spacing = minf(float(physical.spacing),point.distance_to(_position(sim.units[other])))

func _wait_idle(sim: RefCounted, physical: Dictionary) -> bool:
	for _frame: int in range(900):
		_step_actual(sim,physical)
		if _idle(sim): return true
		if sim.command_failures>0 or not sim.result.is_empty(): return false
	return false

func _room_plan(sim: RefCounted, door_id: String, room_id: String, physical: Dictionary) -> Dictionary:
	var door: Dictionary = sim._find(sim.doors,door_id)
	for id: String in IDS: _issue(sim,id,"FACE",{"target":[door.x,door.z],"sector":{"start":-PI,"end":PI,"duration":0.0}})
	var observed := false
	for _frame: int in range(180):
		_step_actual(sim,physical)
		if sim._door_observations.has(door_id) and _idle(sim):
			observed = true
			break
	check(observed,"The next course door becomes actually observed before its public macro")
	var before := _rng(sim)
	var tick_before: int = sim.tick
	var planned: Dictionary = sim.plan_room_entry(door_id,"OPEN_DOOR",IDS,{"room_id":room_id})
	check(bool(planned.get("ok",false)),"The actual observed course door accepts the unchanged ABCD public drill: "+str(planned))
	check(sim.tick==tick_before and _rng(sim)==before,"Room macro expansion consumes no time or RNG")
	return planned

func _wait_room(sim: RefCounted, room_id: String, physical: Dictionary) -> bool:
	for _frame: int in range(900):
		# Use only the player projection to turn an idle operator toward an
		# observed live training target, matching the public course controller.
		if _idle(sim):
			for enemy: Dictionary in sim.snapshot(false).enemies:
				if not bool(enemy.get("visible",false)) or float(enemy.hp)<=0.0 or bool(enemy.get("surrendered",false)): continue
				var selected: Dictionary = {}
				var distance := INF
				for unit: Dictionary in sim.units:
					if not sim._active(unit).is_empty() or float(unit.hp)<=0.0: continue
					var candidate := _position(unit).distance_squared_to(_position(enemy))
					if candidate<distance:
						selected = unit
						distance = candidate
				if selected.is_empty(): continue
				var target: Array = [float(enemy.x),float(enemy.z)]
				if not selected.commands.is_empty() and selected.commands[-1].type=="FACE" and selected.commands[-1].args.get("target",[])==target: continue
				_issue(sim,str(selected.id),"FACE",{"target":target,"persistent":true,"sector":{"start":-PI,"end":PI,"duration":0.0}})
		_step_actual(sim,physical)
		if sim.snapshot(false).room_states.get(room_id,{}).get("state","") in ["CLEAR","MARKED"] and _idle(sim): return true
		if sim.command_failures>0 or not sim.result.is_empty(): return false
	return false

func _wait_ready(sim: RefCounted, planned: Dictionary, physical: Dictionary) -> bool:
	for _frame: int in range(900):
		_step_actual(sim,physical)
		var signals: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type=="SIGNAL" and event.get("sync_id","")==planned.get("sync_id","")+":ready")
		if not signals.is_empty():
			check(planned.slots.all(func(slot: Dictionary)->bool:return _position(sim._find(sim.units,str(slot.unit_id))).distance_to(Vector2(float(slot.stack[0]),float(slot.stack[1])))<=0.1),"At the actual ready release all four stack coordinates are within 0.1m")
			return int(signals[0].released)==4
		if sim.command_failures>0 or not sim.result.is_empty(): return false
	return false

func _run_actual() -> Dictionary:
	var sim := RecoveryProbe.new()
	sim.load_mission(fixture())
	var physical: Dictionary = {"spacing":INF,"max_step":0.0,"leaf_clear":true,"static_clear":true}
	for action: Dictionary in [{"type":"OPEN_DOOR","args":{"door_id":"ext_left"}},{"type":"MOVE","args":{"target":[5.8,16.2]}},{"type":"THROW_FRAG","args":{"target":[5.8,11.4]}}]:
		_issue(sim,"alpha",str(action.type),action.args)
		check(_wait_idle(sim,physical),"The authored high-intensity preparation executes its real primitive")
	var first := _room_plan(sim,"ext_left","r3",physical)
	check(bool(first.get("ok",false)) and _wait_room(sim,"r3",physical),"The unchanged first course drill actually clears r3")
	var planned := _room_plan(sim,"inner_h1_0","r4",physical)
	var originals: Dictionary = {}
	for unit: Dictionary in sim.units:
		for command: Dictionary in unit.commands: originals[str(command.id)] = command.args.duplicate(true)
	var ready: bool = bool(planned.get("ok",false)) and _wait_ready(sim,planned,physical)
	check(ready,"All four actual crossing stack lanes reach the next real ready barrier within 900 fixed STEP")
	check(sim.departures.all(func(row: Dictionary)->bool:return row.move_zero and row.rng_unchanged and row.primitive_unchanged and row.route_clear and row.exact_goal),"Every actual departure preserves exact goals, primitives, RNG and zero movement for its STEP")
	check(float(physical.max_step)<=0.081 and float(physical.spacing)>=sim._movement_body_spacing()-0.00001 and bool(physical.leaf_clear) and bool(physical.static_clear),"Every physical STEP retains speed, full body spacing, authored walls and open leaves")
	check(sim.command_failures==0 and sim.units.all(func(unit: Dictionary)->bool:return float(unit.hp)>0.0),"Movement recovery causes no command failure or loss")
	check(sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return not originals.has(str(command.id)) or originals[str(command.id)]==command.args)),"Recovery preserves all original command IDs and public arguments")
	var signals: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type=="SIGNAL" and event.get("sync_id","")==planned.get("sync_id","")+":ready")
	check(signals.size()==1 and int(signals[0].released)==4,"The actual next ready barrier releases one complete four-member cohort")
	return {"state":JSON.stringify({"units":sim.units,"doors":sim.doors,"snapshot":sim.snapshot(true),"rng":_rng(sim)}),"ticks":sim.tick,"departures":sim.departures,"physical":physical}

func _run_inside_entry() -> Dictionary:
	var sim := RecoveryProbe.new()
	sim.load_mission(AllLeftFixture.make(0))
	var order: Array = ["delta","bravo","alpha","charlie"]
	var before := _rng(sim)
	var planned: Dictionary = sim.plan_room_entry("door","OPEN_DOOR",order,{"delay_ticks":3,"go_long":true})
	check(bool(planned.get("ok",false)) and _rng(sim)==before and sim.tick==0,"The original all-left public macro preserves planning clock and all four RNG streams")
	var originals: Dictionary = {}
	var finals: Dictionary = {}
	for unit: Dictionary in sim.units:
		for command: Dictionary in unit.commands:
			originals[str(command.id)] = command.args.duplicate(true)
			if command.type=="MOVE": finals[str(unit.id)] = command.args.target.duplicate()
	var physical: Dictionary = {"spacing":INF,"max_step":0.0,"leaf_clear":true,"static_clear":true}
	var arrivals: Dictionary = {}
	var complete := false
	for _frame: int in range(900):
		_step_actual(sim,physical)
		for slot: Dictionary in planned.get("slots",[]):
			if _position(sim._find(sim.units,str(slot.unit_id))).distance_to(sim._point(slot.domination))<=0.1: arrivals[str(slot.unit_id)] = true
		complete = sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.state=="SUCCEEDED"))
		if complete: break
	check(complete and sim.command_failures==0,"The unchanged all-left 48-primitive plan completes within its original 900 fixed STEP")
	check(arrivals.size()==4,"All four real original primary domination goals are visited before go-long")
	check(sim.units.all(func(unit: Dictionary)->bool:return _position(unit).distance_to(sim._point(finals[str(unit.id)]))<=0.1),"All four participants finish within 0.1m of their original final goals")
	check(sim.corners_followed,"Every validated away corner is actually reached before the entry recovery path cursor advances")
	check(sim.departures.all(func(row: Dictionary)->bool:return row.move_zero and row.rng_unchanged and row.primitive_unchanged and row.route_clear and row.exact_goal),"All actual entry departures retain full-route safety, zero STEP movement, original goals, IDs and RNG")
	check(float(physical.max_step)<=0.081 and float(physical.spacing)>=sim._movement_body_spacing()-0.00001 and bool(physical.leaf_clear) and bool(physical.static_clear),"The original all-left plan preserves every physical body, wall, leaf and movement STEP")
	check(sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return originals[str(command.id)]==command.args)),"Entry recovery never rewrites any original public primitive argument")
	return {"state":JSON.stringify({"units":sim.units,"doors":sim.doors,"snapshot":sim.snapshot(true),"rng":_rng(sim)}),"ticks":sim.tick,"departures":sim.departures,"entry_checkpoint":sim.entry_checkpoint,"physical":physical,"corners_followed":sim.corners_followed}

func _copy_checkpoint(source: Dictionary, data: Dictionary = {}) -> RefCounted:
	var sim := Simulation.new()
	sim.load_mission(fixture() if data.is_empty() else data)
	sim.units = source.units.duplicate(true)
	sim.doors = source.doors.duplicate(true)
	sim.nav.build(sim.mission,sim.doors)
	sim.time = float(source.time)
	sim.tick = int(source.tick)
	sim._rng.state = source.rng[0]
	sim._hit_region_rng.state = source.rng[1]
	sim._breach_rng.state = source.rng[2]
	sim._surrender_rng.state = source.rng[3]
	return sim

func _entry_recovery_contract() -> Dictionary:
	# Isolate the recovery precondition; successful integration plans need not
	# encounter a particular avoidance branch after routing improvements.
	var sim := RecoveryProbe.new()
	var data := AllLeftFixture.make(0)
	var positions: Array = [[6.4,4.5],[8.0,7.0],[8.0,6.0],[9.6,4.5]]
	for index: int in range(4):
		data.units[index].x = positions[index][0]
		data.units[index].z = positions[index][1]
	sim.load_mission(data)
	for spec: Dictionary in [{"id":"bravo","target":[8.0,4.8],"rank":2},{"id":"charlie","target":[9.6,6.0],"rank":3}]:
		_issue(sim,spec.id,"MOVE",{"target":spec.target,"drill":{"door_id":"door","room_id":"room","stage":"entry","sync_id":"recovery-contract","order":spec.rank}})
		var unit: Dictionary = sim._find(sim.units,spec.id)
		var command: Dictionary = sim._active(unit)
		sim._start_command(unit,command)
		command.state = "WAITING"
		command["_traffic_wait"] = 2.0
	sim.tick = 60
	sim.time = 2.0
	var actor: Dictionary = sim._find(sim.units,"charlie")
	actor["_movement_lane_goal"] = [actor.x,actor.z]
	actor["_movement_lane_requester"] = "bravo"
	actor["_movement_lane_hold_until"] = sim.time + 0.8
	check(sim._recover_formation_lane_hold(actor,sim._active(actor)),"A stopped later-rank entrant can safely leave its reached yield lane")
	check(sim.departures.size()==1 and sim.departures.all(func(row: Dictionary)->bool:return row.move_zero and row.rng_unchanged and row.primitive_unchanged and row.route_clear and row.exact_goal),"Entry recovery preserves full-route safety, exact goal, primitive, RNG and zero movement")
	return sim.entry_checkpoint

func _entry_negative_guards(source: Dictionary) -> void:
	# This checkpoint precedes a successful in-room recovery call. Only
	# derived copies receive synthetic rejection boundaries below.
	if source.is_empty():
		check(false,"The stopped-lane fixture supplies an inside-entry departure checkpoint")
		return
	var baseline := _copy_checkpoint(source,AllLeftFixture.make(0))
	var actor: Dictionary = baseline._find(baseline.units,str(source.unit_id))
	var requester: Dictionary = baseline._find(baseline.units,str(actor._movement_lane_requester))
	var pair: Dictionary = baseline._drill_entry_recovery_pair(actor,baseline._active(actor),requester)
	check(not pair.is_empty(),"The entry checkpoint has matching room/door/cohort and a later rank already inside")
	for variant: String in ["outside_actor","outside_requester","other_door","other_room","earlier_rank","different_cohort","stack","ready_wait","hold_actor","hold_requester","actor_moving","requester_moving","short_wait","cadence","npc","door_operator","unnamed","cannot_act","requester_cannot_act"]:
		var sim := _copy_checkpoint(source,AllLeftFixture.make(0))
		var unit: Dictionary = sim._find(sim.units,str(source.unit_id))
		var command: Dictionary = sim._active(unit)
		var other_unit: Dictionary = sim._find(sim.units,str(unit._movement_lane_requester))
		var other: Dictionary = sim._active(other_unit)
		match variant:
			"outside_actor": unit.z = 8.6; unit._movement_lane_goal = [unit.x,unit.z]
			"outside_requester": other_unit.z = 8.6
			"other_door": other.args.drill.door_id = "hidden_door"
			"other_room": other.args.drill.room_id = "hidden"
			"earlier_rank": command.args.drill.order = int(other.args.drill.order)
			"different_cohort": other.args.drill.sync_id = "other-drill"
			"stack": command.args.drill.stage = "stack"; other.args.drill.stage = "stack"
			"ready_wait": other.type = "WAIT_FOR_SIGNAL"; other.args.drill.stage = "ready"
			"hold_actor": unit.hold_position = true
			"hold_requester": other_unit.hold_position = true
			"actor_moving": unit._movement_moved_tick = sim.tick - 1
			"requester_moving": other_unit._movement_moved_tick = sim.tick - 1
			"short_wait": other._traffic_wait = 1.0
			"cadence": unit._movement_dynamic_route_at = sim.time + 0.01
			"npc": unit.kind = "civilian"
			"door_operator": other.type = "OPEN_DOOR"
			"unnamed": command.args.drill.sync_id = ""
			"cannot_act": unit.hp = 0.0
			"requester_cannot_act": other_unit.hp = 0.0
		var before := JSON.stringify({"units":sim.units,"rng":_rng(sim),"time":sim.time,"tick":sim.tick})
		check(not sim._recover_formation_lane_hold(unit,command),variant+" cannot depart a reached entry yield lane")
		check(before==JSON.stringify({"units":sim.units,"rng":_rng(sim),"time":sim.time,"tick":sim.tick}),variant+" rejection leaves every primitive, clock and RNG unchanged")
	var outside_route: Array = [[float(actor.x),9.0],baseline._active(actor).args.target]
	var before := JSON.stringify({"units":baseline.units,"rng":_rng(baseline),"time":baseline.time,"tick":baseline.tick})
	check(not baseline._drill_entry_recovery_route_clear(actor,pair,outside_route),"A full route that leaves the already-crossed door plane is rejected")
	check(before==JSON.stringify({"units":baseline.units,"rng":_rng(baseline),"time":baseline.time,"tick":baseline.tick}),"The outside-route query is immutable and consumes no clock or RNG")

func _whole_route_guards() -> void:
	var data := fixture()
	data.enemies = []
	data.civilians = []
	data.walls = []
	data.props = []
	data.doors = []
	data.rooms = [{"id":"floor","x":8.0,"z":10.0,"w":14.0,"d":14.0},{"id":"raised","x":8.0,"z":10.0,"w":2.0,"d":1.0,"base_height":2.022}]
	var starts: Array = [[8.0,14.0],[12.0,14.0],[12.0,12.0],[12.0,10.0]]
	for index: int in range(data.units.size()):
		data.units[index].x = starts[index][0]
		data.units[index].z = starts[index][1]
	var sim := Simulation.new()
	sim.load_mission(data)
	var before := _rng(sim)
	check(not sim._formation_recovery_route_clear(sim.units[0],[[8.0,6.0]]),"The drill recovery whole-route guard rejects an intervening authored floor jump")
	check(sim._formation_recovery_route_clear(sim.units[0],[[10.5,14.0],[10.5,6.0],[8.0,6.0]]),"A same-floor full-radius route around the raised island remains legal")
	check(not sim._formation_recovery_route_clear(sim.units[0],[[8.0,13.0],[12.0,14.0],[8.0,6.0]]),"A body obstructing only a later recovery leg still rejects the entire route")
	check(_rng(sim)==before,"All accepted and impossible full-route queries preserve all four RNG streams")
	var leaf_data := data.duplicate(true)
	leaf_data.doors = [{"id":"recovery_leaf","x":8.0,"z":12.0,"w":2.0,"d":0.2,"axis":"x","state":"CLOSED","hp":100.0,"material":"wood"}]
	var leaf_sim := Simulation.new()
	leaf_sim.load_mission(leaf_data)
	var leaf_before := _rng(leaf_sim)
	check(not leaf_sim._formation_recovery_route_clear(leaf_sim.units[0],[[8.0,11.0]]),"An intact physical leaf rejects a recovery route even with no live-body obstruction")
	check(_rng(leaf_sim)==leaf_before,"Physical leaf rejection consumes no RNG")

func _expected_velocity_guards() -> void:
	# These are pure prediction boundary checks on a public-issued primitive;
	# no path/pose mutation here contributes to the actual recovery proof above.
	var sim := Simulation.new()
	sim.load_mission(fixture())
	var accepted: Dictionary = sim.issue("alpha","MOVE",{"target":[5.8,16.2]},true)
	check(bool(accepted.get("ok",false)),"The prediction boundary fixture uses a real accepted MOVE primitive")
	var actor: Dictionary = sim.units[0].duplicate(true)
	var command: Dictionary = sim._active(actor)
	command.state = "WAITING"
	command.path = [[actor.x+2.0,actor.z],[actor.x,actor.z-2.0]]
	command.path_cursor = 1
	actor.velocity_x = 0.0
	actor.velocity_z = 0.0
	actor.erase("_movement_detour")
	var before_rng := _rng(sim)
	var before := JSON.stringify(actor)
	var absent := sim._movement_expected_velocity(actor)
	check(absent.distance_to(Vector2(0.0,-2.16*float(actor.mobility_multiplier)))<0.000001,"Absent detour predicts the active path cursor rather than the final target")
	check(before==JSON.stringify(actor),"Absent-detour prediction preserves every actor and primitive field")
	actor["_movement_detour"] = []
	before = JSON.stringify(actor)
	check(sim._movement_expected_velocity(actor)==absent,"An explicitly empty detour has exactly the same prediction as an absent detour")
	check(before==JSON.stringify(actor),"Empty-detour prediction preserves every actor and primitive field")
	actor["_movement_detour"] = [[actor.x+2.0,actor.z]]
	before = JSON.stringify(actor)
	check(sim._movement_expected_velocity(actor).distance_to(Vector2(2.16*float(actor.mobility_multiplier),0.0))<0.000001,"A nonempty detour predicts its first node independently of the original path cursor")
	check(before==JSON.stringify(actor),"Nonempty-detour prediction preserves every actor and primitive field")
	actor["_movement_detour"] = []
	command.path_cursor = command.path.size()
	var final_direction := (sim._point(command.args.target)-sim._position(actor)).normalized()*2.16*float(actor.mobility_multiplier)
	check(sim._movement_expected_velocity(actor)==final_direction,"Exhausted original path retains the existing final-target prediction")
	actor["_movement_lane_hold_until"] = sim.time + STEP
	actor.velocity_x = 1.0
	check(sim._movement_expected_velocity(actor)==Vector2(1.0,0.0),"Actual movement velocity retains priority even when a lane-hold receipt exists")
	actor.velocity_x = 0.0
	actor.erase("_movement_lane_hold_until")
	check(sim._movement_expected_velocity(actor)==final_direction,"An ordinary WAITING MOVE without an actual lane hold still predicts its original path")
	actor.hold_position = true
	before = JSON.stringify(actor)
	check(sim._movement_expected_velocity(actor)==Vector2.ZERO,"An explicit held actor remains stationary regardless of path or detour")
	check(before==JSON.stringify(actor),"Held prediction is immutable")
	actor.hold_position = false
	command.type = "WAIT_FOR_SIGNAL"
	check(sim._movement_expected_velocity(actor)==Vector2.ZERO,"An actual signal-wait primitive never acquires a predicted MOVE velocity")
	check(_rng(sim)==before_rng,"All prediction edge queries preserve all four RNG streams")

func run() -> void:
	var first := _run_actual()
	var second := first if "--probe-only" in OS.get_cmdline_user_args() else _run_actual()
	check(first==second,"Authored poses and public primitives repeat their entire fixed-STEP outcome and all four RNG streams")
	var entry := _run_inside_entry()
	var entry_repeat := entry if "--probe-only" in OS.get_cmdline_user_args() else _run_inside_entry()
	check(entry==entry_repeat,"The unchanged all-left public plan repeats its whole state and all four RNG streams")
	_entry_negative_guards(_entry_recovery_contract())
	_whole_route_guards()
	_expected_velocity_guards()
	if failures.size()>0: report["failed_state"] = str(first.state); report["failed_entry_state"] = str(entry.state)
	for sample: Dictionary in [first,second,entry,entry_repeat]:
		for key: String in ["entry_checkpoint","state"]: sample.erase(key)
	report.cases = [first,second,entry,entry_repeat]
	report.checks = checks
	report.failures = failures.size()
	var directory := ProjectSettings.globalize_path("res://").path_join("../tests/artifacts/cqb-p7")
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("drill-lane-recovery.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  ")+"\n")
	print("BREACH_DRILL_LANE_RECOVERY_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
