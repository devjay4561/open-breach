extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
class ReferenceReplay extends BreachReplay:
	func _intern(value: Dictionary, table: Array, lookup: Dictionary) -> int:
		var signature := JSON.stringify(value, "", true, true)
		if lookup.has(signature): return int(lookup[signature])
		var index := table.size()
		table.append(value)
		lookup[signature] = index
		_memory_bytes += signature.to_utf8_buffer().size() * 4 + 384
		_serialized_bytes += signature.to_utf8_buffer().size() + 1
		return index
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size() < 20: failures.append(message)

func _fixture() -> Dictionary:
	return {"schema_version":1, "id":"CUSTOM_CROSSPC", "title":"Cross-PC regression", "custom":true, "variant":"normal", "revision":1, "seed":42, "bounds":[12,12], "focus":[6,6], "rooms":[{"id":"room", "x":6.0, "z":6.0, "w":12.0, "d":12.0}], "walls":[], "doors":[], "props":[], "units":[{"id":"alpha", "name":"Alpha", "role":"Assault", "weapon":"standard", "x":2.0, "z":2.0, "facing":0.0}], "enemies":[{"id":"guard", "x":9.0, "z":9.0}], "civilians":[], "objectives":["Regression"]}

func _run() -> void:
	_test_cone_boundaries()
	_test_grid_updates()
	_test_compiled_geometry()
	_test_spatial_candidates()
	_test_replay_interning()
	_test_copy_ownership()
	print("BREACH_CROSSPC_OPTIMIZATION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_cone_boundaries() -> void:
	var sim = Simulation.new()
	var data := _fixture()
	data.props = [{"type":"box", "x":5.0, "z":5.0, "w":1.0, "d":1.0, "cover":"low", "height":0.8}]
	sim.load_mission(data)
	for fov: float in [0.0, 70.0, 110.0, 180.0, 360.0]:
		for distance: float in [0.05, 0.17, 0.30, 0.312, 1.0, 5.0]:
			for facing: float in [-PI, 0.0, PI * 0.5]:
				var observer := {"kind":"unit", "hp":100.0, "x":4.0, "z":4.0, "facing":facing, "fov":fov, "vision_range":10.0, "stance":"standing"}
				var sensor: Dictionary = observer.duplicate(false)
				sensor._cone_facing = facing
				sensor._cone_fov = fov
				sensor._cone_range = sim.effective_vision_range(observer)
				for delta: float in [-0.30, -0.001, 0.0, 0.001, 0.30, PI]:
					var point := Vector2(4,4) + Vector2.from_angle(facing + deg_to_rad(fov) * 0.5 + delta) * distance
					for yaw: float in [0.0, PI * 0.25, PI * 0.5]:
						for stance: String in ["standing", "crouched"]:
							var subject := {"kind":"enemy", "hp":100.0, "x":point.x, "z":point.y, "body_facing":yaw, "stance":stance}
							# Reference tests every body ray without the new disk rejection.
							var expected: float = sim.nav.exposed_fraction(sensor, subject)
							var actual: float = sim.visual_exposure(observer, subject)
							_check(is_equal_approx(actual, expected), "Body-ray exposure preserved at cone edge, short range, PI wrap and posture")
	# A side lean remains independently observable when ordinary facing rejects.
	var observer := {"kind":"unit", "hp":100.0, "x":2.0, "z":2.0, "facing":PI, "fov":70.0, "vision_range":10.0, "_peek_origin":[2.1,2.0], "_peek_facing":0.0, "_peek_remaining":1.0}
	_check(sim.visual_exposure(observer, {"kind":"enemy", "hp":100.0, "x":4.0, "z":2.0}) > 0.0, "Independent reachable peek is retained after ordinary cone rejection")

func _test_grid_updates() -> void:
	var data := _fixture()
	data.walls = [{"x":6.0,"z":2.5,"w":0.4,"d":5.0},{"x":6.0,"z":9.5,"w":0.4,"d":5.0}]
	var door := {"id":"d1","x":6.0,"z":6.0,"axis":"z","w":0.4,"d":2.0,"state":"CLOSED","progress":0.0,"hinge_side":-1.0,"swing_sign":-1.0}
	var nav = Navigation.new()
	nav.build(data, [door])
	for pose: Array in [["OPENING",0.25],["AJAR",0.52],["OPEN",1.0],["CLOSED",0.0],["OPENING",0.75],["OPEN",1.0],["DESTROYED",1.0]]:
		var grid_id: int = nav.grid.get_instance_id()
		door.state = pose[0]
		door.progress = pose[1]
		door.destroyed = pose[0] == "DESTROYED"
		door.hinge_side *= -1.0
		door.swing_sign *= -1.0
		nav.invalidate_dynamic()
		# This segment always crosses the fixed wall and requires a grid query.
		# A direct unobstructed path intentionally leaves the unused grid lazy.
		nav.path(Vector2(2,2), Vector2(10,2))
		# Temporary congestion/preview grids must not change main-grid tracking.
		nav._make_grid([])
		nav._make_grid(["d1"])
		for y: int in range(12,36):
			for x: int in range(18,30):
				var cell := Vector2i(x,y)
				_check(nav.grid.is_point_solid(cell) == (not nav.walkable(nav.grid.get_point_position(cell))), "Incremental door solidity matches physical grid-center tests: %s %s dirty=%s" % [pose, cell, nav._grid_dirty])
		var starts := [Vector2(2,2), Vector2(2,6), Vector2(2,10)]
		var incremental: Array = []
		for start: Vector2 in starts: incremental.append(nav.path(start, Vector2(10,6)))
		_check(nav.grid.get_instance_id() == grid_id, "A moving door retains the main graph allocation")
		nav.rebuild()
		for index: int in range(starts.size()):
			_check(incremental[index] == nav.path(starts[index], Vector2(10,6)), "Incremental paths match a full fresh graph, including tie ordering")

func _test_copy_ownership() -> void:
	var sim = Simulation.new()
	sim.load_mission(_fixture())
	_check(bool(sim.plan_move("alpha", {"target":[4.0,2.0]}, true).ok), "Movement command accepted")
	var view: Dictionary = sim.snapshot(true)
	view.units[0].commands[0].args.target[0] = 11.0
	_check(sim.units[0].commands[0].args.target == [4.0,2.0], "One owned snapshot copy still isolates nested commands")
	var replay = Replay.new()
	replay.begin(_fixture())
	replay.capture(sim.snapshot(true))
	for tick: int in range(8):
		sim.step(1.0 / 30.0)
		var pair: Dictionary = sim.snapshot_pair()
		_check(pair.record == sim.snapshot(true), "Paired recording equals independent complete snapshot")
		_check(pair.observed == sim.snapshot(false), "Paired presentation equals independent filtered snapshot")
		var state: Dictionary = pair.record
		var original := JSON.stringify(state)
		var observed_original := JSON.stringify(pair.observed)
		replay.capture(state)
		_check(JSON.stringify(state) == original, "Replay packing never mutates its input or command arguments")
		_check(JSON.stringify(pair.observed) == observed_original, "Replay packing leaves shared presentation data immutable")
	# Hidden observations must remain frozen even though a full recording exists.
	sim.enemies[0].visible = false
	sim.enemies[0].last_seen = [8.0,8.0]
	sim.enemies[0].last_seen_time = 0.0
	sim.enemies[0].x = 11.0
	_check(sim.snapshot_pair().observed == sim.snapshot(false), "Paired hidden movement is limited to last seen data")
	sim.result = {"success":true}
	_check(sim.snapshot_pair().observed == sim.snapshot(false), "Mission result reveal is unchanged")
	var imported = Replay.new()
	var loaded: Dictionary = imported.load_data(JSON.parse_string(JSON.stringify(replay.export_data())))
	_check(bool(loaded.ok), "Packed replay survives JSON export/import: " + str(loaded.get("message", "")))

func _test_compiled_geometry() -> void:
	var nav = Navigation.new()
	var data := _fixture()
	data.walls = [{"x":6.0,"z":6.0,"w":1.1,"d":4.3,"height":0.85,"base_height":0.25}]
	nav.build(data, [])
	var random := RandomNumberGenerator.new()
	random.seed = 20261008
	for angle: float in [0.0, 0.0000005, PI * 0.5, -PI * 0.25, 0.61]:
		var obstacle: Dictionary = nav.walls[0]
		obstacle.rotation = angle
		for sample_index: int in range(80):
			var a := Vector2(random.randf_range(2,10), random.randf_range(2,10))
			var b := Vector2(random.randf_range(2,10), random.randf_range(2,10))
			var from_height: float = random.randf_range(0,2)
			var to_height: float = random.randf_range(0,2)
			nav.end_geometry_scope()
			var expected: Array = []
			for padding: float in [0.0, Navigation.RADIUS, 0.1]:
				expected.append(nav._contains(obstacle,a,padding))
				expected.append(nav._segment_obstacle(a,b,obstacle,padding))
			var height_expected: bool = nav._height_intersects(a,b,from_height,to_height,obstacle)
			nav.begin_geometry_scope()
			var index := 0
			for padding: float in [0.0, Navigation.RADIUS, 0.1]:
				_check(expected[index] == nav._contains(obstacle,a,padding), "Compiled point containment matches exact uncompiled geometry")
				_check(expected[index+1] == nav._segment_obstacle(a,b,obstacle,padding), "Compiled segment collision matches exact uncompiled geometry")
				index += 2
			_check(height_expected == nav._height_intersects(a,b,from_height,to_height,obstacle), "Compiled inclined height ray matches exact uncompiled geometry")
		nav.end_geometry_scope()

func _test_spatial_candidates() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 99173
	for map_id: String in ["M01", "M06", "M07"]:
		var data: Dictionary = Catalog.load(map_id)
		var nav = Navigation.new()
		nav.build(data, data.doors)
		for sample_index: int in range(300):
			var a := Vector2(random.randf_range(0,data.bounds[0]),random.randf_range(0,data.bounds[1]))
			var b := a + Vector2(random.randf_range(-0.3,0.3),random.randf_range(-0.3,0.3)) if sample_index % 2 == 0 else Vector2(random.randf_range(0,data.bounds[0]),random.randf_range(0,data.bounds[1]))
			# Exact bucket boundaries and different clearances supplement random rays.
			if sample_index % 10 == 0: a = Vector2(4.0,4.0)
			var padding: float = [0.0,Navigation.RADIUS,0.1,0.4][sample_index % 4]
			var from_height: float = random.randf_range(0,2)
			var to_height: float = random.randf_range(0,2)
			nav.end_geometry_scope()
			var expected_segment: bool = nav.segment_clear(a,b,padding)
			var expected_point: bool = nav.walkable(a)
			var expected_sight: bool = nav._uncached_sight_clear_height(a,b,from_height,to_height)
			var expected_transmission: float = nav.sight_transmission_height(a,b,from_height,to_height)
			var expected_shot: Dictionary = nav._uncached_shot_profile_height(a,b,from_height,to_height,8.0)
			nav.begin_geometry_scope()
			_check(nav.segment_clear(a,b,padding) == expected_segment, "Scoped indexed movement matches full scan including bucket boundaries")
			_check(nav.walkable(a) == expected_point, "Scoped indexed point clearance matches full scan")
			_check(nav._uncached_sight_clear_height(a,b,from_height,to_height) == expected_sight, "Scoped indexed sight matches full scan")
			_check(nav.sight_transmission_height(a,b,from_height,to_height) == expected_transmission, "Scoped indexed opacity preserves authored multiplication order")
			_check(nav._uncached_shot_profile_height(a,b,from_height,to_height,8.0) == expected_shot, "Scoped indexed shot preserves resistance and vehicle groups")
		nav.end_geometry_scope()

func _test_replay_interning() -> void:
	var data: Dictionary = Catalog.load("M06")
	var sim = Simulation.new()
	sim.load_mission(data)
	var replay = Replay.new()
	var reference = ReferenceReplay.new()
	replay.begin(data)
	reference.begin(data)
	for index: int in range(4):
		var x: float = [7.1,8.6,24.1,25.6][index]
		for z: float in [27.2,23.0,14.0]: sim.plan_move(sim.units[index].id,{"target":[25.0 if index == 2 and z == 14.0 else x,z]},true)
	for tick: int in range(241):
		if tick > 0: sim.step(1.0 / 30.0)
		var state: Dictionary = sim.snapshot(true)
		replay.capture(state)
		reference.capture(state)
	_check(replay.export_data() == reference.export_data(), "Hash-assisted interning preserves the entire original replay encoding")
	var table: Array = [{"value":"other"}]
	var lookup: Dictionary = {hash({"value":"wanted"}):[0]}
	_check(replay._intern({"value":"wanted"},table,lookup) == 1, "A forced hash collision compares values and retains a distinct definition")
