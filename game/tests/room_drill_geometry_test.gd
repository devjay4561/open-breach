extends SceneTree
const Drill = preload("res://scripts/room_drill.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const STEP := 1.0 / 30.0
const IDS: Array[String] = ["alpha","bravo","charlie","delta"]
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

func fixture(width: float = 5.0, depth: float = 5.0, axis: String = "x") -> Dictionary:
	var door_z: float = 8.0+depth*0.5
	var side_width: float = (width-1.6)*0.5
	var data: Dictionary = {
		"schema_version":3,"id":"ROOM_DRILL_GEOMETRY","revision":1,"seed":0,"bounds":[20.0,20.0],"focus":[8.0,8.0],
		"rooms":[{"id":"inside","x":8.0,"z":8.0,"w":width,"d":depth,"indoor":true},{"id":"staging","x":8.0,"z":door_z+2.5,"w":5.0,"d":5.0,"indoor":true}],
		"walls":[
			{"id":"north","x":8.0,"z":8.0-depth*0.5,"w":width,"d":0.20},
			{"id":"west","x":8.0-width*0.5,"z":8.0,"w":0.20,"d":depth},
			{"id":"east","x":8.0+width*0.5,"z":8.0,"w":0.20,"d":depth},
			{"id":"jamb_west","x":8.0-(1.6+side_width)*0.5,"z":door_z,"w":side_width,"d":0.20},
			{"id":"jamb_east","x":8.0+(1.6+side_width)*0.5,"z":door_z,"w":side_width,"d":0.20},
			{"id":"stage_west","x":5.5,"z":door_z+2.5,"w":0.20,"d":5.0},
			{"id":"stage_east","x":10.5,"z":door_z+2.5,"w":0.20,"d":5.0},
			{"id":"south","x":8.0,"z":door_z+5.0,"w":5.0,"d":0.20}],
		"doors":[{"id":"entry","x":8.0,"z":door_z,"w":1.6,"d":0.20,"axis":"x","hinge_side":-1.0,"swing_sign":-1.0,"state":"CLOSED","progress":0.0}],
		"props":[],"units":[],"enemies":[],"civilians":[],"objectives":["Geometry fixture"],"win":[{"type":"neutralize_all"}],"fail":[]}
	if axis == "z":
		for group: String in ["rooms","walls","doors"]:
			for object: Dictionary in data[group]:
				var x: float = float(object.x)
				var w: float = float(object.w)
				object.x = object.z
				object.z = x
				object.w = object.d
				object.d = w
		data.doors[0].axis = "z"
	return data

func approaches(data: Dictionary, count: int = 4, side: float = 1.0) -> Dictionary:
	var door: Dictionary = data.doors[0]
	var result: Dictionary = {}
	for index: int in range(count):
		var distance: float = 1.4+float(index)*0.7
		result[IDS[index]] = [float(door.x),float(door.z)+side*distance] if door.axis == "x" else [float(door.x)+side*distance,float(door.z)]
	return result

func calculate(data: Dictionary, count: int = 4, side: float = 1.0, options: Dictionary = {}) -> Dictionary:
	var configured: Dictionary = {"method":"OPEN_DOOR"}
	configured.merge(options,true)
	return Drill.calculate(data,"entry",IDS.slice(0,count),approaches(data,count,side),configured)

func _room(data: Dictionary, id: String) -> Dictionary:
	for room: Dictionary in data.rooms:
		if room.id == id: return room
	return {}

func _contains(room: Dictionary, location: Vector2, margin: float = 0.0) -> bool:
	return absf(location.x-float(room.x)) <= float(room.w)*0.5-margin+0.0001 and absf(location.y-float(room.z)) <= float(room.d)*0.5-margin+0.0001

func _json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING: return true
		TYPE_FLOAT: return is_finite(float(value))
		TYPE_ARRAY:
			for member: Variant in value:
				if not _json_safe(member): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _json_safe(value[key]): return false
			return true
	return false

func _portal_crossed(origin: Vector2, route: Array, door: Dictionary) -> bool:
	var center := Vector2(float(door.x),float(door.z))
	var normal := Vector2.DOWN if door.axis == "x" else Vector2.RIGHT
	var across := Vector2.RIGHT if door.axis == "x" else Vector2.DOWN
	var previous: Vector2 = origin
	for raw: Array in route:
		var endpoint: Vector2 = point(raw)
		var before: float = (previous-center).dot(normal)
		var after: float = (endpoint-center).dot(normal)
		if before*after <= 0.0 and absf(after-before) > 0.000001:
			var intersection: Vector2 = previous.lerp(endpoint,-before/(after-before))
			if absf((intersection-center).dot(across)) <= Door.width(door)*0.5+0.0001: return true
		previous = endpoint
	return false

func _planned_nav(data: Dictionary, method: String, open_entry: bool) -> RefCounted:
	var states: Array = data.doors.duplicate(true)
	for door: Dictionary in states:
		if door.id != "entry": continue
		if open_entry:
			door.state = "OPEN"
			door.progress = 1.0
			if method in ["BREACH_DOOR","SHOTGUN_BREACH"]: door.destroyed = true
	var nav := Navigation.new()
	nav.build(data,states)
	return nav

func _route_legal(nav: RefCounted, origin: Vector2, route: Array) -> bool:
	if route.is_empty(): return false
	var previous: Vector2 = origin
	for raw: Array in route:
		var endpoint: Vector2 = point(raw)
		if not nav.walkable(endpoint) or not nav.segment_clear(previous,endpoint,Navigation.RADIUS): return false
		previous = endpoint
	return true

func assert_layout(data: Dictionary, answer: Dictionary, count: int, side: float, label: String) -> void:
	check(bool(answer.get("ok",false)),label+" produces a complete layout: "+str(answer.get("reason_code","")))
	if not bool(answer.get("ok",false)): return
	check(_json_safe(answer),label+" result uses only finite JSON data")
	check(answer.get("door_id","") == "entry" and not _room(data,str(answer.get("room_id",""))).is_empty(),label+" references authored geometry")
	var slots: Array = answer.get("slots",[])
	check(slots.size() == count,label+" preserves the requested team size")
	if slots.size() != count: return
	var room: Dictionary = _room(data,str(answer.room_id))
	var door: Dictionary = data.doors[0]
	var funnel: Rect2 = Door.funnel_rect(door)
	var nav: RefCounted = _planned_nav(data,str(answer.method),true)
	var stack_nav: RefCounted = _planned_nav(data,str(answer.method),false)
	var starts: Dictionary = approaches(data,count,side)
	var unique: Array = []
	for index: int in range(slots.size()):
		var slot: Dictionary = slots[index]
		check(str(slot.get("unit_id","")) == IDS[index] and int(slot.get("order",0)) == index+1,label+" stable operator order "+str(index+1))
		var stack: Vector2 = point(slot.stack)
		var goal: Vector2 = point(slot.domination)
		check(not funnel.has_point(stack),label+" stack remains outside the doorway funnel "+str(index+1))
		check(stack_nav.walkable(stack) and _route_legal(stack_nav,point(starts[IDS[index]]),slot.stack_route),label+" stack and approach are swept-body walkable "+str(index+1))
		for prior: Vector2 in unique: check(prior.distance_to(stack) >= Navigation.RADIUS*2.0-0.0001,label+" stack separates operator bodies")
		unique.append(stack)
		for progress: float in [0.0,0.25,0.5,0.75,1.0]:
			check(not Door.overlaps_actor(door,progress,stack,Navigation.RADIUS),label+" stack avoids the physical door sweep "+str(index+1))
		check(is_equal_approx(float(slot.stack_height),Spatial.floor_base_at(data.rooms,stack)),label+" stack uses actual floor height")
		check(is_equal_approx(float(slot.floor_height),Spatial.floor_base_at(data.rooms,goal)),label+" domination uses actual floor height")
		if bool(slot.entry):
			check(_contains(room,goal,Navigation.RADIUS),label+" domination fits inside the selected room "+str(index+1))
			check(nav.walkable(goal) and _route_legal(nav,stack,slot.entry_route),label+" entry and domination are swept-body walkable "+str(index+1))
			check(_portal_crossed(stack,slot.entry_route,door),label+" entry crosses the specified portal "+str(index+1))
		else:
			check(not _contains(room,goal),label+" short-room guard stays outside")
			check(nav.walkable(goal),label+" guard position is legal floor")
		var entry: Dictionary = slot.sector_entry
		var arrival: Dictionary = slot.sector_domination
		check(is_finite(float(entry.start)) and is_finite(float(entry.end)) and is_finite(float(entry.center)) and float(entry.radius) > 0.0,label+" entry sector is finite")
		check(float(arrival.radius) >= float(entry.radius),label+" arrival sector releases the entry radius limit")
		check(absf(angle_difference(float(arrival.center),float(arrival.start))) >= absf(angle_difference(float(entry.center),float(entry.start))),label+" arrival sector expands")
		if index > 0:
			var prior: Vector2 = point(slots[index-1].stack)
			check(float(entry.radius) <= maxf(0.05,stack.distance_to(prior)-Navigation.RADIUS-0.05)+0.0001,label+" entry fan ends before the preceding body")

func run() -> void:
	_standard_and_determinism()
	_orientations_and_leaf_states()
	_small_teams_and_short_rooms()
	_narrow_portal()
	_furniture_and_atomic_failure()
	_methods_and_go_long()
	_selected_portal()
	_height_and_large_coordinates()
	_water_floor()
	_sector_contracts()
	print("BREACH_ROOM_DRILL_GEOMETRY_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _standard_and_determinism() -> void:
	var reference: String = ""
	for seed_value: int in range(30):
		var data: Dictionary = fixture()
		data.seed = seed_value
		data.time = float(seed_value)*STEP
		data.tick = seed_value
		var before: String = JSON.stringify(data)
		var answer: Dictionary = calculate(data)
		assert_layout(data,answer,4,1.0,"Standard seed "+str(seed_value))
		check(JSON.stringify(data) == before,"Calculation never changes source geometry seed "+str(seed_value))
		check(JSON.stringify(calculate(data)) == JSON.stringify(answer),"Repeated pure input has identical output seed "+str(seed_value))
		seed(seed_value)
		var untouched_rng: int = randi()
		seed(seed_value)
		calculate(data)
		check(randi() == untouched_rng,"Static drill calculation consumes no global RNG seed "+str(seed_value))
		if seed_value == 0: reference = JSON.stringify(answer)
		check(JSON.stringify(answer) == reference,"Seed, tick and simulation time do not change geometry seed "+str(seed_value))
		if not bool(answer.get("ok",false)): continue
		check(not bool(answer.short_room),"A 5x5m room is a full-team room")
		for index: int in [0,1]:
			var goal: Vector2 = point(answer.slots[index].domination)
			var side_margin: float = 2.5-absf(goal.x-8.0)
			check(side_margin >= 0.8-0.0001 and side_margin <= 1.0+0.0001,"Standard near-corner domination keeps .8–1m wall margin")
		check((float(answer.slots[0].domination[0])-8.0)*(float(answer.slots[1].domination[0])-8.0) < 0.0,"First two operators split opposite near corners")
		for index: int in [2,3]: check(float(answer.slots[index].domination[1]) < 8.0,"Rear two operators reach the far half of the room")
		data.enemies = [{"id":"hidden","x":8.0,"z":8.0,"hp":100,"status":"ALERT","door_ready":true}]
		data.civilians = [{"id":"unknown","x":9.0,"z":9.0,"secured":false}]
		data.units = [{"id":"alpha","x":1.0,"z":1.0,"ammo":0,"hp":0,"commands":[{"type":"WAIT","remaining":99}]}]
		data["_live_doors"] = [{"id":"entry","state":"OPEN","progress":1.0,"owner_id":"hidden"}]
		data["_door_observations"] = {"entry":{"state":"OPEN","progress":1.0}}
		data.rooms[0]["room_state"] = "CLEARED"
		check(JSON.stringify(calculate(data)) == reference,"Hidden actors and authoritative live unit state do not influence static preview")

func _orientations_and_leaf_states() -> void:
	for axis: String in ["x","z"]:
		for hinge: float in [-1.0,1.0]:
			for swing: float in [-1.0,1.0]:
				for side: float in [-1.0,1.0]:
					var data: Dictionary = fixture(5.0,5.0,axis)
					data.doors[0].hinge_side = hinge
					data.doors[0].swing_sign = swing
					var label: String = "%s hinge%s swing%s approach%s" % [axis,hinge,swing,side]
					var answer: Dictionary = calculate(data,4,side)
					assert_layout(data,answer,4,side,label)
					if bool(answer.get("ok",false)): check(answer.room_id == ("inside" if side > 0.0 else "staging"),label+" chooses the opposite room")
					for state: String in ["OPEN","AJAR","DESTROYED"]:
						var changed: Dictionary = data.duplicate(true)
						changed.doors[0].state = state
						changed.doors[0].progress = 0.52 if state == "AJAR" else 1.0
						changed.doors[0].destroyed = state == "DESTROYED"
						var before: String = JSON.stringify(changed)
						var preview: Dictionary = calculate(changed,4,side)
						check(JSON.stringify(changed) == before,label+" preview does not alter live "+state+" leaf")
						check(bool(preview.get("ok",false)),label+" supports authored "+state+" leaves")

func _small_teams_and_short_rooms() -> void:
	for count: int in [2,3,4]:
		var data: Dictionary = fixture()
		assert_layout(data,calculate(data,count),count,1.0,"Team size "+str(count))
	for size: Vector2 in [Vector2(3.0,3.0),Vector2(2.5,5.0),Vector2(5.0,2.5)]:
		var data: Dictionary = fixture(size.x,size.y)
		var answer: Dictionary = calculate(data)
		assert_layout(data,answer,4,1.0,"Short-room boundary "+str(size))
		if not bool(answer.get("ok",false)): continue
		check(bool(answer.short_room),"Area≤9m² or minimum side≤2.5m selects SHORT ROOM")
		check(bool(answer.slots[0].entry) and bool(answer.slots[1].entry) and not bool(answer.slots[2].entry) and not bool(answer.slots[3].entry),"SHORT ROOM enters exactly two and keeps two guards")
	var larger: Dictionary = fixture(3.01,3.01)
	var answer: Dictionary = calculate(larger)
	check(bool(answer.get("ok",false)) and not bool(answer.get("short_room",true)),"A room beyond both short-room boundaries allows all four")
	var duplicate: Dictionary = fixture()
	var rejected: Dictionary = Drill.calculate(duplicate,"entry",["alpha","alpha"],approaches(duplicate),{"method":"OPEN_DOOR"})
	check(not bool(rejected.get("ok",false)) and rejected.get("slots",[]).is_empty(),"Duplicate operators fail atomically")

func _furniture_and_atomic_failure() -> void:
	var data: Dictionary = fixture()
	var ordinary: Dictionary = calculate(data)
	if not bool(ordinary.get("ok",false)): check(false,"Furniture fixture needs a valid standard layout"); return
	var blocked: Vector2 = point(ordinary.slots[0].domination)
	data.props = [{"id":"corner_cabinet","type":"cabinet","x":blocked.x,"z":blocked.y,"w":1.3,"d":1.3,"cover":"full","solid":true}]
	var answer: Dictionary = calculate(data)
	assert_layout(data,answer,4,1.0,"Blocked preferred corner")
	if bool(answer.get("ok",false)):
		check((float(answer.slots[0].domination[0])-8.0)*(blocked.x-8.0) < 0.0,"First operator selects the less obstructed opposite corner")
	var sealed: Dictionary = fixture()
	sealed.props = [{"id":"sealed_floor","type":"cabinet","x":8.0,"z":8.0,"w":4.8,"d":4.8,"cover":"full","solid":true}]
	var before: String = JSON.stringify(sealed)
	var rejected: Dictionary = calculate(sealed)
	check(not bool(rejected.get("ok",false)) and rejected.get("slots",[]).is_empty(),"A room without viable domination points has no partial slots")
	check(JSON.stringify(sealed) == before,"Impossible geometry does not mutate the authored map")
	check(not str(rejected.get("reason_code","")).is_empty() and not str(rejected.get("message_key","")).is_empty(),"Atomic geometry failure exposes a stable translated reason")

func _narrow_portal() -> void:
	var data: Dictionary = fixture()
	data.doors[0].w = 0.9
	for wall: Dictionary in data.walls:
		if not wall.id in ["jamb_west","jamb_east"]: continue
		wall.w = (5.0-0.9)*0.5
		wall.x = 8.0+(-1.0 if wall.id == "jamb_west" else 1.0)*(0.9+float(wall.w))*0.5
	assert_layout(data,calculate(data),4,1.0,"Real-width 0.90m entry")

func _selected_portal() -> void:
	var data: Dictionary = fixture()
	data.walls = data.walls.filter(func(wall: Dictionary) -> bool: return wall.id != "jamb_west")
	data.walls.append({"id":"alt_west","x":5.625,"z":10.5,"w":0.25,"d":0.20})
	data.walls.append({"id":"alt_east","x":6.925,"z":10.5,"w":0.55,"d":0.20})
	data.doors.append({"id":"shortcut","x":6.2,"z":10.5,"w":0.9,"d":0.20,"axis":"x","state":"OPEN","destroyed":true,"progress":1.0})
	var answer: Dictionary = calculate(data)
	assert_layout(data,answer,4,1.0,"Two-door room")
	if not bool(answer.get("ok",false)): return
	var nav: RefCounted = _planned_nav(data,"OPEN_DOOR",true)
	for slot: Dictionary in answer.slots:
		if not bool(slot.entry): continue
		check(not _portal_crossed(point(slot.stack),slot.entry_route,data.doors[1]),"Selected entry never uses the open shortcut doorway")
		# A macro executes primitive MOVE targets, so fallback metadata must
		# reconstruct the selected portal when ordinary navigation runs again.
		var orders: Array = slot.get("entry_waypoints",[]).duplicate(true)
		orders.append(slot.domination)
		var origin: Vector2 = point(slot.stack)
		var reconstructed: Array = []
		for destination: Array in orders:
			var route: Array = nav.path(origin,point(destination))
			check(_route_legal(nav,origin,route),"Expanded portal MOVE has a legal swept-body route")
			check(not _portal_crossed(origin,route,data.doors[1]),"Expanded portal MOVE cannot reselect the shortcut door")
			reconstructed.append_array(route)
			origin = point(destination)
		check(_portal_crossed(point(slot.stack),reconstructed,data.doors[0]),"Primitive MOVE expansion preserves the selected portal")

func _methods_and_go_long() -> void:
	for method: String in ["OPEN_DOOR","KICK_DOOR","OPEN_AND_FLASH","BREACH_DOOR","SHOTGUN_BREACH"]:
		var data: Dictionary = fixture()
		var before: String = JSON.stringify(data)
		var answer: Dictionary = calculate(data,4,1.0,{"method":method})
		assert_layout(data,answer,4,1.0,"Method "+method)
		check(JSON.stringify(data) == before,"Forecasting "+method+" never changes live leaf state")
		if method != "BREACH_DOOR" or not bool(answer.get("ok",false)): continue
		var nav: RefCounted = _planned_nav(data,method,false)
		for slot: Dictionary in answer.slots:
			var safe: Vector2 = point(slot.safe_retreat)
			check(safe.distance_to(point([data.doors[0].x,data.doors[0].z])) >= 2.0,"Charge retreat puts every operator outside the safety radius")
			check(_route_legal(nav,point(slot.stack),slot.safe_route),"Charge retreat uses continuous legal floor movement")
	var data: Dictionary = fixture()
	var answer: Dictionary = calculate(data,4,1.0,{"go_long":true})
	check(bool(answer.get("ok",false)) and answer.get("go_long",[]).size() == 2,"GO LONG adds the two leading operators' deeper goals")
	if not bool(answer.get("ok",false)): return
	var nav: RefCounted = _planned_nav(data,"OPEN_DOOR",true)
	for index: int in range(answer.go_long.size()):
		var goal: Dictionary = answer.go_long[index]
		var origin: Vector2 = point(answer.slots[index].domination)
		var target: Vector2 = point(goal.target)
		check(goal.unit_id == IDS[index],"GO LONG keeps the entry order")
		check(target.y < origin.y and nav.walkable(target),"GO LONG advances deeper into the selected room")
		check(_route_legal(nav,origin,goal.route),"GO LONG keeps the entire deeper route body-clear")
		check(is_equal_approx(float(goal.floor_height),Spatial.floor_base_at(data.rooms,target)),"GO LONG preserves the floor height")

func _height_and_large_coordinates() -> void:
	var data: Dictionary = fixture()
	data.rooms.insert(0,{"id":"apron","x":10.0,"z":10.0,"w":20.0,"d":20.0,"indoor":false})
	data.rooms[1].base_height = 2.022
	data.rooms[2].indoor = false
	data.doors[0].base_height = 2.022
	var answer: Dictionary = calculate(data)
	assert_layout(data,answer,4,1.0,"Elevated cabin over exterior apron")
	if bool(answer.get("ok",false)):
		check(answer.room_id == "inside","An overlapping large exterior region never hides the actual cabin")
		for slot: Dictionary in answer.slots: check(is_equal_approx(float(slot.floor_height),2.022),"Cabin domination retains measured elevated floor")
	var translated: Dictionary = fixture()
	translated.bounds = [512.0,512.0]
	for group: String in ["rooms","walls","doors"]:
		for object: Dictionary in translated[group]:
			object.x = float(object.x)+472.0
			object.z = float(object.z)+472.0
	var far: Dictionary = calculate(translated)
	assert_layout(translated,far,4,1.0,"512m map near [480,480]")
	var near: Dictionary = calculate(fixture())
	if bool(far.get("ok",false)) and bool(near.get("ok",false)):
		for index: int in range(4):
			check((point(far.slots[index].stack)-Vector2(472,472)).distance_to(point(near.slots[index].stack)) < 0.001,"World translation preserves stack metre spacing: near=%s far_local=%s" % [point(near.slots[index].stack),point(far.slots[index].stack)-Vector2(472,472)])
			check((point(far.slots[index].domination)-Vector2(472,472)).distance_to(point(near.slots[index].domination)) < 0.001,"World translation preserves domination metre margins")

func _water_floor() -> void:
	var data: Dictionary = fixture()
	data.environment = {"water":true}
	data.walkable_areas = [{"id":"inside_deck","x":8.0,"z":8.0,"w":5.0,"d":5.0},{"id":"stage_deck","x":8.0,"z":13.0,"w":5.0,"d":5.0}]
	var answer: Dictionary = calculate(data)
	assert_layout(data,answer,4,1.0,"Joining deck floor union")
	data.walkable_areas = [{"id":"inside_deck","x":8.0,"z":8.0,"w":5.0,"d":5.0},{"id":"tiny_stage","x":8.0,"z":12.0,"w":0.5,"d":0.5}]
	var rejected: Dictionary = calculate(data)
	check(not bool(rejected.get("ok",false)) and rejected.get("slots",[]).is_empty(),"A water void cannot supply stack positions or connecting routes")

func _sector_contracts() -> void:
	for axis: String in ["x","z"]:
		for side: float in [-1.0,1.0]:
			var answer: Dictionary = calculate(fixture(5,5,axis),4,side)
			if not bool(answer.get("ok",false)): check(false,"Sector fixture requires valid geometry"); continue
			for slot: Dictionary in answer.slots:
				var sector: Dictionary = slot.sector_domination
				check(absf(angle_difference(float(sector.center),float(sector.start))) <= PI and absf(angle_difference(float(sector.center),float(sector.end))) <= PI,"Sector endpoints use wrapped finite world angles")
				check(is_equal_approx(absf(angle_difference(float(sector.center),float(sector.start))),absf(angle_difference(float(sector.center),float(sector.end)))),"Sector remains symmetric across the ±PI seam")
			var first: Dictionary = answer.slots[0].sector_domination
			var second: Dictionary = answer.slots[1].sector_domination
			var half_first: float = absf(angle_difference(float(first.center),float(first.start)))
			var half_second: float = absf(angle_difference(float(second.center),float(second.start)))
			check(absf(angle_difference(float(first.center),float(second.center))) <= half_first+half_second+0.0001,"Arrival sectors overlap for mutual coverage")
