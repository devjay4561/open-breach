extends SceneTree
const Field = preload("res://scripts/visibility_field.gd")
const Simulation = preload("res://scripts/simulation.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size()<20: failures.append(message)
func exhaustive_contains(field: RefCounted, point: Vector2) -> bool:
	for polygon: PackedVector2Array in field.polygons:
		if Geometry2D.is_point_in_polygon(point,polygon): return true
	return false
func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=21972
	for id: String in ["H01","H02","H03"]:
		var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/historical/"+id+".json"))
		var sim := Simulation.new()
		sim.load_mission(map)
		var field := Field.new()
		field.build(map)
		field.update(sim.units,sim.doors)
		for i: int in range(2000):
			var point := Vector2(rng.randf_range(0,float(map.bounds[0])),rng.randf_range(0,float(map.bounds[1])))
			check(field.contains(point)==exhaustive_contains(field,point),id+": bounds preserve exact historical sight containment")
		for polygon: PackedVector2Array in field.polygons:
			for vertex: Vector2 in polygon:
				for offset: Vector2 in [Vector2.ZERO,Vector2(0.00001,0),Vector2(-0.00001,0),Vector2(0,0.00001),Vector2(0,-0.00001)]:
					var point := vertex+offset
					check(field.contains(point)==exhaustive_contains(field,point),id+": conservative bounds preserve polygon boundary tolerance")
		var samples: Array[Vector2] = []
		for z: int in range(32):
			for x: int in range(32): samples.append(Vector2((x+0.5)*float(map.bounds[0])/32.0,(z+0.5)*float(map.bounds[1])/32.0))
		var before := Time.get_ticks_usec()
		var reference_hits := 0
		for i: int in range(20):
			for point: Vector2 in samples: reference_hits += int(exhaustive_contains(field,point))
		var reference_ms := (Time.get_ticks_usec()-before)/1000.0/20.0
		before=Time.get_ticks_usec()
		var filtered_hits := 0
		for i: int in range(20):
			for point: Vector2 in samples: filtered_hits += int(field.contains(point))
		var filtered_ms := (Time.get_ticks_usec()-before)/1000.0/20.0
		check(reference_hits==filtered_hits,id+": profiling samples retain every visible floor point")
		print("VISIBILITY_BOUNDS_PROFILE map=%s samples=1024 exhaustive_ms=%.3f bounded_ms=%.3f" % [id,reference_ms,filtered_ms])
	print("BREACH_VISIBILITY_BOUNDS_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
