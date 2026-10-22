extends SceneTree
## P7 courses run authored geometry and public plans on the normal STEP clock.
## Planning is free, but physical door, movement, combat, search and control
## actions must account for the complete 30–90 second course duration.
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Navigation = preload("res://scripts/navigation.gd")
const STEP := 1.0 / 30.0
const COURSE_TICKS := 2700
const COURSE_IDS: Array[String] = ["SH01","SH02","SH03","SH04","SH05_PRECISION","SH05_HIGH_INTENSITY"]
const ORDER: Array[String] = ["alpha","bravo","charlie","delta"]
var checks := 0
var failures: Array[String] = []
var course_specs: Dictionary = JSON.parse_string("""{"SH01":{"mission_id":"SH01","seed":9001,"order_ids":["alpha","bravo","charlie","delta"],"duration_range":[30.0,90.0],"formation_legs":[],"legs":[{"door_id":"ext_left","room_id":"r3","method":"OPEN_DOOR"},{"door_id":"inner_h1_0","room_id":"r4","method":"OPEN_DOOR"},{"door_id":"inner_v1","room_id":"r2","method":"OPEN_DOOR","order_ids":["delta","bravo","charlie","alpha"]},{"door_id":"inner_h0_0","room_id":"r1","method":"OPEN_DOOR","order_ids":["bravo","alpha","delta","charlie"]}],"finish":{"via_doors":["inner_v0","ext_left"],"zone":[11.399999999999999,16.7,2.8,1.8],"return_leg":{},"outside_targets":{"alpha":[7.1,15.7],"bravo":[4.5,15.7],"charlie":[7.1,16.4],"delta":[4.5,16.4]},"finish_unit_id":"charlie","waypoints":[[5.8,11.399999999999999],[5.8,15.299999999999999],[11.399999999999999,16.7]],"open_doors":["inner_v0"],"rear_depth_margin":1.0}},"SH02":{"mission_id":"SH02","seed":9002,"order_ids":["alpha","bravo","charlie","delta"],"duration_range":[30.0,90.0],"formation_legs":[],"legs":[{"door_id":"ext_left","room_id":"r3","method":"OPEN_DOOR"},{"door_id":"inner_v0","room_id":"r1","method":"OPEN_DOOR","recover_short":true,"order_ids":["charlie","delta","alpha","bravo"]},{"door_id":"inner_h1_0","room_id":"r4","method":"OPEN_DOOR","order_ids":["charlie","alpha","delta","bravo"]},{"door_id":"inner_v1","room_id":"r2","method":"OPEN_DOOR","recover_short":true,"order_ids":["bravo","alpha","delta","charlie"],"stage_stacks":true}],"finish":{"via_doors":["ext_right"],"zone":[11.399999999999999,14.7,2.8,1.8],"return_leg":{},"outside_targets":{"alpha":[12.7,12.5],"bravo":[10.099999999999998,12.5],"charlie":[12.7,13.2],"delta":[10.099999999999998,13.2]},"finish_unit_id":"charlie","waypoints":[[11.399999999999999,8.2],[11.399999999999999,12.1],[11.399999999999999,14.7]]}},"SH03":{"mission_id":"SH03","seed":9003,"order_ids":["alpha","bravo","charlie","delta"],"duration_range":[30.0,90.0],"formation_legs":[{"kind":"SERPENTINE","target":[1.8,4.0]},{"kind":"ROLLING_T","target":[16.4,4.0],"transition_before":{"targets":{"alpha":[16.4,11.0],"bravo":[16.4,11.7],"charlie":[16.4,12.4],"delta":[16.4,13.1]}}}],"legs":[{"door_id":"ext_left","room_id":"r3","method":"OPEN_DOOR"},{"door_id":"inner_h1_0","room_id":"r4","method":"OPEN_DOOR","stage_stacks":true}],"finish":{"via_doors":["ext_right"],"zone":[11.399999999999999,17.9,2.8,1.8],"return_leg":{},"outside_targets":{"alpha":[12.7,15.7],"bravo":[10.099999999999998,15.7],"charlie":[12.7,16.4],"delta":[10.099999999999998,16.4]},"finish_unit_id":"charlie","waypoints":[[11.399999999999999,11.399999999999999],[11.399999999999999,15.299999999999999],[11.399999999999999,17.9]]},"transition_after_formations":{"targets":{"alpha":[7.1,15.7],"bravo":[4.5,15.7],"charlie":[7.1,16.4],"delta":[4.5,16.4]}}},"SH04":{"mission_id":"SH04","seed":9004,"order_ids":["alpha","bravo","charlie","delta"],"duration_range":[30.0,90.0],"formation_legs":[{"kind":"T_JUNCTION","target":[8.6,18.8]},{"kind":"SERPENTINE","target":[4.2,18.8]}],"legs":[{"door_id":"ext_left","room_id":"r3","method":"OPEN_DOOR"},{"door_id":"inner_h1_0","room_id":"r4","method":"OPEN_DOOR","stage_stacks":true}],"finish":{"via_doors":["ext_right"],"zone":[4.2,18.8,1.2,1.2],"return_leg":{},"outside_targets":{"alpha":[12.7,15.7],"bravo":[10.099999999999998,15.7],"charlie":[12.7,16.4],"delta":[10.099999999999998,16.4]},"finish_unit_id":"delta","waypoints":[[11.399999999999999,11.399999999999999],[11.399999999999999,15.299999999999999],[4.2,18.8]]},"transition_after_formations":{"targets":{"alpha":[7.1,15.7],"bravo":[4.5,15.7],"charlie":[7.1,16.4],"delta":[4.5,16.4]}}},"SH05_PRECISION":{"mission_id":"SH05_PRECISION","seed":9055,"order_ids":["alpha","bravo","charlie","delta"],"duration_range":[30.0,90.0],"formation_legs":[],"legs":[{"door_id":"ext_left","room_id":"r3","method":"OPEN_DOOR"},{"door_id":"inner_h1_0","room_id":"r4","method":"OPEN_DOOR"},{"door_id":"inner_v1","room_id":"r2","method":"OPEN_DOOR","order_ids":["delta","bravo","charlie","alpha"]},{"door_id":"inner_h0_0","room_id":"r1","method":"OPEN_DOOR","order_ids":["bravo","alpha","delta","charlie"]}],"finish":{"via_doors":["inner_v0","ext_left"],"zone":[11.399999999999999,16.7,2.8,1.8],"return_leg":{},"outside_targets":{"alpha":[7.1,15.7],"bravo":[4.5,15.7],"charlie":[7.1,16.4],"delta":[4.5,16.4]},"finish_unit_id":"charlie","waypoints":[[5.8,11.399999999999999],[5.8,15.299999999999999],[11.399999999999999,16.7]],"open_doors":["inner_v0"]}},"SH05_HIGH_INTENSITY":{"mission_id":"SH05_HIGH_INTENSITY","seed":9055,"order_ids":["alpha","bravo","charlie","delta"],"duration_range":[30.0,90.0],"formation_legs":[],"legs":[{"door_id":"ext_left","room_id":"r3","method":"OPEN_DOOR","pre_actions":[{"type":"OPEN_DOOR","unit_id":"alpha","args":{"door_id":"ext_left"}},{"type":"MOVE","unit_id":"alpha","args":{"target":[5.8,16.2]}},{"type":"THROW_FRAG","unit_id":"alpha","args":{"target":[5.8,11.399999999999999]}}]},{"door_id":"inner_h1_0","room_id":"r4","method":"OPEN_DOOR"},{"door_id":"inner_v1","room_id":"r2","method":"OPEN_DOOR","order_ids":["delta","bravo","charlie","alpha"]},{"door_id":"inner_h0_0","room_id":"r1","method":"OPEN_DOOR","order_ids":["bravo","alpha","delta","charlie"]}],"finish":{"via_doors":["inner_v0","ext_left"],"zone":[11.399999999999999,16.7,2.8,1.8],"return_leg":{},"outside_targets":{"alpha":[7.1,15.7],"bravo":[4.5,15.7],"charlie":[7.1,16.4],"delta":[4.5,16.4]},"finish_unit_id":"charlie","waypoints":[[5.8,11.399999999999999],[5.8,15.299999999999999],[11.399999999999999,16.7]],"open_doors":["inner_v0"],"rear_depth_margin":1.0}}}""")
var report: Dictionary = {"step":STEP,"courses":[],"course_budget":{"ticks":COURSE_TICKS,"seconds":90.0,"reason":"The specification limits the complete physical course to 90 seconds; individual legs share its remaining fixed-STEP budget rather than an arbitrary 900-STEP cap."}}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x),float(actor.z))

