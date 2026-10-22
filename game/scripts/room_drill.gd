class_name BreachRoomDrill
extends RefCounted
## Pure planning geometry. Callers supply authored static geometry and their
## own projected positions; no simulation, contacts or clock are consulted.
const Navigation = preload("res://scripts/navigation.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const METHODS: Array[String] = ["OPEN_DOOR", "KICK_DOOR", "OPEN_AND_FLASH", "BREACH_DOOR", "SHOTGUN_BREACH"]
const STATIC_KEYS: Array[String] = ["schema_version", "bounds", "walkable_areas", "rooms", "walls", "props", "doors"]
const SPACING := 0.7
const MARGIN := 0.9
const FAR_MARGIN := 1.0
# Vector2 stores float32 coordinates. At 512 m its ULP is about 0.00003 m;
# this tolerance preserves 0.7 m spacing under world translations.
const EPSILON := 0.0001

# Per-calculation navigation only. A permissive eight-neighbour flood can
# prove disconnected endpoints without asking A* to explore the same closed
# compartment for every retreat candidate. It never supplies a route: every
# connected query still uses the original Nav.path and its physical checks.
class PlanningNavigation extends BreachNavigation:
	const NEIGHBOURS: Array[Vector2i] = [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1)]
	var _component_labels := PackedInt32Array()
	var _component_grid_id := 0
	var _component_revision := -1
	var _next_component := 1
	var _path_memo: Dictionary = {}
	var _memo_pose_revision := -1
	const PATH_MEMO_LIMIT := 512
	const COMPONENT_FLOOD_LIMIT := 4096

	# Compile detached exact door obstacles only within an owned immutable
	# geometry scope. Raw door dictionaries and the original Nav stay intact.
	var _compiled_door_blockers: Dictionary = {}

	func begin_geometry_scope() -> void:
		_clear_physical_query_memos()
		_compiled_door_blockers.clear()
		super.begin_geometry_scope()

	func invalidate_sensory_pose() -> void:
		_clear_physical_query_memos()
		_compiled_door_blockers.clear()
		super.invalidate_sensory_pose()

	func _door_blockers(assumed_open: Array, movement: bool) -> Array:
		var raw: Array=super._door_blockers(assumed_open,movement)
		if not _geometry_scope: return raw
		var key: Array=[_exact_door_revision,assumed_open.duplicate(),movement]
		if _compiled_door_blockers.has(key): return _compiled_door_blockers[key]
		var detached: Array=raw.duplicate(true)
		for obstacle: Dictionary in detached: _compile_obstacle(obstacle)
		if _compiled_door_blockers.size()>=64: _compiled_door_blockers.clear()
		_compiled_door_blockers[key]=detached
		return detached

	# Exact physical predicates are pure within these owned immutable scopes.
	# Keep ordered points, original padding precision and a detached open list.
	const PHYSICAL_QUERY_MEMO_LIMIT := 4096
	var _walkable_memo: Dictionary = {}
	var _segment_memo: Dictionary = {}
	var _physical_query_epoch: Array = []

	func _clear_physical_query_memos() -> void:
		_walkable_memo.clear()
		_segment_memo.clear()
		_physical_query_epoch.clear()

	func end_geometry_scope() -> void:
		_clear_physical_query_memos()
		super.end_geometry_scope()

	func _physical_queries_ready() -> bool:
		if not _geometry_scope: return false
		_door_pose_key()
		var epoch: Array=[revision,_exact_door_revision,_grid_dirty,grid.get_instance_id() if grid!=null else 0]
		if _physical_query_epoch!=epoch:
			_walkable_memo.clear()
			_segment_memo.clear()
			_physical_query_epoch=epoch
		return true

	func _physical_query_capacity() -> void:
		if _walkable_memo.size()+_segment_memo.size()>=PHYSICAL_QUERY_MEMO_LIMIT:
			_walkable_memo.clear()
			_segment_memo.clear()

	func walkable(point: Vector2, assumed_open: Array = []) -> bool:
		if not is_finite(point.x) or not is_finite(point.y): return super.walkable(point,assumed_open)
		if not _physical_queries_ready(): return super.walkable(point,assumed_open)
		var key: Array=[point,assumed_open.duplicate(true)]
		if _walkable_memo.has(key): return bool(_walkable_memo[key])
		var result: bool=super.walkable(point,assumed_open)
		_physical_query_capacity()
		_walkable_memo[key]=result
		return result

	func segment_clear(a: Vector2, b: Vector2, padding: float = 0.0, assumed_open: Array = []) -> bool:
		if not is_finite(a.x) or not is_finite(a.y) or not is_finite(b.x) or not is_finite(b.y) or not is_finite(padding): return super.segment_clear(a,b,padding,assumed_open)
		if not _physical_queries_ready(): return super.segment_clear(a,b,padding,assumed_open)
		var key: Array=[Vector4(a.x,a.y,b.x,b.y),padding,assumed_open.duplicate(true)]
		if _segment_memo.has(key): return bool(_segment_memo[key])
		var result: bool=super.segment_clear(a,b,padding,assumed_open)
		_physical_query_capacity()
		_segment_memo[key]=result
		return result

	func path(start: Vector2, target: Vector2, assumed_open: Array = []) -> Array:
		if not assumed_open.is_empty(): return super.path(start,target,assumed_open)
		if not walkable(start) or not walkable(target): return []
		# Keep the original full-body direct segment shortcut before any grid
		# reasoning; its endpoints need not be connected in a centre grid.
		if segment_clear(start,target,RADIUS): return super.path(start,target)
		var changed := _grid_dirty
		if grid == null:
			grid = _make_grid([])
			_main_door_cells = _door_grid_cells([])
			_grid_dirty = false
		elif _grid_dirty:
			_sync_grid_doors()
			_grid_dirty = false
		if changed or _component_grid_id != grid.get_instance_id() or _component_revision != revision:
			_component_labels.resize(_grid_region.size.x*_grid_region.size.y)
			_component_labels.fill(0)
			_component_grid_id=grid.get_instance_id()
			_component_revision=revision
			_next_component=1
			_path_memo.clear()
		_door_pose_key()
		if _memo_pose_revision != _exact_door_revision:
			_path_memo.clear()
			_memo_pose_revision=_exact_door_revision
		# Exact ordered endpoints in this immutable grid epoch repeat during
		# entry costing and final slot routes. Copy both stored and returned
		# arrays, and restore the original Nav.path retry side effect.
		var key := Vector4(start.x,start.y,target.x,target.y)
		if _path_memo.has(key):
			var remembered: Dictionary = _path_memo[key]
			_needs_edge_retry=bool(remembered.edge_retry)
			return remembered.route.duplicate(true)
		var first := _nearest_cell(start,grid,[])
		var last := _nearest_cell(target,grid,[])
		if first.x<0 or last.x<0: return []
		if not _possibly_connected(first,last): return []
		var result: Array = super.path(start,target)
		if _path_memo.size() >= PATH_MEMO_LIMIT: _path_memo.clear()
		_path_memo[key]={"route":result.duplicate(true),"edge_retry":_needs_edge_retry}
		return result

	func _possibly_connected(first: Vector2i, last: Vector2i) -> bool:
		var region := _grid_region
		var width := region.size.x
		var from_index := (first.y-region.position.y)*width+first.x-region.position.x
		var to_index := (last.y-region.position.y)*width+last.x-region.position.x
		if from_index==to_index: return true
		var from_label := _component_labels[from_index]
		var to_label := _component_labels[to_index]
		if from_label>0 or to_label>0: return from_label>0 and from_label==to_label
		var seen := PackedByteArray()
		seen.resize(_component_labels.size())
		seen[to_index]=1
		var pending := PackedInt32Array([to_index])
		var cursor := 0
		# Flood from the candidate: a sealed target room is usually much
		# smaller than the outdoor source component of a 512m map. A found
		# connection ends the proof immediately; partial labels are discarded.
		while cursor<pending.size():
			# A connected, distant query can make this optional proof more
			# expensive than A*. Abandon only the optimization at this bound;
			# unknown still runs the complete original Nav.path below, and no
			# partial component is labelled as disconnected.
			if pending.size()>=COMPONENT_FLOOD_LIMIT: return true
			var index := pending[cursor]
			cursor+=1
			var point := Vector2i(index%width,floori(float(index)/float(width)))+region.position
			for offset: Vector2i in NEIGHBOURS:
				var next := point+offset
				if not region.has_point(next) or grid.is_point_solid(next): continue
				var next_index := (next.y-region.position.y)*width+next.x-region.position.x
				if next_index==from_index: return true
				if seen[next_index]!=0: continue
				seen[next_index]=1
				pending.append(next_index)
		# This complete permissive component cannot reach the source. Cache
		# only complete components, with no shared path arrays or global state.
		for index: int in pending: _component_labels[index]=_next_component
		_next_component+=1
		return false

