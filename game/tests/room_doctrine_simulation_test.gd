extends SceneTree
## P6 integration receipts come from public plans and real fixed STEP actions.
## Hidden actor states are authored fixture variants, never injected at runtime.
const Simulation = preload("res://scripts/simulation.gd")
const STEP := 1.0 / 30.0
const SEEDS := 30
const PRIVACY_TICKS := 60
const ROWS: Array[String] = ["stealth","doorway_dwell","time_to_dominate","threat_order_violations","identification","control","marked","rear_hits"]
var checks := 0
var failures: Array[String] = []

class SoundProbe:
	extends "res://scripts/simulation.gd"
	var team_sounds: Array = []
	func _emit_sound(position: Vector2, radius: float, label: String, source_kind: String, context: Dictionary = {}) -> void:
		# Passive observer: preserve the normal sound call exactly once. This
		# captures order of receipt ownership, without changing NPC awareness.
		if label=="팀 신호 감지":
			team_sounds.append({"tick":tick,"epochs":_room_stack_epochs.keys(),
				"receipts":doctrine._room_doctrine._ready.keys(),
				"stealth":doctrine._room_doctrine._rows.get("entry",{}).get("stealth",{}).duplicate(true)})
		super._emit_sound(position,radius,label,source_kind,context)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _fixture(seed_value: int = 0, hidden_alive: bool = true) -> Dictionary:
	return {"schema_version":6,"id":"ROOM_DOCTRINE_ACTUAL","seed":seed_value,"roe":"precision","bounds":[16,16],
		"rooms":[{"id":"known","x":4.0,"z":8.0,"w":8.0,"d":8.0,"indoor":true},
			{"id":"hidden","x":12.0,"z":8.0,"w":8.0,"d":8.0,"indoor":true}],
		"walls":[{"id":"opaque","x":8.0,"z":8.0,"w":0.2,"d":16.0,"height":2.6,"material":"concrete"}],
		"doors":[],"props":[],
		"units":[{"id":"alpha","x":4.0,"z":8.0,"facing":0.0,"ammo":0,"reserve_ammo":0}],
		"enemies":[{"id":"hidden_enemy","x":12.0,"z":8.0,"facing":0.0,"ammo":0,"reserve_ammo":0,"hp":72.0 if hidden_alive else 0.0}],
		"civilians":[{"id":"hidden_civilian","x":12.0,"z":9.0,"hp":100.0 if hidden_alive else 0.0}],
		"win":[{"type":"reach_zone","zone":[15.0,1.0,0.1,0.1]}],"fail":[]}

func _sim(data: Dictionary) -> RefCounted:
	var sim: RefCounted = Simulation.new()
	sim.load_mission(data)
	return sim

