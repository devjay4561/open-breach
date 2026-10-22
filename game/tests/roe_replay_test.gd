extends SceneTree
## P5 occurrence receipts keep hidden fragmentation outcomes private. The real
## subset uses public issue/step only; 30 cheap serialization cases exercise the
## format without duplicating the gameplay suite's 30-seed physical benchmark.
const Replay = preload("res://scripts/replay.gd")
const Presentation = preload("res://scripts/presentation_state.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Simulation = preload("res://scripts/simulation.gd")
const MainScene = preload("res://main.tscn")
const STEP := 1.0 / 30.0
const TICKS := 120
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
func _json(value: Variant) -> Variant: return JSON.parse_string(JSON.stringify(value))
func _run() -> void:
	_test_contracts()
	_test_presentation()
	_test_boundaries_and_legacy()
	for seed_value: int in range(30): _test_cheap_roundtrip(seed_value)
	for seed_value: int in [0,17,29]: _test_actual(seed_value)
	await _test_main_plan()
	print("BREACH_ROE_REPLAY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _mission(seed_value: int = 0) -> Dictionary:
	var mission: Dictionary = Catalog.load("M01")
	mission.schema_version = 6
	mission.roe = "high_intensity"
	mission.id = "ROE_REPLAY_CONTRACT"
	mission.custom = true
	mission.seed = seed_value
	return mission
func _observed() -> Dictionary:
	return {"neutralized":0,"rescued":0,"kills":0,"arrests":0,"civilian_damage":0.0,"civilian_losses":0,"unlawful_shots":0,"score":80}
func _stars(mission: Dictionary, value: bool = false) -> Dictionary:
	var stars := {}
	for star: Dictionary in mission.get("stars", []): stars[star.id] = value
	return stars
func _state(mission: Dictionary) -> Dictionary:
	var unit: Dictionary = mission.units[0]
	var civilian: Dictionary = mission.civilians[0]
	var enemy: Dictionary = mission.enemies[0]
	return {"time":0.0,"tick":0,"units":[{"id":unit.id,"kind":"unit","x":unit.x,"z":unit.z,"hp":100.0,"frags":1,"available_frags":0,"commands":[{"id":"frag-command","type":"THROW_FRAG","args":{"target":[unit.x+1.0,unit.z]},"state":"PENDING"}]}],"enemies":[{"id":enemy.id,"kind":"enemy","x":enemy.x,"z":enemy.z,"hp":72.0,"visible":false}],"civilians":[{"id":civilian.id,"kind":"civilian","x":civilian.x,"z":civilian.z,"hp":100.0,"visible":false,"secured":true,"last_seen":[civilian.x,civilian.z]}],"doors":[],"events":[],"result":{},"objectives":{"neutralized":0,"total":mission.enemies.size(),"rescued":0,"civilians_total":mission.civilians.size()},"stats_observed":_observed(),"kills":0,"arrests":0,"civilian_damage":0.0,"unit_damage":0.0,"civilian_losses":0,"frags_used":0,"unlawful_shots":0,"frag_projectiles":[]}
func _projectile(mission: Dictionary, released: float = STEP) -> Dictionary:
	var unit: Dictionary = mission.units[0]
	return {"id":"frag-1","unit_id":unit.id,"command_id":"frag-command","source":[unit.x,unit.z,1.0],"target":[unit.x+1.0,unit.z,0.0],"position":[unit.x,unit.z,1.0],"released_at":released,"flight_duration":0.2,"detonate_at":released+0.6,"phase":"FLIGHT"}
func _event(mission: Dictionary, kind: String, seq: int, clock: float) -> Dictionary:
	var unit: Dictionary = mission.units[0]
	var event := {"seq":seq,"tick":roundi(clock/STEP),"time":clock,"type":kind,"from":[unit.x,unit.z],"to":[unit.x+1.0,unit.z],"projectile_id":"frag-1","unit_id":unit.id,"radius":4.0,"target_height":0.0,"observed":true}
	if kind == "FRAG_RELEASE": event.merge({"source_height":1.0,"flight_duration":0.2,"detonate_at":clock+0.6})
	return event
func _terminal(mission: Dictionary, state: Dictionary, hidden: bool) -> Dictionary:
	return {"success":true,"status":"SUCCESS","score":20 if hidden else 100,"rank":"C" if hidden else "S","time":state.time,"duration":state.time,"neutralized":1 if hidden else 0,"enemies_total":mission.enemies.size(),"rescued":1 if hidden else 0,"civilians_total":mission.civilians.size(),"kills":1 if hidden else 0,"arrests":0,"civilian_damage":31.25 if hidden else 0.0,"civilian_losses":1 if hidden else 0,"unit_damage":0.0,"frags_used":1,"unlawful_shots":0,"stats_observed":state.stats_observed.duplicate(true),"stars":_stars(mission,not hidden),"stars_observed":_stars(mission)}
func _record(mission: Dictionary, hidden: bool = false) -> Dictionary:
	var recorder := Replay.new()
	recorder.begin(mission)
	var state := _state(mission)
	recorder.capture(state)
	state.time = STEP
	state.tick = 1
	state.units[0].commands[0].state = "RUNNING"
	state.units[0].commands[0].phase = "WAIT_EXPLOSION"
	state.units[0].commands[0].projectile_id = "frag-1"
	state.units[0].frags = 0
	state.frags_used = 1
	state.frag_projectiles = [_projectile(mission)]
	state.events = [_event(mission,"FRAG_RELEASE",1,STEP)]
	recorder.capture(state)
	state.time = STEP*2.0
	state.tick = 2
	state.stats_observed.score = 79
	state.frag_projectiles = Replay.sample_frag_projectiles(state.frag_projectiles,state.time)
	recorder.capture(state)
	state.time = STEP*20.0
	state.tick = 20
	state.frag_projectiles = []
	state.units[0].commands[0].state = "SUCCEEDED"
	state.events.append(_event(mission,"FRAG",2,state.time))
	if hidden:
		state.enemies[0].hp = 0.0
		state.civilians[0].hp = 0.0
		state.civilian_damage = 31.25
		state.civilian_losses = 1
		state.kills = 1
		state.objectives.neutralized = 1
		state.objectives.rescued = 1
	state.result = _terminal(mission,state,hidden)
	recorder.finish(state)
	return _json(recorder.export_data())
func _bad(candidate: Dictionary, change: Callable, message: String) -> void:
	var restored := Replay.new()
	check(restored.load_data(candidate).get("ok",false),"Valid baseline for malformed case: "+message)
	var before := restored.seek(restored.duration,true)
	var altered := candidate.duplicate(true)
	change.call(altered)
	check(not restored.load_data(altered).get("ok",true),"Strict malformed rejection: "+message)
	check(restored.seek(restored.duration,true)==before,"Invalid import leaves loaded record unchanged: "+message)
func _test_contracts() -> void:
	var mission := _mission()
	var candidate := _record(mission,true)
	var restored := Replay.new()
	var loaded := restored.load_data(candidate)
	check(loaded.get("ok",false),"P5 complete numeric record loads: "+str(loaded.get("message","")))
	if not loaded.get("ok",false): return
	check(candidate.schema_version==1 and candidate.encoding=="numeric-state-v1","P5 leaves the replay wrapper and encoding unchanged")
	check(restored.seek(STEP*1.5,true).units[0].frags==0,"Consumed own inventory persists after release")
	check(restored.seek(STEP*1.5,true).stats_observed.score==80 and restored.seek(STEP*2.0,true).stats_observed.score==79,"Receipt-only changes capture their exact tick below sample cadence")
	check(restored.seek(0.0,true).frag_projectiles.is_empty() and restored.seek(STEP,true).frag_projectiles.size()==1,"Release cannot appear before the recorded clock")
	check(restored.seek(STEP+0.2,true).frag_projectiles[0].phase=="FUSE" and restored.seek(STEP+0.6,true).frag_projectiles.is_empty(),"Physical flight and fuse phase obey exact occurrence clocks")
	var public_final := restored.seek(restored.duration,false)
	check(public_final.civilians.is_empty() and public_final.enemies.is_empty(),"P5 secured/last-seen flags do not expose current hidden civilian health")
	check(not public_final.has("stats_observed") and not public_final.result.has("stats_observed") and not public_final.result.has("stars_observed"),"Private receipts are erased from public top and nested result")
	var other := Replay.new()
	check(other.load_data(_record(mission,false)).get("ok",false),"Paired hidden no-hit record loads")
	check(restored.seek(restored.duration,false)==other.seek(other.duration,false),"Hidden death/damage does not change public counters, score, rank, stars, coordinates or event sequence")
	check(restored.seek(restored.duration,true).result.kills==1 and restored.seek(restored.duration,true).result.civilian_damage==31.25,"Explicit full replay keeps authoritative damage and result")
	for key: String in Replay.OBSERVED_STAT_KEYS:
		_bad(candidate,func(data: Dictionary): data.metadata[0].stats_observed.erase(key),"missing observed "+key)
	for value: Variant in [-1,0.5,true,10000001]:
		_bad(candidate,func(data: Dictionary): data.metadata[0].stats_observed.kills=value,"invalid observed count "+str(value))
	for value: Variant in [-0.1,true,"31"]:
		_bad(candidate,func(data: Dictionary): data.metadata[-1].civilian_damage=value,"invalid raw damage "+str(value))
	_bad(candidate,func(data: Dictionary): data.metadata[-1].result.erase("stats_observed"),"missing terminal observed bundle")
	_bad(candidate,func(data: Dictionary): data.metadata[-1].result.erase("stars_observed"),"missing terminal observed stars")
	_bad(candidate,func(data: Dictionary): data.metadata[-1].result.stars_observed["unknown"]=false,"unknown star ID")
	_bad(candidate,func(data: Dictionary): data.metadata[-1].result.stars_observed[mission.stars[0].id]=1,"nonboolean observed star")
	_bad(candidate,func(data: Dictionary): data.metadata[-1].result.success=false; data.metadata[-1].result.stars[mission.stars[0].id]=true,"failed mission cannot award a star")
	_bad(candidate,func(data: Dictionary): data.commands[0].args["request_id"]="unexpected space","invalid common request ID")
	_bad(candidate,func(data: Dictionary): data.commands[0]["phase"]="OPEN","frag incompatible command phase")
	_bad(candidate,func(data: Dictionary): data.events[0]["enemy_id"]=mission.enemies[0].id,"frag event hidden victim ID")
	_bad(candidate,func(data: Dictionary): data.events[0].observed=false,"unobserved own frag occurrence")
	_bad(candidate,func(data: Dictionary): data.events[0].unit_id=mission.enemies[0].id,"non-own grenade source")
	_bad(candidate,func(data: Dictionary): data.metadata[1].frag_projectiles[0]["door_id"]=mission.doors[0].id,"extra projectile field")
	_bad(candidate,func(data: Dictionary): data.metadata[1].frag_projectiles[0].released_at=STEP*2.0,"projectile begins after its sample")
	_bad(candidate,func(data: Dictionary): data.metadata[1].frag_projectiles[0].phase="FUSE","future fuse phase")
	_bad(candidate,func(data: Dictionary): data.states[0].group="enemies"; data.states[0].base.id=mission.enemies[0].id,"frag inventory belongs only to own units")
	# The capture input is deliberately reused and edited in place. Synthetic
	# rows here validate file ownership, not gameplay or casualty generation.
	var recorder := Replay.new()
	recorder.begin(mission)
	var state := _state(mission)
	recorder.capture(state)
	state.stats_observed.score = 1
	check(recorder.seek(0.0,true).stats_observed.score==80,"Capture detaches the caller's observed aggregate")
	var returned := restored.seek(restored.duration,true)
	returned.stats_observed.score = 1
	returned.result.stars_observed.clear()
	returned.result.stars.clear()
	check(restored.seek(restored.duration,true).stats_observed.score==79 and restored.seek(restored.duration,true).result.stars_observed.size()==mission.stars.size(),"Returned aggregate/stars maps cannot mutate interned history")
func _test_presentation() -> void:
	var mission := _mission()
	var first := _state(mission)
	var following := first.duplicate(true)
	following.time = STEP
	following.tick = 1
	following.frag_projectiles = [_projectile(mission)]
	following.flash_projectiles = [_projectile(mission)]
	var presentation := Presentation.new()
	presentation.reset(first)
	presentation.capture(following,[_event(mission,"FRAG_RELEASE",1,STEP)])
	check(presentation.sample(0.5).frag_projectiles.is_empty(),"Presentation cannot show a future frag release")
	var sampled := presentation.sample(1.0)
	check(sampled.frag_projectiles==sampled.flash_projectiles,"Frag physical arc matches the unchanged flash arc")
	check(sampled.presentation_events.size()==1,"Own frag event enters presentation at its actual release tick")
	var halfway := Replay.sample_frag_projectiles(following.frag_projectiles,STEP+0.1)
	check(halfway[0].position[0]>halfway[0].source[0] and halfway[0].position[2]>0.0,"Frag sampling uses the owned physical arc")
	check(following.frag_projectiles[0].position==following.frag_projectiles[0].source,"Sampling never edits the authoritative projectile array")
func _test_boundaries_and_legacy() -> void:
	var mission := _mission()
	var initial := _state(mission)
	var final := initial.duplicate(true)
	final.time = 600.0
	final.tick = 18000
	final.frag_projectiles = [_projectile(mission,600.0)]
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(initial)
	recorder.finish(final)
	var candidate: Dictionary = _json(recorder.export_data())
	var restored := Replay.new()
	check(restored.load_data(candidate).get("ok",false),"A legal release at600s retains its finite future fuse")
	_bad(candidate,func(data: Dictionary): data.metadata[-1].frag_projectiles[0].detonate_at=601.21,"future fuse hard limit")
	var legacy: Dictionary = Catalog.load("M01")
	var state := _state(legacy)
	for key: String in Replay.P5_META_KEYS: state.erase(key)
	state.units[0].erase("frags")
	state.units[0].erase("available_frags")
	state.units[0].commands.clear()
	var old := Replay.new()
	old.begin(legacy)
	old.capture(state)
	old.finish(state)
	check(restored.load_data(_json(old.export_data())).get("ok",false),"Legacy absence still loads without a version change")
	var shown := restored.seek(0.0,false)
	check(not shown.has("frag_projectiles") and not shown.units[0].has("frags"),"Legacy replay does not acquire empty projectile or zero inventory fields")
	check(shown.civilians.size()==1,"Legacy secured-civilian compatibility follows its existing path")
func _test_cheap_roundtrip(seed_value: int) -> void:
	var mission := _mission(seed_value)
	var candidate := _record(mission,seed_value%2==0)
	var restored := Replay.new()
	var loaded := restored.load_data(candidate)
	check(loaded.get("ok",false),"Cheap deterministic serialization seed%d: %s" % [seed_value,str(loaded.get("message",""))])
	if not loaded.get("ok",false): return
	check(candidate==_record(mission,seed_value%2==0),"Repeated fixed-tick metadata JSON is exact seed%d" % seed_value)
	check(restored.seek(STEP,false).frag_projectiles.size()==1 and restored.seek(0.0,false).frag_projectiles.is_empty(),"Rewind restores the previous grenade prefix seed%d" % seed_value)
	for multiplier: int in [1,4]:
		var seq := 0
		var events: Array = []
		for tick: int in range(0,24,multiplier):
			for event: Dictionary in restored.events_since(seq,tick*STEP,false): events.append(event); seq=event.seq
		check(events==candidate.events,"1x/4x fragment event delivery is complete and once-only seed%d" % seed_value)

func _runtime_mission(seed_value: int, hurt: bool = true) -> Dictionary:
	return _json({"schema_version":6,"id":"ROE_REPLAY_LIVE","revision":1,"custom":true,"title":"Fragment replay fixture","seed":seed_value,"roe":"high_intensity","bounds":[14,12],"focus":[6,8],"objectives":["Keep unseen blast outcomes private"],"rooms":[{"id":"own_room","x":3.5,"z":6.0,"w":6.6,"d":11.5},{"id":"hidden_room","x":10.5,"z":6.0,"w":6.6,"d":11.5}],"units":[{"id":"alpha","name":"ALPHA","role":"Assault","weapon":"standard","x":3.0,"z":8.8,"facing":-1.57,"ammo":0,"equipment":{"frag":1}}],"enemies":[{"id":"hidden_enemy","x":7.6 if hurt else 12.5,"z":8.8,"facing":0.0,"ammo":0,"training":true,"passive":true}],"civilians":[{"id":"hidden_civilian","x":8.4 if hurt else 12.5,"z":8.8 if hurt else 9.8}],"walls":[{"id":"partition_top","x":7.0,"z":2.8,"w":0.2,"d":5.6,"material":"drywall","resistance":0.2},{"id":"partition_bottom","x":7.0,"z":9.5,"w":0.2,"d":5.0,"material":"drywall","resistance":0.2}],"doors":[{"id":"hidden_door","x":7.0,"z":6.3,"w":0.24,"d":1.4,"axis":"z","state":"CLOSED","locked":false}],"props":[],"win":[{"type":"reach_zone","zone":[3.0,9.8,0.3,0.3]}],"fail":[],"stars":[{"id":"no_civilian_damage","label":"No civilian damage","stat":"civilian_damage","op":"lte","value":0},{"id":"no_unit_damage","label":"No unit damage","stat":"unit_damage","op":"eq","value":0}]})
func _project_like(value: Variant, shape: Variant) -> Variant:
	if shape is Dictionary:
		if not value is Dictionary: return null
		var output := {}
		for key: Variant in shape: output[key]=_project_like(value.get(key),shape[key])
		return output
	if shape is Array:
		if not value is Array or value.size()!=shape.size(): return null
		var output: Array = []
		for index: int in range(shape.size()): output.append(_project_like(value[index],shape[index]))
		return output
	return value
func _same(decoded: Dictionary, actual: Dictionary) -> bool:
	return JSON.stringify(_json(_project_like(decoded,actual)),"",true)==JSON.stringify(_json(actual),"",true)
func _rng_states(sim: RefCounted) -> Array:
	return [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]
func _simulate(seed_value: int, hurt: bool) -> Dictionary:
	var mission := _runtime_mission(seed_value,hurt)
	check(Catalog.validate_custom(mission).get("ok",false),"Actual frag fixture is schema-valid")
	var sim := Simulation.new()
	sim.load_mission(mission)
	var requested := sim.issue("alpha","THROW_FRAG",{"target":[6.0,8.8],"request_id":"frag-once"})
	check(requested.get("ok",false),"Public primitive plans an actual legal frag")
	check(sim.issue("alpha","THROW_FRAG",{"target":[6.0,8.8],"request_id":"frag-once"})==requested and sim.units[0].commands.size()==1,"Common cached request preserves one actual primitive and one reservation")
	check(sim.issue("alpha","MOVE",{"target":[3.0,9.8]}).get("ok",false),"Owned objective follows the actual detonation")
	var recorder := Replay.new()
	recorder.begin(mission)
	var full := sim.snapshot(true)
	recorder.capture(full,sim.take_record_events())
	var samples := {0:full}
	var publics: Array = []
	var rng: Array = [_rng_states(sim)]
	for tick: int in range(1,TICKS+1):
		sim.step(STEP)
		var pair := sim.snapshot_pair()
		full = pair.record
		var previous_count := recorder.frames.size()
		recorder.capture(full,sim.take_record_events())
		if recorder.frames.size()>previous_count: samples[int(full.tick)]=full
		publics.append(pair.observed)
		rng.append(_rng_states(sim))
	recorder.finish(full)
	samples[int(full.tick)]=full
	return {"sim":sim,"mission":mission,"data":_json(recorder.export_data()),"samples":samples,"publics":publics,"rng":rng,"full":full}
func _test_actual(seed_value: int) -> void:
	var run := _simulate(seed_value,true)
	var repeat := _simulate(seed_value,true)
	var paired := _simulate(seed_value,false)
	check(run.data==repeat.data and run.rng==repeat.rng,"Actual fixed-step replay and all4 RNG repeat exactly seed%d" % seed_value)
	check(run.full.frags_used==1 and run.full.units[0].commands[0].state=="SUCCEEDED","Actual release consumes one grenade and completes its primitive")
	check(not run.full.result.is_empty(),"Actual post-detonation objective produces terminal result")
	check(run.full.civilian_damage>paired.full.civilian_damage,"Paired actual grenade deals different hidden civilian damage")
	var restored := Replay.new()
	var answer := restored.load_data(run.data)
	check(answer.get("ok",false),"Actual FRAG record loads: "+str(answer.get("message","")))
	if not answer.get("ok",false): return
	for tick: int in run.samples:
		check(_same(restored.seek(float(run.samples[tick].time),true),run.samples[tick]),"Actual full snapshot roundtrip seed%d/tick%d" % [seed_value,tick])
	for index: int in range(run.publics.size()):
		check(run.publics[index].civilians.is_empty() and run.publics[index].enemies.is_empty(),"Actual hidden NPCs remain private seed%d/tick%d" % [seed_value,index])
	check(run.publics==paired.publics,"Actual hidden hit/no-hit pair preserves every public snapshot and terminal result")
	for event: Dictionary in run.data.events:
		if event.type in ["FRAG_RELEASE","FRAG"]: check(not event.has("enemy_id") and not event.has("civilian_id") and event.observed,"Actual grenade event contains own occurrence facts only")
	var receipts: Array = run.data.events.filter(func(event: Dictionary)->bool:return event.type in ["FRAG_RELEASE","FRAG"])
	check(receipts.size()==2 and receipts[0].type=="FRAG_RELEASE" and receipts[1].type=="FRAG","Actual release/explosion events occur exactly once")
	var pair: Dictionary = run.sim.snapshot_pair()
	pair.observed.result.stars.clear()
	check(run.sim.snapshot(true).result.stars.size()==run.mission.stars.size() and pair.record.result.stars.size()==run.mission.stars.size(),"Actual public result edits cannot mutate authority or recorder stars")
func _test_main_plan() -> void:
	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	await process_frame
	var mission := _runtime_mission(17)
	check(not session._register_custom(mission).is_empty(),"Main registers actual ROE mission")
	session._action({"action":"start","mission":"ROE_REPLAY_LIVE","seed":17})
	check(session.sim.issue("alpha","THROW_FRAG",{"target":[6.0,8.8]}).get("ok",false),"Main owns legal primitive frag plan")
	var plan: Dictionary = session._export_plan()
	check(plan.schema_version==1 and plan.kind=="breach-plan","FRAG plan keeps primitive schema1")
	var snapshots: Array = []
	var rng: Array = []
	for tick: int in range(90):
		session.sim.step(STEP)
		snapshots.append(JSON.stringify(session.sim.snapshot(true)))
		rng.append(_rng_states(session.sim))
	session._import_plan(_json(plan),false)
	check(session._export_plan()==plan,"Actual Main plan exports/imports every FRAG argument exactly")
	for tick: int in range(90):
		session.sim.step(STEP)
		check(JSON.stringify(session.sim.snapshot(true))==snapshots[tick] and _rng_states(session.sim)==rng[tick],"Main plan replay preserves full authoritative tick and4 RNG")
	var invalid: Dictionary = _json(plan)
	invalid.units[0].commands[0].args["fuse"]=0.01
	# Existing plan1 omits completed commands. Compare with the current graph
	# and full execution state, not the original pre-execution fresh plan.
	var active_plan: Dictionary = session._export_plan()
	var active_state: String = JSON.stringify(session.sim.snapshot(true))
	session._import_plan(invalid,false)
	check(session._export_plan()==active_plan and JSON.stringify(session.sim.snapshot(true))==active_state,"Main rejects an edited nonprimitive fuse without replacing the active plan or execution state")
	session.queue_free()
	await process_frame
