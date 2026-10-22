class_name BreachNavigation
extends RefCounted
const DoorGeometry = preload("res://scripts/door_geometry.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")

const CELL: float = 0.25
const RADIUS: float = 0.23
const STATIC_BUCKET_SIZE: float = 2.0
var bounds: Vector2 = Vector2(24, 20)
var walls: Array = []
var low_cover: Array = []
var doors: Array = []
var grid: AStarGrid2D
var revision: int = 0
var _preview_grids: Dictionary = {}
var _static_solid_cells: Array[Vector2i] = []
var _static_occupancy: PackedByteArray = PackedByteArray()
var _occupancy_width: int = 0
var _grid_region: Rect2i
var _large_map: bool = false
var _bounded_movement: bool = false
var _walkable_voids: Array[Rect2] = []
var _main_door_cells: Dictionary = {}
var _grid_dirty: bool = false
var _needs_edge_retry: bool = false
var _leaf_cache: Dictionary = {}
var _exposure_cache: Dictionary = {}
var _sight_ray_cache: Dictionary = {}
var _physical_ray_cache: Dictionary = {}
var _shot_ray_cache: Dictionary = {}
var _shot_exposure_cache: Dictionary = {}
var _last_door_key: Array = []
var _exact_door_revision: int = 0
var _geometry_scope: bool = false
var _scope_door_key: Array = []
var _scope_door_dirty: bool = true
var _door_blocker_cache: Dictionary = {}
var _lighting: float = 1.0
var _lighting_rooms: Array = []
var _lighting_regions: Array = []
var _static_buckets: Dictionary = {}
var _indexed_walls: Array = []

class EdgeCheckedGrid extends AStarGrid2D:
	var navigation: WeakRef
	var assumed_open: Array = []
	func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
		var a := get_point_position(from_id)
		var b := get_point_position(to_id)
		var owner = navigation.get_ref()
		# A final segment validation still rejects routes when no legal detour
		# exists; the large cost lets A* prefer any collision-free connection.
		if owner == null or not owner.segment_clear(a, b, RADIUS, assumed_open):
			return 1.0e12
		return a.distance_to(b) / CELL

func build(data: Dictionary, door_states: Array) -> void:
	_leaf_cache.clear()
	_exposure_cache.clear()
	_sight_ray_cache.clear()
	_physical_ray_cache.clear()
	_shot_ray_cache.clear()
	_shot_exposure_cache.clear()
	_last_door_key = []
	_geometry_scope = false
	_scope_door_key = []
	_scope_door_dirty = true
	_door_blocker_cache.clear()
	_indexed_walls.clear()
	_static_buckets.clear()
	var environment: Dictionary = data.get("environment", {})
	_lighting = clampf(float(environment.get("lighting", 1.0)), 0.0, 1.0)
	_lighting_rooms = data.get("rooms", []).duplicate(true)
	_lighting_regions.clear()
	for room: Dictionary in _lighting_rooms:
		if room.has("lighting"):
			_lighting_regions.append([
				Rect2(float(room.get("x", 0)) - float(room.get("w", 0)) * 0.5, float(room.get("z", 0)) - float(room.get("d", 0)) * 0.5, float(room.get("w", 0)), float(room.get("d", 0))),
				clampf(float(room.lighting), 0.0, 1.0),
			])
	var size: Array = data.get("bounds", [24, 20])
	bounds = Vector2(float(size[0]), float(size[1]))
	_bounded_movement = int(data.get("schema_version", 1)) >= 2
	_large_map = int(data.get("schema_version", 1)) >= 2 and maxf(bounds.x, bounds.y) > 32.0
	_build_walkable_region(data.get("walkable_areas", []))
	walls.clear()
	low_cover.clear()
	for wall: Dictionary in data.get("walls", []):
		var obstacle: Dictionary = wall.duplicate(true)
		obstacle["height"] = float(wall.get("height", 2.6))
		walls.append(obstacle)
	for prop: Dictionary in data.get("props", []):
		var cover: String = str(prop.get("cover", cover_default(str(prop.get("type", "")), prop.get("solid"))))
		if cover in ["low", "full"]:
			var obstacle: Dictionary = prop.duplicate(true)
			obstacle["cover"] = cover
			obstacle["height"] = float(prop.get("height", Spatial.prop_height(str(prop.get("type", "")), cover)))
			obstacle["material"] = str(prop.get("material", Spatial.prop_material(str(prop.get("type", "")))))
			if str(prop.get("type", "")) == "vehicle":
				# Match the rendered hood/body and raised cabin rather than a
				# full-height box over the entire parking-space footprint.
				var physical_height := float(obstacle.height) / 0.94
				var base := float(obstacle.get("base_height", 0.0))
				var cabin: Dictionary = obstacle.duplicate(true)
				var cabin_offset := Vector2(0, -float(prop.get("d", 1.0)) * 0.07).rotated(-float(prop.get("rotation", 0.0)))
				cabin["x"] = float(prop.x) + cabin_offset.x
				cabin["z"] = float(prop.z) + cabin_offset.y
				cabin["w"] = float(prop.get("w", 1.2)) * 0.84
				cabin["d"] = float(prop.get("d", 1.0)) * 0.49
				cabin["base_height"] = base + physical_height * 0.54
				cabin["height"] = physical_height * 0.40
				var group := "vehicle-%d" % walls.size()
				cabin["_physical_group"] = group
				obstacle["_physical_group"] = group
				obstacle["base_height"] = base + physical_height * 0.125
				obstacle["height"] = physical_height * 0.49
				walls.append(obstacle)
				walls.append(cabin)
			else:
				walls.append(obstacle)
			if cover == "low":
				low_cover.append(obstacle)
	doors = door_states
	_cache_static_cells()
	rebuild()

static func cover_default(kind: String, legacy_solid: Variant = null) -> String:
	match kind:
		"desk", "table", "sofa", "box", "crate", "bed": return "low"
		"cabinet", "bookshelf": return "full"
		"rug", "plant", "chair": return "none"
	return "full" if legacy_solid == true else "none"

