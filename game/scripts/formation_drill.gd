class_name BreachFormationDrill
extends RefCounted
## Pure formation drafts from the authored floor plan and owned approaches.
## No NPC, simulation clock, random stream or hidden live door is consulted.
const Navigation = preload("res://scripts/navigation.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const Door = preload("res://scripts/door_geometry.gd")
const KINDS: Array[String] = ["AUTO", "SERPENTINE", "ROLLING_T", "T_JUNCTION"]
const STATIC_KEYS: Array[String] = ["schema_version", "bounds", "walkable_areas", "rooms", "walls", "props", "doors"]
const SPACING := 0.7
const BODY_SPACING := Navigation.RADIUS * 2.0 + 0.02
const DEFAULT_BODY_RING := BODY_SPACING + 0.12
const TIGHT_BODY_RING := BODY_SPACING / cos(PI / 8.0) + 0.001
const EPSILON := 0.0001
const FACE_DISTANCE := 4.0
const MAX_BODY_GRAPH_POINTS := 96
const SECTOR_HALF := deg_to_rad(55.0)

static func calculate(static_geometry: Dictionary, order: Array, approaches: Dictionary, target: Array, options: Dictionary = {}) -> Dictionary:
	if order.size() < 2 or order.size() > 4: return _error("team")
	var ids: Array[String] = []
	var origins: Dictionary = {}
	for id: Variant in order:
		if not id is String or str(id).is_empty() or ids.has(str(id)): return _error("team")
		var origin := _point(approaches.get(id))
		if not _finite(origin): return _error("approach")
		ids.append(str(id))
		origins[str(id)] = origin
	for key: Variant in options:
		if key not in ["kind", "append", "signal", "delay_ticks"]: return _error("options")
	var requested := str(options.get("kind", "AUTO"))
	if not KINDS.has(requested): return _error("kind")
	if options.has("append") and not options.append is bool: return _error("options")
	var signal_name := str(options.get("signal", "AUTO"))
	var delay: Variant = options.get("delay_ticks", 0)
	if signal_name not in ["AUTO", "A", "B", "C"] or not _number(delay) or float(delay) != floorf(float(delay)) or float(delay) < 0.0 or float(delay) > 3600.0: return _error("options")
	if requested == "T_JUNCTION" and ids.size() != 4: return _error("team")
	var data: Dictionary = {}
	for key: String in STATIC_KEYS:
		if static_geometry.has(key): data[key] = static_geometry[key].duplicate(true) if static_geometry[key] is Array or static_geometry[key] is Dictionary else static_geometry[key]
	if not _geometry_valid(data): return _error("geometry")
	var destination := _point(target)
	if not _finite(destination): return _error("target")
	var nav := Navigation.new()
	nav.build(data, data.get("doors", []).duplicate(true))
	for id: String in ids:
		if not nav.walkable(origins[id]): return _error("approach")
	if not nav.walkable(destination): return _error("target")
	var lead: Vector2 = origins[ids[0]]
	if lead.distance_to(destination) < EPSILON: return _error("target")
	var central: Array = nav.path(lead, destination)
	if not _route_valid(nav, lead, central): return _error("route")
	var forward := (_point(central[0]) - lead).normalized()
	var final_forward := (_point(central[-1]) - (lead if central.size() == 1 else _point(central[-2]))).normalized()
	var width := _path_width(nav, data, lead, central)
	if not is_finite(width) or width <= Navigation.RADIUS * 2.0: return _error("clearance")
	# Authored scalars, before subtracting the actor radius, determine the
	# doctrine's 1.8 m threshold. The tiny tolerance is only double arithmetic.
	var recommended := "SERPENTINE" if width < 1.8 - 0.00000001 else "ROLLING_T"
	var kind := recommended if requested == "AUTO" else requested
	var stacks: Array[Vector2] = []
	var goals: Array[Vector2] = []
	var body_ring := DEFAULT_BODY_RING
	if kind == "T_JUNCTION":
		forward = final_forward
		var junction := _junction(nav, data, destination, forward)
		if junction.is_empty(): return _error("junction")
		width = float(junction.width)
		recommended = "SERPENTINE" if width < 1.8 - 0.00000001 else "ROLLING_T"
		stacks.assign(junction.stacks)
		goals.assign(junction.goals)
	else:
		var profile := _cross_section(nav, data, lead, forward)
		var across := forward.rotated(PI * 0.5)
		# Centre a nearby corridor without moving an open-ground draft halfway
		# across a large map. The subsequent swept paths remain authoritative.
		var shift := clampf((float(profile.right) - float(profile.left)) * 0.5, -SPACING, SPACING)
		var center := lead + across * shift
		stacks = _stacks(nav, data, center, forward, kind, ids, origins, destination, body_ring)
		if stacks.is_empty():
			# Preserve every previously successful draft. Only failed corridor
			# drafts retry an octagon whose chords still clear the same physical
			# body circle, but whose vertices fit a narrow passing lane.
			body_ring = TIGHT_BODY_RING
			stacks = _stacks(nav, data, center, forward, kind, ids, origins, destination, body_ring)
		if stacks.is_empty(): return _error("stack")
		var final_across := final_forward.rotated(PI * 0.5)
		for index: int in range(ids.size()):
			var offset := _offset(kind, index)
			goals.append(destination + final_across * offset.x - final_forward * offset.y)
	if not _points_valid(nav, stacks) or not _points_valid(nav, goals): return _error("clearance")
	var slots: Array = []
	for index: int in range(ids.size()):
		var id := ids[index]
		var origin: Vector2 = origins[id]
		var stack: Vector2 = stacks[index]
		var goal: Vector2 = goals[index]
		var stack_route := _stack_route(nav, data, origin, stack, ids, origins, stacks, index, body_ring)
		if not _route_valid(nav, origin, stack_route): return _error("stack")
		var move_route: Array = nav.path(stack, goal)
		if not _route_valid(nav, stack, move_route): return _error("route")
		var move_faces: Array = []
		var previous := stack
		for coordinate: Array in move_route:
			var point := _point(coordinate)
			var direction := (point - previous).normalized() if previous.distance_to(point) > EPSILON else final_forward
			var role_direction := _role_direction(kind, index, forward if kind == "T_JUNCTION" else direction)
			move_faces.append(_array(_face_target(data,previous,role_direction)))
			previous = point
		if 4 + stack_route.size() + move_route.size() * 2 > 32: return _error("capacity")
		var final_direction := (goal - stack).normalized() if kind == "T_JUNCTION" else final_forward
		if kind == "T_JUNCTION": final_direction = -forward.rotated(PI * 0.5) if index < 2 else forward.rotated(PI * 0.5)
		var initial_direction := _role_direction(kind, index, forward)
		var final_role := final_direction if kind == "T_JUNCTION" else _role_direction(kind, index, final_direction)
		var stance := ("crouched" if index in [0, 2] else "standing") if kind == "T_JUNCTION" else ""
		slots.append({"unit_id":id,"index":index + 1,"role":_role(kind,index),"approach":_array(origin),"stack":_array(stack),"stack_route":stack_route,"stack_waypoints":stack_route.slice(0,stack_route.size()-1),
			"move_route":move_route,"target":_array(goal),"stance":stance,
			"initial_face_target":_array(_face_target(data,origin,initial_direction)),
			"stack_face_target":_array(_face_target(data,stack,initial_direction)),
			"move_face_targets":move_faces,"face_target":_array(_face_target(data,goal,final_role)),
			"floor_height":Spatial.floor_base_at(data.get("rooms",[]),goal),
			"sector":_sector(goal,final_role),"stack_sector":_sector(stack,initial_direction)})
	var hand_ready := _hand_ready(nav, data, slots)
	return {"ok":true,"kind":kind,"recommended_kind":recommended,"corridor_width":width,"target":_array(destination),
		"order_ids":ids,"signal":signal_name,"delay_ticks":int(delay),"source_unit_id":ids[-1],"slots":slots,"hand_ready_compatible":hand_ready}

static func _geometry_valid(data: Dictionary) -> bool:
	var bounds := _point(data.get("bounds"))
	if not _finite(bounds) or bounds.x <= 0.0 or bounds.y <= 0.0: return false
	for key: String in ["rooms", "walls", "props", "doors", "walkable_areas"]:
		if data.has(key) and not data[key] is Array: return false
		for item: Variant in data.get(key, []):
			if not item is Dictionary: return false
			for coordinate: String in ["x", "z", "w", "d"]:
				if not _number(item.get(coordinate)): return false
			if float(item.w) <= 0.0 or float(item.d) <= 0.0: return false
			for coordinate: String in ["base_height", "rotation", "height", "progress", "hinge_side", "swing_sign"]:
				if item.has(coordinate) and not _number(item[coordinate]): return false
			if key == "doors" and item.get("axis", "x") not in ["x", "z"]: return false
	return true

static func _offset(kind: String, index: int) -> Vector2:
	if kind == "SERPENTINE": return Vector2(0.0, float(index) * SPACING)
	if index < 2: return Vector2((-0.5 if index == 0 else 0.5) * SPACING, 0.0)
	return Vector2(0.0, float(index - 1) * SPACING)

static func _stacks(nav: BreachNavigation, data: Dictionary, center: Vector2, forward: Vector2, kind: String, ids: Array[String], origins: Dictionary, destination: Vector2, body_ring: float = DEFAULT_BODY_RING) -> Array[Vector2]:
	var across := forward.rotated(PI * 0.5)
	var maximum_advance := (destination - center).dot(forward)
	var best: Array[Vector2] = []
	var best_cost := INF
	# A first valid anchor can still cage an operator between current bodies
	# and future stacks. Compare bounded forward approaches with unchanged
	# ranks and offsets; the requested target caps their common advance.
	# Retreat remains a fallback only when no forward anchor is reachable.
	for advance: float in [0.0, 0.35, 0.7, 1.05, 1.4, 1.75, 2.1, 2.45, 2.8, 3.15, -0.35, -0.7]:
		if advance < 0.0 and not best.is_empty(): return best
		if advance >= 0.0 and advance > maximum_advance + EPSILON: continue
		var result: Array[Vector2] = []
		for index: int in range(ids.size()):
			var offset := _offset(kind,index)
			result.append(center + forward * advance + across * offset.x - forward * offset.y)
		if not _points_valid(nav,result): continue
		var clear := true
		# A draft must not depend on another operator vacating a body-overlapped
		# stack. Advance the same common anchor, preserving ranks and offsets.
		for index: int in range(ids.size()):
			for other: int in range(ids.size()):
				if other != index and result[index].distance_to(origins[ids[other]]) < BODY_SPACING: clear = false
		if not clear: continue
		var cost := 0.0
		for index: int in range(ids.size()):
			var route := _stack_route(nav,data,origins[ids[index]],result[index],ids,origins,result,index,body_ring)
			if not _route_valid(nav,origins[ids[index]],route) or not _owned_route_clear(origins[ids[index]],route,ids,origins,result,index):
				clear = false
				break
			cost += _route_length(origins[ids[index]],route)
		if clear:
			if advance < 0.0: return result
			# Strict comparison keeps the existing candidate order on equal cost.
			if cost < best_cost:
				best = result
				best_cost = cost
	return best

static func _owned_route_clear(origin: Vector2, route: Array, ids: Array[String], origins: Dictionary, stacks: Array[Vector2], index: int) -> bool:
	var previous := origin
	for raw: Array in route:
		var point := _point(raw)
		for other: int in range(ids.size()):
			if other == index: continue
			for body: Vector2 in [origins[ids[other]],stacks[other]]:
				if Geometry2D.get_closest_point_to_segment(body,previous,point).distance_to(body) < BODY_SPACING: return false
		previous = point
	return true

static func _points_valid(nav: BreachNavigation, points: Array[Vector2]) -> bool:
	for index: int in range(points.size()):
		if not nav.walkable(points[index]): return false
		for other: int in range(index):
			if points[index].distance_to(points[other]) < SPACING - EPSILON: return false
	return true

static func _stack_route(nav: BreachNavigation, data: Dictionary, origin: Vector2, goal: Vector2, ids: Array[String], origins: Dictionary, stacks: Array[Vector2], index: int, body_ring: float = DEFAULT_BODY_RING) -> Array:
	var direct: Array = nav.path(origin,goal)
	if not _route_valid(nav,origin,direct): return []
	if _owned_route_clear(origin,direct,ids,origins,stacks,index): return direct
	var occupied: Array[Vector2] = []
	for other: int in range(ids.size()):
		if other == index: continue
		for body: Vector2 in [origins[ids[other]],stacks[other]]:
			if not occupied.has(body): occupied.append(body)
	var staged := data.duplicate(true)
	var props: Array = staged.get("props", []).duplicate(true)
	for body: Vector2 in occupied:
		props.append({"id":"_owned_formation_body","type":"box","x":body.x,"z":body.y,"w":(BODY_SPACING - Navigation.RADIUS) * 2.0,"d":(BODY_SPACING - Navigation.RADIUS) * 2.0,"cover":"full"})
	staged["props"] = props
	var body_nav := Navigation.new()
	body_nav.build(staged,staged.get("doors",[]).duplicate(true))
	var route: Array = body_nav.path(origin,goal)
	var square_valid := _route_valid(nav,origin,route) and _owned_route_clear(origin,route,ids,origins,stacks,index)
	# A rectangle expanded by the navigation radius overstates a body's
	# diagonal clearance. Evaluate the bounded circular candidate even when
	# the square raster found a valid route: a valid long retreat need not be
	# the least-resistance approach. Equal lengths retain the existing route.
	var circular := _body_route(nav,origin,goal,occupied,direct,route,body_ring)
	if not _route_valid(nav,origin,circular) or not _owned_route_clear(origin,circular,ids,origins,stacks,index): return route if square_valid else []
	return circular if not square_valid or _route_length(origin,circular) < _route_length(origin,route) else route

static func _route_length(origin: Vector2, route: Array) -> float:
	var length := 0.0
	var previous := origin
	for raw: Array in route:
		var point := _point(raw)
		length += previous.distance_to(point)
		previous = point
	return length

static func _body_segment_clear(origin: Vector2, goal: Vector2, bodies: Array[Vector2]) -> bool:
	for body: Vector2 in bodies:
		if Geometry2D.get_closest_point_to_segment(body,origin,goal).distance_to(body) < BODY_SPACING: return false
	return true

static func _body_route(nav: BreachNavigation, origin: Vector2, goal: Vector2, bodies: Array[Vector2], static_route: Array, square_route: Array, body_ring: float = DEFAULT_BODY_RING) -> Array:
	var points: Array[Vector2] = [origin,goal]
	for raw: Array in static_route + square_route:
		var point := _point(raw)
		if not points.has(point) and nav.walkable(point) and _body_segment_clear(point,point,bodies):
			if points.size() >= MAX_BODY_GRAPH_POINTS: return []
			points.append(point)
	for body: Vector2 in bodies:
		for direction_index: int in range(8):
			var point := body + Vector2.from_angle(float(direction_index)*PI*0.25) * body_ring
			if not points.has(point) and nav.walkable(point) and _body_segment_clear(point,point,bodies) and _floor_segment_clear(nav,origin,point):
				if points.size() >= MAX_BODY_GRAPH_POINTS: return []
				points.append(point)
	var distance: Array[float] = []
	var previous: Array[int] = []
	var visited: Array[bool] = []
	for _point_index: int in range(points.size()): distance.append(INF); previous.append(-1); visited.append(false)
	distance[0] = 0.0
	for _iteration: int in range(points.size()):
		var closest := -1
		for point_index: int in range(points.size()):
			if not visited[point_index] and (closest < 0 or distance[point_index] < distance[closest]): closest = point_index
		if closest < 0 or not is_finite(distance[closest]): return []
		if closest == 1: break
		visited[closest] = true
		for next: int in range(points.size()):
			if visited[next] or next == closest: continue
			var candidate := distance[closest] + points[closest].distance_to(points[next])
			if candidate >= distance[next]: continue
			if not _body_segment_clear(points[closest],points[next],bodies) or not _floor_segment_clear(nav,points[closest],points[next]) or not nav.segment_clear(points[closest],points[next],Navigation.RADIUS): continue
			distance[next] = candidate
			previous[next] = closest
	if previous[1] < 0: return []
	var indices: Array[int] = []
	var cursor := 1
	while cursor != 0:
		indices.push_front(cursor)
		cursor = previous[cursor]
		if cursor < 0: return []
	var result: Array = []
	for point_index: int in indices: result.append(_array(points[point_index]))
	return result

static func _junction(nav: BreachNavigation, data: Dictionary, center: Vector2, forward: Vector2) -> Dictionary:
	var across := forward.rotated(PI * 0.5)
	# A wide cross arm can contain the old fixed 1.4 m sample. Search the
	# contiguous incoming lane, bounded to a small local geometry window.
	# Its minimum parallel-wall separation is the physical stem width.
	var width := INF
	for distance: float in [1.4,2.1,2.8,3.5,4.2,4.9]:
		var sample := center - forward * distance
		if not nav.walkable(sample) or not nav.segment_clear(center,sample,Navigation.RADIUS): break
		width = minf(width,float(_cross_section(nav,data,sample,forward).width))
	if width < SPACING + Navigation.RADIUS * 2.0 or width > 8.0: return {}
	# A genuine T has two usable side arms and a closed forward arm. Merely
	# clicking open ground or the centre of an X intersection is insufficient.
	var probe := width * 0.5 + SPACING
	if nav.segment_clear(center,center + forward * probe,Navigation.RADIUS): return {}
	var stacks: Array[Vector2] = []
	var goals: Array[Vector2] = []
	for index: int in range(4):
		var sign_side := -1.0 if index < 2 else 1.0
		stacks.append(center + across * sign_side * SPACING * 0.5 - forward * (SPACING if index in [0,2] else SPACING * 2.0))
		goals.append(center + across * sign_side * (SPACING * 3.0 if index in [0,2] else SPACING * 2.0))
	if not _points_valid(nav,stacks) or not _points_valid(nav,goals): return {}
	for index: int in range(4):
		var branch := nav.path(center,goals[index])
		if not _route_valid(nav,center,branch): return {}
		# A distant loop into the opposite arm is not a T branch.
		var side := -1.0 if index < 2 else 1.0
		for raw: Array in branch:
			if (_point(raw) - center).dot(across) * side < -EPSILON or absf((_point(raw) - center).dot(forward)) > width * 0.5: return {}
	return {"width":width,"stacks":stacks,"goals":goals}

static func _path_width(nav: BreachNavigation, data: Dictionary, origin: Vector2, route: Array) -> float:
	var result := INF
	var previous := origin
	for raw: Array in route:
		var point := _point(raw)
		var distance := previous.distance_to(point)
		if distance <= EPSILON: continue
		var direction := (point - previous).normalized()
		var samples := maxi(1,ceili(distance / SPACING))
		for index: int in range(samples + 1):
			var sample := previous.lerp(point,float(index) / float(samples))
			result = minf(result,float(_cross_section(nav,data,sample,direction).width))
		previous = point
	return result

static func _cross_section(nav: BreachNavigation, data: Dictionary, center: Vector2, forward: Vector2) -> Dictionary:
	var across := forward.rotated(PI * 0.5)
	var left := _wall_ray(nav,data,center,-across)
	var right := _wall_ray(nav,data,center,across)
	var width := float(left.distance) + float(right.distance)
	# Parallel physical surfaces define their perpendicular separation, even
	# when the intended movement approaches them at a slight diagonal.
	if absf((left.normal as Vector2).dot(right.normal)) > 0.99999:
		width *= absf(across.dot(left.normal))
	return {"left":float(left.distance),"right":float(right.distance),"width":width}

static func _wall_ray(nav: BreachNavigation, data: Dictionary, origin: Vector2, direction: Vector2) -> Dictionary:
	var bounds := _point(data.bounds)
	var limit := bounds.length() + 1.0
	var result := _rect_ray(origin,direction,Vector2.ZERO,bounds,0.0,limit,true)
	var floor_height := Spatial.floor_base_at(data.get("rooms",[]),origin)
	for wall: Dictionary in data.get("walls",[]):
		var base := float(wall.get("base_height",0.0))
		if base > floor_height + 1.75 or base + float(wall.get("height",2.6)) < floor_height: continue
		var hit := _rect_ray(origin,direction,Vector2(float(wall.x),float(wall.z)),Vector2(float(wall.w),float(wall.d)),-float(wall.get("rotation",0.0)),limit,false,wall)
		if float(hit.distance) < float(result.distance): result = hit
	# Water/deck union boundaries are movement constraints rather than walls;
	# include their physical edge only when no closer authored surface exists.
	for forbidden: Rect2 in nav._walkable_voids:
		var hit := _rect_ray(origin,direction,forbidden.get_center(),forbidden.size,0.0,limit,false)
		if float(hit.distance) < float(result.distance): result = hit
	return result

static func _rect_ray(origin: Vector2, direction: Vector2, center: Vector2, size: Vector2, angle: float, limit: float, inside: bool, authored: Dictionary = {}) -> Dictionary:
	var c := cos(angle)
	var s := sin(angle)
	var x := float(authored.get("x",center.x))
	var z := float(authored.get("z",center.y))
	var w := float(authored.get("w",size.x))
	var d := float(authored.get("d",size.y))
	var ox := (float(origin.x) - x) * c + (float(origin.y) - z) * s
	var oz := -(float(origin.x) - x) * s + (float(origin.y) - z) * c
	var dx := float(direction.x) * c + float(direction.y) * s
	var dz := -float(direction.x) * s + float(direction.y) * c
	var near := 0.0
	var far := limit
	var near_normal := Vector2.ZERO
	var far_normal := Vector2.ZERO
	for axis: int in range(2):
		var value := ox if axis == 0 else oz
		var ray := dx if axis == 0 else dz
		var low := (0.0 if inside else -w * 0.5) if axis == 0 else (0.0 if inside else -d * 0.5)
		var high := w if axis == 0 else d
		if not inside: high *= 0.5
		if absf(ray) < 0.000000001:
			if value < low or value > high: return {"distance":limit,"normal":Vector2.ZERO}
			continue
		var a := (low - value) / ray
		var b := (high - value) / ray
		var entry := minf(a,b)
		var exit := maxf(a,b)
		var normal := (Vector2.RIGHT if axis == 0 else Vector2.DOWN).rotated(angle) * (-1.0 if ray > 0.0 else 1.0)
		if entry > near: near = entry; near_normal = normal
		if exit < far: far = exit; far_normal = -normal
		if near > far: return {"distance":limit,"normal":Vector2.ZERO}
	return {"distance":far if inside else near,"normal":far_normal if inside else near_normal}

static func _face_target(data: Dictionary, origin: Vector2, direction: Vector2) -> Vector2:
	# FACE validates its endpoint against map bounds even though the ray can
	# face through a wall. Shortening this ray preserves the intended heading
	# and keeps preview coordinates identical to the expanded primitive.
	var bounds := _point(data.bounds)
	var length := FACE_DISTANCE
	for axis: int in range(2):
		var component := direction.x if axis == 0 else direction.y
		var value := origin.x if axis == 0 else origin.y
		var limit := bounds.x if axis == 0 else bounds.y
		if component > 0.0: length = minf(length,(limit - value) / component)
		elif component < 0.0: length = minf(length,-value / component)
	# One millimetre inside prevents float32 endpoint rounding from crossing
	# the authored boundary without changing any movement or goal tolerance.
	return origin + direction * maxf(length - 0.001,0.001)

static func _role_direction(kind: String, index: int, forward: Vector2) -> Vector2:
	var across := forward.rotated(PI * 0.5)
	if kind == "T_JUNCTION": return -across if index < 2 else across
	if kind == "SERPENTINE":
		if index == 0: return forward
		if index < 3: return (forward * 0.5 + across * (-1.0 if index == 1 else 1.0)).normalized()
	else:
		if index < 2: return (forward * 0.5 + across * (1.0 if index == 0 else -1.0)).normalized()
		if index == 2: return forward
	return -forward

static func _role(kind: String, index: int) -> String:
	if kind == "T_JUNCTION": return "left" if index < 2 else "right"
	return (["front","left","right","rear"] if kind == "SERPENTINE" else ["right","left","front","rear"])[index]

static func _hand_ready(nav: BreachNavigation, data: Dictionary, slots: Array) -> bool:
	var source: Dictionary = slots[-1]
	var source_point := _point(source.stack)
	var angles: Array[float] = []
	for index: int in range(slots.size() - 1): angles.append(fposmod((_point(slots[index].stack) - source_point).angle(),TAU))
	angles.sort()
	var gap := -1.0
	var start := 0.0
	for index: int in range(angles.size()):
		var next := angles[(index + 1) % angles.size()] + (TAU if index == angles.size() - 1 else 0.0)
		if next - angles[index] > gap:
			gap = next - angles[index]
			start = next
	var span := TAU - gap
	var heading := start + span * 0.5
	source["ready_face_target"] = _array(_face_target(data,source_point,Vector2.from_angle(heading)))
	var compatible := span <= SECTOR_HALF * 2.0 + EPSILON
	var source_height := Spatial.floor_base_at(data.get("rooms",[]),source_point)
	var source_eye := source_height + (1.02 if source.stance == "crouched" else 1.62)
	for index: int in range(slots.size() - 1):
		var receiver: Dictionary = slots[index]
		var point := _point(receiver.stack)
		receiver["ready_face_target"] = _array(source_point)
		var height := Spatial.floor_base_at(data.get("rooms",[]),point)
		var eye := height + (1.02 if receiver.stance == "crouched" else 1.62)
		if absf(height - source_height) > EPSILON or point.distance_to(source_point) > 6.0 or not nav.sight_clear_height(source_point,point,source_eye,eye): compatible = false
	return compatible

static func _route_valid(nav: BreachNavigation, origin: Vector2, route: Array) -> bool:
	if route.is_empty(): return false
	var previous := origin
	for raw: Variant in route:
		var point := _point(raw)
		if not _finite(point) or not nav.walkable(point) or not _floor_segment_clear(nav,previous,point) or not nav.segment_clear(previous,point,Navigation.RADIUS): return false
		previous = point
	return true

static func _floor_segment_clear(nav: BreachNavigation, origin: Vector2, goal: Vector2) -> bool:
	# Navigation is horizontal. A formation cannot use a different authored
	# floor as a shortcut: test every constant-height interval of this edge.
	if not nav.has_meta("formation_floor_rooms"):
		var elevated: Array = []
		for room: Dictionary in nav._lighting_rooms:
			if float(room.get("base_height",0.0)) > 0.0: elevated.append(room)
		nav.set_meta("formation_floor_rooms",elevated)
	var rooms: Array = nav.get_meta("formation_floor_rooms")
	if rooms.is_empty(): return true
	var height := Spatial.floor_base_at(rooms,origin)
	if absf(height-Spatial.floor_base_at(rooms,goal)) > EPSILON: return false
	var fractions: Array[float] = [0.0,1.0]
	var direction := goal-origin
	for room: Dictionary in rooms:
		var near := 0.0
		var far := 1.0
		for axis: int in range(2):
			var center := float(room.x if axis==0 else room.z)
			var size := float(room.w if axis==0 else room.d)
			var value := float(origin.x if axis==0 else origin.y)
			var delta := float(direction.x if axis==0 else direction.y)
			if absf(delta)<0.000000001:
				if value<center-size*0.5 or value>center+size*0.5: far=-1.0; break
			else:
				var a := (center-size*0.5-value)/delta
				var b := (center+size*0.5-value)/delta
				near=maxf(near,minf(a,b));far=minf(far,maxf(a,b))
		if near<=far: fractions.append(near);fractions.append(far)
	fractions.sort()
	for index: int in range(fractions.size()-1):
		if fractions[index+1]<=fractions[index]: continue
		var sample := origin.lerp(goal,(fractions[index]+fractions[index+1])*0.5)
		if absf(height-Spatial.floor_base_at(rooms,sample))>EPSILON: return false
	return true

static func _sector(origin: Vector2, direction: Vector2) -> Dictionary:
	var heading := direction.angle()
	return {"origin":_array(origin),"start":wrapf(heading - SECTOR_HALF,-PI,PI),"end":wrapf(heading + SECTOR_HALF,-PI,PI),"center":heading,"radius":FACE_DISTANCE,"duration":12.0}

static func _point(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]): return Vector2(float(value[0]),float(value[1]))
	return Vector2(INF,INF)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _finite(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y)

static func _array(point: Vector2) -> Array:
	return [point.x,point.y]

static func _error(reason: String) -> Dictionary:
	return {"ok":false,"reason_code":"formation_" + reason,"message_key":"formation.error." + reason,"slots":[]}
