extends SceneTree
## P3 controller/presentation contracts. Casualties and search below use real
## fixed-step simulation; only the outgoing browser transport is replaced.
const MainScene = preload("res://main.tscn")
const Presentation = preload("res://scripts/presentation_state.gd")
const STEP := 1.0 / 30.0
const ORDER: Array[String] = ["alpha", "bravo", "charlie", "delta"]
var checks := 0
var failures: Array[String] = []

class RecordingMain extends "res://scripts/main.gd":
	var messages: Array[Dictionary] = []
	func _emit(message: Dictionary) -> void:
		messages.append(message.duplicate(true))

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func last(session: Node, type: String) -> Dictionary:
	for index: int in range(session.messages.size() - 1, -1, -1):
		if session.messages[index].get("type", "") == type: return session.messages[index]
	return {}

func bridge(session: Node, action: Dictionary) -> void:
	session._on_web_message([JSON.stringify(action)])
	session._flush_inputs()

func fixture(seed_value: int, casualty: bool) -> Dictionary:
	# Same authored vulnerability as room_control_test: no death/aim/hit
	# injection. A normal guard must actually shoot the 30HP point operator.
	var positions: Array = [[9.3,10.95],[6.7,10.95],[9.3,11.65],[6.7,11.65]]
	var units: Array = []
	for index: int in range(4):
		var origin := Vector2(float(positions[index][0]),float(positions[index][1]))
		units.append({"id":ORDER[index],"x":origin.x,"z":origin.y,"facing":(Vector2(8.0,10.5)-origin).angle(),"hp":30.0 if casualty and index==0 else 100.0,"armor":"none","helmet":"none","ammo":0 if casualty else 30,"reserve_ammo":72})
	var enemies: Array = [{"id":"shooter","x":9.5,"z":6.4,"facing":PI*0.5,"response_role":"guard"}] if casualty else []
	# A separate sealed room proves RESULT cannot publish hidden NPCs/control.
	enemies.append({"id":"hidden","x":2.0,"z":2.0,"facing":0.0,"response_role":"guard"})
	return {"id":"ROOM_CONTROL_MAIN", "schema_version":4,"seed":seed_value,"variant":"normal","bounds":[16,16],
		"rooms":[{"id":"room","x":8.0,"z":8.0,"w":5.0,"d":5.0,"indoor":true},{"id":"sealed","x":2.0,"z":2.0,"w":2.0,"d":2.0,"indoor":true}],
		"walls":[{"x":5.5,"z":8.0,"w":0.2,"d":5.0},{"x":10.5,"z":8.0,"w":0.2,"d":5.0},{"x":8.0,"z":5.5,"w":5.0,"d":0.2},{"x":6.25,"z":10.5,"w":1.5,"d":0.2},{"x":9.75,"z":10.5,"w":1.5,"d":0.2},{"x":2.0,"z":1.0,"w":2.0,"d":0.2},{"x":2.0,"z":3.0,"w":2.0,"d":0.2},{"x":1.0,"z":2.0,"w":0.2,"d":2.0},{"x":3.0,"z":2.0,"w":0.2,"d":2.0}],
		"doors":[{"id":"door","x":8.0,"z":10.5,"axis":"x","w":1.8,"d":0.2,"state":"CLOSED","hinge_side":-1.0,"swing_sign":1.0}],"props":[],"units":units,"enemies":enemies,"civilians":[],
		"win":[{"type":"reach_zone","zone":[15.0,15.0,0.1,0.1]}] if casualty else [{"type":"rooms_cleared","room_ids":["room"]}],"fail":[]}

func load_fixture(session: Node, seed_value: int, casualty: bool) -> void:
	var data := fixture(seed_value, casualty)
	session.maps[data.id] = data
	session._load_mission(data.id)
	check(bool(session.sim.plan_room_entry("door","OPEN_DOOR",ORDER,{}).get("ok",false)),"Real Main fixture accepts the public entry macro")
	session._shown_dirty = true
	session._refresh_shown()
	session._restore_room_drill_preview()

