extends "res://tests/perf/simulation_profile.gd"
func _movement_dynamic_route(actor: Dictionary, destination: Vector2) -> Array:
	var started := Time.get_ticks_usec()
	var result := super._movement_dynamic_route(actor, destination)
	measure("_movement_dynamic_route", started)
	return result
func _movement_resolve_destination(actor: Dictionary, command: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	super._movement_resolve_destination(actor, command)
	measure("_movement_resolve_destination", started)
func _movement_bypass(actor: Dictionary, blocker: Dictionary, direction: Vector2) -> Array:
	var started := Time.get_ticks_usec()
	var result := super._movement_bypass(actor, blocker, direction)
	measure("_movement_bypass", started)
	return result
func _movement_yield(actor: Dictionary, requester: Dictionary, destination: Vector2, dt: float) -> void:
	var started := Time.get_ticks_usec()
	super._movement_yield(actor, requester, destination, dt)
	measure("_movement_yield", started)
func _movement_route_clear(actor: Dictionary, route: Array) -> bool:
	var started := Time.get_ticks_usec()
	var result := super._movement_route_clear(actor, route)
	measure("_movement_route_clear", started)
	return result
func _movement_swept_blocker(actor: Dictionary, origin: Vector2, candidate: Vector2, prediction: bool = false) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := super._movement_swept_blocker(actor, origin, candidate, prediction)
	measure("_movement_swept_blocker", started)
	return result
var movement_peaks: Array = []
func _repath(unit: Dictionary, command: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	super._repath(unit, command)
	measure("_repath", started)
	if Time.get_ticks_usec() - started > 20000:
		movement_peaks.append({"function":"_repath", "type":command.type, "time":time,"unit":unit.id,"us":Time.get_ticks_usec()-started})
func _start_command(unit: Dictionary, command: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	super._start_command(unit, command)
	measure("_start_command", started)
	if Time.get_ticks_usec() - started > 20000:
		movement_peaks.append({"function":"_start_command", "type":command.type, "time":time,"unit":unit.id,"us":Time.get_ticks_usec()-started})
func _follow_command_path(unit: Dictionary, command: Dictionary, dt: float) -> bool:
	var started := Time.get_ticks_usec()
	var result := super._follow_command_path(unit, command, dt)
	measure("_follow_command_path", started)
	return result
func _advance_open_door(unit: Dictionary, command: Dictionary, dt: float) -> void:
	var started := Time.get_ticks_usec()
	super._advance_open_door(unit, command, dt)
	measure("_advance_open_door", started)
	if Time.get_ticks_usec() - started > 20000:
		movement_peaks.append({"function":"_advance_open_door", "type":command.type, "time":time,"unit":unit.id,"us":Time.get_ticks_usec()-started})
func _refresh_preview(unit: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	super._refresh_preview(unit)
	measure("_refresh_preview", started)
func _door_clearance_position(door: Dictionary, actor: Dictionary, target: float) -> Array:
	var started := Time.get_ticks_usec()
	var result := super._door_clearance_position(door, actor, target)
	measure("_door_clearance_position", started)
	return result
func _advance_doors(dt: float) -> void:
	var started := Time.get_ticks_usec()
	super._advance_doors(dt)
	measure("_advance_doors", started)
