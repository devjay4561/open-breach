extends SceneTree
## P3 room authority consumes fixed simulation facts, never a rendered mask.
const Simulation = preload("res://scripts/simulation.gd")
const RoomControl = preload("res://scripts/room_control.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Navigation = preload("res://scripts/navigation.gd")
const STEP := 1.0 / 30.0
const ORDER: Array[String] = ["alpha", "bravo", "charlie", "delta"]
const SEEDS := 30
var checks := 0
var failures: Array[String] = []
var report: Dictionary = {"step":STEP,"seeds":[0,29]}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or "--contracts-only" in args or "--pure-only" in args:
		_projection_contracts()
		_search_contracts()
		_control_contracts()
		_entry_contracts()
		_observation_contracts()
		_public_clearer_receipt_contracts()
		_delayed_clear_contracts()
	if args.is_empty() or "--contracts-only" in args or "--integration-only" in args:
		_actual_search_contracts()
		_actual_control_contracts()
		_actual_shot_contracts()
		_actual_hit_contracts()
		_actual_stun_contracts()
		_reload_contracts()
		_reload_movement_contracts()
		_short_room_contracts()
		_before_entry_casualty_contract()
	if "--rear-probe-only" in args:
		print("ROOM_CONTROL_REAR_PROBE " + JSON.stringify({"rush":rear_case(0,false),"guard":rear_case(0,true)}))
	if "--man-down-probe-only" in args:
		print("ROOM_CONTROL_MAN_DOWN_PROBE " + JSON.stringify(man_down_case(0)))
	if args.is_empty() or "--benchmarks-only" in args:
		_rear_benchmark()
		_man_down_benchmark()
		_write_report()
	print("BREACH_ROOM_CONTROL_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

func position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x),float(actor.z))

func sim_for(data: Dictionary) -> RefCounted:
	var sim: RefCounted = Simulation.new()
	sim.load_mission(data)
	return sim

func issue(sim: RefCounted, id: String, type: String, args: Dictionary = {}) -> Dictionary:
	var answer: Dictionary = sim.issue(id,type,args,true)
	check(bool(answer.get("ok",false)), "%s actual %s accepted: %s" % [id,type,str(answer)])
	return answer

func advance(sim: RefCounted, ticks: int) -> void:
	for _tick: int in range(ticks): sim.step(STEP)

func active(unit: Dictionary) -> Dictionary:
	for command: Dictionary in unit.commands:
		if command.state not in ["SUCCEEDED","CANCELLED"]: return command
	return {}

func helper_fixture() -> Dictionary:
	return {"rooms":[{"id":"room","x":5.0,"z":5.0,"w":6.0,"d":6.0,"indoor":true}],
		"doors":[{"id":"door","x":5.0,"z":8.0,"axis":"x","w":1.8,"d":0.2,"base_height":0.0}]}

func helper() -> RefCounted:
	var control: RefCounted = RoomControl.new()
	control.reset(helper_fixture())
	return control

func unit_fact(id: String = "alpha", eligible: bool = true) -> Dictionary:
	return {"id":id,"position":[5.0,5.0],"floor_height":0.0,"alive":true,"can_act":true,"search_eligible":eligible}

func context(tick_value: int, own: Array = []) -> Dictionary:
	return {"tick":tick_value,"time":tick_value*STEP,"dt":STEP,"units":[unit_fact()] if own.is_empty() else own,"enemies":[],"civilians":[],
		"observation":{"room":{"fraction":1.0,"center":true,"current":true}},"contacts":[],"exits":[]}

func state(control: RefCounted, reveal: bool = true) -> String:
	return str(control.snapshot(reveal).get("room",{}).get("state","UNKNOWN"))

func search_until(control: RefCounted, first_tick: int, count: int, facts: Dictionary = {}) -> void:
	for tick_value: int in range(first_tick,first_tick+count):
		var frame := context(tick_value)
		for key: String in facts: frame[key] = facts[key].duplicate(true) if facts[key] is Array or facts[key] is Dictionary else facts[key]
		control.tick(frame)

func _projection_contracts() -> void:
	var authority := {"room":{"state":"CONTACT","changed_tick":99,"changed_at":3.3,"observed":false}}
	var memory := {"room":{"state":"MARKED","changed_tick":48,"changed_at":1.6,"observed":true,"door_id":"door"}}
	var original := {"room_states":authority,"room_states_observed":memory,"result":{"room_states":authority,"room_states_observed":memory,"success":true}}
	var owned: Dictionary = original.duplicate(true)
	RoomControl.project_observed_state(owned)
	check(owned.room_states==memory and owned.result.room_states==memory,"Observed projection uses owned memory at top level and completed RESULT")
	check(not owned.has("room_states_observed") and not owned.result.has("room_states_observed"),"Observed projection erases authority-side memory containers")
	owned.room_states.room.state = "UNKNOWN"
	owned.result.room_states.room.state = "UNKNOWN"
	check(original.room_states.room.state=="CONTACT" and original.room_states_observed.room.state=="MARKED" and original.result.room_states_observed.room.state=="MARKED","Observed projection owns both nested maps without mutating the record")
	var events: Array = [{"type":"SHOT","seq":1},{"type":"CALL_CLEAR","seq":2,"observed":false},{"type":"CALL_ROOM_CLEAR","seq":3,"observed":true},{"type":"CALL_MAN_DOWN","seq":4}]
	var filtered := RoomControl.filter_observed_call_events(events)
	check(filtered.size()==2 and filtered[0].seq==1 and filtered[1].seq==3,"Unobserved doctrine calls stay private while old events and observed calls retain sequence")
	if filtered.size()>1: filtered[1].seq = 100
	check(events[2].seq==3,"Filtered doctrine events own their dictionaries")
	var empty := {"result":{"success":true}}
	RoomControl.project_observed_state(empty)
	check(empty.room_states.is_empty() and not empty.result.has("room_states"),"Legacy records without room state project to an empty public map and preserve their result fields")

func _search_contracts() -> void:
	var control := helper()
	var transition: Dictionary = control.tick(context(1))
	check(state(control)=="DOMINATED" and state(control,false)=="DOMINATED","An actual stationary in-room observer can dominate an empty room")
	check(transition.public_transitions.size()==1,"New dominance produces one public transition")
	var first_map := JSON.stringify({"authority":control.snapshot(true),"memory":control.snapshot(false),"search":control._search})
	var backwards := context(2)
	backwards.time = 0.0
	var rejected: Dictionary = control.tick(backwards)
	check(JSON.stringify({"authority":control.snapshot(true),"memory":control.snapshot(false),"search":control._search})==first_map and rejected.public_transitions.is_empty() and rejected.private_transitions.is_empty(),"A later tick with backwards time cannot change room authority, memory or search")
	search_until(control,2,19)
	var before := JSON.stringify({"authority":control.snapshot(true),"memory":control.snapshot(false),"search":control._search})
	var duplicate: Dictionary = control.tick(context(20))
	check(JSON.stringify({"authority":control.snapshot(true),"memory":control.snapshot(false),"search":control._search})==before and duplicate.public_transitions.is_empty() and duplicate.private_transitions.is_empty(),"Duplicate tick does not advance search, clocks or transitions")
	search_until(control,21,25)
	check(state(control)=="DOMINATED","New dominance tick plus 44 eligible STEP cannot clear a room")
	var clear_transition: Dictionary = control.tick(context(46))
	check(state(control)=="CLEAR" and state(control,false)=="CLEAR" and clear_transition.public_transitions.size()==1,"Exactly 45 subsequent continuous eligible STEP clear a room")
	check(control.cleared(["room"]) and not control.cleared([]) and not control.cleared(["missing"]),"Clear objective requires actual current named rooms")
	var copy: Dictionary = control.snapshot(false)
	copy.room.state = "UNKNOWN"
	check(state(control,false)=="CLEAR","Public room snapshots own their rows")
	for interruption: String in ["busy_finished_READY","movement","new_hit","fired","temporarily_stunned","lost_operator"]:
		control = helper()
		control.tick(context(1))
		search_until(control,2,44)
		var own: Dictionary = unit_fact()
		if interruption=="lost_operator": own.id = "bravo"
		else: own.search_eligible = false
		if interruption=="temporarily_stunned": own.can_act = false
		control.tick(context(46,[own]))
		check(state(control)!="CLEAR","%s interrupts the same operator's 44 STEP search" % interruption)
		search_until(control,47,44)
		check(state(control)!="CLEAR","%s cannot carry the old partial search into 44 new STEP" % interruption)
		control.tick(context(91))
		check(state(control)=="CLEAR","%s permits a new full 45 STEP search" % interruption)
	control = helper()
	var contacted := context(1)
	contacted.contacts = [{"room_id":"room"}]
	control.tick(contacted)
	check(state(control)=="CONTACT","Fresh contact has priority over dominance in its transition tick")
	control.tick(context(2))
	check(state(control)=="DOMINATED","Contact requires a separate tick to become dominated")
	search_until(control,3,44)
	check(state(control)=="DOMINATED","CONTACT and DOMINATED do not donate transition time to search")
	control.tick(context(47))
	check(state(control)=="CLEAR","Contacted room clears after a distinct full search")

