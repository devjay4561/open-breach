extends SceneTree
## The browser FX fixture is an exact T01 clone with a schema-4 AND goal.
## Real commands and fixed STEP, rather than a render delay or synthetic death,
## prove that every room can finish its required stationary cursory search.
const Simulation = preload("res://scripts/simulation.gd")
const Schema = preload("res://scripts/mission_schema.gd")
const Replay = preload("res://scripts/replay.gd")
const RoomDrill = preload("res://scripts/room_drill.gd")
const STEP := 1.0 / 30.0
const ROOM_IDS := ["t_ready", "t_breach", "t_signal"]
const WAIT_SECONDS := 4.0
var checks := 0
var failures: Array[String] = []
var report: Dictionary = {"step":STEP,"seed":42,"fx":{}}
const ORDER := ["alpha","bravo","charlie","delta"]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fx_fixture() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json"))
	data = data.duplicate(true)
	data.id = "FX_DOCTRINE_P3"
	data.schema_version = 4
	# Preserve both original win rules, even the empty-civilian condition.
	# A WAIT alone would not prevent neutralize_all ending T01 at the last kill.
	data.win.append({"type":"rooms_cleared","room_ids":ROOM_IDS.duplicate()})
	return data

func fx_commands() -> Array:
	return [
		{"type":"MOVE","args":{"target":[6,10]}},
		{"type":"FACE","args":{"target":[6.4,7.5]}},
		{"type":"WAIT","args":{"duration":WAIT_SECONDS}},
		{"type":"KICK_DOOR","args":{"door_id":"d1"}},
		{"type":"MOVE","args":{"target":[12,10]}},
		{"type":"FACE","args":{"target":[12,8]}},
		{"type":"WAIT","args":{"duration":WAIT_SECONDS}},
		{"type":"OPEN_DOOR","args":{"door_id":"d2"}},
		{"type":"MOVE","args":{"target":[18,10]}},
		{"type":"FACE","args":{"target":[18.4,7.7]}},
		{"type":"WAIT","args":{"duration":WAIT_SECONDS}},
	]