func rebuild() -> void:
	invalidate_sensory_pose()
	_exposure_cache.clear()
	_sight_ray_cache.clear()
	_physical_ray_cache.clear()
	_shot_ray_cache.clear()
	_shot_exposure_cache.clear()
	# Large maps with a straight movement route need no million-point graph.
	# Legacy maps retain their eager graph contract used by old tools/tests.
	grid = null if _large_map else _make_grid([])
	_main_door_cells = _door_grid_cells([])
	_preview_grids.clear()
	_grid_dirty = false
	revision += 1

func invalidate_dynamic() -> void:
	invalidate_sensory_pose()
	_exposure_cache.clear()
	_sight_ray_cache.clear()
	_physical_ray_cache.clear()
	_shot_ray_cache.clear()
	_shot_exposure_cache.clear()
	_grid_dirty = true
	_preview_grids.clear()
	revision += 1

func begin_geometry_scope() -> void:
	# A fixed simulation step advances all door leaves first. The exact live
	# geometry is then stable for its many movement, perception and shot rays.
	_geometry_scope = false
	_scope_door_key = _door_pose_key()
	_scope_door_dirty = false
	# Live scalar comparisons retain direct edits without rebuilding unchanged
	# rectangles or the static spatial index on every simulation tick.
	var static_changed := _indexed_walls.size() != walls.size()
	for index: int in range(walls.size()):
		if _compile_obstacle(walls[index]): static_changed = true
		if index >= _indexed_walls.size() or not is_same(_indexed_walls[index], walls[index]): static_changed = true
	if static_changed:
		_sight_ray_cache.clear()
		_physical_ray_cache.clear()
		_shot_ray_cache.clear()
		_exposure_cache.clear()
		_shot_exposure_cache.clear()
		_static_buckets.clear()
		for index: int in range(walls.size()):
			var compiled: Array = walls[index]._compiled_geometry
			var rect: Rect2 = compiled[6]
			var first := _static_bucket(rect.position)
			var last := _static_bucket(rect.end)
			for y: int in range(first.y, last.y + 1):
				for x: int in range(first.x, last.x + 1):
					var coordinate := Vector2i(x,y)
					if not _static_buckets.has(coordinate): _static_buckets[coordinate] = []
					_static_buckets[coordinate].append(index)
		_indexed_walls = walls.duplicate(false)
	_geometry_scope = true

func end_geometry_scope() -> void:
	_geometry_scope = false

func invalidate_sensory_pose() -> void:
	# Also call this for an exceptional mid-step leaf/hinge/material mutation.
	# It does not force the movement grid to rebuild for sub-cell rotations.
	_scope_door_dirty = true
	_door_blocker_cache.clear()

func _build_walkable_region(areas: Array) -> void:
	_grid_region = Rect2i(0, 0, ceili(bounds.x / CELL), ceili(bounds.y / CELL))
	_walkable_voids.clear()
	if areas.is_empty(): return
	# Subtract the union from the map. Testing its complementary rectangles
	# preserves clearance through touching/overlapping deck pieces; eroding
	# each allowed piece independently would create false seams between them.
	_walkable_voids.append(Rect2(Vector2.ZERO, bounds))
	var envelope := Rect2()
	for i: int in range(areas.size()):
		var area: Dictionary = areas[i]
		var rect := Rect2(Vector2(float(area.x), float(area.z)) - Vector2(float(area.w), float(area.d)) * 0.5, Vector2(float(area.w), float(area.d)))
		envelope = rect if i == 0 else envelope.merge(rect)
		var remaining: Array[Rect2] = []
		for forbidden: Rect2 in _walkable_voids:
			var cut := forbidden.intersection(rect)
			if not cut.has_area():
				remaining.append(forbidden)
				continue
			for piece: Rect2 in [
				Rect2(forbidden.position, Vector2(forbidden.size.x, cut.position.y - forbidden.position.y)),
				Rect2(Vector2(forbidden.position.x, cut.end.y), Vector2(forbidden.size.x, forbidden.end.y - cut.end.y)),
				Rect2(Vector2(forbidden.position.x, cut.position.y), Vector2(cut.position.x - forbidden.position.x, cut.size.y)),
				Rect2(Vector2(cut.end.x, cut.position.y), Vector2(forbidden.end.x - cut.end.x, cut.size.y)),
			]:
				if piece.has_area(): remaining.append(piece)
		_walkable_voids = remaining
	var low := cell(envelope.position)
	var end := Vector2i(ceili(envelope.end.x / CELL), ceili(envelope.end.y / CELL))
	_grid_region = Rect2i(low, end - low).intersection(_grid_region)

func _inside_map(point: Vector2, padding: float) -> bool:
	return point.x >= padding and point.y >= padding and point.x <= bounds.x - padding and point.y <= bounds.y - padding

func _movement_floor_clear(a: Vector2, b: Vector2, padding: float) -> bool:
	if not _inside_map(a, padding) or not _inside_map(b, padding): return false
	for forbidden: Rect2 in _walkable_voids:
		if _segment_rect(a, b, forbidden.grow(padding)): return false
	return true