func _control_contracts() -> void:
	for alive: bool in [true,false]:
		for kind: String in ["surrendered","civilian"]:
			var control := helper()
			var actor := {"position":[5.0,5.8],"floor_height":0.0,"room_id":"room","alive":alive,"can_act":false,"surrendered":true,"arrested":false,"secured":false}
			var facts := {"enemies":[actor]} if kind=="surrendered" else {"civilians":[actor]}
			search_until(control,1,90,facts)
			check(state(control)!="CLEAR","%s alive=%s blocks CLEAR until its explicit control action" % [kind,str(alive)])
			actor["arrested" if kind=="surrendered" else "secured"] = true
			search_until(control,91,44,facts)
			check(state(control)!="CLEAR","Controlling %s alive=%s does not inherit blocked search time" % [kind,str(alive)])
			control.tick(context(135).merged(facts,true))
			check(state(control)=="CLEAR","Explicitly controlled %s alive=%s permits full new search" % [kind,str(alive)])
	var control := helper()
	var incapacitated := {"position":[5.0,5.8],"floor_height":0.0,"room_id":"room","alive":true,"can_act":false,"surrendered":false,"arrested":false}
	search_until(control,1,46,{"enemies":[incapacitated]})
	check(state(control)=="CLEAR","An ordinary temporarily unable-to-act enemy follows the specified can_act criterion")
	incapacitated.can_act = true
	var recovered := context(47)
	recovered.enemies = [incapacitated]
	control.tick(recovered)
	check(state(control)=="CONTACT" and state(control,false)=="CLEAR","A hidden recovered threat contaminates private authority without changing clear memory")

func _entry_contracts() -> void:
	var control := helper()
	var contract := {"sync_id":"entry-1","door_id":"door","room_id":"room","participants":["alpha","bravo"],"targets":{"alpha":[4.0,5.0],"bravo":[6.0,5.0]}}
	control.register_entry(contract)
	var alpha := unit_fact()
	alpha.position = [4.0,5.0]
	var bravo := unit_fact("bravo")
	bravo.position = [6.11,5.0]
	control.tick(context(1,[alpha,bravo]))
	check(state(control)=="UNKNOWN","Registered dominance waits for every actual final goal within 0.1m")
	bravo.position = [6.0,5.0]
	control.tick(context(2,[alpha,bravo]))
	check(state(control)=="DOMINATED","All actual in-room entry targets establish dominance")
	control = helper()
	control.register_entry(contract)
	bravo.alive = false
	bravo.can_act = false
	bravo.search_eligible = false
	control.tick(context(1,[alpha,bravo]))
	check(state(control)=="UNKNOWN","Dead registered participants are not silently removed from an entry contract")
	var reformed := contract.duplicate(true)
	reformed.participants = ["alpha"]
	reformed.targets.erase("bravo")
	control.register_entry(reformed)
	control.tick(context(2,[alpha,bravo]))
	check(state(control)=="DOMINATED","Explicit entry recalculation replaces the dead participant contract")
	var outside := unit_fact("delta")
	outside.position = [5.0,8.6]
	control = helper()
	control.register_entry(reformed)
	control.tick(context(1,[alpha,outside]))
	check(state(control)=="DOMINATED","SHORT_ROOM outside guards are absent from the actual entrant contract")
	control = helper()
	var edited := reformed.duplicate(true)
	edited.targets.alpha = [5.0,8.5]
	control.register_entry(edited)
	search_until(control,1,90)
	check(state(control)=="UNKNOWN","A finite edited entry goal outside its room stays pending and cannot fall back to manual dominance")
	control = helper()
	var invalid := unit_fact()
	invalid["room_id"] = "room"
	invalid.erase("position")
	control.tick(context(1,[invalid]))
	check(state(control)=="UNKNOWN","A room ID without an actual unit position cannot establish dominance")

func _observation_contracts() -> void:
	for previous: String in ["CLEAR","MARKED"]:
		var control := helper()
		search_until(control,1,46)
		var tick_value := 47
		var own := unit_fact()
		if previous=="MARKED":
			own.position = [5.0,7.95]
			control.tick(context(tick_value,[own]))
			tick_value += 1
			own.position = [5.0,8.05]
			var exit_frame := context(tick_value,[own])
			exit_frame.exits = [{"unit_id":"alpha","room_id":"room","door_id":"door"}]
			control.tick(exit_frame)
			tick_value += 1
			check(state(control)=="MARKED","The actual clearing operator leaves through its physical door before marking")
		var memory := JSON.stringify(control.snapshot(false))
		var enemy := {"position":[6.0,5.5],"room_id":"room","floor_height":0.0,"alive":true,"can_act":true,"surrendered":false,"arrested":false}
		var hidden := context(tick_value,[own])
		hidden.enemies = [enemy]
		var change: Dictionary = control.tick(hidden)
		check(state(control)=="CONTACT" and JSON.stringify(control.snapshot(false))==memory and change.public_transitions.is_empty(),"Hidden re-entry after %s keeps public state, clock and transition stream unchanged despite fresh floor samples" % previous)
		own.position = [5.0,5.0]
		for after: int in range(tick_value+1,tick_value+92):
			var result: Dictionary = control.tick(context(after,[own]))
			check(JSON.stringify(control.snapshot(false))==memory and result.public_transitions.is_empty(),"Past goals and manual search cannot refresh hidden contaminated %s memory at tick %d" % [previous,after])
		var visible := context(tick_value+92,[own])
		visible.enemies = [enemy]
		visible.contacts = [{"room_id":"room"}]
		control.tick(visible)
		check(state(control,false)=="CONTACT","Fresh actual enemy contact publishes the hidden contamination after %s" % previous)