func run() -> void:
	_fx_contract()
	_reload_contract()
	_short_contract()
	_man_down_contract()
	var directory := ProjectSettings.globalize_path("res://../tests/artifacts/room-control-browser")
	check(DirAccess.make_dir_recursive_absolute(directory) == OK,"Native preflight evidence directory is writable")
	var artifact := FileAccess.open(directory.path_join("preflight.json"),FileAccess.WRITE)
	check(artifact != null,"Native preflight evidence can be written")
	report["checks"] = checks
	report["failures"] = failures.duplicate()
	report["status"] = "PASS" if failures.is_empty() else "FAIL"
	if artifact != null: artifact.store_string(JSON.stringify(report,"\t")+"\n")
	print("BREACH_ROOM_CONTROL_BROWSER_PREFLIGHT_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _fx_contract() -> void:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json"))
	var data := fx_fixture()
	var restored := data.duplicate(true)
	restored.id = original.id
	restored.schema_version = original.schema_version
	restored.win.pop_back()
	check(restored == original,"FX doctrine fixture preserves every original T01 field except ID, schema and appended AND goal")
	check(bool(Schema.check(data).get("ok",false)),"Exact T01 schema-4 fixture passes mission authoring validation")
	check(data.seed == 42 and data.win.size() == original.win.size()+1,"FX fixture keeps seed 42 and all original win rules")
	var sim := Simulation.new()
	sim.load_mission(data)
	var commands := fx_commands()
	for command: Dictionary in commands:
		var answer: Dictionary = sim.issue("alpha",command.type,command.args,true)
		check(bool(answer.get("ok",false)),"FX primitive %s is accepted: %s" % [command.type,answer.get("message","")])
	var traces: Array = []
	var last_death: Dictionary = {}
	var clear_calls: Dictionary = {}
	var seen_events: Dictionary = {}
	var marked := false
	for _frame: int in range(2400):
		sim.step(STEP)
		var alpha: Dictionary = sim.units[0]
		traces.append({"tick":sim.tick,"position":[alpha.x,alpha.z],"hp":alpha.hp,"stunned":alpha.stunned,"reload_remaining":alpha.get("reload_remaining",0.0),"room_states":sim.room_control.snapshot(true),"search":sim.room_control._search.duplicate(true)})
		for enemy: Dictionary in sim.enemies:
			if float(enemy.hp) <= 0.0 and not last_death.has(str(enemy.id)): last_death[str(enemy.id)] = sim.tick
		for event: Dictionary in sim.events:
			var event_id := str(event.get("seq",-1))
			if seen_events.has(event_id): continue
			seen_events[event_id] = true
			if event.type == "CALL_ROOM_CLEAR":
				var room_id := str(event.get("room_id",""))
				check(not clear_calls.has(room_id),"FX room %s produces one authoritative ROOM CLEAR call" % room_id)
				clear_calls[room_id] = event.duplicate(true)
		for room_id: String in ROOM_IDS:
			marked = marked or str(sim.room_states.get(room_id,{}).get("state","")) == "MARKED"
		if not sim.result.is_empty(): break
	check(bool(sim.result.get("success",false)),"Exact fixed-STEP FX fixture completes all original goals and three room searches")
	check(sim.command_failures == 0,"FX fixture completes without failed primitive commands")
	check(clear_calls.size() == 3,"FX fixture publishes exactly three real CALL_ROOM_CLEAR events")
	check(marked,"Moving through the original doors marks an actually searched room")
	for index: int in range(ROOM_IDS.size()):
		var room_id: String = ROOM_IDS[index]
		check(str(sim.room_states.get(room_id,{}).get("state","")) in ["CLEAR","MARKED"],"Final authoritative %s is currently CLEAR or MARKED" % room_id)
		var event: Dictionary = clear_calls.get(room_id,{})
		check(bool(event.get("observed",false)) and event.get("unit_id","") == "alpha","%s clear call belongs to the real observed searching operator" % room_id)
		var clear_tick := int(event.get("tick",-1))
		var enemy_id := str(data.enemies[index].id)
		check(clear_tick-int(last_death.get(enemy_id,clear_tick)) >= 45,"%s cannot clear at neutralization; it searches for at least 45 fixed STEP ticks" % room_id)
		var tail: Array = traces.filter(func(trace: Dictionary) -> bool: return int(trace.tick)>clear_tick-45 and int(trace.tick)<=clear_tick)
		check(tail.size() == 45,"%s has a full 45-tick search evidence interval" % room_id)
		if tail.size() == 45:
			var position: Array = tail[0].position
			check(tail.all(func(trace: Dictionary) -> bool: return trace.position==position and float(trace.hp)==float(tail[0].hp) and float(trace.stunned)<=0.0 and float(trace.reload_remaining)<=0.0),"%s real search stays stationary, unharmed, unstunned and outside reload for all 45 ticks" % room_id)
			check(absf(float(tail[43].search.get(room_id,{}).get("elapsed",0.0))-44.0*STEP)<0.000001 and str(tail[43].room_states[room_id].state)=="DOMINATED","%s remains DOMINATED after exactly 44 actual eligible search STEP" % room_id)
			check(absf(float(tail[44].search.get(room_id,{}).get("elapsed",0.0))-45.0*STEP)<0.000001 and str(tail[44].room_states[room_id].state)=="CLEAR","%s publishes CLEAR on exactly its 45th actual eligible search STEP" % room_id)
	check(int(sim.result.get("rear_hits",-1)) == 0,"Passive target tutorial records zero real rear hits")
	check(sim.units[0].commands.filter(func(command: Dictionary) -> bool: return command.type in ["MOVE","FACE","KICK_DOOR","OPEN_DOOR"]).all(func(command: Dictionary) -> bool: return command.state=="SUCCEEDED"),"Every original route and door primitive succeeds before the doctrine result")
	report.fx = {"mission":data,"commands":commands,"result":sim.result.duplicate(true),"clear_calls":clear_calls,"death_ticks":last_death,"ticks":sim.tick,"traces":traces}