func _cache_static_cells() -> void:
	_static_solid_cells.clear()
	var width := ceili(bounds.x / CELL)
	var height := ceili(bounds.y / CELL)
	_occupancy_width = width
	var occupied := PackedByteArray()
	occupied.resize(width * height)
	var touched: Array[int] = []
	# Rasterize only cells overlapping each obstacle, preserving exact body
	# clearance tests and the original row-major ordering of occupied cells.
	for obstacle: Dictionary in walls:
		var rect := _obstacle_bounds(obstacle, RADIUS)
		var low := cell(rect.position)
		var high := cell(rect.end)
		for y in range(maxi(_grid_region.position.y, low.y), mini(_grid_region.end.y - 1, high.y) + 1):
			for x in range(maxi(_grid_region.position.x, low.x), mini(_grid_region.end.x - 1, high.x) + 1):
				var index := y * width + x
				if occupied[index] == 0 and _contains(obstacle, Vector2(x + 0.5, y + 0.5) * CELL, RADIUS):
					occupied[index] = 1
					touched.append(index)
	for forbidden: Rect2 in _walkable_voids:
		var rect := forbidden.grow(RADIUS)
		var low := cell(rect.position)
		var high := cell(rect.end)
		for y: int in range(maxi(_grid_region.position.y, low.y), mini(_grid_region.end.y - 1, high.y) + 1):
			for x: int in range(maxi(_grid_region.position.x, low.x), mini(_grid_region.end.x - 1, high.x) + 1):
				var index := y * width + x
				var p := Vector2(x + 0.5, y + 0.5) * CELL
				if occupied[index] == 0 and _segment_rect(p, p, rect):
					occupied[index] = 1
					touched.append(index)
	# Rasterize just the perimeter, then sort only occupied cells. A 256m
	# empty map no longer scans its 1,048,576 floor cells in GDScript.
	for y: int in range(_grid_region.position.y, _grid_region.end.y):
		for x: int in [_grid_region.position.x, _grid_region.end.x - 1]:
			var p := Vector2(x + 0.5, y + 0.5) * CELL
			if not _inside_map(p, RADIUS) and occupied[y * width + x] == 0:
				occupied[y * width + x] = 1
				touched.append(y * width + x)
	for x: int in range(_grid_region.position.x, _grid_region.end.x):
		for y: int in [_grid_region.position.y, _grid_region.end.y - 1]:
			var p := Vector2(x + 0.5, y + 0.5) * CELL
			if not _inside_map(p, RADIUS) and occupied[y * width + x] == 0:
				occupied[y * width + x] = 1
				touched.append(y * width + x)
	touched.sort()
	for index: int in touched:
		_static_solid_cells.append(Vector2i(index % width, index / width))
	_static_occupancy = occupied

func _static_cell_solid(coordinate: Vector2i) -> bool:
	var index := coordinate.y * _occupancy_width + coordinate.x
	return index >= 0 and index < _static_occupancy.size() and _static_occupancy[index] != 0

func _door_grid_cells(assumed_open: Array) -> Dictionary:
	var cells: Dictionary = {}
	for obstacle: Dictionary in _door_blockers(assumed_open, true):
		var rect: Rect2 = _obstacle_bounds(obstacle, RADIUS)
		var low := cell(rect.position)
		var high := cell(rect.end)
		for y: int in range(maxi(_grid_region.position.y, low.y), mini(_grid_region.end.y - 1, high.y) + 1):
			for x: int in range(maxi(_grid_region.position.x, low.x), mini(_grid_region.end.x - 1, high.x) + 1):
				var coordinate := Vector2i(x, y)
				var point := Vector2(x + 0.5, y + 0.5) * CELL
				if not cells.has(coordinate) and _contains(obstacle, point, RADIUS):
					cells[coordinate] = true
	return cells

func _sync_grid_doors() -> void:
	# Door movement changes a small set of solid cells. Retain the original
	# graph and static occupancy instead of reallocating every A* point.
	var next: Dictionary = _door_grid_cells([])
	for coordinate: Vector2i in _main_door_cells:
		if not next.has(coordinate) and not _static_cell_solid(coordinate):
			grid.set_point_solid(coordinate, false)
	for coordinate: Vector2i in next:
		if not _main_door_cells.has(coordinate):
			grid.set_point_solid(coordinate, true)
	_main_door_cells = next