static func calculate(static_geometry: Dictionary, door_id: String, order_ids: Array, approach_by_id: Dictionary, options: Dictionary = {}) -> Dictionary:
	var answer := _calculate(static_geometry,door_id,order_ids,approach_by_id,options,false)
	if not bool(answer.get("ok",false)) and str(answer.get("reason_code","")) == "drill_domination":
		return _calculate(static_geometry,door_id,order_ids,approach_by_id,options,true)
	return answer

static func _calculate_with_baseline(static_geometry: Dictionary, door_id: String, order_ids: Array, approach_by_id: Dictionary, options: Dictionary, shared_baseline: BreachNavigation, private_navigation: Variant = null) -> Dictionary:
	# Offline callers own an immutable authored movement baseline for one map.
	# Runtime calculate() retains its original fresh navigation/default API.
	var answer := _calculate(static_geometry,door_id,order_ids,approach_by_id,options,false,shared_baseline,private_navigation)
	if not bool(answer.get("ok",false)) and str(answer.get("reason_code","")) == "drill_domination":
		return _calculate(static_geometry,door_id,order_ids,approach_by_id,options,true,shared_baseline,private_navigation)
	return answer

static func _calculate(static_geometry: Dictionary, door_id: String, order_ids: Array, approach_by_id: Dictionary, options: Dictionary, use_compartment: bool, shared_baseline: BreachNavigation = null, private_navigation: Variant = null) -> Dictionary:
	var method := str(options.get("method", "OPEN_DOOR"))
	if not METHODS.has(method): return _error("method", door_id)
	if order_ids.size() < 2 or order_ids.size() > 4: return _error("team", door_id)
	var ids: Array[String] = []
	for value: Variant in order_ids:
		if not value is String or str(value).is_empty() or ids.has(str(value)): return _error("team", door_id)
		ids.append(str(value))
	var data: Dictionary = {}
	for key: String in STATIC_KEYS:
		if static_geometry.has(key): data[key] = static_geometry[key].duplicate(true) if static_geometry[key] is Array or static_geometry[key] is Dictionary else static_geometry[key]
	if not data.get("bounds", []) is Array or data.get("bounds", []).size() != 2: return _error("geometry", door_id)
	var bounds := _point(data.bounds)
	if not _finite(bounds) or bounds.x <= 0.0 or bounds.y <= 0.0: return _error("geometry", door_id)
	for key: String in ["doors", "rooms", "walls", "props", "walkable_areas"]:
		if data.has(key) and not data[key] is Array: return _error("geometry", door_id)
	if not _geometry_valid(data): return _error("geometry", door_id)
	var door: Dictionary = {}
	for source: Dictionary in data.get("doors", []):
		if str(source.get("id", "")) == door_id:
			door = source.duplicate(true)
			break
	if door.is_empty(): return _error("door", door_id)
	var center := _entity_point(door)
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var across := Vector2.RIGHT if door.get("axis", "x") == "x" else Vector2.DOWN
	var origins: Dictionary = {}
	for id: String in ids:
		var origin := _point(approach_by_id.get(id, []))
		if not _finite(origin) or origin.x < 0.0 or origin.y < 0.0 or origin.x > bounds.x or origin.y > bounds.y: return _error("approach", door_id)
		origins[id] = origin
	var lead: Vector2 = origins[ids[0]]
	var side := 1.0 if (lead - center).dot(normal) >= 0.0 else -1.0
	if absf((lead - center).dot(normal)) < EPSILON: return _error("approach", door_id)
	var inward := -normal * side
	var room := _choose_room(data.get("rooms", []), door, center + inward * 0.65, str(options.get("room_id", "")))
	if room.is_empty(): return _error("room", door_id)
	var rect := _room_rect(room)
	var authored_rect := rect
	var frame := _portal_frame(data,door,rect,center,inward,across)
	if not frame.is_empty():
		var authored_short := rect.get_area() <= 9.0+EPSILON or minf(rect.size.x,rect.size.y) <= 2.5+EPSILON
		var original_far_min := maxf(1.8,minf(rect.size.x,rect.size.y)*0.45)
		# A full-width wall/other-portal barrier before the old far-zone
		# minimum proves that the original >=3-entrant draft cannot succeed.
		# Avoid repeating large-map A* searches for that certified failure.
		var certified_failure := not authored_short and ids.size() >= 3 and float(frame.barrier_depth) < original_far_min-EPSILON
		if use_compartment or certified_failure: rect = frame.rect
	var room_center := rect.get_center()
	var along_width := rect.size.x if door.get("axis", "x") == "x" else rect.size.y
	var room_depth := rect.size.y if door.get("axis", "x") == "x" else rect.size.x
	var across_center := (room_center - center).dot(across)
	var far_depth := (room_center - center).dot(inward) + room_depth * 0.5
	if far_depth <= Navigation.RADIUS * 2.0: return _error("room", door_id)
	var short_room := rect.get_area() <= 9.0 + EPSILON or minf(rect.size.x, rect.size.y) <= 2.5 + EPSILON
	var baseline: BreachNavigation = shared_baseline
	if baseline == null:
		baseline = PlanningNavigation.new()
		baseline.build(data, data.get("doors", []).duplicate(true))
		# Owned planning copies never change after their final door pose.
		baseline.begin_geometry_scope()
	# Shared offline baselines were already built/scoped by their owner.
	# Only STATIC_KEYS movement geometry is used; lighting is irrelevant.
	var forecast_doors: Array = data.get("doors", []).duplicate(true)
	var open_door: Dictionary = door.duplicate(true)
	for predicted: Dictionary in forecast_doors:
		if str(predicted.get("id", "")) != door_id: continue
		predicted["state"] = "OPEN"
		predicted["progress"] = 1.0
		if method in ["BREACH_DOOR", "SHOTGUN_BREACH"]: predicted["destroyed"] = true
		open_door = predicted
	var forecast: BreachNavigation = private_navigation.get("forecast",null) if private_navigation is Dictionary else null
	if forecast == null:
		forecast=PlanningNavigation.new()
		forecast.build(data,forecast_doors)
		forecast.begin_geometry_scope()
		if private_navigation is Dictionary: private_navigation.forecast=forecast
	# A planning-only sealed portal plane keeps side routes from using a second
	# doorway as a shortcut. The actual crossing is checked in forecast Nav.
	var side_data: Dictionary = data.duplicate(true)
	var side_walls: Array = side_data.get("walls", []).duplicate(true)
	var plane := {"id":"_drill_portal_plane", "x":bounds.x * 0.5, "z":center.y, "w":bounds.x, "d":maxf(0.24, float(door.get("d", 0.24)))} if door.get("axis", "x") == "x" else {"id":"_drill_portal_plane", "x":center.x, "z":bounds.y * 0.5, "w":maxf(0.24, float(door.get("w", 0.24))), "d":bounds.y}
	side_walls.append(plane)
	side_data["walls"] = side_walls
	var side_nav: BreachNavigation = private_navigation.get("side",null) if private_navigation is Dictionary else null
	if side_nav == null:
		side_nav=PlanningNavigation.new()
		side_nav.build(side_data,forecast_doors.duplicate(true))
		side_nav.begin_geometry_scope()
		if private_navigation is Dictionary: private_navigation.side=side_nav
	# One local entry anchor avoids choosing the side from a distant actor's
	# unrelated route. The opened leaf remains an obstacle in this navigation.
	var anchor := _entry_anchor(side_nav, center, inward, across, Door.width(door))
	if not _finite(anchor): return _error("entry", door_id)
	var near_depth := clampf(far_depth * 0.18, 0.8, 1.0)
	near_depth = minf(near_depth, far_depth * 0.5)
	var left_depth := _near_leaf_depth(forecast, open_door, center, inward, across, -1.0, across_center, near_depth, far_depth)
	var right_depth := _near_leaf_depth(forecast, open_door, center, inward, across, 1.0, across_center, near_depth, far_depth)
	var near_left := center + across * (across_center - along_width * 0.5 + MARGIN) + inward * left_depth
	var near_right := center + across * (across_center + along_width * 0.5 - MARGIN) + inward * right_depth
	var left := _domination(side_nav, anchor, near_left, rect, center, inward, across, -1.0, across_center, true, [], door, data.get("doors", []))
	var right := _domination(side_nav, anchor, near_right, rect, center, inward, across, 1.0, across_center, true, [], door, data.get("doors", []))
	if left.is_empty(): left = _domination(side_nav,anchor,near_left,rect,center,inward,across,-1.0,across_center,true,[],door,data.get("doors",[]),24)
	if right.is_empty(): right = _domination(side_nav,anchor,near_right,rect,center,inward,across,1.0,across_center,true,[],door,data.get("doors",[]),24)
	if left.is_empty() or right.is_empty(): return _error("domination", door_id)
	# A narrow room can give both independent near-corner searches valid
	# points whose separation is below team spacing (2.4 - 2*0.9 = 0.6m).
	# Retry only this invalid pair with the other body as a constraint. The
	# same wall clearance, front zone and actual portal routes still apply;
	# already valid layouts keep their original points and ordering exactly.
	if not _separated(right.point, [left.point], SPACING):
		var paired_right := _domination(side_nav, anchor, near_right, rect, center, inward, across, 1.0, across_center, true, [left.point], door, data.get("doors", []))
		if paired_right.is_empty(): paired_right = _domination(side_nav,anchor,near_right,rect,center,inward,across,1.0,across_center,true,[left.point],door,data.get("doors",[]),24)
		if not paired_right.is_empty():
			right = paired_right
		else:
			var paired_left := _domination(side_nav, anchor, near_left, rect, center, inward, across, -1.0, across_center, true, [right.point], door, data.get("doors", []))
			if paired_left.is_empty(): paired_left = _domination(side_nav,anchor,near_left,rect,center,inward,across,-1.0,across_center,true,[right.point],door,data.get("doors",[]),24)
			if paired_left.is_empty(): return _error("domination", door_id)
			left = paired_left
	var jamb := ceilf((Door.width(door) * 0.5 + Navigation.RADIUS + Door.LEAF_HALF_DEPTH + 0.05) * 100.0) / 100.0
	var left_stack := center - across * jamb - inward * 0.45
	var right_stack := center + across * jamb - inward * 0.45
	var left_entry := _entry_route(forecast, left_stack, left.point, door, data.get("doors", []), rect, side_nav)
	var right_entry := _entry_route(forecast, right_stack, right.point, door, data.get("doors", []), rect, side_nav)
	var left_cost := _route_length(left_stack, left_entry) + near_left.distance_to(left.point) * 4.0 if not left_entry.is_empty() else INF
	var right_cost := _route_length(right_stack, right_entry) + near_right.distance_to(right.point) * 4.0 if not right_entry.is_empty() else INF
	# A leaf can obstruct the approach-side jamb as well as an inside corner.
	# Compare complete opened-door routes, then prefer the stable left tie.
	var first_side := -1.0 if left_cost <= right_cost + EPSILON else 1.0
	var preferred: Array = [left.point, right.point] if first_side < 0.0 else [right.point, left.point]
	var assigned_sides: Array[float] = [first_side, -first_side, first_side, -first_side]
	var enter_count := mini(ids.size(), 2) if short_room else ids.size()
	var points: Array[Vector2] = []
	for index: int in range(enter_count):
		var goal: Vector2
		if index < 2:
			goal = preferred[index]
			if not _separated(goal, points, SPACING): return _error("domination", door_id)
		else:
			var lateral := minf(0.7, maxf(0.35, (along_width - MARGIN * 2.0) * 0.22))
			var nominal := center + across * (across_center + assigned_sides[index] * lateral) + inward * (far_depth - FAR_MARGIN)
			var found := _domination(side_nav, anchor, nominal, rect, center, inward, across, assigned_sides[index], across_center, false, points, door, data.get("doors", []))
			if found.is_empty():
				found = _compartment_domination(side_nav, anchor, nominal, rect, center, inward, across, assigned_sides[index], across_center, points, door, data.get("doors", []))
			if found.is_empty(): found = _domination(side_nav,anchor,nominal,rect,center,inward,across,assigned_sides[index],across_center,false,points,door,data.get("doors",[]),24)
			if found.is_empty(): found = _compartment_domination(side_nav,anchor,nominal,rect,center,inward,across,assigned_sides[index],across_center,points,door,data.get("doors",[]),24)
			# The fourth operator may watch its original assigned sector from
			# the other safe far half when furniture seals every candidate in
			# its own half. All far-zone/body/spacing/portal constraints remain;
			# the first two corner roles and original facing side are retained.
			if found.is_empty() and index == 3 and _half_within_search(rect,nominal,center,across,assigned_sides[index],across_center,6.0): found = _domination(side_nav,anchor,nominal,rect,center,inward,across,-assigned_sides[index],across_center,false,points,door,data.get("doors",[]),24)
			if found.is_empty(): return _error("domination", door_id)
			goal = found.point
		points.append(goal)
	# Exact original 65 poses of this owned authored door, not its forecast.
	# Share only within this calculation; sample order/body radius stay intact.
	var sweep_obstacles := _sweep_obstacles(door)
	var stacks: Array[Vector2] = []
	var slots: Array = []
	var operator_id := str(options.get("operator_id", ids[0]))
	if not ids.has(operator_id): return _error("team", door_id)
	for index: int in range(ids.size()):
		var origin: Vector2 = origins[ids[index]]
		var stack_side: float = assigned_sides[index]
		var nominal_stack := center + across * stack_side * jamb - inward * (0.45 + SPACING * float(index / 2))
		var stack_result := _stack(baseline, origin, nominal_stack, center, inward, across, stack_side, stacks, door,8,sweep_obstacles)
		if stack_result.is_empty(): stack_result = _stack(baseline,origin,nominal_stack,center,inward,across,stack_side,stacks,door,24,sweep_obstacles)
		if stack_result.is_empty(): return _error("stack", door_id)
		var stack: Vector2 = stack_result.point
		stacks.append(stack)
		var entering := index < enter_count
		var goal: Vector2 = points[index] if entering else stack
		var connection := _entry_connection(forecast, stack, goal, door, data.get("doors", []), rect, side_nav) if entering else {}
		var route: Array = connection.get("route", [])
		if entering and route.is_empty(): return _error("entry", door_id)
		var face_direction := _face_direction(goal, center, inward, across, assigned_sides[index], index, entering)
		var fan_radius := maxf(rect.size.length(), 1.0)
		for previous: int in range(index): fan_radius = minf(fan_radius, stack.distance_to(stacks[previous]) - Navigation.RADIUS - 0.05)
		var entry_heading := face_direction if index < 2 or not entering else (inward + across * assigned_sides[index] * 0.6).normalized()
		var entry_fan := _sector(stack, entry_heading.angle(), deg_to_rad(45.0), maxf(0.05, fan_radius))
		var arrival_fan := _sector(goal, face_direction.angle(), deg_to_rad(80.0), maxf(rect.size.length(), 1.0))
		var safe_result := _safe_retreat(baseline, stack, center, inward, across, assigned_sides[index], index, slots, door,sweep_obstacles)
		if method == "BREACH_DOOR" and safe_result.is_empty(): return _error("safety", door_id)
		var safe_point: Vector2 = safe_result.get("point", stack)
		var safe_route: Array = safe_result.get("route", [])
		slots.append({"unit_id":ids[index], "index":index + 1, "order":index + 1, "entry":entering,
			"role":"entry" if entering else "guard", "operator":ids[index] == operator_id,
			"stack":_array(stack), "stack_height":Spatial.floor_base_at(data.get("rooms", []), stack), "stack_route":stack_result.route,
			"domination":_array(goal), "floor_height":Spatial.floor_base_at(data.get("rooms", []), goal), "entry_route":route, "entry_waypoints":connection.get("waypoints", []),
			"safe_retreat":_array(safe_point), "safe_route":safe_route, "face_target":_array(goal + face_direction * 2.0),
			"sector_entry":entry_fan, "sector_domination":arrival_fan,
			"sector":{"start":entry_fan.start,"end":entry_fan.end,"duration":12.0}})
	var long_goals: Array = []
	# A front operator must be able to reach its stack after a rear operator
	# has stopped there. Opposite-side actors also need separate crossing rows.
	# These temporary bodies are exclusively the supplied owned plan points.
	for index: int in range(slots.size()):
		var stack: Vector2 = stacks[index]
		var stack_route := _cohort_stack_route(side_data, data.get("doors", []), baseline, origins[ids[index]], stack, center, inward, across, index, ids, origins, stacks, door)
		if stack_route.is_empty(): return _error("stack", door_id)
		slots[index]["stack_route"] = stack_route
		slots[index]["stack_waypoints"] = stack_route.slice(0, stack_route.size() - 1)
	if bool(options.get("go_long", false)):
		for index: int in range(mini(2, enter_count)):
			var nominal := center + across * (across_center + assigned_sides[index] * maxf(0.4, along_width * 0.5 - MARGIN)) + inward * (far_depth - FAR_MARGIN)
			var used: Array[Vector2] = points.slice(2)
			for long_goal: Dictionary in long_goals: used.append(_point(long_goal.target))
			var found := _domination(side_nav, points[index], nominal, rect, center, inward, across, assigned_sides[index], across_center, false, used, door, data.get("doors", []))
			if found.is_empty(): return _error("domination", door_id)
			var long_point: Vector2 = found.point
			var heading := (room_center - long_point).normalized()
			if heading.length_squared() < EPSILON: heading = -inward
			long_goals.append({"unit_id":ids[index], "target":_array(long_point), "route":found.route,
				"floor_height":Spatial.floor_base_at(data.get("rooms", []), long_point), "face_target":_array(long_point + heading * 2.0),
				"sector":_sector(long_point, heading.angle(), deg_to_rad(80.0), rect.size.length())})
	var funnel := Door.funnel_rect(door)
	var answer := {"ok":true, "reason_code":"", "message_key":"", "door_id":door_id, "room_id":str(room.id), "method":method,
		"operator_id":operator_id, "entry_side":side, "short_room":short_room, "entry_count":enter_count,
		"funnel":[funnel.position.x,funnel.position.y,funnel.size.x,funnel.size.y], "slots":slots, "go_long":long_goals}
	if rect != authored_rect: answer["effective_frame"] = [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
	return answer

## A casualty changes only the remaining movement/watch draft. The original
## four-slot entry geometry fixes the room and side even for actors inside it.
## No door action or equipment resource is returned or issued here.
static func recalculate_three(static_geometry: Dictionary, prior_layout: Dictionary, survivor_order_ids: Array, current_positions_by_id: Dictionary, _options: Dictionary = {}) -> Dictionary:
	var door_id := str(prior_layout.get("door_id", ""))
	var room_id := str(prior_layout.get("room_id", ""))
	var method := str(prior_layout.get("method", "OPEN_DOOR"))
	if not bool(prior_layout.get("ok", false)) or not METHODS.has(method) or survivor_order_ids.size() != 3: return _reformation_error("team", door_id)
	var prior_slots: Variant = prior_layout.get("slots", [])
	if not prior_slots is Array or prior_slots.size() != 4: return _reformation_error("team", door_id)
	var old_ids: Array[String] = []
	for slot: Variant in prior_slots:
		if not slot is Dictionary: return _reformation_error("team", door_id)
		var old_id := str(slot.get("unit_id", ""))
		if old_id.is_empty() or old_ids.has(old_id): return _reformation_error("team", door_id)
		if not _finite(_point(slot.get("domination"))) or not slot.get("sector_domination") is Dictionary or not _sector_valid(slot.sector_domination): return _reformation_error("domination", door_id)
		old_ids.append(old_id)
	var ids: Array[String] = []
	var origins: Dictionary = {}
	for id: Variant in survivor_order_ids:
		if not id is String or ids.has(str(id)) or not old_ids.has(str(id)): return _reformation_error("team", door_id)
		var origin := _point(current_positions_by_id.get(id))
		if not _finite(origin): return _reformation_error("approach", door_id)
		ids.append(str(id))
		origins[str(id)] = origin
	var data: Dictionary = {}
	for key: String in STATIC_KEYS:
		if static_geometry.has(key): data[key] = static_geometry[key].duplicate(true) if static_geometry[key] is Dictionary or static_geometry[key] is Array else static_geometry[key]
	for key: String in ["rooms", "doors", "walls", "props", "walkable_areas"]:
		if data.has(key) and not data[key] is Array: return _reformation_error("geometry", door_id)
	if not data.get("bounds", []) is Array or data.get("bounds", []).size() != 2 or not _geometry_valid(data): return _reformation_error("geometry", door_id)
	var bounds := _point(data.bounds)
	if not _finite(bounds) or bounds.x <= 0.0 or bounds.y <= 0.0: return _reformation_error("geometry", door_id)
	var room: Dictionary = {}
	var door: Dictionary = {}
	for candidate: Dictionary in data.get("rooms", []):
		if str(candidate.get("id", "")) == room_id: room = candidate
	var states: Array = data.get("doors", []).duplicate(true)
	for candidate: Dictionary in states:
		if str(candidate.get("id", "")) == door_id:
			candidate["state"] = "OPEN"
			candidate["progress"] = 1.0
			if method in ["BREACH_DOOR", "SHOTGUN_BREACH"]: candidate["destroyed"] = true
			door = candidate
	if room.is_empty() or door.is_empty(): return _reformation_error("room", door_id)
	var side := float(prior_layout.get("entry_side", 0.0))
	if absf(absf(side) - 1.0) > EPSILON: return _reformation_error("approach", door_id)
	var normal := Vector2.DOWN if str(door.get("axis", "x")) == "x" else Vector2.RIGHT
	var across := Vector2.RIGHT if str(door.get("axis", "x")) == "x" else Vector2.DOWN
	var inward := -normal * side
	var center := _entity_point(door)
	var rect := _room_rect(room)
	var nav = Navigation.new()
	nav.build(data, states)
	nav.begin_geometry_scope()
	var side_data := data.duplicate(true)
	var walls: Array = side_data.get("walls", []).duplicate(true)
	walls.append({"id":"_reformation_portal", "x":bounds.x * 0.5, "z":center.y, "w":bounds.x, "d":maxf(0.24, float(door.get("d", 0.24)))} if str(door.get("axis", "x")) == "x" else {"id":"_reformation_portal", "x":center.x, "z":bounds.y * 0.5, "w":maxf(0.24, float(door.get("w", 0.24))), "d":bounds.y})
	side_data["walls"] = walls
	var side_nav = Navigation.new()
	side_nav.build(side_data, states.duplicate(true))
	side_nav.begin_geometry_scope()
	for id: String in ids:
		if not nav.walkable(origins[id]): return _reformation_error("approach", door_id)
	var short_room := bool(prior_layout.get("short_room", false))
	# Keep both near control points, but do not force surviving operators to
	# exchange sides in a narrow lane after a casualty. Only known own origins
	# and the two authored draft routes choose this deterministic permutation.
	var near_sources: Array[int] = [0, 1]
	var original_cost := _near_remap_cost(nav, side_nav, origins, ids, prior_slots, near_sources, rect, door, states)
	var swapped_cost := _near_remap_cost(nav, side_nav, origins, ids, prior_slots, [1, 0], rect, door, states)
	if swapped_cost < original_cost - EPSILON: near_sources = [1, 0]
	if is_inf(minf(original_cost, swapped_cost)): return _reformation_error("domination", door_id)
	var goals: Array[Vector2] = []
	var results: Array = []
	for index: int in range(3):
		var source: Dictionary = prior_slots[near_sources[index] if index < 2 else index]
		var entering := not short_room or index < 2
		var nominal := _point(source.get("domination"))
		if index == 2 and not short_room: nominal = (_point(prior_slots[2].get("domination")) + _point(prior_slots[3].get("domination"))) * 0.5
		if not _finite(nominal): return _reformation_error("domination", door_id)
		var connection := _reformation_connection(nav, side_nav, origins[ids[index]], nominal, entering, rect, door, states)
		var goal := nominal
		if index == 2 and not short_room:
			var merged := _merged_far(nav, side_nav, origins[ids[index]], nominal, goals, rect, center, inward, across, door, states)
			if merged.is_empty(): return _reformation_error("domination", door_id)
			goal = merged.point
			connection = merged.connection
		if connection.is_empty() or not _separated(goal, goals, SPACING): return _reformation_error("domination", door_id)
		if entering and not rect.grow(-Navigation.RADIUS).has_point(goal): return _reformation_error("domination", door_id)
		if not entering and (goal - center).dot(inward) >= 0.0: return _reformation_error("domination", door_id)
		goals.append(goal)
		var sector: Dictionary
		if index == 2 and not short_room:
			sector = _merged_sector(goal, prior_slots[2].get("sector_domination", {}), prior_slots[3].get("sector_domination", {}), rect.size.length())
		else:
			var old_sector: Dictionary = source.get("sector_domination", {})
			if not _sector_valid(old_sector): return _reformation_error("domination", door_id)
			sector = old_sector.duplicate(true)
			sector["origin"] = _array(goal)
		if sector.is_empty(): return _reformation_error("domination", door_id)
		var heading := float(sector.center)
		results.append({"unit_id":ids[index], "order":index + 1, "entry":entering, "role":"merged_far" if index == 2 and not short_room else ("entry" if entering else "guard"),
			"target":_array(goal), "route":connection.route, "entry_waypoints":connection.get("waypoints", []),
			"floor_height":Spatial.floor_base_at(data.get("rooms", []), goal), "face_target":_array(goal + Vector2.from_angle(heading) * 2.0), "sector":sector})
	return {"ok":true, "reason_code":"", "message_key":"", "door_id":door_id, "room_id":room_id, "method":method, "entry_side":side,
		"short_room":short_room, "entry_count":2 if short_room else 3, "targets":results}

static func _reformation_error(reason: String, door_id: String) -> Dictionary:
	var failure := _error(reason, door_id)
	failure["targets"] = []
	return failure

static func _near_remap_cost(nav: BreachNavigation, side_nav: BreachNavigation, origins: Dictionary, ids: Array, prior_slots: Array, assignment: Array, rect: Rect2, door: Dictionary, doors: Array) -> float:
	var cost := 0.0
	for index: int in range(2):
		var goal := _point(prior_slots[int(assignment[index])].domination)
		var origin: Vector2 = origins[ids[index]]
		var connection := _reformation_connection(nav, side_nav, origin, goal, true, rect, door, doors)
		if connection.is_empty(): return INF
		cost += _route_length(origin, connection.route)
	return cost

static func _reformation_connection(nav: BreachNavigation, side_nav: BreachNavigation, origin: Vector2, goal: Vector2, entering: bool, rect: Rect2, door: Dictionary, doors: Array) -> Dictionary:
	if not nav.walkable(goal): return {}
	if entering and rect.grow(0.05).has_point(origin):
		var route := nav.path(origin, goal)
		if route.is_empty() or not _inside_route(origin, route, rect) or _crosses_other_door(origin, route, door, doors): return {}
		return {"route":route, "waypoints":[]}
	if entering: return _entry_connection(nav, origin, goal, door, doors, rect, side_nav)
	var guard_route := nav.path(origin, goal)
	if guard_route.is_empty() or _crosses_door(origin, guard_route, door) or _crosses_other_door(origin, guard_route, door, doors): return {}
	return {"route":guard_route, "waypoints":[]}

static func _merged_far(nav: BreachNavigation, side_nav: BreachNavigation, origin: Vector2, nominal: Vector2, used: Array, rect: Rect2, center: Vector2, inward: Vector2, across: Vector2, door: Dictionary, doors: Array) -> Dictionary:
	var depth := rect.size.y if str(door.get("axis", "x")) == "x" else rect.size.x
	var midpoint_depth := (rect.get_center() - center).dot(inward)
	var best: Dictionary = {}
	var best_cost := INF
	for offset: Vector2i in _offsets():
		var goal := nominal + across * float(offset.x) * Navigation.CELL + inward * float(offset.y) * Navigation.CELL
		if not rect.grow(-Navigation.RADIUS - 0.05).has_point(goal) or (goal - center).dot(inward) < midpoint_depth - EPSILON: continue
		if not _separated(goal, used, SPACING): continue
		var penalty := goal.distance_to(nominal) * 4.0
		if penalty >= best_cost: continue
		var connection := _reformation_connection(nav, side_nav, origin, goal, true, rect, door, doors)
		if connection.is_empty(): continue
		# A reachable midpoint is the actual merge, not an optimization hint.
		if offset == Vector2i.ZERO: return {"point":goal, "connection":connection}
		var cost := penalty + _route_length(origin, connection.route) / maxf(1.0, depth)
		if cost < best_cost - EPSILON:
			best_cost = cost
			best = {"point":goal, "connection":connection}
	return best

static func _sector_valid(sector: Dictionary) -> bool:
	return _number(sector.get("start")) and _number(sector.get("end")) and _number(sector.get("center")) and _number(sector.get("duration", 12.0)) and float(sector.get("duration", 12.0)) >= 0.0 and (not sector.has("radius") or (_number(sector.radius) and float(sector.radius) > 0.0))

static func _merged_sector(origin: Vector2, a: Dictionary, b: Dictionary, radius: float) -> Dictionary:
	if not _sector_valid(a) or not _sector_valid(b): return {}
	var intervals: Array = []
	for fan: Dictionary in [a, b]:
		var difference := float(fan.end) - float(fan.start)
		if absf(difference) >= TAU - EPSILON:
			var full := _sector(origin, 0.0, PI, radius)
			full["end"] = float(full.start) + TAU
			full["duration"] = maxf(float(a.get("duration", 12.0)), float(b.get("duration", 12.0)))
			return full
		var start := fposmod(float(fan.start), TAU)
		var end := start + fposmod(difference, TAU)
		intervals.append([start, minf(TAU, end)])
		if end > TAU: intervals.append([0.0, end - TAU])
	intervals.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var merged: Array = []
	for interval: Array in intervals:
		if merged.is_empty() or float(interval[0]) > float(merged.back()[1]) + EPSILON:
			merged.append(interval.duplicate())
		else: merged.back()[1] = maxf(float(merged.back()[1]), float(interval[1]))
	var largest_gap := -1.0
	var start := 0.0
	for index: int in range(merged.size()):
		var following := float(merged[(index + 1) % merged.size()][0]) + (TAU if index == merged.size() - 1 else 0.0)
		var gap := following - float(merged[index][1])
		if gap > largest_gap + EPSILON:
			largest_gap = gap
			start = fposmod(following, TAU)
	var width := TAU - maxf(0.0, largest_gap)
	var answer := _sector(origin, start + width * 0.5, width * 0.5, radius)
	# A complete circle needs an unwrapped end so the existing sector contract
	# can distinguish it from an empty start == end interval.
	if width >= TAU - EPSILON: answer["end"] = float(answer.start) + TAU
	answer["duration"] = maxf(float(a.get("duration", 12.0)), float(b.get("duration", 12.0)))
	return answer

static func _error(reason: String, door_id: String) -> Dictionary:
	return {"ok":false,"reason_code":"drill_" + reason,"message_key":"drill.error." + reason,"door_id":door_id,"slots":[],"go_long":[]}

static func _point(value: Variant) -> Vector2:
	if value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]): return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary and _number(value.get("x")) and _number(value.get("z")): return Vector2(float(value.x), float(value.z))
	return Vector2(INF, INF)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _finite(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y)

