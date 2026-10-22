extends SceneTree
## Explicit synthetic rendering workload, imported through the normal replay API.
## It is not a gameplay result: ten living combatants animate for forty seconds.
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")

func _initialize() -> void:
	var mission: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var simulation = Simulation.new()
	simulation.load_mission(mission)
	var baseline: Dictionary = simulation.snapshot(true)
	var recorder = Replay.new()
	recorder.begin(mission)
	var events: Array = []
	var sequence: int = 0
	for index: int in range(401):
		var time: float = index * 0.1
		var state: Dictionary = baseline.duplicate(true)
		state.time = time
		state.tick = index * 3
		for group: String in ["units", "enemies"]:
			for actor_index: int in range(state[group].size()):
				var actor: Dictionary = state[group][actor_index]
				var phase: float = time * 1.4 + actor_index * 0.8
				actor.x = float(baseline[group][actor_index].x) + sin(phase) * 0.35
				actor.z = float(baseline[group][actor_index].z) + cos(phase) * 0.25
				actor.facing = phase + PI * 0.5
				actor.move_facing = actor.facing
				actor.aim_facing = actor.facing + (PI * 0.5 if actor_index % 2 else 0.0)
				actor.travel_distance = time * 1.5
				actor.visible = true
				actor.status = "MOVING"
				actor.hp = 100.0
				actor.commands = []
				var cycle: float = fposmod(time + actor_index * 1.7, 8.0)
				if group == "units" and cycle >= 6.2:
					actor.status = "RELOADING"
					actor.commands = [{"id": "benchmark_reload_" + str(actor.id), "type": "RELOAD", "state": "RUNNING", "args": {}, "remaining": 8.0 - cycle}]
		for door: Dictionary in state.doors:
			door.state = "OPEN"
			door.progress = 1.0
		for civilian: Dictionary in state.civilians:
			civilian.visible = true
		if index % 3 == 0:
			var attacker: Dictionary = state.units[(index / 3) % state.units.size()]
			var target: Dictionary = state.enemies[(index / 3) % state.enemies.size()]
			if attacker.status != "RELOADING":
				sequence += 1
				events.append({"seq": sequence, "tick": index * 3, "time": time, "type": "SHOT", "attacker_id": attacker.id, "target_id": target.id, "from": [attacker.x, attacker.z], "to": [target.x, target.z], "hit": index % 9 == 0, "hostile": false})
		state.events = events.slice(maxi(0, events.size() - 40))
		if index == 400:
			recorder.finish(state)
		else:
			recorder.capture(state)
	var data: Dictionary = JSON.parse_string(JSON.stringify(recorder.export_data()))
	var validation: Dictionary = Replay.new().load_data(data)
	if not bool(validation.get("ok", false)):
		push_error("Synthetic combat benchmark invalid: " + str(validation.get("message", "")))
		quit(1)
		return
	var destination: String = ProjectSettings.globalize_path("res://../tests/artifacts/combat-benchmark.breach-replay.json")
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	print("COMBAT_BENCHMARK_FIXTURE duration=40 units=4 enemies=6 frames=%d bytes=%d path=%s" % [data.frames.size(), FileAccess.get_file_as_bytes(destination).size(), destination])
	quit()
