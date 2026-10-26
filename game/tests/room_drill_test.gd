extends SceneTree
## P2 executes the player's expanded primitive queues at exactly 30 Hz.
## The benchmark compares matching actors, room, door, goals, pace and window.
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Navigation = preload("res://scripts/navigation.gd")
const AllLeftFixture = preload("res://tests/room_drill_all_left_fixture.gd")
const STEP := 1.0 / 30.0
const SEEDS := 30
const BENCH_TICKS := 450
const ORDER: Array[String] = ["alpha", "bravo", "charlie", "delta"]
var checks := 0
var failures: Array[String] = []
var report: Dictionary = {"step":STEP, "seeds":[0,29], "ticks":BENCH_TICKS,
	"scope":"An empty enclosed 5x5m room with a 1.8m wooden door opening inward (swing_sign=+1); four standard rifles at the same outside starting positions. Manual uses competent stack/A/open/B/direct-goal primitive planning with event-driven signal release, without arbitrary waits. Both samples run the same fixed window. Actual goal arrival is measured independently within 0.1m, not the P0 doorway-depth proxy."}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or "--contracts-only" in args:
		_atomic_contracts()
		_expansion_contracts()
		_metadata_contracts()
		_signal_contracts()
		_method_contracts()
		_sector_contracts()
		_expanded_sector_contracts()
		_requested_order_contract()
		_approach_contracts()
		_all_left_contracts()
	if "--approach-only" in args:
		_approach_contracts()
		_all_left_contracts()
	if args.is_empty() or "--benchmarks-only" in args:
		_benchmark()
		_write_report()
	if "--probe-only" in args:
		print("ROOM_DRILL_PROBE " + JSON.stringify({"drill":measured_case(0,"drill"),"manual":measured_case(0,"manual")}))
	print("BREACH_ROOM_DRILL_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func fixture(seed_value: int = 0, pace: String = "normal") -> Dictionary:
	# The inward leaf places ranks 1/3 at the right jamb and 2/4 at the left.
	# Both matched plans start at this identical, physically reachable stack.
	var positions: Array = [[9.3,10.95], [6.7,10.95], [9.3,11.65], [6.7,11.65]]
	var units: Array = []
	for index: int in range(4):
		var origin := Vector2(float(positions[index][0]),float(positions[index][1]))
		units.append({"id":ORDER[index],"x":origin.x,"z":origin.y,"facing":(Vector2(8.0,10.5)-origin).angle(),"weapon":"standard","reserve_ammo":72,"breaches":2,"stuns":2,"movement_mode":pace})
	return {"id":"ROOM_DRILL", "seed":seed_value, "variant":"normal", "bounds":[16,16],
		"rooms":[{"id":"room","x":8.0,"z":8.0,"w":5.0,"d":5.0,"indoor":true}, {"id":"outside","x":8.0,"z":13.25,"w":16.0,"d":5.5,"indoor":false}],
		"walls":[{"id":"west","x":5.5,"z":8.0,"w":0.2,"d":5.0}, {"id":"east","x":10.5,"z":8.0,"w":0.2,"d":5.0}, {"id":"north","x":8.0,"z":5.5,"w":5.0,"d":0.2}, {"id":"south_left","x":6.25,"z":10.5,"w":1.5,"d":0.2}, {"id":"south_right","x":9.75,"z":10.5,"w":1.5,"d":0.2}],
		"doors":[{"id":"d1","x":8.0,"z":10.5,"w":1.8,"d":0.2,"axis":"x","state":"CLOSED","hinge_side":-1.0,"swing_sign":1.0,"locked":false,"hp":100.0,"material":"wood"}],
		"props":[],"units":units,"enemies":[],"civilians":[],"win":[{"type":"reach_zone","zone":[15.0,15.0,0.1,0.1]}],"fail":[]}

func simulation(data: Dictionary) -> RefCounted:
	var sim: RefCounted = Simulation.new()
	sim.load_mission(data)
	return sim

func point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

func position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x),float(actor.z))

func issue(sim: RefCounted, id: String, type: String, args: Dictionary = {}) -> Dictionary:
	var answer: Dictionary = sim.issue(id,type,args,true)
	check(bool(answer.get("ok",false)), "%s %s accepted: %s" % [id,type,answer.get("message","")])
	return answer

func active(unit: Dictionary) -> Dictionary:
	for command: Dictionary in unit.commands:
		if command.state not in ["SUCCEEDED","CANCELLED"]: return command
	return {}

func advance(sim: RefCounted, ticks: int) -> void:
	for _tick: int in range(ticks): sim.step(STEP)

func fingerprint(sim: RefCounted) -> String:
	return JSON.stringify({"state":sim.snapshot(true),"units":sim.units,"doors":sim.doors,
		"sequence":sim._sequence,"command_sequence":sim._command_sequence,"drill_sequence":sim._drill_sequence,"requests":sim._requests,
		"revisions":sim.plan_revisions,"sync_waits":sim._sync_waits,"sync_requests":sim._sync_requests,
		"nav_revision":sim.nav.revision,"known_flash_key":sim._known_flash_key,"known_flash_doors":sim._known_flash_doors,
		"reservations":sim._reservations,"flash_barriers":sim._flash_door_barriers,
		"preview_depth":sim._preview_batch_depth,"preview_dirty":sim._preview_dirty_units,
		"insert_index":sim._insert_resource_index,"pause":sim.pause_requested,
		"rng":[sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]})

func slots(answer: Dictionary) -> Array:
	return answer.get("slots",[])

func all_waiting(sim: RefCounted, channel: String) -> bool:
	for unit: Dictionary in sim.units:
		var command := active(unit)
		if command.get("type","")!="WAIT_FOR_SIGNAL" or command.get("state","")!="WAITING" or command.args.get("signal","")!=channel: return false
	return true

func manual_plan(sim: RefCounted, preview: Dictionary) -> void:
	var layout := slots(preview)
	check(layout.size()==4,"Competent manual route uses all four preview goals")
	if layout.size()!=4: return
	for index: int in range(4):
		var slot: Dictionary = layout[index]
		issue(sim,ORDER[index],"MOVE",{"target":slot.stack})
		issue(sim,ORDER[index],"WAIT_FOR_SIGNAL",{"signal":"A"})
		if index==0: issue(sim,ORDER[index],"OPEN_DOOR",{"door_id":"d1"})
		issue(sim,ORDER[index],"WAIT_FOR_SIGNAL",{"signal":"B"})
		issue(sim,ORDER[index],"MOVE",{"target":slot.domination})
		issue(sim,ORDER[index],"FACE",{"target":slot.face_target})