func _make_grid(assumed_open: Array, check_edges: bool = false) -> AStarGrid2D:
	var astar: AStarGrid2D
	if check_edges:
		var checked := EdgeCheckedGrid.new()
		checked.navigation = weakref(self)
		checked.assumed_open = assumed_open.duplicate()
		astar = checked
	else:
		astar = AStarGrid2D.new()
	astar.region = _grid_region
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(CELL * 0.5, CELL * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for solid: Vector2i in _static_solid_cells:
		astar.set_point_solid(solid)
	for solid: Vector2i in _door_grid_cells(assumed_open):
		astar.set_point_solid(solid)
	return astar

func _obstacle_bounds(obstacle: Dictionary, padding: float) -> Rect2:
	var angle := _obstacle_angle(obstacle)
	if absf(angle) < 0.000001: return _axis_rect(obstacle, padding)
	var half := Vector2(float(obstacle.w), float(obstacle.d)) * 0.5 + Vector2.ONE * padding
	var extent := Vector2(absf(cos(angle)) * half.x + absf(sin(angle)) * half.y, absf(sin(angle)) * half.x + absf(cos(angle)) * half.y)
	return Rect2(Vector2(float(obstacle.x), float(obstacle.z)) - extent, extent * 2.0)

func _door_blockers(assumed_open: Array, movement: bool) -> Array:
	_door_pose_key()
	var cache_key: Array = [_exact_door_revision, assumed_open.duplicate(), movement]
	if _door_blocker_cache.has(cache_key): return _door_blocker_cache[cache_key]
	var result: Array = []
	for door: Dictionary in doors:
		if bool(door.get("destroyed", false)):
			continue
		var state: String = str(door.get("state", "CLOSED"))
		var hypothetical: bool = assumed_open.has(str(door.get("id", ""))) and state != "OPEN"
		if hypothetical:
			# The eventual swing side is not known until an operator arrives.
			continue
		if movement and state != "OPEN":
			# Actors wait until the leaf has finished opening. This gate is an
			# interaction rule; sight uses only the rendered leaf's current pose.
			result.append(door)
		var leaf := _leaf_obstacle(door)
		if not leaf.is_empty(): result.append(leaf)
	if _door_blocker_cache.size() >= 64: _door_blocker_cache.clear()
	_door_blocker_cache[cache_key] = result
	return result

func _leaf_obstacle(door: Dictionary) -> Dictionary:
	# Doors can mutate in place between grid revisions (including tiny swings).
	# Compare the live pose, never just nav.revision, to keep LOS exact.
	var key: String = str(door.get("id", ""))
	var pose: Array = [door.get("x"), door.get("z"), door.get("w", 1.6), door.get("d", 1.6), door.get("axis", "x"), door.get("state", "CLOSED"), door.get("progress", 0.0), door.get("swing_sign", -1.0), door.get("hinge_side", -1.0), door.get("destroyed", false), door.get("height", 2.1), door.get("base_height", 0.0), door.get("material", "wood"), door.get("opacity", null), door.get("resistance", null), door.get("penetration_resistance", null), door.get("opaque", null)]
	var cached: Array = _leaf_cache.get(key, [])
	if cached.is_empty() or cached[0] != pose:
		cached = [pose, DoorGeometry.leaf_obstacle(door)]
		_leaf_cache[key] = cached
	return cached[1]

func blockers(assumed_open: Array = [], movement: bool = true) -> Array:
	var result: Array = []
	for obstacle: Dictionary in walls:
		if movement or obstacle.get("cover", "full") != "low":
			result.append(obstacle)
	result.append_array(_door_blockers(assumed_open, movement))
	return result

func _contains(obstacle: Dictionary, point: Vector2, padding: float) -> bool:
	if _geometry_scope and obstacle.has("_compiled_geometry") and (padding == RADIUS or padding == 0.0):
		var compiled: Array = obstacle._compiled_geometry
		var rectangle: Rect2 = compiled[2 if padding == RADIUS else 1]
		if bool(compiled[0]): return rectangle.has_point(point)
		return rectangle.has_point((point - (compiled[3] as Vector2)).rotated(-float(compiled[4])))
	if absf(_obstacle_angle(obstacle)) < 0.000001:
		return _axis_rect(obstacle, padding).has_point(point)
	return _obstacle_local_rect(obstacle, padding).has_point(_obstacle_local_point(obstacle, point))

func _segment_obstacle(a: Vector2, b: Vector2, obstacle: Dictionary, padding: float) -> bool:
	if _geometry_scope and obstacle.has("_compiled_geometry") and (padding == RADIUS or padding == 0.0):
		var compiled: Array = obstacle._compiled_geometry
		var rectangle: Rect2 = compiled[2 if padding == RADIUS else 1]
		if bool(compiled[0]): return _segment_rect(a, b, rectangle)
		var bounds_rect: Rect2 = compiled[6 if padding == RADIUS else 5]
		if not _segment_rect(a, b, bounds_rect): return false
		var center: Vector2 = compiled[3]
		var angle: float = compiled[4]
		return _segment_rect((a - center).rotated(-angle), (b - center).rotated(-angle), rectangle)
	if absf(_obstacle_angle(obstacle)) < 0.000001:
		return _segment_rect(a, b, _axis_rect(obstacle, padding))
	# Most long-axis/rotated furniture is far from a short movement edge.
	if not _segment_rect(a, b, _obstacle_bounds(obstacle, padding)): return false
	return _segment_rect(_obstacle_local_point(obstacle, a), _obstacle_local_point(obstacle, b), _obstacle_local_rect(obstacle, padding))

func _compile_obstacle(obstacle: Dictionary) -> bool:
	var angle := _obstacle_angle(obstacle)
	var aligned := absf(angle) < 0.000001
	var base := float(obstacle.get("base_height", 0.0))
	var top := base + obstacle_height(obstacle)
	var center := Vector2(float(obstacle.get("x", 0)), float(obstacle.get("z", 0)))
	var width := float(obstacle.get("w", 0.25))
	var depth := float(obstacle.get("d", 0.25))
	var cached: Array = obstacle.get("_compiled_geometry", [])
	if cached.size() == 11 and cached[3] == center and cached[4] == angle and cached[7] == base and cached[8] == top and cached[9] == width and cached[10] == depth:
		return false
	obstacle["_compiled_geometry"] = [aligned,
		_axis_rect(obstacle, 0.0) if aligned else _obstacle_local_rect(obstacle, 0.0),
		_axis_rect(obstacle, RADIUS) if aligned else _obstacle_local_rect(obstacle, RADIUS),
		center, angle,
		_obstacle_bounds(obstacle, 0.0), _obstacle_bounds(obstacle, RADIUS),
		base, top, width, depth]
	return true

func _obstacle_angle(obstacle: Dictionary) -> float:
	# Imported furniture rotates around Godot +Y; floor atan2 has the opposite sign.
	return float(obstacle.leaf_angle) if obstacle.has("leaf_angle") else -float(obstacle.get("rotation", 0.0))

func _axis_rect(obstacle: Dictionary, padding: float) -> Rect2:
	var width := float(obstacle.get("w", 0.25))
	var depth := float(obstacle.get("d", 0.25))
	return Rect2(float(obstacle.get("x", 0.0)) - width * 0.5 - padding, float(obstacle.get("z", 0.0)) - depth * 0.5 - padding, width + padding * 2.0, depth + padding * 2.0)

func _obstacle_local_point(obstacle: Dictionary, point: Vector2) -> Vector2:
	var offset := point - Vector2(float(obstacle.get("x", 0)), float(obstacle.get("z", 0)))
	var angle := _obstacle_angle(obstacle)
	return offset if absf(angle) < 0.000001 else offset.rotated(-angle)

func _obstacle_local_rect(obstacle: Dictionary, padding: float = 0.0) -> Rect2:
	var half := Vector2(float(obstacle.get("w", 0.25)), float(obstacle.get("d", 0.25))) * 0.5 + Vector2.ONE * padding
	return Rect2(-half, half * 2.0)

func obstacle_corners(obstacle: Dictionary) -> PackedVector2Array:
	var rect := _obstacle_local_rect(obstacle)
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var center := Vector2(float(obstacle.get("x", 0)), float(obstacle.get("z", 0)))
	for i in range(4): points[i] = points[i].rotated(_obstacle_angle(obstacle)) + center
	return points

func _rect(obstacle: Dictionary, padding: float = 0.0) -> Rect2:
	return _obstacle_bounds(obstacle, padding)

func cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.y / CELL))

func _static_bucket(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / STATIC_BUCKET_SIZE), floori(point.y / STATIC_BUCKET_SIZE))