func _public_clearer_receipt_contracts() -> void:
	var clean := helper()
	var hidden := helper()
	search_until(clean,1,46)
	search_until(hidden,1,46)
	var enemy := {"position":[6.0,5.5],"room_id":"room","floor_height":0.0,"alive":true,"can_act":true,"surrendered":false,"arrested":false}
	var private_contact := context(47)
	private_contact.enemies = [enemy]
	hidden.tick(private_contact)
	clean.tick(context(47))
	check(state(hidden)=="CONTACT" and state(clean)=="CLEAR" and clean.snapshot(false)==hidden.snapshot(false),"Hidden contamination changes authority while preserving the same public CLEAR receipt")
	var own := unit_fact()
	own.search_eligible = false
	var step_tick := 48
	while float(own.position[1])<7.95-0.00001:
		own.position[1] = minf(7.95,float(own.position[1])+0.1)
		var clean_step: Dictionary = clean.tick(context(step_tick,[own]))
		var hidden_frame := context(step_tick,[own])
		hidden_frame.enemies = [enemy]
		var hidden_step: Dictionary = hidden.tick(hidden_frame)
		check(clean.snapshot(false)==hidden.snapshot(false) and clean_step.public_transitions==hidden_step.public_transitions,"The same actual clearing operator approaches its exit without leaking private re-entry at tick %d" % step_tick)
		step_tick += 1
	own.position = [5.0,8.05]
	var exit_frame := context(step_tick,[own])
	exit_frame.exits = [{"unit_id":"alpha","room_id":"room","door_id":"door"}]
	var clean_exit: Dictionary = clean.tick(exit_frame)
	exit_frame.enemies = [enemy]
	var hidden_exit: Dictionary = hidden.tick(exit_frame)
	check(state(clean)=="MARKED" and state(hidden)=="CONTACT","Actual exit does not overwrite privately contaminated room authority")
	check(state(clean,false)=="MARKED" and clean.snapshot(false)==hidden.snapshot(false) and clean_exit.public_transitions==hidden_exit.public_transitions,"Known clearer exit produces identical public MARKED rows, door, clocks and event sequence in clean and hidden worlds")
	check(clean_exit.public_transitions.size()==1 and clean_exit.public_transitions[0].state=="MARKED" and clean.snapshot(false).room.changed_tick==step_tick,"Public marking uses only this physical owned exit tick")
	var remembered := JSON.stringify(hidden.snapshot(false))
	for next_tick: int in range(step_tick+1,step_tick+5):
		var frame := context(next_tick,[own])
		frame.enemies = [enemy]
		var change: Dictionary = hidden.tick(frame)
		check(JSON.stringify(hidden.snapshot(false))==remembered and change.public_transitions.is_empty(),"Repeated hidden facts leave public MARKED clock, count and transition sequence unchanged")
	var seen := context(step_tick+5,[own])
	seen.enemies = [enemy]
	seen.contacts = [{"room_id":"room"}]
	hidden.tick(seen)
	check(state(hidden,false)=="CONTACT","Actual fresh enemy contact consumes the old public clearer receipt")
	var stale_exit := context(step_tick+6,[own])
	stale_exit.exits = [{"unit_id":"alpha","room_id":"room","door_id":"door"}]
	hidden.tick(stale_exit)
	check(state(hidden,false)=="CONTACT","An old owned exit cannot restore MARKED after actual observed recontamination")

func _delayed_clear_contracts() -> void:
	for condition: String in ["fresh","outside","dead","hidden_contact"]:
		var control := helper()
		var own := unit_fact()
		own.position = [3.0,3.0]
		var observed := context(1,[own])
		observed.observation.room.fraction = 0.3
		control.tick(observed)
		var public_dominance := JSON.stringify(control.snapshot(false))
		for step_tick: int in range(2,47):
			var frame := context(step_tick,[own])
			frame.observation.room = {"fraction":0.3,"center":false,"current":true}
			control.tick(frame)
		check(state(control)=="CLEAR" and state(control,false)=="DOMINATED" and JSON.stringify(control.snapshot(false))==public_dominance,"Private completed search preserves the earlier public dominance clock until owned fresh coverage (%s)" % condition)
		var authority_tick: int = int(control.snapshot(true).room.changed_tick)
		if condition=="outside": own.position = [3.0,8.2]
		if condition=="dead":
			own.alive = false
			own.can_act = false
			own.search_eligible = false
		var reveal := context(47,[own])
		if condition=="hidden_contact": reveal.enemies = [{"position":[6.0,5.5],"room_id":"room","floor_height":0.0,"alive":true,"can_act":true,"surrendered":false,"arrested":false}]
		var changed: Dictionary = control.tick(reveal)
		if condition=="fresh":
			check(state(control,false)=="CLEAR" and changed.public_transitions.size()==1 and changed.public_transitions[0].unit_id=="alpha" and control.snapshot(false).room.changed_tick==47 and control.snapshot(true).room.changed_tick==authority_tick,"The living actual searcher supplies fresh owned coverage and declares delayed CLEAR once at the current public tick")
			var memory := JSON.stringify(control.snapshot(false))
			var duplicate: Dictionary = control.tick(context(48,[own]))
			check(JSON.stringify(control.snapshot(false))==memory and duplicate.public_transitions.is_empty(),"Fresh repeated coverage cannot emit or retime a second room-clear declaration")
		else:
			check(JSON.stringify(control.snapshot(false))==public_dominance and changed.public_transitions.is_empty(),"A %s clearer cannot publish a stale delayed clear or change its public clock/sequence" % condition)
			if condition=="hidden_contact": check(state(control)=="CONTACT","Hidden recontamination erases private search clearance before any delayed declaration")

func empty_fixture(seed_value: int = 0) -> Dictionary:
	return {"id":"ROOM_CONTROL","seed":seed_value,"bounds":[12,12],"rooms":[{"id":"room","x":5.0,"z":5.0,"w":6.0,"d":6.0,"indoor":true}],"walls":[],"props":[],"doors":[],
		"units":[{"id":"alpha","x":5.0,"z":5.0,"facing":0.0},{"id":"bravo","x":4.0,"z":5.0,"facing":1.0}],"enemies":[],"civilians":[],"win":[{"type":"reach_zone","zone":[11.0,11.0,0.1,0.1]}],"fail":[]}

func _actual_search_contracts() -> void:
	var sim := sim_for(empty_fixture())
	advance(sim,1)
	check(sim.room_states.room.state=="DOMINATED","Simulation supplies actual stationary and current observation facts")
	advance(sim,44)
	check(sim.room_states.room.state=="DOMINATED","Simulation cannot clear at 44 fixed search steps")
	advance(sim,1)
	check(sim.room_states.room.state=="CLEAR","Simulation clears at 45 fixed search steps")
	var calls: Array = sim.events.filter(func(event: Dictionary) -> bool: return event.type in ["CALL_CLEAR","CALL_ROOM_CLEAR"])
	check(calls.size()==2 and calls[0].type=="CALL_CLEAR" and calls[1].type=="CALL_ROOM_CLEAR" and int(calls[1].seq)>int(calls[0].seq),"Actual simulation emits ordered dominance and room-clear calls once")
	sim = sim_for(empty_fixture())
	advance(sim,45)
	issue(sim,"alpha","MOVE",{"target":[5.0,5.0]})
	issue(sim,"bravo","MOVE",{"target":[4.0,5.0]})
	advance(sim,1)
	check(sim.room_states.room.state!="CLEAR","A MOVE completing READY in the 45th search tick still interrupts actual search")
	advance(sim,44)
	check(sim.room_states.room.state!="CLEAR","Completed movement cannot donate its busy tick to a fresh search")
	advance(sim,1)
	check(sim.room_states.room.state=="CLEAR","Room can be searched fully after a completed movement")
	var door_data := empty_fixture()
	door_data.units = [door_data.units[0]]
	door_data.doors = [{"id":"door","x":7.0,"z":5.0,"axis":"z","w":0.2,"d":1.8,"state":"CLOSED","hinge_side":-1.0,"swing_sign":1.0}]
	sim = sim_for(door_data)
	advance(sim,45)
	issue(sim,"alpha","OPEN_DOOR",{"door_id":"door"})
	var operation: Dictionary = sim.units[0].commands.back()
	for _tick: int in range(240):
		sim.step(STEP)
		if operation.state=="SUCCEEDED": break
	check(operation.state=="SUCCEEDED" and sim.room_states.room.state=="DOMINATED","An actual completed door operation cannot turn its READY tick into search time")
	advance(sim,44)
	check(sim.room_states.room.state=="DOMINATED","Door-operation completion is followed by only 44 fresh search steps")
	advance(sim,1)
	check(sim.room_states.room.state=="CLEAR","Door operator clears after a new complete 45 STEP search")
	var objective := empty_fixture()
	objective.win = [{"type":"rooms_cleared","room_ids":["room"]}]
	sim = sim_for(objective)
	advance(sim,45)
	check(sim.result.is_empty(),"rooms_cleared does not win before the continuous search threshold")
	advance(sim,1)
	check(bool(sim.result.get("success",false)),"rooms_cleared wins on authoritative CLEAR")