static func _array(point: Vector2) -> Array:
	return [point.x, point.y]

static func _entity_point(entity: Dictionary) -> Vector2:
	return Vector2(float(entity.get("x", 0.0)), float(entity.get("z", 0.0)))

static func _room_rect(room: Dictionary) -> Rect2:
	return Rect2(_entity_point(room) - Vector2(float(room.w), float(room.d)) * 0.5, Vector2(float(room.w), float(room.d)))

static func _geometry_valid(data: Dictionary) -> bool:
	for key: String in ["doors", "rooms", "walls", "props", "walkable_areas"]:
		for value: Variant in data.get(key, []):
			if not value is Dictionary: return false
			for coordinate: String in ["x", "z", "w", "d"]:
				if not _number(value.get(coordinate)): return false
			if float(value.w) <= 0.0 or float(value.d) <= 0.0: return false
			if value.has("base_height") and not _number(value.base_height): return false
			if key == "doors" and value.get("axis", "x") not in ["x", "z"]: return false
	return true

static func _choose_room(rooms: Array, door: Dictionary, portal: Vector2, requested: String) -> Dictionary:
	var candidates: Array = []
	var floor := Spatial.floor_base_at(rooms, portal)
	for room: Dictionary in rooms:
		if not _room_rect(room).has_point(portal): continue
		if not requested.is_empty() and str(room.get("id", "")) != requested: continue
		candidates.append(room)
	if candidates.is_empty(): return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ah := absf(float(a.get("base_height", 0.0)) - floor)
		var bh := absf(float(b.get("base_height", 0.0)) - floor)
		if not is_equal_approx(ah, bh): return ah < bh
		var ad := absf(float(a.get("base_height", 0.0)) - float(door.get("base_height", floor)))
		var bd := absf(float(b.get("base_height", 0.0)) - float(door.get("base_height", floor)))
		if not is_equal_approx(ad, bd): return ad < bd
		if bool(a.get("indoor", true)) != bool(b.get("indoor", true)): return bool(a.get("indoor", true))
		var aa := _room_rect(a).get_area()
		var ba := _room_rect(b).get_area()
		if not is_equal_approx(aa, ba): return aa < ba
		return str(a.get("id", "")) < str(b.get("id", "")))
	return candidates[0]

