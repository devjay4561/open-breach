extends SceneTree
## P4 formations remain primitive plans. Signal receipts are occurrence facts,
## never recomputed from the poses or living roster at a later replay frame.
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Simulation = preload("res://scripts/simulation.gd")
const MainScene = preload("res://main.tscn")
const STEP := 1.0 / 30.0
const TICKS := 600
const ORDER := ["delta", "bravo", "alpha", "charlie"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
func _json(value: Variant) -> Variant: return JSON.parse_string(JSON.stringify(value))

func _run() -> void:
	_test_contracts()
	_test_sync_groups()
	_test_complete_call_bundles()
	_test_legacy_and_boundaries()
	for seed_value: int in range(30): _test_runtime(seed_value)
	await _test_main_plans()
	print("BREACH_FORMATION_REPLAY_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _formation(mission: Dictionary, stage: String = "move", order: int = 1) -> Dictionary:
	return {"sync_id":"formation-1","kind":"SERPENTINE","order":order,"stage":stage,"source_unit_id":mission.units[-1].id}

func _state(mission: Dictionary) -> Dictionary:
	var units: Array = []
	for authored: Dictionary in mission.units:
		units.append({"id":authored.id,"kind":"unit","x":authored.x,"z":authored.z,"hp":100.0,"stance":"standing","commands":[]})
	units[0].commands = [
		{"id":"move","type":"MOVE","args":{"target":[12.0,14.0],"formation":_formation(mission)},"state":"PENDING"},
		{"id":"face","type":"FACE","args":{"target":[12.0,11.0],"persistent":true,"stance":"crouched","formation":_formation(mission,"cover")},"state":"PENDING"},
		{"id":"ready","type":"WAIT_FOR_SIGNAL","args":{"signal":"A","sync_id":"formation-1:ready","auto_signal":true,"delay_ticks":3,"formation":_formation(mission,"ready")},"state":"PENDING"}]
	return {"time":0.0,"tick":0,"units":units,"enemies":[{"id":mission.enemies[0].id,"kind":"enemy","x":mission.enemies[0].x,"z":mission.enemies[0].z,"hp":72.0,"visible":false}],"civilians":[],"doors":[],"events":[]}

func _receipt(mission: Dictionary, mode: String, type: String = "SIGNAL", seq: int = 1) -> Dictionary:
	var receivers: Array = mission.units.map(func(unit: Dictionary) -> String: return str(unit.id))
	receivers.sort()
	var event := {"seq":seq,"tick":1,"time":STEP,"type":type,"signal_mode":mode,"source_unit_id":mission.units[-1].id,"receiver_unit_ids":receivers,"signal_radius":6.0 if mode=="verbal" else 0.0}
	if type=="SIGNAL": event.merge({"channel":"A","released":receivers.size(),"sync_id":"formation-1:ready","auto_signal":true})
	else: event.merge({"unit_id":mission.units[0].id,"observed":true})
	return event

func _record(mission: Dictionary, initial: Dictionary, final: Dictionary) -> Dictionary:
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(initial)
	recorder.finish(final)
	return _json(recorder.export_data())

func _test_contracts() -> void:
	var mission: Dictionary = Catalog.load("M01")
	var state := _state(mission)
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(state)
	state.tick = 1
	state.time = STEP
	state.units[0].commands[0].args.formation.kind = "ROLLING_T"
	state.events = [_receipt(mission,"verbal"),_receipt(mission,"hand_signals","CALL_MAN_DOWN",2)]
	recorder.capture(state)
	check(recorder.frames.size()==2,"In-place formation metadata edits retain their exact discrete tick")
	state.tick = 2
	state.time = STEP*2.0
	state.units[0].stance = "crouched"
	state.units[-1].hp = 0.0
	recorder.capture(state)
	check(recorder.frames.size()==3,"Executed stance changes record below the normal sample interval")
	recorder.finish(state)
	state.events[0].receiver_unit_ids.clear()
	state.units[0].commands[0].args.formation.kind = "T_JUNCTION"
	var candidate: Dictionary = _json(recorder.export_data())
	var restored := Replay.new()
	var loaded := restored.load_data(candidate)
	check(loaded.get("ok",false),"Complete P4 primitive/receipt record loads: "+str(loaded.get("message","")))
	if not loaded.get("ok",false): return
	check(candidate.schema_version==1 and candidate.encoding=="numeric-state-v1","P4 preserves the replay envelope and numeric encoding")
	check(restored.seek(0.0,true).units[0].commands[0].args.formation.kind=="SERPENTINE","Earlier interned metadata owns its independent formation dictionary")
	check(restored.seek(STEP,true).units[0].commands[0].args.formation.kind=="ROLLING_T","Exact seek restores the authored formation edit")
	check(restored.seek(STEP*1.5,true).units[0].stance=="standing" and restored.seek(STEP*2.0,true).units[0].stance=="crouched","Stance execution cannot appear before its authoritative tick")
	check(restored.seek(STEP*2.0,false).events==candidate.events,"Receipts survive after their source becomes incapacitated without current-pose rejudgment")
	var events := restored.events_since(0,STEP*2.0,false)
	check(events==candidate.events and events[0].receiver_unit_ids.size()==4,"Recording detaches the caller receipt array at occurrence")
	events[0].receiver_unit_ids.clear()
	var shown := restored.seek(STEP*2.0,false)
	shown.events[1].receiver_unit_ids.clear()
	shown.units[0].commands[0].args.formation.order = 4
	check(restored.events_since(0,STEP*2.0,false)[0].receiver_unit_ids.size()==4 and restored.seek(STEP*2.0,false).events[1].receiver_unit_ids.size()==4,"Event delta and seek arrays cannot rewrite immutable receipt history")
	check(restored.seek(STEP*2.0,true).units[0].commands[0].args.formation.order==1,"Returned command metadata independently owns its nested value")
	_test_malformed(restored,candidate,mission)

func _test_malformed(restored: RefCounted, candidate: Dictionary, mission: Dictionary) -> void:
	var before := JSON.stringify(restored.export_data())
	for mutation: String in ["extra","missing","null","array","id","long","order_zero","order_high","order_fraction","order_nan","kind_auto","kind_case","stage","source_unknown","source_enemy","owner","drill","wait_stage","wait_sync","stance","stance_type","unlock_stance","receipt_missing","receipt_owner","mode","radius","radius_nan","source_event","source_event_enemy","receivers_null","receivers_unknown","receivers_enemy","receivers_order","receivers_duplicate","receivers_many","receivers_type"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		var args: Dictionary = corrupt.commands[0].args
		var receipt: Dictionary = corrupt.events[0]
		match mutation:
			"extra": args.formation.room_id = mission.rooms[0].id
			"missing": args.formation.erase("stage")
			"null": args.formation = null
			"array": args.formation = []
			"id": args.formation.sync_id = "unsafe group"
			"long": args.formation.sync_id = "x".repeat(56)
			"order_zero": args.formation.order = 0
			"order_high": args.formation.order = 5
			"order_fraction": args.formation.order = 1.1
			"order_nan": args.formation.order = NAN
			"kind_auto": args.formation.kind = "AUTO"
			"kind_case": args.formation.kind = "serpentine"
			"stage": args.formation.stage = "door"
			"source_unknown": args.formation.source_unit_id = "unknown"
			"source_enemy": args.formation.source_unit_id = mission.enemies[0].id
			"owner": corrupt.commands[0].type = "THROW_STUN"
			"drill": args.drill = {"sync_id":"drill-1","door_id":mission.doors[0].id,"room_id":mission.rooms[0].id,"order":1,"stage":"entry"}
			"wait_stage": corrupt.commands[2].args.formation.stage = "cover"
			"wait_sync": corrupt.commands[2].args.sync_id = "other:ready"
			"stance": corrupt.commands[1].args.stance = "prone"
			"stance_type": corrupt.commands[1].args.stance = true
			"unlock_stance": corrupt.commands[1].args.erase("target"); corrupt.commands[1].args.erase("persistent"); corrupt.commands[1].args.unlock = true
			"receipt_missing": receipt.erase("signal_radius")
			"receipt_owner": receipt.type = "RELOAD"; receipt.erase("sync_id"); receipt.erase("auto_signal")
			"mode": receipt.signal_mode = "quiet"
			"radius": receipt.signal_radius = 0.0
			"radius_nan": receipt.signal_radius = NAN
			"source_event": receipt.source_unit_id = "unknown"
			"source_event_enemy": receipt.source_unit_id = mission.enemies[0].id
			"receivers_null": receipt.receiver_unit_ids = null
			"receivers_unknown": receipt.receiver_unit_ids = ["unknown"]
			"receivers_enemy": receipt.receiver_unit_ids = [mission.enemies[0].id]
			"receivers_order": receipt.receiver_unit_ids.reverse()
			"receivers_duplicate": receipt.receiver_unit_ids = [mission.units[0].id,mission.units[0].id]
			"receivers_many": receipt.receiver_unit_ids.append(mission.units[0].id)
			"receivers_type": receipt.receiver_unit_ids = [1]
		check(not restored.load_data(corrupt).get("ok",true),"Malformed P4 record rejected: "+mutation)
		check(JSON.stringify(restored.export_data())==before,"Rejected P4 record preserves active replay: "+mutation)

func _test_complete_call_bundles() -> void:
	var mission: Dictionary = Catalog.load("M01")
	for type: String in Replay.CALL_EVENT_TYPES+["SIGNAL"]:
		for mode: String in ["verbal","hand_signals"]:
			var initial := _state(mission)
			var final := initial.duplicate(true)
			final.tick = 1
			final.time = STEP
			final.events = [_receipt(mission,mode,type)]
			var candidate := _record(mission,initial,final)
			var restored := Replay.new()
			check(restored.load_data(candidate).get("ok",false),"Every CALL/SIGNAL preserves its complete occurrence bundle: "+type+"/"+mode)
			check(restored.events_since(0,STEP,false)==candidate.events,"Every observed delivery retains the original source/receivers/radius")
			for key: String in Replay.SIGNAL_PROVENANCE_KEYS:
				var corrupt: Dictionary = candidate.duplicate(true)
				corrupt.events[0].erase(key)
				check(not restored.load_data(corrupt).get("ok",true),"Every partial provenance bundle is rejected: "+type+"/"+key)


func _test_sync_groups() -> void:
	var mission: Dictionary = Catalog.load("M01")
	var initial := _state(mission)
	initial.units[1].commands = [initial.units[0].commands[-1].duplicate(true)]
	initial.units[1].commands[0].id = "second-ready"
	initial.units[1].commands[0].args.formation.order = 2
	var final := initial.duplicate(true)
	final.tick = 1
	final.time = STEP
	for unit: Dictionary in final.units:
		for command: Dictionary in unit.commands:
			if command.type=="WAIT_FOR_SIGNAL": command.args.signal = "C"; command.args.delay_ticks = 7
	var candidate := _record(mission,initial,final)
	var restored := Replay.new()
	check(restored.load_data(candidate).get("ok",false),"Coherent group revisions remain valid in their separate retained frames")
	check(restored.seek(0.0,true).units[1].commands[0].args.signal=="A" and restored.seek(STEP,true).units[1].commands[0].args.signal=="C","Atomic group edits do not rewrite previous revision")
	for mutation: String in ["signal","auto","delay","absent","kind","source","base"]:
		var corrupt: Dictionary = candidate.duplicate(true)
		for command: Dictionary in corrupt.commands:
			if command.id!="second-ready": continue
			match mutation:
				"signal": command.args.signal = "B"
				"auto": command.args.auto_signal = false
				"delay": command.args.delay_ticks = 10
				"absent": command.args.erase("formation")
				"kind": command.args.formation.kind = "ROLLING_T"
				"source": command.args.formation.source_unit_id = mission.units[0].id
				"base": command.args.formation.sync_id = "another"
		check(not restored.load_data(corrupt).get("ok",true),"Incoherent unfinished formation barrier rejects "+mutation)

func _test_legacy_and_boundaries() -> void:
	var mission: Dictionary = Catalog.load("M01")
	var initial := _state(mission)
	for unit: Dictionary in initial.units:
		for command: Dictionary in unit.commands:
			command.args.erase("formation")
			command.args.erase("stance")
			for key: String in ["sync_id","auto_signal","delay_ticks"]: command.args.erase(key)
	var final := initial.duplicate(true)
	final.tick = 1
	final.time = STEP
	final.events = [{"seq":1,"tick":1,"time":STEP,"type":"SIGNAL","channel":"A","released":1},{"seq":2,"tick":1,"time":STEP,"type":"CALL_MAN_DOWN","unit_id":mission.units[0].id,"observed":true}]
	var restored := Replay.new()
	check(restored.load_data(_record(mission,initial,final)).get("ok",false),"Legacy primitive/SIGNAL/CALL absence remains compatible without schema changes")
	check(not restored.seek(STEP,true).events[-1].has("source_unit_id"),"A legacy MAN_DOWN without a living witness does not fabricate delivery")
	for kind: String in Replay.FORMATION_KINDS:
		for stage: String in Replay.FORMATION_STAGES:
			initial = _state(mission)
			initial.units[0].commands[0].args.formation.kind = kind
			initial.units[0].commands[0].args.formation.stage = stage
			initial.units[0].commands[0].args.formation.order = 4.0
			initial.units[0].commands[0].args.formation.sync_id = "x".repeat(55)
			final = initial.duplicate(true)
			final.tick = 1
			final.time = STEP
			final.events = [_receipt(mission,"hand_signals")]
			final.events[0].receiver_unit_ids = []
			final.events[0].released = 0
			check(restored.load_data(_record(mission,initial,final)).get("ok",false),"Inclusive formation bounds and empty persisted receivers accepted: "+kind+"/"+stage)

func _fixture(seed_value: int, hand: bool = false) -> Dictionary:
	var units: Array = []
	for id: String in ["alpha","bravo","charlie","delta"]:
		units.append({"id":id,"name":id.to_upper(),"role":"Assault","weapon":"standard","x":8.0,"z":12.0+ORDER.find(id)*0.7,"facing":-1.57})
	var mission: Dictionary = _json({"schema_version":5,"id":"FORMATION_REPLAY","revision":1,"custom":true,"title":"Formation replay fixture","seed":seed_value,"variant":"normal","bounds":[20,20],"focus":[8,10],"noise_discipline":"hand_signals" if hand else "verbal","rooms":[{"id":"corridor","x":8.0,"z":10.0,"w":3.2,"d":16.0},{"id":"hidden","x":17.0,"z":4.0,"w":3.0,"d":3.0}],"walls":[{"id":"west","x":6.3,"z":10.0,"w":0.2,"d":16.0},{"id":"east_top","x":9.7,"z":5.65,"w":0.2,"d":7.3},{"id":"east_bottom","x":9.7,"z":14.35,"w":0.2,"d":7.3},{"id":"north","x":8.0,"z":2.0,"w":3.2,"d":0.2},{"id":"south","x":8.0,"z":18.0,"w":3.2,"d":0.2},{"id":"hiddenwest","x":15.4,"z":4.0,"w":0.2,"d":3.4},{"id":"hiddeneast","x":18.6,"z":4.0,"w":0.2,"d":3.4},{"id":"hiddennorth","x":17.0,"z":2.4,"w":3.4,"d":0.2},{"id":"hiddensouthleft","x":15.8,"z":5.6,"w":1.0,"d":0.2},{"id":"hiddensouthright","x":18.2,"z":5.6,"w":1.0,"d":0.2}],"doors":[{"id":"side_door","x":9.7,"z":10.0,"w":0.24,"d":1.4,"axis":"z","state":"CLOSED","locked":false},{"id":"hidden_door","x":17.0,"z":5.6,"w":1.4,"d":0.24,"axis":"x","state":"CLOSED","locked":false}],"props":[],"units":units,"enemies":[{"id":"hidden_enemy","x":17.0,"z":3.8,"facing":0.0,"ammo":0,"training":true,"passive":true}],"civilians":[{"id":"hidden_civilian","x":17.4,"z":4.4}],"objectives":["Traverse corridor"],"win":[{"type":"reach_zone","zone":[19.0,19.0,0.2,0.2]}],"fail":[],"stars":[]})

	if _kind(seed_value)=="T_JUNCTION":
		mission.bounds = [20.0,24.0]
		mission.rooms[0] = {"id":"stem","x":8.0,"z":15.1,"w":2.4,"d":13.8}
		mission.rooms.append({"id":"branches","x":8.0,"z":7.0,"w":12.0,"d":2.4})
		mission.walls = mission.walls.filter(func(wall: Dictionary) -> bool: return str(wall.id).begins_with("hidden"))
		mission.walls.append_array([
			{"id":"forward","x":8.0,"z":5.7,"w":12.0,"d":0.2},
			{"id":"west_end","x":1.9,"z":7.0,"w":0.2,"d":2.6},
			{"id":"east_end_top","x":14.1,"z":6.0,"w":0.2,"d":0.6},{"id":"east_end_bottom","x":14.1,"z":8.0,"w":0.2,"d":0.6},
			{"id":"west_bottom","x":4.4,"z":8.3,"w":4.8,"d":0.2},{"id":"east_bottom","x":11.6,"z":8.3,"w":4.8,"d":0.2},
			{"id":"stem_west","x":6.7,"z":15.1,"w":0.2,"d":13.8},{"id":"stem_east","x":9.3,"z":15.1,"w":0.2,"d":13.8},
			{"id":"south","x":8.0,"z":22.0,"w":2.4,"d":0.2}])
		mission.doors[0].x = 14.1
		mission.doors[0].z = 7.0
	return mission

func _kind(seed_value: int) -> String: return ["SERPENTINE","ROLLING_T","T_JUNCTION"][seed_value%3]
func _target(seed_value: int) -> Array: return [8.0,7.0] if _kind(seed_value)=="T_JUNCTION" else [8.0,5.0]

func _project_like(value: Variant, shape: Variant) -> Variant:
	if shape is Dictionary:
		if not value is Dictionary: return null
		var result: Dictionary = {}
		for key: Variant in shape:
			if not value.has(key): return null
			result[key] = _project_like(value[key],shape[key])
		return result
	if shape is Array:
		if not value is Array or value.size()!=shape.size(): return null
		var result: Array = []
		for index: int in range(shape.size()): result.append(_project_like(value[index],shape[index]))
		return result
	return value

func _same_snapshot(decoded: Dictionary, actual: Dictionary) -> bool:
	return JSON.stringify(_json(_project_like(decoded,actual)),"",true)==JSON.stringify(_json(actual),"",true)

func _rng_states(sim: RefCounted) -> Array:
	# Read each independent stream without drawing or serializing 64-bit states.
	return [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]

func _simulate(mission: Dictionary, kind: String, retain: bool) -> Dictionary:
	var sim := Simulation.new()
	sim.load_mission(mission)
	var planned := sim.plan_formation(_target(int(mission.seed)),kind,ORDER,{"delay_ticks":3})
	check(planned.get("ok",false),"Actual formation expands to primitives: "+str(planned.get("message","")))
	if not planned.get("ok",false): return {}
	var recorder := Replay.new()
	recorder.begin(mission)
	var initial := sim.snapshot(true)
	recorder.capture(initial,sim.take_record_events())
	var snapshots: Array = [initial] if retain else []
	var rng_states: Array = [_rng_states(sim)]
	for tick: int in range(TICKS):
		sim.step(STEP)
		var full := sim.snapshot(true)
		recorder.capture(full,sim.take_record_events())
		if retain: snapshots.append(full)
		rng_states.append(_rng_states(sim))
	var final := sim.snapshot(true)
	recorder.finish(final)
	return {"data":_json(recorder.export_data()),"snapshots":snapshots,"final":final,"planned":planned,"rng_states":rng_states}

func _test_runtime(seed_value: int) -> void:
	var mission := _fixture(seed_value,seed_value%2==0)
	var validation := Catalog.validate_custom(mission)
	check(validation.get("ok",false),"Actual formation fixture schema accepted: "+str(validation.get("message","")))
	if not validation.get("ok",false): return
	var run := _simulate(mission,_kind(seed_value),true)
	if run.is_empty(): return
	var repeat := _simulate(mission,_kind(seed_value),false)
	if repeat.is_empty(): return
	check(run.rng_states==repeat.rng_states,"Every fixed tick repeats all four independent RNG states exactly")
	check(JSON.stringify(run.data)==JSON.stringify(repeat.data) and _same_snapshot(repeat.final,run.final),"Seed%d repeated formation produces byte-identical replay/full final state" % seed_value)
	check(run.final.units.all(func(unit: Dictionary) -> bool: return unit.commands.all(func(command: Dictionary) -> bool: return command.state=="SUCCEEDED")),"Every expanded formation primitive actually finishes, seed%d" % seed_value)
	if _kind(seed_value)=="T_JUNCTION":
		for index: int in range(ORDER.size()):
			var unit: Dictionary = run.final.units.filter(func(value: Dictionary) -> bool: return value.id==ORDER[index])[0]
			var expected := "crouched" if index in [0,2] else "standing"
			check(unit.stance==expected,"Actual T rank%d executes its planned low/high stance" % (index+1))
			var readiness: Array = unit.commands.filter(func(command: Dictionary) -> bool: return command.type=="FACE" and command.args.formation.stage=="ready")
			check(readiness.size()==1 and readiness[0].args.stance==expected and readiness[0].state=="SUCCEEDED","Actual T ready FACE retains its stance in primitive replay")
	check(run.data.commands.all(func(command: Dictionary) -> bool: return command.type in ["MOVE","FACE","WAIT_FOR_SIGNAL"]),"Formation save contains only existing primitive commands")
	var restored := Replay.new()
	var loaded := restored.load_data(run.data)
	check(loaded.get("ok",false),"Actual formation record loads: "+str(loaded.get("message","")))
	if not loaded.get("ok",false): return
	for frame: Array in run.data.frames:
		check(_same_snapshot(restored.seek(float(frame[0]),true),run.snapshots[int(frame[1])]),"Every retained formation snapshot restores all authoritative fields, seed%d/tick%d" % [seed_value,int(frame[1])])
	for rate: int in [1,4]:
		var gathered: Array = []
		var seq := 0
		for tick: int in range(rate,TICKS+1,rate):
			var shown := restored.seek(tick*STEP,false)
			var events := restored.events_since(seq,tick*STEP,false)
			gathered.append_array(events)
			if not events.is_empty(): seq = int(events[-1].seq)
			check(shown.enemies.is_empty() and shown.civilians.is_empty(),"Formation replay%dx retains hidden-NPC privacy" % rate)
			check(shown.room_states==_json(run.snapshots[tick].room_states_observed),"Formation replay%dx retains last-known room clocks" % rate)
		check(gathered==run.data.events,"Formation replay%dx delivers persisted receipts/events once" % rate)
	var signals: Array = run.data.events.filter(func(event: Dictionary) -> bool: return event.type=="SIGNAL" and event.get("sync_id","")==run.planned.sync_id+":ready")
	check(signals.size()==1 and signals[0].released==4,"Actual formation uses one complete ready barrier")
	if not signals.is_empty():
		check(signals[0].source_unit_id==ORDER[-1] and signals[0].signal_mode==mission.noise_discipline,"The authored rear signal source and discipline survive recording")
		check(signals[0].receiver_unit_ids==["alpha","bravo","charlie","delta"],"Actual receipt preserves sorted own recipients")
		var tick := int(signals[0].tick)
		check(restored.seek(float(signals[0].time),true).tick==tick,"Signal releases at its exact authoritative tick")
		check(not restored.events_since(0,float(signals[0].time)-STEP*0.5).any(func(event: Dictionary) -> bool: return event==signals[0]),"Future delivery cannot appear before its occurrence")
	check(not JSON.stringify(run.data).contains("_formation_") and not JSON.stringify(run.data).contains("blocked_unit_ids"),"Private draft/delivery diagnostics are absent from saved state")

func _test_main_plans() -> void:
	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	await process_frame
	for seed_value: int in [0,17,28,29]:
		var mission := _fixture(seed_value,seed_value==0)
		check(not session._register_custom(mission).is_empty(),"Main accepts actual formation fixture")
		session._action({"action":"start","mission":"FORMATION_REPLAY","seed":seed_value})
		var planned: Dictionary = session.sim.plan_formation(_target(seed_value),_kind(seed_value),ORDER,{"delay_ticks":3})
		check(planned.get("ok",false),"Main creates a saveable expanded formation")
		if not planned.get("ok",false): continue
		var initial: Dictionary = session.sim.snapshot(true)
		var plan: Dictionary = session._export_plan()
		check(plan.schema_version==1 and plan.kind=="breach-plan","Formation preserves primitive plan schema1")
		var ticks: Array[String] = []
		var rng_ticks: Array = []
		for tick: int in range(TICKS):
			session.sim.step(STEP)
			ticks.append(JSON.stringify(session.sim.snapshot(true)))
			rng_ticks.append(_rng_states(session.sim))
		session._import_plan(_json(plan),false)
		var imported: Dictionary = session.sim.snapshot(true)
		# Existing plan1 stores the current primitive graph, not edit history;
		# the first STEP clears plan_revisions. All other initial fields and all
		# complete authoritative runtime ticks must match without tolerance.
		initial.erase("plan_revisions")
		imported.erase("plan_revisions")
		check(JSON.stringify(initial)==JSON.stringify(imported),"Mission-roster command IDs and complete formation arguments survive Main import")
		check(session._export_plan()==plan,"Main exports the identical expanded primitive plan after import")
		for tick: int in range(TICKS):
			session.sim.step(STEP)
			check(_rng_states(session.sim)==rng_ticks[tick],"Main imported formation preserves all four RNG states at every fixed tick")
			check(JSON.stringify(session.sim.snapshot(true))==ticks[tick],"Main imported formation preserves every full authoritative tick")
		var before := JSON.stringify(session.sim.snapshot(true))
		for mutation: String in ["source","kind","stage","stance"]:
			var invalid: Dictionary = plan.duplicate(true)
			var changed := false
			for unit: Dictionary in invalid.units:
				for command: Dictionary in unit.commands:
					if changed: break
					match mutation:
						"source": command.args.formation.source_unit_id = "hidden_enemy"; changed = true
						"kind": command.args.formation.kind = "AUTO"; changed = true
						"stage":
							if command.type=="WAIT_FOR_SIGNAL": command.args.formation.stage = "move"; changed = true
						"stance":
							if command.type=="FACE": command.args.stance = "prone"; changed = true
			check(changed,"Invalid formation plan reaches intended metadata: "+mutation)
			session._import_plan(invalid,false)
			check(JSON.stringify(session.sim.snapshot(true))==before,"Invalid formation plan leaves active Main state unchanged: "+mutation)
	session.queue_free()
	await process_frame
