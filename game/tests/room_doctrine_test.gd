extends SceneTree
## Pure receipt/FSM instrumentation contracts. Actual public plan execution
## belongs to room_doctrine_simulation_test; these facts never claim gameplay
## success. Every clock below is a fixed STEP and every seed is reproducible.
const RoomDoctrine = preload("res://scripts/room_doctrine.gd")
const RoomControl = preload("res://scripts/room_control.gd")
const Metrics = preload("res://scripts/doctrine_metrics.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

class Facts extends RefCounted:
	var mission: Dictionary
	var room_control: RefCounted
	var doctrine: RefCounted
	var tick := 0
	var time := 0.0
	var units: Array = []
	var doors: Array = []
	var rng := RandomNumberGenerator.new()
	func _init(data: Dictionary) -> void:
		mission=data.duplicate(true)
		room_control=RoomControl.new()
		room_control.reset(data)
		doctrine=Metrics.new()
		doctrine.reset()
		doors=data.doors.duplicate(true)
		units=[{"id":"alpha","x":5.0,"z":2.0,"hp":100.0,"base_height":0.0,"commands":[]}]
	func _position(actor: Dictionary) -> Vector2:
		return Vector2(float(actor.x),float(actor.z))
	func _point(point: Array) -> Vector2:
		return Vector2(float(point[0]),float(point[1]))

static func mission() -> Dictionary:
	return {"rooms":[{"id":"a","x":5.0,"z":2.0,"w":10.0,"d":4.0,"indoor":true},{"id":"b","x":5.0,"z":6.0,"w":10.0,"d":4.0,"indoor":true},{"id":"raised","x":5.0,"z":2.0,"w":2.0,"d":2.0,"base_height":3.0,"indoor":true}],"doors":[{"id":"entry","x":5.0,"z":4.0,"w":1.8,"d":0.2,"axis":"x","base_height":0.0}],"units":[],"enemies":[],"civilians":[]}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)

func fact(tick: int, room_id: String = "a", id: String = "enemy_secret", kind: String = "enemy") -> Dictionary:
	return {"tick":tick,"time":float(tick)*STEP,"room_id":room_id,"id":id,"kind":kind}

func advance(helper: RefCounted, sim: RefCounted, count: int = 1) -> void:
	for _step: int in range(count):
		sim.tick+=1
		sim.time=float(sim.tick)*STEP
		helper.update(sim,STEP)

func known(sim: RefCounted, room_id: String, state: String = "CONTACT", tick: int = 1) -> void:
	var row := {"state":state,"changed_tick":tick,"changed_at":float(tick)*STEP,"observed":true}
	if state=="MARKED": row["door_id"]="entry"
	sim.room_control.room_states_observed[room_id]=row