func run() -> void:
	var session: Node = MainScene.instantiate()
	session.set_script(RecordingMain)
	root.add_child(session)
	session.set_process(false)
	await process_frame # Scene initialization only; no timed simulation waits.
	_settings(session)
	for seed_value: int in [0,17,29]:
		_casualty(session,seed_value,true)
		_casualty(session,seed_value,false)
	_search_and_result(session)
	_presentation_clock()
	_badges(session)
	session.queue_free()
	await process_frame # Disposal only.
	print("BREACH_ROOM_CONTROL_MAIN_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _settings(session: Node) -> void:
	check(session.settings.auto_pause_man_down == false and session.sim.auto_pause_man_down == false,"Legacy settings default to uninterrupted execution")
	bridge(session,{"action":"settings","settings":{"language":"en","auto_pause_man_down":true}})
	check(session.settings.auto_pause_man_down == true and session.sim.auto_pause_man_down == true,"Native bool preference immediately configures authority")
	bridge(session,{"action":"settings","settings":{"auto_pause_man_down":"false"}})
	check(session.settings.auto_pause_man_down == true and session.sim.auto_pause_man_down == true,"Malformed preference cannot silently coerce or replace true")
	check(last(session,"toast").get("i18n_key","")=="team.invalid_settings","Rejected team setting exposes a paired UI key")
	bridge(session,{"action":"settings","settings":{"language":"en"}})
	check(session.settings.auto_pause_man_down == true,"Partial legacy preference keeps the existing explicit bool")
	for message: String in session.REPLAY_ERROR_I18N:
		session._toast(message,"error")
		var toast := last(session,"toast")
		check(toast.get("i18n_key","")==session.REPLAY_ERROR_I18N[message] and toast.message!=message,"New replay diagnostic has a paired key and English native fallback")

func _casualty(session: Node, seed_value: int, automatic: bool) -> void:
	bridge(session,{"action":"settings","settings":{"language":"en","auto_pause_man_down":automatic}})
	load_fixture(session,seed_value,true)
	check(session.sim.auto_pause_man_down==automatic,"New mission preserves the configured auto-pause preference")
	session.selected = "alpha"
	session.selected_units.assign(ORDER)
	session.mode = "EXECUTING"
	var death_tick := -1
	for frame: int in range(300):
		session._process(STEP)
		if float(session.sim.units[0].hp)<=0.0:
			death_tick = int(session.sim.tick)
			break
	check(death_tick>0 and session.sim.hits_taken>0,"Seed %d: normal enemy gunfire causes actual point casualty" % seed_value)
	var calls: Array = session.recorder.events_since(0,session.sim.time,true).filter(func(event: Dictionary)->bool:return event.type=="CALL_MAN_DOWN")
	check(calls.size()==1 and int(calls[0].tick)==death_tick,"Seed %d: same-tick ACK preserves exactly one real casualty CALL" % seed_value)
	check(not session.sim.pause_requested and session.sim.pause_reason.is_empty() and session.sim.pause_unit_id.is_empty(),"Controller leaves no replayable stale pause request/reason/ID")
	var landed: Dictionary = session.recorder.seek(session.sim.time,true)
	# The ID is an optional replay field and is omitted when empty.
	check(not bool(landed.get("pause_requested",true)) and landed.get("pause_reason","missing")=="" and landed.get("pause_unit_id","")=="","Final same-tick recording contains acknowledged pause state")
	check(landed.units[0].hp<=0.0 and landed.tick==death_tick,"ACK retains the exact casualty frame and dead operator")
	if automatic:
		check(session.mode=="PLANNING" and session.selected!="alpha" and not session.selected_units.has("alpha") and session.selected_units.size()==3,"Auto-pause selects only the actual three survivors")
		check(last(session,"toast").get("i18n_key","")=="team.man_down_paused","Actual auto-pause emits the paired casualty notification")
		var fixed_tick: int = session.sim.tick
		for frame: int in range(10): session._process(STEP)
		check(session.sim.tick==fixed_tick,"Planning truly holds authority without sleep or wall-clock polling")
		var preview: Dictionary = session.world._resolved_room_drill_preview()
		check(bool(preview.get("ok",false)) and preview.get("slots",[]).size()==3 and preview.slots.all(func(slot: Dictionary)->bool:return slot.unit_id!="alpha"),"Main restores a surviving three-person preview")
		check(preview.get("entry_count",0)==3,"Merged 3/4 target is drawn exactly once")
		var actual_targets: Dictionary = {}
		for contract: Dictionary in session.sim._room_registered.values():
			if contract.room_id=="room": actual_targets = contract.targets
		for target: Dictionary in preview.get("slots",[]):
			check(target.get("unit_id","")!="alpha","Dead point operator has no future domination target")
			var expected: Array = actual_targets.get(target.unit_id,[])
			var shown_point := Vector2(float(target.domination[0]),float(target.domination[1]))
			# JSON bridge numbers and native Vector2 use different float storage.
			var same_goal: bool = expected.size()==2 and shown_point.distance_to(Vector2(float(expected[0]),float(expected[1])))<0.00001
			check(same_goal and int(target.order)>=1 and int(target.order)<=3,"Preview follows the actual atomically reformed primitive target and rank")
			var owner: Dictionary = session.sim._find(session.sim.units,target.unit_id)
			var sector: Dictionary = {}
			for command: Dictionary in owner.commands:
				if command.type=="FACE" and command.state=="PENDING" and command.args.get("drill",{}).get("stage","")=="domination": sector = command.args.get("sector",{})
			var shown_span: float = fposmod(float(target.sector_domination.end)-float(target.sector_domination.start),TAU)
			var actual_span: float = fposmod(float(sector.get("end",0.0))-float(sector.get("start",0.0)),TAU)
			check(not sector.is_empty() and absf(shown_span-actual_span)<0.00001,"Reformed preview preserves the actual merged firing sector")
		bridge(session,{"action":"toggle"})
		check(session.mode=="EXECUTING","Reformed primitive plan remains executable after actual ACK")
	else:
		check(session.mode=="EXECUTING","Default/off preference continues after actual casualty")
	var before_tick: int = session.sim.tick
	session._process(STEP)
	check(session.sim.tick==before_tick+1,"Post-casualty execution advances exactly one fixed STEP")
	check(session.recorder.events_since(0,session.sim.time,true).filter(func(event: Dictionary)->bool:return event.type=="CALL_MAN_DOWN").size()==1,"Resume does not duplicate casualty CALL")

func _search_and_result(session: Node) -> void:
	load_fixture(session,0,false)
	session.mode = "EXECUTING"
	for frame: int in range(450):
		session._process(STEP)
		if session.mode=="RESULT": break
	check(session.mode=="RESULT" and bool(session.sim.result.get("success",false)),"Actual entrants complete stationary search and reach RESULT")
	var public_state := last(session,"state")
	check(public_state.get("room_states",{}).get("room",{}).get("state","")=="CLEAR","Observed actual CLEAR reaches the RESULT UI")
	check(public_state.get("room_states",{}).get("sealed",{}).get("state","")=="UNKNOWN" and not bool(public_state.room_states.sealed.observed),"Sealed room remains unknown in RESULT")
	check(public_state.enemies.all(func(enemy: Dictionary)->bool:return enemy.id!="hidden"),"RESULT cannot reveal a hidden live enemy")
	check(public_state.get("result",{}).get("room_states",{}).get("sealed",{}).get("state","")=="UNKNOWN","Nested debrief state also preserves the unseen room")
	var full_record: Dictionary = session.recorder.seek(session.recorder.duration,true)
	check(full_record.enemies.any(func(enemy: Dictionary)->bool:return enemy.id=="hidden"),"Full recording retains hidden entities for explicit replay reveal")
	check(not session.world._state.get("presentation_reveal",false),"RESULT presentation keeps observation fog")
	var clear_calls: Array = session.recorder.events_since(0,session.recorder.duration,true).filter(func(event: Dictionary)->bool:return event.type=="CALL_ROOM_CLEAR")
	check(clear_calls.size()==1 and bool(clear_calls[0].observed),"Actual authority publishes exactly one observed search CALL")
	if clear_calls.is_empty(): return
	var call: Dictionary = clear_calls[0]
	# The final CLEAR map is intentionally already present: only occurrence
	# time and event order may animate it, even in a fast multi-tick frame.
	var batch: Dictionary = session.sim.snapshot(false)
	batch["presentation_events"] = [call]
	batch["presentation_time"] = float(call.time)-STEP
	session._reset_fx_cursor({"room_states":{},"events":[]})
	session.messages.clear()
	session._dispatch_fx(batch)
	check(not bool(session._fx_room_cleared.get("room",false)) and last(session,"fx").is_empty(),"Future final CLEAR map cannot animate before its actual CALL")
	batch.presentation_time = call.time
	session._dispatch_fx(batch)
	check(bool(session._fx_room_cleared.get("room",false)) and last(session,"fx").get("kind","")=="room_clear","Exact actual CALL clock animates room clearance")
	var count: int = session.messages.size()
	session._dispatch_fx(batch)
	check(session.messages.size()==count,"Repeated render batch deduplicates real room-clear CALL")
	session._reset_fx_cursor(batch)
	check(session.messages.size()==count and bool(session._fx_room_cleared.get("room",false)),"Quiet seek restores authority without historical FX")
	# A white-box observation projection contract; recontamination behavior
	# itself is exercised with real movement in room_control_test.
	batch.room_states.room = {"state":"CONTACT","changed_tick":session.sim.tick,"changed_at":session.sim.time,"observed":true}
	session.world._sync_room_control_labels(batch)
	check(not bool(session.world._room_cleared.get("room",true)) and session.world._room_state_labels.room.text==session.world._t("교전"),"Observed recontact removes the clear marker")
	batch.room_states_observed = {"room":{"state":"MARKED","changed_tick":1,"changed_at":STEP,"observed":true}}
	session.world._sync_room_control_labels(batch)
	check(bool(session.world._room_cleared.get("room",false)) and session.world._room_state_labels.room.text==session.world._t("표식"),"Private recontact cannot overwrite the public MARKED memory")

func _presentation_clock() -> void:
	var before := {"time":10.0,"tick":300,"units":[],"events":[],"room_states":{"r":{"state":"DOMINATED","observed":true}},"result":{}}
	var after := before.duplicate(true)
	after.time = 10.0+STEP
	after.tick = 301
	after.room_states.r.state = "CLEAR"
	after.result = {"room_states":after.room_states.duplicate(true)}
	after.events = [{"seq":1,"type":"CALL_ROOM_CLEAR","time":after.time,"observed":true,"unit_id":"alpha","room_id":"r"}]
	var p := Presentation.new()
	p.reset(before)
	p.capture(after)
	for fraction: float in [0.0,0.5,0.999]:
		var shown: Dictionary = p.sample(fraction)
		check(shown.room_states.r.state=="DOMINATED" and shown.result.room_states.is_empty() and shown.presentation_events.is_empty(),"Interpolated display never advances CLEAR/result/CALL ahead of the fixed tick")
	var exact: Dictionary = p.sample(1.0)
	check(exact.room_states.r.state=="CLEAR" and exact.result.room_states.r.state=="CLEAR" and exact.presentation_events.size()==1,"Exact boundary lands all discrete room feedback together")
	exact.room_states.r.state = "CONTACT"
	check(before.room_states.r.state=="DOMINATED","Projection does not mutate the previous observation")

func _badges(session: Node) -> void:
	var world: Node = session.world
	var state: Dictionary = session.sim.snapshot(false)
	# These are presentation contract inputs, not fake simulation events or
	# evidence for gameplay completion. Real six-CALL triggers have own suites.
	for index: int in range(world.CALL_LABELS.size()):
		var type: String = world.CALL_LABELS.keys()[index]
		world._call_events.clear()
		world._clock = 20.0
		var event := {"seq":index+1,"type":type,"unit_id":"alpha","time":20.0,"observed":true}
		world._remember_call(event,state)
		for language: String in ["ko","en"]:
			world._language = language
			world._sync_call_labels(state)
			var label: Label3D = world._entity_nodes.alpha.call_label
			check(label.visible and label.text==world._t(str(world.CALL_LABELS[type])),"Owned %s badge translates to %s" % [type,language])
		world._clock = 20.0+world.CALL_LABEL_SECONDS+STEP
		world._sync_call_labels(state)
		check(not world._entity_nodes.alpha.call_label.visible,"CALL badge expires by fixed presentation time")
	world._call_events.clear()
	world._clock = 20.0
	for event: Dictionary in [{"seq":70,"type":"CALL_MAN_DOWN","unit_id":"hidden","time":20.0,"observed":true},{"seq":71,"type":"CALL_MAN_DOWN","unit_id":"alpha","time":20.0+STEP,"observed":true},{"seq":72,"type":"CALL_MAN_DOWN","unit_id":"alpha","time":20.0,"observed":false}]:
		world._remember_call(event,state)
	check(world._call_events.is_empty(),"Hidden NPC, future clock and unobserved CALL cannot become own badges")