static func _entry_anchor(nav: BreachNavigation, center: Vector2, inward: Vector2, across: Vector2, width: float) -> Vector2:
	for depth: float in [0.35, 0.65, 1.0]:
		for fraction: float in [0.0, -0.2, 0.2, -0.35, 0.35]:
			var point := center + inward * depth + across * width * fraction
			# Contains uses an open boundary while a swept segment treats exact
			# contact as blocked. Keep the anchor clear of both representations.
			if nav.walkable(point) and nav.segment_clear(point, point, Navigation.RADIUS + 0.01): return point
	return Vector2(INF, INF)

static func _portal_frame(data: Dictionary, selected: Dictionary, rect: Rect2, center: Vector2, inward: Vector2, across: Vector2) -> Dictionary:
	# A logical authored room may contain several physical rooms and a hall.
	# Prove a barrier across its complete tangent span using actual walls and
	# different portal planes (which an entry route is forbidden to cross).
	# An isolated door in a different bay cannot certify such a boundary.
	var corners: Array[Vector2] = [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	var span_min := INF
	var span_max := -INF
	var near_depth := INF
	var far_depth := -INF
	for corner: Vector2 in corners:
		span_min = minf(span_min,(corner-center).dot(across))
		span_max = maxf(span_max,(corner-center).dot(across))
		near_depth = minf(near_depth,(corner-center).dot(inward))
		far_depth = maxf(far_depth,(corner-center).dot(inward))
	var pieces: Array = []
	var planes: Array[float] = []
	for wall: Dictionary in data.get("walls",[]):
		var tangent_size := float(wall.w) if absf(across.x)>0.5 else float(wall.d)
		var normal_size := float(wall.d) if absf(across.x)>0.5 else float(wall.w)
		if tangent_size < normal_size: continue
		var depth := (_point(wall)-center).dot(inward)
		var lateral := (_point(wall)-center).dot(across)
		# The frame is a whole-body movement proof. Adjacent physical walls
		# leave no passage when their inflated intervals overlap, even if the
		# raw rendering rectangles leave a slit below the actor diameter.
		pieces.append({"depth":depth,"half":normal_size*0.5,"min":lateral-tangent_size*0.5-Navigation.RADIUS,"max":lateral+tangent_size*0.5+Navigation.RADIUS})
		if depth>0.1 and depth<=far_depth+normal_size*0.5+EPSILON: planes.append(depth)
	for door: Dictionary in data.get("doors",[]):
		if str(door.get("id",""))==str(selected.get("id","")) or str(door.get("axis","x"))!=str(selected.get("axis","x")): continue
		var depth := (_point(door)-center).dot(inward)
		var lateral := (_point(door)-center).dot(across)
		var half := float(door.get("d",0.24) if str(door.get("axis","x"))=="x" else door.get("w",0.24))*0.5
		pieces.append({"depth":depth,"half":half,"min":lateral-Door.width(door)*0.5,"max":lateral+Door.width(door)*0.5})
		# A forbidden different portal stays at its raw width. Only an actual
		# intact, fully closed leaf adds physical actor-radius inflation; an
		# open, destroyed or rotated leaf cannot close a real side passage.
		if not bool(door.get("destroyed",false)) and str(door.get("state","CLOSED")) in ["CLOSED","LOCKED"] and absf(float(door.get("progress",0.0)))<=EPSILON:
			var leaf := Door.leaf_obstacle(door)
			if not leaf.is_empty():
				var leaf_depth := (_point(leaf)-center).dot(inward)
				var leaf_lateral := (_point(leaf)-center).dot(across)
				pieces.append({"depth":leaf_depth,"half":float(leaf.d)*0.5,"min":leaf_lateral-Door.width(door)*0.5-Navigation.RADIUS,"max":leaf_lateral+Door.width(door)*0.5+Navigation.RADIUS})
		if depth>0.1 and depth<=far_depth+half+EPSILON: planes.append(depth)
	planes.sort()
	var seen: Array[float] = []
	for plane: float in planes:
		if seen.has(plane): continue
		seen.append(plane)
		var intervals: Array = []
		var thickness := 0.0
		for piece: Dictionary in pieces:
			if absf(float(piece.depth)-plane)>float(piece.half)+EPSILON: continue
			if float(piece.max)<span_min-0.05 or float(piece.min)>span_max+0.05: continue
			intervals.append(piece)
			thickness=maxf(thickness,float(piece.half))
		intervals.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
			if float(a.min)!=float(b.min): return float(a.min)<float(b.min)
			return float(a.max)<float(b.max))
		var covered := span_min-0.05
		for interval: Dictionary in intervals:
			if float(interval.max)<covered-EPSILON: continue
			if float(interval.min)>covered+EPSILON: break
			covered=maxf(covered,float(interval.max))
		if covered<span_max+0.05-EPSILON: continue
		var front := maxf(0.0,near_depth)
		var back := minf(far_depth,plane-thickness)
		if back-front<=Navigation.RADIUS*2.0+0.1: return {}
		var first := center+across*span_min+inward*front
		var last := center+across*span_max+inward*back
		var frame := Rect2(Vector2(minf(first.x,last.x),minf(first.y,last.y)),Vector2(absf(last.x-first.x),absf(last.y-first.y)))
		if frame==rect: return {}
		return {"rect":frame,"far_depth":back,"barrier_depth":plane}
	return {}