func measured_case(seed_value: int, method: String) -> Dictionary:
	var sim := simulation(fixture(seed_value))
	var preview: Dictionary = sim.room_entry_preview("d1","OPEN_DOOR",ORDER,{})
	check(bool(preview.get("ok",false)),"seed %d %s pure room preview accepted: %s" % [seed_value,method,str(preview)])
	var layout := slots(preview)
	check(layout.size()==4,"seed %d %s has four physical goals" % [seed_value,method])
	if layout.size()!=4: return {"seed":seed_value,"method":method,"valid":false,"preview":preview}
	var planned: Dictionary = {}
	if method=="drill":
		planned = sim.plan_room_entry("d1","OPEN_DOOR",ORDER,{})
		check(bool(planned.get("ok",false)),"seed %d actual room macro accepted" % seed_value)
	else: manual_plan(sim,preview)
	var arrivals: Dictionary = {}
	var crossings: Array = []
	var first_crossing: Dictionary = {}
	var opened_at := -1.0
	var released_a := false
	var released_b := false
	var continuous := true
	var separated := true
	var leaf_clear := true
	var all_final := true
	var trace: Array = []
	for frame: int in range(BENCH_TICKS):
		if method=="manual":
			if not released_a and all_waiting(sim,"A"):
				sim.release_signal("A")
				released_a = true
			if released_a and not released_b and sim.doors[0].state=="OPEN" and all_waiting(sim,"B"):
				sim.release_signal("B")
				released_b = true
		var previous: Array = sim.units.map(func(unit: Dictionary) -> Vector2: return position(unit))
		sim.step(STEP)
		if "--probe-only" in OS.get_cmdline_user_args() and frame%15==0 and frame<240:
			trace.append({"tick":sim.tick,"units":sim.units.map(func(unit: Dictionary)->Dictionary: return {"id":unit.id,"position":[unit.x,unit.z],"active":active(unit).duplicate(true)})})
		if opened_at<0.0 and sim.doors[0].state=="OPEN": opened_at = sim.time
		for index: int in range(4):
			var unit: Dictionary = sim._find(sim.units,ORDER[index])
			var here := position(unit)
			continuous = continuous and here.distance_to(previous[index])<=0.115
			leaf_clear = leaf_clear and not Door.overlaps_actor(sim.doors[0],-1.0,here,Navigation.RADIUS)
			for other: int in range(index): separated = separated and here.distance_to(position(sim.units[other]))>=Navigation.RADIUS*2.0-0.0001
			if not first_crossing.has(unit.id) and previous[index].y>10.5 and here.y<=10.5:
				first_crossing[unit.id] = sim.tick
				crossings.append(unit.id)
			if opened_at>=0.0 and not arrivals.has(unit.id) and here.distance_to(point(layout[index].domination))<=0.1:
				arrivals[unit.id] = sim.time-opened_at
	for index: int in range(4):
		all_final = all_final and position(sim._find(sim.units,ORDER[index])).distance_to(point(layout[index].domination))<=0.1
	var metrics: Dictionary = sim._statistics()
	var dwell := 0.0
	for id: String in ORDER: dwell += float(metrics.doorway_dwell.get(id,0.0))
	var elapsed := -1.0
	if arrivals.size()==4:
		elapsed = 0.0
		for value: float in arrivals.values(): elapsed = maxf(elapsed,value)
	var entry: Dictionary = metrics.time_to_dominate.get("d1",{})
	check(opened_at>=0.0 and sim.command_failures==0,"seed %d %s opens its real door without command failures" % [seed_value,method])
	check(arrivals.size()==4 and all_final,"seed %d %s all four actual domination goals reached within 0.1m" % [seed_value,method])
	check(continuous and separated and leaf_clear,"seed %d %s preserves continuous body and leaf physics" % [seed_value,method])
	if method=="drill":
		check(entry.get("participants",[]).size()==4 and entry.get("arrived",[]).size()==4 and float(entry.get("seconds",-1.0))>=0.0,"seed %d four drill participants complete the authoritative metric" % seed_value)
		check(elapsed>=0.0 and absf(float(entry.get("seconds",-1.0))-elapsed)<=STEP+0.000001,"seed %d metric records actual goals, independently measured" % seed_value)
		check(crossings==ORDER,"seed %d physical plane crossing follows requested drill order" % seed_value)
	return {"seed":seed_value,"method":method,"valid":true,"opened_at":opened_at,"actual_domination_seconds":elapsed,
		"arrivals":arrivals,"metric":entry,"crossings":crossings,"crossing_ticks":first_crossing,
		"doorway_dwell":metrics.doorway_dwell,"dwell_per_operator":dwell/4.0,"failures":sim.command_failures,
		"final_goals":all_final,"continuous":continuous,"separated":separated,"leaf_clear":leaf_clear,
		"final_units":sim.units.map(func(unit: Dictionary) -> Dictionary: return {"id":unit.id,"position":[unit.x,unit.z],"active":active(unit)}),
		"goals":layout,
		"trace":trace,
		"state_hash":fingerprint(sim).sha256_text()}

func _benchmark() -> void:
	var rows: Array = []
	var drill_seconds := 0.0
	var drill_dwell := 0.0
	var manual_dwell := 0.0
	for seed_value: int in range(SEEDS):
		var drill := measured_case(seed_value,"drill")
		var manual := measured_case(seed_value,"manual")
		var repeated_drill := measured_case(seed_value,"drill")
		var repeated_manual := measured_case(seed_value,"manual")
		check(JSON.stringify(drill)==JSON.stringify(repeated_drill) and JSON.stringify(manual)==JSON.stringify(repeated_manual),"seed %d repeats full plans, actual arrivals, metrics and RNG states deterministically" % seed_value)
		rows.append({"seed":seed_value,"drill":drill,"manual":manual})
		drill_seconds += float(drill.get("actual_domination_seconds",-1.0))
		drill_dwell += float(drill.get("dwell_per_operator",0.0))
		manual_dwell += float(manual.get("dwell_per_operator",0.0))
	var means := {"actual_domination_seconds":drill_seconds/SEEDS,"drill_dwell":drill_dwell/SEEDS,"manual_dwell":manual_dwell/SEEDS}
	check(float(means.actual_domination_seconds)>=0.0 and float(means.actual_domination_seconds)<=3.0,"Thirty-seed mean reaches all four actual domination goals within three seconds")
	report["benchmark"] = {"means":means,"cases":rows,"pace":"normal","door_width":1.8,"goal_tolerance":0.1}
	print("ROOM_DRILL_BENCHMARK " + JSON.stringify(means))

func rejected_atomically(sim: RefCounted, door_id: String, method: String, order_ids: Array, options: Dictionary, label: String) -> void:
	var before := fingerprint(sim)
	var answer: Dictionary = sim.plan_room_entry(door_id,method,order_ids,options)
	check(not bool(answer.get("ok",false)),label+" rejects its invalid plan")
	check(fingerprint(sim)==before,label+" preserves all commands, IDs, requests, revisions, preview batch, owners, pause and RNG states")