func _reload_contracts() -> void:
	var data := empty_fixture()
	data.units[0].ammo = 0
	data.units[0].reserve_ammo = 24
	var sim := sim_for(data)
	issue(sim,"alpha","FACE",{"target":[7.0,5.0],"persistent":true,"sector":{"start":-0.5,"end":0.5,"duration":20.0}})
	issue(sim,"bravo","FACE",{"target":[4.0,7.0],"persistent":true,"sector":{"start":1.0,"end":2.0,"duration":20.0}})
	advance(sim,1)
	var cover: Dictionary = sim.units[1]
	var saved := {"facing":cover.facing,"facing_locked":cover.facing_locked,"facing_persistent":cover.facing_persistent,"sector":cover.sector.duplicate(true),"commands":cover.commands.duplicate(true),"ammo":cover.ammo,"reserve_ammo":cover.reserve_ammo}
	issue(sim,"alpha","RELOAD")
	var began := false
	var finished := false
	for _tick: int in range(180):
		sim.step(STEP)
		if sim._reload_covers.has("alpha"):
			began = true
			check(sim._reload_covers.alpha.cover_unit_id=="bravo" and cover.get("_reload_cover_for","")=="alpha","Actual RELOAD borrows the closest eligible ally")
			check(cover.commands==saved.commands and cover.ammo==saved.ammo and cover.reserve_ammo==saved.reserve_ammo,"Temporary reload coverage preserves the cover queue and ammunition")
			check(absf(float(cover.facing)-float(sim.units[0].facing))<0.0001 and not cover.sector.is_empty(),"Closest ally actually faces and covers the reloader's leased sector")
		if began and not sim._reload_covers.has("alpha"):
			finished = true
			break
	check(began and finished and int(sim.units[0].ammo)==int(sim.units[0].max_ammo),"Actual reload consumes reserved ammunition and completes its lease")
	check(cover.facing==saved.facing and cover.facing_locked==saved.facing_locked and cover.facing_persistent==saved.facing_persistent and cover.sector==saved.sector and cover.commands==saved.commands,"Reload completion restores the ally's previous facing, sector and command queue")
	var calls: Array = sim.events.filter(func(event: Dictionary) -> bool: return event.type in ["CALL_RELOADING","CALL_GUN_UP"])
	check(calls.size()==2 and calls[0].type=="CALL_RELOADING" and calls[1].type=="CALL_GUN_UP" and calls[0].cover_unit_id=="bravo" and calls[1].cover_unit_id=="bravo","Reload and gun-up calls identify the actual ally and retain order")
	# The reloader is the only searcher in this room; its cover is physically
	# outside. Thus a completed READY reload cannot donate its last busy STEP.
	data = empty_fixture()
	data.units[0].ammo = 0
	data.units[0].reserve_ammo = 24
	data.units[1].x = 9.0
	sim = sim_for(data)
	advance(sim,45)
	issue(sim,"alpha","RELOAD")
	var command: Dictionary = sim.units[0].commands.back()
	var completion := -1
	for _tick: int in range(180):
		sim.step(STEP)
		if command.state=="SUCCEEDED":
			completion = sim.tick
			break
	check(completion>45 and sim.room_states.room.state=="DOMINATED","Actual RELOAD completion remains a busy search interruption even after status READY")
	advance(sim,44)
	check(sim.room_states.room.state=="DOMINATED","Actual reload completion is followed by only 44 qualifying search steps")
	advance(sim,1)
	check(sim.room_states.room.state=="CLEAR","Actual reload permits clearance after a fresh complete search")

func _actual_control_contracts() -> void:
	for kind: String in ["surrendered","civilian"]:
		for hp: float in [100.0,0.0]:
			var data := empty_fixture()
			data.units = [data.units[0]]
			data.units[0].ammo = 0
			if kind=="surrendered": data.enemies = [{"id":"person","x":6.0,"z":5.0,"hp":hp,"surrendered":true,"ammo":0}]
			else: data.civilians = [{"id":"person","x":6.0,"z":5.0,"hp":hp,"secured":false}]
			var sim := sim_for(data)
			advance(sim,90)
			check(sim.room_states.room.state!="CLEAR","Actual %s HP=%.0f is not controlled by incapacity or elapsed search" % [kind,hp])
			if hp<=0.0: continue
			issue(sim,"alpha","ARREST" if kind=="surrendered" else "SECURE_CIVILIAN",{"enemy_id":"person"} if kind=="surrendered" else {"civilian_id":"person"})
			var command: Dictionary = sim.units[0].commands.back()
			var succeeded := false
			for _tick: int in range(180):
				sim.step(STEP)
				if command.state=="SUCCEEDED":
					succeeded = true
					break
			check(succeeded and sim.room_states.room.state!="CLEAR","Actual %s control action completes before a new search can finish" % kind)
			advance(sim,44)
			check(sim.room_states.room.state!="CLEAR","Actual %s action's READY completion tick cannot count as search" % kind)
			advance(sim,1)
			check(sim.room_states.room.state=="CLEAR","Actually controlled %s clears only after a fresh complete search" % kind)

func _reload_movement_contracts() -> void:
	for edited: bool in [false,true]:
		var data := empty_fixture()
		data.units[0].ammo = 0
		data.units[0].reserve_ammo = 24
		var sim := sim_for(data)
		issue(sim,"bravo","MOVE",{"target":[4.0,7.0]})
		advance(sim,1)
		issue(sim,"alpha","RELOAD")
		advance(sim,1)
		var cover: Dictionary = sim.units[1]
		var leased_position := position(cover)
		var queue := JSON.stringify(cover.commands)
		var original_id := str(cover.commands[0].id)
		check(sim._reload_covers.has("alpha") and cover.get("_reload_cover_for","")=="alpha","A moving ally actually accepts a reload-cover lease")
		for _tick: int in range(20):
			sim.step(STEP)
			check(position(cover).distance_to(leased_position)<0.000001 and JSON.stringify(cover.commands)==queue,"Reload cover holds the moving ally physically without advancing its command or path cursor")
		if edited:
			var changed: Dictionary = sim.issue("bravo","FACE",{"target":[6.0,5.0],"persistent":true},false)
			check(bool(changed.get("ok",false)),"The player may explicitly replace a borrowed ally's movement plan")
			sim.step(STEP)
			check(not sim._reload_covers.has("alpha") and cover.get("_reload_cover_for","").is_empty() and cover.commands[0].state=="CANCELLED" and cover.commands.back().type=="FACE" and cover.commands.back().args.target==[6.0,5.0],"An explicit cover edit releases its lease and keeps the player's replacement command")
		var reload: Dictionary = sim.units[0].commands[0]
		for _tick: int in range(180):
			sim.step(STEP)
			if reload.state=="SUCCEEDED": break
		check(reload.state=="SUCCEEDED" and not sim._reload_covers.has("alpha") and cover.get("_reload_cover_for","").is_empty(),"Actual reload completion releases the moving ally's lease")
		var calls: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type in ["CALL_RELOADING","CALL_GUN_UP"])
		check(calls.size()==2 and calls[0].type=="CALL_RELOADING" and calls[1].type=="CALL_GUN_UP","Actual gun-up is emitted once even after an earlier explicit coverage edit")
		advance(sim,120)
		if edited:
			check(cover.commands[0].id==original_id and cover.commands[0].state=="CANCELLED" and cover.commands.back().state=="SUCCEEDED" and bool(cover.facing_persistent),"Lease cleanup preserves the replacement command's history and persistent facing")
		else:
			check(cover.commands.size()==1 and cover.commands[0].id==original_id and cover.commands[0].state=="SUCCEEDED" and position(cover).distance_to(Vector2(4.0,7.0))<=0.1,"A covered MOVE resumes its original command and reaches its actual original goal")