static func _half_within_search(rect: Rect2, nominal: Vector2, center: Vector2, across: Vector2, side: float, across_center: float, radius: float) -> bool:
	var half := rect.grow(-Navigation.RADIUS-0.05)
	if absf(across.x)>0.5:
		var split := center.x+across_center+side*0.2
		if side<0.0: half.size.x=maxf(0.0,minf(half.end.x,split)-half.position.x)
		else:
			var end := half.end.x
			half.position.x=maxf(half.position.x,split)
			half.size.x=maxf(0.0,end-half.position.x)
	else:
		var split := center.y+across_center+side*0.2
		if side<0.0: half.size.y=maxf(0.0,minf(half.end.y,split)-half.position.y)
		else:
			var end := half.end.y
			half.position.y=maxf(half.position.y,split)
			half.size.y=maxf(0.0,end-half.position.y)
	return maxf(absf(half.position.x-nominal.x),absf(half.end.x-nominal.x))<=radius+EPSILON and maxf(absf(half.position.y-nominal.y),absf(half.end.y-nominal.y))<=radius+EPSILON

static func _near_leaf_depth(nav: BreachNavigation, door: Dictionary, center: Vector2, inward: Vector2, across: Vector2, assigned_side: float, across_center: float, depth: float, far_depth: float) -> float:
	var leaf := Door.leaf_obstacle(door)
	if leaf.is_empty(): return depth
	var leaf_side := (_entity_point(leaf) - center).dot(across) - across_center
	if leaf_side * assigned_side <= 0.0: return depth
	var tip := 0.0
	for corner: Vector2 in nav.obstacle_corners(leaf): tip = maxf(tip, (corner - center).dot(inward))
	# Keep the side-wall inset, and let room-scaled entry depth clear the
	# physical leaf instead of walking past it and back to a shallow corner.
	# The first pair remain in the front half even in a short/narrow room.
	return maxf(depth, minf(tip + Navigation.RADIUS + 0.05, far_depth * 0.5 - 0.05))

