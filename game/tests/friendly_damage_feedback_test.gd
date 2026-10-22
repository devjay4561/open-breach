extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Actor = preload("res://scripts/actor_visual.gd")
const Presentation = preload("res://scripts/presentation_state.gd")
class Harness extends "res://scripts/main.gd":
	var emitted: Array = []
	func _ready() -> void: pass
	func _emit(message: Dictionary) -> void: emitted.append(message)
var checks := 0
var failures: Array[String] = []
var evidence: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func hits(app: Node) -> Array:
	return app.emitted.filter(func(e: Dictionary) -> bool: return e.type == "fx" and e.kind == "hit" and e.friendly)
func fixture() -> Dictionary:
	return {"schema_version":1,"id":"DAMAGE_QA","seed":71,"bounds":[16,16],"rooms":[],"walls":[],"props":[],"doors":[],"civilians":[],"units":[{"id":"alpha","x":6.0,"z":6.0,"facing":0.0,"fov":20.0,"armor":"none","helmet":"none"}],"enemies":[{"id":"e1","x":2.0,"z":6.0,"facing":0.0,"vision_range":12.0,"hold_position":true,"hp":10000}],"win":[{"type":"reach_zone","zone":[15,15,.1,.1]}],"fail":[]}
func bridge_sources() -> void:
	var app := Harness.new()
	root.add_child(app)
	var body := Node3D.new()
	root.add_child(body)
	var visual := Actor.create(body, false)
	for source: String in ["hidden_shot", "frag"]:
		app._reset_friendly_health({"units":[{"id":"alpha","hp":100}]})
		var entity := {"id":"alpha","hp":52.0,"x":6.0,"z":6.0,"status":"READY","last_hit_protection":"blocked"}
		var events: Array = [{"seq":10,"type":"FRAG","time":2.0,"observed":true,"to":[6,6],"radius":3.0}] if source == "frag" else []
		var state := {"units":[entity],"time":2.0,"events":events}
		app.last_fx_seq = 0
		app.emitted.clear()
		Actor.sync(visual,entity,[],1.0,0.0,false)
		app._dispatch_fx(state)
		check(hits(app).size() == 1 and is_equal_approx(hits(app)[0].react_at, 0.0 if source == "frag" else 2.05), source + " emits friendly hit with source-appropriate timing")
		check(not entity.has("_feedback_hit"), "Presentation metadata cannot mutate simulation/replay snapshot")
		Actor.sync(visual,state.units[0],[],2.0,0.0,false)
		if source == "hidden_shot":
			check(visual.hit_materials[0].material.albedo_color == visual.hit_materials[0].rest, "Hidden shot flash waits for shot contact")
			Actor.sync(visual,state.units[0],[],2.06,0.0,false)
		check(visual.hit_materials[0].material.albedo_color != visual.hit_materials[0].rest and str(visual.clip).begins_with("RifleHit:"), source + " flashes the actor at contact")
		check(hits(app)[0].protection == ("" if source == "frag" else "blocked"), "Frag does not reuse stale shot armour metadata")
		var before := hits(app).size()
		app._dispatch_fx(state)
		check(hits(app).size() == before, "Repeated health snapshot emits no duplicate")
		app._reset_fx_cursor({"units":[{"id":"alpha","hp":20.0}]})
		app._dispatch_fx({"units":[{"id":"alpha","hp":20.0}],"time":5.0})
		check(hits(app).size() == before, "Seek establishes a health baseline without invented damage")
	for weapon: String in ["standard","shotgun"]:
		app.last_event_seq = 0
		app.last_fx_seq = 0
		app.emitted.clear()
		app._reset_friendly_health({"units":[{"id":"alpha","hp":100}]})
		var shot := {"seq":1,"type":"SHOT","time":3.0,"target_id":"alpha","hostile":false,"hit":true,"weapon":weapon,"protection":"blocked","damage":15.0,"to":[6,6]}
		var state := {"time":3.0,"units":[{"id":"alpha","hp":85}],"events":[shot]}
		app._dispatch_sounds(state)
		app._dispatch_fx(state)
		check(hits(app).size() == 1 and is_equal_approx(hits(app)[0].react_at,3.05), weapon + " and partial armour damage wait for tracer; target roster overrides hostile=false")
		check(app.emitted[1].name == "armour_block" and is_equal_approx(app.emitted[1].react_at,3.05), "Blocked contact uses timed armour cue")
		app.last_fx_seq = 0
		app.emitted.clear()
		shot.target_id = "civilian"
		shot.hostile = true
		state.units[0].hp = 85
		app._dispatch_fx(state)
		check(not app.emitted[0].friendly, "Hostile fire at a civilian cannot flash a friendly card")
	app.last_fx_seq = 0
	app._reset_friendly_health({"units":[{"id":"alpha","hp":100}]})
	app.emitted.clear()
	app._dispatch_fx({"time":6.0,"units":[{"id":"alpha","hp":100}],"events":[{"seq":1,"type":"SHOT","time":6.0,"target_id":"alpha","hit":true,"damage":20.0}]})
	app._dispatch_fx({"time":6.01,"units":[{"id":"alpha","hp":80}]})
	check(hits(app).size() == 1, "A public shot delivered before its HP boundary cannot duplicate fallback feedback")
	app.last_fx_seq = 0
	app._reset_friendly_health({"units":[{"id":"alpha","hp":100}]})
	app.emitted.clear()
	app._dispatch_fx({"time":7.0,"units":[{"id":"alpha","hp":100}],"events":[{"seq":1,"type":"FRAG","time":7.0,"observed":true,"to":[0,0],"radius":3.0}]})
	app._dispatch_fx({"time":7.01,"units":[{"id":"alpha","hp":80,"last_hit_protection":"blocked"}]})
	check(hits(app).size() == 1 and hits(app)[0].react_at == 0 and hits(app)[0].protection == "", "Frag before its HP boundary remains immediate and ignores stale armour")
	body.free()
	app.free()
