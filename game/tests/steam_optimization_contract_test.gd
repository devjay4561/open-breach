extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Replay = preload("res://scripts/replay.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
class FreshRecovery extends BreachSimulation:
	func _movement_dynamic_route(actor: Dictionary, destination: Vector2) -> Array:
		_recovery_grid = null
		return super._movement_dynamic_route(actor, destination)
class CountingPreview extends BreachSimulation:
	var previews := 0
	func _refresh_preview(unit: Dictionary) -> void:
		if _preview_batch_depth == 0: previews += 1
		super._refresh_preview(unit)
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size() < 20: failures.append(message)

func fixture() -> Dictionary:
	return {"id":"OPTIMIZATION", "seed":42, "bounds":[32,32], "rooms":[], "walls":[], "props":[], "doors":[], "units":[{"id":"alpha", "x":4.0, "z":8.0, "facing":0.0, "hp":1000.0, "ammo":0, "reserve_ammo":0}], "enemies":[{"id":"guard", "x":9.0, "z":8.0, "facing":PI, "hp":1000.0, "ammo":0, "reserve_ammo":0}], "civilians":[], "win":[{"type":"reach_zone", "zone":[30,30,1,1]}], "fail":[]}

func run() -> void:
	_test_floor_safety()
	_test_cover_height()
	_test_record_stream()
	_test_door_geometry()
	_test_recovery_grid()
	_test_plan_batch()
	print("BREACH_STEAM_OPTIMIZATION_CONTRACT_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_floor_safety() -> void:
	for height: float in [0.0, 2.022, 4.0]:
		for stance: String in ["standing", "crouched"]:
			var data := fixture()
			data.schema_version = 2
			data.rooms = [{"id":"floor", "x":16.0, "z":16.0, "w":32.0, "d":32.0, "base_height":height}]
			data.units[0].stance = stance
			data.enemies[0].stance = stance
			data.civilians = [{"id":"civilian", "x":6.0, "z":8.0, "stance":stance}]
			var sim := Simulation.new()
			sim.load_mission(data)
			check(not sim.fire_line_clear(sim.units[0], sim.enemies[0]), "Same-floor civilian blocks fire at %s/%s" % [height, stance])
			sim.civilians[0].base_height = height + 4.0
			check(sim.fire_line_clear(sim.units[0], sim.enemies[0]), "Civilian entirely above the shot does not block")
			sim.civilians[0].base_height = height - 4.0
			check(sim.fire_line_clear(sim.units[0], sim.enemies[0]), "Civilian entirely below the shot does not block")

func _test_cover_height() -> void:
	var values: Array = []
	for height: float in [0.0, 2.022]:
		var data := fixture()
		data.schema_version = 2
		data.rooms = [{"id":"floor", "x":16.0, "z":16.0, "w":32.0, "d":32.0, "base_height":height}]
		data.props = [{"id":"cover", "type":"crate", "cover":"low", "x":6.0, "z":8.0, "w":1.0, "d":2.0, "height":1.05, "base_height":height}]
		var sim := Simulation.new()
		sim.load_mission(data)
		var point := Vector2(8,8)
		var threat := Vector2(4,8)
		var observer := {"x":threat.x,"z":threat.y,"stance":"standing","base_height":height}
		var subject := {"kind":"enemy","x":point.x,"z":point.y,"stance":"crouched","base_height":height}
		var actual: float = sim._cover_exposure(sim.enemies[0], point, threat, "crouched")
		check(is_equal_approx(actual, sim.nav.exposed_fraction(observer, subject)), "Cover uses the shared floor/body height rules")
		values.append(actual)
		for stance: String in ["standing", "crouched"]:
			var target := {"kind":"unit","x":threat.x,"z":threat.y,"hp":1.0,"stance":"standing","base_height":height}
			var expected: bool = sim.nav.shot_exposure(point, Spatial.weapon_height({"stance":stance,"base_height":height}), target) > 0.25
			check(sim._alert_weapon_line(sim.enemies[0], point, threat, stance) == expected, "Alert shot uses absolute shared weapon height")
	check(is_equal_approx(values[0], values[1]), "Translating the entire scene vertically preserves exposure")

func _test_record_stream() -> void:
	var sim := Simulation.new()
	sim.load_mission(Catalog.load("M01"))
	var recorder := Replay.new()
	recorder.begin(sim.mission)
	recorder.capture(sim.snapshot(true), sim.take_record_events())
	var before: int = sim._sequence
	for index: int in range(96):
		sim._event("CONTACT", "simultaneous", [], [9.0,8.0], {"entity_id":sim.enemies[0].id})
	check(sim.events.size() == 40, "HUD recent log remains bounded at 40")
	check(sim.snapshot_pair().observed.events.size() == 40, "Snapshot still follows the HUD contract")
	var batch: Array = sim.take_record_events()
	check(batch.size() == 96, "Recorder receives every event beyond the HUD ring")
	check(int(batch.front().seq) == before + 1 and int(batch.back().seq) == before + 96, "Record batch preserves chronological sequence")
	check(sim.take_record_events().is_empty(), "Consuming the stream releases its tick backlog")
	recorder.capture(sim.snapshot(true), batch)
	check(recorder._events.size() == before + 96, "Replay retains the complete subscribed stream")
	var loaded := Replay.new()
	var answer: Dictionary = loaded.load_data(JSON.parse_string(JSON.stringify(recorder.export_data())))
	check(answer.ok, "Complete event stream survives schema validation and JSON roundtrip: " + str(answer.get("message", "")))
	sim.load_mission(fixture())
	for index: int in range(96): sim._event("CONTACT", "sim-only")
	check(sim._pending_record_events.is_empty(), "Simulation-only callers do not accumulate an unused recorder backlog")

func _test_door_geometry() -> void:
	var corner_obstacle := {"x":6.0,"z":6.0,"w":1.05,"d":0.226,"leaf_angle":0.23100000619888306}
	var corner := Vector2(5.3435845375061035,5.493252754211426)
	check(Door.local_rect(corner_obstacle, 0.23).has_point(Door.local_point(corner_obstacle, corner)), "Rounded corner fixture lies inside the exact rectangle")
	check(Door.obstacle_overlaps_actor(corner_obstacle, corner, 0.23), "Broadphase retains a float32-rounded included corner")
	var random := RandomNumberGenerator.new()
	random.seed = 20261009
	for axis: String in ["x", "z"]:
		for hinge: float in [-1.0, 1.0]:
			for swing: float in [-1.0, 1.0]:
				var door := {"id":"door", "x":6.0,"z":6.0,"w":1.6 if axis == "x" else 0.24,"d":0.24 if axis == "x" else 1.6,"axis":axis,"hinge_side":hinge,"swing_sign":swing,"state":"OPENING","progress":0.1}
				var sim := Simulation.new()
				for sample: int in range(120):
					var point := Vector2(random.randf_range(3,9),random.randf_range(3,9))
					var progress: float = random.randf()
					var obstacle: Dictionary = Door.movement_obstacle(door, progress)
					var expected: bool = Door.local_rect(obstacle, 0.31).has_point(Door.local_point(obstacle, point))
					check(Door.obstacle_overlaps_actor(obstacle, point, 0.31) == expected, "Conservative rejection preserves exact rotated rectangle collision")
					var sweep: Array = sim._door_sweep_shapes(door, 1.0)
					var clear := true
					for shape: Dictionary in sweep:
						if Door.local_rect(shape, Navigation.RADIUS + 0.015).has_point(Door.local_point(shape, point)): clear = false
					check(sim._door_sweep_clear(door, point, 1.0, sweep) == clear, "Shared 17-pose sweep preserves leaf collision")

func _test_recovery_grid() -> void:
	var data := fixture()
	data.walls = [{"x":7.0,"z":4.0,"w":0.4,"d":7.0}]
	data.doors = [{"id":"door", "x":7.0,"z":8.5,"w":0.4,"d":2.0,"axis":"z","state":"OPENING","progress":0.5}]
	data.units.append({"id":"bravo","x":6.0,"z":8.0,"ammo":0})
	var cached := Simulation.new()
	var fresh := FreshRecovery.new()
	cached.load_mission(data)
	fresh.load_mission(data)
	var main_grid_id: int = cached.nav.grid.get_instance_id()
	var recovery_id := 0
	for index: int in range(8):
		for sim: RefCounted in [cached, fresh]:
			sim.units[1].x = 5.0 + float(index % 3) * 0.5
			sim.units[1].z = 7.0 + float(index % 4) * 0.5
			sim.doors[0].progress = 0.50 + float(index) * 0.005
		var route: Array = cached._movement_dynamic_route(cached.units[0], Vector2(10,8))
		check(route == fresh._movement_dynamic_route(fresh.units[0], Vector2(10,8)), "Reused recovery matches a fresh graph after actor/door changes")
		if recovery_id == 0: recovery_id = cached._recovery_grid.get_instance_id()
		check(cached._recovery_grid.get_instance_id() == recovery_id, "Recovery queries reuse one bounded graph")
		check(cached.nav.grid.get_instance_id() == main_grid_id, "Temporary body occupancy never replaces the main graph")

func _test_plan_batch() -> void:
	for blocked: bool in [false, true]:
		var data := fixture()
		if blocked: data.walls = [{"x":7.0,"z":12.0,"w":1.0,"d":1.0}]
		var batched := CountingPreview.new()
		var sequential := Simulation.new()
		batched.load_mission(data)
		sequential.load_mission(data)
		batched.previews = 0
		var points: Array = [[5.0,8.0],[5.0,10.0],[7.0,10.0],[7.0,12.0]]
		var accepted := 0
		for point: Array in Simulation.simplify_path(points, 0.12):
			if not sequential.plan_move("alpha", {"target":point}, true).ok: break
			accepted += 1
		var response: Dictionary = batched.plan_drag("alpha", points)
		check(int(response.accepted) == accepted, "Drag preserves the accepted prefix when a later point fails")
		check(batched.snapshot(true) == sequential.snapshot(true), "One preview flush preserves all command/path snapshots")
		check(batched.previews == 1, "Drag refreshes its final accepted plan once")
		check(batched._preview_batch_depth == 0 and batched._preview_dirty_units.is_empty(), "Success/failure closes the preview batch")