func _actual_shot_contracts() -> void:
	var data := empty_fixture()
	data.units = [data.units[0]]
	data.units[0].facing = -PI*0.5
	data.enemies = [{"id":"training","x":9.0,"z":5.0,"target":true,"ammo":0}]
	var sim := sim_for(data)
	advance(sim,20)
	check(sim.room_states.room.state=="DOMINATED" and sim.shots_fired==0,"A real in-room search proceeds before the target enters the operator's cone")
	issue(sim,"alpha","FACE",{"target":[9.0,5.0],"persistent":true})
	var actual_shots := 0
	var reset_on_shot := true
	var last_shot := -1
	for _tick: int in range(240):
		var before := int(sim.shots_fired)
		sim.step(STEP)
		if sim.shots_fired>before:
			actual_shots += int(sim.shots_fired)-before
			last_shot = sim.tick
			reset_on_shot = reset_on_shot and sim.room_states.room.state=="DOMINATED" and not sim.room_control._search.has("room")
		if float(sim.enemies[0].hp)<=0.0: break
	check(actual_shots>0 and last_shot>20 and reset_on_shot and float(sim.enemies[0].hp)<=0.0,"Actual aimed shots reset partial search and resolve the outside target without rule or HP injection")
	advance(sim,44)
	check(sim.room_states.room.state=="DOMINATED","An actual final shot cannot donate its firing tick to 44 subsequent search steps")
	advance(sim,1)
	check(sim.room_states.room.state=="CLEAR","The actual firing operator can clear after a full fresh search")

func _actual_hit_contracts() -> void:
	var data := empty_fixture()
	data.units = [data.units[0]]
	data.units[0].ammo = 0
	data.enemies = [{"id":"shooter","x":9.0,"z":5.0,"facing":PI,"response_role":"guard"}]
	var sim := sim_for(data)
	var shot_count := 0
	var hit_after_search := false
	var reset := false
	for _tick: int in range(240):
		var before_hits := int(sim.hits_taken)
		var before_ammo := int(sim.enemies[0].ammo)
		var prior_elapsed := float(sim.room_control._search.get("room",{}).get("elapsed",0.0))
		sim.step(STEP)
		if not bool(sim.enemies[0].surrendered): shot_count += maxi(0,before_ammo-int(sim.enemies[0].ammo))
		if sim.hits_taken>before_hits:
			hit_after_search = prior_elapsed>0.0
			reset = not sim.room_control._search.has("room") and is_equal_approx(float(sim.units[0].get("_last_hit_time",-1.0)),sim.time)
			break
	check(shot_count>0 and sim.hits_taken>0 and hit_after_search and float(sim.units[0].hp)>0.0,"A physical hostile shot hits a living operator after real partial search")
	check(reset and sim.room_states.room.state=="DOMINATED","Actual hit facts reset search even while the armored operator can still act")

func _actual_stun_contracts() -> void:
	var data := empty_fixture()
	data.units = [data.units[0]]
	data.units[0].ammo = 0
	data.enemies = [{"id":"training","x":7.7,"z":5.0,"target":true,"ammo":0}]
	var sim := sim_for(data)
	advance(sim,5)
	check(sim.room_states.room.state!="CLEAR","An able-to-act ordinary target blocks actual room search")
	issue(sim,"alpha","THROW_STUN",{"target":[7.7,5.0]})
	var clear_tick := -1
	var clear_while_unable := false
	for _tick: int in range(150):
		sim.step(STEP)
		if sim.room_states.room.state=="CLEAR":
			clear_tick = sim.tick
			clear_while_unable = not sim._can_act(sim.enemies[0])
			break
	check(sim.stuns_used==1 and clear_tick>=0 and clear_while_unable and float(sim.enemies[0].hp)==72.0 and not bool(sim.enemies[0].surrendered),"Actual flash flight and explosion permit a full search while the ordinary living target cannot act")
	for _tick: int in range(90):
		sim.step(STEP)
		if sim._can_act(sim.enemies[0]): break
	check(sim._can_act(sim.enemies[0]) and sim.room_states.room.state=="CONTACT" and sim.snapshot(false).room_states.room.state=="CONTACT","Actual visible recovery resets room authority and public memory to CONTACT in its recovery tick")

func _short_room_contracts() -> void:
	var data := man_down_fixture(0)
	data.enemies = []
	for unit: Dictionary in data.units:
		unit.hp = 100.0
		unit.ammo = 24
	data.rooms = [{"id":"room","x":8.0,"z":9.0,"w":3.0,"d":3.0,"indoor":true}]
	data.walls = [{"x":6.5,"z":9.0,"w":0.2,"d":3.0},{"x":9.5,"z":9.0,"w":0.2,"d":3.0},{"x":8.0,"z":7.5,"w":3.0,"d":0.2}]
	var sim := sim_for(data)
	var plan: Dictionary = sim.plan_room_entry("door","OPEN_DOOR",ORDER,{})
	check(bool(plan.get("ok",false)) and bool(plan.get("short_room",false)),"Actual small-room drill selects SHORT_ROOM")
	var arrived: Dictionary = {}
	var dominance := -1
	var clearance := -1
	var entrants: Array = []
	for _tick: int in range(450):
		sim.step(STEP)
		for index: int in range(mini(2,plan.get("slots",[]).size())):
			var unit: Dictionary = sim.units[index]
			if not arrived.has(unit.id) and position(unit).distance_to(point(plan.slots[index].domination))<=0.1: arrived[unit.id] = sim.tick
		if dominance<0 and sim.room_states.room.state=="DOMINATED": dominance = sim.tick
		if clearance<0 and sim.room_states.room.state=="CLEAR": clearance = sim.tick
	for contract: Dictionary in sim._room_registered.values(): entrants = contract.participants
	check(entrants.size()==2 and entrants.has("alpha") and entrants.has("bravo") and not entrants.has("charlie") and not entrants.has("delta"),"Actual entry registration excludes both outside short-room guards")
	check(arrived.size()==2 and dominance>=maxi(int(arrived.get("alpha",10000)),int(arrived.get("bravo",10000))) and clearance>=dominance+45,"SHORT_ROOM reaches both real goals before dominance and a full search")
	check(sim.units.slice(2).all(func(unit: Dictionary)->bool:return sim.room_control.room_at(position(unit))!="room") and sim.command_failures==0,"Both outside guards retain physical positions and successful primitive queues")
	var calls: Array = sim.events.filter(func(event: Dictionary)->bool:return event.type=="CALL_SHORT_ROOM")
	check(calls.size()==1 and calls[0].room_id=="room" and bool(calls[0].observed),"Actual barrier release emits one observed short-room call")

