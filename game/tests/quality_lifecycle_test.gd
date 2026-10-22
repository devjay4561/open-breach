extends SceneTree
## Real scene construction/cleanup and controller transitions under headless Godot.
## Rendering calls construct their actual nodes, but this does not measure GPU FPS.
const MainScene = preload("res://main.tscn")
const STEP: float = 1.0 / 30.0
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _settle() -> void:
	await process_frame
	await process_frame

func _sample(session: Node, cycle: int, phase: String) -> Dictionary:
	return {"cycle": cycle, "phase": phase, "node_count": get_node_count(),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"static_memory_bytes": OS.get_static_memory_usage(), "render_entities": session.world._entity_nodes.size(),
		"active_effects": session.world._flashes.size(), "replay_frames": session.recorder.frames.size(),
		"mode": session.mode, "mission": session.mission_id}

func _run() -> void:
	var initial_nodes: int = get_node_count()
	var session: Node = MainScene.instantiate()
	root.add_child(session)
	session.set_process(false)
	await _settle()
	# Retry restores the first plan, not the edited or partially executed queue.
	session._action({"action": "start", "mission": "M01"})
	session._action({"action": "command", "type": "MOVE", "args": {"target": [12.2, 14.6]}})
	var planned: String = JSON.stringify(session._export_plan())
	session._action({"action": "toggle"})
	for tick_index: int in range(12): session._process(STEP)
	session._action({"action": "clear"})
	session._action({"action": "retry_plan"})
	check(session.mode == "PLANNING" and session.sim.time == 0.0, "Plan retry must reset time and remain paused")
	check(JSON.stringify(session._export_plan()) == planned, "Plan retry lost the original automatic door and move orders")
	check(session.recorder.frames.size() == 1, "Plan retry retained old replay history")
	check(session.sim.units[0].hp == 100, "Plan retry retained damage")
	session._action({"action": "retry_plan"})
	check(JSON.stringify(session._export_plan()) == planned, "Repeated plan retry is not stable")
	session._action({"action": "retry"})
	check(session.initial_plan.is_empty() and session.sim.units[0].commands.is_empty(), "Fresh retry must clear the previous plan")
	session._action({"action": "start", "mission": "T01"})
	session._action({"action": "retry_plan"})
	check(session.mission_id == "T01" and session.sim.units[0].commands.is_empty(), "Plan retry leaked another mission's plan")
	var samples: Array = []
	var started_us: int = Time.get_ticks_usec()
	for cycle: int in range(20):
		session._action({"action": "start", "mission": "M01"})
		session._process(0.0)
		await _settle()
		check(session.mode == "PLANNING" and session.sim.units.size() == 4, "Restart did not restore four operatives in planning mode")
		session._action({"action": "command", "type": "WAIT", "args": {"duration": 0.25}})
		session._action({"action": "toggle"})
		for tick_index: int in range(15):
			session._process(STEP)
		session._action({"action": "pause"})
		check(session.mode == "PLANNING", "Pause did not settle execution")
		var frozen: String = JSON.stringify(session.sim.snapshot(true))
		for frame: int in range(3):
			session._process(STEP)
		check(JSON.stringify(session.sim.snapshot(true)) == frozen, "Planning presentation advanced authoritative game state")
		var replay_data: Dictionary = session.recorder.export_data()
		session._action({"action": "import_replay", "data": replay_data})
		session._process(0.0)
		check(session.mode == "REPLAY", "A normal short recording did not reopen as a replay")
		session._action({"action": "replay_toggle"})
		for seek_index: int in range(20):
			session._action({"action": "replay_seek", "time": 0.0 if seek_index % 2 == 0 else session.recorder.duration})
			session._process(0.0)
		session._action({"action": "replay_seek", "time": 0.0})
		session._process(0.0)
		var rewind: String = JSON.stringify(session.shown)
		session._action({"action": "replay_seek", "time": session.recorder.duration})
		session._action({"action": "replay_seek", "time": 0.0})
		session._process(0.0)
		check(JSON.stringify(session.shown) == rewind, "Repeated controller replay seek changed the restored state")
		session._action({"action": "menu"})
		session._action({"action": "lab"})
		session._process(0.1)
		check(session.mode == "LAB" and is_instance_valid(session.lab), "Presentation lab did not open from the menu")
		session._action({"action": "lab_control", "scene": "reload", "seek": 1.2})
		session._action({"action": "menu"})
		await _settle()
		check(not is_instance_valid(session.lab), "Leaving the lab retained its scene")
		session._action({"action": "start", "mission": "T01"})
		session._process(0.0)
		await _settle()
		check(session.sim.units.size() == 2 and session.world._entity_nodes.size() == 2, "Switching to training retained house actors")
		session._action({"action": "start", "mission": "M01"})
		session._process(0.0)
		await _settle()
		check(session.sim.time == 0.0 and session.recorder.frames.size() == 1, "Fresh mission retained old time or replay frames")
		check(session.world._flashes.is_empty(), "Fresh mission retained effects from previous scenes")
		samples.append(_sample(session, cycle + 1, "fresh-M01-planning"))
		if (cycle + 1) % 5 == 0:
			print("QUALITY_LIFECYCLE cycle=%d nodes=%d objects=%d resources=%d" % [cycle + 1, samples[-1].node_count, samples[-1].object_count, samples[-1].resource_count])
	var warm: Array = samples.slice(3)
	for property: String in ["node_count", "orphan_nodes", "render_entities", "active_effects", "replay_frames"]:
		var first: int = int(warm[0][property])
		for sample: Dictionary in warm:
			check(int(sample[property]) == first, "Identical warmed restart checkpoint accumulated " + property)
	# Resource/allocator caches need not return to a cold baseline. The resource
	# count must still stabilize across the same warmed scene, not grow per cycle.
	check(int(warm[-1].resource_count) <= int(warm[0].resource_count) + 4, "Resource objects continued growing after the warm-up cycles")
	check(int(warm[-1].object_count) <= int(warm[0].object_count) + 32, "Engine object count continued growing after the warm-up cycles")
	session.queue_free()
	await _settle()
	check(get_node_count() == initial_nodes, "Destroying the main session did not release its scene nodes")
	var report := {"kind": "headless-real-scene-lifecycle", "cycles": 20, "warmup_cycles_excluded": 3,
		"wall_execution_ms": float(Time.get_ticks_usec() - started_us) / 1000.0, "samples": samples,
		"nodes_before_session": initial_nodes, "nodes_after_session_free": get_node_count(),
		"checks": checks, "failures": failures,
		"limitations": ["Actual main/world/LAB scene construction and controller transitions were exercised in headless Godot.",
			"Replay input comes from the main controller's real short recording; no enemy positions or results were injected.",
			"This checks lifecycle invariants and native object proxies, not browser DOM cleanup, WebAssembly memory, GPU rendering, audio output or human usability."]}
	var directory: String = ProjectSettings.globalize_path("res://../tests/artifacts/play-quality")
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(directory.path_join("scene-lifecycle.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "  "))
	print("BREACH_QUALITY_LIFECYCLE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
