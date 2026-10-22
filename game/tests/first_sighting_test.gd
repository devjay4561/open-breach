extends SceneTree
## A just-sighted enemy never stands on unlit floor: it is held (at most SIGHTING_GRACE) until the fog covers it, and a
## sim-visible enemy that the polygons still do not cover lights its own floor. Reproduces the door-opening case on M01.
const World = preload("res://scripts/world_view.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Presentation = preload("res://scripts/presentation_state.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

## Plays the scripted M01 plan to `seconds` at `fps` render frames per second and logs every frame.
func _play(fps: float, seconds: float, variable: bool = false) -> Dictionary:
	var delta := 1.0 / fps
	var lcg := 12345
	var max_delta := 0.0
	var mission: Dictionary = Catalog.load("M01")
	mission["seed"] = 2130704788
	var sim := Simulation.new()
	sim.load_mission(mission.duplicate(true))
	var world := World.new()
	root.add_child(world)
	world.build(mission.duplicate(true))
	var presentation := Presentation.new()
	var ids := ["alpha", "bravo", "charlie", "delta"]
	var paths := [[[11,12.6],[12,8.5],[12,5.5]],[[13,12.6],[17,12.5],[18.5,9]],[[11,14.7],[8,12],[5,10]],[[13,14.7],[16,12.5],[18.6,8.5]]]
	for i in range(4):
		for target in paths[i]: sim.plan_move(ids[i], {"target": target}, true)
	presentation.reset(sim.snapshot_pair().observed)
	var accumulator := 0.0
	var held_frames: Array = []
	var shown_unlit := 0
	var longest_hold := 0.0
	var hold_started := {}
	var stale_door_sightings := 0
	var pooled_frames := 0
	var sightings := {}
	while sim.time < seconds:
		if variable:
			lcg = (lcg * 1103515245 + 12345) & 0x7fffffff
			delta = 0.010 + 0.040 * float(lcg % 1000) / 1000.0 # 10..50 ms frames
		max_delta = maxf(max_delta, delta)
		accumulator += delta
		while accumulator >= STEP:
			accumulator -= STEP
			sim.step(STEP)
			var pair: Dictionary = sim.snapshot_pair()
			presentation.capture(pair.observed, pair.observed.get("events", []))
		var state: Dictionary = presentation.sample(accumulator / STEP)
		state["presentation_paused"] = false
		world.display(state, "alpha", false, delta)
		for enemy: Dictionary in state.enemies:
			var id := str(enemy.id)
			if not bool(enemy.get("visible", false)) or float(enemy.get("hp", 0.0)) <= 0.0:
				hold_started.erase(id)
				continue
			var entry: Dictionary = world._entity_nodes.get(id, {})
			var displayed: bool = not entry.is_empty() and entry.node.visible
			var at := Vector2(float(enemy.x), float(enemy.z))
			if not sightings.has(id):
				sightings[id] = float(state.presentation_time)
				for door: Dictionary in state.doors:
					for actual: Dictionary in sim.doors:
						if actual.id == door.id and float(actual.progress) - float(door.get("progress", 0.0)) > 0.15 and str(actual.state) == "OPENING": stale_door_sightings += 1
			if displayed:
				hold_started.erase(id)
				if world._fog_pools.has(id): pooled_frames += 1
				elif not world._fog_covers(at): shown_unlit += 1
			else:
				if not hold_started.has(id): hold_started[id] = float(state.presentation_time)
				longest_hold = maxf(longest_hold, float(state.presentation_time) - float(hold_started[id]))
				held_frames.append([snappedf(float(state.presentation_time), 0.0001), id])
	world.queue_free()
	return {"held": held_frames, "shown_unlit": shown_unlit, "longest_hold": longest_hold, "stale_door_sightings": stale_door_sightings, "pooled": pooled_frames, "sightings": sightings.size(), "max_delta": max_delta}

func _run() -> void:
	var first := _play(60.0, 8.0)
	_check(int(first.sightings) >= 2, "The scripted plan sights enemies through opening doors")
	_check(int(first.stale_door_sightings) >= 2, "Reproduced: at the sighting the public door is still well behind the real one (%d sightings)" % int(first.stale_door_sightings))
	_check(not (first.held as Array).is_empty(), "The stale door leaves the fog behind, so new enemies are actually held back")
	_check(int(first.shown_unlit) == 0, "No frame displays an enemy standing on unlit floor (%d frames)" % int(first.shown_unlit))
	_check(float(first.longest_hold) <= World.SIGHTING_GRACE + 1.0 / 60.0 + 0.0001, "An enemy is never held longer than the %.0f ms grace (longest %.0f ms)" % [World.SIGHTING_GRACE * 1000.0, float(first.longest_hold) * 1000.0])
	var second := _play(60.0, 8.0)
	_check((first.held as Array) == (second.held as Array), "The held frames are identical across two identical runs (deterministic)")
	var slow := _play(20.0, 8.0)
	_check(int(slow.shown_unlit) == 0 and float(slow.longest_hold) <= World.SIGHTING_GRACE + 0.05 + 0.0001, "A 20 fps client behaves the same (longest hold %.0f ms)" % (float(slow.longest_hold) * 1000.0))
	var jittery := _play(60.0, 8.0, true)
	_check(int(jittery.shown_unlit) == 0 and float(jittery.longest_hold) <= World.SIGHTING_GRACE + float(jittery.max_delta) + 0.0001, "With 10-50 ms frames the longest hold is at most the grace plus one frame (%.0f ms, max frame %.0f ms)" % [float(jittery.longest_hold) * 1000.0, float(jittery.max_delta) * 1000.0])
	_check(not (jittery.held as Array).is_empty(), "...and the variable-delta run exercises the hold")
	_synthetic_checks()
	print("BREACH_FIRST_SIGHTING_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)

## Synthetic map: one operator looking away from an enemy, so the enemy is sim-visible but outside every polygon.
func _synthetic_world(with_door: bool) -> Node:
	var world := World.new()
	root.add_child(world)
	var doors: Array = [{"id": "d", "x": 8.0, "z": 10.0, "w": 0.24, "d": 1.8, "axis": "z"}] if with_door else []
	world.build({"id": "GRACE", "bounds": [24, 20], "rooms": [{"id": "room", "x": 12, "z": 10, "w": 20, "d": 18}], "walls": [], "doors": doors, "props": [], "units": [], "enemies": [], "civilians": []})
	return world

func _frame(clock: float, with_door: bool, visible: bool = true, extra: Dictionary = {}) -> Dictionary:
	var frame := {"units": [{"id": "alpha", "x": 4.0, "z": 10.0, "hp": 100.0, "facing": PI, "commands": []}], "enemies": [{"id": "e1", "x": 12.0, "z": 10.0, "hp": 100.0, "facing": 0.0, "status": "READY", "visible": visible, "commands": []}], "civilians": [], "doors": [], "events": [], "tick": int(clock * 30.0), "time": clock, "presentation_time": clock}
	if with_door: frame["doors"] = [{"id": "d", "x": 8.0, "z": 10.0, "w": 0.24, "d": 1.8, "axis": "z", "state": "OPENING", "progress": 0.3, "observed": true}]
	frame.merge(extra, true)
	return frame

func _shown(world: Node) -> bool:
	return world._entity_nodes.has("e1") and world._entity_nodes["e1"].node.visible

func _synthetic_checks() -> void:
	# Door scenario: held for the grace, then displayed with its own sight fan.
	var world := _synthetic_world(true)
	var displayed_at := -1.0
	var clock := 5.0
	var contact := [{"seq": 1, "type": "CONTACT", "time": 5.0, "to": [12.0, 10.0], "enemy_id": "e1"}]
	var leaked_while_held := 0
	var ping_after := 0
	for index in range(12):
		var extra := {"events": contact, "presentation_events": contact} if index == 0 else {}
		world.display(_frame(clock, true, true, extra), "alpha", false, 1.0 / 60.0)
		if _shown(world) and displayed_at < 0.0: displayed_at = clock - 5.0
		if index == 0: _check(not _shown(world), "A sim-visible enemy outside the polygons next to a moving door is held on its first frame")
		# Nothing that belongs to the enemy may be drawn while it is held: no body, halo, disc or label, and no red ping at its feet.
		var visible_children := 0
		if world._entity_nodes.has("e1"):
			for child in world._entity_nodes["e1"].node.find_children("*", "Node3D", true, false):
				if (child as Node3D).is_visible_in_tree(): visible_children += 1
		var ping_vertices := 0
		if world._event_mesh.get_surface_count() > 0:
			for vertex: Vector3 in world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				if vertex.y > 0.15 and vertex.y < 0.3 and Vector2(vertex.x, vertex.z).distance_to(Vector2(12.0, 10.0)) < 2.5: ping_vertices += 1
		if not _shown(world):
			leaked_while_held += visible_children + ping_vertices
		elif ping_vertices > 0:
			ping_after += 1
		clock += 1.0 / 60.0
	_check(leaked_while_held == 0, "While an enemy is held nothing of it is drawn: no visible overlay node and no spotted ring (%d leaked)" % leaked_while_held)
	_check(ping_after > 0, "...and the spotted ring starts once the enemy appears")
	_check(displayed_at >= World.SIGHTING_GRACE - 1.0 / 60.0 - 0.0001 and displayed_at <= World.SIGHTING_GRACE + 1.0 / 60.0 + 0.0001, "...and appears when the 120 ms grace is used up (%.0f ms)" % (displayed_at * 1000.0))
	_check(world._fog_pools.has("e1") and world._pool_polygons.size() == 1, "...with a local sight fan under it")
	# H1: seeks and scrubs never hide a known, pooled enemy.
	world.display(_frame(clock + 30.0, true, true, {"presentation_reset": true, "tick": 1500}), "alpha", false, 1.0 / 60.0)
	_check(_shown(world), "A forward seek keeps a pooled enemy displayed")
	var scrub_hidden := 0
	for index in range(60):
		world.display(_frame(clock + 40.0 + float(index) * 0.5, true, true, {"presentation_reset": true, "tick": 2000 + index * 15}), "alpha", false, 1.0 / 60.0)
		if not _shown(world): scrub_hidden += 1
	_check(scrub_hidden == 0, "60 consecutive scrub frames keep the enemy displayed (hidden on %d)" % scrub_hidden)
	world.display(_frame(clock + 80.0, true, true, {"tick": 2400}), "alpha", false, 1.0 / 60.0)
	_check(_shown(world), "...and the first live frame after the scrub does not start a new grace")
	# Reveal toggle off -> on -> off.
	world.display(_frame(clock + 81.0, true, true, {"presentation_reveal": true, "tick": 2430}), "alpha", false, 1.0 / 60.0)
	var reveal_hidden := 0 if _shown(world) else 1
	world.display(_frame(clock + 81.02, true, true, {"tick": 2431}), "alpha", false, 1.0 / 60.0)
	if not _shown(world): reveal_hidden += 1
	_check(reveal_hidden == 0, "Toggling reveal on and off does not re-hold the enemy")
	world.queue_free()
	# R4-M1: a PLAYING replay seeking forward next to a moving door must not blink a displayed enemy out.
	var playing := _synthetic_world(true)
	clock = 5.0
	for index in range(10):
		playing.display(_frame(clock, true), "alpha", false, 1.0 / 60.0)
		clock += 1.0 / 60.0
	_check(_shown(playing), "A playing enemy beside a moving door is displayed once its grace is used")
	playing.display(_frame(clock + 30.0, true, true, {"presentation_reset": true, "tick": 1500}), "alpha", false, 1.0 / 60.0)
	var blink := 0 if _shown(playing) else 1
	clock += 30.0
	for index in range(12):
		clock += 1.0 / 60.0
		playing.display(_frame(clock, true, true, {"tick": 1500 + index + 1}), "alpha", false, 1.0 / 60.0)
		if not _shown(playing): blink += 1
	_check(blink == 0, "A forward reset while playing leaves 0 hidden frames (hidden on %d)" % blink)
	# Rewind (clock backwards) while playing: also no blink.
	playing.display(_frame(2.0, true, true, {"tick": 60}), "alpha", false, 1.0 / 60.0)
	var rewind_blink := 0 if _shown(playing) else 1
	for index in range(12):
		playing.display(_frame(2.0 + float(index + 1) / 60.0, true, true, {"tick": 61 + index}), "alpha", false, 1.0 / 60.0)
		if not _shown(playing): rewind_blink += 1
	_check(rewind_blink == 0, "A backward seek while playing leaves 0 hidden frames (hidden on %d)" % rewind_blink)
	playing.queue_free()
	# R4-L1: a door that was never seen moving does not count as "recently moved".
	var still := _synthetic_world(true)
	var still_frame := _frame(5.0, true)
	still_frame.doors[0]["state"] = "OPEN"
	still_frame.doors[0]["progress"] = 1.0
	still.display(still_frame, "alpha", false, 1.0 / 60.0)
	_check(_shown(still), "A door that is merely open (first look, no motion) does not hold the enemy")
	still.queue_free()
	# R4-L2: a moving pooled enemy rebuilds its fan only on frames where the fog refreshes (30 Hz), not every frame.
	var mover := _synthetic_world(false)
	clock = 5.0
	for index in range(40):
		var moving := _frame(clock, false)
		moving.enemies[0]["x"] = 12.0 + 0.1 * float(index)
		mover.display(moving, "alpha", false, 1.0 / 120.0)
		clock += 1.0 / 120.0
	_check(mover._pool_rebuilds <= 14, "A moving pooled enemy rebuilds its fan about 30 times a second, not every frame (%d rebuilds in 40 frames at 120 fps)" % mover._pool_rebuilds)
	_check(mover._pool_rebuilds >= 2, "...but it does follow the enemy")
	mover.queue_free()
	# R4-L3: no fan inside smoke (the sight polygons cut smoke out on purpose); the enemy is still displayed.
	var smoky := _synthetic_world(false)
	smoky.display(_frame(5.0, false, true, {"smoke_zones": [{"x": 12.0, "z": 10.0, "radius": 1.5}]}), "alpha", false, 1.0 / 60.0)
	_check(_shown(smoky) and smoky._pool_polygons.is_empty(), "An enemy inside smoke is displayed without a fan")
	smoky.queue_free()
	# Pause: the settled truth plus the fan, immediately, even at a frozen clock.
	var paused := _synthetic_world(true)
	paused.display(_frame(5.0, true), "alpha", true, 0.05)
	_check(_shown(paused) and paused._fog_pools.has("e1"), "A paused game shows the settled enemy with its fan on the first frame")
	paused.queue_free()
	# No door nearby: nothing explains a lag, so no hold; the enemy is shown with its fan at once.
	var open_floor := _synthetic_world(false)
	open_floor.display(_frame(5.0, false), "alpha", false, 1.0 / 60.0)
	_check(_shown(open_floor) and open_floor._fog_pools.has("e1"), "Without a moving door the enemy is displayed immediately with its fan")
	open_floor.queue_free()
	# M2: a flickering sighting (66 ms windows) is still shown on most visible frames.
	var flicker := _synthetic_world(true)
	var visible_frames := 0
	var shown_frames := 0
	clock = 10.0
	for index in range(60):
		var up := (index / 4) % 2 == 0 # 4 frames (66 ms) on, 4 off
		flicker.display(_frame(clock, true, up), "alpha", false, 1.0 / 60.0)
		if up:
			visible_frames += 1
			if _shown(flicker): shown_frames += 1
		clock += 1.0 / 60.0
	_check(float(shown_frames) >= 0.8 * float(visible_frames), "A flickering sighting is displayed on most visible frames (%d of %d)" % [shown_frames, visible_frames])
	flicker.queue_free()
	# M1: the fan is clipped by walls and never touches the exploration memory.
	var walled := _synthetic_world(false)
	walled._obstacles.append(Rect2(12.30, 5.0, 0.24, 10.0)) # a 0.24 m wall whose near face is 0.30 m from the enemy
	var memory_surfaces: int = walled._memory_canvas._mesh.get_surface_count()
	walled.display(_frame(5.0, false), "alpha", false, 1.0 / 60.0)
	_check(walled._pool_polygons.size() == 1, "The enemy beside the wall has a fan")
	if walled._pool_polygons.size() == 1:
		var fan: PackedVector2Array = walled._pool_polygons[0]
		_check(Geometry2D.is_point_in_polygon(Vector2(12.2, 10.0), fan), "The fan lights the floor on the enemy's side of the wall")
		_check(not Geometry2D.is_point_in_polygon(Vector2(12.84, 10.0), fan), "No light 0.3 m beyond the far face of the wall (sight == 0 there)")
		var furthest := 0.0
		for vertex in fan: furthest = maxf(furthest, vertex.x)
		_check(furthest <= 12.30 + 0.001, "The fan stops at the wall's near face")
	_check(_pool_in_current_sight_only(walled), "The fan is drawn into the CurrentSight viewport only")
	_check(walled._memory_canvas._mesh.get_surface_count() == memory_surfaces or walled._visibility.polygons.size() > 0, "The exploration memory mesh is the sight polygons, never the fan")
	walled.queue_free()

func _pool_in_current_sight_only(world: Node) -> bool:
	if world._pool_node.get_parent() != world._fog_viewport: return false
	for child in world._memory_viewport.get_children():
		if child == world._pool_node or child.name == "SightPools": return false
	return world._memory_canvas._mesh != world._pool_mesh