func _rng(sim: RefCounted) -> Array:
	return [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]

func _pending(unit: Dictionary) -> Array:
	return unit.commands.filter(func(command: Dictionary)->bool:return command.state not in ["SUCCEEDED","CANCELLED"])

func _idle(sim: RefCounted) -> bool:
	return sim.units.all(func(unit: Dictionary)->bool:return _pending(unit).is_empty())

func _issue(sim: RefCounted, id: String, type: String, args: Dictionary = {}) -> Dictionary:
	var before_time := float(sim.time)
	var before_tick := int(sim.tick)
	var before_rng := _rng(sim)
	var reply: Dictionary = sim.issue(id,type,args,true)
	check(bool(reply.get("ok",false)),"Public %s %s accepted: %s" % [id,type,str(reply)])
	check(sim.time==before_time and sim.tick==before_tick and _rng(sim)==before_rng,"Plan append preserves the simulation clock and four RNG streams")
	check(sim.units.all(func(unit: Dictionary)->bool:return _pending(unit).size()<=32),"Every unit stays within the existing unfinished primitive limit")
	return reply

func _step(sim: RefCounted, physical: Dictionary) -> void:
	var origins: Dictionary = {}
	for unit: Dictionary in sim.units: origins[str(unit.id)] = _position(unit)
	sim.step(STEP)
	for unit: Dictionary in sim.units:
		var position := _position(unit)
		physical.max_step = maxf(float(physical.max_step),position.distance_to(origins[str(unit.id)]))
		physical.static_clear = bool(physical.static_clear) and sim.nav.segment_clear(origins[str(unit.id)],position,Navigation.RADIUS)
		for door: Dictionary in sim.doors:
			physical.leaf_clear = bool(physical.leaf_clear) and not Door.overlaps_actor(door,-1.0,position,Navigation.RADIUS)
	for first: int in range(sim.units.size()):
		for second: int in range(first+1,sim.units.size()):
			if absf(float(sim.units[first].get("base_height",0.0))-float(sim.units[second].get("base_height",0.0)))>0.01: continue
			physical.min_spacing = minf(float(physical.min_spacing),_position(sim.units[first]).distance_to(_position(sim.units[second])))