func _atomic_contracts() -> void:
	var sim := simulation(fixture())
	issue(sim,"alpha","WAIT",{"duration":0.0,"request_id":"before-invalid"})
	rejected_atomically(sim,"d1","OPEN_DOOR",["alpha","bravo","charlie","missing"],{},"Unknown fourth participant")
	rejected_atomically(sim,"d1","OPEN_DOOR",["alpha","bravo","charlie","alpha"],{},"Duplicate fourth participant")
	rejected_atomically(sim,"missing","OPEN_DOOR",ORDER,{},"Unknown door")
	rejected_atomically(sim,"d1","ENTER_ROOM",ORDER,{},"Unsupported primitive method")
	var blocked_data := fixture()
	blocked_data.props = [{"id":"filled_room","x":8.0,"z":8.0,"w":4.9,"d":4.9,"solid":true,"height":2.0}]
	rejected_atomically(simulation(blocked_data),"d1","OPEN_DOOR",ORDER,{},"No walkable domination goals")
	var limited := simulation(fixture())
	for index: int in range(32): issue(limited,"delta","WAIT",{"duration":0.0,"request_id":"limit-%d"%index})
	rejected_atomically(limited,"d1","OPEN_DOOR",ORDER,{},"Fourth participant's 32-command limit")
	var owner := simulation(fixture())
	issue(owner,"alpha","OPEN_DOOR",{"door_id":"d1"})
	for _tick: int in range(150):
		owner.step(STEP)
		if owner.doors[0].owner_id=="alpha": break
	check(owner.doors[0].owner_id=="alpha","Ownership fixture starts the actual operator's door command")
	rejected_atomically(owner,"d1","OPEN_DOOR",ORDER,{"append":false},"Selected operator owns a running door command")
	var empty_shotgun_data := fixture()
	empty_shotgun_data.units[0].weapon = "shotgun"
	empty_shotgun_data.units[0].ammo = 0
	empty_shotgun_data.units[0].reserve_ammo = 0
	rejected_atomically(simulation(empty_shotgun_data),"d1","SHOTGUN_BREACH",ORDER,{},"Empty owned shotgun")
	var reserved_shotgun_data := fixture()
	reserved_shotgun_data.units[0].weapon = "shotgun"
	reserved_shotgun_data.units[0].ammo = 1
	reserved_shotgun_data.doors.append({"id":"d2","x":14.0,"z":13.0,"w":1.8,"d":0.2,"axis":"x"})
	var reserved_shotgun := simulation(reserved_shotgun_data)
	issue(reserved_shotgun,"alpha","SHOTGUN_BREACH",{"door_id":"d2"})
	rejected_atomically(reserved_shotgun,"d1","SHOTGUN_BREACH",ORDER,{},"A pending breach keeps the only shotgun round reserved")
	var borrowed := fixture()
	borrowed.units[1].weapon = "shotgun"
	rejected_atomically(simulation(borrowed),"d1","SHOTGUN_BREACH",ORDER,{},"Cannot borrow another operator's shotgun")
	var charge_data := fixture()
	charge_data.units[0].breaches = 1
	charge_data.doors.append({"id":"d2","x":14.0,"z":13.0,"w":1.8,"d":0.2,"axis":"x"})
	var charges := simulation(charge_data)
	issue(charges,"alpha","BREACH_DOOR",{"door_id":"d2"})
	rejected_atomically(charges,"d1","BREACH_DOOR",ORDER,{},"Pending charge remains reserved")
	for options: Dictionary in [{"signal":"D"},{"delay_ticks":-1},{"delay_ticks":1.5},{"operator_id":"missing"},{"unknown":true}]:
		rejected_atomically(simulation(fixture()),"d1","OPEN_DOOR",ORDER,options,"Invalid macro options "+str(options))
	var unseen_data := fixture()
	for unit: Dictionary in unseen_data.units: unit.facing = PI*0.5; unit.fov = 20.0
	rejected_atomically(simulation(unseen_data),"d1","OPEN_DOOR",ORDER,{},"Unobserved selected door")

func stage_commands(unit: Dictionary, stage: String) -> Array:
	return unit.commands.filter(func(command: Dictionary) -> bool: return command.args.get("drill",{}).get("stage","")==stage)

func _expansion_contracts() -> void:
	var sim := simulation(fixture())
	var before := fingerprint(sim)
	var preview: Dictionary = sim.room_entry_preview("d1","OPEN_DOOR",ORDER,{"go_long":true})
	check(bool(preview.get("ok",false)) and fingerprint(sim)==before,"Pure preview preserves every simulation and RNG field")
	var rng_before: Array = [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]
	var planned: Dictionary = sim.plan_room_entry("d1","OPEN_DOOR",ORDER,{"go_long":true})
	check(bool(planned.get("ok",false)),"Four-person go-long macro expands successfully")
	check(sim.tick==0 and sim.time==0.0 and rng_before==[sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state],"Successful macro expansion advances neither simulation time nor any RNG stream")
	check("ENTER_ROOM" not in Simulation.COMMANDS and "GO_LONG" not in Simulation.COMMANDS,"Drills add no replay primitive types")
	var ids: Dictionary = {}
	var door_commands := 0
	for index: int in range(4):
		var unit: Dictionary = sim._find(sim.units,ORDER[index])
		var ready := stage_commands(unit,"ready")
		var entry_wait := stage_commands(unit,"entry").filter(func(command: Dictionary) -> bool: return command.type=="WAIT_FOR_SIGNAL")
		check(ready.size()==1 and entry_wait.size()==1,"Rank %d has distinct ready and post-door barriers" % (index+1))
		for command: Dictionary in unit.commands:
			check(command.type in Simulation.COMMANDS,"Expanded command remains an existing primitive")
			var metadata: Dictionary = command.args.get("drill",{})
			var keys: Array = metadata.keys()
			keys.sort()
			check(keys==["door_id","order","room_id","stage","sync_id"] and metadata.get("order",0)==index+1,"Every primitive retains only canonical optional drill metadata")
			check(not ids.has(command.id) and command.state=="PENDING","Expanded commands have unique IDs and execute only after step")
			ids[command.id] = true
			if command.type in Simulation.OPEN_COMMANDS: door_commands += 1
		var long_moves := stage_commands(unit,"go_long").filter(func(command: Dictionary) -> bool: return command.type=="MOVE")
		check(long_moves.size()==(1 if index<2 else 0),"Only ranks one and two receive go-long movement")
	check(door_commands==1,"Exactly one operator receives the actual door primitive")
	var ready_id := str(planned.get("sync_id",""))+":ready"
	var changed: Dictionary = sim.update_room_drill_delay(ready_id,15)
	check(bool(changed.get("ok",false)) and changed.get("updated",0)==4,"Editing the pending ready block updates all four participants atomically")
	check(sim.units.all(func(unit: Dictionary) -> bool: return stage_commands(unit,"ready")[0].args.delay_ticks==15),"Group delay is identical in every participant's saved primitive args")
	advance(sim,2)
	before = fingerprint(sim)
	changed = sim.update_room_drill_delay(ready_id,4)
	check(not bool(changed.get("ok",false)) and fingerprint(sim)==before,"Editing a started ready group rejects atomically")
	var hidden_a := fixture()
	hidden_a.enemies = [{"id":"hidden","x":6.5,"z":6.5,"facing":0.0,"can_surrender":false}]
	var hidden_b := hidden_a.duplicate(true)
	hidden_b.enemies[0].x = 9.5
	var first := simulation(hidden_a)
	var second := simulation(hidden_b)
	var first_preview: Dictionary = first.room_entry_preview("d1","OPEN_DOOR",ORDER,{})
	var second_preview: Dictionary = second.room_entry_preview("d1","OPEN_DOOR",ORDER,{})
	check(JSON.stringify(first_preview)==JSON.stringify(second_preview),"Unobserved enemy coordinates cannot affect the drill preview")
	first.plan_room_entry("d1","OPEN_DOOR",ORDER,{})
	second.plan_room_entry("d1","OPEN_DOOR",ORDER,{})
	check(JSON.stringify(first.units.map(func(unit: Dictionary) -> Array: return unit.commands))==JSON.stringify(second.units.map(func(unit: Dictionary) -> Array: return unit.commands)),"Unobserved enemy coordinates cannot affect expanded primitive planning")
	var short_data := fixture()
	short_data.rooms[0] = {"id":"room","x":8.0,"z":9.0,"w":3.0,"d":3.0,"indoor":true}
	short_data.walls = [{"id":"west","x":6.5,"z":9.0,"w":0.2,"d":3.0},{"id":"east","x":9.5,"z":9.0,"w":0.2,"d":3.0},{"id":"north","x":8.0,"z":7.5,"w":3.0,"d":0.2}]
	var short_sim := simulation(short_data)
	var short_answer: Dictionary = short_sim.plan_room_entry("d1","OPEN_DOOR",ORDER,{})
	check(bool(short_answer.get("ok",false)) and bool(short_answer.get("short_room",false)),"A small room receives a short-room macro: "+str(short_answer))
	if bool(short_answer.get("ok",false)):
		for index: int in [2,3]:
			var unit: Dictionary = short_sim.units[index]
			check(stage_commands(unit,"guard").size()==1 and not unit.commands.any(func(command: Dictionary) -> bool: return command.type=="MOVE" and command.args.get("drill",{}).get("stage","") in ["entry","domination"]),"Short-room rear ranks guard outside without entry movement")
		advance(short_sim,BENCH_TICKS)
		check(short_sim.units.slice(2).all(func(unit: Dictionary) -> bool: return position(unit).y>10.5),"Actual short-room rear guards remain outside the door plane")
		for index: int in range(2): check(position(short_sim.units[index]).distance_to(point(short_answer.slots[index].domination))<=0.1,"Short-room entrant reaches its actual domination goal")