func rear_fixture(seed_value: int) -> Dictionary:
	var units: Array = []
	var positions: Array = [[9.3,16.45],[6.7,16.45],[9.3,17.15],[6.7,17.15]]
	for index: int in range(4):
		var origin := point(positions[index])
		units.append({"id":ORDER[index],"x":origin.x,"z":origin.y,"facing":(Vector2(8.0,16.0)-origin).angle(),"weapon":"shotgun" if index==0 else "standard","reserve_ammo":72})
	return {"id":"ROOM_CONTROL_REAR","seed":seed_value,"variant":"normal","bounds":[16,20],
		"rooms":[{"id":"rear","x":8.0,"z":13.0,"w":6.0,"d":6.0,"indoor":true},{"id":"front","x":8.0,"z":7.0,"w":6.0,"d":6.0,"indoor":true},{"id":"reserve","x":13.0,"z":13.0,"w":4.0,"d":6.0,"indoor":true},{"id":"target","x":3.0,"z":8.4,"w":4.0,"d":2.4,"indoor":true}],
		"walls":[{"x":5.0,"z":13.0,"w":0.2,"d":6.0},{"x":11.0,"z":10.6,"w":0.2,"d":1.2},{"x":11.0,"z":14.4,"w":0.2,"d":3.2},{"x":6.05,"z":10.0,"w":2.1,"d":0.2},{"x":9.95,"z":10.0,"w":2.1,"d":0.2},{"x":6.05,"z":16.0,"w":2.1,"d":0.2},{"x":9.95,"z":16.0,"w":2.1,"d":0.2},{"x":5.0,"z":5.8,"w":0.2,"d":3.6},{"x":5.0,"z":9.6,"w":0.2,"d":0.8},{"x":11.0,"z":7.0,"w":0.2,"d":6.0},{"x":8.0,"z":4.0,"w":6.0,"d":0.2},{"x":13.0,"z":10.0,"w":4.0,"d":0.2},{"x":13.0,"z":16.0,"w":4.0,"d":0.2},{"x":15.0,"z":13.0,"w":0.2,"d":6.0},{"x":1.0,"z":8.4,"w":0.2,"d":2.4},{"x":3.0,"z":7.2,"w":4.0,"d":0.2},{"x":3.0,"z":9.6,"w":4.0,"d":0.2}],
		"doors":[{"id":"entry","x":8.0,"z":16.0,"axis":"x","w":1.8,"d":0.2,"state":"CLOSED","hinge_side":-1.0,"swing_sign":1.0},{"id":"forward","x":8.0,"z":10.0,"axis":"x","w":1.8,"d":0.2,"state":"CLOSED","hinge_side":-1.0,"swing_sign":1.0},{"id":"reserve","x":11.0,"z":12.0,"axis":"z","w":0.2,"d":1.6,"state":"CLOSED","hinge_side":1.0,"swing_sign":-1.0},{"id":"target","x":5.0,"z":8.4,"axis":"z","w":0.2,"d":1.6,"state":"CLOSED","hinge_side":-1.0,"swing_sign":1.0}],"props":[],"units":units,
		"enemies":[{"id":"reserve","x":11.65,"z":12.0,"facing":PI,"response_role":"reserve","weapon":"standard"},{"id":"training","x":3.4,"z":8.4,"facing":PI,"target":true,"ammo":0}],"civilians":[],"win":[{"type":"reach_zone","zone":[15.0,19.0,0.1,0.1]}],"fail":[]}

func waiting(sim: RefCounted, channel: String) -> bool:
	for unit: Dictionary in sim.units:
		var command := active(unit)
		if command.get("type","")!="WAIT_FOR_SIGNAL" or command.get("state","")!="WAITING" or command.args.get("signal","")!=channel: return false
	return true

func rear_case(seed_value: int, guard: bool) -> Dictionary:
	var sim := sim_for(rear_fixture(seed_value))
	var planned: Dictionary = sim.plan_room_entry("entry","OPEN_DOOR",ORDER,{})
	check(bool(planned.get("ok",false)),"seed %d rear setup uses an actual four-person drill" % seed_value)
	var cleared := false
	for _tick: int in range(900):
		sim.step(STEP)
		if sim.room_states.rear.state=="CLEAR":
			cleared = true
			break
	check(cleared,"seed %d rear room is actually searched clear before the advance" % seed_value)
	issue(sim,"alpha","OPEN_DOOR",{"door_id":"forward"})
	var goals: Array = [[6.8,8.4],[9.5,8.4],[9.5,6.7],[8.9,8.9]]
	var looks: Array = [[3.0,8.4],[9.5,4.8],[10.5,4.8],[8.9,13.0] if guard else [8.9,4.8]]
	for index: int in range(4):
		issue(sim,ORDER[index],"WAIT_FOR_SIGNAL",{"signal":"B"})
		issue(sim,ORDER[index],"MOVE",{"target":goals[index]})
		issue(sim,ORDER[index],"FACE",{"target":looks[index],"persistent":true})
	var released := false
	var arrived := false
	for _tick: int in range(900):
		if not released and sim._find(sim.doors,"forward").state=="OPEN" and waiting(sim,"B"):
			sim.release_signal("B")
			released = true
		sim.step(STEP)
		arrived = true
		for index: int in range(4): arrived = arrived and position(sim.units[index]).distance_to(point(goals[index]))<=0.1 and active(sim.units[index]).is_empty()
		if arrived: break
	check(released and arrived and sim.room_states.rear.state=="MARKED","seed %d all four physically leave through the forward door and mark the cleared rear room" % seed_value)
	var reserve: Dictionary = sim._find(sim.enemies,"reserve")
	var before_trigger := position(reserve)
	check(before_trigger.distance_to(Vector2(11.65,12.0))<0.01,"seed %d reserve stays behind its closed door before actual gunfire" % seed_value)
	issue(sim,"alpha","OPEN_DOOR",{"door_id":"target"})
	issue(sim,"alpha","MOVE",{"target":[5.85,8.4]})
	issue(sim,"alpha","FACE",{"target":[3.0,8.4],"persistent":true})
	var first_shot := -1
	var hostile_shots := 0
	var travelled := 0.0
	var marked_contact := false
	var guarded := false
	var trace: Array = []
	var shot_origin: Array = []
	var sound_audibility := 0.0
	var first_move := -1
	var first_guarded := -1
	var physical := true
	var horizon := 900
	for frame: int in range(horizon):
		var previous := position(reserve)
		var ammo := int(reserve.ammo)
		var own_shots := int(sim.shots_fired)
		sim.step(STEP)
		if first_shot<0 and sim.shots_fired>own_shots:
			first_shot = sim.tick
			shot_origin = [sim.units[0].x,sim.units[0].z]
			sound_audibility = sim._acoustic.audibility(point(shot_origin),position(reserve),14.0)
		if first_move<0 and position(reserve).distance_to(before_trigger)>0.001: first_move = sim.tick
		if first_guarded<0 and reserve.get("_rear_state","")=="guarded": first_guarded = sim.tick
		physical = physical and position(reserve).distance_to(previous)<=0.115
		travelled += position(reserve).distance_to(previous)
		if not bool(reserve.get("surrendered",false)): hostile_shots += maxi(0,ammo-int(reserve.ammo))
		marked_contact = marked_contact or sim.room_states.rear.state=="CONTACT"
		guarded = guarded or reserve.get("_rear_state","")=="guarded"
		if "--rear-probe-only" in OS.get_cmdline_user_args() and frame%30==0:
			trace.append({"tick":sim.tick,"time":sim.time,"reserve":[reserve.x,reserve.z],"state":reserve.get("_rear_state",""),"heard":reserve.get("_rear_heard_at",-1),"ready":reserve.get("_rear_ready_at",-1),"goal":reserve.get("_rear_goal",[]),"path":reserve.get("_rear_path",[]),"own":sim.units.map(func(unit: Dictionary)->Dictionary:return {"id":unit.id,"position":[unit.x,unit.z],"hp":unit.hp,"facing":unit.facing}),"hits":sim.hits_taken})
		if first_shot>=0 and sim.tick-first_shot>=450: break
	var metrics: Dictionary = sim._statistics()
	check(first_shot>=0,"seed %d rear response is triggered by an actual player's shot" % seed_value)
	check(first_shot>=0 and sim.tick-first_shot==450,"seed %d rear comparison runs exactly 450 fixed STEP after its actual shot" % seed_value)
	check(sound_audibility>0.0 and absf(float(reserve.get("_rear_heard_at",-1.0))-first_shot*STEP)<=0.000001 and absf(float(reserve.get("_rear_ready_at",-1.0))-float(reserve.get("_rear_heard_at",-1.0))-2.0)<=0.000001,"seed %d the actual audible shotgun event starts a deterministic two-second reserve delay" % seed_value)
	check(first_move>=first_shot+60 and physical,"seed %d reserve movement starts after its real delay and remains physically continuous" % seed_value)
	check(travelled>0.4,"seed %d reserve actually follows physical navigation before holding or shooting" % seed_value)
	if guard:
		check(sim.hits_taken==0 and int(metrics.rear_hits)==0,"seed %d guarded cleared route incurs no actual hits or rear hits" % seed_value)
		check(guarded,"seed %d reserve actually avoids a watched MARKED route" % seed_value)
	else:
		check(hostile_shots>0 and sim.hits_taken>0 and int(metrics.rear_hits)>0,"seed %d immediate forward rush exposes actual hostile fire and rear hits" % seed_value)
		check(marked_contact,"seed %d reserve physically re-enters the vacated marked rear room before attacking the forward rush" % seed_value)
	return {"seed":seed_value,"guard":guard,"cleared":cleared,"arrived":arrived,"first_shot_tick":first_shot,"end_tick":sim.tick,"shot_origin":shot_origin,"sound_audibility":sound_audibility,"first_move_tick":first_move,"first_guarded_tick":first_guarded,"physical":physical,"travelled":travelled,"hostile_shots":hostile_shots,"hits_taken":sim.hits_taken,"rear_hits":metrics.rear_hits,"guarded":guarded,"marked_contact":marked_contact,"command_failures":sim.command_failures,"rear_private":reserve.duplicate(true),"final_units":sim.units.map(func(unit: Dictionary)->Dictionary:return {"id":unit.id,"position":[unit.x,unit.z],"active":active(unit),"commands":unit.commands}),"trace":trace,"state_hash":JSON.stringify({"state":sim.snapshot(true),"rng":[sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]}).sha256_text()}