func base_fixture(id: String) -> Dictionary:
	return {"schema_version":4,"id":id,"revision":1,"title":"방 통제 검증","title_en":"Room Control Check","seed":42,"bounds":[12,12],"focus":[6,6],
		"rooms":[{"id":"room","label":"SEARCH","x":5.0,"z":5.0,"w":6.0,"d":6.0,"indoor":true,"lighting":1.0}],"walls":[],"props":[],"doors":[],
		"units":[{"id":"alpha","name":"ALPHA","role":"TEST","x":5.0,"z":5.0,"facing":0.0,"weapon":"standard","ammo":0,"reserve_ammo":24,"armor":"none","helmet":"none"},
			{"id":"bravo","name":"BRAVO","role":"TEST","x":4.0,"z":5.0,"facing":1.0,"weapon":"standard","ammo":24,"reserve_ammo":24,"armor":"none","helmet":"none"}],
		"enemies":[],"civilians":[],"objectives":["방 수색을 마치세요."],
		# The existing stationary inspection goal keeps this separate UI fixture
		# executing after CLEAR so the actual live CALL log can be observed.
		"interactive_targets":[{"id":"finish","x":5.0,"z":5.0,"w":0.25,"d":0.25,"label":"COMPLETE","action":"inspect","duration":5.0}],
		"win":[{"type":"rooms_cleared","room_ids":["room"]},{"type":"targets_complete","targets":["finish"]}],"fail":[]}

func _reload_contract() -> void:
	var data := base_fixture("ROOM_CONTROL_RELOAD_UI")
	var validation := Schema.check(data)
	check(bool(validation.get("ok",false)),"Actual reload browser fixture passes schema 4: "+str(validation))
	var commands := [{"unit_id":"alpha","type":"FACE","args":{"target":[7.0,5.0],"persistent":true,"sector":{"start":-0.5,"end":0.5,"duration":20.0}}},
		{"unit_id":"bravo","type":"FACE","args":{"target":[4.0,7.0],"persistent":true,"sector":{"start":1.0,"end":2.0,"duration":20.0}}},
		{"unit_id":"alpha","type":"RELOAD","args":{}}]
	var sim := Simulation.new()
	sim.load_mission(data)
	for command: Dictionary in commands:
		check(bool(sim.issue(command.unit_id,command.type,command.args,true).get("ok",false)),"Reload browser primitive %s %s is accepted" % [command.unit_id,command.type])
	var recorder := Replay.new()
	recorder.begin(data)
	recorder.capture(sim.snapshot(true))
	var calls: Array = []
	var previous_cover: Dictionary = {}
	var lease_seen := false
	var restored := false
	var seen: Dictionary = {}
	for _frame: int in range(240):
		sim.step(STEP)
		recorder.capture(sim.snapshot(true))
		if sim.tick==1:
			var bravo: Dictionary = sim.units[1]
			previous_cover = {"facing":bravo.facing,"sector":bravo.sector.duplicate(true),"commands":bravo.commands.duplicate(true),"ammo":bravo.ammo,"reserve_ammo":bravo.reserve_ammo}
		if sim._reload_covers.has("alpha"):
			lease_seen = true
			check(sim._reload_covers.alpha.cover_unit_id=="bravo","Browser reload borrows the actual nearest ally")
		if lease_seen and not sim._reload_covers.has("alpha") and not restored:
			var bravo: Dictionary = sim.units[1]
			restored = bravo.facing==previous_cover.facing and bravo.sector==previous_cover.sector and bravo.commands==previous_cover.commands and bravo.ammo==previous_cover.ammo and bravo.reserve_ammo==previous_cover.reserve_ammo
		for event: Dictionary in sim.events:
			if seen.has(event.seq): continue
			seen[event.seq] = true
			if str(event.type).begins_with("CALL_"): calls.append(event.duplicate(true))
		if not sim.result.is_empty(): break
	check(lease_seen and restored,"Actual browser reload returns the borrowed FACE/sector without mutating queue or ammunition")
	var reload_calls: Array = calls.filter(func(event: Dictionary) -> bool: return event.type in ["CALL_RELOADING","CALL_GUN_UP"])
	check(reload_calls.size()==2 and reload_calls[0].type=="CALL_RELOADING" and reload_calls[1].type=="CALL_GUN_UP","Real reload browser commands publish RELOADING then GUN_UP")
	check(reload_calls.all(func(event: Dictionary) -> bool: return bool(event.get("observed",false)) and event.get("cover_unit_id","")=="bravo"),"Both actual reload calls identify the observed coverer")
	check(bool(sim.result.get("success",false)) and int(sim.units[0].ammo)==24,"Reload browser fixture finishes ammunition transfer and a subsequent real room search")
	check(calls.any(func(event: Dictionary) -> bool: return event.type=="CALL_ROOM_CLEAR" and int(event.tick)<sim.tick-3),"Actual reload ROOM CLEAR has a live native observation interval before RESULT")
	report["reload"] = {"mission":data,"commands":commands,"calls":calls,"ticks":sim.tick,"result":sim.result.duplicate(true),"previous_cover":previous_cover,"final_units":sim.snapshot(false).units,"final_events":sim.events.duplicate(true)}
	recorder.finish(sim.snapshot(true))
	# Exercise an actual schema-1/numeric-state-v1 recording through the real
	# decoder after omitting optional doctrine fields, as older files do.
	# Numeric frame/actor/command arrays and all original result values survive.
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(recorder.data))
	for metadata: Dictionary in legacy.metadata:
		for key: String in ["rear_hits","room_states","room_states_observed","pause_reason","pause_unit_id"]: metadata.erase(key)
		if metadata.get("result") is Dictionary:
			for key: String in ["rear_hits","room_states","room_states_observed"]: metadata.result.erase(key)
	legacy.events = legacy.events.filter(func(event: Dictionary) -> bool: return not str(event.type).begins_with("CALL_"))
	var restored_replay := Replay.new()
	var answer: Dictionary = restored_replay.load_data(legacy)
	check(bool(answer.get("ok",false)),"Schema-1 numeric recording with omitted optional P3 fields loads through the real native decoder: "+str(answer))
	if bool(answer.get("ok",false)):
		var final := restored_replay.seek(float(legacy.duration),false)
		check(bool(final.result.get("success",false)) and not final.result.has("rear_hits") and int(final.result.get("rear_hits",0))==0,"Legacy RESULT keeps its actual success and means zero rear hits when the new counter is absent")
		check(final.room_states.is_empty() and not final.has("room_states_observed"),"A legacy replay does not invent observed room control")
	report["legacy_replay"] = legacy

