extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Door = preload("res://scripts/door_geometry.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(axis: String = "x", closed: bool = false) -> Dictionary:
	var data := {"id":"DOOR_TRAFFIC", "seed":51, "bounds":[12,12], "walls":[{"x":2.5,"z":6,"w":5,"d":0.2},{"x":9.5,"z":6,"w":5,"d":0.2}], "props":[], "doors":[{"id":"d1","x":6,"z":6,"axis":"x","w":2,"d":0.2,"state":"CLOSED" if closed else "OPEN"}], "rooms":[], "units":[], "enemies":[], "civilians":[], "win":[{"type":"reach_zone","zone":[11,11,0.2,0.2]}], "fail":[]}
	# The front operator sorts last by ID; a faster follower must not overtake.
	for index: int in range(4):
		data.units.append({"id":["delta","charlie","bravo","alpha"][index],"x":6.0,"z":8.0+index*0.75,"ammo":0})
	if axis == "z":
		for actor: Dictionary in data.units + data.walls:
			var old_x: float = actor.x
			actor.x = actor.z
			actor.z = old_x
			if actor.has("w"):
				var old_w: float = actor.w
				actor.w = actor.d
				actor.d = old_w
		data.doors[0].axis = "z"
		data.doors[0].w = 0.2
		data.doors[0].d = 2.0
	return data

func simulation(data: Dictionary) -> RefCounted:
	var sim := Simulation.new()
	sim.load_mission(data)
	for actor: Dictionary in sim.units + sim.enemies + sim.civilians:
		actor.ammo = 0
		actor.reserve_ammo = 0
	return sim

func run() -> void:
	for axis: String in ["x", "z"]:
		for closed: bool in [false, true]: _squad_queue(axis, closed)
	_corpses()
	_dead_reservation()
	_idle_escort_reservation()
	_queue_casualty()
	_flash_operator()
	_contended_portal()
	_chained_doors()
	_idle_portal()
	_house_escort()
	print("BREACH_DOOR_TRAFFIC_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _squad_queue(axis: String, closed: bool) -> void:
	var sim := simulation(fixture(axis, closed))
	var normal := Vector2.DOWN if axis == "x" else Vector2.RIGHT
	var label := "%s/%s" % [axis, "closed" if closed else "open"]
	for index: int in range(4):
		sim.units[index].movement_mode = "careful" if index == 0 else "fast"
		var target := Vector2(6, 3.0-index*0.65) if axis == "x" else Vector2(3.0-index*0.65, 6)
		check(bool(sim.plan_move(str(sim.units[index].id), {"target":[target.x,target.y]}).ok), label + " accepts squad move")
	var crossings: Array[String] = []
	var reversals := 0
	var safe := true
	var completed := false
	for frame: int in range(900):
		var before: Array = sim.units.map(func(actor: Dictionary) -> Vector2: return sim._position(actor))
		sim.step(STEP)
		completed = true
		for index: int in range(4):
			var unit: Dictionary = sim.units[index]
			var position: Vector2 = sim._position(unit)
			if (before[index]-Vector2(6,6)).dot(normal)>0 and (position-Vector2(6,6)).dot(normal)<=0: crossings.append(str(unit.id))
			if not closed and before[index].distance_to(Vector2(6,6))<3.0 and (position-before[index]).dot(normal)>0.002: reversals += 1
			for other: int in range(index): safe = safe and position.distance_to(sim._position(sim.units[other])) >= Navigation.RADIUS*2.0-0.00001
			completed = completed and unit.commands.back().state == "SUCCEEDED"
		if completed or sim.command_failures>0: break
	print("DOOR_TRAFFIC %s time=%.2f crossings=%s reversals=%d completed=%s" % [label,sim.time,crossings,reversals,completed])
	check(completed and sim.command_failures == 0, label + " completes all four movements")
	check(crossings == ["delta","charlie","bravo","alpha"], label + " respects physical front-to-back order")
	check(reversals == 0, label + " queue does not bounce backward and forward")
	check(safe, label + " never overlaps living operators")
	check(sim._reservations.is_empty(), label + " releases passage when finished")

func _corpses() -> void:
	for kind: String in ["units","enemies","civilians"]:
		var data := fixture()
		data.units = [data.units[0]]
		data[kind].append({"id":"corpse","x":6.0,"z":6.0,"hp":0,"ammo":0})
		var sim := simulation(data)
		sim.plan_move("delta", {"target":[6,3]})
		var crossed_body := false
		for frame: int in range(450):
			sim.step(STEP)
			crossed_body = crossed_body or sim._position(sim.units[0]).distance_to(Vector2(6,6))<0.15
			if sim.units[0].commands.back().state == "SUCCEEDED": break
		check(crossed_body and sim.units[0].commands.back().state == "SUCCEEDED", "Can step directly over dead " + kind + " in the doorway")

func _dead_reservation() -> void:
	var data := fixture()
	data.units = [data.units[0], {"id":"corpse","x":6.0,"z":6.0,"hp":0,"ammo":0}]
	var sim := simulation(data)
	sim._reservations["d1"] = "corpse"
	sim.units[1]["_movement_wait_door"] = "d1"
	sim.plan_move("delta", {"target":[6,3]})
	for frame: int in range(450):
		sim.step(STEP)
		if sim.units[0].commands.back().state == "SUCCEEDED": break
	check(sim.units[0].commands.back().state == "SUCCEEDED" and sim._reservations.is_empty(), "Dead passage owner cannot block a surviving operator")

func _idle_escort_reservation() -> void:
	var data := fixture()
	data.units = [{"id":"delta","x":6,"z":5.9,"facing":-PI/2,"ammo":0}]
	data.enemies = [{"id":"corpse","x":6,"z":6,"hp":0}]
	data.civilians = [{"id":"c1","x":6,"z":6.9}]
	var sim := simulation(data)
	sim.civilians[0].secured = true
	sim.civilians[0].follow_unit_id = "delta"
	sim.units[0].move_facing = -PI/2
	# The follower reached its one-metre spacing while still in the portal.
	sim._reservations["d1"] = "c1"
	sim.issue("delta", "MOVE", {"target":[6,3]})
	for frame: int in range(450): sim.step(STEP)
	check(sim.units[0].commands[0].state == "SUCCEEDED", "An escort follower resting behind its leader releases its passage reservation")
	check(float(sim.civilians[0].z)<4.3, "Civilian follows its leader over a corpse instead of freezing both in the doorway")

func _queue_casualty() -> void:
	var sim := simulation(fixture())
	for index: int in range(4): sim.issue(str(sim.units[index].id), "MOVE", {"target":[6,3-index*0.65]})
	for frame: int in range(15): sim.step(STEP)
	sim.units[0].hp = 0.0
	for frame: int in range(600): sim.step(STEP)
	check(sim.units.slice(1).all(func(unit: Dictionary) -> bool: return unit.commands[0].state == "SUCCEEDED"), "Queue continues after the leading operator dies")
	check(sim._movement_door_queues.is_empty(), "Finished queue retains no casualty or completed tickets")

func _flash_operator() -> void:
	var sim := simulation(fixture("x", true))
	check(bool(sim.issue("alpha", "OPEN_AND_FLASH", {"door_id":"d1","target":[6,3]}).ok), "Designated rear operator accepts door and flash command")
	for index: int in range(4): sim.plan_move(str(sim.units[index].id), {"target":[6,3-index*0.65]})
	for frame: int in range(900): sim.step(STEP)
	check(sim.units.all(func(unit: Dictionary) -> bool: return unit.commands.back().state == "SUCCEEDED"), "Designated flash operator and all followers pass without a queue/barrier deadlock")
	check(sim.stuns_used == 1 and sim.command_failures == 0, "Door and flash still throws exactly once without failure")

func _house_escort() -> void:
	var data := Catalog.load("M01_ESCORT")
	data.win = [{"type":"reach_zone","zone":[22,2,0.2,0.2]}]
	data.fail = []
	for enemy: Dictionary in data.enemies: enemy.hp = 0.0
	for door: Dictionary in data.doors:
		door.state = "OPEN"
		door.progress = 1.0
	var sim := simulation(data)
	var starts: Array = [[12,8.5],[13,7.5],[11.8,6.7],[13,6.5]]
	for index: int in range(4): sim._set_position(sim.units[index], sim._point(starts[index]))
	sim._set_position(sim.enemies[0], Vector2(12,10))
	sim._set_position(sim.civilians[0], Vector2(12,7.5))
	sim._set_position(sim.civilians[1], Vector2(13,8.5))
	for index: int in range(2):
		sim.civilians[index].secured = true
		sim.civilians[index].follow_unit_id = str(sim.units[index].id)
	var targets: Array = [[11.2,19.5],[12.2,19.5],[13.2,19.5],[14.2,19.5]]
	for index: int in range(4):
		var answer: Dictionary = sim.plan_move(str(sim.units[index].id), {"target":targets[index]})
		check(bool(answer.ok), "House escort accepts extraction route: " + str(answer))
	for frame: int in range(1200): sim.step(STEP)
	print("HOUSE_ESCORT units=%s civilians=%s" % [sim.units.map(func(unit: Dictionary) -> Array: return [unit.id,unit.x,unit.z,sim._active(unit).get("reason", "")]),sim.civilians.map(func(actor: Dictionary) -> Array: return [actor.id,actor.x,actor.z,actor.status])])
	check(sim.units.all(func(unit: Dictionary) -> bool: return not unit.commands.is_empty() and unit.commands.back().state == "SUCCEEDED"), "All four operators extract across the real house with a dead enemy in the study door")
	check(sim.civilians.all(func(actor: Dictionary) -> bool: return float(actor.z)>17.5), "Both escorted civilians step over the dead enemy and leave the house")
	check(sim.command_failures == 0, "House escort completes without a movement failure")

func _contended_portal() -> void:
	var data := fixture()
	data.doors[0].w = 1.8
	data.doors[0].state = "CLOSED"
	data.doors[0].swing_sign = 1.0
	data.rooms = [{"id":"room","x":6,"z":3.5,"w":5,"d":5,"indoor":true},{"id":"outside","x":6,"z":9,"w":12,"d":6,"indoor":false}]
	data.walls.append_array([{"x":3.5,"z":3.5,"w":0.2,"d":5},{"x":8.5,"z":3.5,"w":0.2,"d":5},{"x":6,"z":1,"w":5,"d":0.2}])
	var starts: Array = [[7.3,6.45],[4.7,6.45],[7.3,7.15],[4.7,7.15]]
	var sim := simulation(data)
	for index: int in range(4): sim._set_position(sim.units[index],sim._point(starts[index]))
	var order: Array = sim.units.map(func(unit: Dictionary) -> String: return str(unit.id))
	check(bool(sim.plan_room_entry("d1","OPEN_DOOR",order,{}).ok), "Portal contention drill is accepted")
	var maximum := 0
	var approaches := 0
	var complete := false
	var physical_clear := true
	var crossings: Array = []
	var portal := Door.funnel_rect(sim.doors[0],float(sim.doors[0].d)*0.5).grow(Navigation.RADIUS)
	var approach := Door.funnel_rect(sim.doors[0],1.0).grow(Navigation.RADIUS)
	for frame: int in range(900):
		var before: Array = sim.units.map(func(unit: Dictionary) -> Vector2: return sim._position(unit))
		sim.step(STEP)
		var occupants := 0
		var entering := 0
		for index: int in range(sim.units.size()):
			var unit: Dictionary = sim.units[index]
			var here: Vector2 = sim._position(unit)
			if before[index].y>=6.0 and here.y<6.0: crossings.append(str(unit.id))
			physical_clear = physical_clear and sim.nav.segment_clear(before[index],here,Navigation.RADIUS) and not Door.overlaps_actor(sim.doors[0],-1.0,here,Navigation.RADIUS)
			for other: int in range(index): physical_clear = physical_clear and here.distance_to(sim._position(sim.units[other]))>=sim._movement_body_spacing()-0.00001
			var stage := str(sim._active(unit).get("args",{}).get("drill",{}).get("stage",""))
			if stage in ["entry","domination"] and portal.has_point(sim._position(unit)): occupants += 1
			if stage in ["entry","domination"] and before[index].y>=6.0 and approach.has_point(sim._position(unit)) and before[index].distance_to(sim._position(unit))>0.0001: entering += 1
		maximum = maxi(maximum, occupants)
		approaches = maxi(approaches,entering)
		complete = sim.units.all(func(unit: Dictionary) -> bool: return sim._active(unit).is_empty())
		if complete or sim.command_failures>0: break
	print("PORTAL_CONTENTION maximum=%d simultaneous_approaches=%d complete=%s time=%.2f" % [maximum,approaches,complete,sim.time])
	# A wide portal admits the same ordered cohort concurrently. Physical
	# spacing and actual plane crossings enforce safety, not one-slot occupancy.
	check(maximum>1 and approaches>1,"A wide portal lets the ordered cohort approach and pass concurrently")
	check(physical_clear,"Concurrent entry preserves full body spacing, walls and the physical door leaf on every STEP")
	check(crossings==order,"Concurrent approaches retain the requested actual door-plane crossing order")
	check(complete and sim.command_failures == 0,"All four complete their ordered doorway entry")

func _chained_doors() -> void:
	var data := fixture("x",true)
	data.doors.append({"id":"d2","x":6,"z":3,"axis":"x","w":2,"d":0.2,"state":"CLOSED"})
	data.walls.append_array([{"x":2.5,"z":3,"w":5,"d":0.2},{"x":9.5,"z":3,"w":5,"d":0.2}])
	var sim := simulation(data)
	for index: int in range(4): check(bool(sim.plan_move(str(sim.units[index].id),{"target":[4.8+index*0.8,1.5]}).ok), "Two-door squad route is accepted")
	var maximum := 0
	var reversals := 0
	var complete := false
	var portal := Door.funnel_rect(sim.doors[0],float(sim.doors[0].d)*0.5).grow(Navigation.RADIUS)
	for frame: int in range(1200):
		var before: Array = sim.units.map(func(unit: Dictionary) -> Vector2: return sim._position(unit))
		sim.step(STEP)
		var occupants := 0
		for index: int in range(4):
			var position: Vector2 = sim._position(sim.units[index])
			if portal.has_point(position): occupants += 1
			if sim.doors[0].state == "OPEN" and before[index].distance_to(Vector2(6,6))<1.5 and position.y-before[index].y>0.002: reversals += 1
		maximum = maxi(maximum,occupants)
		complete = sim.units.all(func(unit: Dictionary) -> bool: return not unit.commands.is_empty() and unit.commands.back().state == "SUCCEEDED")
		if complete or sim.command_failures>0: break
	print("CHAINED_DOORS maximum=%d reversals=%d complete=%s time=%.2f" % [maximum,reversals,complete,sim.time])
	check(maximum == 1 and reversals == 0, "Opening a later door still keeps the first portal exclusive without backing up")
	check(complete and sim.command_failures == 0, "All four complete the consecutive door route")

func _idle_portal() -> void:
	var data := fixture()
	data.units = [data.units[0],{"id":"idle","x":6.7,"z":6,"ammo":0}]
	var sim := simulation(data)
	sim.issue("delta","MOVE",{"target":[6,3]})
	var portal := Door.funnel_rect(sim.doors[0],float(sim.doors[0].d)*0.5).grow(Navigation.RADIUS)
	var maximum := 0
	for frame: int in range(450):
		sim.step(STEP)
		maximum = maxi(maximum,sim.units.filter(func(unit: Dictionary) -> bool: return portal.has_point(sim._position(unit))).size())
	check(sim.units[0].commands[0].state == "SUCCEEDED", "An idle teammate clears the portal instead of holding the exclusive slot forever")
	check(maximum == 1 and sim.command_failures == 0, "Idle teammate clearance preserves exclusive doorway occupancy")