func _metadata_contracts() -> void:
	var sim := simulation(fixture())
	var base := {"sync_id":"metadata","door_id":"d1","room_id":"room","order":1,"stage":"entry"}
	var malformed: Array = []
	for modification: Dictionary in [{"order":0},{"order":1.5},{"stage":"secret"},{"door_id":"missing"},{"room_id":"missing"},{"unknown":true}]:
		var metadata: Dictionary = base.duplicate(true)
		metadata.merge(modification,true)
		malformed.append({"type":"MOVE","args":{"target":[9.3,10.95],"drill":metadata}})
	for sector: Dictionary in [{"start":0.0,"end":0.5,"duration":-1.0},{"start":0.0,"end":0.5,"duration":1.0,"unknown":true},{"start":NAN,"end":0.5,"duration":1.0},{"start":0.0,"end":PI+0.1,"duration":1.0}]:
		malformed.append({"type":"FACE","args":{"target":[8.0,8.0],"sector":sector}})
	for args: Dictionary in [{"signal":"A","auto_signal":true},{"signal":"A","sync_id":"bad space","auto_signal":true,"delay_ticks":0},{"signal":"A","sync_id":"ok","auto_signal":true,"delay_ticks":1.5}]: malformed.append({"type":"WAIT_FOR_SIGNAL","args":args})
	for node: Dictionary in malformed:
		var before := fingerprint(sim)
		var answer: Dictionary = sim.issue("alpha",str(node.type),node.args)
		check(not bool(answer.get("ok",false)) and fingerprint(sim)==before,"Malformed optional metadata rejects without command, request or RNG mutation")
	var accepted := issue(sim,"alpha","MOVE",{"target":[9.3,10.95],"drill":base,"sector":{"start":0,"end":1,"duration":2}})
	check(bool(accepted.get("ok",false)) and sim.units[0].commands[0].args.sector.duration is float,"Valid optional metadata canonicalizes inside the existing primitive args format")
	var coherent := simulation(fixture())
	sync_issue(coherent,"alpha","coherent","A",true,0)
	for mismatch: Dictionary in [{"signal":"B","sync_id":"coherent","auto_signal":true,"delay_ticks":0},{"signal":"A","sync_id":"coherent","auto_signal":false,"delay_ticks":0},{"signal":"A","sync_id":"coherent","auto_signal":true,"delay_ticks":1}]:
		var before := fingerprint(coherent)
		var answer: Dictionary = coherent.issue("bravo","WAIT_FOR_SIGNAL",mismatch)
		check(not bool(answer.get("ok",false)) and fingerprint(coherent)==before,"A saved sync group cannot acquire inconsistent channel, mode or delay metadata")
	var guarded := simulation(fixture())
	issue(guarded,"alpha","WAIT_FOR_SIGNAL",{"signal":"A","sync_id":"metadata:entry","auto_signal":true,"delay_ticks":0,"drill":base})
	for metadata: Dictionary in [{}, {"sync_id":"metadata","door_id":"d1","room_id":"room","order":2,"stage":"ready"}]:
		var args := {"signal":"A","sync_id":"metadata:entry","auto_signal":true,"delay_ticks":0}
		if not metadata.is_empty(): args["drill"] = metadata
		var before := fingerprint(guarded)
		var answer: Dictionary = guarded.issue("bravo","WAIT_FOR_SIGNAL",args)
		check(not bool(answer.get("ok",false)) and fingerprint(guarded)==before,"A sync group cannot strip or replace its post-door barrier metadata")

func sync_issue(sim: RefCounted, id: String, group: String, channel: String="A", automatic: bool=false, delay: int=0) -> Dictionary:
	return issue(sim,id,"WAIT_FOR_SIGNAL",{"signal":channel,"sync_id":group,"auto_signal":automatic,"delay_ticks":delay})