func stable_fallback_time() -> void:
	var stamps: Array = []
	var unit := {"id":"alpha","hp":80.0,"x":6.0,"z":6.0}
	var presentation := Presentation.new()
	presentation.reset({"time":9.0 - 1.0/30.0,"units":[{"id":"alpha","hp":100.0,"x":6.0,"z":6.0}]})
	presentation.capture({"time":9.0,"units":[unit]})
	presentation.capture({"time":9.0 + 1.0/30.0,"units":[unit]})
	var states: Array = [presentation.sample(0.1), presentation.sample(0.9)]
	for time: float in [9.004,9.03]: states.append(Presentation.new().settle({"time":time,"units":[unit]}))
	for state: Dictionary in states:
		var app := Harness.new()
		root.add_child(app)
		app._reset_friendly_health({"units":[{"id":"alpha","hp":100.0}]})
		app._dispatch_fx(state)
		check(hits(app).size() == 1, "Each sample/settle detects the same hidden HP drop")
		if not hits(app).is_empty():
			var hit: Dictionary = hits(app)[0]
			stamps.append([hit.time,hit.event_seq,hit.react_at,state.units[0]._feedback_hit.time])
		app.free()
	check(stamps.size() == 4 and stamps.all(func(stamp: Array) -> bool: return stamp == [9.0,"hp:alpha:270",9.05,9.0]), "Sample fractions .1/.9 and replay T+.004/T+.03 share exact tick, key, reaction and actor time")
	evidence.append({"source":"stable_fallback_time","stamps":stamps})
