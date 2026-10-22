extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Schema = preload("res://scripts/mission_schema.gd")
const Replay = preload("res://scripts/replay.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func fixture(strength: String) -> Dictionary:
	return {"id":"STRENGTH_QA","seed":42,"bounds":[16,12],"rooms":[],"walls":[],"props":[],"doors":[],"units":[{"id":"alpha","x":4.0,"z":6.0,"facing":0.0,"hp":1000.0,"ammo":0,"reserve_ammo":0}],"enemies":[{"id":"e1","strength":strength,"x":9.0,"z":6.0,"facing":PI,"hp":72.0,"can_surrender":false}],"civilians":[],"win":[{"type":"reach_zone","zone":[14,10,1,1]}],"fail":[]}
func run() -> void:
	var results: Array = []
	for strength: String in ["weak","medium","strong"]:
		var sim := Simulation.new()
		sim.load_mission(fixture(strength))
		for index: int in range(120): sim.step(STEP)
		var shots: Array = sim.events.filter(func(event: Dictionary) -> bool: return event.type == "SHOT" and bool(event.get("hostile",false)))
		check(shots.size() >= 2, strength + " actually fires more than once")
		if shots.size() < 2: continue
		var profile: Dictionary = Catalog.ENEMY_STRENGTHS[strength]
		check(absf(float(shots[1].time) - float(shots[0].time) - float(profile.interval)) <= STEP + 0.00001, strength + " uses its authored firing interval")
		check(sim.units[0].hp < 1000.0, strength + " deals real health damage")
		check(is_equal_approx(sim._enemy_combat_stat(sim.enemies[0], "damage"),profile.damage), strength + " uses its authored damage")
		check(is_equal_approx(sim._shot_accuracy(sim.enemies[0],sim.units[0],true),profile.accuracy), strength + " uses its authored accuracy")
		results.append({"strength":strength,"first_shot":shots[0].time,"damage_taken":1000.0-float(sim.units[0].hp)})
		var hard := Simulation.new()
		var data := fixture(strength)
		data.challenge = true
		hard.load_mission(data)
		check(hard._enemy_combat_stat(hard.enemies[0], "damage") > profile.damage, strength + " retains explicit challenge scaling")
		var passive := fixture(strength)
		passive.enemies[0].training = true
		var target := Simulation.new()
		target.load_mission(passive)
		for index: int in range(30): target.step(STEP)
		check(int(target.enemies[0].ammo) == int(target.enemies[0].max_ammo), strength + " cannot turn a training target into a shooter")
	check(results.size() == 3, "All three combat tiers produced evidence")
	if results.size() == 3:
		check(float(results[2].first_shot) < float(results[1].first_shot) and float(results[1].first_shot) < float(results[0].first_shot), "Higher tiers respond faster in the same frontal contact")
		check(float(results[2].damage_taken) > float(results[1].damage_taken) and float(results[1].damage_taken) > float(results[0].damage_taken), "Higher tiers produce greater pressure over the same four seconds")
	var valid := Catalog.load("T01")
	valid.enemies[0].strength = "strong"
	check(bool(Schema.check(valid).ok), "Mission schema accepts a supported enemy tier")
	valid.enemies[0].strength = "boss"
	check(not bool(Schema.check(valid).ok), "Mission schema rejects unknown enemy tiers")
	var missions := Catalog.missions()
	var briefs := Catalog.briefings(missions)
	for id: String in missions:
		for enemy: Dictionary in missions[id].enemies:
			if bool(enemy.get("training",false)) or bool(enemy.get("target",false)) or bool(enemy.get("passive",false)): continue
			check(Catalog.ENEMY_STRENGTHS.has(str(enemy.get("strength",""))), id + ": live NPC has an explicit tier")
	for brief: Dictionary in briefs:
		var count: Dictionary = brief.enemy_strengths
		check(int(count.weak)+int(count.medium)+int(count.strong) <= int(brief.enemy_count), str(brief.id) + ": briefing counts exclude passive targets")
	check(briefs.filter(func(brief: Dictionary) -> bool: return brief.id == "M01")[0].enemy_strengths == {"weak":4,"medium":2,"strong":0}, "Opening mission is weak-heavy")
	check(briefs.filter(func(brief: Dictionary) -> bool: return brief.id == "M09")[0].enemy_strengths == {"weak":0,"medium":2,"strong":7}, "Final mission is strong-heavy")
	_replay()
	print("ENEMY_STRENGTH_EVIDENCE " + JSON.stringify(results))
	print("BREACH_ENEMY_STRENGTH_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func _replay() -> void:
	var sim := Simulation.new()
	sim.load_mission(Catalog.load("M03"))
	var recorder := Replay.new()
	recorder.begin(sim.mission)
	recorder.capture(sim.snapshot(true))
	sim.step(STEP)
	recorder.finish(sim.snapshot(true))
	var exported: Dictionary = JSON.parse_string(JSON.stringify(recorder.export_data()))
	var imported := Replay.new()
	var response: Dictionary = imported.load_data(exported)
	check(bool(response.get("ok",false)), "Tiered authored mission replay imports: " + str(response.get("message","")))
	if bool(response.get("ok",false)):
		var replayed: Dictionary = imported.seek(0.0, true)
		check(replayed.enemies.map(func(enemy: Dictionary) -> String: return enemy.strength) == sim.enemies.map(func(enemy: Dictionary) -> String: return enemy.strength), "Replay retains every NPC tier")
	for definition: Dictionary in exported.states:
		if definition.group == "enemies":
			definition.base.strength = "boss"
			break
	check(not bool(Replay.new().load_data(exported).get("ok",true)), "Replay rejects an unsupported enemy tier")
