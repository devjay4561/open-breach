extends RefCounted
## Gameplay sound propagation. Costs are tuning units, not measured decibels.
## A room/portal graph provides an indirect route; closed doors add loss.
var _rooms: Array = []
var _links: Array = []
var _doors: Array = []
var _nav: RefCounted
var _source_cache: Dictionary = {}
var _room_floors: Array = []
var _floor_links: Array = []
var _walls: Array = []
var _room_definitions: Array = []
var _static_pose: Array = []
var _checked_nav_revision := -1
const FLOOR_EPSILON := 0.01
const WALL_CONTACT_DISTANCE := 0.3

func build(data: Dictionary, live_doors: Array, navigation: RefCounted) -> void:
	_rooms.clear()
	_links.clear()
	_source_cache.clear()
	_room_floors.clear()
	_floor_links.clear()
	_doors = live_doors
	_nav = navigation
	_room_definitions = data.get("rooms", []).duplicate(true)
	# Navigation marks props with cover; authored walls have no cover key.
	# Read the live walls so removed/replaced geometry cannot retain contact.
	_walls = _nav.walls.filter(func(obstacle: Dictionary) -> bool: return not obstacle.has("cover")).duplicate(true)
	_static_pose = _static_geometry_pose()
	_checked_nav_revision = int(_nav.revision)
	for room: Dictionary in data.get("rooms", []):
		_rooms.append(Rect2(Vector2(float(room.x), float(room.z)) - Vector2(float(room.w), float(room.d)) * 0.5, Vector2(float(room.w), float(room.d))))
		_room_floors.append(float(room.get("base_height", 0.0)))
	# The final node is the exterior/unlabelled connecting space.
	for door: Dictionary in _doors:
		var point := Vector2(float(door.x), float(door.z))
		var normal := Vector2(0, 1) if door.get("axis", "x") == "x" else Vector2(1, 0)
		var a: int = room_at(point - normal * 0.5)
		var b: int = room_at(point + normal * 0.5)
		if a != b:
			_links.append({"a": a, "b": b, "point": point, "door": door})
		var floor_height := float(door.get("base_height", 0.0))
		var floor_a := room_at(point - normal * 0.5, floor_height)
		var floor_b := room_at(point + normal * 0.5, floor_height)
		if floor_a != floor_b: _floor_links.append({"a":floor_a,"b":floor_b,"point":point,"door":door,"floor_height":floor_height})
	# Touching room labels are not assumed connected: test the physical opening.
	var all_door_ids: Array = []
	for door: Dictionary in _doors: all_door_ids.append(str(door.id))
	for a: int in range(_rooms.size()):
		for b: int in range(a + 1, _rooms.size()):
			var ra: Rect2 = _rooms[a]
			var rb: Rect2 = _rooms[b]
			var overlap: Rect2 = ra.grow(0.02).intersection(rb.grow(0.02))
			if not overlap.has_area(): continue
			for index: int in range(1, 8):
				var f: float = float(index) / 8.0
				var portal: Vector2 = overlap.position + overlap.size * (Vector2(0.5, f) if overlap.size.y > overlap.size.x else Vector2(f, 0.5))
				var direction: Vector2 = (rb.get_center() - ra.get_center()).normalized()
				var door_near: bool = false
				for door: Dictionary in _doors:
					if portal.distance_to(Vector2(float(door.x), float(door.z))) < maxf(float(door.get("w", 0.0)), float(door.get("d", 0.0))) * 0.5 + 0.35:
						door_near = true
						break
				if not door_near and _nav.segment_clear(portal - direction * 0.35, portal + direction * 0.35, 0.0, all_door_ids):
					_links.append({"a": a, "b": b, "point": portal, "door": {}})
					break
	# Explicit-context sounds use a separate same-floor graph. The legacy graph
	# above remains unchanged for old two/three-argument sound callers.
	for a: int in range(_rooms.size()):
		for b: int in range(a + 1, _rooms.size()):
			if absf(float(_room_floors[a]) - float(_room_floors[b])) > FLOOR_EPSILON: continue
			var ra: Rect2 = _rooms[a]
			var rb: Rect2 = _rooms[b]
			var overlap := ra.grow(0.02).intersection(rb.grow(0.02))
			if not overlap.has_area(): continue
			var floor_height := float(_room_floors[a])
			for index: int in range(1, 8):
				var f := float(index) / 8.0
				var portal := overlap.position + overlap.size * (Vector2(0.5, f) if overlap.size.y > overlap.size.x else Vector2(f, 0.5))
				var direction := (rb.get_center() - ra.get_center()).normalized()
				var door_near := false
				for door: Dictionary in _doors:
					if absf(float(door.get("base_height",0.0)) - floor_height) > FLOOR_EPSILON: continue
					if portal.distance_to(Vector2(float(door.x),float(door.z))) < maxf(float(door.get("w",0.0)),float(door.get("d",0.0))) * 0.5 + 0.35:
						door_near = true
						break
				if not door_near and _floor_segment_clear(portal-direction*0.35,portal+direction*0.35,floor_height,all_door_ids):
					_floor_links.append({"a":a,"b":b,"point":portal,"door":{},"floor_height":floor_height})
					break

