extends SceneTree
## Real authored passages, four-body movement and observed civilian following.
const Catalog = preload("res://scripts/mission_catalog.gd")
const Simulation = preload("res://scripts/simulation.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func point(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x),float(actor.z))

func issue(sim: RefCounted, id: String, type: String, args: Dictionary) -> void:
	var response: Dictionary = sim.issue(id,type,args)
	check(bool(response.get("ok",false)),type+": "+str(response.get("message","")))

func finish_commands(sim: RefCounted, ids: Array) -> bool:
	for tick in range(1500):
		var pending := false
		for unit: Dictionary in sim.units:
			if not ids.has(str(unit.id)): continue
			for command: Dictionary in unit.commands:
				if str(command.state) == "FAILED":
					check(false,str(unit.id)+": "+str(command))
					return false
				if str(command.state) in ["PENDING","RUNNING","WAITING"]: pending = true
		if not pending: return true
		sim.step(STEP)
	check(false,"Authored narrow passage commands timed out")
	return false

func _run() -> void:
	var mission := Catalog.load("H03")
	check(int(mission.revision) == 2,"Quiet Lantern uses the compact revision")
	check(mission.units.size() == 4 and mission.enemies.size() == 5 and mission.civilians.size() == 4,"Combat and rescue roster retained")
	var ids: Array = mission.units.map(func(unit: Dictionary) -> String: return str(unit.id))
	# Isolate geometry from combat randomness, retaining real doors, furniture,
	# actors and observed contacts. This fixture does not claim mission victory.
	var fixture: Dictionary = mission.duplicate(true)
	fixture.enemies = []
	fixture.win = [{"type":"reach_zone","zone":[40.0,1.0,0.2,0.2]}]
	fixture.fail = []
	var sim := Simulation.new()
	sim.load_mission(fixture)
	issue(sim,ids[0],"OPEN_DOOR",{"door_id":"front_railing_d0"})
	issue(sim,ids[0],"OPEN_DOOR",{"door_id":"embassy_s_d0"})
	issue(sim,ids[0],"MOVE",{"target":[21.0,24.8]})
	if finish_commands(sim,[ids[0]]):
		check(point(sim.units[0]).distance_to(Vector2(21,24.8))<0.15,"Actual operator opens the gate and entrance, then reaches the hall")
	for i in range(ids.size()): issue(sim,ids[i],"MOVE",{"target":[21.0,18.8+i*1.8]})
	if finish_commands(sim,ids):
		print("QUIET_LANTERN_HALL_POSITIONS ",JSON.stringify(sim.units.map(func(unit: Dictionary) -> Dictionary: return {"id":unit.id,"x":unit.x,"z":unit.z,"status":unit.status})))
		for i in range(ids.size()):
			check(point(sim.units[i]).distance_to(Vector2(21,18.8+i*1.8))<0.15,"All four physical operators pass the real entrance: "+str(ids[i]))
	issue(sim,ids[0],"OPEN_DOOR",{"door_id":"hall_west_d0"})
	issue(sim,ids[0],"MOVE",{"target":[19.5,8.5]})
	if finish_commands(sim,[ids[0]]):
		var observed: Array = sim.snapshot(false).civilians.filter(func(actor: Dictionary) -> bool: return str(actor.id)=="c4" and bool(actor.get("visible",false)))
		check(observed.size()==1,"Civilian is physically observed before securing")
		if observed.size()==1:
			var origin := point(observed[0])
			issue(sim,ids[0],"SECURE_CIVILIAN",{"civilian_id":"c4"})
			if finish_commands(sim,[ids[0]]):
				issue(sim,ids[0],"OPEN_DOOR",{"door_id":"embassy_n_d0"})
				issue(sim,ids[0],"MOVE",{"target":[21.0,4.3]})
				if finish_commands(sim,[ids[0]]):
					var rescued: Dictionary = sim.civilians.filter(func(actor: Dictionary) -> bool: return str(actor.id)=="c4")[0]
					check(bool(rescued.secured) and str(rescued.follow_unit_id)==str(ids[0]),"Secured civilian retains the real escort")
					check(point(rescued).distance_to(origin)>2 and point(rescued).distance_to(point(sim.units[0]))<3,"Civilian actually follows through the store door, corridor and rear door")
	print("BREACH_QUIET_LANTERN_MAP_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
