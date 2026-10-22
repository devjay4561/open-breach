extends SceneTree
## Phase 2 world-space hit feedback: tracers, impact bursts, kill stamp, camera kick, door frames,
## deterministic replay seek and bounded node growth. Presentation only; no simulation access.
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _shot(seq: int, time: float, hit: bool, hostile: bool, weapon: String = "standard", protection: String = "unprotected") -> Dictionary:
	return {"seq": seq, "type": "SHOT", "time": time, "from": [6, 12], "to": [6, 8], "attacker_id": "alpha", "hit": hit, "hostile": hostile, "weapon": weapon, "protection": protection}

func _down(seq: int, time: float, kind: String) -> Dictionary:
	return {"seq": seq, "type": "INCAPACITATED", "time": time, "to": [6, 8], "entity_id": "x%d" % seq, "kind": kind}

func _step(world: Node, state: Dictionary, clock: float, planning: bool = false) -> void:
	world._clock = clock
	world._update_effects(state, 0.0, planning)

## Vertices of the shared event mesh above `min_height` (tracers and bursts live at muzzle height).
func _verts(world: Node, min_height: float = 1.0) -> PackedVector3Array:
	var found := PackedVector3Array()
	if world._event_mesh.get_surface_count() == 0: return found
	for vertex: Vector3 in world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		# Brass casings sit within a metre of the shooter; tracers and bursts are further out.
		if vertex.y > min_height and (min_height < 0.5 or Vector2(vertex.x, vertex.z).distance_to(Vector2(6.0, 12.0)) > 1.6): found.append(vertex)
	return found

func _max_alpha(world: Node, min_height: float = 1.0) -> float:
	var best := 0.0
	if world._event_mesh.get_surface_count() == 0: return best
	var arrays: Array = world._event_mesh.surface_get_arrays(0)
	for index in range((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()):
		var vertex: Vector3 = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[index]
		if vertex.y > min_height and Vector2(vertex.x, vertex.z).distance_to(Vector2(6.0, 12.0)) > 1.6:
			best = maxf(best, (arrays[Mesh.ARRAY_COLOR] as PackedColorArray)[index].a)
	return best

func _hash(world: Node) -> int:
	if world._event_mesh.get_surface_count() == 0: return 0
	return hash(world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])

func _fresh_world() -> Node:
	var world = preload("res://scripts/world_view.gd").new()
	root.add_child(world)
	var mission: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json"))
	world.build(mission)
	return world