static func _separated(point: Vector2, others: Array, distance: float) -> bool:
	for other: Vector2 in others:
		if point.distance_to(other) < distance - EPSILON: return false
	return true

static func _offsets(radius: int = 8) -> Array[Vector2i]:
	# A bounded local fallback avoids rasterizing a 512 m map for four points.
	var result: Array[Vector2i] = []
	for depth: int in range(-radius, radius+1):
		for lateral: int in range(-radius, radius+1): result.append(Vector2i(lateral, depth))
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.length_squared() != b.length_squared(): return a.length_squared() < b.length_squared()
		if a.y != b.y: return a.y < b.y
		return a.x < b.x)
	return result

static func _domination(nav: BreachNavigation, origin: Vector2, nominal: Vector2, rect: Rect2, center: Vector2, inward: Vector2, across: Vector2, assigned_side: float, across_center: float, near: bool, used: Array, door: Dictionary, doors: Array, search_radius: int = 8) -> Dictionary:
	var near_limit := maxf(1.8, minf(rect.size.x, rect.size.y) * 0.45)
	var best: Dictionary = {}
	var best_cost := INF
	for offset: Vector2i in _offsets(search_radius):
		var point := nominal + across * float(offset.x) * Navigation.CELL + inward * float(offset.y) * Navigation.CELL
		if not rect.grow(-Navigation.RADIUS - 0.05).has_point(point): continue
		var depth := (point - center).dot(inward)
		if depth < 0.45 or (near and depth > near_limit): continue
		if ((point - center).dot(across) - across_center) * assigned_side < 0.2: continue
		if not near and depth < maxf(near_limit, 1.0): continue
		if not _separated(point, used, SPACING) or not nav.walkable(point): continue
		var penalty := nominal.distance_to(point) * 4.0
		if penalty >= best_cost: continue
		# Every actual polyline is at least its endpoint distance. A strict
		# lower bound cannot replace the existing winner, so avoid that A*
		# query without changing candidate order, ties or any physical checks.
		if origin.distance_to(point)+penalty > best_cost+EPSILON: continue
		var route: Array = nav.path(origin, point)
		if route.is_empty() or not _inside_route(origin, route, rect) or _crosses_other_door(origin, route, door, doors): continue
		var cost := _route_length(origin, route) + penalty
		if cost < best_cost - EPSILON:
			best_cost = cost
			best = {"point":point,"route":route,"cost":cost}
	return best