func _signal_contracts() -> void:
	for channel: String in ["A","B","C"]:
		var sim := simulation(fixture())
		sync_issue(sim,"alpha","paired",channel)
		sync_issue(sim,"bravo","paired",channel)
		sync_issue(sim,"charlie","other",("B" if channel=="A" else "A"))
		advance(sim,1)
		sim.release_signal(channel)
		check(sim.units[0].commands[0].state=="SUCCEEDED" and sim.units[1].commands[0].state=="SUCCEEDED" and sim.units[2].commands[0].state=="WAITING",channel+" releases only its complete named group")
	var delayed := simulation(fixture())
	sync_issue(delayed,"alpha","delay","A",true,6)
	issue(delayed,"bravo","WAIT",{"duration":0.3})
	sync_issue(delayed,"bravo","delay","A",true,6)
	var last_ready := -1
	var released_at := -1
	for _frame: int in range(40):
		delayed.step(STEP)
		if last_ready<0 and delayed.units[1].commands[1].state=="WAITING": last_ready = delayed.tick
		if delayed.units[0].commands[0].state=="SUCCEEDED": released_at = delayed.tick; break
	check(last_ready>1 and released_at==last_ready+6,"Automatic delay latches six fixed ticks after the last participant becomes ready")
	var removed := simulation(fixture())
	sync_issue(removed,"alpha","missing","A",true)
	issue(removed,"bravo","WAIT",{"duration":5.0})
	sync_issue(removed,"bravo","missing","A",true)
	advance(removed,1)
	check(removed.units[0].commands[0].state=="WAITING","An unready live group member initially blocks automatic release")
	removed.remove_command("bravo",1)
	advance(removed,1)
	check(removed.units[0].commands[0].state=="SUCCEEDED","Deleting an individual pending wait excludes it from group membership")
	var legacy := simulation(fixture())
	issue(legacy,"alpha","WAIT_FOR_SIGNAL",{"signal":"C"})
	issue(legacy,"bravo","WAIT",{"duration":0.2})
	issue(legacy,"bravo","WAIT_FOR_SIGNAL",{"signal":"C"})
	advance(legacy,1)
	legacy.release_signal("C")
	advance(legacy,20)
	check(legacy.units[0].commands[0].state=="SUCCEEDED" and legacy.units[1].commands[1].state=="WAITING","Legacy global signal remains a pulse and cannot release a future waiter")
	legacy.release_signal("C")
	check(legacy.units[1].commands[1].state=="SUCCEEDED","Legacy late waiter still accepts the next global signal")
	var edited := simulation(fixture())
	sync_issue(edited,"alpha","edited","A",true,0)
	sync_issue(edited,"bravo","edited","A",true,0)
	var changed: Dictionary = edited.update_command_args("alpha",0,{"signal":"B","sync_id":"edited","auto_signal":false,"delay_ticks":7})
	check(bool(changed.get("ok",false)) and edited.units.slice(0,2).all(func(unit: Dictionary)->bool: return unit.commands[0].args.signal=="B" and not bool(unit.commands[0].args.auto_signal) and int(unit.commands[0].args.delay_ticks)==7),"Editing a pending grouped wait changes its channel, automatic mode and delay across the complete cohort")
	var partial := simulation(fixture())
	sync_issue(partial,"alpha","partial","A",false,0)
	issue(partial,"bravo","WAIT",{"duration":1.0})
	sync_issue(partial,"bravo","partial","A",false,0)
	advance(partial,1)
	var unchanged := fingerprint(partial)
	changed = partial.update_command_args("bravo",1,{"signal":"C","sync_id":"partial","auto_signal":true,"delay_ticks":2})
	check(not bool(changed.get("ok",false)) and fingerprint(partial)==unchanged,"Editing one pending wait rejects atomically when any cohort member already started")
	var dead_data := fixture(8)
	dead_data.units[0].hp = 1.0
	for unit: Dictionary in dead_data.units: unit.ammo = 0; unit.reserve_ammo = 0
	dead_data.enemies = [{"id":"guard","x":12.0,"z":10.95,"facing":PI,"vision_range":4.0,"fov":80.0,"response_role":"guard","can_surrender":false}]
	var dead := simulation(dead_data)
	issue(dead,"alpha","WAIT",{"duration":10.0})
	sync_issue(dead,"alpha","casualty","A",true)
	sync_issue(dead,"bravo","casualty","A",true)
	advance(dead,1)
	check(dead.units[1].commands[0].state=="WAITING","A living participant's pending wait initially blocks the surviving member")
	for _frame: int in range(150):
		dead.step(STEP)
		if float(dead.units[0].hp)<=0.0: break
	advance(dead,1)
	check(float(dead.units[0].hp)<=0.0 and dead.units[1].commands[0].state=="SUCCEEDED","A participant killed by an actual hostile shot is excluded from its waiting group")

func _method_contracts() -> void:
	for method: String in Simulation.OPEN_COMMANDS:
		var data := fixture()
		if method=="KICK_DOOR": data.doors[0].kick_resistance = 1.0 # Probability remains covered by the P1 thirty-seed suite.
		if method=="BREACH_DOOR":
			# A destroyed leaf selects the opposite initial near corner; start at
			# its actual authored stack rather than invent cross-body traffic.
			for index: int in range(4):
				data.units[index].x = 6.7 if index%2==0 else 9.3
				data.units[index].facing = (Vector2(8.0,10.5)-position(data.units[index])).angle()
		if method=="SHOTGUN_BREACH": data.units[0].weapon = "shotgun"; data.units[0].ammo = 1
		var sim := simulation(data)
		var answer: Dictionary = sim.plan_room_entry("d1",method,ORDER,{})
		check(bool(answer.get("ok",false)),method+" expands through its real operator primitive: "+str(answer))
		if not bool(answer.get("ok",false)): continue
		check(stage_commands(sim._find(sim.units,"alpha"),"door")[0].type==method,method+" keeps the selected operator primitive in its expanded queue")
		var expected_order: Array = ["bravo","charlie","delta","alpha"] if method=="SHOTGUN_BREACH" else ORDER
		check(answer.order_ids==expected_order,method+" applies the correct entry order")
		var premature := false
		var flash_blind := false
		var charge_unsafe := false
		var metric_done := false
		var body_safe := true
		var continuous := true
		var crossing_order: Array = []
		var crossed: Dictionary = {}
		for _frame: int in range(BENCH_TICKS):
			var previous: Dictionary = {}
			for unit: Dictionary in sim.units: previous[unit.id] = position(unit)
			sim.step(STEP)
			var operator: Dictionary = sim._find(sim.units,"alpha")
			var actual_door: Dictionary = stage_commands(operator,"door")[0]
			for unit: Dictionary in sim.units:
				if position(unit).y<=10.5 and actual_door.state!="SUCCEEDED": premature = true
				flash_blind = flash_blind or float(unit.get("stunned",0.0))>0.0
				continuous = continuous and position(unit).distance_to(previous[unit.id])<=0.115
				if not crossed.has(unit.id) and previous[unit.id].y>10.5 and position(unit).y<=10.5: crossed[unit.id] = true; crossing_order.append(unit.id)
				for other: Dictionary in sim.units:
					if other.id!=unit.id: body_safe = body_safe and position(unit).distance_to(position(other))>=Navigation.RADIUS*2.0-0.0001
			# A charge is consumed when planted; safety applies at the actual
			# detonation, evidenced by the leaf becoming destroyed.
			if method=="BREACH_DOOR" and bool(sim.doors[0].destroyed) and not metric_done:
				for unit: Dictionary in sim.units: charge_unsafe = charge_unsafe or position(unit).distance_to(Vector2(8.0,10.5))<Simulation.BREACH_SAFE_DISTANCE-0.0001
				metric_done = true
		check(sim.doors[0].state=="OPEN" and sim.command_failures==0,method+" actually completes its door operation")
		if sim.doors[0].state!="OPEN": print("ROOM_DRILL_METHOD_PROBE "+JSON.stringify({"method":method,"door":sim.doors[0],"units":sim.units.map(func(unit: Dictionary)->Dictionary:return {"id":unit.id,"position":[unit.x,unit.z],"active":active(unit)})}))
		check(not premature,method+" holds every entrant behind the post-door barrier until operation success")
		check(not flash_blind and not charge_unsafe,method+" preserves friendly flash and charge safety")
		check(continuous and body_safe,method+" preserves continuous movement and physical teammate spacing")
		check(crossing_order==expected_order,method+" executes its actual plane crossings in doctrine order")
		for slot: Dictionary in answer.slots: check(position(sim._find(sim.units,str(slot.unit_id))).distance_to(point(slot.domination))<=0.1,method+" entrant reaches its actual domination goal")
		if method=="SHOTGUN_BREACH": check(sim.units[0].ammo==0 and sim.doors[0].destroyed,"Shotgun macro spends exactly the operator's one reserved round")
		if method=="OPEN_AND_FLASH": check(sim.stuns_used==1 and sim.units[0].stuns==1,"Flash macro executes its actual reserved flash throw")
		if method=="BREACH_DOOR": check(sim.breaches_used==1 and sim.units[0].breaches==1 and sim.doors[0].destroyed,"Charge macro plants and detonates exactly one owned charge")
	var reloading_data := fixture()
	reloading_data.units[0].weapon = "shotgun"
	reloading_data.units[0].ammo = 0
	reloading_data.units[0].reserve_ammo = 1
	var reloading := simulation(reloading_data)
	issue(reloading,"alpha","RELOAD")
	var reload_answer: Dictionary = reloading.plan_room_entry("d1","SHOTGUN_BREACH",ORDER,{})
	check(bool(reload_answer.get("ok",false)),"A preceding real reload supplies the owned shotgun macro round")
	advance(reloading,BENCH_TICKS)
	check(reloading.doors[0].destroyed and reloading.units[0].ammo==0 and reloading.command_failures==0,"Reload plus shotgun macro executes its reserved single round")
	var switching_data := fixture()
	switching_data.units[0].weapon = "shotgun"
	switching_data.units[0].sidearm = "pico_p1"
	switching_data.units[0].ammo = 1
	var switching := simulation(switching_data)
	issue(switching,"alpha","SWITCH_WEAPON",{"slot":"secondary"})
	advance(switching,30)
	check(switching.units[0].active_weapon=="secondary","Switch fixture actually equips the operator's sidearm")
	rejected_atomically(switching,"d1","SHOTGUN_BREACH",ORDER,{},"Equipped sidearm cannot supply a shotgun macro")
	issue(switching,"alpha","SWITCH_WEAPON",{"slot":"primary"})
	var switched_answer: Dictionary = switching.plan_room_entry("d1","SHOTGUN_BREACH",ORDER,{})
	check(bool(switched_answer.get("ok",false)),"A preceding primary switch supplies the operator's owned shotgun")
	advance(switching,BENCH_TICKS)
	check(switching.doors[0].destroyed and switching.command_failures==0 and switching.units[0].primary_ammo==0,"Primary switch plus macro spends only the owned shotgun round")