func _nearest_idle(sim: RefCounted, point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var distance := INF
	for unit: Dictionary in sim.units:
		if float(unit.hp)<=0.0 or not _pending(unit).is_empty(): continue
		var candidate := _position(unit).distance_squared_to(point)
		if candidate<distance:
			best = unit
			distance = candidate
	return best

func _service_observed_people(sim: RefCounted) -> void:
	# Planning reads the actual player projection. Verification may inspect
	# authority later, but hidden current NPC positions never select a command.
	# Finish entry first, except when an observed civilian occupies an entrant's goal.
	var idle := _idle(sim)
	var public: Dictionary = sim.snapshot(false)
	for enemy: Dictionary in public.enemies:
		if not idle: continue
		if not bool(enemy.get("visible",false)) or not bool(enemy.get("surrendered",false)) or bool(enemy.get("arrested",false)): continue
		if sim.units.any(func(unit: Dictionary)->bool:return _pending(unit).any(func(command: Dictionary)->bool:return command.type=="ARREST" and command.args.enemy_id==enemy.id)): continue
		var unit := _nearest_idle(sim,_position(enemy))
		if not unit.is_empty(): _issue(sim,str(unit.id),"ARREST",{"enemy_id":str(enemy.id)})
	for civilian: Dictionary in public.civilians:
		if not bool(civilian.get("visible",false)) or bool(civilian.get("secured",false)) or float(civilian.get("hp",0.0))<=0.0: continue
		if not idle and not public.units.any(func(unit: Dictionary)->bool:return unit.commands.any(func(command: Dictionary)->bool:return command.type=="MOVE" and command.state=="WAITING" and _position(civilian).distance_to(Vector2(float(command.args.target[0]),float(command.args.target[1])))<0.6)): continue
		if sim.units.any(func(unit: Dictionary)->bool:return _pending(unit).any(func(command: Dictionary)->bool:return command.type=="SECURE_CIVILIAN" and command.args.civilian_id==civilian.id)): continue
		var unit := _nearest_idle(sim,_position(civilian))
		if not unit.is_empty(): _issue(sim,str(unit.id),"SECURE_CIVILIAN",{"civilian_id":str(civilian.id)})

func _face_observed_targets(sim: RefCounted) -> void:
	if not _idle(sim): return
	for enemy: Dictionary in sim.snapshot(false).enemies:
		if not bool(enemy.get("visible",false)) or float(enemy.get("hp",0.0))<=0.0 or bool(enemy.get("surrendered",false)): continue
		var unit := _nearest_idle(sim,_position(enemy))
		if unit.is_empty(): continue
		var target: Array = [float(enemy.x),float(enemy.z)]
		if not unit.commands.is_empty():
			var prior: Dictionary = unit.commands.back()
			if prior.type=="FACE" and prior.args.get("target",[])==target: continue
		_issue(sim,str(unit.id),"FACE",{"target":target,"persistent":true,"sector":{"start":-PI,"end":PI,"duration":0.0}})

func _observe_door(sim: RefCounted, id: String, physical: Dictionary) -> bool:
	var door: Dictionary = sim.mission.doors.filter(func(candidate: Dictionary)->bool:return str(candidate.id)==id)[0]
	for unit: Dictionary in sim.units:
		_issue(sim,str(unit.id),"FACE",{"target":[float(door.x),float(door.z)],"sector":{"start":-PI,"end":PI,"duration":0.0}})
	for _tick: int in range(180):
		_step(sim,physical)
		if sim._door_observations.has(id) and _idle(sim): return true
	check(false,"Actual authored door %s becomes observed before its next public drill" % id)
	return false

func _restore_control_positions(sim: RefCounted, planned: Dictionary) -> void:
	for slot: Dictionary in planned.get("slots",[]):
		var unit: Dictionary = sim.units.filter(func(candidate: Dictionary)->bool:return candidate.id==slot.unit_id)[0]
		if not _pending(unit).is_empty() or unit.commands.is_empty(): continue
		var last: Dictionary = unit.commands.back()
		if last.type not in ["ARREST","SECURE_CIVILIAN"]: continue
		var goal: Array = slot.get("domination",slot.get("target",[]))
		if goal.size()!=2: continue
		_issue(sim,str(unit.id),"MOVE",{"target":goal})
		if slot.has("face_target"): _issue(sim,str(unit.id),"FACE",{"target":slot.face_target})

func _wait_room(sim: RefCounted, room_id: String, planned: Dictionary, physical: Dictionary) -> bool:
	# The original leg-local 900 STEP guard expired after 43 search ticks
	# despite a valid domination at 75.17 seconds. The specification budgets
	# the whole course, so this guard shares the remaining real 90 seconds.
	# Search still needs every one of its 45 consecutive eligible STEP ticks.
	for _tick: int in range(maxi(0,COURSE_TICKS-int(sim.tick))):
		_restore_control_positions(sim,planned)
		_service_observed_people(sim)
		_face_observed_targets(sim)
		_step(sim,physical)
		if sim.command_failures>0 or not sim.result.is_empty(): break
		var memory: Dictionary = sim.snapshot(false).room_states.get(room_id,{})
		if memory.get("state","") in ["CLEAR","MARKED"] and _idle(sim): return true
	check(false,"Actual room %s completes target control, domination and stationary search" % room_id)
	return false

func _room_plan(sim: RefCounted, door_id: String, room_id: String, physical: Dictionary, options: Dictionary = {}, order_ids: Array = ORDER, stage_stacks: bool = false) -> Dictionary:
	if not _observe_door(sim,door_id,physical): return {}
	if stage_stacks and not _stage_public_stacks(sim,door_id,room_id,physical,options,order_ids): return {}
	if not _escort_observed_followers(sim,door_id,room_id,physical,options,order_ids): return {}
	var before_time := float(sim.time)
	var before_tick := int(sim.tick)
	var before_rng := _rng(sim)
	var arguments := options.duplicate(true)
	arguments["room_id"] = room_id
	var planned: Dictionary = sim.plan_room_entry(door_id,"OPEN_DOOR",order_ids,arguments)
	check(bool(planned.get("ok",false)),"Actual observed door %s plans room %s: %s" % [door_id,room_id,str(planned)])
	check(sim.time==before_time and sim.tick==before_tick and _rng(sim)==before_rng,"Room macro expansion is planning-time only and leaves all four RNG streams untouched")
	check(sim.units.all(func(unit: Dictionary)->bool:return _pending(unit).size()<=32),"Expanded room macros retain the existing per-unit pending command cap")
	return planned

func _stage_public_stacks(sim: RefCounted, door_id: String, room_id: String, physical: Dictionary, options: Dictionary, order_ids: Array) -> bool:
	# Public preview supplies the unchanged role stack goals. Ordinary MOVE
	# first places the front two ranks, then the rear two ranks, using normal
	# physical navigation; SHORT retains its two entrants and two guards.
	# Replanning the unchanged macro from these actual owned origins avoids
	# unnecessary outer-wall staging loops without shortening any MOVE path.
	var before := {"time":sim.time,"tick":sim.tick,"rng":_rng(sim)}
	var arguments := options.duplicate(true)
	arguments["room_id"] = room_id
	var draft: Dictionary = sim.room_entry_preview(door_id,"OPEN_DOOR",order_ids,arguments)
	check(bool(draft.get("ok",false)),"Actual owned regroup uses an accepted public room draft")
	check(sim.time==before.time and sim.tick==before.tick and _rng(sim)==before.rng,"Public regroup preview preserves the clock, ticks and four RNG streams")
	if not bool(draft.get("ok",false)): return false
	for front: bool in [true,false]:
		var targets: Dictionary = {}
		var ids: Array = []
		for slot: Dictionary in draft.slots:
			if (int(slot.index)<=2)!=front: continue
			targets[str(slot.unit_id)] = slot.stack
			ids.append(str(slot.unit_id))
		if not ids.is_empty() and not _move_group(sim,targets,ids,physical,"Front then rear ranks physically reach their public stack goals"): return false
	return true

func _escort_observed_followers(sim: RefCounted, door_id: String, room_id: String, physical: Dictionary, options: Dictionary, order_ids: Array) -> bool:
	# Secured civilians still move physically behind their escort. Leaving
	# the previous room's far operator in charge let that follower occupy the
	# next approach lane before an earlier entrant arrived. Reassign each
	# observed follower to a distinct rear entrant. Stage the other entrants
	# first, then actually escort it along the public draft's stack path. A
	# follower arriving early behind a rear stack can block the north-side
	# approach of an earlier entrant even when both planned routes are legal.
	# Every choice uses player facts and owned routes; no hidden NPC pose or
	# mutable civilian field supplies an action or changes the simulation.
	var observed: Array = sim.snapshot(false).civilians.filter(func(civilian: Dictionary)->bool:return bool(civilian.get("visible",false)) and bool(civilian.get("secured",false)) and float(civilian.get("hp",0.0))>0.0)
	if observed.is_empty(): return true
	var before := {"time":sim.time,"tick":sim.tick,"rng":_rng(sim)}
	var arguments := options.duplicate(true)
	arguments["room_id"] = room_id
	var draft: Dictionary = sim.room_entry_preview(door_id,"OPEN_DOOR",order_ids,arguments)
	check(bool(draft.get("ok",false)),"Observed followers use a legal public preview of the next room entry")
	check(sim.time==before.time and sim.tick==before.tick and _rng(sim)==before.rng,"Escort route preview preserves simulation time, ticks and all four RNG streams")
	if not bool(draft.get("ok",false)): return false
	var rear: Array = draft.slots.filter(func(slot: Dictionary)->bool:return bool(slot.get("entry",true)))
	rear.reverse()
	check(observed.size()<=rear.size(),"Each observed secured civilian receives a distinct actual rear entrant escort")
	if observed.size()>rear.size(): return false
	var escorts: Dictionary = {}
	for index: int in range(observed.size()):
		var civilian: Dictionary = observed[index]
		var slot: Dictionary = rear[index]
		escorts[str(slot.unit_id)] = {"civilian":civilian,"started_tick":sim.tick}
		_issue(sim,str(slot.unit_id),"SECURE_CIVILIAN",{"civilian_id":str(civilian.id)})
		if not _wait_idle(sim,physical,"Actual secured civilian escort reassignment"): return false
	var ordered: Array = draft.slots.filter(func(slot: Dictionary)->bool:return not escorts.has(str(slot.unit_id)))
	ordered.append_array(draft.slots.filter(func(slot: Dictionary)->bool:return escorts.has(str(slot.unit_id))))
	for slot: Dictionary in ordered:
		var waypoints: Array = []
		if escorts.has(str(slot.unit_id)):
			# An escort must avoid reversing through its own follower. Use a
			# real interior corner on the opposite side of the observed civilian,
			# then a right-angle approach to the known portal stack. Ordinary
			# MOVE computes every route and still obeys body/leaf/wall physics.
			var public: Dictionary = sim.snapshot(false)
			var own: Dictionary = public.units.filter(func(unit: Dictionary)->bool:return unit.id==slot.unit_id)[0]
			var known: Dictionary = escorts[str(slot.unit_id)].civilian
			for civilian: Dictionary in public.civilians:
				if civilian.id==known.id and bool(civilian.get("visible",false)): known = civilian
			var source: Dictionary = {}
			for room: Dictionary in sim.mission.rooms:
				var rect := Rect2(Vector2(float(room.x)-float(room.w)*0.5,float(room.z)-float(room.d)*0.5),Vector2(float(room.w),float(room.d)))
				if bool(room.get("indoor",true)) and rect.has_point(_position(own)): source = room; break
			check(not source.is_empty(),"An observed civilian escort stages through its own known physical source room")
			if source.is_empty(): return false
			var door: Dictionary = sim.mission.doors.filter(func(candidate: Dictionary)->bool:return candidate.id==door_id)[0]
			if str(door.get("axis","x"))=="z":
				var side := signf(float(own.x)-float(known.x))
				if side==0.0: side = signf(float(source.x)-float(door.x))
				waypoints.append([float(source.x)+side*float(source.w)*0.25,float(source.z)])
				waypoints.append([float(slot.stack[0]),float(source.z)])
			else:
				var side := signf(float(own.z)-float(known.z))
				if side==0.0: side = signf(float(source.z)-float(door.z))
				waypoints.append([float(source.x),float(source.z)+side*float(source.d)*0.25])
				waypoints.append([float(source.x),float(slot.stack[1])])
		waypoints.append(slot.stack)
		for point: Array in waypoints:
			_issue(sim,str(slot.unit_id),"MOVE",{"target":point})
			if not _wait_idle(sim,physical,"Entrants physically stage before the rear civilian escort arrives"): return false
		# FOLLOW traffic can leave a body-safe temporary endpoint. The next
		# room preview uses these actual poses; final entry goals still require 0.1m.
		if not escorts.has(str(slot.unit_id)): continue
		var civilian: Dictionary = escorts[str(slot.unit_id)].civilian
		var actual: Dictionary = sim.civilians.filter(func(actor: Dictionary)->bool:return actor.id==civilian.id)[0]
		# Authority is checked only as evidence after the public command choices.
		check(bool(actual.secured) and str(actual.follow_unit_id)==str(slot.unit_id),"Real SECURE_CIVILIAN commands assign the observed follower to its rear entrant")
		check(float(actual.get("travel_distance",0.0))-float(civilian.get("travel_distance",0.0))>0.05,"Actual escort MOVE makes the observed civilian physically follow rather than merely changing ownership")
		print("SHOOT_HOUSE_ESCORT "+JSON.stringify({"id":sim.mission.id,"civilian_id":civilian.id,"unit_id":slot.unit_id,"door_id":door_id,"started_tick":escorts[str(slot.unit_id)].started_tick,"tick":sim.tick,"civilian_distance":_position(civilian).distance_to(_position(actual)),"stack":slot.stack}))
	return true

func _wait_idle(sim: RefCounted, physical: Dictionary, label: String) -> bool:
	# Every action shares the course clock; no per-leg timer extends 90s.
	for _tick: int in range(maxi(0,COURSE_TICKS-int(sim.tick))):
		_step(sim,physical)
		if _idle(sim): return true
		if sim.command_failures>0 or not sim.result.is_empty(): break
	check(false,label+" finishes its real primitive actions")
	return false

func _recover_short(sim: RefCounted, room_id: String, planned: Dictionary, physical: Dictionary) -> bool:
	# Two entrants clear a SHORT room while two operators hold its exterior.
	# The next four-person drill needs a real common approach side. Bring only
	# those entrants back to their already known stacks through the open door;
	# guards keep their physical watch positions throughout this regroup.
	check(bool(planned.get("short_room",false)),"An authored SHORT recovery follows an actual two-entrant room draft")
	var guards: Dictionary = {}
	for slot: Dictionary in planned.slots:
		if bool(slot.entry):
			_issue(sim,str(slot.unit_id),"MOVE",{"target":slot.stack})
		else:
			guards[str(slot.unit_id)] = _position(sim.units.filter(func(unit: Dictionary)->bool:return unit.id==slot.unit_id)[0])
	if not _wait_idle(sim,physical,"Actual SHORT entrants regroup through their known open portal"): return false
	check(guards.keys().all(func(id: String)->bool:return _position(sim.units.filter(func(unit: Dictionary)->bool:return unit.id==id)[0]).distance_to(guards[id])<=0.0001),"SHORT exterior guards keep their real physical watch positions during recovery")
	check(sim.snapshot(false).room_states.get(room_id,{}).get("state","")=="MARKED","SHORT entrants physically leave and mark their searched room")
	return true

func _move_stage(sim: RefCounted, targets: Dictionary, physical: Dictionary, label: String) -> bool:
	check(ORDER.all(func(id: String)->bool:return targets.has(id)),label+" supplies distinct authored goals for all four operators")
	if not ORDER.all(func(id: String)->bool:return targets.has(id)): return false
	return _move_group(sim,targets,ORDER,physical,label)

func _move_group(sim: RefCounted, targets: Dictionary, ids: Array, physical: Dictionary, label: String) -> bool:
	if not _turn_observed_escorts(sim,targets,ids,physical): return false
	for id: String in ids: _issue(sim,id,"MOVE",{"target":targets[id]})
	if not _wait_idle(sim,physical,label): return false
	# Ordinary MOVE may reach a temporary body-safe endpoint while a FOLLOW
	# civilian crosses its final grid node. Read only owned goal residuals and
	# issue the same original MOVE again after that traffic has passed. Keep
	# the existing strict 0.1m arrival assertion and the shared 90s budget.
	for _attempt: int in range(4):
		var remaining: Array = ids.filter(func(id: String)->bool:return _position(sim.units.filter(func(unit: Dictionary)->bool:return unit.id==id)[0]).distance_to(Vector2(float(targets[id][0]),float(targets[id][1])))>0.1)
		if remaining.is_empty(): break
		for id: String in remaining: _issue(sim,id,"MOVE",{"target":targets[id]})
		if not _wait_idle(sim,physical,label+" physically aligns its original owned goals after passing traffic"): return false
	check(ids.all(func(id: String)->bool:return _position(sim.units.filter(func(unit: Dictionary)->bool:return unit.id==id)[0]).distance_to(Vector2(float(targets[id][0]),float(targets[id][1])))<=0.1),label+" reaches every actual owned goal within 0.1m")
	return true

func _turn_observed_escorts(sim: RefCounted, targets: Dictionary, ids: Array, physical: Dictionary) -> bool:
	# Following is physical: a 180-degree return can put the known follower
	# directly ahead of its leader. A real lateral MOVE lets that civilian
	# fall behind before the leader takes the new route. This uses observed
	# civilians and owned poses; the static navigation copy has public door
	# poses, so even candidate selection cannot read a hidden live door.
	for id: String in ids:
		var public: Dictionary = sim.snapshot(false)
		var own: Dictionary = public.units.filter(func(unit: Dictionary)->bool:return unit.id==id)[0]
		var origin := _position(own)
		var direction := (Vector2(float(targets[id][0]),float(targets[id][1]))-origin).normalized()
		var blocked := false
		for civilian: Dictionary in public.civilians:
			if not bool(civilian.get("visible",false)) or not bool(civilian.get("secured",false)) or str(civilian.get("follow_unit_id",""))!=id: continue
			var offset := _position(civilian)-origin
			if offset.length()<=2.0 and offset.dot(direction)>0.25 and absf(offset.cross(direction))<0.75: blocked = true
		if not blocked: continue
		var source: Dictionary = {}
		for room: Dictionary in sim.mission.rooms:
			var rect := Rect2(Vector2(float(room.x)-float(room.w)*0.5,float(room.z)-float(room.d)*0.5),Vector2(float(room.w),float(room.d)))
			if rect.has_point(origin): source = room; break
		check(not source.is_empty(),"A real escort turn uses its owner's authored public source room")
		if source.is_empty(): return false
		var inside := Rect2(Vector2(float(source.x)-float(source.w)*0.5+0.4,float(source.z)-float(source.d)*0.5+0.4),Vector2(float(source.w)-0.8,float(source.d)-0.8))
		var planning := Navigation.new()
		planning.build(sim.mission,public.doors)
		var point: Array = []
		for side: float in [1.0,-1.0]:
			var candidate := origin+Vector2(direction.y,-direction.x)*side*1.2
			if not inside.has_point(candidate) or not planning.segment_clear(origin,candidate,Navigation.RADIUS): continue
			if public.units.any(func(unit: Dictionary)->bool:return unit.id!=id and _position(unit).distance_to(candidate)<0.48): continue
			point = [candidate.x,candidate.y]
			break
		check(not point.is_empty(),"An observed FOLLOW reversal has a legal physical lateral escort MOVE")
		if point.is_empty(): return false
		_issue(sim,id,"MOVE",{"target":point})
		if not _wait_idle(sim,physical,"Real lateral escort turn keeps the secured civilian behind its owner"): return false
		check(_position(sim.units.filter(func(unit: Dictionary)->bool:return unit.id==id)[0]).distance_to(Vector2(float(point[0]),float(point[1])))<=0.1,"The actual escort reaches its public lateral turn goal")
	return true

func _park_outside(sim: RefCounted, finish: Dictionary, physical: Dictionary) -> bool:
	# The two rear operators leave first. Parking them one metre farther to
	# the same authored side leaves the front operators' exterior approach
	# grid nodes free. Every stage is real MOVE, with the original four final
	# goals retained; simultaneous parking previously trapped BRAVO behind
	# DELTA's completed rear goal and renewed avoidance for thirty seconds.
	var targets: Dictionary = finish.outside_targets
	check(ORDER.all(func(id: String)->bool:return targets.has(id)),"Four distinct physical exterior goals supplies distinct authored goals for all four operators")
	if not ORDER.all(func(id: String)->bool:return targets.has(id)): return false
	var exit_id := str(finish.via_doors[-1])
	var exit: Dictionary = sim.mission.doors.filter(func(door: Dictionary)->bool:return str(door.id)==exit_id)[0]
	var rear: Array[String] = ["charlie","delta"]
	var temporary: Dictionary = {}
	# An own SECURE receipt and last observation identify these civilians
	# even during temporary loss of sight. Reassignment uses only those known
	# IDs, never a hidden current position. Transfer them before leaving the
	# room so FOLLOW remains behind the rear pair throughout the return.
	var observed: Array = sim.snapshot(false).civilians.filter(func(civilian: Dictionary)->bool:return bool(civilian.get("secured",false)) and (bool(civilian.get("visible",false)) or civilian.has("last_seen")))
	check(observed.size()<=rear.size(),"Observed secured civilians have distinct rear escorts at the final original exterior goals")
	if observed.size()>rear.size(): return false
	for index: int in range(observed.size()):
		if str(observed[index].get("follow_unit_id",""))==rear[index]: continue
		_issue(sim,rear[index],"SECURE_CIVILIAN",{"civilian_id":str(observed[index].id)})
		if not _wait_idle(sim,physical,"Rear operators actually take over their known secured followers before the physical return"): return false
	# Known FOLLOW needs the extra physical depth so civilians stay behind
	# the temporary row. Explicit public course parking preserves the same
	# already verified SH01/HI route without imposing that depth elsewhere.
	var depth_margin := maxf(float(finish.get("rear_depth_margin",0.0)),1.0 if not observed.is_empty() else 0.0)
	for id: String in rear:
		var goal: Array = targets[id]
		temporary[id] = [float(goal[0])+signf(float(goal[0])-float(exit.x)),float(goal[1])+signf(float(goal[1])-float(exit.z))*depth_margin]
	if not _move_group(sim,temporary,rear,physical,"Rear operators physically leave the exterior approach lanes free"): return false
	if not _move_group(sim,targets,["alpha","bravo"],physical,"Front operators reach their original exterior goals"): return false
	if not _move_group(sim,targets,rear,physical,"Rear operators reach their original exterior goals"): return false
	check(ORDER.all(func(id: String)->bool:return _position(sim.units.filter(func(unit: Dictionary)->bool:return unit.id==id)[0]).distance_to(Vector2(float(targets[id][0]),float(targets[id][1])))<=0.1),"Four distinct physical exterior goals reach every actual owned goal within 0.1m")
	return true

func _formation_leg(sim: RefCounted, leg: Dictionary, physical: Dictionary, plans: Array) -> bool:
	if leg.has("transition_before"):
		if not _move_stage(sim,leg.transition_before.targets,physical,"Operators physically stage in the next known training corridor"): return false
	var time_before := float(sim.time)
	var tick_before := int(sim.tick)
	var rng_before := _rng(sim)
	var planned: Dictionary = sim.plan_formation(leg.target,str(leg.kind),ORDER,{})
	plans.append(planned.duplicate(true))
	check(bool(planned.get("ok",false)),"Course %s plans an actual %s formation: %s" % [sim.mission.id,leg.kind,str(planned)])
	check(sim.time==time_before and sim.tick==tick_before and _rng(sim)==rng_before,"Formation expansion consumes no simulation time, ticks or RNG draws")
	check(sim.units.all(func(unit: Dictionary)->bool:return _pending(unit).size()<=32),"Expanded formation macros retain the existing per-unit pending command cap")
	if not bool(planned.get("ok",false)) or not _wait_idle(sim,physical,str(leg.kind)): return false
	check(planned.slots.all(func(slot: Dictionary)->bool:return _position(sim.units.filter(func(unit: Dictionary)->bool:return unit.id==slot.unit_id)[0]).distance_to(Vector2(float(slot.target[0]),float(slot.target[1])))<=0.1),"Formation participants reach all real authored role goals")
	return true

func _course(id: String) -> Dictionary:
	var data: Dictionary = Catalog.load(id)
	check(not data.is_empty(),id+" loads its authored catalog mission")
	if data.is_empty(): return {"id":id,"loaded":false}
	var spec: Dictionary = course_specs[id]
	check(int(data.seed)==int(spec.seed),id+" uses its unchanged authored default seed")
	var sim: RefCounted = Simulation.new()
	sim.load_mission(data)
	var physical := {"max_step":0.0,"min_spacing":INF,"leaf_clear":true,"static_clear":true}
	var plans: Array = []
	var stages: Array = []
	var complete := true
	for leg: Dictionary in spec.get("formation_legs",[]):
		if not _formation_leg(sim,leg,physical,plans):
			complete = false
			break
	if complete and spec.has("transition_after_formations"):
		complete = _move_stage(sim,spec.transition_after_formations.targets,physical,"Formation operators physically return to the known preparation area")
	if complete:
		for leg: Dictionary in spec.legs:
			for action: Dictionary in leg.get("pre_actions",[]):
				_issue(sim,str(action.unit_id),str(action.type),action.args)
				if not _wait_idle(sim,physical,str(action.type)):
					complete = false
					break
			if not complete: break
			var planned := _room_plan(sim,str(leg.door_id),str(leg.room_id),physical,{},leg.get("order_ids",ORDER),bool(leg.get("stage_stacks",false)))
			plans.append(planned.duplicate(true))
			if planned.is_empty() or not bool(planned.get("ok",false)) or not _wait_room(sim,str(leg.room_id),planned,physical):
				complete = false
				break
			stages.append({"door_id":leg.door_id,"room_id":leg.room_id,"clear_tick":sim.tick,"time":sim.time})
			print("SHOOT_HOUSE_STAGE "+JSON.stringify({"id":id,"door_id":leg.door_id,"room_id":leg.room_id,"tick":sim.tick,"seconds":sim.time}))
			if bool(leg.get("recover_short",false)) and not _recover_short(sim,str(leg.room_id),planned,physical):
				complete = false
				break
	if complete:
		var return_leg: Dictionary = spec.finish.return_leg
		if not return_leg.is_empty():
			var returned := _room_plan(sim,str(return_leg.door_id),str(return_leg.room_id),physical,{},return_leg.get("order_ids",ORDER))
			plans.append(returned.duplicate(true))
			complete = not returned.is_empty() and bool(returned.get("ok",false)) and _wait_room(sim,str(return_leg.room_id),returned,physical)
	if complete:
		# Returning through a previously searched room does not require a
		# second assault/assembly. Open the observed connecting door with the
		# nearest owned operator; exterior MOVE still physically leaves and
		# marks the original last room before reaching the original goals.
		for return_door: String in spec.finish.get("open_doors",[]):
			if not _observe_door(sim,return_door,physical): complete = false; break
			var door: Dictionary = sim.mission.doors.filter(func(candidate: Dictionary)->bool:return candidate.id==return_door)[0]
			var operator := _nearest_idle(sim,Door.handle_floor(door))
			check(not operator.is_empty(),"An owned live operator opens the actual observed return door")
			if operator.is_empty(): complete = false; break
			_issue(sim,str(operator.id),"OPEN_DOOR",{"door_id":return_door})
			if not _wait_idle(sim,physical,"Actual connecting door opens for the physical return"): complete = false; break
	if complete:
		var exit_id := str(spec.finish.via_doors[-1])
		complete = _observe_door(sim,exit_id,physical)
		if complete:
			_issue(sim,"alpha","OPEN_DOOR",{"door_id":exit_id})
			complete = _wait_idle(sim,physical,"Final real opened exit")
	if complete:
		complete = _park_outside(sim,spec.finish,physical)
	if complete and sim.result.is_empty():
		var zone: Array = spec.finish.zone
		_issue(sim,str(spec.finish.finish_unit_id),"MOVE",{"target":[float(zone[0]),float(zone[1])]})
		for _tick: int in range(300):
			_step(sim,physical)
			if not sim.result.is_empty(): break
	var final: Dictionary = sim.snapshot(true)
	check(complete and not sim.result.is_empty() and bool(sim.result.get("success",false)),id+" actually completes every authored mission rule")
	check(float(sim.time)>=30.0 and float(sim.time)<=90.0,id+" actual course duration is 30–90 seconds without clock or WAIT padding")
	check(sim.command_failures==0 and sim.units.all(func(unit: Dictionary)->bool:return float(unit.hp)>0.0),id+" course keeps valid actual plans and all four operators alive")
	check(float(physical.max_step)<=0.115 and float(physical.min_spacing)>=0.46 and bool(physical.leaf_clear) and bool(physical.static_clear),id+" every physical STEP preserves movement, friendly body spacing, static geometry and door leaves")
	check(sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.type!="WAIT")),id+" primitive histories contain no duration-padding WAIT commands")
	var indoor: Array = data.rooms.filter(func(room: Dictionary)->bool:return bool(room.get("indoor",true)))
	check(indoor.all(func(room: Dictionary)->bool:return final.room_states[str(room.id)].state in ["CLEAR","MARKED"]),id+" all real authored indoor rooms remain clear or marked")
	check(final.room_states[str(spec.legs[-1].room_id)].state=="MARKED",id+" physically exits and marks the last cleared course room")
	var finish_zone := Rect2(Vector2(float(spec.finish.zone[0]),float(spec.finish.zone[1]))-Vector2(float(spec.finish.zone[2]),float(spec.finish.zone[3]))*0.5,Vector2(float(spec.finish.zone[2]),float(spec.finish.zone[3])))
	check(sim.units.any(func(unit: Dictionary)->bool:return finish_zone.has_point(_position(unit))),id+" a live operator physically reaches the authored finish zone")
	# The player projection deliberately omits internal actor and primitive
	# fields. These authority copies are verification evidence only, never a
	# source of target choices in the public planning controller above.
	var state := JSON.stringify({"record":final,"actors":{"units":sim.units,"enemies":sim.enemies,"civilians":sim.civilians,"doors":sim.doors},"rng":_rng(sim),"plans":plans})
	var summary := {"id":id,"seed":int(data.seed),"mission_hash":JSON.stringify(data).sha256_text(),"success":bool(sim.result.get("success",false)),"tick":sim.tick,"seconds":sim.time,"stages":stages,"physical":physical,"command_failures":sim.command_failures,"plan_count":plans.size(),"state_hash":state.sha256_text(),"state":state}
	print("SHOOT_HOUSE_COURSE "+JSON.stringify({"id":id,"success":summary.success,"tick":sim.tick,"seconds":sim.time,"stages":stages,"physical":physical,"plan_count":plans.size()}))
	return summary