func _static_candidates(a: Vector2, b: Vector2, padding: float) -> Array:
	# Scoped buckets enclose the exact rotated footprint plus actor clearance.
	# Outside a scope retain live full scans (including direct editor/test edits).
	if not _geometry_scope or padding > RADIUS: return walls
	var first := _static_bucket(Vector2(minf(a.x,b.x), minf(a.y,b.y)))
	var last := _static_bucket(Vector2(maxf(a.x,b.x), maxf(a.y,b.y)))
	if (last.x-first.x+1) * (last.y-first.y+1) >= maxi(1,walls.size()/2): return walls
	var indices: Dictionary = {}
	for y: int in range(first.y,last.y+1):
		for x: int in range(first.x,last.x+1):
			for index: int in _static_buckets.get(Vector2i(x,y),[]): indices[index] = true
	var ordered: Array = indices.keys()
	ordered.sort()
	var result: Array = []
	for index: int in ordered: result.append(walls[index])
	return result

func walkable(point: Vector2, assumed_open: Array = []) -> bool:
	if not _movement_floor_clear(point, point, RADIUS):
		return false
	for obstacle: Dictionary in _static_candidates(point, point, RADIUS):
		if _contains(obstacle, point, RADIUS): return false
	for obstacle: Dictionary in _door_blockers(assumed_open, true):
		if _contains(obstacle, point, RADIUS): return false
	return true

func segment_clear(a: Vector2, b: Vector2, padding: float = 0.0, assumed_open: Array = []) -> bool:
	# A positive actor radius asks for movement; zero-radius rays ask for sight.
	# Low furniture stops movement while leaving the sight line available.
	# Test static blockers first. A wall hit needs no door transforms or
	# temporary combined blocker array, while preserving obstacle order.
	if padding > 0.0 and (_bounded_movement or not _walkable_voids.is_empty()) and not _movement_floor_clear(a, b, padding): return false
	for obstacle: Dictionary in _static_candidates(a, b, padding):
		if padding <= 0.0 and obstacle.get("cover", "full") == "low": continue
		if _segment_obstacle(a, b, obstacle, padding): return false
	for obstacle: Dictionary in _door_blockers(assumed_open, padding > 0.0):
		if _segment_obstacle(a, b, obstacle, padding): return false
	return true

func cover_count(a: Vector2, b: Vector2) -> int:
	var count: int = 0
	for obstacle: Dictionary in low_cover:
		if _segment_obstacle(a, b, obstacle, 0.0):
			count += 1
	return count

func shot_clear(a: Vector2, b: Vector2) -> bool:
	# Thin wall penetration changes firing only. Observations still use
	# segment_clear(), so a penetrable wall never reveals its hidden occupant.
	for obstacle: Dictionary in _static_candidates(a, b, 0.0):
		if obstacle.get("cover", "full") == "low" or bool(obstacle.get("thin", false)):
			continue
		if _segment_obstacle(a, b, obstacle, 0.0):
			return false
	for obstacle: Dictionary in _door_blockers([], false):
		if _segment_obstacle(a, b, obstacle, 0.0):
			return false
	return true

func obstacle_height(obstacle: Dictionary) -> float:
	if obstacle.has("height"): return maxf(0.0, float(obstacle.height))
	return 0.8 if obstacle.get("cover", "full") == "low" else 2.6

func effective_vision_range(observer: Dictionary) -> float:
	var light := _lighting
	var position := Spatial.position(observer)
	for region: Array in _lighting_regions:
		if (region[0] as Rect2).has_point(position):
			light *= float(region[1])
			break
	return maxf(0.0, float(observer.get("vision_range", 10.0))) * (0.55 + 0.45 * light)

func obstacle_opacity(obstacle: Dictionary) -> float:
	if obstacle.has("opacity"): return clampf(float(obstacle.opacity), 0.0, 1.0)
	if obstacle.has("opaque"): return 1.0 if bool(obstacle.opaque) else 0.0
	var material := str(obstacle.get("material", ""))
	return 0.0 if material in ["glass", "foliage"] else 1.0

func obstacle_resistance(obstacle: Dictionary) -> float:
	if obstacle.has("resistance"):
		return maxf(0.0, float(obstacle.resistance))
	if obstacle.has("penetration_resistance"):
		return maxf(0.0, float(obstacle.penetration_resistance))
	# Legacy thin describes a physical material, never an observation shortcut.
	if bool(obstacle.get("thin", false)) and not obstacle.has("material"):
		return 0.35
	match str(obstacle.get("material", "concrete")):
		"wood": return 1.0
		"glass": return 0.25
		"plaster", "drywall": return 0.5
		"fabric", "cloth": return 0.05
		"foliage": return 0.03
		"metal", "steel": return 6.0
		"masonry", "brick": return 3.5
	return 4.0

func height_blockers(height: float) -> Array:
	var result: Array = []
	for obstacle: Dictionary in walls:
		if _blocks_horizontal_height(obstacle, height): result.append(obstacle)
	for obstacle: Dictionary in _door_blockers([], false):
		if _blocks_horizontal_height(obstacle, height): result.append(obstacle)
	return result

func _blocks_horizontal_height(obstacle: Dictionary, height: float) -> bool:
	var base := float(obstacle.get("base_height", 0.0))
	return obstacle_opacity(obstacle) >= 0.5 and height >= base and height <= base + obstacle_height(obstacle)

