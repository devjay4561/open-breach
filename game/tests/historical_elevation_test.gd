extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const Replay = preload("res://scripts/replay.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _initialize() -> void:
	var mission := {"schema_version":2,"id":"H_FLOOR_QA","revision":1,"custom":true,"title":"Measured cabin floor","seed":1,"bounds":[128,80],"focus":[48,40],
		"rooms":[{"id":"apron","x":64,"z":40,"w":128,"d":80,"indoor":false},{"id":"cabin","x":48,"z":40,"w":20,"d":10,"base_height":2.022}],
		"walls":[{"id":"cabin_partition","x":50,"z":40,"w":0.18,"d":10,"height":2.1,"base_height":2.022}],"doors":[],"props":[],
		"units":[{"id":"alpha","name":"Alpha","role":"Assault","weapon":"standard","x":30,"z":40,"facing":0}],"enemies":[],
		"civilians":[{"id":"passenger","x":44,"z":43,"hp":100}],"objectives":["Reach the distant mark"],"win":[{"type":"reach_zone","zone":[120,40,2,2]}],"fail":[]}
	var sim := Simulation.new()
	sim.load_mission(mission)
	var apron_weapon_height: float = Spatial.weapon_height(sim.units[0])
	check(is_zero_approx(float(sim.units[0].base_height)), "An operator starts at apron level")
	check(is_equal_approx(float(sim.civilians[0].base_height),2.022), "A passenger starts on the actual aircraft floor")
	check(is_equal_approx(Spatial.eye_height(sim.civilians[0]),3.642), "Sight height includes the cabin floor")
	var recording := Replay.new()
	recording.begin(mission)
	recording.capture(sim.snapshot(true))
	check(bool(sim.issue("alpha","MOVE",{"target":[44,40]},true).ok), "The operator boards using an ordinary movement order")
	for tick in range(600):
		sim.step(1.0/30.0)
		if Vector2(float(sim.units[0].x),float(sim.units[0].z)).distance_to(Vector2(44,40)) < 0.05: break
	check(is_equal_approx(float(sim.units[0].base_height),2.022), "Movement synchronizes the operator's floor at entry")
	var cabin_weapon_height: float = Spatial.weapon_height(sim.units[0])
	check(is_equal_approx(cabin_weapon_height, apron_weapon_height + 2.022), "Weapon height shares the visible operator's floor without changing the model's muzzle")
	check(not sim.nav.shot_clear_height(Vector2(44,40),Vector2(54,40),cabin_weapon_height,cabin_weapon_height), "The raised cabin wall blocks a shot at the actual weapon height")
	var final := sim.snapshot(true)
	recording.capture(final)
	recording.finish(final)
	var restored := Replay.new()
	var result := restored.load_data(JSON.parse_string(JSON.stringify(recording.export_data())))
	check(bool(result.ok), "An elevated operation replay imports: " + str(result.get("message","")))
	if result.ok:
		check(is_equal_approx(float(restored.seek(restored.duration,true).units[0].base_height),2.022), "Replay preserves the same floor height")
	check(bool(sim.issue("alpha","MOVE",{"target":[30,40]},true).ok), "The operator can leave the cabin")
	for tick in range(600):
		sim.step(1.0/30.0)
		if Vector2(float(sim.units[0].x),float(sim.units[0].z)).distance_to(Vector2(30,40)) < 0.05: break
	check(is_zero_approx(float(sim.units[0].base_height)), "Leaving restores ground level without resizing the person")
	print("BREACH_HISTORICAL_ELEVATION_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