func short_fixture() -> Dictionary:
	var data := base_fixture("ROOM_CONTROL_SHORT_UI")
	data.bounds = [18,14]
	data.focus = [9,7]
	data.rooms = [{"id":"ready","label":"READY","x":4.0,"z":6.0,"w":6.0,"d":10.0,"indoor":true,"lighting":1.0},
		{"id":"target","label":"SHORT","x":8.2,"z":6.0,"w":2.4,"d":3.6,"indoor":true,"lighting":1.0},
		{"id":"private","label":"PRIVATE","x":13.2,"z":6.0,"w":7.6,"d":5.0,"indoor":true,"lighting":1.0}]
	var raw_walls := [["ready_n",4,1,6,0.24],["ready_s",4,11,6,0.24],["ready_w",1,6,0.24,10],
		["entry_n",7,3.05,0.24,4.1],["entry_s",7,8.95,0.24,4.1],["short_n",8.2,4.2,2.4,0.24],["short_s",8.2,7.8,2.4,0.24],
		["private_a",9.4,4.45,0.24,1.9],["private_b",9.4,7.55,0.24,1.9],["private_n",13.2,3.5,7.6,0.24],["private_s",13.2,8.5,7.6,0.24],["private_e",17,6,0.24,5]]
	data.walls = []
	for row: Array in raw_walls: data.walls.append({"id":row[0],"x":row[1],"z":row[2],"w":row[3],"d":row[4],"material":"concrete","height":2.8})
	data.doors = [{"id":"entry","x":7.0,"z":6.0,"w":0.24,"d":1.8,"axis":"z","state":"CLOSED","material":"wood","height":2.1,"hp":100,"locked":false,"hinge_side":-1.0,"swing_sign":-1.0},
		{"id":"private_door","x":9.4,"z":6.0,"w":0.24,"d":1.2,"axis":"z","state":"CLOSED","material":"wood","height":2.1,"hp":100,"locked":false,"hinge_side":-1.0,"swing_sign":-1.0}]
	data.units = []
	for index: int in range(4): data.units.append({"id":ORDER[index],"name":str(ORDER[index]).to_upper(),"role":"TEST","x":5.4-float(index%2)*0.7,"z":5.2 if index<2 else 6.8,"facing":0.0,"weapon":"standard","ammo":24,"reserve_ammo":0,"armor":"none","helmet":"none"})
	data.enemies = [{"id":"unseen","name":"UNSEEN","x":15.0,"z":6.0,"facing":PI,"weapon":"standard","ammo":24,"hp":100,"enemy_type":"sentry","passive":true}]
	data.interactive_targets = [{"id":"finish","x":7.8,"z":6.9,"w":0.25,"d":0.25,"label":"COMPLETE","action":"inspect","duration":5.0}]
	data.win = [{"type":"rooms_cleared","room_ids":["target"]},{"type":"targets_complete","targets":["finish"]}]
	return data

