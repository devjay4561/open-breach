extends SceneTree
const Field = preload("res://scripts/visibility_field.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Navigation = preload("res://scripts/navigation.gd")
# Exhaustive ray/edge intersection oracle from the original renderer.
class FullEdgeField extends BreachVisibilityField:
	var oracle_eye_height := 1.62
	func uncached_update(units: Array, doors: Array, smoke: Array) -> void:
		# Reference rebuilds static geometry as the original renderer did.
		_edges.clear()
		_corners.clear()
		_edge_heights.clear()
		_corner_heights.clear()
		for obstacle: Dictionary in nav.walls: _append_obstacle_geometry(obstacle)
		_static_edge_count = _edge_heights.size()
		_static_corner_count = _corners.size()
		_signature = ""
		_geometry_signature = ""
		_observer_cache.clear()
		update(units, doors, smoke)
	func _prepare_rays(origin: Vector2, maximum: float, eye_height: float = 1.62) -> void:
		oracle_eye_height = eye_height
		super._prepare_rays(origin, maximum, eye_height)
	func _ray_distance(origin: Vector2, direction: Vector2, maximum: float) -> float:
		var nearest := maximum
		for i in range(0, _edges.size(), 2):
			var heights: Vector2 = _edge_heights[i / 2]
			if oracle_eye_height < heights.x or oracle_eye_height > heights.y: continue
			var edge := _edges[i + 1] - _edges[i]
			var divisor := direction.cross(edge)
			if absf(divisor) < 0.0000001: continue
			var offset := _edges[i] - origin
			var along := offset.cross(edge) / divisor
			var across := offset.cross(direction) / divisor
			if along >= 0 and along < nearest and across >= -0.000001 and across <= 1.000001:
				nearest = along
		return nearest
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void:
	_test_ray_buckets()
	_test_static_geometry_reuse()
	_test_preview_grid_limit()
	for id in ["M01", "M04", "M06", "H01", "H02", "H03"]:
		var data := Catalog.load(id)
		check(not data.is_empty(), "Visibility fixture exists: " + id)
		if data.is_empty(): continue
		var sim := Simulation.new()
		sim.load_mission(data)
		var field := Field.new()
		field.build(data)
		var oracle := FullEdgeField.new()
		oracle.build(data)
		for frame in range(36):
			var observers: Array = sim.snapshot(true).units
			for i in range(observers.size()):
				observers[i].x = 3.3 + fmod(frame * 1.3 + i * 4.7, float(data.bounds[0]) - 6)
				observers[i].z = 3.7 + fmod(frame * 0.9 + i * 6.1, float(data.bounds[1]) - 6)
				observers[i].facing = frame * 0.31 + i
			if frame % 4 == 0:
				observers[0]["peek_origin"] = [observers[0].x + 0.3, observers[0].z]
				observers[0]["peek_remaining"] = 1.0
				observers[0]["peek_facing"] = observers[0].facing + 0.2
			if frame % 7 == 0: observers[1].hp = 0
			if frame % 5 == 0: observers[2].stunned = 1
			for door: Dictionary in sim.doors:
				door.progress = (frame % 4) / 3.0
				door.state = "OPEN" if door.progress == 1 else "OPENING"
			var smoke: Array = [] if frame % 3 == 0 else [{"x":8.0,"z":10.0,"radius":3.0}]
			# Recompute the exhaustive oracle without geometry or observer caches.
			oracle.uncached_update(observers,sim.doors,smoke)
			field.update(observers,sim.doors,smoke)
			check(field.polygons == oracle.polygons, "%s frame %d: optimized polygons equal all-edge reference" % [id,frame])
			check(not field.update(observers,sim.doors,smoke), "Unchanged observations reuse visibility")
			# Change only one observer with stationary geometry, then compare fresh.
			observers[0].facing += 0.1
			field.update(observers,sim.doors,smoke)
			oracle.uncached_update(observers,sim.doors,smoke)
			check(field.polygons == oracle.polygons, "Observer cache preserves other actors when one turns")
			check(field.polygon_for(str(observers[1].id)) == oracle.polygon_for(str(observers[1].id)), "Selected cone uses the same occluded polygon")
		field.build(data)
		check(field.polygon_for("alpha").is_empty(), "Mission change clears actor polygons")
	print("BREACH_VISIBILITY_OPTIMIZATION_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_ray_buckets() -> void:
	var fixtures: Array = [
		[Vector2(-4,-2),Vector2(-4,2)],
		[Vector2(5,0),Vector2(5,10)],
		[Vector2(5,-10),Vector2(5,0)],
		[Vector2(0.00005,0),Vector2(100,0)],
		[Vector2.ZERO,Vector2.RIGHT],
		[Vector2(4,-100),Vector2(4,100)],
		[Vector2(-1,0),Vector2(1,0)],
	]
	var directions: Array[Vector2] = [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]
	for side: float in [-1.0,1.0]:
		for slope: float in [0.00000005,0.00000015,0.000001,0.000003]:
			directions.append(Vector2(1,side*slope).normalized())
			directions.append(Vector2(-1,side*slope).normalized())
	# Every angular-bin boundary and either side must retain exact hits.
	for i: int in range(Field.RAY_BUCKET_COUNT):
		for offset: float in [-0.0000001,0.0,0.0000001]:
			directions.append(Vector2.from_angle(float(i)*TAU/Field.RAY_BUCKET_COUNT+offset))
	for points: Array in fixtures:
		var field := Field.new()
		field._edges = PackedVector2Array(points)
		field._edge_heights = PackedVector2Array([Vector2(0,3)])
		var oracle := FullEdgeField.new()
		oracle._edges = field._edges
		oracle._edge_heights = field._edge_heights
		field._prepare_rays(Vector2.ZERO,8.0)
		oracle._prepare_rays(Vector2.ZERO,8.0)
		for direction: Vector2 in directions:
			check(field._ray_distance(Vector2.ZERO,direction,8.0) == oracle._ray_distance(Vector2.ZERO,direction,8.0), "Angular candidates preserve wrap, endpoint tolerance, origin-on-edge, long edges and divisor threshold")
	# Excluded edges must not shift retained edge indices or include wrong heights.
	var field := Field.new()
	field._edges = PackedVector2Array([Vector2(1,-2),Vector2(1,2),Vector2(100,-2),Vector2(100,2),Vector2(4,-100),Vector2(4,100)])
	field._edge_heights = PackedVector2Array([Vector2(0,0.5),Vector2(0,3),Vector2(1,2)])
	field._prepare_rays(Vector2.ZERO,8.0,1.0)
	check(field._ray_distance(Vector2.ZERO,Vector2.RIGHT,8.0) == 4.0,"Height/range filtering retains the compressed edge index and inclusive height boundary")
	field._prepare_rays(Vector2.ZERO,8.0,2.0)
	check(field._ray_distance(Vector2.ZERO,Vector2.RIGHT,8.0) == 4.0,"The top height boundary remains inclusive")

func _test_static_geometry_reuse() -> void:
	var nav := Navigation.new()
	nav.build({"schema_version":2,"bounds":[12,12],"walls":[{"x":4.0,"z":4.0,"w":0.6,"d":2.0,"height":2.6},{"x":8.0,"z":8.0,"w":1.0,"d":2.0,"rotation":0.3}]},[])
	nav.begin_geometry_scope()
	var compiled: Array = nav.walls[0]._compiled_geometry
	var bucket := nav._static_bucket(Vector2(4,4))
	var members: Array = nav._static_buckets[bucket]
	nav.end_geometry_scope()
	nav.begin_geometry_scope()
	check(is_same(compiled,nav.walls[0]._compiled_geometry) and is_same(members,nav._static_buckets[bucket]),"Unchanged ticks retain exact compiled rectangles and bucket arrays")
	check(not nav.sight_clear_height(Vector2(2,4),Vector2(6,4),1.62,1.62),"Initial cached sight is blocked")
	nav.end_geometry_scope()
	nav.walls[0].x = 9.0
	nav.walls[0].height = 0.5
	nav.begin_geometry_scope()
	check(nav.sight_clear_height(Vector2(2,4),Vector2(6,4),1.62,1.62),"Direct position/height edits invalidate stale sight and rebuild exact buckets")
	nav.end_geometry_scope()
	# Reordering and appending are live mutations too: bucket indices must follow.
	nav.walls.reverse()
	nav.walls.append({"x":3.0,"z":3.0,"w":0.4,"d":2.0,"height":2.6})
	var a := Vector2(2,3)
	var b := Vector2(4,3)
	var expected := nav.segment_clear(a,b,Navigation.RADIUS)
	nav.begin_geometry_scope()
	check(nav.segment_clear(a,b,Navigation.RADIUS) == expected and not expected,"Static index follows reordered and newly appended dictionaries")
	nav.end_geometry_scope()
	nav.walls.clear()
	nav.begin_geometry_scope()
	check(nav.segment_clear(a,b,Navigation.RADIUS),"Removing all walls discards their old spatial index")
	nav.end_geometry_scope()

func _test_preview_grid_limit() -> void:
	var doors: Array = []
	for i: int in range(3):
		doors.append({"id":"door%d"%i,"x":6.0,"z":float(i+1)*2.0,"axis":"x","w":1.0,"d":0.2,"state":"CLOSED"})
	var data := {"bounds":[12,12],"walls":[{"x":6.0,"z":8.0,"w":0.3,"d":8.0}]}
	var nav := Navigation.new()
	nav.build(data,doors)
	for assumed: Array in [["door0"],["door1"],["door2"],["door0","door1"],["door0"]]:
		var result: Array = nav.path(Vector2(2,8),Vector2(10,8),assumed)
		var fresh := Navigation.new()
		fresh.build(data,doors)
		check(result == fresh.path(Vector2(2,8),Vector2(10,8),assumed),"Preview eviction preserves exact paths for small-map door combinations")
		check(nav._preview_grids.size() <= 2,"Small-map hypothetical graphs have a fixed retention limit")