class SectorProbe extends "res://scripts/simulation.gd":
	var scores: Dictionary = {}
	var readiness: Dictionary = {}
	func _friendly_threat_score(unit: Dictionary, enemy: Dictionary) -> float:
		var value := super._friendly_threat_score(unit,enemy)
		if shots_fired==0:
			scores[enemy.id] = value
			readiness[enemy.id] = {"state":enemy.aim_state,"error":absf(angle_difference(float(enemy.aim_facing),(_position(unit)-_position(enemy)).angle())),"ammo":enemy.ammo}
		return value # Passive instrumentation leaves normal selection and combat untouched.

func sector_sample(sector: Dictionary, near_melee: bool=false, wrap: bool=false, expiry: bool=false, ready: bool=false) -> Dictionary:
	var inside: Array = [14.0,10.0]
	var outside: Array = [12.0,12.0]
	if near_melee: inside = [10.9,10.0]; outside = [10.0,10.8]
	if wrap: inside = [6.0,10.0]; outside = [7.4,11.5]
	if ready: inside = [15.0,10.0]; outside = [10.0,13.0]
	var sim := SectorProbe.new()
	sim.load_mission({"id":"ROOM_DRILL_SECTOR","seed":8,"bounds":[20,20],"walls":[],"props":[],"doors":[],"rooms":[],"units":[{"id":"alpha","x":10.0,"z":10.0,"facing":0.0,"fov":360.0,"hp":1000.0,"ammo":0 if expiry or ready else 24,"reserve_ammo":1}],"enemies":[{"id":"inside","x":inside[0],"z":inside[1],"facing":PI,"response_role":"guard","ammo":24 if ready else 0,"reserve_ammo":0,"vision_range":10.0 if ready else 0.1,"fov":360.0,"can_surrender":false,"hp":1000.0},{"id":"outside","x":outside[0],"z":outside[1],"facing":-PI*0.5,"response_role":"guard","ammo":24 if ready else 0,"reserve_ammo":0,"vision_range":10.0 if ready else 0.1,"fov":360.0,"can_surrender":false,"hp":1000.0}],"win":[{"type":"reach_zone","zone":[19.0,19.0,0.1,0.1]}],"fail":[]})
	# Each candidate lies within 45 degrees of this physical rifle heading.
	# Sector membership, rather than an impossible body/aim angle, decides fire.
	var args := {"target":[6.0,10.0] if wrap else [14.0,14.0],"persistent":true}
	if not sector.is_empty(): args["sector"] = sector
	issue(sim,"alpha","FACE",args)
	if expiry or ready: issue(sim,"alpha","RELOAD")
	for _frame: int in range(150):
		sim.step(STEP)
		if sim.shots_fired>0: break
	var target := ""
	for event: Dictionary in sim.events:
		if event.type=="SHOT" and not bool(event.get("hostile",false)): target = str(event.get("target_id",""))
	check(sim.shots_fired==1,"Sector sample executes its first actual shot through fixed steps")
	if sim.shots_fired!=1: print("ROOM_DRILL_SECTOR_PROBE "+JSON.stringify({"melee":near_melee,"wrap":wrap,"ready":ready,"unit":sim.units[0],"scores":sim.scores,"enemies":sim.enemies}))
	return {"target":target,"scores":sim.scores,"readiness":sim.readiness,"sector":sim.units[0].sector,"tick":sim.tick}