func _static_geometry_pose() -> Array:
	var pose: Array = []
	for obstacle: Dictionary in _nav.walls:
		var item: Array = []
		for key: String in ["x","z","w","d","rotation","height","base_height","cover"]: item.append(obstacle.get(key))
		pose.append(item)
	return pose

func _ensure_live_graph() -> void:
	if int(_nav.revision)==_checked_nav_revision: return
	_checked_nav_revision = int(_nav.revision)
	# Door poses use the exact source key below. Only changed static geometry
	# requires rebuilding the actual touching-room openings (the cold rule).
	if _static_geometry_pose()!=_static_pose:
		build({"rooms":_room_definitions},_doors,_nav)

func room_at(point: Vector2, floor_height: Variant = null) -> int:
	for index: int in range(_rooms.size()):
		if floor_height != null and absf(float(_room_floors[index]) - float(floor_height)) > FLOOR_EPSILON: continue
		if (_rooms[index] as Rect2).has_point(point): return index
	return _rooms.size()

func _on_floor(obstacle: Dictionary, floor_height: float) -> bool:
	var base := float(obstacle.get("base_height", 0.0))
	return floor_height >= base-FLOOR_EPSILON and floor_height <= base+float(obstacle.get("height",2.6))+FLOOR_EPSILON

func _floor_segment_clear(a: Vector2, b: Vector2, floor_height: float, assumed_open: Array = []) -> bool:
	# Match legacy low-cover handling, then restrict actual geometry to the
	# supplied floor. Optical transparency never removes a physical sound wall.
	for obstacle: Dictionary in _nav._static_candidates(a,b,0.0):
		if obstacle.get("cover","full") == "low" or not _on_floor(obstacle,floor_height): continue
		if _nav._segment_obstacle(a,b,obstacle,0.0): return false
	for obstacle: Dictionary in _nav._door_blockers(assumed_open,false):
		if _on_floor(obstacle,floor_height) and _nav._segment_obstacle(a,b,obstacle,0.0): return false
	return true

func wall_contact(source: Vector2, floor_height: float = 0.0) -> Dictionary:
	_ensure_live_graph()
	var nearest := INF
	var answer: Dictionary = {}
	for index: int in range(_walls.size()):
		var wall: Dictionary = _walls[index]
		if not _on_floor(wall,floor_height): continue
		var center := Vector2(float(wall.x),float(wall.z))
		var size := Vector2(float(wall.w),float(wall.d))
		var rect := Rect2(center-size*0.5,size)
		var surface := source.clamp(rect.position,rect.end)
		var distance := source.distance_to(surface)
		var inside := source.x>rect.position.x and source.x<rect.end.x and source.y>rect.position.y and source.y<rect.end.y
		if distance > WALL_CONTACT_DISTANCE or distance >= nearest or inside: continue
		var opposite := surface
		if size.x <= size.y:
			opposite.x = center.x + (size.x*0.5+0.005) * (-1.0 if source.x<center.x else 1.0) * -1.0
		else:
			opposite.y = center.y + (size.y*0.5+0.005) * (-1.0 if source.y<center.y else 1.0) * -1.0
		nearest = distance
		answer = {"wall_index":index,"floor_height":floor_height,"source":source,"opposite":opposite}
	return answer

func _door_loss(door: Dictionary) -> float:
	if door.is_empty(): return 0.0
	if bool(door.get("destroyed", false)) or str(door.get("state", "CLOSED")) in ["BROKEN", "DESTROYED"]: return 0.0
	return lerpf(6.0, 0.5, clampf(float(door.get("progress", 0.0)), 0.0, 1.0))

