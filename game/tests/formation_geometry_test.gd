extends SceneTree
## Geometry and drafting use fixed inputs. Actual combat and primitive
## execution are tested separately by formation_combat_test.
const Formation = preload("res://scripts/formation_drill.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const BrowserFixture = preload("res://tests/formation_browser_preflight_test.gd")
const STEP := 1.0 / 30.0
const IDS: Array[String] = ["alpha","bravo","charlie","delta"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

func fixture(width: float = 3.2) -> Dictionary:
	return {"schema_version":4,"bounds":[20.0,24.0],"rooms":[{"id":"corridor","x":8.0,"z":12.0,"w":width,"d":20.0}],
		"walls":[{"id":"west","x":8.0-width*0.5-0.1,"z":12.0,"w":0.2,"d":20.0},
			{"id":"east","x":8.0+width*0.5+0.1,"z":12.0,"w":0.2,"d":20.0},
			{"id":"north","x":8.0,"z":2.0,"w":width,"d":0.2},
			{"id":"south","x":8.0,"z":22.0,"w":width,"d":0.2}],"props":[],"doors":[]}

func approaches(count: int = 4) -> Dictionary:
	var result: Dictionary = {}
	for index: int in range(count): result[IDS[index]] = [8.0,18.0+float(index)*0.7]
	return result

func json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING: return true
		TYPE_FLOAT: return is_finite(float(value))
		TYPE_ARRAY:
			for item: Variant in value:
				if not json_safe(item): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not json_safe(value[key]): return false
				if not json_safe(value[key]): return false
			return true
	return false

func direction(origin: Array, target: Array) -> Vector2:
	return (point(target)-point(origin)).normalized()

func assert_layout(data: Dictionary, ids: Array, starts: Dictionary, target: Array, result: Dictionary, label: String) -> void:
	check(bool(result.get("ok",false)),label+" complete layout: "+str(result.get("reason_code","")))
	if not bool(result.get("ok",false)): return
	check(json_safe(result),label+" finite JSON result")
	check(result.order_ids==ids and result.source_unit_id==ids[-1],label+" stable tactical order and rear source")
	check(result.slots.size()==ids.size() and point(result.target).distance_to(point(target))<0.0001,label+" exact participant count and requested target at simulation coordinate precision")
	var nav := Navigation.new()
	nav.build(data,data.get("doors",[]).duplicate(true))
	for index: int in range(result.slots.size()):
		var slot: Dictionary = result.slots[index]
		check(slot.unit_id==ids[index] and slot.index==index+1,label+" one-based rank "+str(index))
		var stack := point(slot.stack)
		var goal := point(slot.target)
		check(nav.walkable(stack) and nav.walkable(goal),label+" legal stack and goal "+str(index))
		for other: int in range(index):
			check(stack.distance_to(point(result.slots[other].stack))>=0.7-0.0001,label+" stack body separation")
			check(goal.distance_to(point(result.slots[other].target))>=0.7-0.0001,label+" goal body separation")
		check(is_equal_approx(float(slot.floor_height),Spatial.floor_base_at(data.rooms,goal)),label+" authored floor")
		check(slot.move_route.size()==slot.move_face_targets.size(),label+" movement faces align with route")
		var face_origins := [starts[slot.unit_id],slot.stack,slot.stack,slot.target]
		var face_targets := [slot.initial_face_target,slot.stack_face_target,slot.ready_face_target,slot.face_target]
		var move_origin: Array = slot.stack
		for route_index: int in range(slot.move_route.size()):
			face_origins.append(move_origin)
			face_targets.append(slot.move_face_targets[route_index])
			move_origin = slot.move_route[route_index]
		for face_index: int in range(face_targets.size()):
			var face := point(face_targets[face_index])
			check(face.x>=0.0 and face.y>=0.0 and face.x<=float(data.bounds[0]) and face.y<=float(data.bounds[1]) and face.distance_to(point(face_origins[face_index]))>0.0,label+" FACE ray remains nonzero and inside authored bounds")
		var previous := point(starts[slot.unit_id])
		for raw: Array in slot.stack_route:
			var next := point(raw)
			check(nav.walkable(next) and nav.segment_clear(previous,next,Navigation.RADIUS),label+" complete stack swept segment")
			previous = next
		check(previous.distance_to(stack)<0.0001,label+" stack route exact endpoint")
		for raw: Array in slot.move_route:
			var next := point(raw)
			check(nav.walkable(next) and nav.segment_clear(previous,next,Navigation.RADIUS),label+" complete movement swept segment")
			previous = next
		check(previous.distance_to(goal)<0.0001,label+" move route exact endpoint")
		check(4+slot.stack_route.size()+2*slot.move_route.size()<=32,label+" primitive capacity before existing prefix")
		var sector: Dictionary = slot.sector
		check(point(sector.origin).distance_to(goal)<0.0001,label+" final sector origin")
		check(absf(angle_difference(float(sector.center),direction(slot.target,slot.face_target).angle()))<0.0001,label+" heading uses Vector2.angle")
		check(absf(fposmod(float(sector.end)-float(sector.start),TAU)-deg_to_rad(110.0))<0.0001,label+" 110 degree final sector")

func route_length(origin: Vector2, route: Array) -> float:
	var result := 0.0
	var previous := origin
	for raw: Array in route:
		var next := point(raw)
		result += previous.distance_to(next)
		previous = next
	return result

func _basic_contracts() -> void:
	for width: float in [1.6,1.799,1.8,3.2]:
		for count: int in range(2,5):
			var data := fixture(width)
			var ids: Array = IDS.slice(0,count)
			var starts := approaches(count)
			var target := [8.0,6.0]
			var before := JSON.stringify({"data":data,"ids":ids,"starts":starts,"target":target})
			var result := Formation.calculate(data,ids,starts,target,{})
			assert_layout(data,ids,starts,target,result,"width%.3f team%d"%[width,count])
			check(JSON.stringify({"data":data,"ids":ids,"starts":starts,"target":target})==before,"Draft does not mutate authored input")
			if not bool(result.get("ok",false)): continue
			check(result.kind==("SERPENTINE" if width<1.8 else "ROLLING_T"),"AUTO uses physical wall width before body-radius subtraction")
			check(absf(float(result.corridor_width)-width)<0.00001,"Reports authored physical wall width")
			check(bool(result.hand_ready_compatible),"Straight staging supports default mutual hand FOV")
			for index: int in range(count):
				var slot: Dictionary = result.slots[index]
				check(slot.stance=="","Corridor leaves the operator's existing stance unchanged")
				check(direction(starts[slot.unit_id],slot.initial_face_target).dot(direction(slot.stack,slot.stack_face_target))>0.99999,"Initial face is anchored at each owned approach")
			var source: Dictionary = result.slots[-1]
			for index: int in range(count-1):
				var receiver: Dictionary = result.slots[index]
				check(direction(receiver.stack,receiver.ready_face_target).dot(direction(receiver.stack,source.stack))>0.99999,"Hand receiver faces actual rear source")
				check(absf(angle_difference(direction(source.stack,source.ready_face_target).angle(),direction(source.stack,receiver.stack).angle()))<=deg_to_rad(55.0)+0.0001,"Source bisector covers receiver")
	var data := fixture(3.2)
	var manual := Formation.calculate(data,IDS,approaches(),[8.0,6.0],{"kind":"SERPENTINE","signal":"B","delay_ticks":7})
	check(bool(manual.get("ok",false)) and manual.kind=="SERPENTINE" and manual.recommended_kind=="ROLLING_T" and manual.signal=="B" and manual.delay_ticks==7,"Manual draft remains editable independently of recommendation")
	check(not bool(Formation.calculate(fixture(1.0),IDS,approaches(),[8.0,6.0],{"kind":"ROLLING_T"}).get("ok",false)),"Manual rolling row cannot override insufficient physical clearance")

func _repeat_contracts() -> void:
	var random := RandomNumberGenerator.new()
	for seed_value: int in range(30):
		var data := fixture(3.2)
		data["seed"] = seed_value
		data["enemies"] = [{"id":"hidden","x":float(seed_value),"z":4.0,"hp":70.0}]
		data["civilians"] = [{"id":"unobserved","x":1.0,"z":float(seed_value)}]
		data["time"] = float(seed_value)*STEP
		data["room_states"] = {"corridor":{"state":"CONTACT"}}
		data["_live_doors"] = [{"state":"OPEN","progress":1.0}]
		var before := JSON.stringify(data)
		random.seed = seed_value
		var rng_state := random.state
		var result := Formation.calculate(data,IDS,approaches(),[8.0,6.0],{})
		var repeated := Formation.calculate(data,IDS,approaches(),[8.0,6.0],{})
		var clean := Formation.calculate(fixture(3.2),IDS,approaches(),[8.0,6.0],{})
		assert_layout(data,IDS,approaches(),[8.0,6.0],result,"seed%d"%seed_value)
		check(JSON.stringify(result)==JSON.stringify(repeated) and result==clean,"Same seed repeats and hidden NPC/time/state do not affect draft")
		check(JSON.stringify(data)==before and random.state==rng_state,"Pure calculation preserves input and independent RNG")

func _invalid_contracts() -> void:
	var data := fixture()
	var cases: Array = [
		[data,[],approaches(),[8.0,6.0],{}],
		[data,["alpha","alpha"],approaches(),[8.0,6.0],{}],
		[data,IDS,{"alpha":[NAN,18.0]},[8.0,6.0],{}],
		[data,IDS,approaches(),[INF,6.0],{}],
		[data,IDS,approaches(),[8.0,6.0],{"kind":"INVALID"}],
		[data,IDS,approaches(),[8.0,6.0],{"delay_ticks":0.5}],
		[data,IDS,approaches(),[8.0,6.0],{"delay_ticks":true}],
		[data,IDS,approaches(),[8.0,6.0],{"signal":"D"}],
		[data,IDS.slice(0,3),approaches(3),[8.0,6.0],{"kind":"T_JUNCTION"}],
		[data,IDS,approaches(),[8.0,6.0],{"kind":"T_JUNCTION"}],
		[{"bounds":[20.0,24.0],"walls":"bad"},IDS,approaches(),[8.0,6.0],{}]]
	for input: Array in cases:
		var result := Formation.calculate(input[0],input[1],input[2],input[3],input[4])
		check(not bool(result.get("ok",false)) and result.slots.is_empty() and str(result.reason_code).begins_with("formation_") and str(result.message_key).begins_with("formation.error."),"Malformed/blocked drafts reject atomically with paired translation key")

func _m01_contract() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	for door: Dictionary in data.doors:
		if door.id in ["d1","d2"]: door["state"] = "OPEN"; door["progress"] = 1.0
	var starts: Dictionary = {}
	for index: int in range(4): starts[IDS[index]] = [11.4+float(index)*0.7,15.7]
	var result := Formation.calculate(data,IDS,starts,[12.0,10.8],{})
	assert_layout(data,IDS,starts,[12.0,10.8],result,"P0 M01 unchanged central passage")
	if not bool(result.get("ok",false)): return
	check(result.kind=="ROLLING_T","Authored M01 passage recommends rolling T")
	# The original P0 line starts x=11.4+0.7*i at one depth. A nominal
	# stack at x=11.65 overlapped the next actor's current body (0.449 m).
	# Every selected anchor and every complete approach leg must fit both
	# the unchanged live 0.48 m body contract and the other future stacks.
	for index: int in range(result.slots.size()):
		var slot: Dictionary = result.slots[index]
		var previous := point(starts[slot.unit_id])
		for other: int in range(result.slots.size()):
			if other==index: continue
			check(point(slot.stack).distance_to(point(starts[result.slots[other].unit_id]))>=Navigation.RADIUS*2.0+0.02,"P0 common stack anchor clears all other owned current bodies")
		for raw: Array in slot.stack_route:
			var next := point(raw)
			for other: int in range(result.slots.size()):
				if other==index: continue
				for body: Vector2 in [point(starts[result.slots[other].unit_id]),point(result.slots[other].stack)]:
					check(Geometry2D.get_closest_point_to_segment(body,previous,next).distance_to(body)>=Navigation.RADIUS*2.0+0.02,"P0 complete static approach avoids owned origin and stack bodies")
			previous = next
	var cover: Dictionary = result.slots[1]
	# The former first legal 2.1 m anchor caged BRAVO between current bodies
	# and the future rear stack, forcing a 5.054 m retreating approach. The
	# unchanged roles now fit a 2.45 m forward anchor with total cost 8.570 m.
	# A cheaper negative anchor must not displace a legal forward draft.
	var total_approach := 0.0
	for slot: Dictionary in result.slots: total_approach += route_length(point(starts[slot.unit_id]),slot.stack_route)
	check(total_approach<9.0,"P0 reachable forward anchor removes the unnecessary 10.339m team approach")
	check((point(cover.stack_route[0])-point(starts.bravo)).dot((point(result.target)-point(starts.bravo)).normalized())>0.0,"P0 left cover starts forward rather than selecting the cheaper retreat fallback")
	# P0 used a valid square-raster approach that needlessly retreated south.
	# The actor circle has additional legal diagonal space. Preserve the
	# physical body contract, and require a genuinely shorter complete route
	# rather than accepting any first-found valid detour as least resistance.
	var square_data := data.duplicate(true)
	var owned_bodies: Array[Vector2] = []
	for slot: Dictionary in result.slots:
		if slot.unit_id=="bravo": continue
		for body: Vector2 in [point(starts[slot.unit_id]),point(slot.stack)]:
			if not owned_bodies.has(body): owned_bodies.append(body)
	for body: Vector2 in owned_bodies:
		square_data.props.append({"id":"reference_body","type":"box","x":body.x,"z":body.y,"w":0.5,"d":0.5,"cover":"full"})
	var square_nav := Navigation.new()
	square_nav.build(square_data,square_data.doors)
	var square_route: Array = square_nav.path(point(starts.bravo),point(cover.stack))
	check(not square_route.is_empty(),"P0 comparison retains the earlier valid conservative square route")
	if not square_route.is_empty():
		var chosen_length := route_length(point(starts.bravo),cover.stack_route)
		var square_length := route_length(point(starts.bravo),square_route)
		check(chosen_length+0.1<square_length,"P0 exact circular route removes at least 0.1m of unnecessary conservative detour")
	var contact := Vector2(7.8,13.6)-point(starts.bravo)
	check(absf(angle_difference(direction(starts.bravo,cover.initial_face_target).angle(),contact.angle()))<=deg_to_rad(55.0),"Initial role FACE covers original P0 side contact before stack MOVE")
	# Without a target cap, this nearby destination selects a legal anchor
	# beyond its target and sends the formation backwards after readiness.
	var nearby := Formation.calculate(data,IDS,starts,[12.0,14.5],{})
	check(not bool(nearby.get("ok",false)) and nearby.slots.is_empty() and nearby.reason_code=="formation_stack","Nearby M01 target cannot be overshot to manufacture a reachable forward stack")
	var retreat := Formation.calculate(data,IDS,starts,[12.0,14.0],{})
	assert_layout(data,IDS,starts,[12.0,14.0],retreat,"Bounded M01 retreat fallback when forward anchors do not fit")

func _close_anchor_contract() -> void:
	# Operators already in a valid rolling row need no staging advance for a
	# short order. The target cap must preserve this ordinary legal plan.
	var starts := {"alpha":[7.65,18.0],"bravo":[8.35,18.0],"charlie":[8.0,18.7],"delta":[8.0,19.4]}
	var target := [7.65,17.85]
	var result := Formation.calculate(fixture(),IDS,starts,target,{"kind":"ROLLING_T"})
	assert_layout(fixture(),IDS,starts,target,result,"Already formed nearby target")
	if bool(result.get("ok",false)):
		for slot: Dictionary in result.slots:
			check(point(slot.stack).distance_to(point(starts[slot.unit_id]))<0.0001,"Nearby order retains the reachable zero-cost existing stack")

func _narrow_reorder_contract() -> void:
	# The browser's authored 1.6 m corridor has a body-clear half-width of
	# 0.57 m. The old 0.6 m cardinal vertices fell outside it; its diagonal
	# vertices at 0.424 m could not pass the unchanged 0.48 m body circles.
	# The fallback octagon fits, with chords still strictly outside 0.48 m.
	var data := BrowserFixture.fixture("narrow","verbal")
	var ids: Array[String] = ["alpha","bravo","delta","charlie"]
	var starts: Dictionary = {}
	for unit: Dictionary in data.units: starts[str(unit.id)] = [unit.x,unit.z]
	# A real DOM click publishes x=7.98 (then float32 canonicalizes it);
	# both it and the authored x=8 target must accept the same rear reorder.
	for target: Array in [[8.0,4.0],[7.98,4.0]]:
		var before := JSON.stringify({"data":data,"starts":starts})
		var result := Formation.calculate(data,ids,starts,target,{})
		assert_layout(data,ids,starts,target,result,"Authored narrow browser rear-rank reorder")
		check(JSON.stringify({"data":data,"starts":starts})==before,"Narrow fallback preserves all authored inputs")
		check(Formation.TIGHT_BODY_RING*cos(PI/8.0)>Navigation.RADIUS*2.0+0.02,"Fallback polygon chords retain the full physical body spacing")
		if not bool(result.get("ok",false)): return
		check(result.kind=="SERPENTINE" and result.source_unit_id=="charlie","Narrow reorder retains doctrine and the actual new rear source")
		var uses_passing_lane := false
		for index: int in range(result.slots.size()):
			var slot: Dictionary = result.slots[index]
			var previous := point(starts[slot.unit_id])
			for raw: Array in slot.stack_route:
				var next := point(raw)
				uses_passing_lane = uses_passing_lane or absf(next.x-8.0)>0.48
				for other: int in range(ids.size()):
					if other==index: continue
					for body: Vector2 in [point(starts[ids[other]]),point(result.slots[other].stack)]:
						check(Geometry2D.get_closest_point_to_segment(body,previous,next).distance_to(body)>=Navigation.RADIUS*2.0+0.02,"Narrow fallback whole edges clear every owned origin and future stack circle")
				previous = next
		check(uses_passing_lane,"Narrow reorder uses a real lateral passing lane rather than crossing occupied bodies")
		check(JSON.stringify(result)==JSON.stringify(Formation.calculate(data,ids,starts,target,{})),"Narrow fallback repeats the same complete deterministic draft")

func _old_success_differential(original_path: String) -> void:
	# Focused verification can load the untouched pre-change script from /tmp
	# in this same engine. This avoids cross-platform atan2 bit goldens and
	# leaves the permanent regressions independent of external oracle files.
	var original: GDScript = load(original_path)
	check(original!=null,"Requested pre-fallback differential oracle loads")
	if original==null: return
	var narrow := BrowserFixture.fixture("narrow","verbal")
	var narrow_starts: Dictionary = {}
	for unit: Dictionary in narrow.units: narrow_starts[str(unit.id)] = [unit.x,unit.z]
	var house: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	for door: Dictionary in house.doors:
		if door.id in ["d1","d2"]: door["state"] = "OPEN"; door["progress"] = 1.0
	var house_starts: Dictionary = {}
	for index: int in range(4): house_starts[IDS[index]] = [11.4+float(index)*0.7,15.7]
	var cases: Array = [
		["default narrow",narrow,narrow_starts,BrowserFixture.destination("narrow"),{}],
		["default narrow DOM click",narrow,narrow_starts,[7.98,4.0],{}],
		["default wide",fixture(),approaches(),[8.0,6.0],{}],
		["P0 M01",house,house_starts,[12.0,10.8],{}],
		["explicit T",junction_fixture(),approaches(),[8.0,7.0],{"kind":"T_JUNCTION"}]]
	for input: Array in cases:
		var old: Dictionary = original.calculate(input[1],IDS,input[2],input[3],input[4])
		var current := Formation.calculate(input[1],IDS,input[2],input[3],input[4])
		check(bool(old.get("ok",false)),str(input[0])+" oracle was successful before fallback")
		check(JSON.stringify(old)==JSON.stringify(current),str(input[0])+" previously successful full JSON draft stays exactly unchanged")
		print("FORMATION_OLD_DRAFT "+JSON.stringify({"case":input[0],"old_hash":JSON.stringify(old).sha256_text(),"current_hash":JSON.stringify(current).sha256_text()}))
	var old_reorder: Dictionary = original.calculate(narrow,["alpha","bravo","delta","charlie"],narrow_starts,BrowserFixture.destination("narrow"),{})
	check(not bool(old_reorder.get("ok",false)) and old_reorder.get("reason_code","")=="formation_stack","Original narrow reordered fixture reproduces the false rejection before fallback")

func junction_fixture() -> Dictionary:
	return {"schema_version":4,"bounds":[20.0,24.0],"rooms":[{"id":"stem","x":8.0,"z":15.1,"w":2.4,"d":13.8},{"id":"branches","x":8.0,"z":7.0,"w":12.0,"d":2.4}],
		"walls":[{"id":"forward","x":8.0,"z":5.7,"w":12.0,"d":0.2},
			{"id":"west_end","x":1.9,"z":7.0,"w":0.2,"d":2.6},{"id":"east_end","x":14.1,"z":7.0,"w":0.2,"d":2.6},
			{"id":"west_bottom","x":4.4,"z":8.3,"w":4.8,"d":0.2},{"id":"east_bottom","x":11.6,"z":8.3,"w":4.8,"d":0.2},
			{"id":"stem_west","x":6.7,"z":15.1,"w":0.2,"d":13.8},{"id":"stem_east","x":9.3,"z":15.1,"w":0.2,"d":13.8},
			{"id":"south","x":8.0,"z":22.0,"w":2.4,"d":0.2}],"props":[],"doors":[]}

func wide_junction_fixture() -> Dictionary:
	# The 3.2 m cross arm contains a point 1.4 m behind its centre. The stem
	# width must be sampled beyond that arm, while the exact T centre and
	# authored floor-union remain legal. This matches the browser's real map.
	return {"schema_version":5,"bounds":[20.0,18.0],
		"rooms":[{"id":"stem","x":8.0,"z":11.4,"w":3.2,"d":9.2},{"id":"cross","x":8.0,"z":5.2,"w":12.0,"d":3.2}],
		"walkable_areas":[{"x":8.0,"z":11.4,"w":3.2,"d":9.2},{"x":8.0,"z":5.2,"w":12.0,"d":3.2}],
		"walls":[{"x":6.3,"z":11.4,"w":0.2,"d":9.2},{"x":9.7,"z":11.4,"w":0.2,"d":9.2},{"x":8.0,"z":16.1,"w":3.2,"d":0.2},
			{"x":8.0,"z":3.5,"w":12.0,"d":0.2},{"x":1.9,"z":5.2,"w":0.2,"d":3.2},{"x":14.1,"z":5.2,"w":0.2,"d":3.2},
			{"x":4.2,"z":6.9,"w":4.4,"d":0.2},{"x":11.8,"z":6.9,"w":4.4,"d":0.2}],"props":[],"doors":[]}

func _junction_contracts() -> void:
	var data := junction_fixture()
	var result := Formation.calculate(data,IDS,approaches(),[8.0,7.0],{"kind":"T_JUNCTION"})
	assert_layout(data,IDS,approaches(),[8.0,7.0],result,"Physical four-person T")
	if not bool(result.get("ok",false)): return
	check(result.kind=="T_JUNCTION" and bool(result.hand_ready_compatible),"Explicit T supplies legal default hand readiness")
	for index: int in range(4):
		var slot: Dictionary = result.slots[index]
		check(slot.stance==("crouched" if index in [0,2] else "standing"),"T low/high pairs use the actual ready FACE stance request")
		check((float(slot.target[0])-8.0)*(-1.0 if index<2 else 1.0)>0.0,"T pairs enter separate side branches")
		var previous := point(slot.stack)
		for route_index: int in range(slot.move_route.size()):
			var face := point(slot.move_face_targets[route_index])-previous
			check(face.normalized().dot(Vector2.LEFT if index<2 else Vector2.RIGHT)>0.9999,"T faces along branch instead of rotating perpendicular to each movement segment")
			previous = point(slot.move_route[route_index])
	var wide := wide_junction_fixture()
	var wide_starts: Dictionary = {}
	for index: int in range(4): wide_starts[IDS[index]] = [8.0,11.0+index*0.7]
	var wide_result := Formation.calculate(wide,IDS,wide_starts,[8.0,5.2],{"kind":"T_JUNCTION"})
	assert_layout(wide,IDS,wide_starts,[8.0,5.2],wide_result,"Wide-arm actual floor-union T")
	if bool(wide_result.get("ok",false)):
		check(absf(float(wide_result.corridor_width)-3.2)<0.00001,"Wide T reports incoming stem width rather than cross-arm length")
	var cross := data.duplicate(true)
	cross.walls = cross.walls.filter(func(wall: Dictionary)->bool:return wall.id!="forward")
	check(not bool(Formation.calculate(cross,IDS,approaches(),[8.0,7.0],{"kind":"T_JUNCTION"}).get("ok",false)),"An open X or field is not silently accepted as a T")

func _rotated_geometry(data: Dictionary, turns: int) -> Dictionary:
	var result := data.duplicate(true)
	for _turn: int in range(turns):
		var bounds: Array = result.bounds.duplicate()
		result.bounds = [bounds[1],bounds[0]]
		for key: String in ["rooms","walls","props","walkable_areas"]:
			for item: Dictionary in result.get(key,[]):
				var x := float(item.x)
				item.x = float(bounds[1])-float(item.z)
				item.z = x
				var width := float(item.w)
				item.w = item.d
				item.d = width
	return result

func _rotate_point(raw: Array, bounds: Array, turns: int) -> Array:
	var result := raw.duplicate()
	var size := bounds.duplicate()
	for _turn: int in range(turns):
		result = [float(size[1])-float(result[1]),result[0]]
		size = [size[1],size[0]]
	return result

func _rotation_large_floor_contracts() -> void:
	for width: float in [1.6,1.8,3.2]:
		var original := fixture(width)
		for turns: int in range(4):
			var data := _rotated_geometry(original,turns)
			var starts: Dictionary = {}
			for id: String in IDS: starts[id] = _rotate_point(approaches()[id],original.bounds,turns)
			var target := _rotate_point([8.0,6.0],original.bounds,turns)
			var result := Formation.calculate(data,IDS,starts,target,{})
			assert_layout(data,IDS,starts,target,result,"Axis%d width%.1f"%[turns,width])
			if bool(result.get("ok",false)):
				check(result.kind==("SERPENTINE" if width<1.8 else "ROLLING_T"),"Rotated physical width keeps recommendation")
	var near := fixture(1.8)
	var translated := near.duplicate(true)
	translated.bounds = [512.0,512.0]
	for key: String in ["rooms","walls"]:
		for item: Dictionary in translated[key]: item.x = float(item.x)+460.0; item.z = float(item.z)+460.0
	var translated_starts: Dictionary = {}
	for id: String in IDS: translated_starts[id] = [float(approaches()[id][0])+460.0,float(approaches()[id][1])+460.0]
	var far := Formation.calculate(translated,IDS,translated_starts,[468.0,466.0],{})
	assert_layout(translated,IDS,translated_starts,[468.0,466.0],far,"512m local formation")
	if bool(far.get("ok",false)):
		check(far.kind=="ROLLING_T" and absf(float(far.corridor_width)-1.8)<0.00001,"Large-world float32 locations preserve authored double width threshold")
		var nearby := Formation.calculate(near,IDS,approaches(),[8.0,6.0],{})
		for index: int in range(4):
			check((point(far.slots[index].stack)-Vector2(460,460)).distance_to(point(nearby.slots[index].stack))<0.0002,"Large-world stack layout retains room-relative spacing")
	var raised := fixture(3.2)
	raised.rooms.insert(0,{"id":"apron","x":10.0,"z":12.0,"w":20.0,"d":24.0,"indoor":false})
	raised.rooms[1]["base_height"] = 2.022
	raised.rooms[1]["indoor"] = true
	for wall: Dictionary in raised.walls: wall["base_height"] = 2.022
	var elevated := Formation.calculate(raised,IDS,approaches(),[8.0,6.0],{})
	assert_layout(raised,IDS,approaches(),[8.0,6.0],elevated,"Overlapping elevated deck")
	if bool(elevated.get("ok",false)):
		for slot: Dictionary in elevated.slots: check(is_equal_approx(float(slot.floor_height),2.022),"Authored elevated floor overrides overlapping outdoor apron")
	var interrupted := fixture(3.2)
	interrupted.rooms.append({"id":"raised_strip","x":8.0,"z":13.0,"w":3.2,"d":1.0,"base_height":2.022})
	check(not bool(Formation.calculate(interrupted,IDS,approaches(),[8.0,6.0],{}).get("ok",false)),"Equal-height endpoints cannot hide an intervening floor jump without authored vertical navigation")

func _water_and_bend_contracts() -> void:
	var deck := fixture(3.2)
	deck.walkable_areas = [{"x":8.0,"z":7.0,"w":3.2,"d":10.0},{"x":8.0,"z":17.0,"w":3.2,"d":10.0}]
	var joined := Formation.calculate(deck,IDS,approaches(),[8.0,6.0],{})
	assert_layout(deck,IDS,approaches(),[8.0,6.0],joined,"Touching walkable deck union")
	var broken := deck.duplicate(true)
	broken.walkable_areas[1].z = 17.5
	check(not bool(Formation.calculate(broken,IDS,approaches(),[8.0,6.0],{}).get("ok",false)),"A real water gap refuses the complete formation instead of jumping across")
	var corner := {"schema_version":5,"bounds":[24.0,24.0],"walls":[],"props":[],"doors":[],
		"rooms":[{"id":"stem","x":8.0,"z":15.0,"w":3.2,"d":14.0},{"id":"arm","x":13.0,"z":8.0,"w":13.2,"d":3.2}],
		"walkable_areas":[{"x":8.0,"z":15.0,"w":3.2,"d":14.0},{"x":13.0,"z":8.0,"w":13.2,"d":3.2}]}
	var bent := Formation.calculate(corner,IDS,approaches(),[17.0,8.0],{})
	assert_layout(corner,IDS,approaches(),[17.0,8.0],bent,"Actual L corridor and segment role faces")
	if bool(bent.get("ok",false)):
		check(bent.slots.any(func(slot: Dictionary)->bool:return slot.move_route.size()>1),"L corridor preserves necessary corner endpoints")
		for index: int in range(4):
			var slot: Dictionary = bent.slots[index]
			var prior := point(slot.stack)
			for route_index: int in range(slot.move_route.size()):
				var leg := (point(slot.move_route[route_index])-prior).normalized()
				var role := Formation._role_direction(str(bent.kind),index,leg)
				check((point(slot.move_face_targets[route_index])-prior).normalized().dot(role)>0.9999,"Every bend FACE is based on the preceding actual route endpoint")
				prior = point(slot.move_route[route_index])

func _door_and_furniture_contracts() -> void:
	for hinge: int in [-1,1]:
		for swing: int in [-1,1]:
			for state: String in ["CLOSED","AJAR","OPEN","DESTROYED"]:
				var data := fixture(3.2)
				data.doors = [{"id":"portal","x":8.0,"z":12.0,"w":3.2,"d":0.24,"axis":"x","hinge_side":hinge,"swing_sign":swing,"state":state,"progress":0.5 if state=="AJAR" else (1.0 if state=="OPEN" else 0.0),"destroyed":state=="DESTROYED"}]
				var before := JSON.stringify(data)
				var result := Formation.calculate(data,IDS,approaches(),[8.0,6.0],{})
				if state in ["OPEN","DESTROYED"]:
					assert_layout(data,IDS,approaches(),[8.0,6.0],result,"Authored leaf %s hinge%d swing%d"%[state,hinge,swing])
				elif bool(result.get("ok",false)):
					assert_layout(data,IDS,approaches(),[8.0,6.0],result,"Body-clear partial leaf")
				else: check(result.slots.is_empty(),"Blocked authored leaf rejects atomically")
				if state=="CLOSED": check(not bool(result.get("ok",false)),"A full closed leaf is not silently forecast as open")
				check(JSON.stringify(data)==before,"Door pose, hinge and swing are never mutated by preview")
	var furnished := fixture(3.2)
	furnished.props = [{"id":"cabinet","type":"cabinet","x":8.0,"z":12.0,"w":1.1,"d":1.2,"cover":"full"}]
	var furniture := Formation.calculate(furnished,IDS,approaches(),[8.0,6.0],{})
	assert_layout(furnished,IDS,approaches(),[8.0,6.0],furniture,"Full-height furniture detour")
	if bool(furniture.get("ok",false)): check(furniture.slots.any(func(slot: Dictionary)->bool:return slot.move_route.size()>1),"Furniture produces a continuous obstacle detour instead of clipping the cabinet")

func run() -> void:
	_basic_contracts()
	_m01_contract()
	_close_anchor_contract()
	_narrow_reorder_contract()
	_junction_contracts()
	if not "--smoke-only" in OS.get_cmdline_user_args():
		_repeat_contracts()
		_invalid_contracts()
		_rotation_large_floor_contracts()
		_water_and_bend_contracts()
		_door_and_furniture_contracts()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--original-helper="): _old_success_differential(argument.trim_prefix("--original-helper="))
	for failure: String in failures: print("FAIL "+failure)
	print("BREACH_FORMATION_GEOMETRY_RESULT checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
