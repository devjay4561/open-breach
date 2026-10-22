extends SceneTree
## Ten minutes of the authored M01 simulation, not a browser/GPU performance run.
const Simulation = preload("res://scripts/simulation.gd")
const Replay = preload("res://scripts/replay.gd")
const STEP: float = 1.0 / 30.0
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var sim: RefCounted = Simulation.new()
	var recorder: RefCounted = Replay.new()
	sim.load_mission(data)
	recorder.begin(data)
	recorder.capture(sim.snapshot(true))
	check(bool(sim.issue("alpha", "OPEN_DOOR", {"door_id": "d1"}, true).get("ok", false)), "The first authored door command must be accepted")
	var samples: Array = []
	var started_us: int = Time.get_ticks_usec()
	var patrol_positions: Dictionary = {}
	var patrol_moved: Dictionary = {}
	for enemy: Dictionary in sim.enemies:
		if enemy.get("patrol", []).size() > 1:
			patrol_positions[enemy.id] = Vector2(float(enemy.x), float(enemy.z))
	for index: int in range(18000):
		sim.step(STEP)
		recorder.capture(sim.snapshot(true))
		if (index + 1) % 300 == 0:
			check(sim.tick == index + 1, "Simulation stopped or skipped ticks before ten minutes")
			check(not sim.pause_requested, "A valid long-session plan requested a failure pause")
			check(sim.result.is_empty(), "The authored partial mission unexpectedly terminated")
			check(sim.events.size() <= 40, "Simulation event window grew without a bound")
			for actor: Dictionary in sim.units + sim.enemies + sim.civilians:
				var point := Vector2(float(actor.x), float(actor.z))
				check(is_finite(point.x) and is_finite(point.y) and is_finite(float(actor.hp)), "Non-finite actor state appeared during the soak")
				check(sim.nav.walkable(point), "An actor entered a wall or a closed/opening door during the soak: " + str(actor.id))
				if patrol_positions.has(actor.id) and point.distance_to(patrol_positions[actor.id]) > 0.25:
					patrol_moved[actor.id] = true
			samples.append({"simulation_seconds": sim.time, "tick": sim.tick,
				"node_count": get_node_count(), "object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
				"static_memory_bytes": OS.get_static_memory_usage(), "replay_estimated_bytes": recorder.estimate_memory_bytes(),
				"frames": recorder.frames.size(), "events": sim.events.size(),
				"observed_enemies": sim.snapshot(false).enemies.size()})
			# Yield to the engine only for deferred cleanup; this is still accelerated logic.
			await process_frame
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_us) / 1000.0
	check(absf(sim.time - 600.0) < 0.001 and sim.tick == 18000, "Exactly ten minutes of fixed ticks must execute")
	check(patrol_moved.size() == patrol_positions.size() and not patrol_moved.is_empty(), "The authored enemy patrol AI never moved")
	check(sim.doors[0].state == "OPEN", "The first door did not finish its real interaction")
	check(sim.shots_fired > 0 or sim.enemies.any(func(enemy: Dictionary) -> bool: return bool(enemy.get("surrendered", false))), "The front-door scenario never exercised automatic combat or deterministic surrender")
	check(recorder.estimate_memory_bytes() <= 40 * 1024 * 1024, "The long recording exceeded the replay memory budget")
	var export_data: Dictionary = JSON.parse_string(JSON.stringify(recorder.export_data()))
	var encoded_bytes: int = JSON.stringify(export_data).to_utf8_buffer().size()
	check(encoded_bytes <= 20 * 1024 * 1024, "The ten-minute recording exceeded the file budget")
	var replay: RefCounted = Replay.new()
	var loaded: Dictionary = replay.load_data(export_data)
	check(bool(loaded.get("ok", false)), "A long recording failed its own import validation: " + str(loaded.get("message", "")))
	var seek_us: Array[int] = []
	if bool(loaded.get("ok", false)):
		var expected: String = JSON.stringify(replay.seek(300.0, true))
		for index: int in range(20):
			var seek_start: int = Time.get_ticks_usec()
			replay.seek(0.0, false)
			replay.seek(replay.duration, true)
			check(JSON.stringify(replay.seek(300.0, true)) == expected, "Long replay seeking accumulated state or changed event order")
			seek_us.append(Time.get_ticks_usec() - seek_start)
	var before_tick: int = sim.tick
	sim.step(STEP)
	recorder.capture(sim.snapshot(true))
	check(sim.tick == before_tick + 1, "The game stopped when the replay limit was reached")
	check(recorder.is_partial() and not recorder.complete and recorder.duration <= 600.000001, "The recording limit did not produce an honest partial replay")
	var report := {"kind": "accelerated-authored-mission-logic-soak", "mission": "M01", "simulation_seconds": sim.time,
		"ticks": sim.tick, "wall_execution_ms": elapsed_ms, "actor_count": sim.units.size() + sim.enemies.size() + sim.civilians.size(),
		"patrols_exercised": patrol_moved.keys(), "shots_fired": sim.shots_fired, "surrendered": sim.enemies.filter(func(enemy: Dictionary) -> bool: return bool(enemy.get("surrendered", false))).size(), "replay_duration": recorder.duration,
		"replay_file_bytes": encoded_bytes, "replay_estimated_memory_bytes": recorder.estimate_memory_bytes(),
		"seek_triplet_microseconds": seek_us, "samples": samples, "checks": checks, "failures": failures,
		"simulation_sha256": FileAccess.get_sha256("res://scripts/simulation.gd"),
		"limitations": ["No browser, GPU, audio device, or physical input was exercised.",
			"The original M01 map, enemies, perception and patrol code ran. Only the front door was opened; most of this long session is a quiet partial mission, not ten minutes of continuous combat.",
			"Wall execution time is accelerated logic-test duration, not rendered FPS. Godot static-memory and object counts are native process proxies, not WebAssembly/tab memory."]}
	_write_report("logic-soak.json", report)
	print("BREACH_QUALITY_SOAK_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _write_report(filename: String, report: Dictionary) -> void:
	var directory: String = ProjectSettings.globalize_path("res://../tests/artifacts/play-quality")
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
