extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const Schema = preload("res://scripts/mission_schema.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture() -> Dictionary:
	return {"schema_version":2,"id":"WIDE_REPLAY_QA","revision":1,"custom":true,"seed":72,"title":"Wide objective replay","variant":"normal",
		"bounds":[128,80],"focus":[64,40],"rooms":[{"id":"ground","x":64.0,"z":40.0,"w":128.0,"d":80.0}],
		"walls":[{"id":"barrier","x":64.0,"z":27.0,"w":0.30,"d":54.0}],"props":[],"doors":[],
		"units":[{"id":"alpha","name":"Alpha","role":"Assault","weapon":"standard","x":4.0,"z":40.0,"facing":0.0}],"enemies":[],"civilians":[],
		"environment":{"biome":"harbour","ground_color":"#637a6b","ground_surface":"concrete","water":false,"water_level":-3.45,"time_of_day":"day","lighting":1.0},
		"interactive_targets":[{"id":"radio","x":112.0,"z":40.0,"w":4.0,"d":4.0,"label":"Radio room","action":"disable","duration":2.0}],
		"win":[{"type":"targets_complete","targets":["radio"]}],"fail":[{"type":"no_shots"}],"objectives":["Reach the distant radio and disable it"]}

func _initialize() -> void:
	var mission := fixture()
	var validated: Dictionary = Schema.check(mission)
	check(bool(validated.ok),"Large objective fixture validates: "+str(validated.get("message","")))
	var sim := Simulation.new()
	sim.load_mission(mission)
	var recording := Replay.new()
	recording.begin(mission)
	recording.capture(sim.snapshot(true))
	check(bool(sim.issue("alpha","MOVE",{"target":[112.0,40.0]},true).ok),"A planned movement command accepts a target more than 100 metres away")
	var initial_progress := float(sim.interactive_targets[0].progress)
	var walked := 0.0
	var previous := Vector2(4,40)
	for i: int in range(6000):
		sim.step(1.0/30.0)
		var current := Vector2(float(sim.units[0].x),float(sim.units[0].z))
		walked += current.distance_to(previous)
		previous = current
		recording.capture(sim.snapshot(true))
		if not sim.result.is_empty(): break
	var final: Dictionary = sim.snapshot(true)
	recording.finish(final)
	check(initial_progress == 0.0,"Physical target starts with no remote completion progress")
	check(walked>100.0,"Simulation walks a full physical route past the 32 metre legacy extent")
	check(bool(sim.result.get("success",false)),"Stationary arrival performs the target interaction and completes the operation")
	check(bool(final.interactive_targets[0].completed) and is_equal_approx(float(final.interactive_targets[0].progress),2.0),"Objective duration is accumulated in actual simulation seconds")
	check(int(final.objectives.targets_completed)==1 and int(final.objectives.targets_total)==1,"Objective counters include completed physical targets")
	var exported: Dictionary = JSON.parse_string(JSON.stringify(recording.export_data()))
	var loaded := Replay.new()
	var result: Dictionary = loaded.load_data(exported)
	check(bool(result.ok),"Large mission replay imports: "+str(result.get("message","")))
	if result.ok:
		var ending: Dictionary = loaded.seek(loaded.duration,true)
		check(ending.interactive_targets == JSON.parse_string(JSON.stringify(final.interactive_targets)),"Replay preserves target progress and completion after JSON round-trip")
		check(ending.objectives==JSON.parse_string(JSON.stringify(final.objectives)),"Replay preserves physical objective counters")
		check(Vector2(float(ending.units[0].x),float(ending.units[0].z)).distance_to(previous)<0.00001,"Replay preserves final metre position")
		var baseline := JSON.stringify(loaded.export_data())
		for mutation: String in ["bounds","legacy_version","unknown_environment","water_level","target_progress","target_id","unknown_target_field","rule_target","target_event"]:
			var broken: Dictionary = exported.duplicate(true)
			match mutation:
				"bounds": broken.bounds = [513,80]
				"legacy_version": broken.mission_data.schema_version = 1
				"unknown_environment": broken.environment.weather = "rain"
				"water_level": broken.environment.water_level = 1.0
				"target_progress": broken.metadata[0].interactive_targets[0].progress = 3.0
				"target_id": broken.metadata[0].interactive_targets[0].id = "missing"
				"unknown_target_field": broken.metadata[0].interactive_targets[0].script = "remote"
				"rule_target": broken.metadata[0].win[0].targets = ["missing"]
				"target_event":
					for event: Dictionary in broken.events:
						if event.type == "TARGET_COMPLETE": event.target_id = "missing"
			check(not bool(loaded.load_data(broken).ok),"Malformed large replay is rejected: "+mutation)
			check(JSON.stringify(loaded.export_data())==baseline,"Rejected large replay leaves the loaded record intact: "+mutation)
	print("BREACH_LARGE_MAP_REPLAY_RESULT checks=%d failures=%d walked_m=%.2f duration_s=%.2f bytes=%d" % [checks,failures.size(),walked,sim.time,recording.export_size_bytes()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
