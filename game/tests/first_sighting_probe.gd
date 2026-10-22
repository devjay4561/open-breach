extends SceneTree
## Native first-sighting probe (headless OK): godot --headless --path game --script res://tests/first_sighting_probe.gd -- <render fps> <sim seconds>
## Per sighting: how long a visible alive enemy stood outside the fog polygons, public vs real door progress, and the same with the real doors.
const World = preload("res://scripts/world_view.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Presentation = preload("res://scripts/presentation_state.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const STEP := 1.0 / 30.0
const VisibilityField = preload("res://scripts/visibility_field.gd")
func _initialize() -> void:
	call_deferred("_run")
func _inside(world: Node, p: Vector2) -> bool:
	for polygon: PackedVector2Array in world._visibility.polygons:
		if Geometry2D.is_point_in_polygon(p, polygon): return true
	return false
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var delta := 1.0 / float(args[0]) if args.size() > 0 else 1.0 / 60.0
	var mission: Dictionary = Catalog.load("M01")
	mission["seed"] = 2130704788
	var sim := Simulation.new()
	sim.load_mission(mission.duplicate(true))
	var world := World.new()
	root.add_child(world)
	world.build(mission.duplicate(true))
	var presentation := Presentation.new()
	var truth_field := VisibilityField.new()
	truth_field.build(mission.duplicate(true))
	var runs := {}
	var run_stats: Array = []
	var ids := ["alpha", "bravo", "charlie", "delta"]
	var paths := [[[11,12.6],[12,8.5],[12,5.5]],[[13,12.6],[17,12.5],[18.5,9]],[[11,14.7],[8,12],[5,10]],[[13,14.7],[16,12.5],[18.6,8.5]]]
	for i in range(4):
		for t in paths[i]: sim.plan_move(ids[i], {"target": t}, true)
	var shown: Dictionary = sim.snapshot_pair().observed
	presentation.reset(shown)
	var accumulator := 0.0
	var seen_before := {}
	var frame := 0
	var lag_frames := 0
	var sightings := 0
	while sim.time < float(args[1]) if args.size() > 1 else 45.0:
		accumulator += delta
		while accumulator >= STEP:
			accumulator -= STEP
			sim.step(STEP)
			var pair: Dictionary = sim.snapshot_pair()
			shown = pair.observed
			presentation.capture(shown, pair.observed.get("events", []))
		var state: Dictionary = presentation.sample(accumulator / STEP)
		state["presentation_paused"] = false
		world.display(state, "alpha", false, delta)
		frame += 1
		truth_field.update(state.units, sim.doors, state.get("smoke_zones", []))
		for enemy: Dictionary in state.enemies:
			var id := str(enemy.id)
			var vis := bool(enemy.get("visible", false)) and float(enemy.get("hp", 0.0)) > 0.0
			if not vis:
				if runs.has(id):
					run_stats.append(runs[id])
					runs.erase(id)
				continue
			var at := Vector2(float(enemy.x), float(enemy.z))
			var inside: bool = world._fog_covers(at) # footprint test, same as the shipped check
			var truth_inside := false
			for polygon: PackedVector2Array in truth_field.polygons:
				if Geometry2D.is_point_in_polygon(at, polygon): truth_inside = true
			if not runs.has(id):
				sightings += 1
				runs[id] = {"id": id, "t0": float(state.presentation_time), "outside_frames": 0, "outside_until": -1.0, "truth_outside_frames": 0, "shown_outside": 0, "door": ""}
				for door: Dictionary in state.doors:
					var real := {}
					for actual: Dictionary in sim.doors:
						if actual.id == door.id: real = actual
					if absf(float(door.get("progress", 0.0)) - float(real.get("progress", 0.0))) > 0.05:
						runs[id].door += " %s public=%.2f(%s,obs=%s) sim=%.2f(%s)" % [door.id, float(door.get("progress", 0.0)), door.get("state"), door.get("observed"), float(real.get("progress", 0.0)), real.get("state")]
			var run: Dictionary = runs[id]
			if not inside and world._entity_nodes.has(id) and world._entity_nodes[id].node.visible and not world._fog_pools.has(id): run.shown_outside += 1
			if not inside:
				run.outside_frames += 1
				run.outside_until = float(state.presentation_time)
				lag_frames += 1
			if not truth_inside: run.truth_outside_frames += 1
	for id in runs: run_stats.append(runs[id])
	for run: Dictionary in run_stats:
		if run.outside_frames > 0 or run.truth_outside_frames > 0:
			print("SIGHT enemy=%s first=%.3f outside_frames=%d until=%.3f ms_outside=%d truth_field_outside_frames=%d DISPLAYED_outside_frames=%d doors:%s" % [run.id, run.t0, run.outside_frames, run.outside_until, int((run.outside_until - run.t0) * 1000.0), run.truth_outside_frames, run.shown_outside, run.door])
	var shown_total := 0
	for run: Dictionary in run_stats: shown_total += int(run.shown_outside)
	print("SIGHT_SUMMARY fps=%d sightings=%d state_frames_outside_fog=%d displayed_frames_outside_fog=%d" % [int(round(1.0 / delta)), sightings, lag_frames, shown_total])
	quit()