static func _compartment_domination(nav: BreachNavigation, origin: Vector2, nominal: Vector2, rect: Rect2, center: Vector2, inward: Vector2, across: Vector2, assigned_side: float, across_center: float, used: Array, door: Dictionary, doors: Array, search_radius: int = 8) -> Dictionary:
	# An authored room may contain another partition doorway. If the original
	# far goal is unreachable without crossing that different door, search in
	# front of its plane. Reuse every original domination constraint; this
	# fallback never runs for a successful original goal or crosses the portal.
	var boundaries: Array = []
	var original_depth := (nominal-center).dot(inward)
	for other: Dictionary in doors:
		if str(other.get("id","")) == str(door.get("id","")) or str(other.get("axis","x")) != str(door.get("axis","x")): continue
		var point := _point(other)
		if not _finite(point) or not rect.grow(0.05).has_point(point): continue
		var depth := (point-center).dot(inward)
		if depth <= EPSILON or depth >= original_depth+FAR_MARGIN-EPSILON: continue
		boundaries.append({"depth":depth,"id":str(other.get("id",""))})
	boundaries.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if not is_equal_approx(float(a.depth),float(b.depth)): return float(a.depth) < float(b.depth)
		return str(a.id) < str(b.id))
	var tried: Array[float] = []
	for boundary: Dictionary in boundaries:
		var depth := float(boundary.depth)-FAR_MARGIN
		if tried.has(depth): continue
		tried.append(depth)
		var alternative := nominal + inward*(depth-original_depth)
		var found := _domination(nav,origin,alternative,rect,center,inward,across,assigned_side,across_center,false,used,door,doors,search_radius)
		if not found.is_empty(): return found
	return {}

static func _stack(nav: BreachNavigation, origin: Vector2, nominal: Vector2, center: Vector2, inward: Vector2, across: Vector2, stack_side: float, used: Array, door: Dictionary, search_radius: int = 8, sweep_obstacles: Array = []) -> Dictionary:
	if not nav.walkable(origin): return {}
	for offset: Vector2i in _offsets(search_radius):
		var point := nominal + across * stack_side * absf(float(offset.x)) * Navigation.CELL - inward * absf(float(offset.y)) * Navigation.CELL
		if (point - center).dot(inward) > -0.25 or not _separated(point, used, SPACING): continue
		if Door.funnel_rect(door).grow(Navigation.RADIUS).has_point(point) or not nav.walkable(point) or not _sweep_clear(door, point,sweep_obstacles): continue
		var route: Array = nav.path(origin, point)
		if route.is_empty() or _crosses_door(origin, route, door): continue
		return {"point":point,"route":route}
	return {}

static func _sweep_obstacles(door: Dictionary) -> Array:
	var result: Array = []
	if bool(door.get("destroyed",false)): return result
	for sample: int in range(65): result.append(Door.movement_obstacle(door,float(sample)/64.0))
	return result

static func _sweep_clear(door: Dictionary, point: Vector2, sweep_obstacles: Array = []) -> bool:
	if bool(door.get("destroyed", false)): return true
	if not sweep_obstacles.is_empty():
		for obstacle: Dictionary in sweep_obstacles:
			if Door.obstacle_overlaps_actor(obstacle,point,Navigation.RADIUS+0.02): return false
		return true
	# Preserve the original standalone helper/default path exactly.
	for sample: int in range(65):
		if Door.overlaps_actor(door, float(sample) / 64.0, point, Navigation.RADIUS + 0.02): return false
	return true

static func _cohort_stack_route(side_data: Dictionary, baseline_doors: Array, baseline: BreachNavigation, origin: Vector2, goal: Vector2, center: Vector2, inward: Vector2, across: Vector2, index: int, ids: Array[String], origins: Dictionary, stacks: Array[Vector2], door: Dictionary) -> Array:
	var direct: Array = baseline.path(origin, goal)
	if direct.is_empty(): return []
	if origin.distance_to(goal) <= 0.08: return direct
	var occupied: Array[Vector2] = []
	for other: int in range(ids.size()):
		if other == index: continue
		for point: Vector2 in [origins[ids[other]], stacks[other]]:
			# A teammate occupying this actor's starting/ending spot is expected
			# to vacate it. Avoid its intermediate location, without sealing the
			# actor inside a future body or making the final stack unreachable.
			if point.distance_to(origin) > 0.66 and point.distance_to(goal) > 0.66: occupied.append(point)
	var origin_lateral := (origin - center).dot(across)
	var goal_lateral := (goal - center).dot(across)
	var crossing := origin_lateral * goal_lateral < -EPSILON
	var blocked := false
	var previous := origin
	for coordinate: Array in direct:
		var next := _point(coordinate)
		for body: Vector2 in occupied:
			if _segment_distance(body, previous, next) < Navigation.RADIUS * 2.0 + 0.05: blocked = true
		previous = next
	if not crossing and not blocked and not _crosses_door(origin, direct, door): return direct
	var data: Dictionary = side_data.duplicate(true)
	var props: Array = data.get("props", []).duplicate(true)
	for body: Vector2 in occupied:
		props.append({"id":"_owned_plan_body", "type":"box", "x":body.x, "z":body.y, "w":Navigation.RADIUS * 2.0, "d":Navigation.RADIUS * 2.0, "cover":"full"})
	data["props"] = props
	var nav = PlanningNavigation.new()
	nav.build(data, baseline_doors.duplicate(true))
	nav.begin_geometry_scope()
	if not nav.walkable(origin) or not nav.walkable(goal): return []
	var origin_side := -1.0 if origin_lateral < -EPSILON else (1.0 if origin_lateral > EPSILON else signf(goal_lateral))
	var goal_side := signf(goal_lateral)
	var preferred_depth := Door.width(door) + Navigation.RADIUS + 0.25 + float(index) * SPACING
	for depth: float in _stack_lane_depths(_point(data.bounds), center, inward, preferred_depth):
		for origin_gap: float in [0.7, 1.0, 1.4, 0.5, 0.3]:
			for goal_gap: float in [0.7, 0.5, 0.3]:
				var origin_outer := origin + across * origin_side * origin_gap
				var goal_outer := goal + across * goal_side * goal_gap
				var outer_row := center - inward * depth
				var requested: Array[Vector2] = [origin_outer, outer_row + across * (origin_outer - center).dot(across), outer_row + across * (goal_outer - center).dot(across), goal_outer, goal]
				var route: Array = []
				var current := origin
				var valid := true
				for target: Vector2 in requested:
					var leg: Array = nav.path(current, target)
					if leg.is_empty() or _crosses_door(current, leg, door): valid = false; break
					for coordinate: Array in leg:
						var next := _point(coordinate)
						if not baseline.segment_clear(current, next, Navigation.RADIUS): valid = false; break
						route.append(coordinate)
						current = next
					if not valid: break
				if valid: return route
	return []