func _height_intersects(a: Vector2, b: Vector2, from_height: float, to_height: float, obstacle: Dictionary) -> bool:
	# Clip the floor segment against the exact oriented footprint, then test
	# the vertical ray only across its entry/exit interval. A low obstacle near
	# a tall observer differs from the same obstacle immediately before a target.
	var compiled: Array = obstacle.get("_compiled_geometry", []) if _geometry_scope else []
	var base := float(obstacle.get("base_height", 0.0)) if compiled.is_empty() else float(compiled[7])
	var top := base + obstacle_height(obstacle) if compiled.is_empty() else float(compiled[8])
	if minf(from_height, to_height) > top or maxf(from_height, to_height) < base: return false
	var axis_aligned := absf(_obstacle_angle(obstacle)) < 0.000001 if compiled.is_empty() else bool(compiled[0])
	var start: Vector2 = a
	var end: Vector2 = b
	var rect: Rect2
	if compiled.is_empty():
		if not axis_aligned:
			start = _obstacle_local_point(obstacle, a)
			end = _obstacle_local_point(obstacle, b)
		rect = _axis_rect(obstacle, 0.0) if axis_aligned else _obstacle_local_rect(obstacle)
	else:
		if not axis_aligned:
			var center: Vector2 = compiled[3]
			var angle: float = compiled[4]
			start = (a - center).rotated(-angle)
			end = (b - center).rotated(-angle)
		rect = compiled[1]
	if (start.x < rect.position.x and end.x < rect.position.x) or (start.x > rect.end.x and end.x > rect.end.x) or (start.y < rect.position.y and end.y < rect.position.y) or (start.y > rect.end.y and end.y > rect.end.y): return false
	var direction := end - start
	var near_t := 0.0
	var far_t := 1.0
	for axis in range(2):
		if absf(direction[axis]) < 0.000001:
			if start[axis] < rect.position[axis] or start[axis] > rect.end[axis]: return false
		else:
			var first: float = (rect.position[axis] - start[axis]) / direction[axis]
			var last: float = (rect.end[axis] - start[axis]) / direction[axis]
			near_t = maxf(near_t, minf(first, last))
			far_t = minf(far_t, maxf(first, last))
			if near_t > far_t: return false
	var entry_height := lerpf(from_height, to_height, near_t)
	var exit_height := lerpf(from_height, to_height, far_t)
	return minf(entry_height, exit_height) <= top and maxf(entry_height, exit_height) >= base

func sight_clear_height(a: Vector2, b: Vector2, from_height: float, to_height: float) -> bool:
	var key := _ray_key(a, b, from_height, to_height)
	if _sight_ray_cache.has(key): return bool(_sight_ray_cache[key])
	var clear := _uncached_sight_clear_height(a, b, from_height, to_height)
	if _sight_ray_cache.size() >= 1024: _sight_ray_cache.clear()
	_sight_ray_cache[key] = clear
	return clear

func physical_clear_height(a: Vector2, b: Vector2, from_height: float, to_height: float) -> bool:
	# Physical placement differs from optical opacity and penetration budget.
	# Transparent/penetrable material still stops a leaned head or weapon.
	var key := _ray_key(a, b, from_height, to_height)
	if _physical_ray_cache.has(key): return bool(_physical_ray_cache[key])
	var clear := true
	for obstacle: Dictionary in _static_candidates(a, b, 0.0):
		if _height_intersects(a, b, from_height, to_height, obstacle):
			clear = false
			break
	if clear:
		for obstacle: Dictionary in _door_blockers([], false):
			if _height_intersects(a, b, from_height, to_height, obstacle):
				clear = false
				break
	if _physical_ray_cache.size() >= 512: _physical_ray_cache.clear()
	_physical_ray_cache[key] = clear
	return clear

func _uncached_sight_clear_height(a: Vector2, b: Vector2, from_height: float, to_height: float) -> bool:
	for obstacle: Dictionary in _static_candidates(a, b, 0.0):
		if obstacle_opacity(obstacle) >= 0.5 and _height_intersects(a, b, from_height, to_height, obstacle): return false
	for obstacle: Dictionary in _door_blockers([], false):
		if obstacle_opacity(obstacle) >= 0.5 and _height_intersects(a, b, from_height, to_height, obstacle): return false
	return true

func sight_transmission_height(a: Vector2, b: Vector2, from_height: float, to_height: float) -> float:
	var transmission := 1.0
	for obstacle: Dictionary in _static_candidates(a, b, 0.0):
		var opacity := obstacle_opacity(obstacle)
		if opacity <= 0.0 or not _height_intersects(a, b, from_height, to_height, obstacle): continue
		if opacity >= 0.5: return 0.0
		transmission *= 1.0 - opacity
	for obstacle: Dictionary in _door_blockers([], false):
		var opacity := obstacle_opacity(obstacle)
		if opacity <= 0.0 or not _height_intersects(a, b, from_height, to_height, obstacle): continue
		if opacity >= 0.5: return 0.0
		transmission *= 1.0 - opacity
	return transmission

func shot_profile_height(a: Vector2, b: Vector2, from_height: float, to_height: float, penetration_budget: float = 0.0) -> Dictionary:
	var key := _ray_key(a, b, from_height, to_height)
	key.append(penetration_budget)
	if _shot_ray_cache.has(key): return _shot_ray_cache[key]
	var profile := _uncached_shot_profile_height(a, b, from_height, to_height, penetration_budget)
	if _shot_ray_cache.size() >= 1024: _shot_ray_cache.clear()
	_shot_ray_cache[key] = profile
	return profile

func _uncached_shot_profile_height(a: Vector2, b: Vector2, from_height: float, to_height: float, penetration_budget: float) -> Dictionary:
	var remaining := maxf(0.0, penetration_budget)
	var transmission := 1.0
	var penetrations := 0
	var crossed_groups: Dictionary = {}
	# Static hits need no door transform or combined temporary obstacle array.
	for obstacle: Dictionary in _static_candidates(a, b, 0.0):
		if not _height_intersects(a, b, from_height, to_height, obstacle): continue
		var group := str(obstacle.get("_physical_group", ""))
		if not group.is_empty():
			if crossed_groups.has(group): continue
			crossed_groups[group] = true
		var resistance := obstacle_resistance(obstacle)
		if resistance > remaining + 0.000001:
			return {"clear": false, "transmission": 0.0, "penetrations": penetrations}
		remaining -= resistance
		transmission *= clampf(1.0 - resistance / maxf(penetration_budget, 0.001) * 0.55, 0.15, 1.0)
		penetrations += 1
	for obstacle: Dictionary in _door_blockers([], false):
		if not _height_intersects(a, b, from_height, to_height, obstacle): continue
		var resistance := obstacle_resistance(obstacle)
		if resistance > remaining + 0.000001:
			return {"clear": false, "transmission": 0.0, "penetrations": penetrations}
		remaining -= resistance
		transmission *= clampf(1.0 - resistance / maxf(penetration_budget, 0.001) * 0.55, 0.15, 1.0)
		penetrations += 1
	return {"clear": true, "transmission": transmission, "penetrations": penetrations}

