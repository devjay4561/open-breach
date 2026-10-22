extends SceneTree
## Controlled structural comparison, not a full M01 playthrough or a claim about
## human difficulty. Preserve M01 geometry, furniture, doors and authored e2 at
## its primary living-room position. Keep one ordinary standard alpha inside the
## entry. The same FACE / THROW_STUN / WAIT plan looks toward the other flank.
## Both cases use NORMAL reaction, speed, accuracy and damage. Only the enemy's
## permission to open closed doors differs. No hidden coordinate enters a plan.
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const STEP := 1.0 / 30.0
const SEEDS := [1, 7, 42, 97, 313, 713, 1049, 8191]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func scenario(seed_value: int) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var alpha: Dictionary = data.units[0].duplicate(true)
	alpha.x = 10.3
	alpha.z = 15.15
	alpha.facing = 0.0
	var living_enemy: Dictionary = {}
	for source: Dictionary in data.enemies:
		if source.id == "e2":
			living_enemy = source.duplicate(true)
	# Fix the authored primary position: seed variation here changes combat draws
	# while each pair has precisely the same actors, geometry and starting state.
	living_enemy.erase("spawns")
	living_enemy.erase("patrol")
	data.seed = seed_value
	data.units = [alpha]
	data.enemies = [living_enemy]
	data.civilians = []
	data.win = [{"type": "neutralize_all"}]
	data.fail = []
	data.stars = []
	data.modifiers = []
	return data

func metric(instance: BreachSimulation, opened: bool, crossed: bool, contact: bool, hostile_shots: int) -> Dictionary:
	return {"survived": instance.units[0].hp > 0.0,
		"pressure_free": instance.hits_taken == 0,
		"hp": instance.units[0].hp, "hits_taken": instance.hits_taken,
		"door_opened": opened, "door_crossed": crossed, "visual_contact":contact, "hostile_shots":hostile_shots,
		"shots_fired": instance.shots_fired, "stuns_used": instance.stuns_used}

func run_case(seed_value: int, enemy_opens: bool) -> Dictionary:
	var instance := Simulation.new()
	instance.load_mission(scenario(seed_value))
	instance.enemy_rules = Catalog.NORMAL.duplicate(true)
	instance.enemy_rules["enemy_opens_doors"] = enemy_opens
	check(instance.units.size() == 1 and instance.enemies.size() == 1, "Benchmark has one ordinary unit and one authored living-room enemy")
	check(instance.nav.walkable(Vector2(10.3, 15.15)), "Benchmark unit starts on a legal point in the actual entry geometry")
	check(bool(instance.issue("alpha", "FACE", {"target": [14.5, 15.15]}).get("ok", false)), "Alternative-flank FACE plan is accepted")
	check(bool(instance.issue("alpha", "THROW_STUN", {"target": [13.1, 16.3]}).get("ok", false)), "Ordinary entry stun plan is accepted")
	check(bool(instance.issue("alpha", "WAIT", {"duration": 30.0}).get("ok", false)), "Door-defense WAIT plan is accepted")
	var door: Dictionary = instance._find(instance.doors, "d2")
	check(not instance.nav.segment_clear(Vector2(13.1, 16.3), Vector2(float(instance.enemies[0].x), float(instance.enemies[0].z))), "Closed d2 blocks the burst-to-enemy stun line")
	# The same audible entry disturbance in both cases; walls attenuate its radius.
	instance._emit_sound(Vector2(10.3, 15.15), 12.0, "문 소리", "unit")
	var opened := false
	var crossed := false
	var contact := false
	var hostile_shots := 0
	var enemy_stun_peak := 0.0
	var unit_stun_peak := 0.0
	var at_fifteen: Dictionary = {}
	for tick_index: int in range(720):
		var ammunition_before: int = int(instance.enemies[0].ammo)
		instance.step(STEP)
		# Hidden attackers intentionally do not publish precise SHOT events.
		# Count authoritative spent rounds instead of weakening that privacy rule.
		hostile_shots += maxi(0, ammunition_before - int(instance.enemies[0].ammo))
		opened = opened or door.state == "OPEN"
		crossed = crossed or float(instance.enemies[0].x) > 9.23
		contact = contact or not instance.enemies[0].get("_observed", []).is_empty()
		enemy_stun_peak = maxf(enemy_stun_peak, float(instance.enemies[0].stunned))
		unit_stun_peak = maxf(unit_stun_peak, float(instance.units[0].stunned))
		if tick_index == 449:
			at_fifteen = metric(instance, opened, crossed, contact, hostile_shots)
	check(instance.stuns_used == 1 and enemy_stun_peak == 0.0 and unit_stun_peak == 0.0, "The plan emits one heard equipment sound without stunning either actor")
	return {"seed": seed_value, "enemy_opens_doors": enemy_opens,
		"15_seconds": at_fifteen, "24_seconds": metric(instance, opened, crossed, contact, hostile_shots)}