func _sector_contracts() -> void:
	var arc := {"start":deg_to_rad(-15.0),"end":deg_to_rad(15.0),"duration":12.0}
	var plain := sector_sample({})
	var narrowed := sector_sample(arc)
	check(plain.target=="outside" and narrowed.target=="inside","An active sector changes actual target selection toward its assigned arc")
	check(is_equal_approx(float(plain.scores.outside)-float(narrowed.scores.outside),60.0) and is_equal_approx(float(plain.scores.inside),float(narrowed.scores.inside)),"Only the non-immediate out-of-sector threat loses exactly sixty points")
	var melee := sector_sample(arc,true)
	check(melee.target=="outside" and float(melee.scores.outside)>float(melee.scores.inside),"A closer threat within one metre overrides the sector penalty")
	var wrapped := sector_sample({"start":deg_to_rad(170.0),"end":deg_to_rad(-170.0),"duration":12.0},false,true)
	check(wrapped.target=="inside","A sector crossing the minus-pi seam contains its actual inside target")
	var expired := sector_sample({"start":arc.start,"end":arc.end,"duration":0.1},false,false,true)
	check(expired.target=="outside" and expired.sector.is_empty(),"An expired sector stops affecting the actual post-reload shot")
	var ready := sector_sample(arc,false,false,false,true)
	check(ready.target=="outside" and ready.readiness.outside.state=="ready" and float(ready.readiness.outside.error)<=deg_to_rad(15.0) and int(ready.readiness.outside.ammo)>0,"A real ready enemy aiming at the unit overrides its outside-sector penalty")

func arc_contains(arc: Dictionary, bearing: float) -> bool:
	return fposmod(bearing-float(arc.start),TAU)<=fposmod(float(arc.end)-float(arc.start),TAU)+0.000001

func _expanded_sector_contracts() -> void:
	var sim := simulation(fixture())
	var answer: Dictionary = sim.plan_room_entry("d1","OPEN_DOOR",ORDER,{"go_long":true})
	check(bool(answer.get("ok",false)),"Expanded-sector and go-long fixture plans through the public macro")
	if not bool(answer.get("ok",false)): return
	var arcs: Dictionary = {}
	var first_long := -1
	var premature := false
	for _frame: int in range(BENCH_TICKS):
		sim.step(STEP)
		for unit: Dictionary in sim.units:
			for command: Dictionary in stage_commands(unit,"domination"):
				if command.type=="FACE" and bool(command.get("_started",false)) and not arcs.has(unit.id): arcs[unit.id] = unit.sector.duplicate(true)
			for command: Dictionary in stage_commands(unit,"go_long"):
				if command.type=="MOVE" and bool(command.get("_started",false)):
					if first_long<0: first_long = sim.tick
					for other: Dictionary in sim.units:
						var goals: Array = other.commands.filter(func(node: Dictionary)->bool: return node.type=="MOVE" and node.args.get("drill",{}).get("stage","") in ["entry","domination"])
						premature = premature or goals.is_empty() or goals.back().state!="SUCCEEDED"
	check(arcs.size()==4,"All four actual domination FACE commands install their expanded sectors")
	if arcs.size()==4:
		for index: int in range(4):
			var original: Dictionary = answer.slots[index].sector_entry
			var expanded: Dictionary = arcs[ORDER[index]]
			check(fposmod(float(expanded.end)-float(expanded.start),TAU)>fposmod(float(original.end)-float(original.start),TAU),"Actual rank %d sector widens after goal arrival"%(index+1))
		check(arc_contains(arcs.alpha,-PI*0.5) and arc_contains(arcs.bravo,-PI*0.5) and arc_contains(arcs.charlie,PI*0.5) and arc_contains(arcs.delta,PI*0.5),"Actual near and deep domination sectors overlap across their assigned room halves")
	check(first_long>0 and not premature,"Go-long movement begins only after every entry participant actually completes its goal")
	for goal: Dictionary in answer.get("go_long",[]):
		check(position(sim._find(sim.units,str(goal.unit_id))).distance_to(point(goal.target))<=0.1,"Go-long rank reaches its actual second domination goal")

func _requested_order_contract() -> void:
	# Unit processing remains canonical ID order; tactical rank is separately
	# authored by the selected order and must govern the real portal crossing.
	var requested: Array = ["delta","bravo","alpha","charlie"]
	var data := fixture()
	var starts: Array = [[9.3,10.95],[6.7,10.95],[9.3,11.65],[6.7,11.65]]
	for rank: int in range(4):
		for unit: Dictionary in data.units:
			if unit.id==requested[rank]:
				unit.x = starts[rank][0]
				unit.z = starts[rank][1]
				unit.facing = (Vector2(8.0,10.5)-position(unit)).angle()
	var sim := simulation(data)
	var answer: Dictionary = sim.plan_room_entry("d1","OPEN_DOOR",requested,{})
	check(bool(answer.get("ok",false)),"A tactical order differing from canonical unit IDs plans successfully")
	if not bool(answer.get("ok",false)): return
	var crossings: Array = []
	var crossed: Dictionary = {}
	for _frame: int in range(BENCH_TICKS):
		var previous: Dictionary = {}
		for unit: Dictionary in sim.units: previous[unit.id] = position(unit)
		sim.step(STEP)
		for unit: Dictionary in sim.units:
			if not crossed.has(unit.id) and previous[unit.id].y>10.5 and position(unit).y<=10.5: crossed[unit.id] = true; crossings.append(unit.id)
	check(crossings==requested,"Actual portal crossings honor selected tactical order rather than unit-ID update order")
	for slot: Dictionary in answer.slots: check(position(sim._find(sim.units,str(slot.unit_id))).distance_to(point(slot.domination))<=0.1,"Reordered participant reaches its actual assigned goal")

func _approach_case(data: Dictionary, label: String, door_id: String) -> void:
	var sim := simulation(data)
	var answer: Dictionary = sim.plan_room_entry(door_id,"OPEN_DOOR",ORDER,{})
	check(bool(answer.get("ok",false)),label+" plans through the actual public macro")
	if not bool(answer.get("ok",false)): return
	var continuous := true
	var separated := true
	var leaf_clear := true
	var minimum_spacing := INF
	var complete := false
	for _frame: int in range(900):
		var previous: Dictionary = {}
		for unit: Dictionary in sim.units: previous[unit.id] = position(unit)
		sim.step(STEP)
		for index: int in range(sim.units.size()):
			var unit: Dictionary = sim.units[index]
			continuous = continuous and position(unit).distance_to(previous[unit.id])<=0.115
			for door: Dictionary in sim.doors: leaf_clear = leaf_clear and not Door.overlaps_actor(door,-1.0,position(unit),Navigation.RADIUS)
			for other: int in range(index): minimum_spacing = minf(minimum_spacing,position(unit).distance_to(position(sim.units[other])))
		separated = separated and minimum_spacing>=Navigation.RADIUS*2.0-0.0001
		complete = sim.units.all(func(unit: Dictionary)->bool: return not unit.commands.is_empty() and unit.commands.all(func(command: Dictionary)->bool: return command.state=="SUCCEEDED"))
		if complete: break
	check(complete and sim.command_failures==0,label+" completes every real expanded primitive within 900 fixed steps")
	check(continuous and separated and leaf_clear,label+" preserves movement continuity, teammate spacing and every physical leaf")
	for slot: Dictionary in answer.slots: check(position(sim._find(sim.units,str(slot.unit_id))).distance_to(point(slot.domination))<=0.1,label+" participant reaches its actual domination goal")
	report[label] = {"ticks":sim.tick,"minimum_spacing":minimum_spacing,"complete":complete,"continuous":continuous,"separated":separated,"leaf_clear":leaf_clear}

