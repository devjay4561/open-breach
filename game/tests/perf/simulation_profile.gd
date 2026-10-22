extends "res://scripts/simulation.gd"
var timings: Dictionary = {}
func measure(name: String, start: int) -> void:
	var item: Array = timings.get(name, [0, 0, 0])
	var elapsed := Time.get_ticks_usec() - start
	item[0] += 1; item[1] += elapsed; item[2] = maxi(item[2],elapsed)
	timings[name] = item

func _update_perception() -> void:
	var started := Time.get_ticks_usec()
	super._update_perception()
	measure("_update_perception", started)

func _advance_enemy(enemy: Dictionary, dt: float) -> void:
	var started := Time.get_ticks_usec()
	super._advance_enemy(enemy, dt)
	measure("_advance_enemy", started)

func _combat(attacker: Dictionary, candidates: Array, hostile: bool, forced_target: String = "") -> void:
	var started := Time.get_ticks_usec()
	super._combat(attacker, candidates, hostile, forced_target)
	measure("_combat", started)

func _take_enemy_cover(enemy: Dictionary, threat_position: Vector2) -> void:
	var started := Time.get_ticks_usec()
	super._take_enemy_cover(enemy, threat_position)
	measure("_take_enemy_cover", started)

func _advance_command(unit: Dictionary, dt: float) -> void:
	var started := Time.get_ticks_usec()
	super._advance_command(unit, dt)
	measure("_advance_command", started)

func can_see(observer: Dictionary, subject: Dictionary) -> bool:
	var started := Time.get_ticks_usec()
	var result = super.can_see(observer, subject)
	measure("can_see", started)
	return result
