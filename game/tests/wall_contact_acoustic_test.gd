extends SceneTree
## P4 sound context is additive: old-arity propagation keeps its 2D model;
## explicit floor/contact queries use live geometry without RNG or clock waits.
const Acoustic = preload("res://scripts/acoustic_model.gd")
const Navigation = preload("res://scripts/navigation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _fixture() -> Dictionary:
	return {"bounds":[20,16],"rooms":[{"id":"left","x":5.0,"z":8.0,"w":10.0,"d":16.0},{"id":"right","x":15.0,"z":8.0,"w":10.0,"d":16.0}],"walls":[{"id":"wall","x":10.0,"z":8.0,"w":0.2,"d":16.0}],"doors":[],"props":[]}

func _model(data: Dictionary, nav: RefCounted) -> RefCounted:
	var acoustic := Acoustic.new()
	acoustic.build(data,data.doors,nav)
	return acoustic

func _context(source: Vector2, acoustic: RefCounted, floor_height: float = 0.0) -> Dictionary:
	return {"source_floor":floor_height,"listener_floor":floor_height,"wall_contact":acoustic.wall_contact(source,floor_height)}

func _run() -> void:
	_test_surface_and_routes()
	_test_floors()
	_test_live_cache()
	_test_bent_portal_cache()
	_test_static_topology_cache()
	print("BREACH_WALL_CONTACT_ACOUSTIC_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_surface_and_routes() -> void:
	var data := _fixture()
	var nav := Navigation.new()
	nav.build(data,data.doors)
	var acoustic := _model(data,nav)
	for distance: float in [0.0,0.1,0.29,0.3,0.3001,0.31,0.6]:
		var source := Vector2(9.9-distance,8.0)
		var contact: Dictionary = acoustic.wall_contact(source,0.0)
		check(not contact.is_empty() if distance<=0.3 else contact.is_empty(), "Actual AABB thickness defines center-to-surface contact at %.4fm" % distance)
	var source := Vector2(9.61,8.0)
	var listener := Vector2(10.61,8.0)
	var context := _context(source,acoustic)
	var plain: float = acoustic.audibility(source,listener,3.1*1.5,{"source_floor":0.0,"listener_floor":0.0})
	var vibration: float = acoustic.audibility(source,listener,3.1*1.5,context)
	check(plain==0.0 and vibration>0.0, "A physical contact transmits one footstep through its separating wall into the opposite room")
	check(acoustic.travel_cost(source,listener,context)>=source.distance_to(listener), "Wall-face transmission includes its source-to-face distance")
	var face: Vector2 = context.wall_contact.opposite
	var face_cost: float = source.distance_to(face)+acoustic.travel_cost(face,listener,{"source_floor":0.0,"listener_floor":0.0})
	check(vibration==clampf(1.0-face_cost/(3.1*1.5),0.0,1.0), "The two propagation alternatives select the exact strongest single audibility")
	var context_copy := context.duplicate(true)
	context_copy.wall_contact.opposite = Vector2(2,2)
	context_copy.wall_contact.source = Vector2(1,1)
	check(acoustic.audibility(source,listener,3.1*1.5,context_copy)==vibration, "Caller edits cannot fabricate an acoustic face or move the actual contact")
	var away := Vector2(9.4,8.0)
	check(acoustic.audibility(away,listener,3.1*1.5,context)==0.0, "A stale contact cannot transmit after the actor leaves the wall")
	for strength: float in [0.01,3.1,4.65,12.0,18.0]:
		for ratio: float in [0.99999,1.0,1.000001,1.01]:
			var target := source+Vector2(strength*ratio,0)
			var exact: float = clampf(1.0-acoustic.travel_cost(source,target,context)/strength,0.0,1.0)
			check(acoustic.audibility(source,target,strength,context)==exact, "Contact distance prefilter keeps the exact range boundary %s/%s" % [strength,ratio])
	var mirrored := Vector2(10.39,8.0)
	check(acoustic.audibility(mirrored,Vector2(9.39,8.0),4.65,_context(mirrored,acoustic))>0.0, "The opposite wall face works in both physical directions")
	data = _fixture()
	data.rooms = [data.rooms[0]]
	nav.build(data,data.doors)
	acoustic = _model(data,nav)
	var known := {"source_floor":0.0,"listener_floor":0.0}
	check(acoustic.travel_cost(source,listener,_context(source,acoustic))==acoustic.travel_cost(source,listener,known), "An unlabelled exterior is not fabricated as an opposite room")
	data = _fixture()
	data.walls[0].w = 1.0
	nav.build(data,data.doors)
	acoustic = _model(data,nav)
	check(not acoustic.wall_contact(Vector2(9.21,8),0).is_empty() and acoustic.wall_contact(Vector2(9.19,8),0).is_empty(), "Thick-wall detection uses its real outer surface rather than the wall center")
	data = _fixture()
	data.walls[0] = {"id":"horizontal","x":10.0,"z":8.0,"w":20.0,"d":0.2}
	data.rooms = [{"id":"top","x":10.0,"z":4.0,"w":20.0,"d":8.0},{"id":"bottom","x":10.0,"z":12.0,"w":20.0,"d":8.0}]
	nav.build(data,data.doors)
	acoustic = _model(data,nav)
	check(acoustic.audibility(Vector2(10,7.61),Vector2(10,8.61),4.65,_context(Vector2(10,7.61),acoustic))>0.0, "Horizontal-wall contact follows its actual normal")

func _test_floors() -> void:
	var data := _fixture()
	for room: Dictionary in data.rooms.duplicate(true):
		room.id += "_upper"
		room.base_height = 3.0
		data.rooms.append(room)
	var upper: Dictionary = data.walls[0].duplicate(true)
	upper.id = "upper_wall"
	upper.base_height = 3.0
	data.walls.append(upper)
	var nav := Navigation.new()
	nav.build(data,data.doors)
	var acoustic := _model(data,nav)
	var source := Vector2(9.61,8)
	var listener := Vector2(10.61,8)
	check(acoustic.room_at(source)==0 and acoustic.room_at(source,0.0)==0 and acoustic.room_at(source,3.0)==2, "Optional floor selects the correct overlapping authored room while old arity stays 2D")
	check(acoustic.wall_contact(source,0).wall_index==0 and acoustic.wall_contact(source,3).wall_index==1, "A wall contact selects actual geometry on its authoritative floor")
	check(acoustic.audibility(source,listener,4.65,_context(source,acoustic,0))>0.0 and acoustic.audibility(source,listener,4.65,_context(source,acoustic,3))>0.0, "Both authored floors transmit within their own opposite room")
	var cross := _context(source,acoustic,0)
	cross.listener_floor = 3.0
	check(acoustic.audibility(source,listener,32.0,cross)==0.0 and is_inf(acoustic.travel_cost(source,listener,cross)), "Explicit CALL/foot context never reaches a different floor")
	check(acoustic.audibility(source,listener,32.0)>0.0, "Old gun/door sound arity retains its original floor-agnostic behavior")
	for floor_height: float in [0.0,3.0]:
		for strength: float in [3.1,4.65,12.0]:
			var context := _context(source,acoustic,floor_height)
			var cold := _model(data,nav)
			check(acoustic.audibility(source,listener,strength,context)==cold.audibility(source,listener,strength,context), "Shared source cache cannot alias identical XZ poses on different floors")

func _test_live_cache() -> void:
	var data := {"bounds":[20,16],"rooms":[{"id":"left","x":5,"z":8,"w":10,"d":16},{"id":"right","x":15,"z":8,"w":10,"d":16}],"walls":[{"x":10,"z":3,"w":0.3,"d":6},{"x":10,"z":11,"w":0.3,"d":10}],"doors":[{"id":"door","x":10,"z":6.5,"w":0.24,"d":1.0,"axis":"z","state":"CLOSED","progress":0.1}],"props":[]}
	var nav := Navigation.new()
	nav.build(data,data.doors)
	var warm := _model(data,nav)
	var source := Vector2(8,6.5)
	var listener := Vector2(12,6.5)
	var initial: float = warm.audibility(source,listener,12)
	# This exact positive regression failed before P4: both poses had a 0.1
	# rounded cache key although the real door-loss formula had changed.
	data.doors[0].progress = 0.101
	var cold := _model(data,nav)
	check(warm.audibility(source,listener,12)==cold.audibility(source,listener,12) and cold.audibility(source,listener,12)>initial, "Live 0.100->0.101 portal progress invalidates the stale rounded key")
	for progress: float in [0.102,0.111,0.219,0.221,0.501,0.999,1.0,0.0]:
		data.doors[0].progress = progress
		cold = _model(data,nav)
		for context: Dictionary in [{},{"source_floor":0.0,"listener_floor":0.0}]:
			check(warm.travel_cost(source,listener,context)==cold.travel_cost(source,listener,context), "Warm/cold exact portal cost at real progress %s" % progress)
	data.doors[0].progress = 0.1
	nav.rebuild()
	cold = _model(data,nav)
	check(warm.travel_cost(source,listener)==cold.travel_cost(source,listener), "Navigation revision changes cannot retain an older source cost")
	check(warm._source_cache.key[2]==nav.revision, "The actual navigation revision owns the current acoustic source cache")

func _test_bent_portal_cache() -> void:
	var data := {"bounds":[20,16],"rooms":[{"id":"left","x":5,"z":5,"w":10,"d":10},{"id":"hall","x":10,"z":13,"w":20,"d":6},{"id":"right","x":15,"z":5,"w":10,"d":10}],"walls":[{"x":10,"z":5,"w":0.3,"d":10},{"x":2,"z":10,"w":4,"d":0.3},{"x":10,"z":10,"w":8,"d":0.3},{"x":18,"z":10,"w":4,"d":0.3}],"doors":[{"id":"leftdoor","x":5,"z":10,"w":2,"d":0.24,"axis":"x","state":"CLOSED","progress":0.1},{"id":"rightdoor","x":15,"z":10,"w":2,"d":0.24,"axis":"x","state":"OPEN","progress":1.0}],"props":[]}
	var nav := Navigation.new()
	nav.build(data,data.doors)
	var warm := _model(data,nav)
	var source := Vector2(5,8)
	var listener := Vector2(15,8)
	var before: float = warm.travel_cost(source,listener)
	data.doors[0].destroyed = true
	var cold := _model(data,nav)
	check(warm.travel_cost(source,listener)==cold.travel_cost(source,listener) and warm.travel_cost(source,listener)<before, "A destroyed live portal invalidates its loss on an indirect route")
	for context: Dictionary in [{},{"source_floor":0.0,"listener_floor":0.0}]:
		check(warm.audibility(source,listener,30,context)==cold.audibility(source,listener,30,context), "Exact indirect audibility remains independent of cache warmth and optional context")

func _test_static_topology_cache() -> void:
	var data := _fixture()
	var nav := Navigation.new()
	nav.build(data,data.doors)
	var warm := _model(data,nav)
	var source := Vector2(8,8)
	var listener := Vector2(12,8)
	var context := {"source_floor":0.0,"listener_floor":0.0}
	var before: float = warm.travel_cost(source,listener,context)
	# Before P4 a changed nav revision invalidated only source costs. The
	# original closed-wall graph still returned 14 while a fresh portal graph
	# through the real new opening returned 5.66392993927002.
	data.walls = [{"id":"top","x":10,"z":4.9,"w":0.2,"d":9.8},{"id":"bottom","x":10,"z":13.1,"w":0.2,"d":5.8}]
	nav.build(data,data.doors)
	var cold := _model(data,nav)
	check(warm.travel_cost(source,listener,context)==cold.travel_cost(source,listener,context) and cold.travel_cost(source,listener,context)<before,"A live static opening rebuilds the actual portal topology exactly like a cold model")
	for query: Dictionary in [{},context]:
		check(warm.audibility(source,listener,12.0,query)==cold.audibility(source,listener,12.0,query),"Static topology revision preserves exact warm/cold old and contextual audibility")
	check(warm.wall_contact(Vector2(9.61,10.0),0.0).is_empty() and cold.wall_contact(Vector2(9.61,10.0),0.0).is_empty(),"A removed wall segment no longer produces amplified physical contact")
	data.walls = []
	nav.build(data,data.doors)
	cold = _model(data,nav)
	check(warm.wall_contact(Vector2(9.61,8.0),0.0).is_empty(),"Removing all live walls clears historical wall contact")
	check(warm.travel_cost(source,listener,context)==cold.travel_cost(source,listener,context) and warm.travel_cost(source,listener,context)==source.distance_to(listener),"A fully removed partition uses the exact unobstructed route")