func _short_contract() -> void:
	var data := short_fixture()
	var validation := Schema.check(data)
	check(bool(validation.get("ok",false)),"SHORT and sealed-room browser fixture passes schema 4: "+str(validation))
	var sim := Simulation.new()
	sim.load_mission(data)
	var preview: Dictionary = sim.room_entry_preview("entry","OPEN_DOOR",ORDER,{})
	check(bool(preview.get("ok",false)) and bool(preview.get("short_room",false)),"Actual browser SHORT preview has two entrants and outside guards")
	var plan: Dictionary = sim.plan_room_entry("entry","OPEN_DOOR",ORDER,{})
	check(bool(plan.get("ok",false)),"SHORT browser plan expands into accepted existing primitives")
	var initial_commands: Array = sim.snapshot(false).units.map(func(unit: Dictionary) -> Dictionary: return {"id":unit.id,"commands":unit.commands.map(func(command: Dictionary) -> Dictionary: return {"type":command.type,"args":command.args.duplicate(true)})})
	for _frame: int in range(1200):
		sim.step(STEP)
		if not sim.result.is_empty(): break
	check(bool(sim.result.get("success",false)) and sim.command_failures==0,"Two actual SHORT entrants finish the room search without failed primitives")
	var calls: Array = sim.events.filter(func(event: Dictionary) -> bool: return str(event.type).begins_with("CALL_"))
	check(calls.filter(func(event: Dictionary) -> bool: return event.type=="CALL_SHORT_ROOM").size()==1,"Actual entry barrier publishes one observed SHORT ROOM call")
	check(calls.filter(func(event: Dictionary) -> bool: return event.type=="CALL_ROOM_CLEAR" and event.room_id=="target").size()==1,"SHORT room publishes its actual stationary search completion")
	check(calls.any(func(event: Dictionary) -> bool: return event.type=="CALL_ROOM_CLEAR" and event.room_id=="target" and int(event.tick)<sim.tick-3),"Actual SHORT ROOM CLEAR has a live native observation interval before RESULT")
	var observed := sim.snapshot(false)
	check(observed.enemies.is_empty() and not bool(observed.room_states.private.observed) and observed.room_states.private.state=="UNKNOWN","Hidden hostile and unobserved sealed room stay private after real SHORT execution")
	check(not observed.has("room_states_observed") and not observed.result.has("room_states_observed"),"Public native and RESULT room projections erase authority-side memory containers")
	report["short"] = {"mission":data,"preview":preview,"initial_commands":initial_commands,"calls":calls,"ticks":sim.tick,"result":observed.result,"final_units":observed.units,"final_events":sim.events.duplicate(true)}