func run() -> void:
	_receipts()
	_late_discovery()
	_dwell_and_arrival()
	_floor_and_privacy()
	_floor_arrival()
	_projection_ownership()
	for seed_value: int in range(30):
		check(_repeat(seed_value)==_repeat(seed_value),"Same fixed seed/facts/STEP produce identical detached room receipts")
	var legacy := Metrics.new()
	legacy.reset()
	check(legacy.statistics().keys().size()==5 and not legacy.statistics().has("room_doctrine"),"The existing no-argument P0 reset retains its original statistics shape")
	print("BREACH_ROOM_DOCTRINE_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _receipts() -> void:
	var helper := RoomDoctrine.new()
	helper.reset(mission())
	var sim := Facts.new(mission())
	advance(helper,sim)
	check(helper.snapshot().is_empty(),"Authored room IDs with UNKNOWN unobserved memory cannot produce grading rows")
	known(sim,"a")
	advance(helper,sim)
	var rows: Dictionary = helper.snapshot().a
	check(rows.keys().size()==8 and RoomDoctrine.ROWS.all(func(key: String)->bool:return rows.has(key)),"Every public known room has exactly the eight doctrine rows")
	check(rows.stealth=={"value":null,"tick":null,"time":null} and rows.identification==rows.stealth and rows.control==rows.stealth,"No observed enemy/civilian/control opportunity remains N/A")
	check(rows.rear_hits.value==0 and rows.rear_hits.tick==1 and rows.rear_hits.time==STEP,"Owned zero evidence retains its actual first proof clock")
	var context := fact(3)
	context.merge({"sync_id":"drill","door_id":"entry","unit_ids":["alpha"],"command_ids":["alpha-0002"],"observed_enemies":[]})
	helper.record_stack(context)
	context.observed_enemies=[{"id":"enemy_secret","status":"ALERT","awareness_state":"TRACKING","door_ready":true}]
	helper.record_stack(context)
	check(helper.snapshot().a.stealth.value==null,"An empty first ready epoch cannot gain hidden/post-signal enemy knowledge later")
	context.sync_id="second_drill"
	helper.record_stack(context)
	check(helper.snapshot().a.stealth.value==2 and helper.snapshot().a.stealth.tick==3,"Observed alert maps to category two at the actual preparation tick")
	var surrender := fact(4)
	surrender.merge({"hp":60.0,"max_hp":100.0,"surrendered":true,"arrested":false,"secured":false})
	helper.record_observation(surrender)
	helper.record_observation(surrender)
	var civilian := fact(4,"a","civilian_secret","civilian")
	civilian.merge({"hp":10.0,"max_hp":100.0,"secured":false})
	helper.record_observation(civilian)
	check(helper.snapshot().a.control.surrendered==1 and helper.snapshot().a.control.civilians==1 and helper.snapshot().a.control.value==0.0,"Control denominators count unique observed people once")
	check(helper.snapshot().a.identification.civilian_damage==0.0,"First sight of an already injured civilian never copies hidden damage")
	var arrest := fact(5)
	arrest.merge({"action":"arrest","unit_id":"alpha"})
	helper.record_control(arrest)
	helper.record_control(arrest)
	check(helper.snapshot().a.control.arrested==1 and helper.snapshot().a.control.value==0.5 and helper.snapshot().a.control.tick==5,"Actual owned arrest updates the ratio once at its receipt tick")
	var secure := fact(6,"a","civilian_secret","civilian")
	secure.merge({"action":"secure","unit_id":"alpha"})
	helper.record_control(secure)
	check(helper.snapshot().a.control.secured==1 and helper.snapshot().a.control.value==1.0,"Owned secure receipt completes the observed control denominator")
	var damage := fact(7,"a","civilian_secret","civilian")
	damage.merge({"before":10.0,"after":4.0})
	helper.record_damage(damage)
	helper.record_observation(civilian)
	helper.record_damage(damage)
	check(helper.snapshot().a.identification.value==1 and helper.snapshot().a.identification.civilian_damage==6.0 and helper.snapshot().a.identification.tick==7,"Observed damage is counted once across duplicate observation/damage hooks")
	var unlawful := fact(8)
	unlawful["unit_id"]="alpha"
	helper.record_unlawful(unlawful)
	check(helper.snapshot().a.identification.unlawful_shots==1 and helper.snapshot().a.identification.tick==7,"The first failure evidence stays stable while later owned violations accumulate")
	var serialized := JSON.stringify(helper.snapshot())
	check(not serialized.contains("enemy_secret") and not serialized.contains("civilian_secret") and not serialized.contains("hp") and not serialized.contains("command_ids"),"Public rows contain no NPC identities/health or private command receipt data")
	rows=helper.snapshot()
	rows.a.control.secured=99
	check(helper.snapshot().a.control.secured==1,"Public nested room rows have independent ownership")

func _late_discovery() -> void:
	var helper := RoomDoctrine.new()
	helper.reset(mission())
	var sim := Facts.new(mission())
	known(sim,"a")
	advance(helper,sim)
	var observed := fact(1,"a","civilian_late","civilian")
	observed["hp"] = 100.0
	helper.record_observation(observed)
	var before: Dictionary = helper.snapshot()
	advance(helper,sim,3)
	check(helper.snapshot()==before,"Hidden injury without a fresh fact leaves known room damage and evidence clocks unchanged")
	observed.tick=5
	observed.time=5.0*STEP
	observed.hp=70.0
	helper.record_observation(observed)
	check(helper.snapshot().a.identification.civilian_damage==30.0 and helper.snapshot().a.identification.tick==5 and helper.snapshot().a.identification.time==5.0*STEP,"Late fresh observation records the learned decrease at the discovery tick")
	var damage := fact(6,"a","civilian_late","civilian")
	damage.merge({"before":70.0,"after":40.0})
	helper.record_damage(damage)
	observed.tick=6
	observed.time=6.0*STEP
	observed.hp=40.0
	helper.record_observation(observed)
	helper.record_observation(observed)
	helper.record_damage(damage)
	check(helper.snapshot().a.identification.civilian_damage==60.0,"Actual damage followed by repeated observation/hook contributes only its real health decrease")
	observed.hp=70.0
	helper.record_observation(observed)
	observed.hp=40.0
	helper.record_observation(observed)
	check(helper.snapshot().a.identification.civilian_damage==60.0,"A stale before-health observation in the same tick cannot revive and re-count the damage baseline")
	var first_damage := fact(7,"a","civilian_first_hit","civilian")
	first_damage.merge({"before":50.0,"after":40.0})
	helper.record_damage(first_damage)
	check(helper.snapshot().a.identification.civilian_damage==70.0 and helper.snapshot().a.control.civilians==2,"A first observed hit counts its actual delta and its known civilian control opportunity")

func _dwell_and_arrival() -> void:
	var helper := RoomDoctrine.new()
	helper.reset(mission())
	var sim := Facts.new(mission())
	known(sim,"a")
	sim.units[0].z=4.3
	sim.units[0].commands=[{"state":"PENDING","args":{"drill":{"door_id":"entry","room_id":"a"}}}]
	advance(helper,sim,3)
	sim.units[0].z=6.0
	advance(helper,sim)
	sim.units[0].z=4.3
	advance(helper,sim,5)
	var row: Dictionary = helper.snapshot().a.doorway_dwell
	check(absf(float(row.value)-8.0*STEP)<0.00000001 and row.tick==5 and row.time==5.0*STEP,"Dwell uses cumulative own seconds and the real worst uninterrupted start tick")
	check(row.unit_id=="alpha" and row.door_id=="entry","Dwell evidence contains only the responsible own actor and door")
	var before: Dictionary = helper.snapshot()
	helper.update(sim,STEP)
	check(helper.snapshot()==before,"Duplicate update in one fixed tick cannot inflate dwell")
	# A completed manual entry supplies its actual destination membership;
	# the earlier funnel sample was still on the opposite side of this door.
	sim.units[0].z=2.0
	sim.doctrine.time_to_dominate.entry={"room_id":"a","opened_at":2.0*STEP,"participants":["alpha"],"arrived":["alpha"],"seconds":4.0*STEP,"observed":false}
	sim.doctrine.evidence=[{"type":"DOMINATED","room_id":"a","door_id":"entry","tick":6,"time":6.0*STEP,"seconds":4.0*STEP}]
	advance(helper,sim)
	check(helper.snapshot().a.time_to_dominate.value==null,"Unobserved opening cannot disclose a domination timer")
	sim.units[0].z=6.0
	sim.doctrine.time_to_dominate.entry.observed=true
	advance(helper,sim)
	row=helper.snapshot().a.time_to_dominate
	check(row.value==4.0*STEP and row.tick==6 and row.time==6.0*STEP,"Delayed door observation preserves the actual arrival proof tick rather than the later display tick")

func _floor_and_privacy() -> void:
	var helper := RoomDoctrine.new()
	helper.reset(mission())
	var sim := Facts.new(mission())
	known(sim,"a","MARKED",1)
	sim.units[0].base_height=3.0
	advance(helper,sim)
	check(helper.snapshot().a.rear_hits.value==null,"An actor at the same horizontal coordinates on a raised floor cannot supply lower-room evidence")
	known(sim,"raised","DOMINATED",2)
	advance(helper,sim)
	helper.record_rear_hit(sim,sim.units[0])
	check(helper.snapshot().raised.rear_hits.value==1 and helper.snapshot().raised.rear_hits.tick==2 and helper.snapshot().a.rear_hits.value==null,"Rear hit attribution uses RoomControl's actual floor-aware room membership")
	var before: Dictionary = helper.snapshot()
	sim.room_control.room_states.a={"state":"CONTACT","changed_tick":3,"changed_at":3.0*STEP,"observed":false}
	advance(helper,sim)
	check(helper.snapshot()==before,"Hidden authoritative re-entry cannot change public room values/evidence clocks")
	check(helper.snapshot().a.marked.value==1 and helper.snapshot().a.marked.tick==1,"The owned MARKED memory remains valid through hidden recontamination")

func _floor_arrival() -> void:
	var data := mission()
	data.doors[0].base_height=3.0
	data.doors[0].z=2.8
	var helper := RoomDoctrine.new()
	helper.reset(data)
	var sim := Facts.new(data)
	known(sim,"a")
	known(sim,"raised")
	sim.units[0].base_height=3.0
	sim.units[0].z=2.9
	# P0's first rectangular match is the lower overlapping room. Its old
	# duration remains intact while P6 resolves the actual elevated target.
	sim.doctrine.time_to_dominate.entry={"room_id":"a","opened_at":0.0,"participants":["alpha"],"arrived":["alpha"],"targets":{"alpha":[5.0,2.0]},"seconds":4.0*STEP,"observed":false}
	sim.doctrine.evidence=[{"type":"DOMINATED","room_id":"a","door_id":"entry","tick":4,"time":4.0*STEP,"seconds":4.0*STEP}]
	var p0_before := JSON.stringify(sim.doctrine.time_to_dominate)
	advance(helper,sim)
	check(helper.snapshot().a.doorway_dwell.value==null and helper.snapshot().raised.doorway_dwell.value==STEP,"An elevated funnel target cannot give dwell evidence to the overlapping lower room")
	check(helper.snapshot().raised.time_to_dominate.value==null,"Floor-aware completed receipt stays private until its door opening is observed")
	check(JSON.stringify(sim.doctrine.time_to_dominate)==p0_before,"P6 floor attribution never modifies P0 duration, participants, room or observation")
	sim.units[0].base_height=0.0
	sim.units[0].z=6.0
	sim.doctrine.time_to_dominate.entry.observed=true
	advance(helper,sim)
	var row: Dictionary = helper.snapshot().raised.time_to_dominate
	check(row.value==4.0*STEP and row.tick==4 and row.time==4.0*STEP and helper.snapshot().a.time_to_dominate.value==null,"Delayed door observation publishes the captured target floor and actual completion clock despite later own movement")
	# Mixed-floor participants cannot safely name a room for this timer.
	helper.reset(data)
	sim=Facts.new(data)
	known(sim,"a")
	known(sim,"raised")
	sim.units[0].base_height=3.0
	sim.units.append({"id":"bravo","x":5.0,"z":2.0,"hp":100.0,"base_height":0.0,"commands":[]})
	sim.doctrine.time_to_dominate.entry={"room_id":"a","opened_at":0.0,"participants":["alpha","bravo"],"arrived":["alpha","bravo"],"targets":{"alpha":[5.0,2.0],"bravo":[5.0,2.0]},"seconds":STEP,"observed":true}
	advance(helper,sim)
	check(helper.snapshot().a.time_to_dominate.value==null and helper.snapshot().raised.time_to_dominate.value==null,"Inconsistent participant and door floors leave the timer N/A instead of exposing another floor")
	# Manual funnel fallback must also reject P0's overlapping lower room.
	helper.reset(data)
	sim=Facts.new(data)
	known(sim,"a")
	known(sim,"raised")
	sim.units[0].base_height=3.0
	sim.units[0].z=2.9
	sim.doctrine.time_to_dominate.entry={"room_id":"a","opened_at":0.0,"participants":["alpha"],"arrived":[],"seconds":-1.0,"observed":false}
	advance(helper,sim)
	check(helper.snapshot().a.doorway_dwell.value==null and helper.snapshot().raised.doorway_dwell.value==STEP,"Manual funnel fallback checks authored room, own and door floor agreement")

func _repeat(seed_value: int) -> String:
	var helper := RoomDoctrine.new()
	helper.reset(mission())
	var sim := Facts.new(mission())
	sim.rng.seed=seed_value
	var rng_state: int = sim.rng.state
	known(sim,"a")
	var context := fact(0)
	context.merge({"sync_id":"drill","door_id":"entry","unit_ids":["alpha"],"command_ids":["alpha-0001"],"observed_enemies":[{"id":"enemy_secret","status":"IDLE","awareness_state":["UNAWARE","SUSPICIOUS","IDENTIFIED"][seed_value%3],"door_ready":false}]})
	helper.record_stack(context)
	advance(helper,sim,4)
	check(helper.snapshot().a.stealth.value==seed_value%3,"All three stealth categories preserve observed-only preparation evidence")
	check(sim.rng.state==rng_state,"Instrumentation never advances the fixed-seed gameplay stream")
	return JSON.stringify(helper.snapshot())

func _projection_ownership() -> void:
	var helper := RoomDoctrine.new()
	helper.reset(mission())
	var sim := Facts.new(mission())
	known(sim,"a","UNKNOWN",0)
	advance(helper,sim,3)
	check(helper.snapshot().a.marked.tick==1 and helper.snapshot().a.marked.time==STEP,"A known UNKNOWN zero marker receives its first actual observation proof rather than a synthetic pre-observation clock")
	var record := {"room_doctrine":helper.snapshot(),"result":{"success":false,"room_doctrine":helper.snapshot()}}
	var bytes := JSON.stringify(record)
	var observed: Dictionary = record.duplicate(false)
	Metrics.filter_observed_statistics(observed)
	observed.room_doctrine.a.marked.value=99
	observed.result.room_doctrine.a.marked.value=99
	check(JSON.stringify(record)==bytes,"Both top-level and nested-result observed maps are detached from paired recording ownership")
	var legacy := {"time":0.0,"result":{}}
	bytes=JSON.stringify(legacy)
	Metrics.filter_observed_statistics(legacy)
	check(JSON.stringify(legacy)==bytes,"Legacy absent maps and empty result retain their exact projection shape")
