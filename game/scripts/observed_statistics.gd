class_name BreachObservedStatistics
extends RefCounted

# Receipts contain facts learned by the squad, never live actor references.
var _receipts: Dictionary = {}
var _initial_dead: Dictionary = {}
var _counts: Dictionary = {"enemy":0, "civilian":0}
var _unlawful_shots: int = 0

func reset(mission: Dictionary) -> void:
	_receipts.clear()
	_initial_dead.clear()
	_unlawful_shots = 0
	_counts = {"enemy":mission.get("enemies", []).size(), "civilian":mission.get("civilians", []).size()}
	for actor: Dictionary in mission.get("enemies", []) + mission.get("civilians", []):
		if float(actor.get("hp", 72.0)) <= 0.0: _initial_dead[str(actor.id)] = true

func observe(actor: Dictionary, tick: int) -> void:
	var id := str(actor.get("id", ""))
	var kind := str(actor.get("kind", ""))
	if id.is_empty() or kind not in ["enemy", "civilian"]: return
	var health := maxf(0.0, float(actor.get("hp", 0.0)))
	var receipt: Dictionary = _receipts.get(id, {})
	if receipt.is_empty():
		receipt = {"kind":kind, "hp":health, "damage":0.0, "baseline_known":health >= float(actor.get("max_hp", health)), "arrested":false, "arrest_action":false, "secured":false}
	elif health < float(receipt.hp):
		receipt["damage"] = float(receipt.damage) + float(receipt.hp) - health
	receipt["hp"] = health
	receipt["tick"] = tick
	receipt["arrested"] = bool(receipt.arrested) or bool(actor.get("arrested", false))
	receipt["secured"] = bool(receipt.secured) or bool(actor.get("secured", false))
	_receipts[id] = receipt

func observe_damage(actor: Dictionary, before: float, after: float, tick: int) -> void:
	var prior := actor.duplicate(true)
	prior["hp"] = before
	observe(prior, tick)
	var current := actor.duplicate(true)
	current["hp"] = after
	observe(current, tick)

func control(kind: String, actor: Dictionary, tick: int) -> void:
	observe(actor, tick)
	var receipt: Dictionary = _receipts.get(str(actor.get("id", "")), {})
	if not receipt.is_empty():
		receipt["arrested" if kind == "arrest" else "secured"] = true
		if kind == "arrest": receipt["arrest_action"] = true

func record_unlawful_shot() -> void:
	_unlawful_shots += 1

func bundle(units: Array, success: bool = false) -> Dictionary:
	var answer := {"neutralized":0, "rescued":0, "kills":0, "arrests":0, "civilian_damage":0.0, "civilian_losses":0, "unlawful_shots":_unlawful_shots, "score":0}
	for id: String in _receipts:
		var receipt: Dictionary = _receipts[id]
		if receipt.kind == "enemy":
			if float(receipt.hp) <= 0.0 or bool(receipt.arrested): answer.neutralized += 1
			if float(receipt.hp) <= 0.0 and not _initial_dead.has(id): answer.kills += 1
			if bool(receipt.arrest_action): answer.arrests += 1
		else:
			answer.civilian_damage += float(receipt.damage)
			if float(receipt.hp) <= 0.0 and not _initial_dead.has(id): answer.civilian_losses += 1
			if bool(receipt.secured) and float(receipt.hp) > 0.0: answer.rescued += 1
	var total_health := 0.0
	for unit: Dictionary in units: total_health += maxf(0.0, float(unit.hp)) / maxf(1.0, float(unit.max_hp))
	var squad := 20.0 * total_health / float(maxi(1, units.size()))
	var objectives := 40.0 * float(answer.neutralized) / float(maxi(1, int(_counts.enemy))) if int(_counts.enemy) > 0 else 40.0
	var rescue := 40.0 * float(answer.rescued) / float(maxi(1, int(_counts.civilian))) if int(_counts.civilian) > 0 else 0.0
	var score := roundi((objectives + rescue + squad) * (100.0 / 60.0 if int(_counts.civilian) == 0 else 1.0))
	# A completed non-elimination objective is itself an owned receipt.
	if success and int(answer.neutralized) < int(_counts.enemy): score = roundi(80.0 + squad)
	answer.score = clampi(score - _unlawful_shots * 40, 0, 100)
	return answer

func _complete(kind: String, tick: int, damage: bool = false) -> bool:
	var known := 0
	for receipt: Dictionary in _receipts.values():
		if receipt.kind != kind: continue
		if damage and not bool(receipt.baseline_known): return false
		if float(receipt.hp) > 0.0 and int(receipt.get("tick", -1)) != tick: return false
		known += 1
	return known == int(_counts.get(kind, 0))

func stars(definitions: Array, raw: Dictionary, units: Array, success: bool, tick: int) -> Dictionary:
	var actual: Dictionary = {}
	var observed: Dictionary = {}
	var known := bundle(units, success)
	for star: Dictionary in definitions:
		var id := str(star.id)
		# Preserve evaluateStar's existing reserved-ID meaning, including old
		# authored complete/survival definitions whose numeric target is zero.
		if id in ["complete", "survival"]:
			var awarded := success and (id == "complete" or (not units.is_empty() and units.all(func(unit: Dictionary) -> bool: return float(unit.hp) > 0.0)))
			actual[id] = awarded
			observed[id] = awarded
			continue
		var stat := str(star.get("stat", ""))
		var value: Variant = raw.get(stat)
		var op := str(star.get("op", "eq"))
		var expected := float(star.get("value", star.get("limit", star.get("max", 1 if id in ["complete", "survival"] else 0))))
		actual[id] = success and value != null and _compare(float(value), op, expected)
		var complete := true
		if stat in ["kills", "neutralized"]: complete = _complete("enemy", tick)
		elif stat == "civilian_damage": complete = _complete("civilian", tick, true)
		elif stat in ["civilian_losses", "rescued"]: complete = _complete("civilian", tick)
		if known.has(stat): value = known[stat]
		# A lower bound proves a positive threshold or a failed upper bound, but
		# unknown hidden outcomes never grant a zero-damage/zero-kill star.
		var proven := complete or (op == "gte" and value != null and float(value) >= expected)
		observed[id] = success and proven and value != null and _compare(float(value), op, expected)
	return {"actual":actual, "observed":observed}

func _compare(actual: float, op: String, expected: float) -> bool:
	match op:
		"eq": return actual == expected
		"lte": return actual <= expected
		"gte": return actual >= expected
	return false