func _approach_contracts() -> void:
	var crossed := fixture()
	for unit: Dictionary in crossed.units:
		unit.x = 16.0-float(unit.x)
		unit.facing = (Vector2(8.0,10.5)-position(unit)).angle()
	_approach_case(crossed,"crossed_stack","d1")
	# Preserve M01's authored floor, door leaves, bounds, seed and loadouts.
	# NPC removal isolates the narrow outside-row navigation contract; contact
	# and full-mission gameplay remain covered by the unmodified P1 suites.
	var house: Dictionary = Catalog.load("M01")
	house.enemies = []
	house.civilians = []
	house.win = [{"type":"reach_zone","zone":[0.1,0.1,0.1,0.1]}]
	house.fail = []
	_approach_case(house,"m01_bounded_stack","d1")

func _all_left_contracts() -> void:
	# Keep the original replay fixture, including its hidden NPCs, JSON number
	# normalization and non-ID tactical order. An earlier same-cohort detour
	# kept CHARLIE circling beside BRAVO after its direct route became clear.
	var sim := simulation(AllLeftFixture.make(0))
	var requested: Array = ["delta","bravo","alpha","charlie"]
	var answer: Dictionary = sim.plan_room_entry("door","OPEN_DOOR",requested,{"delay_ticks":3,"go_long":true})
	check(bool(answer.get("ok",false)),"All-left replay reproducer plans through its original public macro")
	if not bool(answer.get("ok",false)): return
	var count := 0
	var counts: Dictionary = {}
	for unit: Dictionary in sim.units: count += unit.commands.size(); counts[unit.id] = unit.commands.size()
	# The intermediate producer emitted 49 nodes. Final owned-route geometry
	# emits 48 (13/12/10/13); keep the original normalized mission unchanged.
	check(count==48 and counts=={"alpha":13,"bravo":12,"charlie":10,"delta":13},"All-left reproducer retains its final 48 expanded primitives with the exact per-unit counts (actual=%d)"%count)
	var metadata_valid := true
	var ids: Dictionary = {}
	for rank: int in range(4):
		for command: Dictionary in sim._find(sim.units,str(requested[rank])).commands:
			var metadata: Dictionary = command.args.get("drill",{})
			var keys: Array = metadata.keys()
			keys.sort()
			metadata_valid = metadata_valid and command.type in Simulation.COMMANDS and command.state=="PENDING" and not ids.has(command.id)
			metadata_valid = metadata_valid and keys==["door_id","order","room_id","stage","sync_id"] and metadata.get("order",0)==rank+1 and metadata.get("sync_id","")==answer.sync_id and metadata.get("door_id","")=="door" and metadata.get("room_id","")=="room"
			ids[command.id] = true
	check(metadata_valid,"All 48 primitives preserve their unique IDs, original tactical ranks and canonical optional metadata")
	var continuous := true
	var leaf_clear := true
	var minimum_spacing := INF
	var domination_arrivals: Dictionary = {}
	var sectors: Dictionary = {}
	var sector_transitions := 0
	var completion_tick := -1
	var crossed: Dictionary = {}
	var crossing_order: Array = []
	# P2 adds owned stack routes: this unchanged fixture expands to 48 nodes,
	# including ALPHA's 18.533m approach. Actual preparation finishes at tick
	# 340, opening at 399, primary goals at 579 and final FACE at 631. The old
	# 450-tick replay window covered the previous 29-node route. Use 900 fixed
	# steps for this full-route regression; the standard benchmark stays 450.
	for _frame: int in range(900):
		var previous: Dictionary = {}
		for unit: Dictionary in sim.units: previous[unit.id] = position(unit)
		sim.step(STEP)
		for index: int in range(sim.units.size()):
			var unit: Dictionary = sim.units[index]
			continuous = continuous and position(unit).distance_to(previous[unit.id])<=0.115
			if not crossed.has(unit.id) and previous[unit.id].y>8.5 and position(unit).y<=8.5: crossed[unit.id] = true; crossing_order.append(unit.id)
			for other: int in range(index): minimum_spacing = minf(minimum_spacing,position(unit).distance_to(position(sim.units[other])))
			for door: Dictionary in sim.doors: leaf_clear = leaf_clear and not Door.overlaps_actor(door,-1.0,position(unit),Navigation.RADIUS)
			var signature := JSON.stringify(unit.sector)
			if signature!=str(sectors.get(unit.id,"{}")): sector_transitions += 1
			sectors[unit.id] = signature
		for slot: Dictionary in answer.slots:
			if not domination_arrivals.has(slot.unit_id) and position(sim._find(sim.units,str(slot.unit_id))).distance_to(point(slot.domination))<=0.1: domination_arrivals[slot.unit_id] = sim.tick
		if completion_tick<0 and sim.units.all(func(unit: Dictionary)->bool: return unit.commands.all(func(command: Dictionary)->bool: return command.state=="SUCCEEDED")): completion_tick = sim.tick
	var complete: bool = sim.units.all(func(unit: Dictionary)->bool: return unit.commands.all(func(command: Dictionary)->bool: return command.state=="SUCCEEDED"))
	check(complete and sim.command_failures==0,"All-left reproducer completes every one of its 48 real primitives within 900 fixed steps")
	check(continuous and minimum_spacing>=Navigation.RADIUS*2.0-0.0001 and leaf_clear,"All-left recovery preserves each fixed movement step, physical body spacing and every door leaf")
	check(crossing_order==requested,"All-left actual door-plane crossing preserves its original tactical order")
	check(domination_arrivals.size()==4,"All-left participants actually visit all four original domination goals before go-long")
	for slot: Dictionary in answer.slots:
		var final_target: Array = slot.domination
		for goal: Dictionary in answer.get("go_long",[]):
			if goal.unit_id==slot.unit_id: final_target = goal.target
		check(position(sim._find(sim.units,str(slot.unit_id))).distance_to(point(final_target))<=0.1,"All-left participant finishes at its actual final goal")
	check(sim.events.any(func(event: Dictionary)->bool: return event.type=="SIGNAL" and event.get("sync_id","")==str(answer.sync_id)+":entry"),"All-left entry keeps its scoped post-door signal event")
	check(sector_transitions>1,"All-left actual entry and domination retain their discrete sector transitions")
	report["all_left_stale_detour"] = {"ticks":sim.tick,"completion_tick":completion_tick,"commands":count,"complete":complete,"continuous":continuous,"leaf_clear":leaf_clear,"minimum_spacing":minimum_spacing,"domination_arrivals":domination_arrivals,"crossing_order":crossing_order,"sector_transitions":sector_transitions}

func _write_report() -> void:
	var directory := ProjectSettings.globalize_path("res://../tests/artifacts")
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("room-drill.json"),FileAccess.WRITE)
	check(file!=null,"Room-drill deterministic evidence can be saved")
	report["checks"] = checks
	report["failures"] = failures.duplicate()
	if file!=null: file.store_string(JSON.stringify(report,"\t")+"\n")
