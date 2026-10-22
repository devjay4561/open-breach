extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Replay = preload("res://scripts/replay.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func fixture() -> Dictionary:
	return {"id":"M01","seed":42,"bounds":[32,24],"rooms":[],"walls":[],"doors":[],"props":[{"id":"cover","type":"crate","cover":"low","x":12,"z":10,"w":1.4,"d":1.4}],"units":[{"id":"alpha","x":2,"z":2,"facing":PI,"ammo":0}],"enemies":[{"id":"guard","x":12,"z":12,"facing":0,"response_role":"guard"},{"id":"reserve","x":17,"z":10,"facing":0,"response_role":"reserve"},{"id":"distant","x":29,"z":20,"facing":0}],"civilians":[],"win":[{"type":"reach_zone","zone":[30,2,1,1]}],"fail":[]}
func make(data: Dictionary) -> BreachSimulation:
	var sim := Simulation.new()
	sim.load_mission(data)
	return sim
func advance(sim: BreachSimulation, seconds: float) -> void:
	for i: int in range(roundi(seconds/STEP)): sim.step(STEP)
func position(actor: Dictionary) -> Vector2: return Vector2(actor.x, actor.z)
func run() -> void:
	var sim := make(fixture())
	var twin := make(fixture())
	var origin: Vector2 = position(sim.enemies[0])
	var support_origin: Vector2 = position(sim.enemies[1])
	for instance: BreachSimulation in [sim,twin]: instance._emit_sound(Vector2(6,10),14.0,"총성 감지","unit")
	check(sim.enemies[0]._alert_until > 0 and sim.enemies[1]._alert_until > 0,"Gunfire alerts nearby guards and reserves")
	check(sim.enemies[2]._alert_until == 0,"Distant enemies are not globally alerted")
	check(sim.snapshot().enemies.is_empty(),"Hearing does not reveal hidden enemy identities or positions")
	advance(sim,3.0)
	advance(twin,3.0)
	check(position(sim.enemies[0]).distance_to(origin)>0.2 and position(sim.enemies[0]).distance_to(origin)<7.0,"Guard moves to nearby cover rather than charging the sound")
	check(sim.enemies[0].get("_cover_target",[]).size()==2,"Guard selects a physical cover position")
	check(position(sim.enemies[1]).distance_to(Vector2(6,10)) < support_origin.distance_to(Vector2(6,10)),"A reserve element moves toward a support position")
	check(sim.enemies[0]._alert_action in ["guard","cover"] and sim.enemies[1]._alert_action=="support","Guard and support decisions are distinct")
	check(not sim.events.any(func(e: Dictionary)->bool:return e.type=="SHOT"),"An alert region never grants permission to shoot an unseen player")
	check(JSON.stringify(sim.snapshot(true))==JSON.stringify(twin.snapshot(true)),"Combat alert movement is deterministic")
	var memory: Array = sim.enemies[0]._alert_position.duplicate()
	sim.units[0].x=1;sim.units[0].z=21
	advance(sim,0.2)
	check(sim.enemies[0]._alert_position==memory,"Hidden player motion does not update remembered threat location")
	advance(sim,10.0)
	check(sim.enemies[0]._alert_position.is_empty(),"Unconfirmed combat alerts expire")
	# A local observation can inform an ally through a wall, without granting vision.
	var data:=fixture()
	data.props=[]
	data.units[0].x=4;data.units[0].z=6;data.units[0].facing=0
	data.enemies=[{"id":"spotter","x":8,"z":6,"facing":PI},{"id":"receiver","x":13,"z":6,"facing":0},{"id":"remote","x":29,"z":20,"facing":0}]
	data.walls=[{"x":10,"z":12,"w":0.3,"d":24}]
	sim=make(data)
	advance(sim,0.5)
	check(sim.enemies[1]._detect_reason=="report" and sim.enemies[1]._observed.is_empty(),"A nearby witness relays a contact region through a wall without relaying direct sight")
	check(sim.enemies[2]._alert_until==0,"Contact reports do not chain across the whole map")
	advance(sim,0.5)
	check(not sim.can_see(sim.enemies[1],sim.units[0]),"Alerted receiver still obeys walls and own vision cone")
	# Empty magazines recover in both difficulty levels.
	data=fixture();data.enemies[0].ammo=0
	sim=make(data);advance(sim,0.1)
	check(sim.enemies[0].status=="RELOADING","Normal guards reload rather than becoming inert")
	advance(sim,2.0);check(sim.enemies[0].ammo==sim.enemies[0].max_ammo,"Normal reload replenishes the real magazine")
	# Deliberate preparation should reduce risk under exactly matched seeds.
	var exposed_shots:=0
	var stunned_shots:=0
	for seed_value: int in range(12):
		for prepared: bool in [false,true]:
			data=fixture();data.seed=seed_value;data.props=[];data.win=[{"type":"neutralize_all"}]
			data.units=[{"id":"alpha","x":4,"z":6,"facing":0,"weapon":"standard"}]
			# P1 restores surrender. This paired experiment isolates return-fire
			# exposure and shotgun damage, so its combatant explicitly opts out.
			data.enemies=[{"id":"e1","x":8,"z":6,"facing":PI,"can_surrender":false}]
			sim=make(data)
			if prepared: sim.enemies[0].stunned=3.5
			advance(sim,5.0)
			for event: Dictionary in sim.events:
				if event.type=="SHOT" and bool(event.get("hostile",false)):
					if prepared: stunned_shots+=1
					else: exposed_shots+=1
			check(not sim.enemies[0].surrendered,"The explicit combat-only fixture never surrenders")
	check(exposed_shots>0 and stunned_shots<exposed_shots,"Prepared entry has lower return-fire exposure than a frontal encounter")
	data.units[0].weapon="shotgun";data.seed=42
	# Catalog shotgun acquisition is longer than the old common rifle timer;
	# a real enemy hit can also lower the weapon before it finishes acquiring.
	# Preserve the one-shot damage/ammo assertion after that bounded preparation.
	sim=make(data);advance(sim,1.2)
	check(sim.enemies[0].hp==0 and sim.units[0].ammo==7,"A close-range shotgun hit clears the ordinary health threshold after identification and acquisition")
	check(float(Simulation.WEAPONS.shotgun.range)<float(Simulation.WEAPONS.standard.range),"Shotgun retains a meaningful range tradeoff")
	for id: String in ["M04","M05","M06"]:
		data=Catalog.load(id)
		check(data.rooms.size()>=8 and data.enemies.size()>=8 and int(data.bounds[0])==32 and int(data.bounds[1])==32,id+": larger authored floor plan")
		check(bool(Catalog.validate_custom(data).get("ok",false)),id+": full geometry validation")
		sim=make(data)
		var record:=Replay.new();record.begin(data);record.capture(sim.snapshot(true))
		for i: int in range(150):sim.step(STEP);record.capture(sim.snapshot(true))
		var restored:=Replay.new()
		var restore_result: Dictionary = restored.load_data(record.export_data())
		check(bool(restore_result.get("ok",false)),id+": tactical movement and statuses round-trip through replay: "+str(restore_result.get("message", "")))
		check(sim.enemies.any(func(e: Dictionary)->bool:return float(e.travel_distance)>0.4),id+": patrols actually move before player input")
	# Returning through an open door must visit the actual corner waypoint.
	data=Catalog.load("M05");data.enemies=[];data.civilians=[]
	data.units=[{"id":"alpha","x":7.69765,"z":26.64975,"facing":0}]
	data.win=[{"type":"reach_zone","zone":[30,2,1,1]}]
	for door:Dictionary in data.doors:
		if door.id=="M05_d13":door.state="OPEN";door.swing_sign=-1.0
	sim=make(data)
	check(bool(sim.plan_move("alpha",{"target":[16,29]},false).get("ok",false)),"Door-jamb return route is accepted")
	advance(sim,10.0)
	check(position(sim.units[0]).distance_to(Vector2(16,29))<0.2 and sim.command_failures==0,"A unit does not cut a corner and become stuck at the exit")
	data.units[0].x=16;data.units[0].z=29
	data.civilians=[{"id":"escort","x":7.69765,"z":26.64975}]
	sim=make(data);sim.civilians[0].secured=true;sim.civilians[0].follow_unit_id="alpha"
	advance(sim,10.0)
	check(position(sim.civilians[0]).distance_to(Vector2(15,29))<0.3,"An escorted civilian can follow the same exit corner")
	print("BREACH_TACTICAL_RESPONSE_RESULT checks=%d failures=%d"%[checks,failures.size()])
	for failure: String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
