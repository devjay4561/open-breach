extends RefCounted
## Offline content validation. NPC placements never participate in a room draft.
const Drill = preload("res://scripts/room_drill.gd")
const Nav = preload("res://scripts/navigation.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const EPS := 0.0001
# Try the full jamb lanes before the compact centerline starts. Every
# original candidate remains available; all accepted drafts use all checks.
const APPROACH_PATTERNS: Array[int] = [2,3,0,1,4,5]

static func validate_entry_drills(source: Dictionary) -> Dictionary:
	var result := {"checks":0,"errors":[],"door_count":source.get("doors",[]).size(),"entry_doors":0,"entry_directions":0,"short_guards":0,"passages":[],"entry_methods":[],"layouts":[]}
	var data: Dictionary = {}
	for key: String in Drill.STATIC_KEYS:
		if source.has(key): data[key] = source[key].duplicate(true) if source[key] is Array or source[key] is Dictionary else source[key]
	if source.has("environment"): data.environment = source.environment.duplicate(true)
	var ids: Array[String] = []
	for unit: Dictionary in source.get("units",[]):
		if ids.size() < 4: ids.append(str(unit.id))
	# The geometry contract measures four-person capacity even for an authored
	# operation with fewer deployed operators. These are owned planning IDs,
	# never additional NPC blockers or mission-data fields.
	while ids.size() < 4: ids.append("content_slot_%d" % [ids.size()+1])
	var opened: Array = data.get("doors",[]).duplicate(true)
	for door: Dictionary in opened:
		door.state = "OPEN"
		door.progress = 1.0
		if bool(door.get("destroyed",false)) or float(door.get("hp",1)) <= 0.0: door.destroyed = true
	# Structural access matches the existing hypothetical-open navigation
	# check. Real opened leaves are tested separately in every local draft and
	# in the original Python physical-passage loop, not at a spawn that a leaf
	# could occupy only after it has swung open.
	var structural_doors: Array = opened.duplicate(true)
	for door: Dictionary in structural_doors: door.destroyed = true
	var global_nav := Nav.new()
	global_nav.build(data,structural_doors)
	# All following queries read this owned immutable geometry; no live
	# simulation Nav or mutable door array enters this function-local scope.
	global_nav.begin_geometry_scope()
	var origin := Vector2(float(source.units[0].x),float(source.units[0].z)) if not source.get("units",[]).is_empty() else Vector2(INF,INF)
	_check(result,global_nav.walkable(origin),str(source.get("id","content"))+": structurally clear staging origin")
	if not global_nav.walkable(origin): return result
	# Every direction uses exactly the same immutable authored baseline.
	# Reuse its graph only within this map; paths returned by Nav are fresh.
	var baseline := Drill.PlanningNavigation.new()
	baseline.build(data,data.get("doors",[]).duplicate(true))
	baseline.begin_geometry_scope()
	for authored: Dictionary in data.get("doors",[]):
		var center := _point(authored)
		var normal := Vector2.DOWN if authored.axis == "x" else Vector2.RIGHT
		var targets: Array = []
		for inward_side: float in [-1.0,1.0]:
			var sample := center + normal * inward_side * 0.65
			var room: Dictionary = Drill._choose_room(data.get("rooms",[]),authored,sample,"")
			if not room.is_empty() and bool(room.get("indoor",true)): targets.append({"side":inward_side,"room":room})
		if targets.is_empty():
			result.passages.append({"door_id":str(authored.id),"class":"outdoor_passage","reason":"Neither canonical portal side enters an authored indoor room; retain the independent physical passage validation."})
			continue
		result.entry_doors += 1
		# At most three exact-method pairs live for this selected door only.
		var navigation_by_method: Dictionary = {}
		for target: Dictionary in targets:
			result.entry_directions += 1
			var label := str(source.get("id","content"))+" "+str(authored.id)+" -> "+str(target.room.id)
			var local: Dictionary = data.duplicate(true)
			# The running planner forecasts only its selected door. Other doors
			# retain authored state/progress/destruction, rather than introducing
			# hypothetical opened leaves into every adjacent room and corridor.
			local.doors = data.get("doors",[]).duplicate(true)
			var origins: Dictionary = {}
			var starts: Dictionary = {}
			var answer: Dictionary = {}
			var failures: Array[String] = []
			var reachable: Dictionary = {}
			var local_reachable: Dictionary = {}
			var outside_anchor := _outside_anchor(baseline,authored,float(target.side))
			var pattern_origins: Dictionary = {}
			var tried: Dictionary = {}
			# Capacity is proved by an actual draft, not by one arbitrary start
			# configuration. Stable mirrored/jamb lanes avoid false failures from
			# cohort bodies or a nearest floor sample in an unreachable pocket.
			# This proves geometric capacity, independently of a particular
			# deployed loadout. Runtime equipment and resource validation still
			# decides whether its operator can execute the selected method.
			for method: String in ["OPEN_DOOR","SHOTGUN_BREACH","BREACH_DOOR"]:
				if not navigation_by_method.has(method): navigation_by_method[method] = {}
				var private_navigation: Dictionary = navigation_by_method[method]
				for pattern: int in APPROACH_PATTERNS:
					if not pattern_origins.has(pattern): pattern_origins[pattern] = _approaches(baseline,global_nav,origin,authored,float(target.side),ids,pattern,reachable,outside_anchor,local_reachable)
					origins = pattern_origins[pattern]
					if origins.size() != 4:
						failures.append(method+":approach")
						continue
					starts = {}
					for id: String in ids: starts[id] = _array(origins[id])
					var signature := method+":"+JSON.stringify(starts)
					if tried.has(signature): continue
					tried[signature] = true
					answer = Drill._calculate_with_baseline(local,str(authored.id),ids,starts,{"method":method,"room_id":str(target.room.id),"operator_id":ids[0]},baseline,private_navigation)
					if bool(answer.get("ok",false)): break
					failures.append(method+":"+str(answer.get("reason_code","")))
					# Entry routes start at the selected stack, so a different
					# reachable cohort can resolve an entry failure. Room and
					# domination failures do not depend on those origins.
					if str(answer.get("reason_code","")) in ["drill_domination","drill_room","drill_door","drill_geometry"]: break
				if bool(answer.get("ok",false)): break
			_check(result,bool(answer.get("ok",false)),label+": room drill " + ",".join(failures))
			if not bool(answer.get("ok",false)): continue
			_check(result,origins.size() == 4,label+": four clear reachable approach positions on the entry side")
			for id: String in ids:
				_check(result,_route(global_nav,origin,global_nav.path(origin,origins[id])),label+": staged position for "+id+" is structurally reachable")
				_check(result,_route(baseline,outside_anchor,baseline.path(outside_anchor,origins[id])),label+": staged position shares the actual outside component "+id)
			_check(result,answer.slots.size() == 4,label+": exact four-person layout")
			_check(result,str(answer.room_id) == str(target.room.id),label+": actual selected room")
			_check(result,float(answer.entry_side)==-float(target.side),label+": actual approach side matches this entry direction")
			for id: String in ids: _check(result,signf((origins[id]-center).dot(normal))==float(answer.entry_side),label+": owned origin is on the recorded approach side")
			var forecast_doors: Array = local.doors.duplicate(true)
			for door: Dictionary in forecast_doors:
				if str(door.id) == str(authored.id):
					door.state = "OPEN"
					door.progress = 1.0
					if str(answer.method) in ["SHOTGUN_BREACH","BREACH_DOOR"]: door.destroyed = true
			var forecast := Nav.new()
			forecast.build(local,forecast_doors)
			forecast.begin_geometry_scope()
			var room_rect := _rect(target.room)
			if answer.has("effective_frame"):
				var effective: Array = answer.effective_frame
				var frame := Rect2(float(effective[0]),float(effective[1]),float(effective[2]),float(effective[3]))
				var proven: Dictionary = Drill._portal_frame(local,authored,room_rect,center,normal*float(target.side),Vector2.RIGHT if authored.axis=="x" else Vector2.DOWN)
				_check(result,not proven.is_empty() and proven.rect==frame,label+": complete physical tangent barrier certifies the effective frame")
				_check(result,room_rect.grow(EPS).encloses(frame),label+": effective frame stays within the authored room")
				room_rect=frame
			var short_room := room_rect.get_area() <= 9.0+EPS or minf(room_rect.size.x,room_rect.size.y) <= 2.5+EPS
			_check(result,bool(answer.short_room) == short_room,label+": physical entry frame SHORT ROOM classification")
			_check(result,int(answer.entry_count) == (2 if short_room else 4),label+": two SHORT entrants or four standard entrants")
			var stacks: Array[Vector2] = []
			for index: int in range(answer.slots.size()):
				var slot: Dictionary = answer.slots[index]
				var stack := _vector(slot.stack)
				var goal := _vector(slot.domination)
				_check(result,str(slot.unit_id) == ids[index] and int(slot.order) == index+1,label+": stable owned slot order")
				_check(result,_route(baseline,origins[ids[index]],slot.stack_route),label+": swept-body stack route "+ids[index])
				_check(result,not Door.funnel_rect(authored).has_point(stack),label+": stack outside the funnel")
				for prior: Vector2 in stacks: _check(result,prior.distance_to(stack) >= 0.7-EPS,label+": stack spacing")
				stacks.append(stack)
				for progress: float in [0.0,0.25,0.5,0.75,1.0]: _check(result,not Door.overlaps_actor(authored,progress,stack,Nav.RADIUS),label+": stack outside leaf sweep")
				_check(result,is_equal_approx(float(slot.stack_height),Spatial.floor_base_at(local.rooms,stack)),label+": actual stack floor")
				_check(result,is_equal_approx(float(slot.floor_height),Spatial.floor_base_at(local.rooms,goal)),label+": actual domination floor")
				if bool(slot.entry):
					_check(result,room_rect.grow(-Nav.RADIUS).has_point(goal),label+": domination lies inside the target room")
					_check(result,_route(forecast,stack,slot.entry_route),label+": swept-body entry route "+ids[index])
					_check(result,_crossed(stack,slot.entry_route,authored),label+": route crosses the specified portal")
					_check(result,_floor_samples(local.rooms,stack,slot.entry_route),label+": actual floor samples along the entry route")
				else:
					result.short_guards += 1
					_check(result,short_room and index >= 2 and not room_rect.has_point(goal),label+": SHORT guard remains outside")
					_check(result,baseline.walkable(goal) and baseline.segment_clear(goal,goal,Nav.RADIUS),label+": guard has physical floor clearance")
			result.entry_methods.append({"door_id":str(authored.id),"room_id":str(target.room.id),"entry_side":float(answer.entry_side),"method":str(answer.method)})
			result.layouts.append({"door_id":str(authored.id),"room_id":str(target.room.id),"method":str(answer.method),"entry_side":answer.entry_side,"short_room":short_room,"entry_count":answer.entry_count,"slots":answer.slots,"approaches":starts})
	return result

static func _outside_anchor(nav: RefCounted, door: Dictionary, inward_side: float) -> Vector2:
	var center := _point(door)
	var normal := Vector2.DOWN if door.axis == "x" else Vector2.RIGHT
	var across := Vector2.RIGHT if door.axis == "x" else Vector2.DOWN
	for depth: float in [0.65,0.4,1.0]:
		for fraction: float in [0.0,-0.2,0.2,-0.35,0.35]:
			var point := center-normal*inward_side*depth+across*Door.width(door)*fraction
			if nav.walkable(point) and nav.segment_clear(point,point,Nav.RADIUS+0.01): return point
	return Vector2(INF,INF)

static func _approaches(nav: RefCounted, global_nav: RefCounted, origin: Vector2, door: Dictionary, inward_side: float, ids: Array[String], pattern: int, reachable: Dictionary, outside_anchor: Vector2, local_reachable: Dictionary) -> Dictionary:
	if not is_finite(outside_anchor.x) or not is_finite(outside_anchor.y): return {}
	var center := _point(door)
	var normal := Vector2.DOWN if door.axis == "x" else Vector2.RIGHT
	var across := Vector2.RIGHT if door.axis == "x" else Vector2.DOWN
	var outside := -normal * inward_side
	var jamb := ceilf((Door.width(door)*0.5+Nav.RADIUS+Door.LEAF_HALF_DEPTH+0.05)*100.0)/100.0
	var result: Dictionary = {}
	var used: Array[Vector2] = []
	for index: int in range(ids.size()):
		var lateral := (-1.0 if index%2 == 0 else 1.0) * (0.35 if pattern < 2 else jamb)
		var depth := (1.15 if pattern < 2 else 0.45) + 0.7*floori(index/2.0)
		if pattern%2 == 1: lateral = -lateral
		if pattern >= 4:
			lateral = jamb * (-1.0 if pattern == 4 else 1.0)
			depth = 0.65 + 0.7*index
		var desired := center + outside * depth + across * lateral
		var candidates: Array[Vector2] = []
		for depth_index: int in range(16):
			for lateral_index: int in range(-12,13):
				candidates.append(center+outside*(0.65+0.25*depth_index)+across*(0.25*lateral_index))
		candidates.sort_custom(func(a: Vector2,b: Vector2) -> bool:
			var ca := a.distance_squared_to(desired)
			var cb := b.distance_squared_to(desired)
			if not is_equal_approx(ca,cb): return ca < cb
			if a.x != b.x: return a.x < b.x
			return a.y < b.y)
		for candidate: Vector2 in candidates:
			if not nav.walkable(candidate) or not nav.segment_clear(candidate,candidate,Nav.RADIUS+0.01): continue
			if Door.funnel_rect(door).has_point(candidate): continue
			var separated := true
			for prior: Vector2 in used:
				if prior.distance_to(candidate) < 0.7-EPS: separated = false; break
			if not separated: continue
			# A candidate behind another authored CLOSED doorway already fails
			# the same required local-body condition. Prove that first, then
			# retain the complete global structural proof for every survivor.
			if not local_reachable.has(candidate): local_reachable[candidate] = _route(nav,outside_anchor,nav.path(outside_anchor,candidate))
			if not bool(local_reachable[candidate]): continue
			if not reachable.has(candidate): reachable[candidate] = _route(global_nav,origin,global_nav.path(origin,candidate))
			if not bool(reachable[candidate]): continue
			result[ids[index]] = candidate
			used.append(candidate)
			break
	return result

static func _check(result: Dictionary, condition: bool, message: String) -> void:
	result.checks += 1
	if not condition: result.errors.append(message)

static func _route(nav: RefCounted, origin: Vector2, route: Array) -> bool:
	if route.is_empty(): return false
	var previous := origin
	for raw: Array in route:
		var current := _vector(raw)
		if not nav.walkable(current) or not nav.segment_clear(previous,current,Nav.RADIUS): return false
		previous = current
	return true

static func _floor_samples(rooms: Array, origin: Vector2, route: Array) -> bool:
	# Existing navigation permits authored elevation transitions. Verify the
	# physical floor data, without inventing a new same-height movement rule.
	var previous := origin
	for raw: Array in route:
		var current := _vector(raw)
		var count := maxi(1,ceili(previous.distance_to(current)/Nav.CELL))
		for index: int in range(count+1):
			if not is_finite(Spatial.floor_base_at(rooms,previous.lerp(current,float(index)/count))): return false
		previous = current
	return true

static func _crossed(origin: Vector2, route: Array, door: Dictionary) -> bool:
	var center := _point(door)
	var normal := Vector2.DOWN if door.axis == "x" else Vector2.RIGHT
	var across := Vector2.RIGHT if door.axis == "x" else Vector2.DOWN
	var previous := origin
	for raw: Array in route:
		var current := _vector(raw)
		var a := (previous-center).dot(normal)
		var b := (current-center).dot(normal)
		if a*b <= 0.0 and absf(b-a) > EPS:
			var crossing := previous.lerp(current,-a/(b-a))
			if absf((crossing-center).dot(across)) <= Door.width(door)*0.5+EPS: return true
		previous = current
	return false

static func _point(value: Dictionary) -> Vector2: return Vector2(float(value.x),float(value.z))
static func _vector(value: Array) -> Vector2: return Vector2(float(value[0]),float(value[1]))
static func _array(value: Vector2) -> Array: return [value.x,value.y]
static func _rect(value: Dictionary) -> Rect2: return Rect2(float(value.x)-float(value.w)*0.5,float(value.z)-float(value.d)*0.5,float(value.w),float(value.d))
