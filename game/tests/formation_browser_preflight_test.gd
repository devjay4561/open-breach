extends SceneTree
## P4 browser fixtures use authored floor geometry, public primitives and real
## fixed steps. Preview angles are a same-runtime contract; JSON artifacts are
## geometry/role oracles for WASM, never cross-platform atan2 bit goldens.
const Simulation = preload("res://scripts/simulation.gd")
const Schema = preload("res://scripts/mission_schema.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Replay = preload("res://scripts/replay.gd")
const STEP := 1.0 / 30.0
const ORDER := ["alpha", "bravo", "charlie", "delta"]
const META_KEYS := ["kind", "order", "source_unit_id", "stage", "sync_id"]
const PROVENANCE := ["receiver_unit_ids", "signal_mode", "signal_radius", "source_unit_id"]
var checks := 0
var failures: Array[String] = []
var report: Dictionary = {"step":STEP,"seed":42,"cases":[]}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

static func fixture(kind: String = "wide", discipline: String = "verbal") -> Dictionary:
	var narrow := kind == "narrow"
	var junction := kind == "junction"
	var width := 1.6 if narrow else 3.2
	var walls: Array = []
	var areas: Array = []
	var rooms: Array = []
	if junction:
		areas = [{"id":"stem_floor","x":8.0,"z":11.4,"w":3.2,"d":9.2},{"id":"cross_floor","x":8.0,"z":5.2,"w":12.0,"d":3.2}]
		rooms = [{"id":"stem","x":8.0,"z":11.4,"w":3.2,"d":9.2,"indoor":true},{"id":"cross","x":8.0,"z":5.2,"w":12.0,"d":3.2,"indoor":true}]
		walls = [{"id":"stem_left","x":6.3,"z":11.4,"w":0.2,"d":9.2},{"id":"stem_right","x":9.7,"z":11.4,"w":0.2,"d":9.2},{"id":"stem_end","x":8.0,"z":16.1,"w":3.2,"d":0.2},{"id":"cross_top","x":8.0,"z":3.5,"w":12.0,"d":0.2},{"id":"cross_left","x":1.9,"z":5.2,"w":0.2,"d":3.2},{"id":"cross_right","x":14.1,"z":5.2,"w":0.2,"d":3.2},{"id":"cross_bottom_left","x":4.2,"z":6.9,"w":4.4,"d":0.2},{"id":"cross_bottom_right","x":11.8,"z":6.9,"w":4.4,"d":0.2}]
	else:
		areas = [{"id":"hall_floor","x":8.0,"z":9.0,"w":width,"d":14.0}]
		rooms = [{"id":"hall","x":8.0,"z":9.0,"w":width,"d":14.0,"indoor":true}]
		walls = [{"id":"hall_left","x":8.0-width*0.5-0.1,"z":9.0,"w":0.2,"d":14.0},{"id":"hall_right","x":8.0+width*0.5+0.1,"z":9.0,"w":0.2,"d":14.0},{"id":"hall_top","x":8.0,"z":1.9,"w":width,"d":0.2},{"id":"hall_bottom","x":8.0,"z":16.1,"w":width,"d":0.2}]
	# The sealed hostile remains in the authoritative recording. It cannot
	# affect static preview geometry or appear in planning/result observations.
	areas.append({"id":"sealed_floor","x":17.0,"z":4.0,"w":2.0,"d":2.0})
	rooms.append({"id":"sealed","x":17.0,"z":4.0,"w":2.0,"d":2.0,"indoor":true})
	# Authoring requires every room/actor to be reachable with all doors open.
	# Keep a real service route behind two currently closed leaves instead of
	# an unreachable sealed box (the first fixture draft violated that rule).
	var edge := 8.0+width*0.5
	var right_id := "stem_right" if junction else "hall_right"
	for index: int in range(walls.size()-1,-1,-1):
		if walls[index].id==right_id: walls.remove_at(index)
	var start_z := 6.8 if junction else 2.0
	walls.append_array([{"id":"hall_right_upper","x":edge+0.1,"z":(start_z+9.4)*0.5,"w":0.2,"d":9.4-start_z},{"id":"hall_right_lower","x":edge+0.1,"z":13.3,"w":0.2,"d":5.4}])
	areas.append_array([{"id":"service_floor","x":(edge+17.6)*0.5,"z":10.0,"w":17.6-edge,"d":1.2},{"id":"service_turn_floor","x":17.0,"z":7.0,"w":1.2,"d":6.4}])
	rooms.append_array([{"id":"service","x":(edge+17.6)*0.5,"z":10.0,"w":17.6-edge,"d":1.2,"indoor":true},{"id":"service_turn","x":17.0,"z":7.0,"w":1.2,"d":6.4,"indoor":true}])
	walls.append_array([{"id":"sealed_top","x":17.0,"z":2.9,"w":2.2,"d":0.2},{"id":"sealed_bottom_left","x":16.1,"z":5.1,"w":0.6,"d":0.2},{"id":"sealed_bottom_right","x":17.9,"z":5.1,"w":0.6,"d":0.2},{"id":"sealed_left","x":15.9,"z":4.0,"w":0.2,"d":2.2},{"id":"sealed_right","x":18.1,"z":4.0,"w":0.2,"d":2.2}])
	var doors := [{"id":"service_entry","x":edge+0.1,"z":10.0,"w":0.2,"d":1.2,"axis":"z","state":"CLOSED","material":"wood","hinge_side":-1.0,"swing_sign":-1.0},{"id":"sealed_entry","x":17.0,"z":5.1,"w":1.2,"d":0.2,"axis":"x","state":"CLOSED","material":"wood","hinge_side":-1.0,"swing_sign":-1.0}]
	for wall: Dictionary in walls:
		wall["material"] = "concrete"
		wall["height"] = 2.8
	var units: Array = []
	for index: int in range(4):
		units.append({"id":ORDER[index],"name":str(ORDER[index]).to_upper(),"role":"TEST","x":8.0,"z":11.0+index*0.7,"facing":-PI*0.5,"weapon":"standard","ammo":24,"reserve_ammo":24,"hp":100.0,"armor":"none","helmet":"none","stance":"standing","movement_mode":"normal"})
	return {"schema_version":5,"id":"FORMATION_%s_%s_UI"%[kind.to_upper(),discipline.to_upper()],"revision":1,"title":"대형 검증","title_en":"Formation Check","seed":42,"default_seed":42,"bounds":[20,18],"focus":[8,9],"custom":true,"rooms":rooms,"walls":walls,"walkable_areas":areas,"doors":doors,"props":[],"units":units,"enemies":[{"id":"unseen","name":"UNSEEN","x":17.0,"z":4.0,"facing":0.0,"weapon":"standard","ammo":24,"hp":100.0,"enemy_type":"sentry","passive":true}],"civilians":[],"objectives":["대형을 검증하세요."],"win":[{"type":"neutralize_all"}],"fail":[],"stars":[],"variant":"normal","modifiers":[],"noise_discipline":discipline,"environment":{"time_of_day":"day","lighting":1}}

static func destination(kind: String) -> Array:
	return [8.0,5.2] if kind == "junction" else [8.0,4.0]

static func canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func run() -> void:
	for configuration: Array in [["narrow","verbal","AUTO","AUTO"],["wide","verbal","AUTO","B"],["wide","hand_signals","ROLLING_T","B"],["junction","hand_signals","T_JUNCTION","B"]]:
		_case(str(configuration[0]),str(configuration[1]),str(configuration[2]),str(configuration[3]))
	var directory := ProjectSettings.globalize_path("res://../tests/artifacts/formation-browser")
	check(DirAccess.make_dir_recursive_absolute(directory)==OK,"Native fixture evidence directory is writable")
	var file := FileAccess.open(directory.path_join("preflight.json"),FileAccess.WRITE)
	check(file!=null,"Native fixture evidence can be written")
	report["checks"] = checks
	report["failures"] = failures.duplicate()
	report["status"] = "PASS" if failures.is_empty() else "FAIL"
	if file!=null: file.store_string(JSON.stringify(report,"\t")+"\n")
	print("BREACH_FORMATION_BROWSER_PREFLIGHT_RESULT checks=%d failures=%d"%[checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _queues(sim: RefCounted) -> Array:
	return sim.snapshot(false).units.map(func(unit: Dictionary)->Dictionary:return {"id":unit.id,"commands":unit.commands.map(func(command: Dictionary)->Dictionary:return {"type":command.type,"args":command.args.duplicate(true)})})

func _rngs(sim: RefCounted) -> Array:
	return [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]

func _route(nav: RefCounted, origin: Array, points: Array, label: String) -> void:
	var prior := Vector2(float(origin[0]),float(origin[1]))
	check(nav.walkable(prior),label+" starts on body-clear authored floor")
	for point: Array in points:
		var current := Vector2(float(point[0]),float(point[1]))
		check(nav.walkable(current) and nav.segment_clear(prior,current,Navigation.RADIUS),label+" has a complete swept body-clear segment")
		prior = current

func _preview_contract(sim: RefCounted, preview: Dictionary, kind: String, discipline: String) -> void:
	check(preview.get("source_unit_id","")=="delta","Actual default signal source is the last formation rank")
	check(preview.get("kind","")==("T_JUNCTION" if kind=="junction" else ("SERPENTINE" if kind=="narrow" else "ROLLING_T")),"AUTO uses physical clear width while T is explicit")
	check(preview.get("slots",[]).size()==4,"All four owned slots are published")
	var nav := Navigation.new()
	nav.build(sim._formation_geometry(),sim._formation_geometry().get("doors",[]))
	for index: int in range(preview.get("slots",[]).size()):
		var slot: Dictionary = preview.slots[index]
		check(slot.unit_id==ORDER[index] and int(slot.index)==index+1,"Preview preserves exact selected order")
		for key: String in ["initial_face_target","stack_face_target","ready_face_target","face_target","stack","target"]:
			check(slot.get(key) is Array and slot[key].size()==2,"Slot publishes "+key)
		check(str(slot.get("stance",""))==("crouched" if kind=="junction" and index%2==0 else "standing"),"T ranks 1/3 crouch and 2/4 stand in both signal modes")
		var origin: Array = [sim.units[index].x,sim.units[index].z]
		_route(nav,origin,slot.get("stack_route",[]),str(slot.unit_id)+" stack")
		_route(nav,slot.stack,slot.get("move_route",[]),str(slot.unit_id)+" advance")
		check(not slot.get("stack_route",[]).is_empty() and canonical(slot.stack_route.back())==canonical(slot.stack),"Stack route ends at the actual stack slot")
		check(not slot.get("move_route",[]).is_empty() and canonical(slot.move_route.back())==canonical(slot.target),"Advance route ends at the actual final slot")
		var initial := Vector2(float(slot.initial_face_target[0])-float(origin[0]),float(slot.initial_face_target[1])-float(origin[1]))
		var stacked := Vector2(float(slot.stack_face_target[0])-float(slot.stack[0]),float(slot.stack_face_target[1])-float(slot.stack[1]))
		var final_direction := Vector2(float(slot.face_target[0])-float(slot.target[0]),float(slot.face_target[1])-float(slot.target[1]))
		check(initial.length()>0.0 and stacked.length()>0.0 and final_direction.length()>0.0,"Every FACE uses its own projected origin")
		if index==3 and kind!="junction": check(initial.y>0.0 and stacked.y>0.0 and final_direction.y>0.0,"Fourth rank actually watches the rear throughout the route")
		if discipline=="hand_signals": check(canonical(slot.ready_face_target)!=canonical(slot.stack_face_target),"Hand readiness uses mutual source sight instead of the covered sector")

func _command_contract(sim: RefCounted, preview: Dictionary, discipline: String) -> void:
	for slot: Dictionary in preview.slots:
		var unit: Dictionary = sim._find(sim.units,str(slot.unit_id))
		var commands: Array = unit.commands
		check(commands.size()>5 and commands[0].type=="FACE" and commands[0].args.target==canonical(slot.initial_face_target) and bool(commands[0].args.persistent),"Initial persistent FACE covers its actual projected approach")
		check(commands[0].args.get("sector",{})=={"start":0.0,"end":0.0,"duration":0.0},"Only the initial role FACE explicitly clears a preceding room sector")
		var waits: Array = commands.filter(func(command: Dictionary)->bool:return command.type=="WAIT_FOR_SIGNAL")
		check(waits.size()==1,"The macro expands exactly one primitive barrier per member")
		var ready_faces: Array = commands.filter(func(command: Dictionary)->bool:return command.type=="FACE" and command.args.formation.stage=="ready")
		var ready_target: Array = slot.ready_face_target if discipline=="hand_signals" else slot.stack_face_target
		check(ready_faces.size()==1 and ready_faces[0].args.target==canonical(ready_target),"Readiness preserves verbal role or physical hand sight")
		check((ready_faces[0].args.get("stance","")==slot.stance) if preview.kind=="T_JUNCTION" else not ready_faces[0].args.has("stance"),"Only the T drill issues prescribed stance; corridor posture remains owned")
		for command: Dictionary in commands:
			var metadata: Dictionary = command.args.get("formation",{})
			var keys: Array = metadata.keys();keys.sort()
			check(keys==META_KEYS and not command.args.has("drill") and command.type in ["MOVE","FACE","WAIT_FOR_SIGNAL"],"Only existing primitives carry the exact independent formation metadata")
			check(metadata.kind==preview.kind and int(metadata.order)==int(slot.index) and metadata.source_unit_id=="delta" and metadata.stage in ["stack","ready","move","cover"],"Each primitive keeps resolved kind, rank, stable source and stage")
		check(commands.back().type=="FACE" and commands.back().args.target==canonical(slot.face_target) and commands.back().args.sector==canonical({"start":slot.sector.start,"end":slot.sector.end,"duration":slot.sector.duration}),"Final same-runtime FACE and sector match the entire published preview exactly")

func _case(kind: String, discipline: String, requested: String, signal_name: String) -> void:
	var data := fixture(kind,discipline)
	var schema: Dictionary = Schema.check(data)
	check(bool(schema.get("ok",false)),"Authored "+kind+"/"+discipline+" fixture passes schema 5: "+str(schema.get("errors",[])))
	var sim := Simulation.new()
	sim.load_mission(data)
	var options := {"append":true,"signal":signal_name,"delay_ticks":3}
	var prior := JSON.stringify(sim.snapshot(true))
	var rng := _rngs(sim)
	var preview: Dictionary = sim.formation_preview(destination(kind),requested,ORDER,options)
	check(bool(preview.get("ok",false)),kind+"/"+discipline+" accepts the public formation preview: "+str(preview.get("message_key",preview.get("reason_code",""))))
	if not bool(preview.get("ok",false)): return
	check(JSON.stringify(sim.snapshot(true))==prior and _rngs(sim)==rng and sim.tick==0 and sim.time==0.0,"Static preview consumes no clock, RNG or command authority")
	_preview_contract(sim,preview,kind,discipline)
	# Completion targets are authored from the already-public geometry, then
	# fixed before execution. Every slot must remain stationary long enough for
	# its real final FACE; one point entering a reach-zone cannot end the fixture.
	data["interactive_targets"] = []
	var target_ids: Array = []
	for slot: Dictionary in preview.slots:
		var id := "finish_"+str(slot.unit_id)
		target_ids.append(id)
		data.interactive_targets.append({"id":id,"x":slot.target[0],"z":slot.target[1],"w":0.25,"d":0.25,"label":id.to_upper(),"action":"inspect","duration":2.0})
	data.win = [{"type":"targets_complete","targets":target_ids}]
	schema = Schema.check(data)
	check(bool(schema.get("ok",false)),"All four fixed inspection goals pass authored schema: "+str(schema.get("errors",[])))
	sim.load_mission(data)
	preview = sim.formation_preview(destination(kind),requested,ORDER,options)
	var planned: Dictionary = sim.plan_formation(destination(kind),requested,ORDER,options)
	check(bool(planned.get("ok",false)),kind+" actual macro accepts all body-clear primitives")
	if not bool(planned.get("ok",false)): return
	_command_contract(sim,preview,discipline)
	var initial := _queues(sim)
	var ready_tick := -1
	var release_tick := -1
	var min_gap := INF
	var signals: Array = []
	var trace: Array = []
	var seen: Dictionary = {}
	var record := Replay.new()
	record.begin(data)
	record.capture(sim.snapshot(true),sim.take_record_events())
	for _frame: int in range(1800):
		sim.step(STEP)
		for first: int in range(sim.units.size()):
			for second: int in range(first+1,sim.units.size()):
				min_gap = minf(min_gap,Vector2(sim.units[first].x,sim.units[first].z).distance_to(Vector2(sim.units[second].x,sim.units[second].z)))
		var waits: Array = []
		for unit: Dictionary in sim.units:
			waits.append_array(unit.commands.filter(func(command: Dictionary)->bool:return command.type=="WAIT_FOR_SIGNAL"))
		if ready_tick<0 and waits.all(func(command: Dictionary)->bool:return command.state=="WAITING"):
			ready_tick = sim.tick
			if signal_name!="AUTO": sim.release_signal(signal_name)
		if release_tick<0 and waits.all(func(command: Dictionary)->bool:return command.state=="SUCCEEDED"): release_tick = sim.tick
		for event: Dictionary in sim.events:
			if event.type=="SIGNAL" and not seen.has(event.seq):
				seen[event.seq] = true
				signals.append(event.duplicate(true))
		record.capture(sim.snapshot(true),sim.take_record_events())
		trace.append({"tick":sim.tick,"units":sim.units.map(func(unit: Dictionary)->Dictionary:return {"id":unit.id,"x":unit.x,"z":unit.z,"stance":unit.stance}),"wait_states":waits.map(func(command: Dictionary)->String:return command.state)})
		if not sim.result.is_empty(): break
	check(ready_tick>0 and release_tick>=ready_tick+3,"All real arrivals precede the shared three-tick release")
	# The first draft assumed 0.49m. Actual movement's existing body contract
	# is 2*Navigation.RADIUS + 0.02 = 0.48m; use it exactly, without epsilon.
	check(min_gap>=sim._movement_body_spacing(),"Whole-route living body clearance satisfies the actual movement spacing contract")
	check(bool(sim.result.get("success",false)) and sim.command_failures==0,"Real fixed-step formation reaches SUCCESS without command failures")
	check(sim.units.all(func(unit: Dictionary)->bool:return unit.commands.all(func(command: Dictionary)->bool:return command.state=="SUCCEEDED")),"Completion requires every expanded primitive, including final FACE, to succeed")
	for slot: Dictionary in preview.slots:
		var unit: Dictionary = sim._find(sim.units,str(slot.unit_id))
		check(Vector2(unit.x,unit.z).distance_to(Vector2(slot.target[0],slot.target[1]))<=0.1,"Every final coverer remains at its actual authored goal within the existing arrival contract")
		check(unit.stance==slot.stance,"All final owned postures retain the public prescribed or preserved stance")
	check(signals.size()==1,"The actual barrier emits exactly one SIGNAL")
	if signals.size()==1:
		var event: Dictionary = signals[0]
		var keys: Array = []
		for key: String in PROVENANCE:
			if event.has(key): keys.append(key)
		check(keys==PROVENANCE and event.source_unit_id=="delta" and event.signal_mode==discipline and float(event.signal_radius)==(0.0 if discipline=="hand_signals" else 6.0),"Real signal publishes all four provenance fields and the actual last-rank source")
		var receivers: Array = event.receiver_unit_ids
		check(receivers.size()==4 and receivers.all(func(id: Variant)->bool:return id in ORDER),"Physical signal reaches exactly the four owned ready members")
	var observed: Dictionary = sim.snapshot(false)
	check(observed.enemies.all(func(enemy: Dictionary)->bool:return enemy.id!="unseen") and observed.room_states.sealed.state=="UNKNOWN" and not bool(observed.room_states.sealed.observed),"Planning and result do not leak the sealed hostile or room control")
	# Record every real fixed tick, including the manual signal's actual event
	# bundle, and verify the unchanged format at its exact final duration.
	# Recorder.finish accepts a full snapshot, as Main does; feeding only the
	# result dictionary would serialize its statistic keys as mission metadata.
	record.finish(sim.snapshot(true))
	var replay := Replay.new()
	var replay_check: Dictionary = replay.load_data(canonical(record.data))
	check(bool(replay_check.get("ok",false)),"Expanded formation replay uses the unchanged numeric-state-v1 contract: "+str(replay_check.get("message","")))
	# Legacy replay decoding explicitly supplies exposure=1 for own rows that
	# omit this optional field (replay.gd defaults). Keep every live field and
	# compare the entire decoded dictionary including that required default.
	check(observed.units.all(func(unit: Dictionary)->bool:return not unit.has("exposure")),"Quiet live own rows omit the optional legacy exposure property")
	var expected_replay: Array = observed.units.map(func(unit: Dictionary)->Dictionary:
		var expected: Dictionary = unit.duplicate(true)
		expected["exposure"] = 1.0
		return expected)
	if not replay.data.is_empty(): check(canonical(replay.seek(replay.duration,false).units)==canonical(expected_replay),"Exact final observed replay keeps every command ID, posture, value and declared legacy exposure default")
	report.cases.append({"id":kind+"_"+discipline,"mission":data,"requested_kind":requested,"target":destination(kind),"order":ORDER.duplicate(),"options":options,"preview":preview,"initial_commands":initial,"ready_tick":ready_tick,"release_tick":release_tick,"min_gap":min_gap,"signals":signals,"ticks":sim.tick,"result":observed.result,"final_units":observed.units,"trace":trace})
