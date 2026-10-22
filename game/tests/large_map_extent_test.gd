extends SceneTree
const Navigation = preload("res://scripts/navigation.gd")
const Schema = preload("res://scripts/mission_schema.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/historical/H02.json"))
	check(float(map.bounds[0])==78.0 and float(map.bounds[1])==80.0,"Terminal sector removes the empty airport apron")
	var nav := Navigation.new()
	var before := Time.get_ticks_usec()
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	nav.build(map,map.doors)
	check(nav.grid==null,"Airport map keeps the live graph lazy until movement needs it")
	var origin := Vector2(float(map.units[0].x),float(map.units[0].z))
	var target := origin
	for actor: Dictionary in map.enemies+map.civilians:
		var candidate := Vector2(float(actor.x),float(actor.z))
		if origin.distance_squared_to(candidate)>origin.distance_squared_to(target): target=candidate
	var opened: Array = []
	for door: Dictionary in map.doors: opened.append(door.id)
	var route: Array = nav.path(origin,target,opened)
	check(not route.is_empty(),"Full airport route reaches a real authored target")
	var previous := origin
	var length := 0.0
	for raw: Array in route:
		var current := Vector2(float(raw[0]),float(raw[1]))
		check(nav.segment_clear(previous,current,Navigation.RADIUS,opened),"Full airport route preserves actual actor clearance")
		length += previous.distance_to(current)
		previous=current
	check(length>10.0 and length<100.0,"Terminal route keeps metre scale with a short approach")
	check(nav.grid==null,"Door-preview planning does not allocate an unused second live graph")
	var memory_delta := int(Performance.get_monitor(Performance.MEMORY_STATIC))-memory_before
	check(memory_delta<160*1024*1024,"Actual 360m airport planning graph stays below 160 MiB static allocation")
	print("LARGE_MAP_AIRPORT_PROFILE bounds=78x80 cell=0.25 route_m=%.2f segments=%d build_path_ms=%.1f memory_delta_bytes=%d" % [length,route.size(),(Time.get_ticks_usec()-before)/1000.0,memory_delta])
	var fixture := {"schema_version":2,"id":"EXTENT_QA","revision":1,"seed":1,"title":"Extent contract","bounds":[512,512],"focus":[256,256],
		"rooms":[{"id":"ground","x":256.0,"z":256.0,"w":512.0,"d":512.0}],"walls":[],"doors":[],"props":[],
		"units":[{"id":"alpha","name":"Alpha","role":"Assault","weapon":"standard","x":4.0,"z":4.0,"facing":0.0}],"enemies":[],"civilians":[],"objectives":["Reach destination"],"win":[{"type":"reach_zone","zone":[508,508,2,2]}]}
	check(bool(Schema.check(fixture).ok),"V2 accepts 512m bounds and physical room extents")
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/historical/registry.json"))
	fixture.scenery = [{"id":"landmark","asset":str(registry.keys()[0]),"x":256.0,"z":256.0,"cutaway":false}]
	check(bool(Schema.check(fixture).ok),"V2 accepts an explicit closed exterior landmark")
	fixture.scenery[0].cutaway=0
	check(not bool(Schema.check(fixture).ok),"Scenery cutaway accepts Boolean values only")
	fixture.erase("scenery")
	fixture.bounds=[513,512]
	check(not bool(Schema.check(fixture).ok),"V2 rejects a bound beyond 512m")
	fixture.bounds=[512,512]
	fixture.schema_version=1
	check(not bool(Schema.check(fixture).ok),"Legacy v1 still rejects bounds beyond 32m")
	print("BREACH_LARGE_MAP_EXTENT_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