func _issue(sim: RefCounted, id: String, type: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = sim.issue(id,type,args,true)
	check(bool(result.get("ok",false)),"Public %s %s accepted: %s" % [id,type,str(result)])
	return result

func _advance(sim: RefCounted, count: int) -> void:
	for _tick: int in range(count): sim.step(STEP)

func _rng(sim: RefCounted) -> Array:
	return [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]

func _metrics(state: Dictionary) -> Dictionary:
	return state.get("room_doctrine",{})

func _row(sim: RefCounted, room: String, metric: String) -> Dictionary:
	return _metrics(sim.snapshot(false)).get(room,{}).get(metric,{})

func _shape(rows: Dictionary, label: String) -> void:
	check(rows.size()==ROWS.size() and ROWS.all(func(id: String)->bool:return rows.has(id)),label+" contains exactly the eight doctrine items")
	for metric: String in rows:
		var row: Dictionary = rows[metric]
		var allowed: Array = ["value","tick","time","unit_id","door_id"]
		if metric=="identification": allowed.append_array(["civilian_damage","unlawful_shots"])
		if metric=="control": allowed.append_array(["arrested","surrendered","secured","civilians"])
		check(row.has("value") and row.has("tick") and row.has("time") and row.keys().all(func(key: String)->bool:return allowed.has(key)),label+" "+metric+" has only the exact common occurrence and metric-specific receipt fields")
		check((row.tick==null and row.time==null) or (row.tick is int and row.time is float and int(row.tick)>=0 and is_equal_approx(float(row.time),int(row.tick)*STEP)),label+" "+metric+" timestamp uses the actual fixed simulation clock")

func _privacy_case(seed_value: int, hidden_alive: bool) -> Dictionary:
	var sim := _sim(_fixture(seed_value,hidden_alive))
	_issue(sim,"alpha","WAIT",{"duration":2.0})
	_advance(sim,PRIVACY_TICKS)
	var paired: Dictionary = sim.snapshot_pair()
	var observed: Dictionary = sim.snapshot(false)
	var record: Dictionary = sim.snapshot(true)
	check(sim.tick==PRIVACY_TICKS and sim.result.is_empty(),"seed %d privacy case runs all fixed STEP without early result" % seed_value)
	check(sim.room_states.known.state=="CLEAR" and paired.observed.room_states.known.state=="CLEAR","seed %d own stationary search supplies actual observed room clearance" % seed_value)
	var metrics := _metrics(observed)
	check(metrics.has("known") and not metrics.has("hidden"),"seed %d metrics list only the actually observed room" % seed_value)
	check(_metrics(paired.observed)==metrics and _metrics(paired.record)==_metrics(record),"seed %d paired snapshots preserve both metric projections without alias mutation" % seed_value)
	var encoded := JSON.stringify(metrics)
	check(not encoded.contains("hidden_enemy") and not encoded.contains("hidden_civilian"),"seed %d public room metrics contain no hidden actor identities" % seed_value)
	return {"public":JSON.stringify({"metrics":metrics,"rooms":observed.room_states,"events":observed.events}),
		"authority":JSON.stringify(record),"state":JSON.stringify({"record":record,"rng":_rng(sim)}),"rows":metrics.get("known",{})}

func _privacy_repeat(all_seeds: bool) -> void:
	for seed_value: int in range(SEEDS if all_seeds else 1):
		var alive := _privacy_case(seed_value,true)
		var dead := _privacy_case(seed_value,false)
		check(alive.public==dead.public,"seed %d hidden current casualties cannot change observed doctrine rows, clocks or event sequence" % seed_value)
		check(alive.authority!=dead.authority,"seed %d recording retains the actual hidden-world difference" % seed_value)
		if seed_value==0: _shape(alive.rows,"Observed actual known room")
		if all_seeds:
			check(alive.state==_privacy_case(seed_value,true).state and dead.state==_privacy_case(seed_value,false).state,"seed %d identical authored world and plan repeat full state and four RNG streams exactly" % seed_value)

func _control_and_marked() -> void:
	var data := _fixture()
	data.enemies = [{"id":"surrendered","x":4.8,"z":8.0,"surrendered":true,"ammo":0,"reserve_ammo":0}]
	data.civilians = [{"id":"civilian","x":4.8,"z":8.7}]
	data.doors = [{"id":"exit","x":4.0,"z":12.0,"axis":"x","w":1.8,"d":0.2,"state":"OPEN","hinge_side":-1.0,"swing_sign":1.0}]
	var sim := _sim(data)
	_advance(sim,1)
	var before := _row(sim,"known","control")
	check(int(before.get("surrendered",0))==1 and int(before.get("civilians",0))==1 and int(before.get("arrested",0))==0 and int(before.get("secured",0))==0,"Fresh actual sightings establish both observed control denominators without granting actions")
	_issue(sim,"alpha","ARREST",{"enemy_id":"surrendered"})
	_issue(sim,"alpha","SECURE_CIVILIAN",{"civilian_id":"civilian"})
	var action_tick := -1
	for _tick: int in range(240):
		sim.step(STEP)
		if bool(sim.enemies[0].arrested) and bool(sim.civilians[0].secured):
			action_tick = sim.tick
			break
	check(action_tick>1 and sim.arrests==1 and int(sim.snapshot(true).objectives.rescued)==1,"Actual public ARREST and SECURE actions both complete")
	var control := _row(sim,"known","control")
	check(int(control.get("arrested",0))==1 and int(control.get("surrendered",0))==1 and int(control.get("secured",0))==1 and int(control.get("civilians",0))==1 and is_equal_approx(float(control.get("value",-1.0)),1.0),"Room control score comes from actual own actions and fresh observed people")
	check(int(control.get("tick",-1))==action_tick,"Control completion link retains the actual last action tick")
	var identification := _row(sim,"known","identification")
	check(identification.get("value",null)==0 and is_zero_approx(float(identification.get("civilian_damage",-1.0))) and int(identification.get("unlawful_shots",-1))==0,"Fresh observed healthy civilian and actual lawful control establish identification evidence")
	# The last control action is busy. CONTACT first transitions to DOMINATED
	# on its next eligible tick; only then do 45 further search STEP count.
	if OS.get_cmdline_user_args().has("--probe-only"): print("ROOM_DOCTRINE_CONTROL " + JSON.stringify({"tick":sim.tick,"room":sim.room_states.known,"unit":[sim.units[0].x,sim.units[0].z]}))
	_advance(sim,1)
	check(sim.room_states.known.state=="DOMINATED","The first eligible tick after actual control establishes dominance without counting search")
	_advance(sim,45)
	check(sim.room_states.known.state=="CLEAR","Controlled people permit a real full stationary search")
	_issue(sim,"alpha","MOVE",{"target":[4.0,13.5]})
	var marked_tick := -1
	for _tick: int in range(180):
		sim.step(STEP)
		if sim.room_states.known.state=="MARKED":
			marked_tick = sim.tick
			break
	var marked := _row(sim,"known","marked")
	check(marked_tick>action_tick and marked.get("value",null)==1 and int(marked.get("tick",-1))==marked_tick and str(marked.get("door_id",""))=="exit","A real crossing of the opened authored door supplies the marked score and exact replay link")
	check(float(_row(sim,"known","doorway_dwell").get("value",0.0))>0.0,"Real departure through a physical door accumulates measured funnel dwell")

func _floor_attribution() -> void:
	var data := _fixture()
	data.rooms = [{"id":"lower","x":4.0,"z":8.0,"w":8.0,"d":8.0,"base_height":0.0},
		{"id":"upper","x":4.0,"z":8.0,"w":8.0,"d":8.0,"base_height":3.0}]
	data.enemies = []
	data.civilians = []
	var sim := _sim(data)
	_issue(sim,"alpha","WAIT",{"duration":2.0})
	_advance(sim,PRIVACY_TICKS)
	var metrics := _metrics(sim.snapshot(false))
	check(is_equal_approx(float(sim.units[0].base_height),3.0) and sim.room_states.upper.state=="CLEAR" and sim.room_states.lower.state=="UNKNOWN","Actual elevated walkable surface supplies only its physical room's search authority")
	check(metrics.has("upper") and not metrics.has("lower"),"Same horizontal bounds on another floor cannot receive observed room doctrine receipts")

func _actual_rear_hit() -> void:
	var data := _fixture()
	data.rooms = [{"id":"known","x":8.0,"z":8.0,"w":12.0,"d":12.0}]
	data.walls = []
	data.units[0].x = 8.0
	data.units[0].facing = -PI*0.5
	data.units[0].armor = "none"
	data.units[0].helmet = "none"
	data.enemies = [{"id":"rear_shooter","x":8.0,"z":11.0,"facing":-PI*0.5,"weapon":"standard","can_surrender":false}]
	data.civilians = []
	var sim := _sim(data)
	_issue(sim,"alpha","WAIT",{"duration":3.0})
	var before := float(sim.units[0].hp)
	var hit_tick := -1
	for _tick: int in range(180):
		sim.step(STEP)
		if float(sim.units[0].hp)<before:
			hit_tick = sim.tick
			break
	var rear := _row(sim,"known","rear_hits")
	check(hit_tick>0 and sim.hits_taken>0 and float(sim.units[0].hp)<before and sim.doctrine.rear_hits>0,"Normal hostile aim and fire cause a real own rear HP loss without injected shots, injury or aim")
	check(int(rear.get("value",0))==sim.doctrine.rear_hits and int(rear.get("tick",-1))==hit_tick,"Own rear-hit evidence is attributed to the physical known room at the actual hit tick")
	check(not JSON.stringify(_metrics(sim.snapshot(false))).contains("rear_shooter"),"Own-hit scoring does not disclose an unobserved shooter's identity")

func _stack_receipt(automatic: bool) -> void:
	var data := {"schema_version":6,"id":"ROOM_DOCTRINE_STACK","seed":0,"roe":"precision","bounds":[16,16],
		"rooms":[{"id":"entry","x":8.0,"z":8.0,"w":5.0,"d":5.0,"indoor":true}],"walls":[],"props":[],
		"doors":[{"id":"entry_door","x":8.0,"z":10.5,"axis":"x","w":1.8,"d":0.2,"state":"OPEN","hinge_side":-1.0,"swing_sign":1.0}],
		"units":[{"id":"alpha","x":9.3,"z":10.95,"facing":Vector2(-1.3,-0.45).angle(),"ammo":0,"reserve_ammo":0},
			{"id":"bravo","x":6.7,"z":10.95,"facing":Vector2(1.3,-0.45).angle(),"ammo":0,"reserve_ammo":0}],
		"enemies":[{"id":"observed_guard","x":8.0,"z":7.5,"facing":-PI*0.5,"ammo":0,"reserve_ammo":0,"can_surrender":false}],"civilians":[],
		"win":[{"type":"reach_zone","zone":[15.0,1.0,0.1,0.1]}],"fail":[]}
	var sim := SoundProbe.new()
	sim.load_mission(data)
	var planned: Dictionary = sim.plan_room_entry("entry_door","OPEN_DOOR",["alpha","bravo"],{"signal":"AUTO" if automatic else "A","delay_ticks":3})
	check(bool(planned.get("ok",false)),"Actual %s drill plans existing door, stack and grouped primitives: %s" % ["automatic" if automatic else "manual",str(planned)])
	var ready_tick := -1
	var first_stealth: Dictionary = {}
	var released := automatic
	for _tick: int in range(360):
		sim.step(STEP)
		if ready_tick<0 and not sim._room_stack_epochs.is_empty():
			ready_tick = sim.tick
			first_stealth = sim.doctrine._room_doctrine._rows.entry.stealth.duplicate(true)
			if not automatic:
				var reply: Dictionary = sim.release_signal("A","bravo")
				released = bool(reply.get("ok",false))
		if not sim.team_sounds.is_empty(): break
	check(ready_tick>0 and released and not sim.team_sounds.is_empty(),"Actual %s ready cohort reaches one real spoken release" % ("automatic" if automatic else "manual"))
	if sim.team_sounds.is_empty(): return
	var sound: Dictionary = sim.team_sounds[0]
	var ready_commands: Array = []
	for unit: Dictionary in sim.units:
		for command: Dictionary in unit.commands:
			if command.args.get("drill",{}).get("stage","")=="ready": ready_commands.append(str(command.id))
	var base := str(planned.get("sync_id",""))
	check(ready_commands.size()==2 and sound.epochs==[base+":"+JSON.stringify(ready_commands)] and sound.receipts==[base+JSON.stringify(ready_commands)],"Whole actual cohort's ready command IDs already own both stack receipts when verbal sound begins")
	check(first_stealth.get("value",null)==0 and int(first_stealth.get("tick",-1))==ready_tick and sound.stealth==first_stealth,"First actual ready epoch records the fresh observed unaware guard before sound or delay")
	# Manual signals sound when pressed and release after their delay. Auto
	# signals sound when the ready delay expires; neither recomputes stealth.
	check(int(sound.tick)>=ready_tick+(3 if automatic else 0),"Signal timing preserves the actual manual-press or automatic-delay contract")
	_advance(sim,30)
	check(sim.enemies[0].awareness_state!="UNAWARE" and _row(sim,"entry","stealth")==first_stealth,"Actual verbal hearing may alert the guard while the initial stack evidence stays unchanged")

func _actual_entry_metrics() -> void:
	var data := {"schema_version":6,"id":"ROOM_DOCTRINE_ENTRY","seed":0,"roe":"precision","bounds":[16,16],
		"rooms":[{"id":"entry","x":8.0,"z":8.0,"w":5.0,"d":5.0,"indoor":true}],"walls":[],"props":[],
		"doors":[{"id":"entry_door","x":8.0,"z":10.5,"axis":"x","w":1.8,"d":0.2,"state":"CLOSED","hinge_side":-1.0,"swing_sign":1.0}],
		"units":[{"id":"alpha","x":9.3,"z":10.95,"facing":Vector2(-1.3,-0.45).angle()},
			{"id":"bravo","x":6.7,"z":10.95,"facing":Vector2(1.3,-0.45).angle()}],"enemies":[],"civilians":[],
		"win":[{"type":"reach_zone","zone":[15.0,1.0,0.1,0.1]}],"fail":[]}
	var sim := _sim(data)
	var planned: Dictionary = sim.plan_room_entry("entry_door","OPEN_DOOR",["alpha","bravo"],{})
	check(bool(planned.get("ok",false)),"A closed observed door expands an actual two-person entry plan")
	var arrival_tick := -1
	for _tick: int in range(360):
		sim.step(STEP)
		var entry: Dictionary = sim.doctrine.time_to_dominate.get("entry_door",{})
		if not entry.is_empty() and float(entry.seconds)>=0.0:
			arrival_tick = sim.tick
			break
	var entry: Dictionary = sim.doctrine.time_to_dominate.get("entry_door",{})
	check(arrival_tick>0 and entry.get("participants",[]).size()==2 and entry.get("arrived",[]).size()==2,"Both real participants reach their authored final domination goals")
	var dominated := _row(sim,"entry","time_to_dominate")
	check(dominated.get("value",null)!=null and is_equal_approx(float(dominated.get("value",-1.0)),float(entry.get("seconds",-2.0))) and int(dominated.get("tick",-1))==arrival_tick and str(dominated.get("door_id",""))=="entry_door","Room domination score and replay link retain actual P0 goal-arrival duration and tick")
	check(float(_row(sim,"entry","doorway_dwell").get("value",0.0))>0.0,"Actual entry MOVE crossings supply room funnel dwell")
	check(_row(sim,"entry","stealth").get("value",null)==null,"No observed enemy at the ready epoch remains unknown rather than proving a quiet approach")
	_advance(sim,60)
	check(sim.room_states.entry.state=="CLEAR" and sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.state=="SUCCEEDED")),"The actual door and entry primitive queues finish before a full physical room search")

