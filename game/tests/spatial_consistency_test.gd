extends SceneTree
const Navigation = preload("res://scripts/navigation.gd")
const Door = preload("res://scripts/door_geometry.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _map() -> Dictionary:
	return {"bounds": [12, 12], "walls": [], "props": []}

func _door(axis: String, sign_value: float, progress: float) -> Dictionary:
	return {"id": "d1", "x": 6.0, "z": 6.0, "axis": axis, "w": 1.8 if axis == "x" else 0.24, "d": 0.24 if axis == "x" else 1.8, "state": "OPEN" if progress == 1.0 else "OPENING", "progress": progress, "swing_sign": sign_value}

func _valid_route(nav: BreachNavigation, start: Vector2, target: Vector2, route: Array) -> bool:
	if route.is_empty():
		return false
	var previous: Vector2 = start
	for coordinate: Array in route:
		var point := Vector2(float(coordinate[0]), float(coordinate[1]))
		if not nav.walkable(point) or not nav.segment_clear(previous, point, Navigation.RADIUS):
			return false
		previous = point
	return previous.distance_to(target) < 0.00001

func _run() -> void:
	for axis: String in ["x", "z"]:
		for sign_value: float in [-1.0, 1.0]:
			for progress: float in [0.0, 0.3, 0.6, 0.85, 1.0]:
				var door: Dictionary = _door(axis, sign_value, progress)
				var nav: BreachNavigation = Navigation.new()
				nav.build(_map(), [door])
				var leaf: Dictionary = Door.leaf_obstacle(door)
				var center := Vector2(float(leaf.x), float(leaf.z))
				var normal := Vector2.UP.rotated(float(leaf.leaf_angle))
				var a := center + normal * 0.8
				var b := center - normal * 0.8
				_check(not nav.segment_clear(a, b), "Zero-radius LOS is blocked by current leaf pose %s/%s/%s" % [axis, sign_value, progress])
				_check(not nav.segment_clear(a, b, Navigation.RADIUS), "Body collision and LOS share the leaf pose")
				var hit: float = Door.ray_distance(door, a, b - a, 1.6)
				_check(absf(hit - (0.8 - Door.LEAF_HALF_DEPTH)) < 0.00001, "FOV ray stops on the same leaf surface as navigation")
				_check(nav.segment_clear(a, a + (b - a).normalized() * (hit - 0.0001)), "Ray prefix ends before the actual leaf")
				_check(not nav.segment_clear(a, a + (b - a).normalized() * (hit + 0.0001)), "Ray suffix enters the actual leaf")
				var parallel_start := center + normal * (Door.LEAF_HALF_DEPTH + 0.02)
				var along := Vector2.RIGHT.rotated(float(leaf.leaf_angle))
				_check(is_equal_approx(Door.ray_distance(door, parallel_start, along, 2.0), 2.0), "A parallel ray outside the leaf is unobstructed")
				if progress >= 0.85:
					var threshold_normal := Vector2.DOWN if axis == "x" else Vector2.RIGHT
					var threshold_a := Vector2(6, 6) - threshold_normal * 0.6
					var threshold_b := Vector2(6, 6) + threshold_normal * 0.6
					_check(nav.segment_clear(threshold_a, threshold_b), "Visible empty doorway no longer has an invisible LOS slab")
					_check(nav.segment_clear(threshold_a, threshold_b, Navigation.RADIUS) == (progress == 1.0), "Movement waits for completed opening as an explicit interaction rule")

	# Start and cell centre are both outside this expanded corner, but the
	# connection between them crosses it. An unchecked nearest-cell shortcut
	# used to select exactly that invalid connection.
	var corner_map := _map()
	corner_map.walls = [{"x": 2.38, "z": 2.29, "w": 0.02, "d": 0.02}]
	var corner_nav: BreachNavigation = Navigation.new()
	corner_nav.build(corner_map, [])
	var start := Vector2(2.24, 2.01)
	var destination := Vector2(1.2, 3.0)
	var center := corner_nav.grid.get_point_position(corner_nav.cell(start))
	_check(corner_nav.walkable(start) and corner_nav.walkable(center) and not corner_nav.segment_clear(start, center, Navigation.RADIUS), "Fixture exposes an edge crossing that free grid centres miss")
	var nearest: Vector2i = corner_nav._nearest_cell(start, corner_nav.grid)
	_check(nearest != corner_nav.cell(start) and corner_nav.segment_clear(start, corner_nav.grid.get_point_position(nearest), Navigation.RADIUS), "Nearest-cell connection checks actual body clearance")
	_check(_valid_route(corner_nav, start, destination, corner_nav.path(start, destination)), "A legal detour survives the corner fix")

	# A stale grid is never authority for a newly occupied segment.
	var stale_nav: BreachNavigation = Navigation.new()
	stale_nav.build(_map(), [])
	var stale_grid: AStarGrid2D = stale_nav.grid
	stale_nav.walls.append({"x": 6.0, "z": 6.0, "w": 0.1, "d": 12.0})
	var impossible: Array = stale_nav._grid_path(Vector2(2, 6), Vector2(10, 6), [], stale_grid)
	_check(impossible.is_empty(), "Smoothing cannot emit an unchecked neighbouring segment from stale occupancy")
	_check(stale_nav.path(Vector2(-1, 6), Vector2(2, 6)).is_empty(), "Out-of-bounds start is rejected")
	stale_nav.walls[0].d = 1.2
	var repaired: Array = stale_nav.path(Vector2(2, 6), Vector2(10, 6))
	_check(stale_nav._needs_edge_retry and _valid_route(stale_nav, Vector2(2, 6), Vector2(10, 6), repaired), "Edge-aware retry recovers a legal detour when the cached grid crosses a new corner")

	var dynamic: Dictionary = _door("x", -1.0, 1.0)
	var nav: BreachNavigation = Navigation.new()
	nav.build(_map(), [dynamic])
	var previous_grid: AStarGrid2D = nav.grid
	var previous_revision: int = nav.revision
	dynamic.swing_sign = 1.0
	var leaf: Dictionary = Door.leaf_obstacle(dynamic)
	var leaf_center := Vector2(float(leaf.x), float(leaf.z))
	var normal := Vector2.UP.rotated(float(leaf.leaf_angle))
	var a := leaf_center + normal * 0.8
	var b := leaf_center - normal * 0.8
	_check(not nav.segment_clear(a, b), "Live LOS sees rotated geometry before a cached path grid rebuild")
	nav.invalidate_dynamic()
	_check(nav.grid == previous_grid and nav.revision == previous_revision + 1, "Dynamic invalidation is cheap and visible to path consumers")
	_check(_valid_route(nav, a, b, nav.path(a, b)), "Next path query lazily updates and detours around the new leaf")
	_check(nav.grid == previous_grid and not nav._grid_dirty, "Lazy path query consumes the invalidation while retaining graph allocation")
	_check(not nav.segment_clear(a, b, 0.0, ["d1"]), "Hypothetical opening cannot remove an already open physical leaf")

	# Multiple directions around each actual open leaf exercise oblique corners
	# rather than checking just a single perpendicular detour.
	for axis: String in ["x", "z"]:
		for sign_value: float in [-1.0, 1.0]:
			var door: Dictionary = _door(axis, sign_value, 1.0)
			nav.build(_map(), [door])
			leaf = Door.leaf_obstacle(door)
			leaf_center = Vector2(float(leaf.x), float(leaf.z))
			var all_valid := true
			for index: int in range(16):
				a = leaf_center + Vector2.from_angle(float(index) * TAU / 16.0) * 1.7
				b = leaf_center - Vector2.from_angle(float(index + 1) * TAU / 16.0) * 1.7
				all_valid = all_valid and _valid_route(nav, a, b, nav.path(a, b))
			_check(all_valid, "All 16 oblique detours around %s/%s have valid segments" % [axis, sign_value])
	print("BREACH_SPATIAL_CONSISTENCY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