func _rear_benchmark() -> void:
	var rows: Array = []
	for seed_value: int in range(SEEDS):
		var rush := rear_case(seed_value,false)
		var guard := rear_case(seed_value,true)
		check(JSON.stringify(rush)==JSON.stringify(rear_case(seed_value,false)) and JSON.stringify(guard)==JSON.stringify(rear_case(seed_value,true)),"seed %d identical rear plans repeat physical results and all RNG states" % seed_value)
		rows.append({"seed":seed_value,"rush":rush,"guard":guard})
	report["rear"] = rows
	report["scope"] = "Four empty-room entrants physically search and mark the rear room, then all exit forward. The only paired command difference is the last entrant's persistent FACE toward the rear portal. An actual shotgun shot at a separate enclosed training target wakes a reserve behind its closed side door. Both plans run exactly 450 fixed STEP after the first shot; no HP, hit, alert, shot or movement injection."

func man_down_fixture(seed_value: int) -> Dictionary:
	# A wounded, unarmored point operator has 30 authored HP. Every casualty
	# below still requires real enemy aim, physical LOS, accuracy and damage.
	# Empty rifles make the pre-reload contact deliberately vulnerable; actual
	# public RELOAD commands restore all three survivors' ability to respond.
	var positions: Array = [[9.3,10.95],[6.7,10.95],[9.3,11.65],[6.7,11.65]]
	var units: Array = []
	for index: int in range(4):
		var origin := point(positions[index])
		units.append({"id":ORDER[index],"x":origin.x,"z":origin.y,"facing":(Vector2(8.0,10.5)-origin).angle(),"hp":30.0 if index==0 else 100.0,"armor":"none","helmet":"none","ammo":0,"reserve_ammo":72})
	return {"id":"ROOM_CONTROL_MAN_DOWN","seed":seed_value,"variant":"normal","bounds":[16,16],
		"rooms":[{"id":"room","x":8.0,"z":8.0,"w":5.0,"d":5.0,"indoor":true}],
		"walls":[{"x":5.5,"z":8.0,"w":0.2,"d":5.0},{"x":10.5,"z":8.0,"w":0.2,"d":5.0},{"x":8.0,"z":5.5,"w":5.0,"d":0.2},{"x":6.25,"z":10.5,"w":1.5,"d":0.2},{"x":9.75,"z":10.5,"w":1.5,"d":0.2}],
		"doors":[{"id":"door","x":8.0,"z":10.5,"axis":"x","w":1.8,"d":0.2,"state":"CLOSED","hinge_side":-1.0,"swing_sign":1.0}],"props":[],"units":units,
		"enemies":[{"id":"shooter","x":9.5,"z":6.4,"facing":PI*0.5,"response_role":"guard"}],"civilians":[],"win":[{"type":"reach_zone","zone":[15.0,15.0,0.1,0.1]}],"fail":[]}

func man_down_case(seed_value: int) -> Dictionary:
	var sim := sim_for(man_down_fixture(seed_value))
	var planned: Dictionary = sim.plan_room_entry("door","OPEN_DOOR",ORDER,{})
	check(bool(planned.get("ok",false)),"seed %d actual casualty drill accepted" % seed_value)
	var first_death := -1
	var dead_id := ""
	var base := ""
	var targets: Dictionary = {}
	var after_death: Array = []
	var arrivals: Dictionary = {}
	var minimum_spacing := INF
	var physical := true
	var trace: Array = []
	var hostile_shots := 0
	var shooter: Dictionary = sim.enemies[0]
	var recorded_events: Array = sim.take_record_events()
	for frame: int in range(900):
		var old: Array = sim.units.map(func(unit: Dictionary)->Vector2:return position(unit))
		var old_ammo := int(shooter.ammo)
		sim.step(STEP)
		recorded_events.append_array(sim.take_record_events())
		if not bool(shooter.get("surrendered",false)): hostile_shots += maxi(0,old_ammo-int(shooter.ammo))
		for index: int in range(4):
			var unit: Dictionary = sim.units[index]
			physical = physical and position(unit).distance_to(old[index])<=0.115
			if float(unit.hp)<=0.0: continue
			physical = physical and not Door.overlaps_actor(sim.doors[0],-1.0,position(unit),Navigation.RADIUS)
			for other: int in range(index):
				if float(sim.units[other].hp)>0.0: minimum_spacing = minf(minimum_spacing,position(unit).distance_to(position(sim.units[other])))
		if first_death<0:
			for unit: Dictionary in sim.units:
				if float(unit.hp)>0.0: continue
				first_death = sim.tick
				dead_id = str(unit.id)
				after_death = sim.units.map(func(member: Dictionary)->Dictionary:return {"id":member.id,"hp":member.hp,"commands":member.commands.duplicate(true)})
				for value: String in sim._room_registered:
					var contract: Dictionary = sim._room_registered[value]
					if contract.room_id=="room":
						base = value
						targets = contract.targets.duplicate(true)
				for member: Dictionary in sim.units:
					if float(member.hp)>0.0: issue(sim,str(member.id),"RELOAD")
				break
		if first_death>=0:
			for id: String in targets:
				var unit: Dictionary = sim._find(sim.units,id)
				if float(unit.hp)>0.0 and position(unit).distance_to(point(targets[id]))<=0.1 and not arrivals.has(id): arrivals[id] = sim.tick
		if "--man-down-probe-only" in OS.get_cmdline_user_args() and frame%30==0:
			trace.append({"tick":sim.tick,"targets":targets.duplicate(true),"shooter":{"position":[shooter.x,shooter.z],"hp":shooter.hp,"ammo":shooter.ammo,"surrendered":shooter.surrendered},"own":sim.units.map(func(unit: Dictionary)->Dictionary:return {"id":unit.id,"position":[unit.x,unit.z],"hp":unit.hp,"active":active(unit).duplicate(true)})})
		if arrivals.size()==3 and sim.units.filter(func(unit: Dictionary)->bool:return float(unit.hp)>0.0).all(func(unit: Dictionary)->bool:return active(unit).is_empty()): break
	var calls: Array = recorded_events.filter(func(event: Dictionary)->bool:return event.type=="CALL_MAN_DOWN")
	var survivor_ids: Array = sim.units.filter(func(unit: Dictionary)->bool:return float(unit.hp)>0.0).map(func(unit: Dictionary)->String:return str(unit.id))
	var ranks: Array = []
	var original_door_count := 0
	var final_door_count := 0
	for member: Dictionary in after_death:
		for command: Dictionary in member.commands:
			if command.type in ["OPEN_DOOR","BREACH_DOOR","SHOTGUN_BREACH"]: original_door_count += 1
			if member.id==dead_id: continue
			if command.state not in ["SUCCEEDED","CANCELLED"] and command.args.get("drill",{}).get("sync_id","")==base: ranks.append(int(command.args.drill.order))
	for unit: Dictionary in sim.units:
		for command: Dictionary in unit.commands:
			if command.type in ["OPEN_DOOR","BREACH_DOOR","SHOTGUN_BREACH"]: final_door_count += 1
	check(first_death>=0 and dead_id=="alpha" and hostile_shots>0 and sim.hits_taken>0,"seed %d actual normal enemy gunfire incapacitates the wounded point operator" % seed_value)
	check(targets.size()==3 and survivor_ids.size()==3 and not targets.has(dead_id),"seed %d same-step casualty atomically replaces the four-person entry with three living target owners" % seed_value)
	check(not ranks.is_empty() and ranks.all(func(rank: int)->bool:return rank>=1 and rank<=3) and ranks.has(1) and ranks.has(2) and ranks.has(3),"seed %d all pending survivor drill metadata compacts to ranks 1, 2 and combined 3/4" % seed_value)
	check(arrivals.size()==3 and survivor_ids.all(func(id: String)->bool:return targets.has(id) and position(sim._find(sim.units,id)).distance_to(point(targets[id]))<=0.1),"seed %d every survivor reaches its actual recalculated domination goal" % seed_value)
	check(physical and minimum_spacing>=Navigation.RADIUS*2.0-0.0001,"seed %d casualty reformation retains body spacing, leaf clearance and fixed-step movement" % seed_value)
	check(calls.size()==1 and calls[0].unit_id==dead_id and int(calls[0].tick)==first_death and not sim.pause_requested,"seed %d casualty call occurs in its actual death tick with default auto-pause disabled" % seed_value)
	check(original_door_count==1 and final_door_count==1 and sim.doors[0].state=="OPEN" and sim.command_failures==0,"seed %d three-person reformation preserves the consumed single door action without reissuing it" % seed_value)
	return {"seed":seed_value,"death_tick":first_death,"dead_id":dead_id,"targets":targets,"arrivals":arrivals,"ranks":ranks,"survivors":survivor_ids,"hostile_shots":hostile_shots,"hits_taken":sim.hits_taken,"minimum_spacing":minimum_spacing,"physical":physical,"calls":calls,"after_death":after_death,"command_failures":sim.command_failures,"trace":trace,"state_hash":JSON.stringify({"state":sim.snapshot(true),"rng":[sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]}).sha256_text()}