func delayed_frag_and_credit() -> void:
	var app := Harness.new()
	root.add_child(app)
	# Both a single slow frame and a separate HP frame must retain the public cause.
	for separate: bool in [false,true]:
		for offset: float in [0.01,0.1]:
			app._reset_friendly_health({"units":[{"id":"alpha","hp":100.0}]})
			app.last_fx_seq = 0
			app.emitted.clear()
			var explosion := {"seq":1,"type":"FRAG","time":12.0,"observed":true,"to":[6,6],"radius":3.0}
			if separate: app._dispatch_fx({"time":12.0,"units":[{"id":"alpha","hp":100.0}],"events":[explosion]})
			var state := {"time":12.0 + offset,"units":[{"id":"alpha","hp":80.0,"x":6.0,"z":6.0,"last_hit_protection":"blocked"}],"events":[] if separate else [explosion]}
			app._dispatch_fx(state)
			check(hits(app).size() == 1 and hits(app)[0].react_at == 0 and hits(app)[0].protection == "", "FRAG remains immediate even three ticks late, with no stale armour")
			check(app.emitted[-1].type == "sound" and app.emitted[-1].name == "hit" and app.emitted[-1].react_at == 0 and not state.units[0]._feedback_hit.after_shot, "Delayed FRAG sound and actor stay immediate without armour tink")
			check(app._fx_frag_pending.is_empty(), "Matched explosion is consumed after fallback")
	# A distant explosion must not reclassify an unrelated shot.
	app._reset_friendly_health({"units":[{"id":"alpha","hp":100.0}]})
	app.last_fx_seq = 0
	app.emitted.clear()
	app._dispatch_fx({"time":13.1,"units":[{"id":"alpha","hp":80.0,"x":12.0,"z":12.0,"last_hit_protection":"blocked"}],"events":[{"seq":1,"type":"FRAG","time":13.0,"observed":true,"to":[1,1],"radius":3.0}]})
	check(hits(app)[0].react_at > 0 and hits(app)[0].protection == "blocked", "Only a unit inside the public blast radius is classified as frag damage")
	app._dispatch_fx({"time":13.2,"units":[{"id":"alpha","hp":80.0}]})
	check(app._fx_frag_pending.is_empty(), "Unmatched explosion expires after the next dispatch")
	# HP-before-SHOT can create unused credit; it must not hide a later loss.
	app._reset_friendly_health({"units":[{"id":"alpha","hp":100.0}]})
	app.last_fx_seq = 0
	app.emitted.clear()
	app._dispatch_fx({"time":14.0,"units":[{"id":"alpha","hp":80.0}]})
	app._dispatch_fx({"time":14.01,"units":[{"id":"alpha","hp":80.0}],"events":[{"seq":1,"type":"SHOT","time":14.0,"target_id":"alpha","hit":true,"damage":20.0}]})
	check(app._fx_unit_shot_damage.has("alpha"), "HP-before-SHOT fixture leaves credit to exercise expiry")
	app._dispatch_fx({"time":14.1,"units":[{"id":"alpha","hp":60.0}]})
	check(hits(app).size() == 3 and not app._fx_unit_shot_damage.has("alpha"), "Credit expires after two ticks and cannot suppress the next real hit")
	app._reset_friendly_health({"units":[{"id":"alpha","hp":100.0}]})
	app.last_fx_seq = 0
	app._dispatch_fx({"time":15.0,"units":[{"id":"alpha","hp":100.0}],"events":[{"seq":1,"type":"SHOT","time":15.0,"target_id":"enemy","hit":true,"damage":20.0},{"seq":2,"type":"SHOT","time":15.0,"target_id":"civilian","hit":true,"damage":20.0}]})
	check(app._fx_unit_shot_damage.is_empty(), "Enemy and civilian SHOT targets never receive friendly damage credit")
	# Unlinked deaths already produce immediate unit_down in world_view.
	app.emitted.clear()
	var casualty := {"time":16.0,"units":[{"id":"alpha","hp":0.0,"x":6.0,"z":6.0}],"events":[{"seq":3,"type":"INCAPACITATED","time":16.0,"entity_id":"alpha","kind":"unit","to":[6,6]}]}
	app._dispatch_fx(casualty)
	var down: Array = app.emitted.filter(func(event: Dictionary) -> bool: return event.type == "fx" and event.kind == "unit_down")
	check(down.size() == 1 and down[0].react_at == 0 and not down[0].after_shot and hits(app).size() == 1 and hits(app)[0].react_at == 0, "Hidden-shooter casualty hit and unit_down both react immediately")
	check(app.emitted[-1].react_at == 0 and not casualty.units[0]._feedback_hit.after_shot, "Hidden casualty sound and actor match immediate world reaction")
	app.free()
func real_hidden_shot() -> void:
	var sim := Simulation.new()
	sim.load_mission(fixture())
	var app := Harness.new()
	root.add_child(app)
	app._reset_friendly_health(sim.snapshot(false))
	for frame: int in range(90):
		sim.step(1.0/30.0)
		var state := sim.snapshot(false)
		app._dispatch_sounds(state)
		app._dispatch_fx(state)
		if float(sim.units[0].hp) < 100: break
	check(float(sim.units[0].hp) < 100 and not bool(sim.enemies[0].visible), "Actual unseen shooter reduces friendly HP")
	check(not sim.events.any(func(e: Dictionary) -> bool: return e.type == "SHOT"), "Actual unseen hit has no public SHOT")
	check(hits(app).size() == 1 and hits(app)[0].react_at > hits(app)[0].time, "Actual unseen hit still reaches friendly feedback without exposing enemy origin")
	evidence.append({"source":"hidden_shot","hp":sim.units[0].hp,"hits":hits(app)})
	app.free()
