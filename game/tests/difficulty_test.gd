extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func fixture(id: String, obstructed: bool = false) -> Dictionary:
	return {"id":id,"seed":42,"bounds":[16,12],"walls":[{"x":8,"z":6,"w":0.4,"d":12}] if obstructed else [],"props":[],"doors":[],"units":[{"id":"alpha","x":4,"z":6,"facing":0,"ammo":0}],"enemies":[{"id":"e1","x":11,"z":6,"facing":PI,"ammo":32,"weapon":"light"}],"civilians":[]}
func sim(data: Dictionary) -> BreachSimulation:
	var instance := Simulation.new()
	instance.load_mission(data)
	return instance
func advance(instance: BreachSimulation, duration: float) -> void:
	for tick: int in range(int(duration*30)): instance.step(1.0/30.0)
func run() -> void:
	var normal := sim(fixture("M02"))
	var hard := sim(fixture("M02H"))
	check(hard.enemies[0].hp == normal.enemies[0].hp, "Challenge does not inflate enemy health")
	check(hard.enemies[0]._reaction < normal.enemies[0]._reaction, "Challenge reacts sooner after actual observation")
	advance(normal,2.5)
	advance(hard,2.5)
	check(hard.units[0].hp < normal.units[0].hp, "Identical exposed fixture receives more challenge pressure")
	check(hard.enemies[0].ammo < normal.enemies[0].ammo, "Challenge fire cadence is faster")
	var blocked := sim(fixture("M02H",true))
	advance(blocked,4)
	check(blocked.units[0].hp == 100 and blocked.enemies[0].ammo == 32, "Challenge cannot shoot through walls")
	var blind_data := fixture("M02H")
	blind_data.enemies[0].facing = 0
	var blind := sim(blind_data)
	advance(blind,3)
	check(blind.units[0].hp == 100, "Challenge cannot target actors outside its FOV")
	var reload_data := fixture("M02H",true)
	reload_data.enemies[0].ammo = 0
	var reload_sim := sim(reload_data)
	advance(reload_sim,0.1)
	check(reload_sim.enemies[0].status == "RELOADING" and reload_sim.enemies[0].ammo == 0, "Empty challenge enemy spends time reloading")
	advance(reload_sim,2)
	check(reload_sim.enemies[0].ammo == 32, "Enemy reload restores the authored magazine")
	var target_data := fixture("M02H")
	target_data.enemies[0].passive = true
	var passive := sim(target_data)
	advance(passive,4)
	check(passive.units[0].hp == 100, "Passive training target never attacks even under challenge rules")
	for id: String in Catalog.CHALLENGE_IDS:
		var data: Dictionary = Catalog.load(id)
		var first := sim(data)
		var second := sim(data)
		var record := Replay.new()
		record.begin(data)
		record.capture(first.snapshot(true))
		for tick: int in range(90):
			first.step(1.0/30.0)
			second.step(1.0/30.0)
			record.capture(first.snapshot(true))
		check(JSON.stringify(first.snapshot(true)) == JSON.stringify(second.snapshot(true)), id+": repeated start is deterministic")
		var restored := Replay.new()
		check(bool(restored.load_data(record.export_data()).get("ok",false)),id+": challenge replay round trip")
		check(restored.data.get("map_id","")==id,id+": replay retains separate difficulty identity")
	print("BREACH_DIFFICULTY_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
