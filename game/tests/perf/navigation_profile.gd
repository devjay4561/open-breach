extends "res://scripts/navigation.gd"
var timings: Dictionary = {}
func measure(name: String, start: int) -> void:
	var item: Array = timings.get(name, [0, 0, 0])
	var elapsed := Time.get_ticks_usec() - start
	item[0] += 1; item[1] += elapsed; item[2] = maxi(item[2],elapsed)
	timings[name] = item

func build(data: Dictionary, door_states: Array) -> void:
	var started := Time.get_ticks_usec()
	super.build(data, door_states)
	measure("build", started)

func _cache_static_cells() -> void:
	var started := Time.get_ticks_usec()
	super._cache_static_cells()
	measure("_cache_static_cells", started)

func path(start: Vector2, target: Vector2, assumed_open: Array = []) -> Array:
	var started := Time.get_ticks_usec()
	var result = super.path(start, target, assumed_open)
	measure("path", started)
	return result

func segment_clear(a: Vector2, b: Vector2, padding: float = 0.0, assumed_open: Array = []) -> bool:
	var started := Time.get_ticks_usec()
	var result = super.segment_clear(a, b, padding, assumed_open)
	measure("segment_clear", started)
	return result

func shot_clear(a: Vector2, b: Vector2) -> bool:
	var started := Time.get_ticks_usec()
	var result = super.shot_clear(a, b)
	measure("shot_clear", started)
	return result

func walkable(point: Vector2, assumed_open: Array = []) -> bool:
	var started := Time.get_ticks_usec()
	var result = super.walkable(point, assumed_open)
	measure("walkable", started)
	return result

func _door_blockers(assumed_open: Array, movement: bool) -> Array:
	var started := Time.get_ticks_usec()
	var result = super._door_blockers(assumed_open, movement)
	measure("_door_blockers", started)
	return result

func _rect(obstacle: Dictionary, padding: float = 0.0) -> Rect2:
	var started := Time.get_ticks_usec()
	var result = super._rect(obstacle, padding)
	measure("_rect", started)
	return result

func _segment_obstacle(a: Vector2, b: Vector2, obstacle: Dictionary, padding: float) -> bool:
	var started := Time.get_ticks_usec()
	var result = super._segment_obstacle(a, b, obstacle, padding)
	measure("_segment_obstacle", started)
	return result