func _late_damage_discovery() -> void:
	var data := _fixture()
	data.roe = "high_intensity"
	data.rooms = [{"id":"known","x":4.5,"z":8.0,"w":9.0,"d":16.0}]
	data.walls = []
	data.units[0].x = 3.0
	data.units[0].equipment = {"frag":1}
	data.enemies = [{"id":"guard","x":6.0,"z":6.0,"facing":PI,"ammo":0,"reserve_ammo":0,"can_surrender":false}]
	data.civilians = [{"id":"civilian","x":7.0,"z":8.0}]
	var sim := _sim(data)
	var civilian: Dictionary = sim.civilians[0]
	check(bool(civilian.visible) and is_equal_approx(float(civilian.hp),100.0),"Initial actual LOS supplies a healthy civilian baseline")
	_issue(sim,"alpha","FACE",{"target":[3.0,1.0],"persistent":true})
	for _tick: int in range(90):
		sim.step(STEP)
		if not sim._currently_observed(civilian) and sim.units[0].commands.back().state=="SUCCEEDED": break
	check(not sim._currently_observed(civilian),"An actual persistent turn removes the civilian from observation before the throw")
	_issue(sim,"alpha","THROW_FRAG",{"target":[8.0,8.0]})
	for _tick: int in range(120):
		sim.step(STEP)
		if sim.events.any(func(event: Dictionary)->bool:return event.type=="FRAG"): break
	var hidden_damage := 100.0-float(civilian.hp)
	check(hidden_damage>0.0 and not sim._currently_observed(civilian),"Actual fragment geometry causes civilian damage while the operator looks away")
	check(is_zero_approx(float(_row(sim,"known","identification").get("civilian_damage",-1.0))),"Unobserved physical injury cannot update the public identification ledger")
	_issue(sim,"alpha","FACE",{"target":[7.0,8.0],"persistent":true})
	var discovery_tick := -1
	for _tick: int in range(90):
		sim.step(STEP)
		if float(_row(sim,"known","identification").get("civilian_damage",0.0))>0.0:
			discovery_tick = sim.tick
			break
	var identified := _row(sim,"known","identification")
	check(discovery_tick>0 and sim._currently_observed(civilian) and is_equal_approx(float(identified.get("civilian_damage",-1.0)),hidden_damage) and int(identified.get("tick",-1))==discovery_tick,"A real return of fresh LOS records only the prior-known HP loss at its discovery tick")
	var receipt := identified.duplicate(true)
	_advance(sim,30)
	check(_row(sim,"known","identification")==receipt,"Later repeated fresh observations cannot count the discovered injury twice or move its replay link")

func run() -> void:
	_privacy_repeat(not OS.get_cmdline_user_args().has("--probe-only"))
	_control_and_marked()
	_floor_attribution()
	_actual_rear_hit()
	_stack_receipt(false)
	_stack_receipt(true)
	_actual_entry_metrics()
	_late_damage_discovery()
	print("BREACH_ROOM_DOCTRINE_SIMULATION_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
