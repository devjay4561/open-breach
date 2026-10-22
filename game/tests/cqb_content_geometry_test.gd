extends SceneTree
const Geometry = preload("res://scripts/content_geometry_validator.gd")
const Schema = preload("res://scripts/mission_schema.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const STEP := 1.0 / 30.0
const CONTENT_IDS: Array[String] = ["SH01","SH02","SH03","SH04","SH05_PRECISION","SH05_HIGH_INTENSITY","CQB01","CQB02","CQB03","CQB04","CQB05","CQB06","CQB07","CQB08","CQB09","CQB10","CQB11","CQB12"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func fixture(depth: float = 5.6, axis: String = "x") -> Dictionary:
	var door_z := 5.0 + depth*0.5
	var data := {"schema_version":6,"id":"CONTENT_GEOMETRY","revision":1,"title":"기하 검사","seed":0,"bounds":[16.0,18.0],"focus":[8.0,5.0],
		"rooms":[{"id":"inside","x":8.0,"z":5.0,"w":5.6,"d":depth,"indoor":true},{"id":"outside","x":8.0,"z":door_z+2.8,"w":5.6,"d":5.6,"indoor":false}],
		"walls":[{"id":"north","x":8.0,"z":5.0-depth*0.5,"w":5.6,"d":0.2},{"id":"west","x":5.2,"z":5.0,"w":0.2,"d":depth},{"id":"east","x":10.8,"z":5.0,"w":0.2,"d":depth},
			{"id":"jamb_left","x":6.2,"z":door_z,"w":2.0,"d":0.2},{"id":"jamb_right","x":9.8,"z":door_z,"w":2.0,"d":0.2},
			{"id":"outside_west","x":5.2,"z":door_z+2.8,"w":0.2,"d":5.6},{"id":"outside_east","x":10.8,"z":door_z+2.8,"w":0.2,"d":5.6},{"id":"south","x":8.0,"z":door_z+5.6,"w":5.6,"d":0.2}],
		"doors":[{"id":"entry","x":8.0,"z":door_z,"w":1.6,"d":0.2,"axis":"x","state":"CLOSED","hinge_side":-1.0,"swing_sign":-1.0}],"props":[],"units":[],"enemies":[],"civilians":[],"objectives":["Geometry"],"win":[{"type":"rooms_cleared","room_ids":["inside"]}],"fail":[]}
	for index: int in range(4):
		data.units.append({"id":["alpha","bravo","charlie","delta"][index],"name":"Operator","role":"rifle","x":7.2+1.6*(index%2),"z":door_z+1.4+0.8*floori(index/2.0),"facing":-PI*0.5,"weapon":"rifle","hp":100,"ammo":30})
	data.units[0].x = 8.0
	data.units[0].z = door_z+3.5
	if axis == "z":
		data.bounds = [18.0,16.0]
		data.focus.reverse()
		for group: String in ["rooms","walls","doors","units"]:
			for object: Dictionary in data[group]:
				var x: float = object.x
				object.x = object.z
				object.z = x
				if object.has("w"):
					var width: float = object.w
					object.w = object.d
					object.d = width
		data.doors[0].axis = "z"
	return data

func _content_sources() -> void:
	check(Schema.CURRENT_SCHEMA_VERSION == 6,"P7 content uses the established v6 authoring boundary")
	for id: String in CONTENT_IDS:
		var expected := "cqb/"+id
		check(Catalog.FILES.get(id,"") == expected,"FILES exact nested path "+id)
		check(Catalog.MAPS.get(id,"") == expected,"MAPS exact nested path "+id)
		var path := "res://data/"+expected+".json"
		check(FileAccess.file_exists(path),"required source exists "+id)
		if not FileAccess.file_exists(path): continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(data is Dictionary,"source JSON object "+id)
		if not data is Dictionary: continue
		check(str(data.get("id","")) == id,"authored source ID "+id)
		var result: Dictionary = Schema.check(data)
		check(bool(result.get("ok",false)),"actual MissionSchema.check "+id+" "+str(result.get("errors",[])))
		check(int(data.schema_version) == 6,"new content stays schema6 "+id)
		check(data.enemies.size() == (4 if id.begins_with("SH") else 8),"authored room target population "+id)
		var product := 1
		for npc: Dictionary in data.enemies:
			check(npc.get("spawns",[]).size() == 2,"two authored NPC candidates "+id+" "+str(npc.id))
			product *= npc.get("spawns",[]).size()
			if npc.get("spawns",[]).size() != 2: continue
			check(float(npc.spawns[0].x) == float(npc.x) and float(npc.spawns[0].z) == float(npc.z),"default candidate exactly authored pose "+id+" "+str(npc.id))
		# Four-room houses have 16 enemy arrangements; eight-room puzzles
		# have 256. Civilian authoring has no spawn-candidate field and remains
		# a fixed singleton in the original Cartesian placement validator.
		check(product == (16 if id.begins_with("SH") else 256),"independent complete candidate population "+id)

func _pure_geometry() -> void:
	for axis: String in ["x","z"]:
		for depth: float in [5.6,2.4]:
			var data := fixture(depth,axis)
			var before := JSON.stringify(data)
			var answer: Dictionary = Geometry.validate_entry_drills(data)
			check(answer.errors.is_empty(),"actual "+axis+" geometry depth "+str(depth)+" "+str(answer.errors))
			check(JSON.stringify(data) == before,"validator preserves authored geometry and live doors")
			check(int(answer.entry_directions) == 1 and int(answer.entry_doors) == 1,"exterior entrance only targets the indoor direction")
			check(int(answer.short_guards) == (2 if depth <= 2.5 else 0),"SHORT keeps exactly two outside guards")
			check(answer.layouts.size() == 1,"successful geometry has one complete layout")
			check(answer.entry_methods.size() == 1 and answer.entry_methods[0].method == "OPEN_DOOR","ordinary layouts keep OPEN_DOOR as the first supported method")
			check(float(STEP) == 1.0/30.0,"fixed simulation step contract")
	var normal := fixture()
	var reference := Geometry.validate_entry_drills(normal)
	# A 1.6m exterior corridor cannot route a body around the selected opened
	# leaf. Destruction is a supported geometric alternative, without granting
	# any operator equipment or weakening the original portal/body checks.
	var corridor := normal.duplicate(true)
	var portal_z: float = corridor.doors[0].z
	corridor.rooms[1].z = portal_z+0.8
	corridor.rooms[1].d = 1.6
	for wall_index: int in [5,6]:
		corridor.walls[wall_index].z = portal_z+0.8
		corridor.walls[wall_index].d = 1.6
	corridor.walls[7].z = portal_z+1.6
	corridor.units[0].z = portal_z+0.8
	var destroyed_draft := Geometry.validate_entry_drills(corridor)
	check(destroyed_draft.errors.is_empty(),"narrow approach corridor retains real supported entry capacity "+str(destroyed_draft.errors))
	check(destroyed_draft.entry_methods.size() == 1 and destroyed_draft.entry_methods[0].method == "SHOTGUN_BREACH","capacity report records the actual first successful destruction method")
	if not destroyed_draft.layouts.is_empty():
		var layout: Dictionary = destroyed_draft.layouts[0]
		check(layout.method == "SHOTGUN_BREACH" and layout.slots.size() == 4,"destruction capacity still has an exact complete four-person draft")
		for own_id: String in layout.approaches:
			check(float(layout.approaches[own_id][1]) < portal_z+1.6,"local component filtering keeps every approach in the real corridor")
		check(not corridor.units[0].get("equipment",{}).has("shotgun"),"geometric capacity never injects an operator loadout")
	# The 2.4m tangent side gives independently chosen 0.9m corner margins
	# only 0.6m separation. The planner must find a legal staggered near pair
	# while preserving two entrants, two guards and swept-body portal routes.
	var narrow := normal.duplicate(true)
	narrow.rooms[0].w = 2.4
	narrow.walls[0].w = 2.4
	narrow.walls[1].x = 6.8
	narrow.walls[2].x = 9.2
	narrow.walls[3].x = 7.15
	narrow.walls[3].w = 0.7
	narrow.walls[4].x = 8.85
	narrow.walls[4].w = 0.7
	narrow.doors[0].w = 1.0
	var paired := Geometry.validate_entry_drills(narrow)
	check(paired.errors.is_empty(),"2.4m SHORT tangent finds an actual legal pair "+str(paired.errors))
	check(int(paired.short_guards) == 2,"2.4m SHORT tangent preserves outside guards")
	if not paired.layouts.is_empty():
		var slots: Array = paired.layouts[0].slots
		var first := Vector2(float(slots[0].domination[0]),float(slots[0].domination[1]))
		var second := Vector2(float(slots[1].domination[0]),float(slots[1].domination[1]))
		check(first.distance_to(second) >= 0.7-0.0001,"fallback never weakens team spacing")
		for goal: Vector2 in [first,second]:
			check(float(narrow.doors[0].z)-goal.y <= 1.8+0.0001,"fallback stays in the existing near front zone")
	# One authored room spans both sides of an internal closed partition.
	# The selected-door draft must use legal far points before that different
	# doorway rather than walking through it to the room's nominal far wall.
	var compartment := fixture(9.4)
	compartment.walls.append({"id":"partition_left","x":6.35,"z":5.0,"w":2.3,"d":0.2})
	compartment.walls.append({"id":"partition_right","x":9.65,"z":5.0,"w":2.3,"d":0.2})
	var inner := {"id":"partition_door","x":8.0,"z":5.0,"w":1.0,"d":0.2,"axis":"x","state":"CLOSED","hinge_side":-1.0,"swing_sign":-1.0}
	compartment.doors.append(inner)
	# This unit checks the selected entrance without requiring an invented
	# separate authored room for the partition. The full build audits every
	# other authored doorway independently.
	var ids := ["alpha","bravo","charlie","delta"]
	var starts: Dictionary = {}
	for rank: int in range(4): starts[ids[rank]] = [8.0+(-1.2 if rank%2 == 0 else 1.2),float(compartment.doors[0].z)+1.4+0.7*floori(rank/2.0)]
	var draft: Dictionary = Geometry.Drill.calculate(compartment,"entry",ids,starts,{"method":"OPEN_DOOR","room_id":"inside"})
	check(bool(draft.get("ok",false)),"partitioned authored room finds lawful far points "+str(draft.get("reason_code","")))
	if bool(draft.get("ok",false)):
		for rank: int in [2,3]:
			var slot: Dictionary = draft.slots[rank]
			check(float(slot.domination[1]) > 5.0,"far fallback remains in the accessible front compartment")
			check(float(compartment.doors[0].z)-float(slot.domination[1]) >= 2.52-0.0001,"far fallback preserves the original far-zone minimum")
			check(not Geometry._crossed(Vector2(float(slot.stack[0]),float(slot.stack[1])),slot.entry_route,inner),"far fallback never traverses the different partition doorway")
	var hidden := normal.duplicate(true)
	hidden.enemies = [{"id":"hidden","x":normal.doors[0].x,"z":normal.doors[0].z,"hp":0,"last_seen":{"x":99,"z":99}}]
	hidden.civilians = [{"id":"hidden_civilian","x":0,"z":0}]
	hidden["room_states"] = {"inside":{"state":"CONTACT"}}
	check(JSON.stringify(Geometry.validate_entry_drills(hidden)) == JSON.stringify(reference),"NPC placement, memory and runtime room state never change a static draft")
	seed(713)
	var expected := randf()
	seed(713)
	Geometry.validate_entry_drills(normal)
	check(randf() == expected,"static geometry consumes no global RNG")
	var elevated := normal.duplicate(true)
	elevated.rooms[0].base_height = 2.022
	elevated.doors[0].base_height = 2.022
	var raised := Geometry.validate_entry_drills(elevated)
	check(raised.errors.is_empty(),"existing Nav elevation transition remains legal "+str(raised.errors))
	if not raised.layouts.is_empty():
		for slot: Dictionary in raised.layouts[0].slots:
			check(is_equal_approx(float(slot.floor_height),2.022),"raised domination records actual floor height")
	var sealed := normal.duplicate(true)
	sealed.props = [{"id":"sealed","x":8.0,"z":5.0,"w":5.4,"d":5.4,"type":"cabinet","solid":true}]
	var impossible := Geometry.validate_entry_drills(sealed)
	check(not impossible.errors.is_empty(),"no physical alternative is rejected")
	check(impossible.layouts.is_empty(),"failed draft cannot emit a partial layout")
	var passage := normal.duplicate(true)
	passage.rooms[0].indoor = false
	var outdoors := Geometry.validate_entry_drills(passage)
	check(outdoors.errors.is_empty() and int(outdoors.entry_directions) == 0,"outdoor passage has no invented indoor room")
	check(outdoors.passages.size() == 1 and outdoors.passages[0].class == "outdoor_passage","outdoor passage receives an explicit structural classification")

func _physical_compartment() -> void:
	# Like the historic cell blocks, one logical room covers a deep building
	# while the selected portal actually enters a shallow full-width hall.
	# Its real wall and three closed portal planes, rather than a smaller
	# arbitrary far-distance constant, define the front compartment.
	var data := fixture(10.0)
	data.rooms[0].w = 11.82
	data.rooms[0].d = 9.82
	data.walls[0].w = 12.0
	data.walls[1].x = 2.0
	data.walls[2].x = 14.0
	data.walls[3].x = 4.6
	data.walls[3].w = 5.2
	data.walls[4].x = 11.4
	data.walls[4].w = 5.2
	data.walls.append({"id":"partition_left","x":4.6,"z":7.0,"w":5.2,"d":0.2})
	data.walls.append({"id":"partition_right","x":11.4,"z":7.0,"w":5.2,"d":0.2})
	var partition := {"id":"partition","x":8.0,"z":7.0,"w":1.6,"d":0.2,"axis":"x","state":"CLOSED","hinge_side":-1.0,"swing_sign":-1.0}
	data.doors.append(partition)
	var rect := Geometry.Drill._room_rect(data.rooms[0])
	var center := Vector2(8.0,10.0)
	var proof: Dictionary = Geometry.Drill._portal_frame(data,data.doors[0],rect,center,Vector2.UP,Vector2.RIGHT)
	check(not proof.is_empty(),"whole tangent barrier certifies a physical compartment")
	if not proof.is_empty():
		check(is_equal_approx(float(proof.barrier_depth),3.0),"effective depth comes from the actual partition plane")
		# The intact door leaf is 0.226m thick, slightly thicker than the
		# 0.2m wall. The physical certificate must stop at its actual face.
		check(is_equal_approx(float(proof.rect.position.y),7.113) and is_equal_approx(float(proof.rect.end.y),9.91),"effective frame stops at the actual inner obstacle face")
		check(rect.encloses(proof.rect),"effective compartment is contained by authored room")
		check(minf(proof.rect.size.x,proof.rect.size.y)>2.5,"2.81m physical hall keeps all four entrants")
	var ids := ["alpha","bravo","charlie","delta"]
	var starts: Dictionary = {}
	for rank: int in range(4): starts[ids[rank]]=[8.0+(-1.2 if rank%2==0 else 1.2),11.4+0.7*floori(rank/2.0)]
	var before := JSON.stringify(data)
	var draft: Dictionary = Geometry.Drill.calculate(data,"entry",ids,starts,{"room_id":"inside","method":"OPEN_DOOR"})
	check(bool(draft.get("ok",false)),"physical compartment creates a complete actual draft "+str(draft.get("reason_code","")))
	check(JSON.stringify(data)==before,"compartment proof never rewrites historical authoring")
	if bool(draft.get("ok",false)):
		check(draft.has("effective_frame") and not draft.short_room and draft.entry_count==4,"effective frame retains four-person standard classification")
		var forecast := Geometry.Nav.new()
		var forecast_doors: Array = data.doors.duplicate(true)
		forecast_doors[0].state="OPEN"
		forecast_doors[0].progress=1.0
		forecast.build(data,forecast_doors)
		var goals: Array[Vector2] = []
		for rank: int in range(4):
			var slot: Dictionary=draft.slots[rank]
			var goal:=Geometry._vector(slot.domination)
			check(bool(slot.entry),"every standard slot enters the actual compartment")
			check(proof.rect.grow(-Geometry.Nav.RADIUS).has_point(goal),"goal remains inside physical compartment")
			check(Geometry._route(forecast,Geometry._vector(slot.stack),slot.entry_route),"compartment entry keeps whole-body segment clearance")
			check(Geometry._crossed(Geometry._vector(slot.stack),slot.entry_route,data.doors[0]),"compartment route crosses the selected portal")
			check(not Geometry._crossed(Geometry._vector(slot.stack),slot.entry_route,partition),"compartment route never uses the partition portal")
			if rank>=2: check(10.0-goal.y>=1.8-0.0001,"far slots preserve the unchanged frame-based far-zone formula")
			for prior: Vector2 in goals: check(prior.distance_to(goal)>=0.7-0.0001,"compartment keeps 0.7m separation")
			goals.append(goal)
	# A door elsewhere in a bay or a wall with a real unclosed gap cannot
	# certify a smaller room. The original complete authored frame remains.
	var isolated:=data.duplicate(true)
	isolated.walls=isolated.walls.slice(0,8)
	var isolated_proof: Dictionary=Geometry.Drill._portal_frame(isolated,isolated.doors[0],rect,center,Vector2.UP,Vector2.RIGHT)
	check(isolated_proof.is_empty() or float(isolated_proof.barrier_depth)>=9.8,"isolated same-axis doorway cannot truncate the logical room at its plane")
	var gap:=data.duplicate(true)
	# The previous raw 0.25m slit was narrower than a 0.46m actor. Use a
	# genuinely traversable 0.6m opening to retain this rejection invariant.
	gap.walls[8].w=4.0
	var gap_proof: Dictionary=Geometry.Drill._portal_frame(gap,gap.doors[0],rect,center,Vector2.UP,Vector2.RIGHT)
	check(gap_proof.is_empty() or float(gap_proof.barrier_depth)>=9.8,"a genuine gap prevents full-tangent barrier certification at that plane")
	var gap_nav:=Geometry.Nav.new()
	gap_nav.build(gap,gap.doors.duplicate(true))
	check(gap_nav.segment_clear(Vector2(6.9,6.4),Vector2(6.9,7.6),Geometry.Nav.RADIUS),"the genuine 0.6m gap admits an actual whole-body route")
	var body_gap:=data.duplicate(true)
	body_gap.walls[9].x=11.625
	body_gap.walls[9].w=4.75
	# A 0.45m raw slit is physically sealed only by the actual CLOSED leaf
	# and wall together. A virtual different-portal plane keeps its raw width.
	for axis: String in ["x","z"]:
		var rotated:=body_gap.duplicate(true)
		var frame_center:=center
		var frame_inward:=Vector2.UP
		var frame_across:=Vector2.RIGHT
		if axis=="z":
			for group: String in ["rooms","walls","doors"]:
				for object: Dictionary in rotated[group]:
					var x: float=object.x
					object.x=object.z
					object.z=x
					var w: float=object.w
					object.w=object.d
					object.d=w
			for portal: Dictionary in rotated.doors: portal.axis="z"
			frame_center=Vector2(center.y,center.x)
			frame_inward=Vector2.LEFT
			frame_across=Vector2.DOWN
		var rotated_rect:=Geometry.Drill._room_rect(rotated.rooms[0])
		var closed_proof: Dictionary=Geometry.Drill._portal_frame(rotated,rotated.doors[0],rotated_rect,frame_center,frame_inward,frame_across)
		check(not closed_proof.is_empty() and is_equal_approx(float(closed_proof.get("barrier_depth",0.0)),3.0),"physical actor diameter certifies the closed 0.45m slit on axis "+axis)
		# When the leaf is absent, the portal's raw edge is 8.8 and the
		# wall's actor-safe edge is 9.02. Check a route between both edges.
		var first:=Vector2(8.91,6.4) if axis=="x" else Vector2(6.4,8.91)
		var last:=Vector2(8.91,7.6) if axis=="x" else Vector2(7.6,8.91)
		var physical_nav:=Geometry.Nav.new()
		physical_nav.build(rotated,rotated.doors.duplicate(true))
		check(not physical_nav.segment_clear(first,last,Geometry.Nav.RADIUS),"the closed 0.45m slit physically blocks the unchanged actor radius on axis "+axis)
		for condition: String in ["OPEN","DESTROYED","AJAR"]:
			var open_gap:=rotated.duplicate(true)
			open_gap.doors[1].state="OPEN" if condition=="OPEN" else "CLOSED"
			open_gap.doors[1].progress=1.0 if condition=="OPEN" else (0.4 if condition=="AJAR" else 0.0)
			open_gap.doors[1].destroyed=condition=="DESTROYED"
			var open_proof: Dictionary=Geometry.Drill._portal_frame(open_gap,open_gap.doors[0],rotated_rect,frame_center,frame_inward,frame_across)
			check(open_proof.is_empty() or float(open_proof.barrier_depth)>=9.8,"raw different-portal width cannot seal the actual "+condition+" side gap on axis "+axis)
			if condition!="AJAR":
				physical_nav.build(open_gap,open_gap.doors.duplicate(true))
				check(physical_nav.segment_clear(first,last,Geometry.Nav.RADIUS),"the actual "+condition+" side gap admits the unchanged whole-body route on axis "+axis)
	var blocked:=data.duplicate(true)
	blocked.props=[{"id":"sealed_hall","x":8.0,"z":8.5,"w":11.5,"d":2.9,"type":"cabinet","solid":true}]
	var rejected: Dictionary=Geometry.Drill.calculate(blocked,"entry",ids,starts,{"room_id":"inside","method":"OPEN_DOOR"})
	check(not bool(rejected.get("ok",false)) and rejected.get("slots",[]).is_empty(),"effective frame still rejects a physically sealed compartment atomically")

func _component_filter() -> void:
	var data:=fixture()
	data.walls.append({"id":"closed_partition","x":8.0,"z":5.0,"w":5.6,"d":0.2})
	var plain:=Geometry.Nav.new()
	plain.build(data,data.doors.duplicate(true))
	var planned:=Geometry.Drill.PlanningNavigation.new()
	planned.build(data,data.doors.duplicate(true))
	var source:=Vector2(6.0,6.0)
	var target:=Vector2(6.0,4.0)
	var expected: Array=plain.path(source,target)
	check(expected.is_empty(),"reference Nav rejects the actually disconnected compartment")
	check(planned.path(source,target)==expected,"component prefilter preserves the original disconnected result")
	check(planned._next_component>1,"disconnected proof completes and caches a whole permissive component")
	var previous_components: int=planned._next_component
	check(planned.path(source,Vector2(7.0,4.0)).is_empty(),"another target in the same sealed room remains disconnected")
	check(planned._next_component==previous_components,"the complete component proof is reused locally")
	check(planned.path(target,source).is_empty(),"completed target labels also preserve the reversed disconnected query")
	var first: Array=planned.path(source,Vector2(7.0,6.0))
	check(JSON.stringify(first)==JSON.stringify(plain.path(source,Vector2(7.0,6.0))),"direct full-body segment preserves exact reference route")
	first[0][0]=999.0
	check(JSON.stringify(planned.path(source,Vector2(7.0,6.0)))==JSON.stringify(plain.path(source,Vector2(7.0,6.0))),"returned routes never share mutable arrays with the component cache")
	var connected:=fixture()
	connected.props=[{"id":"cabinet","x":8.0,"z":5.0,"w":0.8,"d":1.2,"type":"cabinet","solid":true}]
	plain=Geometry.Nav.new()
	plain.build(connected,connected.doors.duplicate(true))
	planned=Geometry.Drill.PlanningNavigation.new()
	planned.build(connected,connected.doors.duplicate(true))
	source=Vector2(6.0,5.0)
	target=Vector2(10.0,5.0)
	var route: Array=planned.path(source,target)
	check(not route.is_empty(),"connected obstacle detour still delegates to actual Nav")
	check(JSON.stringify(route)==JSON.stringify(plain.path(source,target)),"connected A* path and tie order remain byte identical")
	check(Geometry._route(plain,source,route),"connected output retains every whole-body segment check")
	check(planned._next_component==1,"partial connected floods cannot be cached as complete components")
	check(planned._path_memo.size()==1,"only the actual non-direct Nav result enters the local exact endpoint memo")
	var expected_route:=JSON.stringify(route)
	var expected_retry: bool=planned._needs_edge_retry
	route[0][0]=999.0
	planned._needs_edge_retry=not expected_retry
	check(JSON.stringify(planned.path(source,target))==expected_route,"memo stores and returns independent route arrays")
	check(planned._needs_edge_retry==expected_retry,"memo preserves the original Nav retry side effect")
	var reversed: Array=planned.path(target,source)
	check(JSON.stringify(reversed)==JSON.stringify(plain.path(target,source)),"reversed exact endpoints preserve their own original Nav route")
	check(planned._path_memo.size()==2,"memo endpoint keys distinguish both query directions")
	var memo_size: int=planned._path_memo.size()
	check(JSON.stringify(planned.path(source,target,["entry"]))==JSON.stringify(plain.path(source,target,["entry"])),"hypothetical open queries retain the original Nav implementation")
	check(planned._path_memo.size()==memo_size,"hypothetical open queries never read or add a baseline route memo")
	planned._path_memo[Vector4(source.x,source.y,target.x,target.y)].route[0][0]=888.0
	planned.doors[0].progress=0.4
	plain.doors[0].progress=0.4
	check(JSON.stringify(planned.path(source,target))==JSON.stringify(plain.path(source,target)),"an exact door pose change invalidates routes without requiring a caller dirty signal")
	check(planned._memo_pose_revision==planned._exact_door_revision,"memo epochs track the same exact actual door pose revision as Nav")
	# Corrupt only this test's private stored copy. An actual dirty/revision
	# boundary must discard it before it can affect any returned geometry.
	planned._path_memo[Vector4(source.x,source.y,target.x,target.y)].route[0][0]=777.0
	planned.invalidate_dynamic()
	check(JSON.stringify(planned.path(source,target))==expected_route,"dirty geometry invalidates every remembered route before lookup")
	check(planned._path_memo.size()==1,"dirty geometry starts a new local memo epoch")
	var changed:=connected.duplicate(true)
	changed.props[0].d=2.2
	plain.build(changed,changed.doors.duplicate(true))
	planned.build(changed,changed.doors.duplicate(true))
	check(JSON.stringify(planned.path(source,target))==JSON.stringify(plain.path(source,target)),"a replaced grid and revision retain only the new original Nav result")
	# These components exceed the optimization budget. Both a connected
	# detour and a genuinely disconnected result must still come from the
	# complete original Nav query, without cached partial component labels.
	var large: Dictionary={"bounds":[48.0,24.0],"rooms":[],"walls":[],"doors":[],"props":[{"id":"large_detour","type":"cabinet","x":24.0,"z":12.0,"w":0.8,"d":12.0,"solid":true}]}
	plain=Geometry.Nav.new()
	planned=Geometry.Drill.PlanningNavigation.new()
	plain.build(large,[])
	planned.build(large,[])
	source=Vector2(12.0,12.0)
	target=Vector2(36.0,12.0)
	var large_expected: Array=plain.path(source,target)
	check(not large_expected.is_empty(),"reference large component retains a genuine connected detour")
	check(JSON.stringify(planned.path(source,target))==JSON.stringify(large_expected),"bounded optional flood retains the full exact connected Nav result")
	check(planned._next_component==1,"abandoned connected flood stores no partial component labels")
	check(planned._path_memo.size()==1,"the bounded flood still executes and remembers the original actual Nav query")
	large.walls=[{"id":"sealed_large_partition","x":24.0,"z":12.0,"w":0.2,"d":24.0}]
	large.props=[]
	plain.build(large,[])
	planned.build(large,[])
	large_expected=plain.path(source,target)
	check(large_expected.is_empty(),"reference Nav rejects a genuinely disconnected large component")
	check(planned.path(source,target)==large_expected,"the optimization bound cannot accept a disconnected physical route")
	check(planned._next_component==1,"an abandoned disconnected flood also stores no partial labels")
	check(planned._path_memo.size()==1,"disconnected large query uses the original complete empty result")
	check(planned._needs_edge_retry==plain._needs_edge_retry,"bounded fallback preserves original Nav retry state for a large disconnected query")

func _immutable_geometry_scope() -> void:
	for axis: String in ["x","z"]:
		for pose: String in ["CLOSED","OPEN","DESTROYED","AJAR"]:
			var data:=fixture(5.6,axis)
			var door: Dictionary=data.doors[0]
			door.state="OPEN" if pose=="OPEN" else "CLOSED"
			door.progress=1.0 if pose=="OPEN" else (0.4 if pose=="AJAR" else 0.0)
			door.destroyed=pose=="DESTROYED"
			door.hinge_side=1.0 if pose in ["OPEN","AJAR"] else -1.0
			door.swing_sign=1.0 if pose in ["OPEN","DESTROYED"] else -1.0
			data.props=[{"id":"rotated_bucket_corner","type":"cabinet","x":float(data.focus[0]),"z":float(data.focus[1]),"w":0.8,"d":1.2,"rotation":0.7,"solid":true}]
			if pose in ["OPEN","AJAR"]:
				data.rooms[0].base_height=2.022
				door.base_height=2.022
			var before:=JSON.stringify(data)
			var plain:=Geometry.Nav.new()
			var scoped:=Geometry.Nav.new()
			plain.build(data,data.doors.duplicate(true))
			scoped.build(data,data.doors.duplicate(true))
			scoped.begin_geometry_scope()
			var source:=Vector2(8.0,8.8) if axis=="x" else Vector2(8.8,8.0)
			var targets: Array[Vector2]=[Vector2(6.0,5.0),Vector2(10.0,5.0),Vector2(7.5,4.5)]
			for raw: Vector2 in targets:
				var target:=raw if axis=="x" else Vector2(raw.y,raw.x)
				check(scoped.walkable(target)==plain.walkable(target),"immutable scope preserves actual body/floor walkability "+axis+" "+pose)
				for padding: float in [0.0,Geometry.Nav.RADIUS,Geometry.Nav.RADIUS+0.07]:
					check(scoped.segment_clear(source,target,padding)==plain.segment_clear(source,target,padding),"immutable scope preserves rotated/cutaway obstacle clearance at padding "+str(padding)+" "+axis+" "+pose)
				var original: Array=plain.path(source,target)
				check(JSON.stringify(scoped.path(source,target))==JSON.stringify(original),"immutable scope preserves original full route bytes "+axis+" "+pose)
				check(scoped._needs_edge_retry==plain._needs_edge_retry,"immutable scope preserves original Nav retry state "+axis+" "+pose)
			check(JSON.stringify(data)==before,"scoped Nav compiles only its owned walls and preserves source dictionaries")

func _shared_authored_baseline() -> void:
	var ids := ["alpha","bravo","charlie","delta"]
	for axis: String in ["x","z"]:
		for depth: float in [5.6,2.4]:
			var data := fixture(depth,axis)
			# Environment only affects lighting; the private baseline serves movement.
			data.environment={"lighting":0.4}
			var before := JSON.stringify(data)
			var baseline := Geometry.Drill.PlanningNavigation.new()
			baseline.build(data,data.doors.duplicate(true))
			baseline.begin_geometry_scope()
			var revision: int=baseline.revision
			var poses := JSON.stringify(baseline.doors)
			var starts: Dictionary={}
			for unit: Dictionary in data.units: starts[unit.id]=[unit.x,unit.z]
			for method: String in ["OPEN_DOOR","SHOTGUN_BREACH","BREACH_DOOR"]:
				var options := {"method":method,"room_id":"inside","operator_id":"alpha"}
				var fresh: Dictionary=Geometry.Drill.calculate(data,"entry",ids,starts,options)
				var shared: Dictionary=Geometry.Drill._calculate_with_baseline(data,"entry",ids,starts,options,baseline)
				check(bool(fresh.get("ok",false)),"reference draft is complete for shared baseline "+axis+" "+str(depth)+" "+method)
				check(JSON.stringify(shared)==JSON.stringify(fresh),"shared immutable authored baseline preserves whole draft bytes "+axis+" "+str(depth)+" "+method)
				check(baseline.revision==revision and JSON.stringify(baseline.doors)==poses,"private sharing never rebuilds, rescopes or changes authored door poses")
				var expected := JSON.stringify(shared)
				if bool(shared.get("ok",false)) and not shared.slots[0].stack_route.is_empty(): shared.slots[0].stack_route[0][0]=999.0
				check(JSON.stringify(Geometry.Drill._calculate_with_baseline(data,"entry",ids,starts,options,baseline))==expected,"a caller-mutated returned route never poisons the shared baseline")
			check(JSON.stringify(data)==before,"shared baseline leaves all authored/static/environment inputs unchanged")
			var invalid: Dictionary=starts.duplicate(true)
			invalid.alpha=[-1.0,0.0]
			check(Geometry.Drill._calculate_with_baseline(data,"entry",ids,invalid,{},baseline)==Geometry.Drill.calculate(data,"entry",ids,invalid),"shared private path retains input validation and atomic error shape")

func _exact_leaf_sweep_samples() -> void:
	for axis: String in ["x","z"]:
		for hinge: float in [-1.0,1.0]:
			for swing: float in [-1.0,1.0]:
				for width: float in [0.8,1.6,2.4]:
					var door: Dictionary={"id":"sweep","axis":axis,"x":8.0,"z":8.0,"w":width if axis=="x" else 0.2,"d":0.2 if axis=="x" else width,"state":"CLOSED","progress":0.4,"hinge_side":hinge,"swing_sign":swing}
					var before:=JSON.stringify(door)
					var samples: Array=Geometry.Drill._sweep_obstacles(door)
					check(samples.size()==65,"owned leaf cache retains every original pose sample")
					for sample: int in range(65): check(samples[sample]==Geometry.Door.movement_obstacle(door,float(sample)/64.0),"leaf sample transform is exact and preserves 0..64 order")
					for offset: Vector2 in [Vector2(-2.0,-2.0),Vector2(-1.0,0.0),Vector2(-0.25,0.1),Vector2(0.0,0.0),Vector2(0.25,0.3),Vector2(1.0,0.0),Vector2(1.0,1.0),Vector2(2.0,2.0)]:
						var point:=Vector2(8.0,8.0)+offset
						check(Geometry.Drill._sweep_clear(door,point,samples)==Geometry.Drill._sweep_clear(door,point),"precomputed leaf sweep retains exact whole-body collision at the original sample order")
					check(JSON.stringify(door)==before,"leaf samples never mutate an authored door or inject private fields")
					door.destroyed=true
					check(Geometry.Drill._sweep_obstacles(door).is_empty() and Geometry.Drill._sweep_clear(door,Vector2(8.0,8.0)),"destroyed leaves preserve original early-clear behavior")

func _private_entry_navigation_context() -> void:
	var ids := ["alpha","bravo","charlie","delta"]
	for axis: String in ["x","z"]:
		for depth: float in [5.6,2.4]:
			var data := fixture(depth,axis)
			data.rooms[1].indoor=true
			var before:=JSON.stringify(data)
			var baseline:=Geometry.Drill.PlanningNavigation.new()
			baseline.build(data,data.doors.duplicate(true))
			baseline.begin_geometry_scope()
			var method_contexts: Dictionary={}
			for method: String in ["OPEN_DOOR","SHOTGUN_BREACH","BREACH_DOOR"]:
				var context: Dictionary={}
				method_contexts[method]=context
				for pattern: int in range(3):
					var starts: Dictionary={}
					for index: int in range(data.units.size()):
						var unit: Dictionary=data.units[index]
						var point:=Vector2(unit.x,unit.z)
						if pattern==1: point+=Vector2(0.25,0.0) if axis=="x" else Vector2(0.0,0.25)
						if pattern==2:
							point=Vector2(7.2+1.6*(index%2),float(data.doors[0].z)-1.0-0.7*floori(index/2.0)) if axis=="x" else Vector2(float(data.doors[0].x)-1.0-0.7*floori(index/2.0),7.2+1.6*(index%2))
						starts[unit.id]=[point.x,point.y]
					var options: Dictionary={"method":method,"operator_id":"alpha","room_id":"outside" if pattern==2 else "inside"}
					var expected: Dictionary=Geometry.Drill.calculate(data,"entry",ids,starts,options)
					var actual: Dictionary=Geometry.Drill._calculate_with_baseline(data,"entry",ids,starts,options,baseline,context)
					check(JSON.stringify(actual)==JSON.stringify(expected),"same-door exact-method forecast/side context preserves whole draft or atomic failure across changed approaches and both room directions")
					check(context.size()<=2,"the exact-method context holds at most a forecast and portal-plane Nav")
					if context.has("forecast") and context.has("side"):
						check(context.forecast!=context.side and context.forecast!=baseline and context.side!=baseline,"forecast, side and authored baseline are distinct owned geometry")
						var revisions: Array=[context.forecast.revision,context.side.revision]
						var poses: Array=[JSON.stringify(context.forecast.doors),JSON.stringify(context.side.doors)]
						var saved:=JSON.stringify(actual)
						if bool(actual.get("ok",false)) and not actual.slots[0].entry_route.is_empty(): actual.slots[0].entry_route[0][0]=999.0
						check(JSON.stringify(Geometry.Drill._calculate_with_baseline(data,"entry",ids,starts,options,baseline,context))==saved,"context caches never alias a caller-mutated draft path")
						check([context.forecast.revision,context.side.revision]==revisions and [JSON.stringify(context.forecast.doors),JSON.stringify(context.side.doors)]==poses,"context reuse never changes geometry, rebuilds or door poses")
				var invalid: Dictionary={"alpha":[-1.0,0.0]}
				check(Geometry.Drill._calculate_with_baseline(data,"entry",ids,invalid,{},baseline,context)==Geometry.Drill.calculate(data,"entry",ids,invalid),"cached geometry never bypasses actual command approach validation")
			check(method_contexts.size()==3,"at most three exact-method context pairs remain inside one door")
			check(JSON.stringify(data)==before,"private contexts never inject Nav or cache metadata into source or returned authoring")

func _compiled_owned_door_geometry() -> void:
	for axis: String in ["x","z"]:
		for pose: String in ["CLOSED","OPEN","DESTROYED","AJAR"]:
			for angle: float in [-PI/6.0,0.0,PI/4.0]:
				var data:=fixture(5.6,axis)
				var door: Dictionary=data.doors[0]
				door.state="OPEN" if pose=="OPEN" else "CLOSED"
				door.progress=1.0 if pose=="OPEN" else (0.4 if pose=="AJAR" else 0.0)
				door.destroyed=pose=="DESTROYED"
				door.rotation=angle
				var input:=JSON.stringify(data)
				var plain:=Geometry.Nav.new()
				var planned:=Geometry.Drill.PlanningNavigation.new()
				plain.build(data,data.doors.duplicate(true))
				planned.build(data,data.doors.duplicate(true))
				plain.begin_geometry_scope()
				planned.begin_geometry_scope()
				var points: Array[Vector2]=[Vector2(door.x,door.z),Vector2(door.x,door.z)+Vector2(0.0,0.3),Vector2(door.x,door.z)+Vector2(-0.8,0.0),Vector2(door.x,door.z)+Vector2(1.2,1.0)]
				for movement: bool in [false,true]:
					var raw: Array=plain._door_blockers([],movement)
					var prepared: Array=planned._door_blockers([],movement)
					var stripped: Array=prepared.duplicate(true)
					for blocker: Dictionary in stripped: blocker.erase("_compiled_geometry")
					check(stripped==raw,"compiled private blockers preserve exact raw order and geometry")
					check(is_same(prepared,planned._door_blockers([],movement)),"same pose epoch reuses only detached compiled obstacles")
					for index: int in range(prepared.size()):
						check(not is_same(prepared[index],raw[index]),"compilation never mutates an owned raw door or original leaf cache")
						for padding: float in [0.0,0.1,Geometry.Nav.RADIUS,Geometry.Nav.RADIUS+0.02,0.46]:
							for point: Vector2 in points:
								check(planned._contains(prepared[index],point,padding)==plain._contains(raw[index],point,padding),"compiled exact contains preserves every original padding and rotated pose")
								check(planned._segment_obstacle(point,points[0],prepared[index],padding)==plain._segment_obstacle(point,points[0],raw[index],padding),"compiled exact segment retains the original collision predicate")
				check(planned._door_blockers(["entry"],true).size()==plain._door_blockers(["entry"],true).size(),"hypothetical opening retains its distinct exact blocker list")
				check(JSON.stringify(data)==input and JSON.stringify(planned.doors)==JSON.stringify(plain.doors),"compilation keeps all external and owned raw door bytes unchanged")
				if pose=="CLOSED" and angle==0.0:
					var prior: Array=planned._door_blockers([],true)
					plain.doors[0].x+=1.0
					planned.doors[0].x+=1.0
					plain.invalidate_sensory_pose()
					planned.invalidate_sensory_pose()
					check(planned._compiled_door_blockers.is_empty(),"pose invalidation discards compiled clones before the next query")
					check(not is_same(prior,planned._door_blockers([],true)),"changed actual pose produces a new detached blocker list")
					for point: Vector2 in points: check(planned.walkable(point)==plain.walkable(point),"changed CLOSED raw gate keeps actual exact body clearance")
					planned.doors[0].rotation=PI/4.0
					plain.doors[0].rotation=PI/4.0
					planned.invalidate_sensory_pose()
					plain.invalidate_sensory_pose()
					for point: Vector2 in points: check(planned.segment_clear(point,points[0],Geometry.Nav.RADIUS)==plain.segment_clear(point,points[0],Geometry.Nav.RADIUS),"invalidation refreshes raw gate rotation even outside the old scalar pose key")
				planned.begin_geometry_scope()
				check(planned._compiled_door_blockers.is_empty(),"a new immutable scope drops every prior compiled list")
				planned.end_geometry_scope()
				plain.end_geometry_scope()
				check(planned._door_blockers([],true)==plain._door_blockers([],true),"unscoped PlanningNavigation retains the original raw/default branch")

func _offline_pattern_order() -> void:
	check(Geometry.APPROACH_PATTERNS==[2,3,0,1,4,5],"offline capacity prefers the already supported full-jamb lanes first")
	check(Geometry.APPROACH_PATTERNS.size()==6,"offline reordering preserves the complete six-candidate population")
	for pattern: int in range(6): check(Geometry.APPROACH_PATTERNS.count(pattern)==1,"every original approach pattern remains exactly once")
	# This is an intentional offline search preference change. It can select
	# different reported origins/routes while every original physical test and
	# runtime RoomDrill/public API remain unchanged; report byte equality is
	# not an acceptance criterion for that new preference.

func _exact_physical_predicate_memo() -> void:
	for axis: String in ["x","z"]:
		for pose: String in ["CLOSED","OPEN","AJAR","DESTROYED"]:
			var data:=fixture(5.6,axis)
			data.props=[{"id":"rotated","type":"box","x":6.4,"z":5.0,"w":0.8,"d":0.4,"rotation":PI/6.0,"cover":"full"}]
			var door: Dictionary=data.doors[0]
			door.state="OPEN" if pose=="OPEN" else "CLOSED"
			door.progress=1.0 if pose=="OPEN" else (0.4 if pose=="AJAR" else 0.0)
			door.destroyed=pose=="DESTROYED"
			var before:=JSON.stringify(data)
			var plain:=Geometry.Nav.new()
			var planned:=Geometry.Drill.PlanningNavigation.new()
			plain.build(data,data.doors.duplicate(true))
			planned.build(data,data.doors.duplicate(true))
			plain.begin_geometry_scope()
			planned.begin_geometry_scope()
			var points: Array[Vector2]=[Vector2(door.x,door.z),Vector2(door.x,door.z)+Vector2(-1.2,0.0),Vector2(door.x,door.z)+Vector2(0.0,1.4),Vector2(6.4,5.0),Vector2(0.05,0.05)]
			for assumed: Array in [[],["entry"],["entry","ghost"],["ghost","entry"]]:
				for point: Vector2 in points:
					var expected: bool=plain.walkable(point,assumed)
					check(planned.walkable(point,assumed)==expected,"scoped exact point memo preserves original floor, rotated furniture and every door pose")
					var count:=planned._walkable_memo.size()
					check(planned.walkable(point,assumed)==expected and planned._walkable_memo.size()==count,"same point and ordered opened IDs reuse true and false original predicates")
				for padding: float in [0.0,0.1,Geometry.Nav.RADIUS,Geometry.Nav.RADIUS+0.02,0.23000000001]:
					for point: Vector2 in points:
						var expected: bool=plain.segment_clear(point,points[2],padding,assumed)
						check(planned.segment_clear(point,points[2],padding,assumed)==expected,"scoped segment memo preserves ordered endpoints and original float padding")
						var count:=planned._segment_memo.size()
						check(planned.segment_clear(point,points[2],padding,assumed)==expected and planned._segment_memo.size()==count,"same segment predicate hit keeps the exact original boolean")
						check(planned.segment_clear(points[2],point,padding,assumed)==plain.segment_clear(points[2],point,padding,assumed),"reversed endpoint key remains independently checked")
			check(planned._walkable_memo.has([points[0],["entry","ghost"]]) and planned._walkable_memo.has([points[0],["ghost","entry"]]),"ordered assumed-open lists are stored as separate exact keys")
			check(planned._segment_memo.has([Vector4(points[0].x,points[0].y,points[2].x,points[2].y),Geometry.Nav.RADIUS,[]]) and planned._segment_memo.has([Vector4(points[0].x,points[0].y,points[2].x,points[2].y),0.23000000001,[]]),"padding retains original float precision without Vector float32 conversion")
			var mutable: Array=["entry","owned_key"]
			planned.walkable(points[0],mutable)
			mutable[1]="changed"
			check(planned._walkable_memo.has([points[0],["entry","owned_key"]]),"a caller-edited assumed list cannot change a saved detached key")
			var invalid: Vector2=Vector2(NAN,0.0)
			var counts: Array=[planned._walkable_memo.size(),planned._segment_memo.size()]
			check(planned.walkable(invalid)==plain.walkable(invalid),"nonfinite points preserve the original predicate without a memo key")
			check(planned.segment_clear(points[0],points[2],NAN)==plain.segment_clear(points[0],points[2],NAN),"nonfinite padding preserves the original segment predicate")
			check([planned._walkable_memo.size(),planned._segment_memo.size()]==counts,"nonfinite fallback does not publish a query record")
			planned.end_geometry_scope()
			plain.end_geometry_scope()
			check(planned._walkable_memo.is_empty() and planned._segment_memo.is_empty(),"ending an immutable scope clears both predicate maps")
			check(planned.walkable(points[0])==plain.walkable(points[0]) and planned._walkable_memo.is_empty(),"outside a scope the original walkable branch remains uncached")
			check(planned.segment_clear(points[0],points[2],Geometry.Nav.RADIUS)==plain.segment_clear(points[0],points[2],Geometry.Nav.RADIUS) and planned._segment_memo.is_empty(),"outside a scope the original segment branch remains uncached")
			plain.doors[0].x+=0.4
			planned.doors[0].x+=0.4
			plain.invalidate_sensory_pose()
			planned.invalidate_sensory_pose()
			plain.begin_geometry_scope()
			planned.begin_geometry_scope()
			for point: Vector2 in points: check(planned.walkable(point)==plain.walkable(point),"new actual door epoch recomputes the exact point predicate")
			var revision: int=planned.revision
			planned.revision+=1
			planned.walkable(points[0])
			check(planned._walkable_memo.size()==1 and int(planned._physical_query_epoch[0])==revision+1,"revision change clears previous point and segment records before lookup")
			planned._grid_dirty=not planned._grid_dirty
			planned.segment_clear(points[0],points[2],Geometry.Nav.RADIUS)
			check(planned._walkable_memo.is_empty() and planned._segment_memo.size()==1,"a changed grid dirty epoch drops old records while preserving physical result")
			planned._walkable_memo[Vector2(-100.0,-100.0)]=false
			planned.begin_geometry_scope()
			check(planned._walkable_memo.is_empty() and planned._segment_memo.is_empty(),"new begin always clears memo even if only static walls changed")
			planned.walkable(points[0])
			planned.rebuild()
			check(planned._walkable_memo.is_empty() and planned._segment_memo.is_empty(),"original rebuild invalidation clears all private predicate records")
			planned.walkable(points[0])
			planned.build(data,data.doors.duplicate(true))
			check(planned._walkable_memo.is_empty() and planned._segment_memo.is_empty(),"building new owned geometry does not retain old query records")
			check(JSON.stringify(data)==before,"physical query caches do not escape into original geometry or actors")
	var bounded:=Geometry.Drill.PlanningNavigation.new()
	var tiny:=fixture()
	bounded.build(tiny,tiny.doors.duplicate(true))
	bounded.begin_geometry_scope()
	for index: int in range(bounded.PHYSICAL_QUERY_MEMO_LIMIT): bounded._walkable_memo[Vector2(index,-10.0)]=false
	bounded.walkable(Vector2(8.0,5.0))
	check(bounded._walkable_memo.size()==1 and bounded._segment_memo.is_empty(),"bounded eviction abandons only memo reuse and still returns the original predicate")

func run() -> void:
	_content_sources()
	_pure_geometry()
	_physical_compartment()
	_component_filter()
	_immutable_geometry_scope()
	_shared_authored_baseline()
	_exact_leaf_sweep_samples()
	_private_entry_navigation_context()
	_compiled_owned_door_geometry()
	_offline_pattern_order()
	_exact_physical_predicate_memo()
	for failure: String in failures: printerr("FAIL "+failure)
	print("BREACH_CQB_CONTENT_GEOMETRY_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
