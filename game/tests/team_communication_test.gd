extends SceneTree
## P4 pure communication contracts use real navigation geometry and poses.
## No clock, contacts, camera/peek sensors, movement or RNG is advanced here.
const Communication = preload("res://scripts/team_communication.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _unit(id: String, point: Vector2, facing: float = 0.0) -> Dictionary:
	return {"id":id,"kind":"unit","x":point.x,"z":point.y,"can_act":true,"hp":100.0,"base_height":0.0,"stance":"standing","facing":facing,"fov":110.0,"vision_range":10.0}

func _nav(walls: Array = [], doors: Array = [], extra: Dictionary = {}) -> BreachNavigation:
	var map: Dictionary = {"schema_version":5,"bounds":[12,12],"rooms":[],"walls":walls,"props":[],"doors":doors}
	map.merge(extra,true)
	var navigation := Navigation.new()
	navigation.build(map,doors)
	return navigation

func _receives(sender: Dictionary, receiver: Dictionary, navigation: BreachNavigation, mode: String = "hand_signals", smoke: Array = []) -> bool:
	return Communication.can_receive(sender,receiver,navigation,mode,smoke)

func _run() -> void:
	_modes_and_eligibility()
	_delivery_contract()
	_mutual_fov_and_range()
	_body_eye_geometry()
	_door_geometry()
	_smoke_geometry()
	_purity_and_determinism()
	print("BREACH_TEAM_COMMUNICATION_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _modes_and_eligibility() -> void:
	var navigation := _nav()
	var alpha := _unit("alpha",Vector2(3,6))
	var bravo := _unit("bravo",Vector2(5,6),PI)
	check(Communication.discipline({}) == "verbal","Missing policy uses spoken runtime default")
	for mode: String in ["verbal","hand_signals"]:
		var mission := {"noise_discipline":mode}
		var before := JSON.stringify(mission)
		check(Communication.discipline(mission) == mode and JSON.stringify(mission) == before,"Explicit policy lookup preserves source "+mode)
		check(_receives(alpha,bravo,navigation,mode),"Eligible own units communicate using "+mode)
		check(_receives(alpha,alpha,null,mode),"Valid self delivery is accepted using "+mode)
	check(not _receives(alpha,bravo,null),"Hand signal requires actual navigation")
	check(_receives(alpha,bravo,null,"verbal"),"Spoken legacy logical delivery does not require geometry")
	check(not _receives(alpha,bravo,navigation,"Verbal"),"Wrong-case signal mode does not silently use spoken fallback")
	for value: Variant in [null,true,1,[],{},"","quiet","VERBAL"]:
		check(Communication.discipline({"noise_discipline":value}).is_empty(),"Invalid explicit policy has no default fallback: "+str(value))
	for field: String in ["id","kind","x","z","can_act"]:
		var invalid := alpha.duplicate(true)
		invalid.erase(field)
		check(not _receives(invalid,bravo,navigation,"verbal"),"Missing explicit own context rejected: "+field)
	for values: Dictionary in [
		{"id":""},{"id":1},{"kind":"enemy"},{"kind":"civilian"},{"can_act":false},{"can_act":1},{"can_act":"true"},
		{"hp":0.0},{"hp":-1.0},{"hp":true},{"stunned":0.1},{"_flash_recover":0.1},{"surrendered":true},{"arrested":true},
		{"x":NAN},{"z":INF},{"x":true},{"facing":NAN},{"base_height":INF},{"fov":-1},{"fov":361},{"vision_range":-1},
		{"effective_vision_range":-1},{"body_height":0},{"eye_height":0},{"stance":"prone"}
	]:
		var invalid := alpha.duplicate(true)
		invalid.merge(values,true)
		check(not _receives(invalid,bravo,navigation,"verbal"),"Invalid source rejected without fallback: "+str(values))
		check(not _receives(bravo,invalid,navigation,"verbal"),"Invalid receiver rejected: "+str(values))
		check(not _receives(invalid,invalid,navigation),"Invalid actor cannot accept itself: "+str(values))
	check(not _receives({},bravo,navigation),"Unknown own ID lookup is rejected")
	var upstairs := bravo.duplicate(true)
	upstairs.base_height = 9.0
	upstairs.facing = 0.0
	check(_receives(alpha,upstairs,navigation,"verbal"),"Spoken logical broadcast retains legacy floor/FOV independence")

func _delivery_contract() -> void:
	var navigation := _nav()
	var alpha := _unit("alpha",Vector2(3,6))
	var bravo := _unit("bravo",Vector2(5,6),PI)
	var charlie := _unit("charlie",Vector2(5,7),Vector2(-2,-1).angle())
	var delta := _unit("delta",Vector2(1,6),0)
	var receivers := [charlie,delta,bravo,alpha,bravo.duplicate(true)]
	var answer := Communication.delivery(alpha,receivers,navigation,"hand_signals")
	check(answer.keys().size() == 4 and answer.has_all(["source_unit_id","receiver_unit_ids","blocked_unit_ids","complete"]),"Delivery uses exact diagnostic shape")
	check(answer.source_unit_id == "alpha","Explicit source ID is retained")
	check(answer.receiver_unit_ids == ["alpha","bravo","charlie"],"Hand recipients are sorted, unique and physically received")
	check(answer.blocked_unit_ids == ["delta"] and not answer.complete,"Partial delivery reports blocked own IDs")
	check(not JSON.stringify(answer).contains("Vector"),"Delivery remains JSON-safe")
	for order: Array in [[alpha,bravo,charlie],[charlie,bravo,alpha],[bravo,alpha,charlie,bravo]]:
		var delivered := Communication.delivery(alpha,order,navigation,"hand_signals")
		check(delivered.complete and delivered.receiver_unit_ids == ["alpha","bravo","charlie"] and delivered.blocked_unit_ids.is_empty(),"Input ordering/duplicate ID does not change complete recipient set")
	var spoken := Communication.delivery(alpha,receivers,navigation,"verbal")
	check(spoken.complete and spoken.receiver_unit_ids == ["alpha","bravo","charlie","delta"],"Spoken broadcast retains all valid own recipients")
	var empty := Communication.delivery(alpha,[],navigation)
	check(not empty.complete and empty.receiver_unit_ids.is_empty() and empty.blocked_unit_ids.is_empty(),"An empty receiver group is not a successful barrier")
	var invalid := alpha.duplicate(true)
	invalid.can_act = false
	var rejected := Communication.delivery(invalid,[charlie,bravo],navigation,"verbal")
	check(not rejected.complete and rejected.receiver_unit_ids.is_empty() and rejected.blocked_unit_ids == ["bravo","charlie"],"Invalid explicit sender never selects another source")
	check(rejected.source_unit_id == "alpha","Rejected explicit sender remains explicit in private diagnostic result")
	var unknown := Communication.delivery({},[bravo],navigation)
	check(unknown.source_unit_id.is_empty() and not unknown.complete and unknown.blocked_unit_ids == ["bravo"],"Unknown source cannot deliver")
	var malformed := Communication.delivery(alpha,[null,{},bravo],navigation,"verbal")
	check(not malformed.complete and malformed.receiver_unit_ids == ["bravo"],"Malformed receiver context prevents successful group delivery")

func _mutual_fov_and_range() -> void:
	var navigation := _nav()
	var alpha := _unit("alpha",Vector2(3,6))
	var bravo := _unit("bravo",Vector2(5,6),PI)
	bravo.facing = 0.0
	check(not _receives(alpha,bravo,navigation),"One-way sight cannot receive a hand signal")
	bravo.facing = PI
	alpha.facing = PI
	check(not _receives(alpha,bravo,navigation),"Sender must also see recipient")
	alpha.facing = 0.0
	for degrees: float in [54.9,-54.9,55.1,-55.1]:
		var offset := Vector2.from_angle(deg_to_rad(degrees))*2.0
		bravo.x = alpha.x+offset.x
		bravo.z = alpha.z+offset.y
		bravo.facing = (-offset).angle()
		check(_receives(alpha,bravo,navigation) == (absf(degrees) < 55.0),"Mutual FOV respects cone edge "+str(degrees))
	alpha.x = 5.0
	bravo.x = 3.0
	bravo.z = 6.0
	bravo.facing = 0.0
	for wrapped: float in [PI-0.01,-PI+0.01,PI+TAU*4.0]:
		alpha.facing = wrapped
		check(_receives(alpha,bravo,navigation),"World angle wrap preserves body sight "+str(wrapped))
	alpha = _unit("alpha",Vector2(1,6))
	bravo = _unit("bravo",Vector2(6,6),PI)
	alpha.vision_range = 5.0
	bravo.vision_range = 5.0
	check(_receives(alpha,bravo,navigation),"Exact effective vision range remains inclusive")
	bravo.x = 6.01
	check(not _receives(alpha,bravo,navigation),"Just beyond either recipient range is blocked")
	alpha.vision_range = 10.0
	bravo.vision_range = 4.0
	check(not _receives(alpha,bravo,navigation),"Long sender range does not bypass short recipient range")
	var dark := _nav([],[],{"environment":{"lighting":0.0}})
	alpha.vision_range = 10.0
	bravo.vision_range = 10.0
	bravo.x = 6.5
	check(_receives(alpha,bravo,dark),"Dark environment uses existing effective range factor")
	bravo.x = 6.6
	check(not _receives(alpha,bravo,dark),"Hand range uses lighting rather than raw distance limit")
	alpha.effective_vision_range = 6.0
	bravo.effective_vision_range = 6.0
	check(_receives(alpha,bravo,dark),"Explicit effective range is not dimmed a second time")
	var dim_room := _nav([],[],{"rooms":[{"id":"dim","x":6,"z":6,"w":12,"d":12,"lighting":0.5}]})
	alpha.erase("effective_vision_range")
	bravo.erase("effective_vision_range")
	alpha.x = 2.0
	bravo.x = 9.7
	check(_receives(alpha,bravo,dim_room),"Room lighting is part of body communication range")
	bravo.x = 9.8
	check(not _receives(alpha,bravo,dim_room),"Room lighting constrains both observers")

func _body_eye_geometry() -> void:
	var alpha := _unit("alpha",Vector2(4,6))
	var bravo := _unit("bravo",Vector2(8,6),PI)
	var wall := {"id":"wall","x":6,"z":6,"w":0.2,"d":10,"height":2.6}
	var solid := _nav([wall])
	check(not _receives(alpha,bravo,solid),"Full wall blocks body-eye communication")
	check(_receives(alpha,bravo,solid,"verbal"),"Spoken legacy logical delivery remains independent of physical wall")
	wall.height = 1.35
	var low := _nav([wall])
	check(_receives(alpha,bravo,low),"Standing eyes see over a low obstruction")
	alpha.stance = "crouched"
	bravo.stance = "crouched"
	check(not _receives(alpha,bravo,low),"Crouched eye height cannot see through the same obstruction")
	alpha.stance = "standing"
	check(not _receives(alpha,bravo,low),"Mixed stance uses the actual sloped eye ray")
	bravo.stance = "standing"
	bravo.base_height = 0.00005
	check(_receives(alpha,bravo,low),"Same-floor float tolerance accepts small pose drift")
	bravo.base_height = 0.0002
	check(not _receives(alpha,bravo,low),"Different actual floors reject otherwise clear sight")
	alpha.base_height = 9.0
	bravo.base_height = 9.0
	check(_receives(alpha,bravo,solid),"Both actors on high floor see over an obstacle on ground")
	wall.height = 2.6
	wall.base_height = 9.0
	var raised := _nav([wall])
	check(not _receives(alpha,bravo,raised),"Obstacle base height blocks the matching raised eye ray")
	wall.material = "glass"
	var transparent := _nav([wall])
	check(_receives(alpha,bravo,transparent),"Optical LOS preserves existing transparent material geometry")
	var map512 := {"bounds":[512,512],"walkable_areas":[{"id":"deck","x":480,"z":480,"w":8,"d":8}]}
	var far := _nav([],[],map512)
	alpha.x = 478.0
	alpha.z = 480.0
	bravo.x = 482.0
	bravo.z = 480.0
	check(_receives(alpha,bravo,far),"512m coordinates and raised floors do not change mutual body sight")
	# These auxiliary origins could see around the original wall; the physical
	# sender remains behind it and must not inherit camera/peek/memory sight.
	alpha = _unit("alpha",Vector2(4,6))
	bravo = _unit("bravo",Vector2(8,6),PI)
	alpha["_peek_origin"] = [7.0,6.0]
	alpha["_peek_remaining"] = 10.0
	alpha["camera_origin"] = [7.0,6.0]
	alpha["_camera_sensor"] = {"x":7.0,"z":6.0,"facing":0.0,"range":30.0}
	alpha["last_seen"] = [8.0,6.0]
	alpha["_sensory_memory"] = {"bravo":{"position":[8.0,6.0],"confidence":1.0}}
	check(not _receives(alpha,bravo,solid),"Camera, leaning origins and memory cannot bypass body-eye LOS")

func _door_geometry() -> void:
	var alpha := _unit("alpha",Vector2(6,4),PI*0.5)
	var bravo := _unit("bravo",Vector2(6,8),-PI*0.5)
	for hinge: int in [-1,1]:
		for swing: int in [-1,1]:
			for axis: String in ["x","z"]:
				var door := {"id":"door","x":6,"z":6,"w":1.8 if axis == "x" else 0.24,"d":0.24 if axis == "x" else 1.8,"axis":axis,"state":"CLOSED","progress":0.0,"destroyed":false,"height":2.1,"hinge_side":hinge,"swing_sign":swing}
				if axis == "z":
					alpha.x = 4.0; alpha.z = 6.0; alpha.facing = 0.0
					bravo.x = 8.0; bravo.z = 6.0; bravo.facing = PI
				else:
					alpha.x = 6.0; alpha.z = 4.0; alpha.facing = PI*0.5
					bravo.x = 6.0; bravo.z = 8.0; bravo.facing = -PI*0.5
				var closed := _nav([],[door])
				check(not _receives(alpha,bravo,closed),"Closed leaf blocks both-axis hand LOS h%d s%d %s" % [hinge,swing,axis])
				door.state = "OPEN"; door.progress = 1.0
				var opened := _nav([],[door])
				check(_receives(alpha,bravo,opened),"Open actual leaf permits center portal hand LOS h%d s%d %s" % [hinge,swing,axis])
				door.state = "AJAR"; door.progress = 0.52
				var ajar := _nav([],[door])
				check(not _receives(alpha,bravo,ajar),"AJAR leaf keeps actual center ray blocked h%d s%d %s" % [hinge,swing,axis])
				door.state = "CLOSED"; door.progress = 0.0; door.destroyed = true
				var destroyed := _nav([],[door])
				check(_receives(alpha,bravo,destroyed),"Destroyed leaf does not block body sight h%d s%d %s" % [hinge,swing,axis])

func _smoke_geometry() -> void:
	var navigation := _nav()
	var alpha := _unit("alpha",Vector2(3,6))
	var bravo := _unit("bravo",Vector2(7,6),PI)
	for center: Vector2 in [Vector2(5,6),Vector2(3,6),Vector2(7,6)]:
		var smoke := [{"x":center.x,"z":center.y,"radius":0.5,"remaining":4.0}]
		check(not _receives(alpha,bravo,navigation,"hand_signals",smoke),"Active smoke intersects segment/endpoints "+str(center))
		check(_receives(alpha,bravo,navigation,"verbal",smoke),"Smoke does not silence spoken logical communication")
	check(_receives(alpha,bravo,navigation,"hand_signals",[{"x":5.0,"z":6.5,"radius":0.5}]),"Smoke tangent preserves the existing strict circle boundary")
	check(not _receives(alpha,bravo,navigation,"hand_signals",[{"x":5.0,"z":6.49,"radius":0.5}]),"Just inside active smoke circle blocks")
	check(_receives(alpha,bravo,navigation,"hand_signals",[{"x":9.0,"z":6.0,"radius":0.5}]),"Smoke beyond the finite segment does not block")
	check(_receives(alpha,bravo,navigation,"hand_signals",[{"x":5.0,"z":8.0,"radius":0.5}]),"Nearby smoke outside actual LOS does not block")

func _purity_and_determinism() -> void:
	var door := {"id":"door","x":6,"z":6,"w":1.8,"d":0.24,"axis":"x","state":"OPEN","progress":1.0,"hinge_side":-1,"swing_sign":1}
	var navigation := _nav([],[door])
	var alpha := _unit("alpha",Vector2(6,4),PI*0.5)
	var bravo := _unit("bravo",Vector2(6,8),-PI*0.5)
	var smoke: Array = [{"x":10.0,"z":10.0,"radius":0.5,"remaining":2.0}]
	var actors := [alpha,bravo]
	var before := JSON.stringify([actors,smoke,door,navigation.doors,navigation.walls])
	var revision := navigation.revision
	var expected := JSON.stringify(Communication.delivery(alpha,actors,navigation,"hand_signals",smoke))
	for fixed_seed: int in range(30):
		seed(42000+fixed_seed)
		var expected_rng := randi()
		seed(42000+fixed_seed)
		var actual := JSON.stringify(Communication.delivery(alpha,actors,navigation,"hand_signals",smoke))
		check(actual == expected,"Fixed geometry result is independent of seed "+str(fixed_seed))
		check(randi() == expected_rng,"Communication never consumes RNG seed "+str(fixed_seed))
		check(JSON.stringify([actors,smoke,door,navigation.doors,navigation.walls]) == before and navigation.revision == revision,"Communication leaves actor/timer/door/geometry inputs unchanged seed "+str(fixed_seed))