func _man_down_benchmark() -> void:
	var rows: Array = []
	for seed_value: int in range(SEEDS):
		var row := man_down_case(seed_value)
		check(JSON.stringify(row)==JSON.stringify(man_down_case(seed_value)),"seed %d actual casualty, atomic three-person targets and completed execution repeat deterministically" % seed_value)
		rows.append(row)
	report["man_down"] = rows

func _before_entry_casualty_contract() -> void:
	# This single boundary regression starts the rear guard critically wounded.
	# A real exterior guard's single authored round kills DELTA before the
	# entry barrier can register; no scripted injury or forced shot is used.
	# The 30-seed casualty benchmark above keeps its original 30 HP point man.
	var data := man_down_fixture(0)
	data.units[0].hp = 100.0
	data.units[3].hp = 1.0
	data.enemies = [{"id":"shooter","x":6.7,"z":13.5,"facing":-PI*0.5,"response_role":"guard","ammo":1,"reserve_ammo":0}]
	data.win = [{"type":"rooms_cleared","room_ids":["room"]}]
	var sim := sim_for(data)
	var resources: Array = sim.units.map(func(unit: Dictionary)->Dictionary:return {"ammo":unit.ammo,"reserve_ammo":unit.reserve_ammo,"breaches":unit.breaches,"stuns":unit.stuns})
	var plan: Dictionary = sim.plan_room_entry("door","OPEN_DOOR",ORDER,{})
	check(bool(plan.get("ok",false)),"Pre-registration casualty uses an accepted actual four-person door drill")
	var death: Dictionary = {}
	var recorded: Array = sim.take_record_events()
	var physical := true
	var spacing := INF
	for _tick: int in range(450):
		var prior: Array = sim.units.map(func(unit: Dictionary)->Vector2:return position(unit))
		sim.step(STEP)
		recorded.append_array(sim.take_record_events())
		for index: int in range(4):
			var unit: Dictionary = sim.units[index]
			physical = physical and position(unit).distance_to(prior[index])<=0.115
			if float(unit.hp)<=0.0: continue
			physical = physical and not Door.overlaps_actor(sim.doors[0],-1.0,position(unit),Navigation.RADIUS)
			for other: int in range(index):
				if float(sim.units[other].hp)>0.0: spacing = minf(spacing,position(unit).distance_to(position(sim.units[other])))
		if death.is_empty() and float(sim.units[3].hp)<=0.0: death = {"tick":sim.tick,"registered":sim._room_registered.size(),"door_state":sim.doors[0].state}
		if not sim.result.is_empty(): break
	check(not death.is_empty() and int(death.get("registered",-1))==0 and death.get("door_state","")=="CLOSED" and sim.hits_taken==1 and int(sim.enemies[0].ammo)==0,"Actual DELTA casualty occurs from one exterior shot before the closed door's entry registration")
	var contract: Dictionary = {}
	for candidate: Dictionary in sim._room_registered.values(): contract = candidate
	check(contract.get("participants",[]).size()==3 and contract.participants==["alpha","bravo","charlie"] and not contract.targets.has("delta"),"Actual entry registration explicitly recalculates the earlier casualty into three living participants")
	check(contract.get("targets",{}).size()==3 and contract.targets.keys().all(func(id: String)->bool:return float(sim._find(sim.units,id).hp)>0.0 and position(sim._find(sim.units,id)).distance_to(point(contract.targets[id]))<=0.1),"All three survivors physically reach the recalculated goals after a pre-entry casualty")
	check(bool(sim.result.get("success",false)) and sim.room_states.room.state=="CLEAR" and sim.command_failures==0,"Earlier casualty cannot leave a dead four-person registration blocking actual dominance, search or rooms_cleared")
	var calls: Array = recorded.filter(func(event: Dictionary)->bool:return event.type=="CALL_MAN_DOWN")
	var actions: Array = recorded.filter(func(event: Dictionary)->bool:return event.type=="DOOR_ACTION" and event.get("kind","")=="OPEN_DOOR")
	var door_commands := 0
	for unit: Dictionary in sim.units:
		for command: Dictionary in unit.commands:
			if command.type=="OPEN_DOOR": door_commands += 1
	check(calls.size()==1 and calls[0].unit_id=="delta" and int(calls[0].tick)==int(death.get("tick",-1)) and actions.size()==1 and door_commands==1,"Later registration neither repeats the original casualty call nor reissues its consumed door action")
	check(sim.units.map(func(unit: Dictionary)->Dictionary:return {"ammo":unit.ammo,"reserve_ammo":unit.reserve_ammo,"breaches":unit.breaches,"stuns":unit.stuns})==resources and sim.shots_fired==0,"Late three-person registration preserves all owned ammunition and equipment resources")
	check(physical and spacing>=Navigation.RADIUS*2.0-0.0001 and not sim.pause_requested,"Pre-entry casualty reformation keeps actual body, leaf and fixed-step motion with default pause disabled")

func _write_report() -> void:
	var file := FileAccess.open("res://../tests/artifacts/room-control.json",FileAccess.WRITE)
	check(file!=null,"Room-control evidence report can be written")
	if file!=null: file.store_string(JSON.stringify(report,"\t")+"\n")
