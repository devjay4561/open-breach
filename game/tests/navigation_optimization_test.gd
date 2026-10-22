extends SceneTree
const Nav=preload("res://scripts/navigation.gd")
const Door=preload("res://scripts/door_geometry.gd")
const Catalog=preload("res://scripts/mission_catalog.gd")
class OriginalNav extends BreachNavigation:
	func walkable(point: Vector2, assumed_open: Array = []) -> bool:
		if point.x < RADIUS or point.y < RADIUS or point.x > bounds.x - RADIUS or point.y > bounds.y - RADIUS:
			return false
		for obstacle: Dictionary in blockers(assumed_open, true):
			if _contains(obstacle, point, RADIUS): return false
		return true
	func segment_clear(a: Vector2, b: Vector2, padding: float = 0.0, assumed_open: Array = []) -> bool:
		for obstacle: Dictionary in blockers(assumed_open, padding > 0.0):
			if _segment_obstacle(a, b, obstacle, padding): return false
		return true
	func _cache_static_cells() -> void:
		_static_solid_cells.clear()
		for y in range(ceili(bounds.y/CELL)):
			for x in range(ceili(bounds.x/CELL)):
				var p:=Vector2(x+0.5,y+0.5)*CELL
				var solid:=p.x<RADIUS or p.y<RADIUS or p.x>bounds.x-RADIUS or p.y>bounds.y-RADIUS
				if not solid:
					for obstacle: Dictionary in walls:
						if _contains(obstacle,p,RADIUS):solid=true;break
				if solid:_static_solid_cells.append(Vector2i(x,y))
	func _leaf_obstacle(door: Dictionary) -> Dictionary:
		return BreachDoorGeometry.leaf_obstacle(door)
	func _segment_rect(a: Vector2,b: Vector2,rect: Rect2) -> bool:
		var direction:=b-a
		var near_t:=0.0
		var far_t:=1.0
		for axis in range(2):
			var start: float=a[axis]
			var delta: float=direction[axis]
			var low: float=rect.position[axis]
			var high: float=rect.end[axis]
			if absf(delta)<0.000001:
				if start<low or start>high:return false
			else:
				var t1: float=(low-start)/delta
				var t2: float=(high-start)/delta
				near_t=maxf(near_t,minf(t1,t2));far_t=minf(far_t,maxf(t1,t2))
				if near_t>far_t:return false
		return near_t<=far_t
var checks:=0
var failures: Array[String]=[]
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message)
func _initialize() -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=77271
	for id in ["M01","M04","M06"]:
		var map:=Catalog.load(id)
		var nav:=Nav.new();nav.build(map,map.doors)
		var original:=OriginalNav.new();original.build(map,map.doors)
		check(nav._static_solid_cells==original._static_solid_cells,id+": exact row-major occupancy preserved")
		for i in range(400):
			var a:=Vector2(rng.randf_range(0,map.bounds[0]),rng.randf_range(0,map.bounds[1]))
			var b:=Vector2(rng.randf_range(0,map.bounds[0]),rng.randf_range(0,map.bounds[1]))
			var door: Dictionary=map.doors[i%map.doors.size()]
			door.progress=rng.randf();door.state="OPEN" if i%4==0 else "OPENING";door.swing_sign=1 if i%2==0 else -1
			var padding: float=0.0 if i%2==0 else Nav.RADIUS
			var assumed_open: Array = [door.id] if i % 3 == 0 else []
			check(nav.segment_clear(a,b,padding,assumed_open)==original.segment_clear(a,b,padding,assumed_open),"LOS/body segment agrees with uncached slab reference")
			check(nav.walkable(a,assumed_open)==original.walkable(a,assumed_open),"Walkability agrees after live door mutation")
			check(nav.shot_clear(a,b)==original.shot_clear(a,b),"Shot occlusion agrees with moving leaf")
		for door: Dictionary in map.doors:
			for progress in [0.35,0.35000001,0.3500001,0.4,1.0]:
				door.progress=progress
				check(nav._leaf_obstacle(door)==Door.leaf_obstacle(door),"Leaf cache sees sub-revision progress changes")
	var nav:=Nav.new();var original:=OriginalNav.new()
	for i in range(1000):
		var rect:=Rect2(rng.randf_range(-2,2),rng.randf_range(-2,2),rng.randf_range(0,3),rng.randf_range(0,3))
		var a:=rect.position if i%3==0 else Vector2(rng.randf_range(-5,5),rng.randf_range(-5,5))
		var b:=a+Vector2(0.0000005,0.0000001) if i%2==0 else Vector2(rng.randf_range(-5,5),rng.randf_range(-5,5))
		check(nav._segment_rect(a,b,rect)==original._segment_rect(a,b,rect),"Degenerate and boundary segments retain original clipping semantics")
	print("BREACH_NAV_OPTIMIZATION_RESULT checks=%d failures=%d"%[checks,failures.size()])
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
