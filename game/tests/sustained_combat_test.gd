extends SceneTree
## Focused acceptance cases for sustained play: sensory AI, cover, control,
## moving protected people and observation boundaries. No rendering is required.
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const Navigation = preload("res://scripts/navigation.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func fixture() -> Dictionary:
	# Known map/entity IDs and dimensions permit replay validation while a small
	# purpose-built room makes each sensory or timing rule independently visible.
	return {"id": "M01", "revision": 1, "seed": 42, "bounds": [24, 20],
		# P0 replay metrics validate room references as well as actors/doors.
		# Keep this synthetic rectangle and every behavioral assertion; use the
		# installed house room ID so its recording satisfies that same contract.
		"rooms": [{"id": "h_entry", "x": 12, "z": 10, "w": 23, "d": 19}],
		"walls": [], "props": [], "doors": [],
		"units": [{"id": "alpha", "x": 4, "z": 6, "facing": 0, "ammo": 0}],
		# P1 restores surrender. Ordinary cover/shot/timing fixtures opt out so
		# their original combat contracts remain independent of yielding.
		"enemies": [{"id": "e1", "x": 8, "z": 6, "facing": PI, "weapon": "light", "enemy_type": "normal", "can_surrender": false}],
		"civilians": []}

func sim(data: Dictionary) -> BreachSimulation:
	var instance := Simulation.new()
	instance.load_mission(data)
	return instance

func point(entity: Dictionary) -> Vector2:
	return Vector2(float(entity.x), float(entity.z))

func advance(instance: BreachSimulation, seconds: float) -> void:
	for _tick: int in range(roundi(seconds / STEP)):
		instance.step(STEP)

func advance_enemy(instance: BreachSimulation, seconds: float) -> void:
	# Freeze perception so this tests the FSM's dependence on its sensory memory.
	for _tick: int in range(roundi(seconds / STEP)):
		instance.time += STEP
		instance._advance_doors(STEP)
		for enemy: Dictionary in instance.enemies:
			instance._advance_enemy(enemy, STEP)

func sound_fixture() -> Dictionary:
	var data := fixture()
	data.units[0].x = 1
	data.units[0].z = 1
	data.units[0].vision_range = 0.5
	data.enemies[0].x = 4
	data.enemies[0].facing = 0
	data.enemies[0].patrol = [[4, 6], [4, 9]]
	return data

func divided_fixture(hard: bool = false) -> Dictionary:
	var data := fixture()
	data.id = "M01H" if hard else "M01"
	data.walls = [{"x": 8, "z": 2.55, "w": 0.24, "d": 5.1},
		{"x": 8, "z": 13.45, "w": 0.24, "d": 13.1}]
	data.doors = [{"id": "d1", "x": 8, "z": 6, "w": 0.24, "d": 1.8, "axis": "z", "state": "CLOSED"}]
	data.units[0].x = 1
	data.units[0].z = 1
	data.units[0].vision_range = 0.5
	data.enemies[0].x = 11
	data.enemies[0].facing = PI
	return data

func two_observers(data: Dictionary) -> void:
	data.units[0].x = 4
	data.units[0].z = 5.5
	data.units[0].facing = 0
	data.units.append({"id": "bravo", "x": 4, "z": 6.5, "facing": 0, "ammo": 0})
	data.enemies[0].facing = 0

func ready_combat(instance: BreachSimulation, attacker: Dictionary, target: Dictionary) -> void:
	# Isolate the shot/suppression rules with an already identified direct
	# observation, while still exercising authoritative acquisition and turning.
	for index: int in range(20):
		instance.time += STEP
		instance._update_combat_state(attacker, STEP)
		attacker._reaction = 0.0
		attacker._target = target.id
		attacker._observed = [{"id": target.id, "position": [target.x, target.z], "time": instance.time, "confidence": 1.0, "identified": true}]
		instance._remember_aim(attacker, target)
		instance._advance_authoritative_aim(attacker, true)
		if attacker.aim_state == "ready": break

func test_low_cover() -> void:
	var clear := sim(fixture())
	var base: float = clear._shot_accuracy(clear.units[0], clear.enemies[0], false)
	var data := fixture()
	# With the measured 1.536m rifle muzzle, a 1.15m obstacle covers the
	# leg sample while the head and torso rays remain clear. Both obstacles
	# intentionally cover that same sample to test geometric union exposure.
	data.props = [{"id": "cover", "type": "table", "cover": "low", "solid": true, "height": 1.15, "material": "steel", "x": 6, "z": 6, "w": 1, "d": 2}]
	var covered := sim(data)
	check(not covered.nav.walkable(Vector2(6, 6)), "Low cover blocks actor movement")
	check(covered.can_see(covered.units[0], covered.enemies[0]), "Low cover preserves sight through its footprint")
	check(covered.fire_line_clear(covered.units[0], covered.enemies[0]), "Low cover permits a shot rather than treating it as a wall")
	var partial: float = covered._shot_accuracy(covered.units[0], covered.enemies[0], false)
	check(partial > 0.0 and partial < base, "Cover affects accuracy through actual exposed body samples")
	covered.units[0].suppressed = 1.5
	check(is_equal_approx(covered._shot_accuracy(covered.units[0], covered.enemies[0], false), partial * 0.5), "Geometric exposure and attacker suppression compose without replacing each other")
	data.props.append({"id": "second", "type": "crate", "cover": "low", "height": 1.15, "material": "steel", "x": 7, "z": 6, "w": 0.5, "d": 1})
	var doubled := sim(data)
	check(is_equal_approx(doubled._shot_accuracy(doubled.units[0], doubled.enemies[0], false), partial), "A second obstacle covering the same body samples does not multiply an arbitrary furniture penalty")
	data.props[0].cover = "full"
	data.props[0].height = 2.6
	var full := sim(data)
	check(not full.can_see(full.units[0], full.enemies[0]), "Full cover blocks sight")
	data.props = [{"id": "rug", "type": "rug", "cover": "none", "solid": false, "x": 6, "z": 6, "w": 2, "d": 2}]
	var rug := sim(data)
	check(rug.nav.walkable(Vector2(6, 6)) and is_equal_approx(rug._shot_accuracy(rug.units[0], rug.enemies[0], false), base), "Decorative none cover blocks neither movement nor accuracy")

func test_sound_pursuit() -> void:
	var first := sim(sound_fixture())
	var second := sim(sound_fixture())
	for instance: BreachSimulation in [first, second]:
		instance._emit_sound(Vector2(9.2, 6.7), 12.0, "문 소리", "unit")
	check(first.enemies[0]._last_known == [10.0, 6.0], "Sound memory stores a coarse heard region rather than the source coordinate")
	check(first.enemies[0]._observed.is_empty(), "A heard sound does not manufacture a visual target")
	# Moving the unseen unit must not steer the enemy toward its live location.
	second.units[0].x = 20
	second.units[0].z = 18
	advance_enemy(first, 2.0)
	advance_enemy(second, 2.0)
	check(first.enemies[0].x > 4.5 and first.enemies[0].status == "SUSPICIOUS", "Suspicious enemy walks toward its remembered sound")
	check(point(first.enemies[0]).is_equal_approx(point(second.enemies[0])) and first.enemies[0]._last_known == second.enemies[0]._last_known, "Sound pursuit never reads an unseen unit's current coordinates")
	var reached := false
	for _tick: int in range(450):
		advance_enemy(first, STEP)
		if point(first.enemies[0]).distance_to(Vector2(10, 6)) <= 0.5:
			reached = true
			break
	check(reached, "Pursuit persists until the heard region is reached")
	if reached:
		advance_enemy(first, 2.4)
		check(first.enemies[0].status == "SUSPICIOUS", "Enemy searches the reached sound region for at least 2.4 seconds")
		advance_enemy(first, 1.0)
		check(first.enemies[0].status == "PATROL", "Enemy returns to its authored patrol after three seconds of search")

func test_hit_cover_response() -> void:
	var data := fixture()
	data.props = [{"id": "cover", "type": "crate", "cover": "low", "x": 9, "z": 7, "w": 1.0, "d": 1.0}]
	var instance := sim(data)
	var enemy: Dictionary = instance.enemies[0]
	enemy.status = "ALERT"
	enemy._ai_state = "ALERT"
	enemy._reaction = 1.0
	instance._take_enemy_cover(enemy, point(instance.units[0]))
	var selected: Array = enemy.get("_cover_target", []).duplicate()
	check(selected.size() == 2 and instance.nav.walkable(Vector2(float(selected[0]), float(selected[1]))), "An alert enemy chooses a walkable point behind nearby cover after a hit")
	if selected.size() == 2:
		var before := point(enemy)
		instance._advance_enemy(enemy, 0.5)
		check(point(enemy).distance_to(before) > 0.0, "An alert enemy actually moves toward its selected cover")
		instance._take_enemy_cover(enemy, Vector2(20, 6))
		check(enemy.get("_cover_target", []) == selected, "Repeated hits do not replace the enemy's single cover relocation")
	data.enemies[0].enemy_type = "rusher"
	var rusher := sim(data)
	rusher.enemies[0].status = "ALERT"
	rusher.enemies[0]._ai_state = "ALERT"
	rusher._take_enemy_cover(rusher.enemies[0], point(rusher.units[0]))
	check(rusher.enemies[0].get("_cover_target", []).is_empty(), "A rusher keeps advancing instead of seeking cover after a hit")

func test_enemy_doors_and_replay() -> void:
	var normal := sim(divided_fixture(false))
	var hard := sim(divided_fixture(true))
	var repeat := sim(divided_fixture(true))
	var record := Replay.new()
	var duplicate_record := Replay.new()
	record.begin(hard.mission)
	duplicate_record.begin(repeat.mission)
	for instance: BreachSimulation in [normal, hard, repeat]:
		instance._emit_sound(Vector2(5.4, 6), 12.0, "문 소리", "unit")
	record.capture(hard.snapshot(true))
	duplicate_record.capture(repeat.snapshot(true))
	for _tick: int in range(450):
		normal.step(STEP)
		hard.step(STEP)
		repeat.step(STEP)
		record.capture(hard.snapshot(true))
		duplicate_record.capture(repeat.snapshot(true))
	check(normal.doors[0].state == "OPEN" and normal.enemies[0].x < 7.7, "Normal enemy can operate a closed doorway while investigating")
	check(hard.doors[0].state == "OPEN" and hard.enemies[0].x < 7.7, "Challenge enemy opens a closed door and pursues into the other room")
	check(JSON.stringify(hard.snapshot(true)) == JSON.stringify(repeat.snapshot(true)), "Challenge sound and door pursuit is deterministic for the same seed")
	check(JSON.stringify(record.export_data()) == JSON.stringify(duplicate_record.export_data()), "The same seed produces the same complete pursuit replay data")
	var restored := Replay.new()
	var response: Dictionary = restored.load_data(record.export_data())
	check(bool(response.get("ok", false)), "Enemy-operated doorway replay survives export and validated import: " + str(response.get("message", "")))
	if bool(response.get("ok", false)):
		var replay_state: Dictionary = restored.seek(restored.duration, true)
		check(replay_state.doors[0].state == "OPEN" and replay_state.enemies[0].x < 7.7, "Replay reproduces the opened doorway and crossed enemy")

func test_surrender_conditions() -> void:
	# P1 restores these existing eligibility rules. Keep all twenty type/trigger
	# combinations and four assertions per case: immediate state, persistence,
	# fire permission and the corresponding event. Rusher never yields; hostage
	# taker retains only the two-observer surprise rule from the existing code.
	for enemy_type: String in ["normal", "guard", "sentry", "rusher", "hostage_taker"]:
		for trigger: String in ["ambush", "stun", "wounded", "combined"]:
			var data := fixture()
			data.enemies[0].enemy_type = enemy_type
			data.enemies[0].can_surrender = true
			if trigger in ["ambush", "combined"]:
				two_observers(data)
			if trigger in ["stun", "combined"]:
				data.enemies[0].x = 6
			if trigger in ["wounded", "combined"]:
				data.enemies[0].hp = 30
			var instance := sim(data)
			var enemy: Dictionary = instance.enemies[0]
			# P1 samples willingness once on its own RNG stream. These existing
			# cases test trigger/type eligibility for a willing enemy; the new
			# thirty-seed doctrine experiment checks the population proportion.
			enemy._surrender_susceptible = true
			if trigger in ["stun", "combined"]:
				enemy.stunned = 0.5
			var yields: bool = enemy_type != "rusher" and (enemy_type != "hostage_taker" or trigger in ["ambush", "combined"])
			advance(instance, 0.3)
			check((bool(enemy.surrendered) and enemy.status == "SURRENDERED" and int(enemy.ammo) == 0) if yields else
				(not bool(enemy.surrendered) and enemy.status != "SURRENDERED" and int(enemy.ammo) > 0),
				enemy_type + "/" + trigger + ": restored eligibility determines armed or surrendered state")
			enemy.facing = PI
			advance(instance, 3.0)
			check(bool(enemy.surrendered) == yields, enemy_type + "/" + trigger + ": a watched surrender persists and exempt types remain armed")
			check(instance.events.any(func(event: Dictionary) -> bool: return event.type == "SHOT" and bool(event.get("hostile", false))) == (not yields),
				enemy_type + "/" + trigger + ": only an armed survivor resumes combat after seeing the squad")
			check(instance.events.any(func(event: Dictionary) -> bool: return event.type == "SURRENDER") == yields,
				enemy_type + "/" + trigger + ": surrender event matches restored eligibility")

func test_rearming() -> void:
	var instance := sim(fixture())
	var enemy: Dictionary = instance.enemies[0]
	instance._set_surrendered(enemy)
	instance.units[0].facing = PI
	instance._update_perception()
	instance._update_surrender(4.9)
	check(bool(enemy.surrendered), "An unwatched surrendered enemy remains disarmed before five seconds")
	instance._update_surrender(0.11)
	check(not bool(enemy.surrendered) and int(enemy.ammo) > 0, "Five unwatched seconds rearms a living surrendered enemy")
	var watched := sim(fixture())
	enemy = watched.enemies[0]
	watched._set_surrendered(enemy)
	watched.units[0].facing = PI
	watched._update_perception()
	watched._update_surrender(4.0)
	watched.units[0].facing = 0
	watched._update_perception()
	watched._update_surrender(2.0)
	check(bool(enemy.surrendered), "A watching unit preserves surrender after more than five elapsed seconds")
	watched.units[0].facing = PI
	watched._update_perception()
	watched._update_surrender(4.9)
	check(bool(enemy.surrendered), "Observation resets the uninterrupted unwatched timer")
	watched._update_surrender(0.11)
	check(not bool(enemy.surrendered), "The reset timer rearms after a fresh five-second absence")
	enemy.surrendered = true
	enemy.arrested = true
	enemy.status = "ARRESTED"
	enemy.ammo = 0
	watched._update_surrender(10.0)
	check(bool(enemy.arrested) and bool(enemy.surrendered) and enemy.ammo == 0, "An arrested enemy cannot rearm even without a guard")

func test_surrendered_shot_accounting() -> void:
	var data := fixture()
	data.units[0].ammo = 8
	data.enemies[0].hp = 20
	var instance := sim(data)
	var enemy: Dictionary = instance.enemies[0]
	enemy.surrendered = true
	enemy.status = "SURRENDERED"
	enemy.ammo = 0
	instance._update_perception()
	var before_ammo: int = int(instance.units[0].ammo)
	instance._combat(instance.units[0], instance.enemies, false)
	check(instance.units[0].ammo == before_ammo and instance.shots_fired == 0, "Automatic fire protects an observed surrendered enemy")
	ready_combat(instance, instance.units[0], enemy)
	# Fix the next draw to a hit so killing and unlawful firing remain distinct
	# counters and the score penalty can be assessed on a completed mission.
	for _draw: int in range(1000):
		var saved_state: int = instance._rng.state
		if instance._rng.randf() < instance._shot_accuracy(instance.units[0], enemy, false):
			instance._rng.state = saved_state
			break
	var response: Dictionary = instance.fire_at("alpha", "e1")
	check(bool(response.get("ok", false)) and float(enemy.hp) == 0.0, "Explicit observed firing can exercise the surrendered-shot penalty")
	instance._check_result()
	check(int(instance.result.get("unlawful_shots", 0)) == 1 and int(instance.result.get("kills", 0)) == 1, "A surrendered kill records one kill and one separate unlawful shot")
	var lawful := sim(fixture())
	lawful.enemies[0].hp = 0.0
	lawful._check_result()
	check(int(instance.result.get("score", -1)) == int(lawful.result.get("score", -1)) - 40, "One unlawful shot deducts exactly forty virtual mission points")

func test_suppression() -> void:
	var data := fixture()
	data.units[0].ammo = 8
	data.enemies[0].hp = 200
	data.enemies[0].enemy_type = "rusher"
	data.enemies.append({"id": "e2", "x": 8, "z": 6.8, "facing": PI, "enemy_type": "rusher"})
	data.enemies.append({"id": "e3", "x": 8, "z": 7.1, "facing": PI, "enemy_type": "rusher"})
	var instance := sim(data)
	for enemy: Dictionary in instance.enemies:
		enemy._reaction = 0.0
	ready_combat(instance, instance.units[0], instance.enemies[0])
	instance._combat(instance.units[0], instance.enemies, false)
	var target: Dictionary = instance.enemies[0]
	check(is_equal_approx(float(target.suppressed), 1.5), "A shot applies exactly 1.5 seconds of suppression to its target")
	check(is_equal_approx(float(target._reaction), 0.12), "Suppression adds 0.12 seconds of reaction delay")
	check(float(instance.enemies[1].suppressed) > 0.0 and float(instance.enemies[2].suppressed) == 0.0, "Suppression includes a body within one metre of the shot and excludes a body beyond it")
	var normal_accuracy: float = instance._shot_accuracy(target, instance.units[0], true) * 2.0
	check(is_equal_approx(normal_accuracy, float(instance.enemy_rules.accuracy)), "A suppressed enemy receives the 0.5 accuracy multiplier")
	instance._update_tactical_effects(1.49)
	check(float(target.suppressed) > 0.0, "Suppression remains effective immediately before its expiry")
	instance._update_tactical_effects(0.02)
	check(float(target.suppressed) == 0.0 and is_equal_approx(instance._shot_accuracy(target, instance.units[0], true), normal_accuracy), "Suppression expires and restores the original accuracy")
	data = fixture()
	data.units[0].hp = 200
	var incoming := sim(data)
	incoming.enemies[0]._reaction = 0.0
	incoming.enemies[0]._target = "alpha"
	ready_combat(incoming, incoming.enemies[0], incoming.units[0])
	incoming._combat(incoming.enemies[0], incoming.units, true)
	check(is_equal_approx(float(incoming.units[0].suppressed), 1.5), "Enemy fire suppresses units under the same rule")
	check(is_equal_approx(incoming._shot_accuracy(incoming.units[0], incoming.enemies[0], false), float(Simulation.WEAPONS.standard.accuracy) * 0.5), "Suppression halves squad accuracy too")
	data = fixture()
	data.units[0].ammo = 8
	data.enemies[0].enemy_type = "rusher"
	var miss := sim(data)
	ready_combat(miss, miss.units[0], miss.enemies[0])
	var miss_state_found := false
	# Select a deterministic RNG state that will miss; this assertion must never
	# depend on a probabilistic expectation that a short run contains a miss.
	for _draw: int in range(1000):
		var saved_state: int = miss._rng.state
		if miss._rng.randf() >= miss._shot_accuracy(miss.units[0], miss.enemies[0], false):
			miss._rng.state = saved_state
			miss_state_found = true
			break
	check(miss_state_found, "Miss fixture obtains a seeded RNG state for an actual miss")
	miss._combat(miss.units[0], miss.enemies, false)
	var miss_seen := false
	for event: Dictionary in miss.events:
		if event.type == "SHOT" and not bool(event.hit):
			miss_seen = true
	check(miss_seen and is_equal_approx(float(miss.enemies[0].suppressed), 1.5), "A missed shot still suppresses the exposed target")

func test_enemy_types() -> void:
	for enemy_type: String in ["normal", "guard", "sentry", "rusher", "hostage_taker"]:
		var data := fixture()
		data.enemies[0].x = 6
		data.enemies[0].facing = 0
		data.enemies[0].enemy_type = enemy_type
		data.enemies[0].can_surrender = true
		data.enemies[0].patrol = [[6, 6], [6, 9]]
		var instance := sim(data)
		# P1: isolate type eligibility from the separately measured willingness.
		instance.enemies[0]._surrender_susceptible = true
		instance.enemies[0].stunned = 3.5
		instance._update_surrender(0.0)
		# P1 restores normal/guard/sentry stun surrender while retaining both
		# exceptional enemy types' existing rejection of this single trigger.
		check(bool(instance.enemies[0].surrendered) == (enemy_type in ["normal", "guard", "sentry"]), enemy_type + ": restored stun surrender respects enemy type")
	var data := sound_fixture()
	data.enemies[0].enemy_type = "guard"
	var guard := sim(data)
	check(is_equal_approx(float(guard.enemies[0].vision_range), 12.0) and is_equal_approx(float(guard.enemies[0].fov), 70.0), "Guard has a 12m sight range and a 70-degree cone")
	var guard_start := point(guard.enemies[0])
	advance_enemy(guard, 2.0)
	check(point(guard.enemies[0]).is_equal_approx(guard_start), "Guard ignores authored patrol routes while idle")
	check(is_equal_approx(guard._shot_accuracy(guard.enemies[0], guard.units[0], true), float(guard.enemy_rules.accuracy) + 0.1), "Guard accuracy adds the fixed 0.1 bonus")
	data = sound_fixture()
	data.enemies[0].enemy_type = "rusher"
	var rush := sim(data)
	var start := point(rush.enemies[0])
	rush._emit_sound(Vector2(9.2, 6), 12.0, "문 소리", "unit")
	rush._advance_enemy(rush.enemies[0], STEP)
	check(point(rush.enemies[0]).distance_to(start) > 0.0, "Rusher starts moving on the first update after hearing sound")
	data = fixture()
	data.enemies[0].enemy_type = "hostage_taker"
	data.enemies[0].hp = 20
	data.enemies[0].can_surrender = true
	var hostage_low := sim(data)
	hostage_low._update_surrender(0.0)
	check(not bool(hostage_low.enemies[0].surrendered), "Hostage taker does not surrender under the low-health rule")
	two_observers(data)
	var hostage_ambush := sim(data)
	hostage_ambush._update_surrender(0.0)
	# P1 re-enables the pre-existing hostage-taker surprise exception; low
	# health alone above still leaves it armed.
	check(bool(hostage_ambush.enemies[0].surrendered), "Hostage taker surrenders under the restored two-unit ambush rule")
	data = fixture()
	data.units[0].x = 1
	data.units[0].z = 1
	data.units[0].vision_range = 0.5
	data.enemies[0].enemy_type = "hostage_taker"
	data.enemies[0].x = 9
	data.enemies[0].facing = 0
	data.enemies[0].patrol = [[9, 6], [18, 6]]
	data.civilians = [{"id": "c1", "x": 8, "z": 6}]
	var tethered := sim(data)
	advance_enemy(tethered, 6.0)
	check(point(tethered.enemies[0]).distance_to(point(tethered.civilians[0])) <= 2.0, "Hostage taker stays within two metres of its civilian")
	var alert := sim(data)
	alert.enemies[0]._reaction = 0.0
	alert.enemies[0]._observed = [{"id": "alpha", "position": [1, 1], "time": 0.0, "identified": true, "confidence": 1.0}]
	var before: float = float(alert.civilians[0].hp)
	advance_enemy(alert, 3.9)
	check(float(alert.civilians[0].hp) == before, "Hostage taker does not attack its civilian before four seconds of alert")
	advance_enemy(alert, 0.7)
	check(float(alert.civilians[0].hp) < before, "Sustained alert and direct observation permit the hostage threat after physical aim acquisition")

func test_civilian_movement() -> void:
	var data := fixture()
	data.units[0].x = 1
	data.units[0].z = 1
	data.civilians = [{"id": "c1", "x": 7, "z": 6}, {"id": "c2", "x": 20, "z": 18}]
	var panic := sim(data)
	check(panic.civilians[0].status == "IDLE", "A civilian starts idle")
	panic._emit_sound(Vector2(7, 6), 4.0, "총성 감지", "unit")
	check(panic.civilians[0].status == "PANIC" and panic.civilians[1].status == "IDLE", "Gunfire panics only civilians inside its sound radius")
	var start := point(panic.civilians[0])
	for _tick: int in range(60):
		panic.time += STEP
		panic._advance_civilians(STEP)
	check(point(panic.civilians[0]).distance_to(start) > 0.2, "Panicked civilian moves toward room cover")
	data = divided_fixture()
	data.civilians = [{"id": "c1", "x": 10, "z": 6}]
	var blocked := sim(data)
	blocked._emit_sound(Vector2(10, 6), 4.0, "총성 감지", "unit")
	var movement_valid := true
	for _tick: int in range(240):
		var previous := point(blocked.civilians[0])
		blocked.time += STEP
		blocked._advance_civilians(STEP)
		var current := point(blocked.civilians[0])
		movement_valid = movement_valid and blocked.nav.walkable(current) and blocked.nav.segment_clear(previous, current, Navigation.RADIUS)
	check(movement_valid and blocked.doors[0].state == "CLOSED" and float(blocked.civilians[0].travel_distance) > 0.2, "Active panic navigation never clips through walls or a closed door")
	data = fixture()
	data.units[0].x = 10
	data.units[0].facing = 0
	data.civilians = [{"id": "c1", "x": 5, "z": 6}]
	var following := sim(data)
	following.civilians[0].secured = true
	following.civilians[0].status = "FOLLOW"
	following.civilians[0].follow_unit_id = "alpha"
	for _tick: int in range(240):
		following._advance_civilians(STEP)
	check(absf(point(following.civilians[0]).distance_to(point(following.units[0])) - 1.0) <= 0.2 and following.civilians[0].x < following.units[0].x, "A following civilian settles one metre behind its assigned unit")
	following.units[0].x = 13
	var previous := point(following.civilians[0])
	for _tick: int in range(120):
		following._advance_civilians(STEP)
	check(following.civilians[0].x > previous.x + 1.0 and following.civilians[0].follow_unit_id == "alpha", "A moving escort carries its civilian follower with it")
	following.units[0].x = 4
	following.enemies[0].x = 14
	following.civilians[0].x = 10
	check(not following.fire_line_clear(following.units[0], following.enemies[0]), "A moving civilian follower remains a protected body on a squad firing line")
	data = divided_fixture()
	data.units[0].x = 6
	data.units[0].z = 6
	data.units[0].facing = 0
	data.civilians = [{"id": "c1", "x": 10, "z": 6}]
	var closed := sim(data)
	closed.civilians[0].secured = true
	closed.civilians[0].status = "FOLLOW"
	closed.civilians[0].follow_unit_id = "alpha"
	for _tick: int in range(240):
		closed._advance_civilians(STEP)
	check(closed.civilians[0].x > 8.0 and closed.doors[0].state == "CLOSED", "A civilian follower cannot teleport across a closed doorway")

func test_hidden_information_and_peek() -> void:
	var data := divided_fixture()
	data.doors[0].swing_sign = 1.0
	data.units[0].x = 7.6
	data.units[0].z = 6.612
	data.units[0].facing = PI * 0.5
	data.units[0].fov = 20.0
	data.units[0].vision_range = 10
	data.enemies[0].x = 10
	data.enemies[0].z = 6.8
	data.enemies[0].facing = 0
	data.enemies[0].ammo = 0
	data.enemies[0].passive = true
	data.civilians = [{"id": "c1", "x": 11, "z": 6}]
	var instance := sim(data)
	check(instance.snapshot(false).enemies.is_empty() and instance.snapshot(false).civilians.is_empty(), "An unobserved room exposes neither enemy nor civilian")
	# A fabricated eye point behind a closed leaf is rejected. The public peek
	# command must physically open an aperture and keep its sensor reachable.
	instance.units[0]._peek_origin = [8.25, 6.0]
	instance.units[0]._peek_facing = 0.0
	instance.units[0]._peek_remaining = 1.5
	check(not instance.can_see(instance.units[0], instance.enemies[0]), "An unreachable sensor beyond a closed leaf cannot reveal the room")
	instance.units[0]._peek_remaining = 0.0
	instance.issue("alpha", "FACE", {"target":[7.6,10.0], "persistent":true})
	instance.issue("alpha", "PEEK_DOOR", {"door_id":"d1"})
	for _tick: int in range(150):
		instance.step(STEP)
		if float(instance.units[0].get("_peek_remaining",0.0)) > 0.0: break
	check(instance.can_see(instance.units[0], instance.enemies[0]), "Physical peek observes through the actual partial latch gap")
	check(not instance.can_see(instance.units[0], {"x": 10, "z": 10}), "Peek uses its narrow 70-degree cone instead of revealing the whole room")
	instance._update_perception()
	check(instance.snapshot(false).enemies.size() == 1 and instance.enemies[0].last_seen == [10.0, 6.8], "Peek publishes contact through the ordinary last-seen observation path")
	check(instance.doors[0].state == "AJAR" and float(instance.doors[0].progress) > 0.22, "Peek observation requires a partially opened physical door")
	var peek_origin: Vector2 = instance._point(instance.units[0].get("_peek_origin",[instance.units[0].x,instance.units[0].z]))
	check(peek_origin.x < 8.0 and peek_origin.distance_to(point(instance.units[0])) <= 0.161, "The eye remains on the operator's physical side")
	# Peek duration belongs to the command clock. Keep both sides empty so only
	# perception and the temporary view advance during this acceptance case.
	instance.enemies[0].ammo = 0
	advance(instance, 1.6)
	instance._update_perception()
	check(not instance.can_see(instance.units[0], instance.enemies[0]) and not bool(instance.enemies[0].visible), "Peek visibility expires after 1.5 seconds")
	var remembered: String = JSON.stringify(instance.snapshot(false).enemies)
	instance.enemies[0].x = 14
	instance.enemies[0].hp = 20
	instance.enemies[0].suppressed = 1.5
	instance.enemies[0].surrendered = true
	instance.enemies[0].status = "SURRENDERED"
	instance.enemies[0].ammo = 0
	instance.civilians[0].x = 16
	instance.civilians[0].status = "PANIC"
	instance._update_perception()
	check(JSON.stringify(instance.snapshot(false).enemies) == remembered, "Hidden movement, suppression and surrender do not change a stale observation")
	check(instance.snapshot(false).civilians.is_empty(), "An unobserved moving civilian does not expose its current position or panic state")
	var hidden: Dictionary = instance.snapshot(false).enemies[0]
	check(not hidden.has("suppressed") and not hidden.has("surrendered") and not hidden.has("ammo") and not hidden.has("_last_known"), "A last-seen enemy record contains no hidden tactical state")
	var hidden_shot: Dictionary = instance.fire_at("alpha", "e1")
	check(not bool(hidden_shot.get("ok", false)) and instance.shots_fired == 0, "Explicit firing refuses a stale observation after the target leaves sight")
	check(instance.snapshot(true).enemies[0].x == 14 and instance.snapshot(true).civilians[0].x == 16, "Authoritative replay capture retains hidden movement for review")

func test_combined_seed_determinism() -> void:
	var data := fixture()
	data.id = "M01H"
	data.seed = 713
	data.modifiers = ["night", "low_ammo"]
	data.units[0].hp = 5000
	data.units.append({"id": "bravo", "x": 4, "z": 7, "facing": 0, "ammo": 0, "hp": 5000})
	data.enemies[0].x = 6.49
	data.enemies[0].facing = 0
	# P1: this combined determinism contract must actually exercise surrender.
	data.enemies[0].can_surrender = true
	data.enemies.append({"id": "e2", "x": 10, "z": 8, "facing": PI, "enemy_type": "rusher"})
	data.enemies.append({"id": "e3", "x": 14, "z": 10, "facing": PI, "enemy_type": "hostage_taker"})
	data.enemies.append({"id": "e4", "x": 18, "z": 6, "facing": PI, "enemy_type": "sentry"})
	data.civilians = [{"id": "c1", "x": 15, "z": 10}, {"id": "c2", "x": 4, "z": 8}]
	data.props = [{"id": "cover", "type": "crate", "cover": "low", "x": 11, "z": 6, "w": 1, "d": 1}]
	var first := sim(data)
	var second := sim(data)
	var first_record := Replay.new()
	var second_record := Replay.new()
	first_record.begin(data)
	second_record.begin(data)
	var accepted := true
	for instance: BreachSimulation in [first, second]:
		# Keep surrender present in this all-effects determinism experiment.
		instance.enemies[0]._surrender_susceptible = true
		instance.enemies[0].stunned = 3.5
		instance.civilians[1].secured = true
		instance.civilians[1].follow_unit_id = "bravo"
		instance.civilians[1].status = "FOLLOW"
		accepted = accepted and bool(instance.issue("alpha", "THROW_STUN", {"target": [10, 8]}).get("ok", false))
		accepted = accepted and bool(instance.plan_move("bravo", {"target": [13, 11]}).get("ok", false))
		instance._emit_sound(Vector2(9.2, 6), 12.0, "총성 감지", "unit")
	check(accepted, "Combined deterministic fixture accepts the same equipment and escort plan")
	first_record.capture(first.snapshot(true))
	second_record.capture(second.snapshot(true))
	var identical := true
	for _tick: int in range(180):
		first.step(STEP)
		second.step(STEP)
		var first_state: Dictionary = first.snapshot(true)
		var second_state: Dictionary = second.snapshot(true)
		identical = identical and JSON.stringify(first_state) == JSON.stringify(second_state)
		first_record.capture(first_state)
		second_record.capture(second_state)
	check(identical, "Surrender, stun, suppression, enemy types and civilian movement remain identical every tick for the same seed, plan and modifiers")
	check(JSON.stringify(first_record.export_data()) == JSON.stringify(second_record.export_data()), "Combined tactical state produces identical replay bytes for the same operation")
	var restored := Replay.new()
	var response: Dictionary = restored.load_data(first_record.export_data())
	check(bool(response.get("ok", false)), "Combined enemy and civilian state survives validated replay import: " + str(response.get("message", "")))

func test_observed_thin_wall_fire() -> void:
	var data := fixture()
	data.units[0].ammo = 1
	data.units.append({"id": "bravo", "x": 8, "z": 9, "facing": -PI / 2.0, "ammo": 0})
	data.enemies[0].hp = 10000
	data.enemies[0].passive = true
	data.walls = [{"id": "partition", "x": 6, "z": 6, "w": 0.24, "d": 4, "thin": true}]
	var instance := sim(data)
	check(not instance.can_see(instance.units[0], instance.enemies[0]) and instance.can_see(instance.units[1], instance.enemies[0]), "Thin wall conceals the enemy from the shooter while its teammate can actually observe it")
	check(not instance.nav.segment_clear(point(instance.units[0]), point(instance.enemies[0])) and instance.nav.shot_clear(point(instance.units[0]), point(instance.enemies[0])), "Thin partition separates blocked sight from allowed shot geometry")
	for _draw: int in range(1000):
		var saved_state: int = instance._rng.state
		if instance._rng.randf() < instance._shot_accuracy(instance.units[0], instance.enemies[0], false):
			instance._rng.state = saved_state
			break
	var response: Dictionary = instance.fire_at("alpha", "e1")
	check(not bool(response.get("ok", false)) and instance.units[0].ammo == 1 and instance.enemies[0].hp == 10000.0, "A teammate's observation cannot authorize a shot at a personally unidentified hidden target")
	var direct_profile: Dictionary = instance.nav.shot_profile_height(point(instance.units[0]), point(instance.enemies[0]), 1.35, 1.19, instance._weapon_penetration(instance.units[0]))
	check(bool(direct_profile.clear) and float(direct_profile.transmission) < 1.0, "The physical thin partition can transmit a shot with finite material attenuation independently of identification")
	check(not instance.can_see(instance.units[0], instance.enemies[0]), "Firing through a thin partition does not grant the shooter vision")
	data.walls[0].thin = false
	var full := sim(data)
	response = full.fire_at("alpha", "e1")
	check(not bool(response.get("ok", false)) and full.units[0].ammo == 1 and full.enemies[0].hp == 10000.0, "An ordinary full wall refuses teammate-assisted fire")
	data.walls[0].thin = true
	data.units[1].facing = 0.0
	var stale := sim(data)
	stale.enemies[0].visible = true
	stale.enemies[0].last_seen = [8.0, 6.0]
	stale._combat(stale.units[0], stale.enemies, false)
	response = stale.fire_at("alpha", "e1")
	check(not bool(response.get("ok", false)) and stale.units[0].ammo == 1 and stale.units[0]._aim_position.is_empty(), "Stale visibility and last-seen coordinates cannot authorize a hidden wall shot or expose a live aim position")
	data.units[1].facing = -PI / 2.0
	data.units[0].facing = PI
	var away := sim(data)
	response = away.fire_at("alpha", "e1")
	check(not bool(response.get("ok", false)) and away.units[0].ammo == 1, "Teammate observation does not bypass the shooter's own firing cone")
	data.units[0].facing = 0.0
	var smoke := sim(data)
	# Smoke covers only the shooter's segment; the teammate still has clear sight.
	smoke._smoke_zones.append({"x": 5.0, "z": 6.0, "radius": 0.5, "remaining": 4.0})
	response = smoke.fire_at("alpha", "e1")
	check(not bool(response.get("ok", false)) and smoke.units[0].ammo == 1 and smoke.can_see(smoke.units[1], smoke.enemies[0]), "A thin wall shot still obeys smoke blocking on the shooter's own segment")

func run() -> void:
	var readiness := sim(fixture())
	check(readiness.units.size() == 1 and readiness.enemies.size() == 1, "Combat fixture initializes its unit and enemy dependencies")
	if readiness.units.size() != 1 or readiness.enemies.size() != 1:
		print("BREACH_SUSTAINED_COMBAT_RESULT checks=%d failures=%d" % [checks, failures.size()])
		for failure: String in failures:
			push_error(failure)
		quit(1)
		return
	test_low_cover()
	test_sound_pursuit()
	test_hit_cover_response()
	test_enemy_doors_and_replay()
	test_surrender_conditions()
	test_rearming()
	test_surrendered_shot_accounting()
	test_suppression()
	test_enemy_types()
	test_civilian_movement()
	test_hidden_information_and_peek()
	test_combined_seed_determinism()
	test_observed_thin_wall_fire()
	print("BREACH_SUSTAINED_COMBAT_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
