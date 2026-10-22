extends SceneTree
const Schema = preload("res://scripts/mission_schema.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void:
	var map := {"schema_version":2,"id":"ELEVATED_QA","revision":1,"seed":1,"custom":true,"variant":"normal","title":"Cabin floor replay","bounds":[32,32],"focus":[16,16],
		"rooms":[{"id":"cabin","x":16.0,"z":16.0,"w":32.0,"d":32.0,"base_height":2.022}],"walls":[],"doors":[],"props":[],
		"units":[{"id":"alpha","name":"Alpha","role":"Assault","weapon":"standard","x":4.0,"z":4.0,"facing":0.0}],"enemies":[],"civilians":[],"objectives":["Reach destination"],"win":[{"type":"reach_zone","zone":[28,28,2,2]}]}
	check(bool(Schema.check(map).ok),"V2 accepts the real aircraft cabin floor elevation")
	var sim := Simulation.new()
	sim.load_mission(map)
	check(is_equal_approx(float(sim.units[0].get("base_height",-1)),2.022),"Simulation assigns the actor its actual cabin floor elevation")
	check(is_equal_approx(Spatial.eye_height(sim.units[0]),3.642),"Eye geometry includes the elevated floor")
	var ground_actor: Dictionary = sim.units[0].duplicate(true)
	ground_actor.base_height = 0.0
	check(is_equal_approx(Spatial.weapon_height(sim.units[0]) - Spatial.weapon_height(ground_actor),2.022),"Weapon geometry includes the elevated floor without changing the model's muzzle")
	var recording := Replay.new()
	recording.begin(map)
	recording.capture(sim.snapshot(true))
	for i: int in range(6):
		sim.step(1.0/30.0)
		recording.capture(sim.snapshot(true))
	recording.finish(sim.snapshot(true))
	var exported: Dictionary = JSON.parse_string(JSON.stringify(recording.export_data()))
	var loaded := Replay.new()
	var result: Dictionary = loaded.load_data(exported)
	check(bool(result.ok),"Elevated actor replay imports: "+str(result.get("message","")))
	if result.ok:
		check(is_equal_approx(float(loaded.seek(loaded.duration,true).units[0].base_height),2.022),"Replay preserves the actual cabin floor after JSON round-trip")
		var original := JSON.stringify(loaded.export_data())
		var definition: Dictionary = exported.states[int(exported.frames[0][2][1])]
		var offset: int = 2+definition.fields.find("base_height")
		check(offset>=2,"Actor floor is packed as a numeric replay field")
		for invalid: float in [-0.01,65.0,NAN]:
			var broken: Dictionary = exported.duplicate(true)
			broken.frames[0][2][offset]=invalid
			check(not bool(loaded.load_data(broken).ok),"Replay rejects malformed actor floor height: "+str(invalid))
			check(JSON.stringify(loaded.export_data())==original,"Rejected floor height leaves the loaded replay intact")
		var legacy: Dictionary = exported.duplicate(true)
		legacy.mission_data.schema_version=1
		legacy.mission_data.rooms[0].erase("base_height")
		check(not bool(loaded.load_data(legacy).ok),"Legacy replay rejects the new actor elevation numeric field")
	map.schema_version=1
	check(not bool(Schema.check(map).ok),"Legacy source map rejects room elevation")
	print("BREACH_ELEVATED_FLOOR_REPLAY_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