func totals(cases: Array, horizon: String) -> Dictionary:
	var result: Dictionary = {"cases": cases.size(), "survivors": 0, "pressure_free_holds": 0, "hits_taken": 0, "doors_opened": 0, "doors_crossed": 0, "shots_fired": 0, "visual_contacts":0, "hostile_shots":0, "remaining_hp":0.0}
	for case: Dictionary in cases:
		var current: Dictionary = case[horizon]
		result.survivors += int(bool(current.survived))
		result.pressure_free_holds += int(bool(current.pressure_free))
		result.hits_taken += int(current.hits_taken)
		result.doors_opened += int(bool(current.door_opened))
		result.doors_crossed += int(bool(current.door_crossed))
		result.shots_fired += int(current.shots_fired)
		result.visual_contacts += int(bool(current.visual_contact))
		result.hostile_shots += int(current.hostile_shots)
		result.remaining_hp += float(current.hp)
	return result

func run() -> void:
	var baseline: Array = []
	var enemy_doors: Array = []
	for seed_value: int in SEEDS:
		baseline.append(run_case(seed_value, false))
		enemy_doors.append(run_case(seed_value, true))
	var normal_fifteen := totals(baseline, "15_seconds")
	var opening_fifteen := totals(enemy_doors, "15_seconds")
	var normal_twenty_four := totals(baseline, "24_seconds")
	var opening_twenty_four := totals(enemy_doors, "24_seconds")
	check(normal_twenty_four.survivors == SEEDS.size() and normal_twenty_four.hits_taken == 0 and normal_twenty_four.doors_opened == 0, "Closed doors provide complete protection in the baseline controlled hold")
	check(opening_fifteen.doors_opened == SEEDS.size() and opening_fifteen.visual_contacts == SEEDS.size(), "Enemy opening creates actual visual contact in every paired scenario")
	# Useful cover may keep an enemy on its original side. Verify effective
	# pressure rather than requiring it to abandon cover or force a fixed kill.
	check(opening_twenty_four.hostile_shots > normal_twenty_four.hostile_shots and opening_twenty_four.hits_taken > normal_twenty_four.hits_taken and opening_twenty_four.pressure_free_holds < normal_twenty_four.pressure_free_holds, "Enemy-operated doors create real hostile fire and reduce pressure-free holds within twenty-four seconds")
	check(opening_twenty_four.remaining_hp < normal_twenty_four.remaining_hp, "Effective enemy pressure causes more damage over the controlled hold")
	print("BREACH_DOOR_DEFENSE_BENCHMARK " + JSON.stringify({"scope": "controlled M01 entry hold, one authored unit and e2, actual geometry, normal combat rules; only enemy door opening changes", "seeds": SEEDS, "15_seconds": {"closed_baseline": normal_fifteen, "enemy_opening": opening_fifteen}, "24_seconds": {"closed_baseline": normal_twenty_four, "enemy_opening": opening_twenty_four}, "paired_cases": {"closed_baseline": baseline, "enemy_opening": enemy_doors}}))
	print("BREACH_DOOR_DEFENSE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
