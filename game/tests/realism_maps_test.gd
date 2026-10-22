extends SceneTree
## Authoring invariants and public-command traversal on every new floor plan.
## Combat difficulty is exercised by the separate sustained/combat suites.
const Catalog = preload("res://scripts/mission_catalog.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.x), float(actor.z))

func room_sample(nav: RefCounted, room: Dictionary, opened: Array) -> Vector2:
	var center := Vector2(float(room.x), float(room.z))
	for offset: Vector2 in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1,-1), Vector2(1,1)]:
		var point: Vector2 = center + offset
		if nav.walkable(point, opened): return point
	return center

func run() -> void:
	var seen_layouts: Dictionary = {}
	var seen_objectives: Dictionary = {}
	for id: String in ["M07", "M08", "M09"]:
		var source: Dictionary = Catalog.load(id)
		check(not source.is_empty() and source.id == id, id+": playable catalog identity")
		check(source.units.size() == 4 and source.enemies.size() >= 8, id+": complete squad and opposing cast")
		check(source.rooms.size() >= 7 and source.doors.size() >= 8, id+": connected authored interiors")
		var answer: Dictionary = Catalog.validate_custom(source)
		check(bool(answer.get("ok",false)), id+": full schema and geometry: "+str(answer.get("message","")))
		var layout: int = hash([source.rooms,source.walls,source.props])
		check(not seen_layouts.has(layout), id+": structurally different floor plan")
		seen_layouts[layout] = true
		var objectives: String = JSON.stringify(source.win)
		check(not seen_objectives.has(objectives), id+": distinct objective combination")
		seen_objectives[objectives] = true
		for room: Dictionary in source.rooms:
			check(room.has("lighting") and room.has("indoor") and room.has("floor_surface"), id+": authored room environment "+str(room.id))
		for enemy: Dictionary in source.enemies:
			check(enemy.spawns.size() >= 2 and Vector2(float(enemy.spawns[0].x),float(enemy.spawns[0].z)).distance_to(Vector2(float(enemy.spawns[1].x),float(enemy.spawns[1].z))) > 0.5, id+": meaningful bounded spawn alternative "+str(enemy.id))
		for door: Dictionary in source.doors:
			check(door.has("hinge_side") and door.has("swing_sign") and door.has("locked"), id+": authored physical door "+str(door.id))
		# Preserve geometry, exercise actual MOVE execution with a single actor.
		# Opening all leaves isolates each floor plan's travel correctness from AI.
		var traverse: Dictionary = source.duplicate(true)
		traverse.units = [source.units[0].duplicate(true)]
		traverse.enemies = []
		traverse.civilians = []
		traverse.win = [{"type":"reach_zone","zone":[31,31,0.5,0.5]}]
		traverse.fail = []
		for door: Dictionary in traverse.doors:
			door.state = "OPEN"
			door.locked = false
			door.erase("initial_states")
		var sim := Simulation.new()
		sim.load_mission(traverse)
		var opened: Array = sim.doors.map(func(door: Dictionary) -> String: return str(door.id))
		for room: Dictionary in source.rooms:
			var target: Vector2 = room_sample(sim.nav,room,opened)
			var planned: Dictionary = sim.plan_move("alpha",{"target":[target.x,target.y]},false)
			check(bool(planned.get("ok",false)), id+": public route accepted to "+str(room.id)+" "+str(planned))
			if not bool(planned.get("ok",false)): continue
			for tick: int in range(1200):
				sim.step(1.0/30.0)
				if position(sim.units[0]).distance_to(target) < .25: break
			check(position(sim.units[0]).distance_to(target) < .3 and sim.command_failures == 0, id+": actor physically reaches "+str(room.id))
		# Seeded variants must repeat and keep all generated positions legal.
		var seen_spawns: Dictionary = {}
		var seen_doors: Dictionary = {}
		for seed_value: int in [40,41,42,43]:
			var varied: Dictionary = source.duplicate(true)
			varied.seed = seed_value
			var first := Simulation.new()
			var second := Simulation.new()
			first.load_mission(varied)
			second.load_mission(varied)
			check(first.enemies.map(func(actor: Dictionary) -> Vector2: return position(actor)) == second.enemies.map(func(actor: Dictionary) -> Vector2: return position(actor)), id+": same seed repeats placement")
			check(first.doors.map(func(door: Dictionary) -> String: return str(door.state)) == second.doors.map(func(door: Dictionary) -> String: return str(door.state)), id+": same seed repeats initial door states")
			seen_spawns[hash(first.enemies.map(func(actor: Dictionary) -> Vector2: return position(actor)))] = true
			seen_doors[hash(first.doors.map(func(door: Dictionary) -> String: return str(door.state)))] = true
			for actor: Dictionary in first.units+first.enemies+first.civilians:
				check(first.nav.walkable(position(actor)), id+": variant spawn on usable floor "+str(actor.id))
		check(seen_spawns.size() > 1, id+": seeds actually vary legal placements")
		check(seen_doors.size() > 1, id+": seeds actually vary initial door states")
		check(Catalog.load(id+"H").challenge, id+": separately selectable challenge operation")
	check(Catalog.load("M07").props.any(func(prop: Dictionary) -> bool: return prop.type == "vehicle"), "Garage includes parked vehicles")
	check(Catalog.load("M07").props.any(func(prop: Dictionary) -> bool: return prop.type == "pillar"), "Garage includes solid columns")
	check(Catalog.load("M09").rooms.any(func(room: Dictionary) -> bool: return not room.indoor and room.floor_surface == "gravel"), "Courtyard includes real outdoor surface and lighting metadata")
	for entry: Dictionary in Catalog.briefings():
		check(entry.rooms == Catalog.load(entry.id).rooms.size(), str(entry.id)+": accurate menu room count")
	print("BREACH_REALISM_MAPS_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
