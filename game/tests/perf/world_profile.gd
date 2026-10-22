extends "res://scripts/world_view.gd"
var timings: Dictionary = {}
func _sync_actor(entity: Dictionary, kind: String, index: int, selected_id: String, _delta: float, planning: bool) -> void:
	var started := Time.get_ticks_usec()
	super._sync_actor(entity, kind, index, selected_id, _delta, planning)
	var item: Array = timings.get("_sync_actor", [0, 0])
	item[0] += 1; item[1] += Time.get_ticks_usec() - started
	timings["_sync_actor"] = item
func _draw_paths(units: Array) -> void:
	var started := Time.get_ticks_usec()
	super._draw_paths(units)
	var item: Array = timings.get("_draw_paths", [0, 0])
	item[0] += 1; item[1] += Time.get_ticks_usec() - started
	timings["_draw_paths"] = item
func _draw_cone(_units: Array) -> void:
	var started := Time.get_ticks_usec()
	super._draw_cone(_units)
	var item: Array = timings.get("_draw_cone", [0, 0])
	item[0] += 1; item[1] += Time.get_ticks_usec() - started
	timings["_draw_cone"] = item
func _update_effects(state: Dictionary, _delta: float, planning: bool) -> void:
	var started := Time.get_ticks_usec()
	super._update_effects(state, _delta, planning)
	var item: Array = timings.get("_update_effects", [0, 0])
	item[0] += 1; item[1] += Time.get_ticks_usec() - started
	timings["_update_effects"] = item
func _update_room_exploration() -> void:
	var started := Time.get_ticks_usec()
	super._update_room_exploration()
	var item: Array = timings.get("_update_room_exploration", [0, 0])
	item[0] += 1; item[1] += Time.get_ticks_usec() - started
	timings["_update_room_exploration"] = item