func _run() -> void:
	var world := _fresh_world()
	var state: Dictionary = {"events": []}
	# --- Tracer: hits stop at the target, misses run on and fade, no invented impact.
	_step(world, state, 5.0)
	state.events = [_shot(1, 5.0, false, false)]
	_step(world, state, 5.0)
	var miss_world := _verts(world)
	_check(not miss_world.is_empty(), "A shot draws a tracer on its first presented frame")
	var origin := Vector2(6.0, 12.0)
	var far := 0.0
	for tick in range(0, 7):
		_step(world, state, 5.0 + float(tick) * 0.01)
		for vertex in _verts(world):
			far = maxf(far, origin.distance_to(Vector2(vertex.x, vertex.z)))
	_check(far > 4.0 + 1.1, "A miss tracer continues past the target")
	_check(far < 4.0 + 3.2, "A miss tracer overshoots by a bounded distance")
	_step(world, state, 5.10)
	_check(_verts(world).is_empty(), "Tracer and bursts are gone by 100 ms")
	# --- Hit: confirmed impact burst, bounded and transient. Blocked sparks are distinct.
	state.events = [_shot(2, 6.0, true, false)]
	_step(world, state, 6.0)
	_step(world, state, 6.08)
	var hit_verts := _verts(world)
	var beyond := 0.0
	for vertex in hit_verts: beyond = maxf(beyond, origin.distance_to(Vector2(vertex.x, vertex.z)))
	_check(not hit_verts.is_empty() and beyond < 4.0 + 1.3, "A hit tracer ends at the target with a short burst")
	var colors_unprotected := (world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()
	_step(world, state, 6.30)
	_check(_verts(world).is_empty(), "Hit burst expires within 180 ms")
	state.events = [_shot(3, 7.0, true, false, "standard", "blocked")]
	_step(world, state, 7.0)
	_step(world, state, 7.08)
	var colors_blocked := world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	var blue := 0
	for color in colors_blocked:
		if color.b > color.r + 0.25 and color.a > 0.3: blue += 1
	var blue_unprotected := 0
	for color in colors_unprotected:
		if color.b > color.r + 0.25 and color.a > 0.3: blue_unprotected += 1
	_check(blue > 0 and blue_unprotected == 0, "Armour-blocked hits throw steel-blue sparks, unprotected hits do not")
	# --- Faction colour: enemy tracers are warm, friendly tracers pale.
	_step(world, state, 9.0)
	state.events = [_shot(4, 10.0, false, true)]
	_step(world, state, 10.0)
	_step(world, state, 10.03)
	var enemy_colors := world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	var verts := world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var warm := 0
	for index in range(verts.size()):
		if verts[index].y > 1.0 and enemy_colors[index].a > 0.5:
			if enemy_colors[index].g < 0.5: warm += 1
	_check(warm > 0, "Enemy tracers carry a warm orange-red glow")
	state.events = [_shot(5, 11.0, false, false)]
	_step(world, state, 11.0)
	_step(world, state, 11.03)
	enemy_colors = world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	verts = world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var friendly_red := 0
	for index in range(verts.size()):
		if verts[index].y > 1.0 and enemy_colors[index].a > 0.5 and enemy_colors[index].g < 0.5: friendly_red += 1
	_check(friendly_red == 0, "Friendly tracers stay pale yellow-white")
	# --- Shotgun: several diverging tracers vs one for a rifle.
	_step(world, state, 12.0)
	state.events = [_shot(6, 13.0, false, false, "shotgun")]
	_step(world, state, 13.0)
	_step(world, state, 13.025)
	var shotgun_width := 0.0
	for vertex in _verts(world): shotgun_width = maxf(shotgun_width, absf(vertex.x - 6.0))
	_step(world, state, 14.0)
	state.events = [_shot(7, 15.0, false, false)]
	_step(world, state, 15.0)
	_step(world, state, 15.025)
	var rifle_width := 0.0
	for vertex in _verts(world): rifle_width = maxf(rifle_width, absf(vertex.x - 6.0))
	_check(shotgun_width > rifle_width + 0.15, "Shotgun shots spread into diverging pellet tracers")
	# --- Reduced flash is thinner and dimmer.
	_step(world, state, 16.0)
	state.events = [_shot(8, 17.0, false, true)]
	_step(world, state, 17.0)
	_step(world, state, 17.025)
	var full_alpha := _max_alpha(world)
	_step(world, state, 18.0)
	world._flash_reduced = true
	state.events = [_shot(9, 19.0, false, true)]
	_step(world, state, 19.0)
	_step(world, state, 19.025)
	_check(_max_alpha(world) < full_alpha - 0.2, "Reduced flash dims the tracer")
	_check(_verts(world, 0.0).size() > 0 and _verts(world, 0.0).size() < 400, "Reduced flash keeps a small, bounded mesh")
	world._flash_reduced = false
	# --- Muzzle floor light goes into the over-fog mesh near the floor, only for the first 50 ms.
	_step(world, state, 20.0)
	state.events = [_shot(10, 21.0, false, false)]
	_step(world, state, 21.0)
	var floor_light := 0
	for vertex in world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if vertex.y > 0.2 and vertex.y < 0.3: floor_light += 1
	_check(floor_light > 0, "Observed muzzle flash lights the floor above the fog")
	_step(world, state, 21.08)
	floor_light = 0
	for vertex in world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if vertex.y > 0.2 and vertex.y < 0.3: floor_light += 1
	_check(floor_light == 0, "Muzzle floor light lasts about 50 ms")
	# --- Kill punctuation and camera kick.
	_step(world, state, 30.0)
	world._shake_remaining = 0.0
	state.events = [_shot(20, 31.0, true, false), _down(21, 31.0, "enemy")]
	_step(world, state, 31.0)
	var stamps := 0
	for effect: Dictionary in world._flashes:
		if effect.type == "kill_stamp": stamps += 1
	_check(stamps == 1, "An observed enemy kill creates one stamp")
	_check(world._shake_remaining == 0.0, "A shot-caused kill does not kick the camera before the tracer arrives")
	_step(world, state, 31.04)
	_check(world._shake_remaining == 0.0, "No kick at 40 ms (tracer still in flight)")
	_step(world, state, 31.06)
	_check(world._shake_remaining > 0.0 and world._shake_remaining <= world.KILL_KICK_DURATION + 0.0001, "A kill nudges the camera for ~70 ms once the tracer arrives")
	_check(is_equal_approx(world._shake_magnitude, world.SHAKE_MAGNITUDE / 3.0 * 4.0) and world.KILL_KICK_DURATION <= 0.11, "The kill kick is the 4x phase-3 value and stays within 110 ms")
	state.events = [_down(22, 31.0, "enemy"), _down(23, 31.0, "enemy"), _down(24, 31.0, "enemy"), _down(25, 31.0, "enemy")]
	var before: float = world._shake_remaining
	_step(world, state, 31.06)
	_check(world._shake_remaining <= before + 0.0001 and world._shake_remaining <= world.KILL_KICK_DURATION + 0.0001, "A burst of kills does not stack into a long shake")
	world._shake_remaining = 0.0
	state.events = [_down(26, 32.0, "unit")]
	_step(world, state, 32.0)
	_check(is_equal_approx(world._shake_remaining, world.DOWN_KICK_DURATION) and world._shake_magnitude > world.KILL_KICK_MAGNITUDE and world.DOWN_KICK_DURATION <= 0.16, "A friendly going down gets a stronger but still short kick")
	_check(is_equal_approx(world.DOWN_KICK_MAGNITUDE, world.SHAKE_MAGNITUDE * 0.7 * 4.0), "The casualty kick constants are exactly 4x the phase-2 values")
	var plain_marks := 0
	for effect: Dictionary in world._flashes:
		if effect.type == "neutralized_mark": plain_marks += 1
	_check(plain_marks == 1, "A friendly casualty keeps the plain mark, not the enemy kill stamp")
	world._shake_remaining = 0.0
	world._screen_shake_enabled = false
	state.events = [_down(27, 33.0, "enemy"), _shot(28, 33.0, false, false)]
	_step(world, state, 33.0)
	_check(world._shake_remaining == 0.0, "Disabled screen shake suppresses the kill kick")
	world._screen_shake_enabled = true
	world._motion_reduced = true
	state.events = [_down(29, 34.0, "unit")]
	_step(world, state, 34.0)
	_check(world._shake_remaining == 0.0, "Reduced motion suppresses the casualty kick")
	world._motion_reduced = false
	state.events = [{"seq": 30, "type": "DOOR_ACTION", "kind": "KICK_DOOR", "time": 35.0, "from": [6, 8]}]
	_step(world, state, 35.0)
	_check(is_equal_approx(world._shake_remaining, world.SHAKE_DURATION) and is_equal_approx(world._shake_magnitude, world.SHAKE_MAGNITUDE), "A breach still uses the full breach shake")
	# --- Target-side reactions wait for tracer arrival (50 ms; 35 ms with reduced flash).
	_check(is_equal_approx(world._hit_reaction_delay(), 0.05) and is_equal_approx(world.HIT_REACTION_DELAY, world.TRACER_TRAVEL), "Normal arrival delay is the 50 ms tracer flight")
	world._flash_reduced = true
	_check(is_equal_approx(world._hit_reaction_delay(), 0.035), "Reduced-flash arrival delay is 35 ms")
	world._flash_reduced = false
	for reduced in [false, true]:
		world._flash_reduced = reduced
		var delay: float = world._hit_reaction_delay()
		world._shake_remaining = 0.0
		_step(world, {"events": []}, 70.0)
		var timeline_hit := [_shot(60 + int(reduced) * 10, 71.0, true, false), _down(61 + int(reduced) * 10, 71.0, "enemy")]
		var arrival_state := {"events": timeline_hit, "presentation_events": timeline_hit}
		_step(world, arrival_state, 71.0)
		_step(world, arrival_state, 71.0 + delay * 0.5)
		var early_burst := 0
		var early_stamp := 0
		var early_ring := 0
		var colors := world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
		var positions := world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for index in range(positions.size()):
			var vertex := positions[index]
			if colors[index].r > 0.3 and colors[index].g < 0.06 and colors[index].b < 0.07 and colors[index].a > 0.05: early_burst += 1
			if vertex.y > 1.3: early_stamp += 1
			if vertex.y > 0.2 and vertex.y < 0.3 and Vector2(vertex.x, vertex.z).distance_to(Vector2(6.0, 8.0)) < 0.8: early_ring += 1
		_check(early_burst == 0 and early_stamp == 0 and early_ring == 0, "Nothing target-side is drawn before the tracer arrives (reduced=%s)" % reduced)
		_check(world._shake_remaining == 0.0, "No camera kick before the tracer arrives (reduced=%s)" % reduced)
		_step(world, arrival_state, 71.0 + delay + 0.03)
		early_burst = 0
		early_stamp = 0
		early_ring = 0
		colors = world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
		positions = world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for index in range(positions.size()):
			var vertex := positions[index]
			if colors[index].r > 0.3 and colors[index].g < 0.06 and colors[index].b < 0.07 and colors[index].a > 0.05: early_burst += 1
			if vertex.y > 1.3: early_stamp += 1
			if vertex.y > 0.2 and vertex.y < 0.3 and Vector2(vertex.x, vertex.z).distance_to(Vector2(6.0, 8.0)) < 0.8: early_ring += 1
		_check(early_burst > 0 and early_stamp > 0 and early_ring > 0, "Burst, stamp and confirm ring all appear after arrival (reduced=%s)" % reduced)
		_check(world._shake_remaining > 0.0, "The kick lands after arrival (reduced=%s)" % reduced)
		_step(world, {"events": []}, 75.0)
	world._flash_reduced = false
	# A friendly going down from an observed hit is delayed too; a casualty with no shot is not.
	world._shake_remaining = 0.0
	var friendly_timeline := [_shot(80, 80.0, true, true), _down(81, 80.0, "unit")]
	_step(world, {"events": friendly_timeline, "presentation_events": friendly_timeline}, 80.0)
	_check(world._shake_remaining == 0.0, "Friendly-down kick waits for the enemy tracer")
	_step(world, {"events": friendly_timeline, "presentation_events": friendly_timeline}, 80.06)
	_check(is_equal_approx(world._shake_remaining, world.DOWN_KICK_DURATION), "Friendly-down kick lands on arrival")
	world._shake_remaining = 0.0
	# --- Stamp pops past full size within 150 ms and then settles.
	var arm_samples: Array[float] = []
	for age in [0.0, 0.06, 0.15, 0.4]:
		world._event_mesh.clear_surfaces()
		world._event_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, world._vertex_material())
		world._draw_kill_stamp(Vector2(6, 8), age, world.STAMP_LIFE - age)
		world._event_mesh.surface_end()
		var extent := 0.0
		for vertex in world._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: extent = maxf(extent, absf(vertex.x - 6.0))
		arm_samples.append(extent)
	_check(arm_samples[1] > arm_samples[2] + 0.05 and arm_samples[2] <= arm_samples[3] + 0.01 and arm_samples[0] < arm_samples[2], "The stamp scales up past full size and settles by ~150 ms")
	# --- Door frames: static, palette aware, drawn once per build, never per-frame.
	_check(world._door_frame_mesh.get_surface_count() == 1, "Doors get one over-fog frame surface")
	var frame_before := hash(world._door_frame_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
	world._apply_palette("tritan")
	var frame_after := hash(world._door_frame_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
	_check(frame_before != frame_after, "Door frames follow the colour-blind palette")
	_check(world.ENEMY_COLOR.is_equal_approx(Color("e4457e")), "Tritan palette still maps the threat colour")
	world._apply_palette("deutan")
	_check(world.ENEMY_COLOR.is_equal_approx(Color("ffb000")), "Deutan palette still maps the threat colour")
	world._apply_palette("default")
	_check(world.ENEMY_COLOR.is_equal_approx(Color("e3483b")), "Default threat colour is the saturated red")
	# --- Replay seek: backward clears, forward rebuilds identically.
	var timeline: Array = [_shot(40, 50.0, true, false, "shotgun"), _down(41, 50.0, "enemy")]
	_step(world, {"events": [], "presentation_events": []}, 49.0) # a real seek lands before the events exist
	state = {"events": timeline, "presentation_events": timeline}
	_step(world, state, 49.0)
	_step(world, state, 50.0)
	var first_hash := _hash(world)
	_step(world, state, 50.03)
	var second_hash := _hash(world)
	_check(first_hash != 0 and second_hash != 0 and first_hash != second_hash, "Effects animate over time")
	state = {"events": [], "presentation_events": []}
	_step(world, state, 40.0)
	_check(world._flashes.is_empty() and _verts(world, 0.0).is_empty(), "Seeking backwards clears every effect")
	_check(world._shake_remaining == 0.0, "Seeking backwards clears the camera kick")
	state = {"events": timeline, "presentation_events": timeline}
	_step(world, state, 49.0)
	_step(world, state, 50.0)
	_check(_hash(world) == first_hash, "Replaying the same timeline redraws the identical first frame")
	_step(world, state, 50.03)
	_check(_hash(world) == second_hash, "Replaying the same timeline redraws the identical later frame")
	# --- Round 3 review fixes.
	# L1: an equal or weaker kick never restarts one in flight; a stronger one still wins.
	world._shake_remaining = 0.05
	world._shake_duration = world.KILL_KICK_DURATION
	world._shake_magnitude = world.KILL_KICK_MAGNITUDE
	world._request_kick(world.KILL_KICK_DURATION, world.KILL_KICK_MAGNITUDE, Vector2.UP)
	_check(is_equal_approx(world._shake_remaining, 0.05), "An equal-strength kick shortly after another does not restart it")
	world._request_kick(world.DOWN_KICK_DURATION, world.DOWN_KICK_MAGNITUDE, Vector2.UP)
	_check(is_equal_approx(world._shake_remaining, world.DOWN_KICK_DURATION), "A stronger kick still replaces a running weaker one")
	world._shake_remaining = 0.0
	# L2/M3: linkage, kick direction, held discs, and seek hygiene.
	_step(world, {"events": [], "presentation_events": []}, 90.0)
	var shot_down := {"id": "e9", "x": 6.0, "z": 8.0, "hp": 100.0}
	world._sync_actor(shot_down, "enemy", 0, "", 0.0, true)
	var disc_entry: Dictionary = world._entity_nodes["e9"]
	_check(is_equal_approx(float(disc_entry.visual.get("hit_delay", -1.0)), 0.05), "The actor visual receives the 50 ms hit delay from world_view")
	world._flash_reduced = true
	world._sync_actor(shot_down, "enemy", 0, "", 0.0, true)
	_check(is_equal_approx(float(disc_entry.visual.get("hit_delay", -1.0)), 0.035) and is_equal_approx(world._hit_reaction_delay(), 0.035), "Reduced flash hands the actor visual 35 ms")
	world._flash_reduced = false
	world._sync_actor(shot_down, "enemy", 0, "", 0.0, true)
	var killing := [_shot(90, 91.0, true, false), {"seq": 91, "type": "INCAPACITATED", "time": 91.0, "to": [6, 8], "entity_id": "e9", "kind": "enemy"}]
	var dead := {"id": "e9", "x": 6.0, "z": 8.0, "hp": 0.0}
	world._clock = 91.0
	world._sync_actor(dead, "enemy", 0, "", 0.0, true)
	_step(world, {"events": killing, "presentation_events": killing}, 91.0)
	_check(disc_entry.ring.visible and disc_entry.tick.visible and disc_entry.threat_halo.visible, "A shot-down enemy keeps its disc, tick and halo on the trigger frame")
	world._clock = 91.03
	world._sync_actor(dead, "enemy", 0, "", 0.0, true)
	_check(disc_entry.ring.visible and disc_entry.threat_halo.visible, "...and until the tracer arrives")
	world._clock = 91.06
	world._sync_actor(dead, "enemy", 0, "", 0.0, true)
	_check(not disc_entry.ring.visible and not disc_entry.tick.visible and not disc_entry.threat_halo.visible, "...then hides once it has")
	_check(world._shake_direction.is_equal_approx(Vector2(0.0, -1.0)), "A shot-caused kill kicks along the shot direction")
	world._shake_remaining = 0.0
	var orphan := [{"seq": 92, "type": "INCAPACITATED", "time": 92.0, "to": [6, 9], "entity_id": "e10", "kind": "enemy"}]
	world._sync_actor({"id": "e10", "x": 6.0, "z": 9.0, "hp": 100.0}, "enemy", 0, "", 0.0, true)
	world._clock = 92.0
	world._sync_actor({"id": "e10", "x": 6.0, "z": 9.0, "hp": 0.0}, "enemy", 0, "", 0.0, true)
	_step(world, {"events": orphan, "presentation_events": orphan}, 92.0)
	_check(not world._entity_nodes["e10"].ring.visible, "A cause-less casualty hides its disc immediately")
	_check(world._shake_remaining > 0.0 and is_equal_approx(world._shake_direction.length(), 1.0) and not world._shake_direction.is_equal_approx(Vector2(0.0, -1.0)), "A cause-less casualty kicks along a deterministic direction, not a stale shot direction or random jitter")
	var orphan_direction: Vector2 = world._shake_direction
	_step(world, {"events": [], "presentation_events": []}, 10.0)
	world._shake_remaining = 0.0
	_step(world, {"events": orphan, "presentation_events": orphan}, 92.0)
	_check(world._shake_direction.is_equal_approx(orphan_direction), "The same cause-less casualty always kicks the same way (replay-stable)")
	# Every casualty-sized kick is deterministic and clamped, even if it arrives with no direction at all.
	world._camera_base_size = 10.0
	world._view_size = Vector2(1440.0, 900.0)
	world._shake_duration = world.DOWN_KICK_DURATION
	world._shake_magnitude = world.DOWN_KICK_MAGNITUDE
	world._shake_direction = Vector2.ZERO
	var clamp_m: float = world.SAFE_AREA_MARGIN_PX * 10.0 / 900.0
	var first_run: Array[Vector3] = []
	var second_run: Array[Vector3] = []
	for sample in range(40):
		world._shake_remaining = world.DOWN_KICK_DURATION * float(sample + 1) / 40.0
		first_run.append(world._current_kick_offset())
	for sample in range(40):
		world._shake_remaining = world.DOWN_KICK_DURATION * float(sample + 1) / 40.0
		second_run.append(world._current_kick_offset())
	var worst := 0.0
	for offset in first_run: worst = maxf(worst, offset.length())
	_check(first_run == second_run and worst <= clamp_m + 0.0001, "A ZERO-direction down kick is clamped to the safe-area margin and identical across runs")
	world._shake_remaining = 0.0
	world._shake_duration = world.SHAKE_DURATION
	world._shake_magnitude = world.SHAKE_MAGNITUDE
	_step(world, {"events": [], "presentation_events": []}, 10.0)
	_check(world._casualty_hold.is_empty() and world._last_shot_direction == Vector2.ZERO and float(world._last_hit_shot.time) < 0.0, "Seeking back forgets shot/casualty links")
	# L3: miss tracers stop at walls instead of passing through them.
	world._obstacles.clear()
	world._obstacles.append(Rect2(4.0, 6.5, 4.0, 0.3))
	_step(world, {"events": []}, 100.0)
	var wall_state := {"events": [_shot(100, 101.0, false, false)]}
	_step(world, wall_state, 101.0)
	var walled: float = (world._flashes[0].plan[0] as Vector2).y
	world._obstacles.clear()
	_step(world, {"events": []}, 102.0)
	var open_state := {"events": [_shot(101, 103.0, false, false)]}
	_step(world, open_state, 103.0)
	var open: float = (world._flashes[world._flashes.size() - 1].plan[0] as Vector2).y
	_check(walled < 4.2 and open > 4.3 and walled >= 2.8, "A miss tracer is clamped by a wall (%.2f) but runs on in the open (%.2f)" % [walled, open])
	_step(world, {"events": []}, 110.0)
	# M1: a clock that jumps ~133 ms per frame (4x replay at 30 fps) still shows a sensible result.
	var jump_events := [_shot(110, 120.0, true, false), _down(111, 120.0, "enemy")]
	var jump_state := {"events": jump_events, "presentation_events": jump_events}
	world._shake_remaining = 0.0
	_step(world, {"events": []}, 119.9)
	_step(world, jump_state, 120.12)
	var negative := false
	var stamp_seen := false
	var late_flash_visible := false
	for effect: Dictionary in world._flashes:
		if float(effect.lifetime) - float(effect.remaining) < 0.0: negative = true
		if effect.type == "kill_stamp": stamp_seen = true
		if effect.type == "shot" and effect.get("flash_sprite") != null and effect.flash_sprite.visible: late_flash_visible = true
	_check(not negative and stamp_seen and world._flashes.size() == 2, "A 120 ms clock jump creates back-dated effects with no negative ages")
	_check(_verts(world, 1.3).size() > 0, "A late first frame still draws the kill stamp (arrival measured from the event time)")
	_check(world._shake_remaining > 0.0, "A late first frame still lands the kick when arrival was recent")
	_check(late_flash_visible, "A late first frame still shows one muzzle flash")
	_step(world, jump_state, 120.12 + 0.133)
	_step(world, jump_state, 120.12 + 0.266)
	_step(world, jump_state, 120.12 + 0.4)
	_check(world._flashes.size() == 1, "The shot expires on its own clock while the stamp keeps fading")
	_step(world, jump_state, 120.12 + 0.9)
	_check(world._flashes.is_empty(), "Everything expires after the late start")
	# H2: the kill stamp sits above raised floors.
	var Catalog = preload("res://scripts/mission_catalog.gd")
	var raised: Node = preload("res://scripts/world_view.gd").new()
	root.add_child(raised)
	var h04: Dictionary = Catalog.load("H04")
	raised.build(h04)
	var room: Dictionary = {}
	for candidate: Dictionary in h04.rooms:
		if float(candidate.get("base_height", 0.0)) > 1.0:
			room = candidate
			break
	_check(not room.is_empty() and not raised._elevated_rooms.is_empty(), "H04 has a raised room to test against")
	if not room.is_empty():
		var base := float(room.base_height)
		var spot := [float(room.x), float(room.z)]
		var raised_events := [{"seq": 1, "type": "SHOT", "time": 5.0, "from": [spot[0], spot[1] + 3.0], "to": spot, "attacker_id": "alpha", "hit": true, "hostile": false, "weapon": "standard", "protection": "unprotected"}, {"seq": 2, "type": "INCAPACITATED", "time": 5.0, "to": spot, "entity_id": "r1", "kind": "enemy"}]
		var raised_state := {"events": raised_events, "presentation_events": raised_events}
		raised._clock = 4.9
		raised._update_effects({"events": []}, 0.0, false)
		raised._clock = 5.0
		raised._update_effects(raised_state, 0.0, false)
		raised._clock = 5.08
		raised._update_effects(raised_state, 0.0, false)
		var stamp_low := 0
		var stamp_high := 0
		for vertex: Vector3 in raised._event_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if vertex.y > base + 1.3: stamp_high += 1
			elif vertex.y > 1.35 and vertex.y < 1.6: stamp_low += 1 # where the unoffset stamp used to be
		_check(stamp_high > 0, "Kill stamp vertices sit above the raised floor (base %.2f)" % base)
		_check(stamp_low == 0, "No stamp geometry is left under the raised floor")
	raised.queue_free()
	# --- Phase 3: kick clamp on screen, fog refresh on sighting, no last-seen ghost for the neutralized.
	world._camera_base_size = 10.0
	world._view_size = Vector2(1440.0, 900.0)
	world._shake_duration = world.DOWN_KICK_DURATION
	world._shake_magnitude = world.DOWN_KICK_MAGNITUDE
	world._shake_direction = Vector2(0.0, -1.0)
	world._shake_remaining = world.DOWN_KICK_DURATION
	var limit_m: float = world.SAFE_AREA_MARGIN_PX * 10.0 / 900.0
	_check(world._current_kick_offset().length() <= limit_m + 0.0001, "A casualty kick never moves the frame past the safe-area margin")
	world._shake_magnitude = 50.0
	_check(is_equal_approx(world._current_kick_offset().length(), limit_m), "An absurdly large kick is clamped to exactly the safe-area margin")
	world._shake_direction = Vector2.ZERO
	world._shake_magnitude = world.SHAKE_MAGNITUDE
	var breach_max := 0.0
	for sample in range(40): breach_max = maxf(breach_max, world._current_kick_offset().length())
	_check(breach_max <= world.SHAKE_MAGNITUDE * 1.4143 + 0.0001, "Breach jitter is unchanged (random, up to SHAKE_MAGNITUDE per axis)")
	world._shake_remaining = 0.0
	world._shake_duration = world.SHAKE_DURATION
	world._shake_magnitude = world.SHAKE_MAGNITUDE
	var live := _fresh_world()
	var unit := {"id": "alpha", "x": 4.0, "z": 12.0, "hp": 100.0, "facing": 0.0, "commands": []}
	var hostile := {"id": "e1", "x": 9.0, "z": 12.0, "hp": 100.0, "facing": 3.14, "status": "READY", "visible": false, "commands": [], "weapon": "standard", "armor": "none", "helmet": "none", "sidearm": "none"}
	var frame := {"units": [unit], "enemies": [hostile], "civilians": [], "doors": [], "events": [], "tick": 1}
	frame["time"] = 1.0
	frame["presentation_time"] = 1.0
	live.display(frame, "alpha", false, 0.0)
	var settled_fog: float = live._fog_time
	frame["presentation_time"] = 1.005
	live.display(frame, "alpha", false, 0.005)
	_check(is_equal_approx(live._fog_time, settled_fog), "Steady state keeps the 30 Hz fog throttle")
	hostile["visible"] = true
	frame["presentation_time"] = 1.010
	live.display(frame, "alpha", false, 0.005)
	_check(is_equal_approx(live._fog_time, 1.010), "A newly visible enemy refreshes the fog in the same frame, not up to 33 ms later")
	var visible_gear: Array = (live._entity_nodes["e1"].visual.gear_signature as Array).duplicate(true)
	_check(live._entity_nodes["e1"].visual.equipped_armor == "none", "A visible enemy wears no armour carrier")
	hostile["visible"] = false
	frame["presentation_time"] = 1.012
	live.display(frame, "alpha", false, 0.002)
	_check(is_equal_approx(live._fog_time, 1.012), "A lost enemy refreshes the fog in the same frame too")
	# A hidden but alive enemy keeps its last-seen ghost; a neutralized one never does and its body stays, fogged.
	hostile["last_seen"] = [9.0, 12.0]
	hostile["last_seen_time"] = 0.5
	frame["presentation_time"] = 1.3
	live.display(frame, "alpha", false, 0.3)
	_check(live._ghost_nodes.has("e1") and live._ghost_nodes["e1"].node.visible, "A living, unseen enemy still shows the last-seen ghost")
	_check(not live._entity_nodes.has("e1") or not live._entity_nodes["e1"].node.visible, "A living, unseen enemy shows no body")
	hostile["hp"] = 0.0
	hostile["status"] = "INCAPACITATED"
	frame["presentation_time"] = 1.4
	live.display(frame, "alpha", false, 0.1)
	_check(not live._ghost_nodes["e1"].node.visible, "A neutralized enemy never shows a last-seen ghost")
	_check(live._entity_nodes.has("e1") and live._entity_nodes["e1"].node.visible and live._remembered_bodies.has("e1"), "...its last known body stays on the map")
	_check(int(live._fog_material.get_shader_parameter("actor_count")) == 1, "...and stays fogged: the remembered body is not part of the actor bubble")
	_check(live._entity_nodes["e1"].visual.equipped_armor == "none" and live._entity_nodes["e1"].visual.equipped_helmet == "none", "A remembered body keeps the enemy's real gear, not operator defaults")
	_check((live._entity_nodes["e1"].visual.gear_signature as Array) == visible_gear, "...so no prop rebuild happens when a visible enemy becomes a remembered body")
	_check(not live._entity_nodes["e1"].label.visible and not live._entity_nodes["e1"].status.visible, "A remembered body hides its bright disc label and status text")
	hostile["hp"] = 100.0
	hostile["status"] = "ARRESTED"
	frame["presentation_time"] = 1.5
	live.display(frame, "alpha", false, 0.1)
	_check(not live._ghost_nodes["e1"].node.visible and live._remembered_bodies.has("e1"), "An arrested enemy is a remembered body, not a ghost")
	# Killed out of sight: the record still says alive. No ghost; the body goes where the public kill event put it.
	hostile["status"] = "READY"
	live._room_neutralized_ids["e1"] = true
	live._neutralized_at.erase("e1")
	frame["presentation_time"] = 1.6
	live.display(frame, "alpha", false, 0.1)
	_check(not live._ghost_nodes["e1"].node.visible and not live._remembered_bodies.has("e1") and not live._entity_nodes["e1"].node.visible, "A known-neutralized enemy with no observed position draws neither ghost nor body")
	live._neutralized_at["e1"] = Vector2(10.0, 12.5)
	frame["presentation_time"] = 1.7
	live.display(frame, "alpha", false, 0.1)
	_check(live._remembered_bodies.has("e1") and not live._ghost_nodes["e1"].node.visible, "A kill observed out of sight leaves a body")
	_check(absf(live._entity_nodes["e1"].node.position.x - 10.0) < 0.01 and absf(live._entity_nodes["e1"].node.position.z - 12.5) < 0.01, "...at the public kill position, not at the stale last-seen spot")
	_check(not live._entity_nodes["e1"].ring.visible, "...downed, not standing")
	# The first frame of such a kill (event not yet processed by the effects pass) already has no ghost.
	live._neutralized_at.clear()
	live._room_neutralized_ids.clear()
	var late_kill := [{"seq": 500, "type": "INCAPACITATED", "time": 1.8, "to": [11.0, 12.0], "entity_id": "e1", "kind": "enemy"}]
	frame["events"] = late_kill
	frame["presentation_events"] = late_kill
	frame["presentation_time"] = 1.8
	live.display(frame, "alpha", false, 0.1)
	_check(not live._ghost_nodes["e1"].node.visible and live._remembered_bodies.has("e1") and absf(live._entity_nodes["e1"].node.position.x - 11.0) < 0.01, "The first frame after an out-of-sight kill has no ghost and the body at the event position")
	# A body never seen alive falls back to a neutral enemy loadout, not operator gear.
	var stranger := {"id": "e2", "x": 7.0, "z": 12.0, "hp": 0.0, "facing": 0.0, "status": "INCAPACITATED", "visible": false, "commands": [], "last_seen": [7.0, 12.0], "last_seen_time": 0.4}
	frame["enemies"] = [hostile, stranger]
	frame["events"] = []
	frame["presentation_events"] = []
	frame["presentation_time"] = 1.9
	live.display(frame, "alpha", false, 0.1)
	_check(live._entity_nodes["e2"].visual.equipped_armor == "none" and live._entity_nodes["e2"].visual.equipped_helmet == "none", "A never-seen remembered body falls back to an unarmoured loadout")
	live.queue_free()
	# --- Bounded growth under sustained fire (sprites are recycled).
	_step(world, {"events": []}, 60.0)
	await process_frame
	var baseline: int = world.get_child_count()
	var clock := 100.0
	var seq := 1000
	var peak := 0
	var peak_effects := 0
	for burst in range(120):
		var events: Array = []
		for shooter in range(3):
			seq += 1
			events.append(_shot(seq, clock, burst % 2 == 0, burst % 3 == 0, "shotgun" if burst % 4 == 0 else "standard", "blocked" if burst % 5 == 0 else "unprotected"))
		seq += 1
		events.append(_down(seq, clock, "enemy" if burst % 2 == 0 else "unit"))
		var burst_state := {"events": events, "presentation_events": events}
		for tick in range(5):
			_step(world, burst_state, clock + float(tick) * 0.016)
		clock += 0.08
		peak = maxi(peak, world.get_child_count())
		peak_effects = maxi(peak_effects, world._flashes.size())
	await process_frame
	_step(world, {"events": []}, clock + 2.0)
	_step(world, {"events": []}, clock + 3.0)
	await process_frame
	_check(world._flashes.is_empty(), "Every effect expires after the firefight")
	_check(world.get_child_count() <= baseline + world.EFFECT_SPRITE_POOL, "Node count settles back near baseline (%d vs %d)" % [world.get_child_count(), baseline])
	_check(peak <= baseline + 3 * peak_effects + world.EFFECT_SPRITE_POOL, "Node count is bounded by live effects plus the pool, not by shots fired (peak %d, baseline %d, concurrent effects %d)" % [peak, baseline, peak_effects])
	world.queue_free()
	await process_frame
	print("BREACH_HIT_FEEDBACK_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