func man_down_fixture() -> Dictionary:
	# Same actual seed-0 contact as the audited 30-seed simulation suite.
	# Authored wounded point HP and empty magazines deliberately permit real
	# enemy aim/LOS/accuracy/damage; no actor, hit or death state is injected.
	var data := base_fixture("ROOM_CONTROL_MAN_DOWN_UI")
	data.seed = 0
	data.bounds = [16,16]
	data.focus = [8,8]
	data.rooms = [{"id":"room","label":"CONTACT","x":8.0,"z":8.0,"w":5.0,"d":5.0,"indoor":true,"lighting":1.0}]
	var rows := [["west",5.5,8,0.2,5],["east",10.5,8,0.2,5],["north",8,5.5,5,0.2],["south_a",6.25,10.5,1.5,0.2],["south_b",9.75,10.5,1.5,0.2]]
	data.walls = []
	for row: Array in rows: data.walls.append({"id":row[0],"x":row[1],"z":row[2],"w":row[3],"d":row[4]})
	data.doors = [{"id":"door","x":8.0,"z":10.5,"axis":"x","w":1.8,"d":0.2,"state":"CLOSED","hinge_side":-1.0,"swing_sign":1.0}]
	var positions := [[9.3,10.95],[6.7,10.95],[9.3,11.65],[6.7,11.65]]
	data.units = []
	for index: int in range(4):
		var origin := Vector2(float(positions[index][0]),float(positions[index][1]))
		data.units.append({"id":ORDER[index],"name":str(ORDER[index]).to_upper(),"role":"TEST","x":origin.x,"z":origin.y,"facing":(Vector2(8.0,10.5)-origin).angle(),"weapon":"standard","hp":30.0 if index==0 else 100.0,"armor":"none","helmet":"none","ammo":0,"reserve_ammo":72})
	data.enemies = [{"id":"shooter","name":"CONTACT","x":9.5,"z":6.4,"facing":PI*0.5,"weapon":"standard","response_role":"guard"}]
	data.win = [{"type":"reach_zone","zone":[15.0,15.0,0.1,0.1]}]
	data.erase("interactive_targets")
	return data

