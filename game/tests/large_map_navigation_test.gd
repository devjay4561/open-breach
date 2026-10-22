extends SceneTree
const Navigation = preload("res://scripts/navigation.gd")
const Schema = preload("res://scripts/mission_schema.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture(width: float = 128.0, depth: float = 96.0) -> Dictionary:
	return {"schema_version":2, "id":"LARGE_QA", "revision":1, "title":"Metre-scale QA", "seed":1,
		"bounds":[width,depth], "focus":[width*0.5,depth*0.5],
		"rooms":[{"id":"ground", "x":width*0.5, "z":depth*0.5, "w":width, "d":depth}],
		"walls":[], "doors":[], "props":[],
		"units":[{"id":"alpha", "name":"Alpha", "role":"Assault", "weapon":"standard", "x":4.0, "z":4.0, "facing":0.0}],
		"enemies":[], "civilians":[], "objectives":["Reach the far end"],
		"win":[{"type":"reach_zone", "zone":[width-4.0,depth-4.0,2.0,2.0]}]}

func assert_route(nav: RefCounted, start: Vector2, target: Vector2, label: String) -> Array:
	var route: Array = nav.path(start,target)
	check(not route.is_empty(), label+": reachable")
	var previous := start
	for raw: Array in route:
		var current := Vector2(float(raw[0]),float(raw[1]))
		check(nav.segment_clear(previous,current,Navigation.RADIUS),label+": swept body stays on legal floor")
		previous = current
	check(previous.distance_to(target)<0.001,label+": exact destination")
	return route

func _initialize() -> void:
	var data := fixture()
	data.walls = [{"id":"barrier", "x":64.0,"z":35.0,"w":0.30,"d":70.0,"height":3.0}]
	var nav := Navigation.new()
	var before := Time.get_ticks_usec()
	nav.build(data,[])
	check(nav.grid == null,"Large maps create a graph only when a detour needs it")
	check(nav._static_solid_cells.size()<5000,"Sparse wall occupancy avoids a full-floor raster scan")
	var route := assert_route(nav,Vector2(10,20),Vector2(110,20),"100 metre route around a building")
	check(route.size()>1,"Obstacle causes a real long detour")
	var long_ms := (Time.get_ticks_usec()-before)/1000.0
	print("LARGE_MAP_PROFILE bounds=128x96 cell=0.25 points=%d build_and_path_ms=%.1f" % [nav.grid.region.size.x*nav.grid.region.size.y,long_ms])

	data = fixture()
	data.walls = [
		{"x":64.0,"z":23.775,"w":0.20,"d":47.55},
		{"x":64.0,"z":72.225,"w":0.20,"d":47.55}]
	var door := {"id":"door","x":64.0,"z":48.0,"w":0.20,"d":0.90,"axis":"z","state":"CLOSED","progress":0.0,"swing_sign":1.0,"hinge_side":-1.0}
	nav = Navigation.new()
	nav.build(data,[door])
	check(nav.path(Vector2(10,48),Vector2(110,48)).is_empty(),"A closed 0.90m door blocks a 100m route")
	door.state = "OPEN"
	door.progress = 1.0
	nav.invalidate_dynamic()
	assert_route(nav,Vector2(10,48),Vector2(110,48),"An open real-width 0.90m door")
	var existing_grid: AStarGrid2D = nav.grid
	nav.path(Vector2(10,47),Vector2(110,47))
	check(nav.grid == existing_grid,"Moving a door keeps the large graph allocation")

	data = fixture()
	data.environment = {"water":true}
	data.walkable_areas = [
		{"id":"north_deck","x":64.0,"z":30.0,"w":110.0,"d":8.0},
		{"id":"south_deck","x":64.0,"z":60.0,"w":110.0,"d":8.0},
		{"id":"joining_deck","x":13.0,"z":45.0,"w":8.0,"d":30.0}]
	nav = Navigation.new()
	nav.build(data,[])
	check(not nav.walkable(Vector2(80,45)),"Water is not legal actor floor")
	check(not nav.segment_clear(Vector2(100,30),Vector2(100,60),Navigation.RADIUS),"Movement cannot shortcut through water")
	check(nav.segment_clear(Vector2(100,30),Vector2(100,60)),"Water keeps sight unobstructed")
	check(nav.shot_clear(Vector2(100,30),Vector2(100,60)),"Water keeps firing unobstructed")
	check(nav.segment_clear(Vector2(13,32),Vector2(13,38),Navigation.RADIUS),"Touching deck areas have no false clearance seam")
	assert_route(nav,Vector2(100,30),Vector2(100,60),"Deck union detour over a connected quay")
	check(nav.grid.region.size.x*nav.grid.region.size.y<80000,"Graph allocation crops the ocean background")
	check(nav.grid.region.position != Vector2i.ZERO,"Cropped graph retains global metre coordinates")

	data = fixture(256,256)
	nav = Navigation.new()
	before = Time.get_ticks_usec()
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	nav.build(data,[])
	assert_route(nav,Vector2(4,4),Vector2(252,252),"256m reference open map")
	var memory_delta := int(Performance.get_monitor(Performance.MEMORY_STATIC))-memory_before
	check(nav.grid == null,"An open 256m map never allocates an unused million-point AStar graph")
	print("LARGE_MAP_PROFILE bounds=256x256 cell=0.25 graph=lazy build_and_path_ms=%.1f memory_delta_bytes=%d" % [(Time.get_ticks_usec()-before)/1000.0,memory_delta])
	data.walls = [{"id":"large_barrier","x":128.0,"z":70.0,"w":0.30,"d":140.0,"height":3.0}]
	before = Time.get_ticks_usec()
	memory_before = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	nav.build(data,[])
	assert_route(nav,Vector2(10,100),Vector2(240,100),"256m reference map with a 230m obstacle detour")
	memory_delta = int(Performance.get_monitor(Performance.MEMORY_STATIC))-memory_before
	check(memory_delta<128*1024*1024,"The maximum tested AStar graph stays below a 128 MiB static allocation budget")
	print("LARGE_MAP_PROFILE bounds=256x256 points=%d build_and_path_ms=%.1f memory_delta_bytes=%d" % [nav.grid.region.size.x*nav.grid.region.size.y,(Time.get_ticks_usec()-before)/1000.0,memory_delta])
	data.walls = []
	var legacy := fixture(32,32)
	legacy.schema_version = 1
	check(bool(Schema.check(legacy).ok),"Legacy v1 retains its 32m authoring contract")
	legacy.bounds = [33,32]
	check(not bool(Schema.check(legacy).ok),"Legacy v1 rejects maps beyond 32m")
	check(bool(Schema.check(data).ok),"V2 accepts the full 256m metre contract")
	data.bounds = [512.1,256]
	check(not bool(Schema.check(data).ok),"V2 rejects bounds beyond the 512m schema maximum")
	data = fixture()
	data.environment = {"biome":"coast","ground_color":"#687b7c","ground_surface":"concrete","water":false}
	data.historical = {"location":"Nervask Strait","accuracy_note":"Fixture only"}
	data.interactive_targets = [{"id":"radio","x":20.0,"z":20.0,"w":2.0,"d":2.0,"label":"Radio","action":"disable","duration":3.0}]
	data.win = [{"type":"targets_complete","targets":["radio"]}]
	data.fail = [{"type":"no_shots"}]
	check(bool(Schema.check(data).ok),"Historical metadata and physical objective geometry validate together")
	data.win[0].targets = ["missing"]
	check(not bool(Schema.check(data).ok),"Unknown interactive target references are rejected")
	data.win[0].targets = ["radio"]
	data.environment.weather = "rain"
	check(not bool(Schema.check(data).ok),"V2 still rejects unknown nested environment fields")
	data.environment.erase("weather")
	data.scenery = [{"id":"fake","asset":"missing_model","x":40.0,"z":40.0}]
	check(not bool(Schema.check(data).ok),"V2 rejects scenery without a registered asset")
	if FileAccess.file_exists("res://assets/historical/registry.json"):
		var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/historical/registry.json"))
		check(not registry.is_empty(),"Historical asset registry is populated")
		for id: String in registry:
			var path: String = str(registry[id].get("path","res://assets/historical/"+id+".glb"))
			check(FileAccess.file_exists(path),"Registered historical asset actually exists: "+id)
		data.scenery = [{"id":"valid_scenery","asset":str(registry.keys()[0]),"x":40.0,"z":40.0,"scale":1.0}]
		check(bool(Schema.check(data).ok),"Registered metre-scale scenery can be authored")
	print("BREACH_LARGE_MAP_NAVIGATION_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