func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var probe := arguments.has("--probe-only")
	var verify_course := false
	var selected := "SH01"
	for argument: String in arguments:
		if argument.begins_with("--probe-course="):
			probe = true
			selected = argument.get_slice("=",1)
		if argument.begins_with("--verify-course="):
			verify_course = true
			selected = argument.get_slice("=",1)
	check(not (probe or verify_course) or selected in COURSE_IDS,"A focused probe or repeat verification selects one authored shoot-house course")
	report["repetitions"] = 1 if probe else 2
	report["source_hashes"] = {}
	for path: String in ["res://tests/shoot_house_test.gd","res://scripts/simulation.gd","res://scripts/room_drill.gd","res://scripts/formation_drill.gd"]:
		report.source_hashes[path] = FileAccess.get_file_as_string(path).sha256_text()
	if course_specs.is_empty():
		check(false,"Course specifications are embedded in the test before execution")
		print("BREACH_SHOOT_HOUSE_RESULT checks=%d failures=%d" % [checks,failures.size()])
		quit(1)
		return
	for id: String in COURSE_IDS:
		if (probe or verify_course) and id!=selected: continue
		var first := _course(id)
		if not probe:
			var second := _course(id)
			check(first==second,id+" default authored seed repeats actual completion, full final state, plan and four RNG streams")
			first["repeat_identical"] = first==second
		report.courses.append(first)
	var directory := ProjectSettings.globalize_path("res://").path_join("../tests/artifacts/cqb-p7")
	DirAccess.make_dir_recursive_absolute(directory)
	var filename := "shoot-house-probe-%s.json" % selected if probe else "shoot-house-actual.json"
	if verify_course and not probe: filename = "shoot-house-verify-%s.json" % selected
	var file := FileAccess.open(directory.path_join(filename),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  ")+"\n")
	print("BREACH_SHOOT_HOUSE_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
