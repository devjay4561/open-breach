extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []
var scenarios: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture() -> Dictionary:
	return {"schema_version":1,"id":"HIT_REACTION_QA","revision":1,"custom":true,"title":"Rear-hit reaction","variant":"normal","seed":71,"bounds":[14,12],"focus":[7,6],"walls":[],"props":[],"doors":[],"rooms":[{"id":"room","x":7,"z":6,"w":14,"d":12}],"units":[{"id":"alpha","name":"Alpha","role":"Assault","weapon":"standard","x":6.0,"z":6.0,"facing":0.0,"fov":110.0}],"enemies":[{"id":"e1","x":2.0,"z":6.0,"facing":0.0,"vision_range":12.0,"hold_position":true}],"civilians":[],"objectives":["Reach the far zone"],"stars":[],"win":[{"type":"reach_zone","zone":[12,10,0.2,0.2]}],"fail":[]}

func run() -> void:
	var validated: Dictionary = Catalog.validate_custom(fixture())
	check(bool(validated.ok), "Rear-hit fixture is a valid playable mission: " + str(validated))
	var fixture_file := FileAccess.open("res://../tests/artifacts/hit-reaction/fixture.json", FileAccess.WRITE)
	fixture_file.store_string(JSON.stringify(fixture(), "  ") + "\n")
	fixture_file.close()
	for moving: bool in [false, true]: _rear_hit(moving)
	_fixed_watch(false)
	_fixed_watch(true)
	_hidden_attacker()
	_hold_position()
	var output := FileAccess.open("res://../tests/artifacts/hit-reaction/native-report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"scenarios":scenarios}, "  ") + "\n")
	output.close()
	print("BREACH_HIT_REACTION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _rear_hit(moving: bool) -> void:
	var data := fixture()
	var sim := Simulation.new()
	sim.load_mission(data)
	var label := "moving" if moving else "stationary"
	if moving: check(bool(sim.issue("alpha", "MOVE", {"target":[12.0,6.0]}).ok), "Moving rear-hit route accepted")
	var replay := Replay.new()
	replay.begin(data)
	replay.capture(sim.snapshot(true))
	var first_hit := -1.0
	var turned := -1.0
	var first_return_fire := -1.0
	var no_blind_fire := true
	var smooth := true
	var continued_move := false
	var first_position := Vector2.ZERO
	for frame: int in range(120):
		var before_body: float = sim.units[0].body_facing
		var before_aim: float = sim.units[0].aim_facing
		var shots := sim.shots_fired
		sim.step(STEP)
		var unit: Dictionary = sim.units[0]
		if sim.hits_taken > 0 and first_hit < 0.0:
			first_hit = sim.time
			first_position = sim._position(unit)
		if sim.time - float(unit.get("_last_hit_time", -100.0)) < 1.5:
			smooth = smooth and absf(angle_difference(before_body, unit.body_facing)) <= 5.2 * STEP + 0.00001 and absf(angle_difference(before_aim, unit.aim_facing)) <= 6.4 * STEP + 0.00001
		if first_hit >= 0.0:
			if turned < 0.0 and absf(angle_difference(unit.body_facing, PI)) < 0.15 and absf(angle_difference(unit.aim_facing, PI)) < 0.15: turned = sim.time
			continued_move = continued_move or sim._position(unit).distance_to(first_position) > 0.4
		if sim.shots_fired > shots:
			no_blind_fire = no_blind_fire and sim.observation_ready(unit, sim.enemies[0]) and sim.can_see(unit, sim.enemies[0])
			if first_return_fire < 0.0: first_return_fire = sim.time
		replay.capture(sim.snapshot(true))
	check(first_hit > 0.0, label + " receives a real shot from outside its FOV")
	check(turned > first_hit and turned - first_hit < 1.5, label + " body and weapon turn toward incoming fire")
	check(smooth, label + " reaction uses bounded body and weapon turn rates")
	check(first_return_fire > first_hit and no_blind_fire, label + " returns fire only after actual sight and identification")
	check(float(sim.units[0].hp) > 0.0, label + " turns and returns fire while alive")
	check(sim.command_failures == 0, label + " reaction does not fail player commands")
	if moving:
		check(continued_move and sim.units[0].commands[0].args.target == [12.0,6.0], "Looking back preserves the move and its target")
		check(sim.units[0].commands[0].state == "SUCCEEDED", "Movement still reaches its destination")
	var imported := Replay.new()
	var loaded: Dictionary = imported.load_data(JSON.parse_string(JSON.stringify(replay.export_data())))
	check(bool(loaded.ok), label + " reaction poses survive replay export/import: " + str(loaded))
	scenarios.append({"scenario":label,"first_hit":first_hit,"turned":turned,"return_fire":first_return_fire,"hp":sim.units[0].hp,"enemy_hp":sim.enemies[0].hp,"shots":sim.shots_fired,"command_failures":sim.command_failures})

func _fixed_watch(persistent: bool) -> void:
	var sim := Simulation.new()
	sim.load_mission(fixture())
	sim.issue("alpha", "FACE", {"target":[10.0,6.0],"persistent":persistent})
	for frame: int in range(45): sim.step(STEP)
	check(sim.hits_taken > 0, "Fixed watch receives incoming fire")
	check(sim.units[0].facing_locked and sim.units[0].facing_persistent == persistent, "Hit never releases an explicit watch mode")
	check(absf(sim.units[0].body_facing) < 0.01 and absf(sim.units[0].aim_facing) < 0.01, "Explicit watch retains the commanded direction")

func _hidden_attacker() -> void:
	var data := fixture()
	data.bounds = [30,12]
	data.units[0].fov = 20.0
	data.enemies[0].hp = 10000.0
	var sim := Simulation.new()
	sim.load_mission(data)
	for frame: int in range(60):
		sim.step(STEP)
		if sim.hits_taken > 0: break
	check(sim.hits_taken > 0 and not bool(sim.enemies[0].visible), "Hidden-attacker fixture begins with a real unseen hit")
	# Keep the shooter beyond sight during both the rearward reaction and
	# the return turn, so a newly observed target cannot override movement.
	sim.enemies[0].ammo = 0
	sim.enemies[0].reserve_ammo = 0
	sim.enemies[0].x = 26.0
	sim.enemies[0].z = 10.0
	for frame: int in range(30): sim.step(STEP)
	check(absf(angle_difference(sim.units[0].body_facing, PI)) < 0.15, "Hit reaction keeps the original incoming direction")
	check(not bool(sim.enemies[0].visible) and sim.units[0]._observed.is_empty(), "Hit does not invent a visual observation")
	check(sim.shots_fired == 0 and sim.units[0]._aim_target == "", "Unseen hit never supplies a target identity or blind shot")
	check(sim.snapshot().enemies.is_empty(), "Hit reaction does not expose hidden enemy coordinates")
	for frame: int in range(30): sim.step(STEP)
	sim.issue("alpha", "MOVE", {"target":[10.0,6.0]}, false)
	for frame: int in range(20): sim.step(STEP)
	check(not bool(sim.enemies[0].visible) and sim.units[0]._observed.is_empty(), "Returning from an unseen hit does not acquire a new target")
	check(absf(angle_difference(sim.units[0].body_facing, 0.0)) < 0.2, "Expired hit direction no longer overrides ordinary movement")

func _hold_position() -> void:
	var data := fixture()
	data.units[0].hold_position = true
	var sim := Simulation.new()
	sim.load_mission(data)
	var origin: Vector2 = sim._position(sim.units[0])
	for frame: int in range(60): sim.step(STEP)
	check(sim.hits_taken > 0 and absf(angle_difference(sim.units[0].body_facing, PI)) < 0.15, "Position holder still turns toward incoming fire")
	check(sim._position(sim.units[0]).is_equal_approx(origin), "Hit reaction never moves a position holder")
