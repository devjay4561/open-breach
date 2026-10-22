extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Navigation = preload("res://scripts/navigation.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture(axis: String = "x", hinge: float = -1.0, swing: float = -1.0, side: float = -1.0) -> Dictionary:
	# P1 makes kicking probabilistic. This fixture measures successful leaf
	# damage and collision geometry; the doctrine suite covers probability.
	var door: Dictionary = {"id":"d1", "x":6.0, "z":6.0, "w":1.6 if axis == "x" else 0.24, "d":0.24 if axis == "x" else 1.6, "axis":axis, "state":"CLOSED", "hinge_side":hinge, "swing_sign":swing, "hp":100.0, "locked":false, "kick_resistance":1.0}
	var normal: Vector2 = Vector2.DOWN if axis == "x" else Vector2.RIGHT
	var origin: Vector2 = Door.handle_floor(door) + normal * side * Door.APPROACH_DISTANCE
	return {"id":"DOOR_REALISM", "seed":42, "bounds":[12,12], "walls":[], "props":[], "rooms":[], "doors":[door], "units":[{"id":"alpha", "x":origin.x, "z":origin.y, "facing":(-normal * side).angle(), "ammo":0, "breaches":2, "fov":360.0}], "enemies":[], "civilians":[], "win":[{"type":"reach_zone", "zone":[11,11,0.2,0.2]}]}

func simulation(data: Dictionary) -> RefCounted:
	var sim := Simulation.new()
	sim.load_mission(data)
	return sim

func advance(sim: RefCounted, frames: int = 240) -> void:
	for frame: int in range(frames):
		sim.step(STEP)
		if sim.units[0].commands.back().state in ["SUCCEEDED", "FAILED"]: return

func run() -> void:
	_fixed_hinges()
	_partial_observation()
	_partial_from_both_sides()
	_locked_and_destroyed()
	_cooperative_clearance()
	_injured_interaction()
	_enemy_door_operation()
	print("BREACH_DOOR_REALISM_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _fixed_hinges() -> void:
	for axis: String in ["x", "z"]:
		for hinge: float in [-1.0, 1.0]:
			for swing: float in [-1.0, 1.0]:
				for side: float in [-1.0, 1.0]:
					var sim: RefCounted = simulation(fixture(axis, hinge, swing, side))
					var door: Dictionary = sim.doors[0]
					var hinge_origin: Vector3 = Door.hinge_transform(door, 0.0).origin
					check(sim.issue("alpha", "OPEN_DOOR", {"door_id":"d1"}).ok, "Fixed door command accepted")
					var collided: bool = false
					var teleported: bool = false
					for frame: int in range(240):
						var before: Vector2 = sim._position(sim.units[0])
						sim.step(STEP)
						var after: Vector2 = sim._position(sim.units[0])
						collided = collided or Door.overlaps_actor(door, -1.0, after, Navigation.RADIUS)
						teleported = teleported or before.distance_to(after) > 0.081
						if sim.units[0].commands[0].state in ["SUCCEEDED", "FAILED"]: break
					check(sim.units[0].commands[0].state == "SUCCEEDED" and door.state == "OPEN", "Door opens from either side with authored hinge")
					check(float(door.swing_sign) == swing and float(door.hinge_side) == hinge, "Operator never flips hinge or opening direction")
					check(Door.hinge_transform(door, 1.0).origin.is_equal_approx(hinge_origin), "Opening retains fixed hinge anchor")
					check(not collided, "Swept leaf never overlaps its operator")
					check(not teleported, "Operator clearance is continuous floor movement")

func _partial_observation() -> void:
	var data: Dictionary = fixture()
	data.walls = [{"x":2.55, "z":6.0, "w":5.3, "d":0.2}, {"x":9.45, "z":6.0, "w":5.3, "d":0.2}]
	var sim: RefCounted = simulation(data)
	var unit: Dictionary = sim.units[0]
	var door: Dictionary = sim.doors[0]
	check(not sim.can_see(unit, {"x":6.65, "z":8.0}), "Closed physical leaf blocks the opposite room")
	check(sim.issue("alpha", "PEEK_DOOR", {"door_id":"d1"}).ok, "Partial observation command accepted")
	var observing: bool = false
	for frame: int in range(180):
		sim.step(STEP)
		if float(unit.get("_peek_remaining", 0.0)) > 0.0:
			observing = true
			break
	check(observing and door.state == "AJAR", "Observation starts only after a real partial opening")
	check(float(door.progress) > 0.22 and float(door.progress) < 1.0, "Peek keeps an actual partially rotated leaf")
	var origin: Vector2 = sim._point(unit.get("_peek_origin", [unit.x, unit.z]))
	var body: Vector2 = sim._position(unit)
	check(origin.distance_to(body) <= 0.161 and sim.nav.segment_clear(body, origin), "Peek eye point is a short reachable lean")
	check((origin.y - 6.0) * (body.y - 6.0) > 0.0, "Peek sensor never crosses the door plane")
	var leaf: Dictionary = Door.leaf_obstacle(door)
	var through_leaf: Vector2 = origin + (Vector2(leaf.x, leaf.z) - origin) * 2.0
	check(not sim.can_see(unit, {"x":through_leaf.x, "z":through_leaf.y}), "Peek cannot see through the opaque remainder of the leaf")
	var visible_gap: bool = false
	for x: float in [6.55, 6.6, 6.65, 6.7, 6.75]:
		visible_gap = visible_gap or sim.can_see(unit, {"x":x, "z":8.0})
	check(visible_gap, "Targets visible through the actual latch gap can be observed")
	advance(sim)
	check(unit.commands[0].state == "SUCCEEDED" and float(unit._peek_remaining) <= 0.0, "Peek finishes and releases its temporary observation")
	check(door.state == "AJAR" and str(door.owner_id).is_empty(), "Partial leaf remains physical after ownership releases")
	check(sim.issue("alpha", "OPEN_DOOR", {"door_id":"d1"}, false).ok, "Partial door can be opened normally afterward")
	advance(sim)
	check(unit.commands.back().state == "SUCCEEDED" and door.state == "OPEN", "Partial observation does not strand subsequent door commands")

func _locked_and_destroyed() -> void:
	var data: Dictionary = fixture()
	data.doors[0].locked = true
	for type: String in ["OPEN_DOOR", "PEEK_DOOR"]:
		var sim: RefCounted = simulation(data)
		var answer: Dictionary = sim.issue("alpha", type, {"door_id":"d1"})
		if answer.ok: advance(sim)
		check(not answer.ok or sim.units[0].commands[0].state == "FAILED", "Locked door rejects ordinary open and peek")
		check(sim.doors[0].state == "CLOSED" and is_zero_approx(float(sim.doors[0].progress)), "Locked interaction never creates a sensor aperture")
	var kicked: RefCounted = simulation(data)
	check(kicked.issue("alpha", "KICK_DOOR", {"door_id":"d1"}).ok, "Forced opening of locked door accepted")
	advance(kicked)
	check(kicked.doors[0].state == "OPEN" and not bool(kicked.doors[0].locked), "Kick forces the lock and opens the authored leaf")
	check(float(kicked.doors[0].hp) == 35.0 and not bool(kicked.doors[0].get("destroyed", false)), "Kick damages an intact leaf")
	check(not Door.leaf_obstacle(kicked.doors[0]).is_empty(), "Damaged open leaf still collides")
	var breached: RefCounted = simulation(data)
	check(breached.issue("alpha", "BREACH_DOOR", {"door_id":"d1"}).ok, "Destructive breach accepted")
	advance(breached)
	var door: Dictionary = breached.doors[0]
	check(door.state == "OPEN" and bool(door.destroyed) and float(door.hp) == 0.0, "Breach destroys the leaf and opens passage")
	check(int(breached.units[0].breaches) == 1 and breached.breaches_used == 1, "Destructive action consumes exactly one charge")
	check(Door.leaf_obstacle(door).is_empty(), "Destroyed leaf no longer supplies an invisible collision obstacle")
	check(breached.nav.segment_clear(Vector2(6,5), Vector2(6,7), Navigation.RADIUS), "Destroyed doorway permits movement through its opening")
	check(is_equal_approx(Door.ray_distance(door, Vector2(6,5), Vector2.DOWN, 5.0), 5.0), "Destroyed leaf never occludes sight")
	check(breached.events.any(func(event: Dictionary) -> bool: return event.type == "DOOR_DESTROYED"), "Destruction is represented explicitly in replay events")
	data.doors[0].hp = 30.0
	var weak: RefCounted = simulation(data)
	weak.issue("alpha", "KICK_DOOR", {"door_id":"d1"})
	advance(weak)
	check(bool(weak.doors[0].destroyed), "A sufficiently damaged leaf can break under forced opening")

func _partial_from_both_sides() -> void:
	for side: float in [-1.0, 1.0]:
		var sim: RefCounted = simulation(fixture("x", -1.0, -1.0, side))
		var unit: Dictionary = sim.units[0]
		var body_side: float = float(unit.z) - 6.0
		check(sim.issue("alpha", "PEEK_DOOR", {"door_id":"d1"}).ok, "Physical peek accepted from either side")
		var observing: bool = false
		for frame: int in range(240):
			sim.step(STEP)
			if float(unit.get("_peek_remaining", 0.0)) > 0.0:
				observing = true
				break
		var origin: Vector2 = sim._point(unit.get("_peek_origin", [unit.x,unit.z]))
		check(observing and sim.doors[0].state == "AJAR", "Fixed partial leaf can be observed from both sides")
		check((origin.y - 6.0) * body_side > 0.0 and origin.distance_to(sim._position(unit)) <= 0.161, "Either approach keeps the eye on its physical side")
		advance(sim)
		sim.issue("alpha", "OPEN_DOOR", {"door_id":"d1"}, false)
		advance(sim)
		check(unit.commands.back().state == "SUCCEEDED" and sim.doors[0].state == "OPEN", "The retreating peek operator can subsequently open the door")

func _cooperative_clearance() -> void:
	for held: bool in [false, true]:
		var data: Dictionary = fixture()
		var future: Dictionary = Door.leaf_obstacle(data.doors[0], 0.65)
		data.units.append({"id":"bravo", "x":future.x, "z":future.z, "ammo":0, "hold_position":held})
		var sim: RefCounted = simulation(data)
		var initial: Vector2 = sim._position(sim.units[1])
		sim.issue("alpha", "OPEN_DOOR", {"door_id":"d1"})
		var overlapping: bool = false
		for frame: int in range(180):
			sim.step(STEP)
			for actor: Dictionary in sim.units:
				overlapping = overlapping or Door.overlaps_actor(sim.doors[0], -1.0, sim._position(actor), Navigation.RADIUS)
		check(not overlapping, "Cooperative door clearance preserves all actor and leaf separation")
		if held:
			check(sim._position(sim.units[1]).is_equal_approx(initial), "Explicit position hold is never overridden for door clearance")
			check(sim.doors[0].state == "OPENING" and bool(sim.doors[0].blocked), "Door waits safely for an explicitly held bystander")
			sim.units[1].hold_position = false
			advance(sim)
			check(sim.doors[0].state == "OPEN", "Releasing the hold lets blocked door clearance recover")
		else:
			check(sim._position(sim.units[1]).distance_to(initial) > 0.05, "Idle squadmate steps out of a future door arc")
			check(sim.doors[0].state == "OPEN" and sim.command_failures == 0, "An idle squadmate no longer strands the door operator")

func _injured_interaction() -> void:
	for type: String in ["OPEN_DOOR", "PEEK_DOOR", "BREACH_DOOR"]:
		var healthy: RefCounted = simulation(fixture())
		var injured: RefCounted = simulation(fixture())
		injured.units[0].hp = 20.0
		healthy.issue("alpha", type, {"door_id":"d1"})
		injured.issue("alpha", type, {"door_id":"d1"})
		advance(healthy)
		advance(injured)
		check(healthy.units[0].commands.back().state == "SUCCEEDED" and injured.units[0].commands.back().state == "SUCCEEDED", "Door interaction remains possible when injured")
		check(injured.time > healthy.time, "Injury affects door interaction duration for " + type)

func _enemy_door_operation() -> void:
	for side: float in [-1.0, 1.0]:
		var data: Dictionary = fixture("x", -1.0, -1.0, side)
		data.units[0].x = 10.0
		data.units[0].z = 10.0
		data.enemies = [{"id":"e1", "x":6.544, "z":6.0 + side * 2.0, "ammo":0}]
		var sim: RefCounted = simulation(data)
		var enemy: Dictionary = sim.enemies[0]
		var door: Dictionary = sim.doors[0]
		var waypoint := Vector2(6.544, 6.0 - side * 2.0)
		var collided: bool = false
		for frame: int in range(300):
			sim.tick += 1
			sim.time += STEP
			sim._approach_enemy_route_door(enemy, waypoint, 1.4, STEP)
			sim._advance_doors(STEP)
			collided = collided or Door.overlaps_actor(door, -1.0, sim._position(enemy), Navigation.RADIUS)
			if door.state == "OPEN": break
		check(door.state == "OPEN" and float(door.swing_sign) == -1.0, "Enemy opens the same fixed door from either physical side")
		check(not collided, "Enemy door operator also clears the physical leaf sweep")
		data.doors[0].locked = true
		var locked: RefCounted = simulation(data)
		for frame: int in range(90):
			locked.tick += 1
			locked._approach_enemy_route_door(locked.enemies[0], waypoint, 1.4, STEP)
			locked._advance_doors(STEP)
		check(locked.doors[0].state == "CLOSED" and is_zero_approx(float(locked.doors[0].progress)), "Enemy does not magically operate a locked door")