func shot_clear_height(a: Vector2, b: Vector2, from_height: float, to_height: float, penetration_budget: float = 0.0) -> bool:
	return bool(shot_profile_height(a, b, from_height, to_height, penetration_budget).clear)

func _door_pose_key() -> Array:
	if _geometry_scope and not _scope_door_dirty: return _scope_door_key
	var doors_pose: Array = []
	for door: Dictionary in doors:
		doors_pose.append([door.get("id", ""), door.get("x", 0), door.get("z", 0), door.get("w", 1.6), door.get("d", 1.6), door.get("axis", "x"), door.get("state", "CLOSED"), door.get("progress", 0.0), door.get("swing_sign", -1.0), door.get("hinge_side", -1.0), door.get("destroyed", false), door.get("height", 2.1), door.get("base_height", 0), door.get("material", "wood"), door.get("opacity", null), door.get("resistance", null), door.get("penetration_resistance", null), door.get("opaque", null)])
	# All stationary rays share one immutable geometry key. Retaining a fresh
	# full door array for every cached sample would multiply memory by cache size.
	if doors_pose == _last_door_key:
		_scope_door_key = _last_door_key
		_scope_door_dirty = false
		return _last_door_key
	_last_door_key = doors_pose
	_exact_door_revision += 1
	_scope_door_key = doors_pose
	_scope_door_dirty = false
	return _last_door_key

func _ray_key(a: Vector2, b: Vector2, from_height: float, to_height: float) -> Array:
	# The full live pose comparison remains exact, including direct edits
	# outside a scope. Cached ray keys hash one revision instead of every
	# nested door field for every sample in the unchanged geometry.
	_door_pose_key()
	return [revision, a.x, a.y, b.x, b.y, from_height, to_height, _exact_door_revision]

func _exposure_key(observer: Dictionary, target: Dictionary) -> Array:
	var origin := Spatial.position(observer)
	var destination := Spatial.position(target)
	_door_pose_key()
	return [revision, origin.x, origin.y, Spatial.eye_height(observer), destination.x, destination.y, Spatial.body_height(target), target.get("base_height", 0), target.get("body_facing", target.get("facing", 0)), observer.get("_cone_facing", null), observer.get("_cone_fov", null), observer.get("_cone_range", null), _exact_door_revision]

func exposed_fraction(observer: Dictionary, target: Dictionary) -> float:
	var key := _exposure_key(observer, target)
	if _exposure_cache.has(key): return float(_exposure_cache[key])
	var origin := Spatial.position(observer)
	var center := Spatial.position(target)
	var from_height := Spatial.eye_height(observer)
	var result := 0.0
	for sample: Dictionary in Spatial.samples(target):
		var destination: Vector2 = sample.point
		var height: float = sample.height
		if observer.has("_cone_range"):
			var offset := destination - origin
			if offset.length_squared() > pow(float(observer._cone_range), 2): continue
			if offset.length_squared() > 0.02 and absf(angle_difference(float(observer.get("_cone_facing", 0.0)), offset.angle())) > deg_to_rad(float(observer.get("_cone_fov", 110))) * 0.5: continue
		# A shoulder cannot become a remote sensor through a wall which cuts
		# across the actor's body. Prevent wall-overlapping test/spawn geometry
		# from exposing a sample on the opposite side of that wall.
		if not sight_clear_height(center, destination, height, height): continue
		result += float(sample.weight) * sight_transmission_height(origin, destination, from_height, height)
	if _exposure_cache.size() >= 512: _exposure_cache.clear()
	_exposure_cache[key] = result
	return clampf(result, 0.0, 1.0)

func shot_exposure(origin: Vector2, origin_height: float, target: Dictionary, penetration_budget: float = 0.0) -> float:
	var observer := {"x": origin.x, "z": origin.y, "eye_height": origin_height, "body_height": maxf(origin_height, 1.75)}
	var key := _exposure_key(observer, target)
	key.append(penetration_budget)
	if _shot_exposure_cache.has(key): return float(_shot_exposure_cache[key])
	var result := 0.0
	for sample: Dictionary in Spatial.samples(target):
		var destination: Vector2 = sample.point
		var height: float = sample.height
		if not sight_clear_height(Spatial.position(target), destination, height, height): continue
		var profile := shot_profile_height(origin, destination, origin_height, height, penetration_budget)
		if bool(profile.clear): result += float(sample.weight) * float(profile.transmission)
	result = clampf(result, 0.0, 1.0)
	if _shot_exposure_cache.size() >= 512: _shot_exposure_cache.clear()
	_shot_exposure_cache[key] = result
	return result

func _segment_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	# Most visibility/movement segments are far from most map obstacles.
	# Reject disjoint bounds before division and per-axis slab clipping.
	if (a.x < rect.position.x and b.x < rect.position.x) or (a.x > rect.end.x and b.x > rect.end.x) or (a.y < rect.position.y and b.y < rect.position.y) or (a.y > rect.end.y and b.y > rect.end.y):
		return false
	var direction: Vector2 = b - a
	var near_t: float = 0.0
	var far_t: float = 1.0
	for axis: int in range(2):
		var start: float = a[axis]
		var delta: float = direction[axis]
		var low: float = rect.position[axis]
		var high: float = rect.end[axis]
		if absf(delta) < 0.000001:
			if start < low or start > high:
				return false
		else:
			var t1: float = (low - start) / delta
			var t2: float = (high - start) / delta
			near_t = maxf(near_t, minf(t1, t2))
			far_t = minf(far_t, maxf(t1, t2))
			if near_t > far_t:
				return false
	return near_t <= far_t