func travel_cost(source: Vector2, listener: Vector2, context: Dictionary = {}) -> float:
	_ensure_live_graph()
	var explicit_floor := context.has("source_floor") and context.has("listener_floor")
	var floor_height := float(context.get("source_floor",0.0))
	if explicit_floor and absf(floor_height-float(context.listener_floor)) > FLOOR_EPSILON: return INF
	var best := _travel_cost(source,listener,floor_height if explicit_floor else null)
	var contact: Dictionary = context.get("wall_contact",{})
	if explicit_floor and not contact.is_empty():
		# Recompute the authoritative contact instead of trusting a stale caller
		# pose. The alternative face is a source only in the opposite known room.
		var current := wall_contact(source,floor_height)
		if not current.is_empty() and int(current.wall_index)==int(contact.get("wall_index",-1)):
			var opposite: Vector2 = current.opposite
			var other := room_at(opposite,floor_height)
			if other < _rooms.size() and other != room_at(source,floor_height):
				best = minf(best,source.distance_to(opposite)+_travel_cost(opposite,listener,floor_height))
	# Keep the original Euclidean prefilter exact for both propagation routes.
	return maxf(source.distance_to(listener),best)

func _travel_cost(source: Vector2, listener: Vector2, floor_height: Variant) -> float:
	var direct: float = source.distance_to(listener)
	if _nav.segment_clear(source,listener) if floor_height==null else _floor_segment_clear(source,listener,float(floor_height)): return direct
	# Transmission through a separating wall remains possible for loud events.
	var best: float = direct + 10.0
	if _rooms.is_empty(): return direct + 5.5
	var source_room: int = room_at(source,floor_height)
	var listener_room: int = room_at(listener,floor_height)
	if source_room == listener_room: return direct + 4.0
	var pose: Array = []
	# _door_loss uses the real progress. A 0.02-rounded key used to retain a
	# stale cost at e.g. 0.100 -> 0.101; warm and cold queries must agree exactly.
	for door: Dictionary in _doors: pose.append([str(door.get("id","")),str(door.get("state","CLOSED")),float(door.get("progress",0.0)),bool(door.get("destroyed",false)),float(door.get("base_height",0.0))])
	var key: Array = [source,floor_height,int(_nav.revision),pose]
	if _source_cache.get("key", []) != key:
		var costs: Array = []
		var points: Array = []
		var visited: Array = []
		for i: int in range(_rooms.size() + 1):
			costs.append(INF)
			points.append(source)
			visited.append(false)
		costs[source_room] = 0.0
		for iteration: int in range(costs.size()):
			var current: int = -1
			for i: int in range(costs.size()):
				if not visited[i] and (current < 0 or float(costs[i]) < float(costs[current])): current = i
			if current < 0 or is_inf(float(costs[current])): break
			visited[current] = true
			for edge: Dictionary in _links if floor_height==null else _floor_links:
				if floor_height!=null and absf(float(edge.floor_height)-float(floor_height))>FLOOR_EPSILON: continue
				var next: int = int(edge.b) if int(edge.a) == current else (int(edge.a) if int(edge.b) == current else -1)
				if next < 0: continue
				var value: float = float(costs[current]) + (points[current] as Vector2).distance_to(edge.point) + _door_loss(edge.door)
				if value < float(costs[next]):
					costs[next] = value
					points[next] = edge.point
		_source_cache = {"key": key, "costs": costs, "points": points}
	var graph_cost: float = float(_source_cache.costs[listener_room])
	if not is_inf(graph_cost): best = minf(best, graph_cost + (_source_cache.points[listener_room] as Vector2).distance_to(listener))
	return best

func audibility(source: Vector2, listener: Vector2, strength: float, context: Dictionary = {}) -> float:
	if strength <= 0.0: return 0.0
	# Every portal route is at least its Euclidean length and every loss is
	# nonnegative. Distant listeners cannot hear this event, so avoid tracing
	# walls and building graph keys for them. Keep boundary cases on the exact
	# path to cover float rounding in sums of short portal segments.
	var margin: float = maxf(0.0001, absf(strength) * 0.000001)
	if source.distance_to(listener) > strength + margin: return 0.0
	return clampf(1.0 - travel_cost(source, listener,context) / strength, 0.0, 1.0)