static func _stack_lane_depths(bounds: Vector2, center: Vector2, inward: Vector2, preferred: float) -> Array[float]:
	# Spacious staging keeps the rank-separated lanes. At a real map edge,
	# search the available strip instead of asking actors to leave its bounds.
	# These are geometric routes; runtime teammate collision still applies.
	var padding := Navigation.RADIUS + 0.02
	var outward := -inward
	var maximum := (bounds.x - center.x - padding if outward.x > 0.0 else center.x - padding) if absf(outward.x) > 0.5 else (bounds.y - center.y - padding if outward.y > 0.0 else center.y - padding)
	maximum = minf(maximum, preferred + SPACING * 2.0)
	var result: Array[float] = [preferred]
	for offset: int in range(24):
		var depth := maximum - float(offset) * Navigation.CELL
		if depth < 0.45: break
		if absf(depth - preferred) > EPSILON: result.append(depth)
	return result

static func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	if delta.length_squared() < EPSILON * EPSILON: return point.distance_to(a)
	return point.distance_to(a + delta * clampf((point - a).dot(delta) / delta.length_squared(), 0.0, 1.0))

static func _safe_retreat(nav: BreachNavigation, origin: Vector2, center: Vector2, inward: Vector2, across: Vector2, assigned_side: float, index: int, slots: Array, door: Dictionary, sweep_obstacles: Array = []) -> Dictionary:
	var used: Array[Vector2] = []
	for slot: Dictionary in slots: used.append(_point(slot.safe_retreat))
	var nominal := center - inward * (2.15 + SPACING * float(index / 2)) + across * assigned_side * 0.7
	for offset: Vector2i in _offsets():
		var point := nominal + across * float(offset.x) * Navigation.CELL - inward * absf(float(offset.y)) * Navigation.CELL
		if (point - center).dot(inward) >= 0.0 or point.distance_to(center) < 2.15 or not _separated(point, used, SPACING): continue
		if not nav.walkable(point) or not _sweep_clear(door, point,sweep_obstacles): continue
		var route: Array = nav.path(origin, point)
		if route.is_empty() or _crosses_door(origin, route, door): continue
		return {"point":point,"route":route}
	return {}

static func _entry_route(nav: BreachNavigation, origin: Vector2, point: Vector2, door: Dictionary, doors: Array, room: Rect2, side_nav: BreachNavigation) -> Array:
	return _entry_connection(nav, origin, point, door, doors, room, side_nav).get("route", [])

static func _entry_connection(nav: BreachNavigation, origin: Vector2, point: Vector2, door: Dictionary, doors: Array, room: Rect2, side_nav: BreachNavigation) -> Dictionary:
	var route: Array = nav.path(origin, point)
	if _valid_entry_route(origin, route, point, door, doors, room): return {"route":route,"waypoints":[]}
	# Another authored open door may be a shorter unconstrained route. Keep
	# the selected portal by connecting its two physically clear sides. Only
	# this fallback asks the macro to expand explicit primitive MOVE waypoints.
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var across := Vector2.RIGHT if door.get("axis", "x") == "x" else Vector2.DOWN
	var center := _entity_point(door)
	var origin_side := 1.0 if (origin - center).dot(normal) >= 0.0 else -1.0
	var best: Dictionary = {}
	var cost := INF
	for fraction: float in [0.0, -0.2, 0.2, -0.35, 0.35]:
		var before := center + normal * origin_side * 0.4 + across * Door.width(door) * fraction
		var after := center - normal * origin_side * 0.4 + across * Door.width(door) * fraction
		if not nav.walkable(before) or not nav.walkable(after) or not nav.segment_clear(before, after, Navigation.RADIUS): continue
		var approach: Array = side_nav.path(origin, before)
		var inside: Array = side_nav.path(after, point)
		if approach.is_empty() or inside.is_empty() or _crosses_door(origin, approach, door) or _crosses_other_door(origin, approach, door, doors): continue
		if not _inside_route(after, inside, room) or _crosses_other_door(after, inside, door, doors): continue
		var combined: Array = approach.duplicate(true)
		combined.append(_array(after))
		combined.append_array(inside)
		if not _valid_entry_route(origin, combined, point, door, doors, room): continue
		var length := _route_length(origin, combined)
		if length < cost - EPSILON:
			cost = length
			best = {"route":combined,"waypoints":combined.slice(0, combined.size() - 1)}
	return best

static func _valid_entry_route(origin: Vector2, route: Array, point: Vector2, door: Dictionary, doors: Array, room: Rect2) -> bool:
	if route.is_empty() or not _crosses_door(origin, route, door) or _crosses_other_door(origin, route, door, doors): return false
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var center := _entity_point(door)
	var target_side := 1.0 if (point - center).dot(normal) >= 0.0 else -1.0
	for coordinate: Array in route:
		var candidate := _point(coordinate)
		if (candidate - center).dot(normal) * target_side > 0.1 and not room.grow(0.05).has_point(candidate): return false
	return true

static func _inside_route(origin: Vector2, route: Array, room: Rect2) -> bool:
	if not room.grow(0.05).has_point(origin): return false
	for coordinate: Array in route:
		if not room.grow(0.05).has_point(_point(coordinate)): return false
	return true

static func _crosses_other_door(origin: Vector2, route: Array, selected: Dictionary, doors: Array) -> bool:
	for door: Dictionary in doors:
		if str(door.get("id", "")) != str(selected.id) and _crosses_door(origin, route, door): return true
	return false

static func _crosses_door(origin: Vector2, route: Array, door: Dictionary) -> bool:
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var across := Vector2.RIGHT if door.get("axis", "x") == "x" else Vector2.DOWN
	var center := _entity_point(door)
	for coordinate: Array in route:
		var endpoint := _point(coordinate)
		var before := (origin - center).dot(normal)
		var after := (endpoint - center).dot(normal)
		if before * after <= 0.0 and absf(before - after) > EPSILON:
			var crossing := origin.lerp(endpoint, before / (before - after))
			if absf((crossing - center).dot(across)) <= Door.width(door) * 0.5 + EPSILON: return true
		origin = endpoint
	return false

static func _route_length(origin: Vector2, route: Array) -> float:
	var length := 0.0
	for coordinate: Array in route:
		var point := _point(coordinate)
		length += origin.distance_to(point)
		origin = point
	return length

static func _face_direction(point: Vector2, center: Vector2, inward: Vector2, across: Vector2, assigned_side: float, index: int, entering: bool) -> Vector2:
	if not entering: return -inward
	if index < 2: return (inward - across * assigned_side).normalized()
	var back := (center - point).normalized()
	return (back + across * assigned_side * 0.6).normalized()

static func _sector(origin: Vector2, heading: float, half_angle: float, radius: float) -> Dictionary:
	return {"origin":_array(origin),"start":wrapf(heading - half_angle, -PI, PI),"end":wrapf(heading + half_angle, -PI, PI),"center":wrapf(heading, -PI, PI),"radius":radius,"duration":12.0}