func path(start: Vector2, target: Vector2, assumed_open: Array = []) -> Array:
	if not walkable(start, assumed_open) or not walkable(target, assumed_open):
		return []
	if segment_clear(start, target, RADIUS, assumed_open):
		return [[target.x, target.y]]
	# A hypothetical-open planning query needs only its own graph. Avoid
	# allocating a second full-sized live graph that the query never uses.
	if assumed_open.is_empty():
		if grid == null:
			grid = _make_grid([])
			_main_door_cells = _door_grid_cells([])
			_grid_dirty = false
		elif _grid_dirty:
			_sync_grid_doors()
			_grid_dirty = false
	var astar: AStarGrid2D = grid
	if not assumed_open.is_empty():
		var sorted_ids: Array = assumed_open.duplicate()
		sorted_ids.sort()
		var key: String = JSON.stringify(sorted_ids)
		if not _preview_grids.has(key):
			# A bounded preview cache prevents large temporary planning graphs
			# accumulating for every distinct hypothetical door combination.
			var preview_limit: int = 1 if _grid_region.size.x * _grid_region.size.y > 1048576 else 2
			if _preview_grids.size() >= preview_limit: _preview_grids.clear()
			_preview_grids[key] = _make_grid(assumed_open)
		astar = _preview_grids[key]
	_needs_edge_retry = false
	var result := _grid_path(start, target, assumed_open, astar)
	if not result.is_empty() or not _needs_edge_retry:
		return result
	# Center-point occupancy can miss a tiny corner crossed by a grid edge.
	# Retry with segment costs only for that case, preserving normal-path speed.
	return _grid_path(start, target, assumed_open, _make_grid(assumed_open, true))

func _grid_path(start: Vector2, target: Vector2, assumed_open: Array, astar: AStarGrid2D) -> Array:
	var first: Vector2i = _nearest_cell(start, astar, assumed_open)
	var last: Vector2i = _nearest_cell(target, astar, assumed_open)
	if first.x < 0 or last.x < 0:
		return []
	var raw: PackedVector2Array = astar.get_point_path(first, last)
	if raw.is_empty():
		return []
	var points: Array[Vector2] = [start]
	for point: Vector2 in raw:
		points.append(point)
	points.append(target)
	var smoothed: Array = []
	var cursor: int = 0
	while cursor < points.size() - 1:
		var next: int = -1
		for candidate: int in range(points.size() - 1, cursor, -1):
			if segment_clear(points[cursor], points[candidate], RADIUS, assumed_open):
				next = candidate
				break
		if next < 0:
			# Never fall back to the immediate grid neighbour without checking
			# it. That silently emitted colliding routes around rotated corners.
			_needs_edge_retry = true
			return []
		var p: Vector2 = points[next]
		smoothed.append([p.x, p.y])
		cursor = next
	return smoothed

func _nearest_cell(point: Vector2, astar: AStarGrid2D, assumed_open: Array = []) -> Vector2i:
	var center: Vector2i = cell(point)
	if astar.is_in_boundsv(center) and not astar.is_point_solid(center) and segment_clear(point, astar.get_point_position(center), RADIUS, assumed_open):
		return center
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: float = INF
	for y: int in range(center.y - 2, center.y + 3):
		for x: int in range(center.x - 2, center.x + 3):
			var candidate: Vector2i = Vector2i(x, y)
			if astar.is_in_boundsv(candidate) and not astar.is_point_solid(candidate):
				var p: Vector2 = astar.get_point_position(candidate)
				var distance: float = point.distance_squared_to(p)
				if distance < best_distance and segment_clear(point, p, RADIUS, assumed_open):
					best_distance = distance
					best = candidate
	return best

func approach(start: Vector2, object: Dictionary, distance: float = 0.9, assumed_open: Array = []) -> Array:
	var center: Vector2 = Vector2(float(object.get("x", 0.0)), float(object.get("z", 0.0)))
	var candidates: Array[Vector2] = []
	if object.has("axis"):
		var normal: Vector2 = Vector2(0, 1) if object.get("axis", "x") == "x" else Vector2(1, 0)
		var handle: Vector2 = DoorGeometry.handle_floor(object)
		var progress := 1.0 if object.get("state", "CLOSED") == "OPEN" else float(object.get("progress", 0.0))
		if progress > 0.0 and not bool(object.get("destroyed", false)):
			var actual_handle := DoorGeometry.handle_world(object, progress)
			var actual_point := Vector2(actual_handle.x, actual_handle.z)
			var leaf := _leaf_obstacle(object)
			var leaf_normal := Vector2.from_angle(float(leaf.get("leaf_angle", 0.0)) + PI * 0.5)
			for gap: float in [DoorGeometry.APPROACH_DISTANCE, 0.6]:
				candidates.append(actual_point + leaf_normal * gap)
				candidates.append(actual_point - leaf_normal * gap)
		# Closed-frame sides are still useful when the swung handle is against
		# a wall or lies across the aperture's temporary movement gate.
		candidates.append(handle + normal * DoorGeometry.APPROACH_DISTANCE)
		candidates.append(handle - normal * DoorGeometry.APPROACH_DISTANCE)
	else:
		for i: int in range(8):
			candidates.append(center + Vector2.from_angle(float(i) * TAU / 8.0) * distance)
	var best: Array = []
	var length: float = INF
	var best_index := candidates.size()
	var ordered: Array = []
	for index in range(candidates.size()):
		ordered.append({"point": candidates[index], "index": index, "bound": start.distance_to(candidates[index])})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.bound < b.bound or (a.bound == b.bound and a.index < b.index))
	for entry: Dictionary in ordered:
		# No valid polyline can beat its straight-line lower bound. Preserve
		# authored candidate order for exact-length ties while avoiding searches
		# to the far/unreachable side once a shorter reachable approach exists.
		if float(entry.bound) > length + 0.000001: continue
		var candidate: Vector2 = entry.point
		var route: Array = path(start, candidate, assumed_open)
		if route.is_empty():
			continue
		var route_length: float = 0.0
		var previous: Vector2 = start
		for coordinate: Array in route:
			var point: Vector2 = Vector2(float(coordinate[0]), float(coordinate[1]))
			route_length += previous.distance_to(point)
			previous = point
		if route_length < length or (route_length == length and int(entry.index) < best_index):
			length = route_length
			best_index = int(entry.index)
			best = route
	return best

func blocked_by_leaf(point: Vector2) -> bool:
	for door: Dictionary in doors:
		if door.get("state", "CLOSED") in ["OPEN", "OPENING"] and DoorGeometry.overlaps_actor(door, -1.0, point, RADIUS):
			return true
	return false