func real_grenades() -> void:
	for type: String in ["THROW_FRAG","THROW_STUN"]:
		var data := fixture()
		data.roe = "high_intensity"
		data.enemies = []
		data.units = [{"id":"alpha","x":3.0,"z":8.0,"facing":0.0,"armor":"none","helmet":"none","equipment":{"frag":1,"stun":1}}, {"id":"bravo","x":10.0,"z":8.0,"facing":PI,"armor":"none","helmet":"none"}]
		var sim := Simulation.new()
		sim.load_mission(data)
		var app := Harness.new()
		root.add_child(app)
		app._reset_friendly_health(sim.snapshot(false))
		check(bool(sim.issue("alpha",type,{"target":[8.0,8.0]}).ok), type + " accepted")
		for frame: int in range(120):
			sim.step(1.0/30.0)
			var state := sim.snapshot(false)
			app._dispatch_sounds(state)
			app._dispatch_fx(state)
		if type == "THROW_FRAG":
			check(float(sim.units[1].hp) < 100 and hits(app).any(func(e: Dictionary) -> bool: return e.target_id == "bravo" and e.react_at == 0), "Actual friendly frag damage emits immediate feedback")
		else:
			check(sim.events.any(func(e: Dictionary) -> bool: return e.type == "STUN") and float(sim.units[1].hp) == 100 and hits(app).is_empty(), "Actual flash/stun causes no HP loss or invented hit")
		evidence.append({"source":type,"hp":sim.units[1].hp,"hits":hits(app)})
		app.free()
func m01() -> void:
	var data := Catalog.load("M01")
	data.seed = 2130704788
	var sim := Simulation.new()
	sim.load_mission(data)
	var paths := [[[11,12.6],[12,8.5],[12,5.5]],[[13,12.6],[17,12.5],[18.5,9]],[[11,14.7],[8,12],[5,10]],[[13,14.7],[16,12.5],[18.6,8.5]]]
	var accepted := 0
	var rejected: Array = []
	for index: int in range(4):
		for target: Array in paths[index]:
			var response := sim.plan_move(str(sim.units[index].id),{"target":target})
			if bool(response.ok): accepted += 1
			else: rejected.append({"unit":sim.units[index].id,"target":target,"response":response})
	check(accepted >= 10, "Original web plan queues its reachable targets")
	var app := Harness.new()
	root.add_child(app)
	var presentation := Presentation.new()
	var initial := sim.snapshot(false)
	presentation.reset(initial)
	app._reset_friendly_health(initial)
	var losses := 0
	var hp: Dictionary = {}
	for unit: Dictionary in initial.units: hp[unit.id] = float(unit.hp)
	for frame: int in range(1830):
		sim.step(1.0/30.0)
		var observed := sim.snapshot(false)
		presentation.capture(observed)
		# Exercise the production interpolation boundary, including event before health.
		for fraction: float in [0.3,0.8]:
			var state := presentation.sample(fraction)
			app._dispatch_sounds(state)
			app._dispatch_fx(state)
		for unit: Dictionary in observed.units:
			if float(unit.hp) < float(hp[unit.id]): losses += 1
			hp[unit.id] = float(unit.hp)
	app._dispatch_fx(presentation.settle(sim.snapshot(false)))
	check(losses > 0 and hits(app).size() == losses, "M01 fixed seed emits exactly one friendly feedback per HP drop")
	evidence.append({"source":"M01 seed 2130704788","hp":hp,"losses":losses,"rejected_route_commands":rejected,"hits":hits(app)})
	app.free()
func run() -> void:
	bridge_sources()
	stable_fallback_time()
	delayed_frag_and_credit()
	real_hidden_shot()
	real_grenades()
	m01()
	var evidence_path := OS.get_environment("BREACH_DAMAGE_EVIDENCE")
	if not evidence_path.is_empty():
		var file := FileAccess.open(evidence_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence},"  "))
			file.close()
	print("BREACH_FRIENDLY_DAMAGE_FEEDBACK_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
