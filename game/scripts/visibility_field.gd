class_name BreachVisibilityField
extends RefCounted
## Continuous sight polygons. No world-space occupancy grid is rasterized.
const Navigation = preload("res://scripts/navigation.gd")
const DoorGeometry = preload("res://scripts/door_geometry.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const CORNER_EPSILON: float = 0.00001
const RAY_BUCKET_COUNT: int = 180
var nav = Navigation.new()
var bounds := Vector2.ZERO
var polygons: Array[PackedVector2Array] = []
var _polygon_bounds: Array[Rect2] = []
var revision: int = 0
var _signature: String = ""
var _edges := PackedVector2Array()
var _corners := PackedVector2Array()
var _edge_heights := PackedVector2Array()
var _corner_heights := PackedVector2Array()
var _geometry_signature: String = ""
var _static_edge_count: int = 0
var _static_corner_count: int = 0
var _observer_cache: Dictionary = {}
var _unit_polygons: Dictionary = {}
var _ray_offsets := PackedVector2Array()
var _ray_vectors := PackedVector2Array()
var _ray_crosses := PackedFloat64Array()
var _ray_buckets: Array[Array] = []

func build(mission: Dictionary) -> void:
	var b: Array = mission.get("bounds", [24, 20])
	bounds = Vector2(float(b[0]), float(b[1]))
	nav.build(mission, [])
	_edges.clear()
	_corners.clear()
	_edge_heights.clear()
	_corner_heights.clear()
	for obstacle: Dictionary in nav.walls:
		_append_obstacle_geometry(obstacle)
	_static_edge_count = _edge_heights.size()
	_static_corner_count = _corners.size()
	polygons.clear()
	_polygon_bounds.clear()
	_signature = ""
	_geometry_signature = ""
	_observer_cache.clear()
	_unit_polygons.clear()

func update(units: Array, doors: Array, smoke_zones: Array = []) -> bool:
	var signature: Array = []
	for unit: Dictionary in units:
		signature.append([unit.get("id", ""), unit.x, unit.z, unit.facing, float(unit.hp) > 0, float(unit.get("stunned", 0)) > 0, unit.get("fov", 110), nav.effective_vision_range(unit), Spatial.eye_height(unit)])
		signature.append([unit.get("peek_origin", []), unit.get("peek_facing", 0), float(unit.get("peek_remaining", 0)) > 0])
	var geometry: Array = []
	for door: Dictionary in doors:
		geometry.append([door.id, door.get("x", 0), door.get("z", 0), door.get("w", 1.6), door.get("d", 1.6), door.get("axis", "x"), door.state, door.get("progress", 0), door.get("swing_sign", -1), door.get("hinge_side", -1), door.get("destroyed", false), door.get("height", 2.1), door.get("base_height", 0), door.get("material", "wood"), door.get("opacity", null), door.get("opaque", null)])
	for smoke: Dictionary in smoke_zones:
		geometry.append([smoke.x, smoke.z, smoke.radius])
	var geometry_key := JSON.stringify(geometry)
	signature.append(geometry_key)
	var key := JSON.stringify(signature)
	if key == _signature:
		return false
	_signature = key
	if geometry_key != _geometry_signature:
		_geometry_signature = geometry_key
		_observer_cache.clear()
		nav.doors = doors
		# The immutable prefix belongs to walls/props; only door and smoke
		# geometry changes while the mission runs.
		_edges.resize(_static_edge_count * 2)
		_corners.resize(_static_corner_count)
		_edge_heights.resize(_static_edge_count)
		_corner_heights.resize(_static_corner_count)
		for obstacle: Dictionary in nav._door_blockers([], false):
			_append_obstacle_geometry(obstacle)
		for smoke: Dictionary in smoke_zones:
			var center: Vector2 = Vector2(float(smoke.x), float(smoke.z))
			for i: int in range(24):
				var a: Vector2 = center + Vector2.from_angle(TAU * float(i) / 24.0) * float(smoke.radius)
				var b: Vector2 = center + Vector2.from_angle(TAU * float(i + 1) / 24.0) * float(smoke.radius)
				_corners.append(a)
				_corner_heights.append(Vector2(-INF, INF))
				_edges.append(a)
				_edges.append(b)
				_edge_heights.append(Vector2(-INF, INF))
	polygons.clear()
	_polygon_bounds.clear()
	_unit_polygons.clear()
	var next_cache: Dictionary = {}
	var observers: Array = units.duplicate(false)
	for unit: Dictionary in units:
		if float(unit.get("peek_remaining", 0)) > 0 and unit.get("peek_origin", []).size() == 2:
			var peek_point := Vector2(float(unit.peek_origin[0]), float(unit.peek_origin[1]))
			if Spatial.position(unit).distance_to(peek_point) > Spatial.MAX_PEEK_LEAN or not nav.physical_clear_height(Spatial.position(unit), peek_point, Spatial.eye_height(unit), Spatial.eye_height(unit)):
				continue
			var peek: Dictionary = unit.duplicate(false)
			peek["_peek_observer"] = true
			peek.x = unit.peek_origin[0]
			peek.z = unit.peek_origin[1]
			peek.facing = unit.peek_facing
			peek.fov = 70
			observers.append(peek)
	for unit: Dictionary in observers:
		if float(unit.hp) <= 0 or float(unit.get("stunned", 0)) > 0:
			continue
		var origin := Vector2(float(unit.x), float(unit.z))
		var obscured: bool = false
		for smoke: Dictionary in smoke_zones:
			if origin.distance_to(Vector2(float(smoke.x), float(smoke.z))) < float(smoke.radius): obscured = true
		if obscured: continue
		var facing: float = float(unit.facing)
		var distance: float = nav.effective_vision_range(unit)
		var eye_height: float = Spatial.eye_height(unit)
		var half_angle: float = deg_to_rad(float(unit.get("fov", 110))) * 0.5
		var observer_key := JSON.stringify([origin.x, origin.y, facing, distance, half_angle, eye_height])
		if _observer_cache.has(observer_key):
			var cached: PackedVector2Array = _observer_cache[observer_key]
			_append_polygon(cached)
			next_cache[observer_key] = cached
			if not unit.get("_peek_observer", false): _unit_polygons[str(unit.get("id", ""))] = cached
			continue
		_prepare_rays(origin, distance, eye_height)
		var angles: Array[float] = []
		# Only the circular range limit needs tessellation; walls and cone sides
		# are exact line segments. Corner rays prevent cutting across occluders.
		var segments: int = maxi(32, ceili(half_angle * 2.0 / deg_to_rad(1.0)))
		for i in range(segments + 1):
			angles.append(lerpf(-half_angle, half_angle, float(i) / segments))
		for corner_index in range(_corners.size()):
			var corner: Vector2 = _corners[corner_index]
			var corner_height: Vector2 = _corner_heights[corner_index]
			if eye_height < corner_height.x or eye_height > corner_height.y: continue
			if origin.distance_squared_to(corner) > distance * distance:
				continue
			var angle := wrapf(origin.angle_to_point(corner) - facing, -PI, PI)
			if absf(angle) <= half_angle:
				angles.append(clampf(angle - CORNER_EPSILON, -half_angle, half_angle))
				angles.append(angle)
				angles.append(clampf(angle + CORNER_EPSILON, -half_angle, half_angle))
		angles.sort()
		var polygon := PackedVector2Array([origin])
		var previous_angle: float = -INF
		for angle: float in angles:
			if angle - previous_angle < 0.000001:
				continue
			previous_angle = angle
			var direction := Vector2.from_angle(facing + angle)
			polygon.append(origin + direction * _ray_distance(origin, direction, distance))
		_append_polygon(polygon)
		next_cache[observer_key] = polygon
		if not unit.get("_peek_observer", false): _unit_polygons[str(unit.get("id", ""))] = polygon
	_observer_cache = next_cache
	revision += 1
	return true

func _append_obstacle_geometry(obstacle: Dictionary) -> void:
	if nav.obstacle_opacity(obstacle) < 0.5: return
	var points: PackedVector2Array = nav.obstacle_corners(obstacle)
	var height_range := Vector2(float(obstacle.get("base_height", 0.0)), float(obstacle.get("base_height", 0.0)) + nav.obstacle_height(obstacle))
	_corners.append_array(points)
	for i: int in range(4):
		_corner_heights.append(height_range)
		_edges.append(points[i])
		_edges.append(points[(i + 1) % 4])
		_edge_heights.append(height_range)

func contains(point: Vector2) -> bool:
	# Room exploration samples many distant floor points on large maps.
	# Reject them against each observer's bounds before traversing the exact
	# sight polygon. Bounds have a tiny conservative margin for Geometry2D's
	# boundary tolerance; the final polygon test remains authoritative.
	for index: int in range(polygons.size()):
		if index < _polygon_bounds.size():
			var box: Rect2 = _polygon_bounds[index]
			if point.x < box.position.x or point.y < box.position.y or point.x > box.end.x or point.y > box.end.y: continue
		if Geometry2D.is_point_in_polygon(point, polygons[index]):
			return true
	return false

func _append_polygon(polygon: PackedVector2Array) -> void:
	polygons.append(polygon)
	if polygon.is_empty():
		_polygon_bounds.append(Rect2())
		return
	var low: Vector2 = polygon[0]
	var high: Vector2 = low
	for point: Vector2 in polygon:
		low.x = minf(low.x,point.x)
		low.y = minf(low.y,point.y)
		high.x = maxf(high.x,point.x)
		high.y = maxf(high.y,point.y)
	_polygon_bounds.append(Rect2(low,high-low).grow(0.0001))

func polygon_for(unit_id: String) -> PackedVector2Array:
	return _unit_polygons.get(unit_id, PackedVector2Array())

func polygon_bounds() -> Array[Rect2]:
	return _polygon_bounds

func _prepare_rays(origin: Vector2, maximum: float, eye_height: float = 1.62) -> void:
	_ray_offsets.clear()
	_ray_vectors.clear()
	_ray_crosses.clear()
	if _ray_buckets.is_empty():
		for i: int in range(RAY_BUCKET_COUNT): _ray_buckets.append([])
	else:
		for bucket: Array in _ray_buckets: bucket.clear()
	for i in range(0, _edges.size(), 2):
		var height_range: Vector2 = _edge_heights[i / 2]
		if eye_height < height_range.x or eye_height > height_range.y: continue
		var a := _edges[i]
		var b := _edges[i + 1]
		var edge := b - a
		# Conservative range box, including the endpoint tolerance used below.
		# Long segments crossing the range are retained even if both ends lie outside.
		var reach := maximum + edge.length() * 0.000001 + 0.00001
		if maxf(a.x, b.x) < origin.x - reach or minf(a.x, b.x) > origin.x + reach or maxf(a.y, b.y) < origin.y - reach or minf(a.y, b.y) > origin.y + reach:
			continue
		var offset := a - origin
		_ray_offsets.append(offset)
		_ray_vectors.append(edge)
		_ray_crosses.append(offset.cross(edge))
		_index_ray_edge(offset, edge, _ray_vectors.size() - 1)

func _index_ray_edge(offset: Vector2, edge: Vector2, index: int) -> void:
	var length_squared := edge.length_squared()
	if length_squared == 0.0: return
	# The exact intersection accepts an edge extended by 1e-6 at either end.
	# Near that segment every direction can hit at zero distance.
	var nearest := offset + edge * clampf(-offset.dot(edge) / length_squared, -0.000001, 1.000001)
	if nearest.length_squared() <= 0.000001:
		for bucket: Array in _ray_buckets: bucket.append(index)
		return
	var first_angle := (offset - edge * 0.000001).angle()
	var last_angle := (offset + edge * 1.000001).angle()
	var turn := wrapf(last_angle - first_angle, -PI, PI)
	var low := first_angle if turn >= 0.0 else first_angle + turn
	var high := first_angle + turn if turn >= 0.0 else first_angle
	# One neighbouring bin on either side absorbs atan2/bucket rounding.
	var first := floori(low * RAY_BUCKET_COUNT / TAU) - 1
	var last := floori(high * RAY_BUCKET_COUNT / TAU) + 1
	for i: int in range(first, last + 1):
		_ray_buckets[posmod(i, RAY_BUCKET_COUNT)].append(index)

func _ray_distance(_origin: Vector2, direction: Vector2, maximum: float) -> float:
	var nearest: float = maximum
	var bucket := mini(RAY_BUCKET_COUNT - 1, floori(wrapf(direction.angle(), 0.0, TAU) * RAY_BUCKET_COUNT / TAU))
	for i: int in _ray_buckets[bucket]:
		var divisor: float = direction.cross(_ray_vectors[i])
		if absf(divisor) < 0.0000001:
			continue
		var along: float = _ray_crosses[i] / divisor
		if along < 0.0 or along >= nearest: continue
		var across: float = _ray_offsets[i].cross(direction) / divisor
		if across >= -0.000001 and across <= 1.000001:
			nearest = along
	return nearest