func _man_down_contract() -> void:
	var data := man_down_fixture()
	var validation := Schema.check(data)
	check(bool(validation.get("ok",false)),"Actual MAN DOWN browser fixture passes schema 4: "+str(validation))
	var variants: Dictionary = {}
	for pause: bool in [false,true]:
		var sim := Simulation.new()
		sim.load_mission(data)
		check(bool(sim.configure_team_settings({"auto_pause_man_down":pause}).get("ok",false)),"Actual MAN DOWN accepts the requested boolean pause setting")
		var plan: Dictionary = sim.plan_room_entry("door","OPEN_DOOR",ORDER,{})
		check(bool(plan.get("ok",false)),"MAN DOWN fixture expands its original real four-person entry")
		var initial: Array = sim.snapshot(false).units.map(func(unit: Dictionary) -> Dictionary: return {"id":unit.id,"commands":unit.commands.map(func(command: Dictionary) -> Dictionary: return {"type":command.type,"args":command.args.duplicate(true)})})
		for _frame: int in range(900):
			sim.step(STEP)
			if sim.units.any(func(unit: Dictionary) -> bool: return float(unit.hp)<=0.0): break
		var death := sim.snapshot(false)
		var dead: Array = sim.units.filter(func(unit: Dictionary) -> bool: return float(unit.hp)<=0.0)
		check(dead.size()==1 and dead[0].id=="alpha","Real seed-0 shooter downs only the authored wounded point operator")
		var calls: Array = sim.events.filter(func(event: Dictionary) -> bool: return event.type=="CALL_MAN_DOWN")
		check(calls.size()==1 and calls[0].unit_id=="alpha" and bool(calls[0].get("observed",false)),"Actual casualty publishes one observed MAN DOWN call")
		check(sim.hits_taken>0 and int(sim.enemies[0].ammo)<int(sim.enemies[0].max_ammo),"MAN DOWN is caused by actual hostile shots and damage")
		check(sim.pause_requested==pause and sim.pause_reason==("man_down" if pause else ""),"Boolean setting controls only the real native MAN DOWN pause request")
		var contract: Dictionary = sim._room_registered.values()[0]
		var survivors: Array = sim.units.filter(func(unit: Dictionary) -> bool: return float(unit.hp)>0.0).map(func(unit: Dictionary) -> String: return str(unit.id))
		check(contract.targets.size()==3 and survivors.size()==3 and not contract.targets.has("alpha"),"Same casualty STEP atomically replaces four entry goals with exactly three surviving owners")
		var positions: Dictionary = {}
		for unit: Dictionary in sim.units: positions[str(unit.id)] = [unit.x,unit.z]
		var preview: Dictionary = RoomDrill.recalculate_three(sim._drill_geometry("door"),sim._room_drill_layouts[contract.sync_id],survivors,positions,{})
		check(bool(preview.get("ok",false)) and preview.targets.size()==3,"Actual casualty positions produce a valid three-person static remap preview")
		for target: Dictionary in preview.get("targets",[]):
			check(target.target==contract.targets[target.unit_id],"Three-person preview %s agrees exactly with the committed real goal" % str(target.unit_id))
			var unit: Dictionary = sim._find(sim.units,str(target.unit_id))
			# New primitive args use the same 15-significant-digit JSON canonical
			# boundary as plan files. Vector2-backed preview values can differ by
			# an internal f64 ulp; compare the exact browser/plan array values.
			var canonical_target: Array = JSON.parse_string(JSON.stringify(target.target))
			check(unit.commands.any(func(command: Dictionary) -> bool: return command.type=="MOVE" and command.state=="PENDING" and command.args.get("drill",{}).get("stage","")=="domination" and command.args.target==canonical_target and int(command.args.drill.order)==int(target.order)),"Actual remap %s owns its pending rank/goal primitive" % str(target.unit_id))
		var door_count: int = sim.units.reduce(func(count: int, unit: Dictionary) -> int: return count+unit.commands.filter(func(command: Dictionary) -> bool: return command.type=="OPEN_DOOR").size(),0)
		for id: String in survivors: check(bool(sim.issue(id,"RELOAD",{},true).get("ok",false)),"Surviving %s accepts actual ammunition recovery" % id)
		var arrived: Dictionary = {}
		for _frame: int in range(360):
			sim.step(STEP)
			for id: String in survivors:
				var unit: Dictionary = sim._find(sim.units,id)
				if float(unit.hp)>0.0 and not arrived.has(id) and Vector2(float(unit.x),float(unit.z)).distance_to(Vector2(float(contract.targets[id][0]),float(contract.targets[id][1])))<=0.1: arrived[id] = sim.tick
			var complete := arrived.size()==3
			for id: String in survivors:
				complete = complete and sim._find(sim.units,id).commands.filter(func(command: Dictionary) -> bool: return command.type=="MOVE" and command.args.get("drill",{}).get("stage","")=="domination" and command.state!="CANCELLED").all(func(command: Dictionary) -> bool: return command.state=="SUCCEEDED")
			if complete: break
		check(arrived.size()==3 and sim.units.filter(func(unit: Dictionary) -> bool: return float(unit.hp)>0.0).size()==3,"All three actual survivors physically finish their recalculated goals")
		check(survivors.all(func(id: String) -> bool: return sim._find(sim.units,id).commands.filter(func(command: Dictionary) -> bool: return command.type=="MOVE" and command.args.get("drill",{}).get("stage","")=="domination" and command.state!="CANCELLED").all(func(command: Dictionary) -> bool: return command.state=="SUCCEEDED")),"All three real remap MOVE primitives reach SUCCEEDED, beyond merely entering the goal tolerance")
		check(sim.units.reduce(func(count: int, unit: Dictionary) -> int: return count+unit.commands.filter(func(command: Dictionary) -> bool: return command.type=="OPEN_DOOR").size(),0)==door_count and door_count==1,"Actual remap never queues or consumes a second door action")
		variants[str(pause)] = {"pause":pause,"mission":data,"initial_commands":initial,"death":death,"call":calls[0] if calls.size()==1 else {},"preview":preview,"targets":contract.targets,"survivors":survivors,"arrived":arrived,"final":sim.snapshot(false)}
	check(variants["false"].death.tick==variants["true"].death.tick and variants["false"].death.units==variants["true"].death.units,"Pause preference leaves actual casualty timing, RNG outcome and atomic remap identical")
	report["man_down"] = variants
