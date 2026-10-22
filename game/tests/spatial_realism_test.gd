extends SceneTree
const Navigation = preload("res://scripts/navigation.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const Field = preload("res://scripts/visibility_field.gd")
const Simulation = preload("res://scripts/simulation.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func actor(x: float, z: float, stance: String = "standing") -> Dictionary:
	return {"id": "actor", "kind": "unit", "x": x, "z": z, "hp": 100.0, "stunned": 0.0, "facing": 0.0, "body_facing": 0.0, "stance": stance, "fov": 110.0, "vision_range": 10.0}

func data(obstacles: Array = [], props: Array = []) -> Dictionary:
	return {"bounds": [12, 10], "walls": obstacles, "props": props, "doors": [], "units": [], "enemies": [], "civilians": []}

func _initialize() -> void:
	var nav := Navigation.new()
	var observer := actor(1, 5)
	var subject := actor(7, 5)
	check(Spatial.eye_height(observer) > Spatial.weapon_height(observer), "Eyes and weapon heights are independent simulation dimensions")
	check(Spatial.eye_height(actor(1, 5, "crouched")) < Spatial.eye_height(observer), "Crouching lowers eye position")
	check(is_equal_approx(Spatial.prop_height("cabinet"), 1.30), "Furniture dimensions match imported rendering defaults")
	var cover := {"type": "table", "cover": "low", "x": 6.7, "z": 5, "w": 0.3, "d": 3, "height": 0.90}
	nav.build(data([], [cover]), [])
	var standing_exposure := nav.exposed_fraction(observer, subject)
	var crouched := subject.duplicate(true)
	crouched.stance = "crouched"
	var crouched_exposure := nav.exposed_fraction(observer, crouched)
	check(standing_exposure > 0.60 and standing_exposure < 1.0, "Low obstacle partially conceals standing body")
	check(crouched_exposure > 0.0 and crouched_exposure < standing_exposure, "Crouching behind low cover reduces exposed body without inventing total concealment")
	cover.height = 1.13
	nav.build(data([], [cover]), [])
	check(nav.exposed_fraction(observer, crouched) == 0.0, "Cover above crouched body conceals all samples")
	check(nav.exposed_fraction(observer, subject) > 0.0, "Same cover leaves standing upper body exposed")
	check(not nav.shot_clear_height(Vector2(1, 5), Vector2(7, 5), 0.9, 0.8), "Weapon ray cannot pass through low furniture below its top")
	check(nav.shot_clear_height(Vector2(1, 5), Vector2(7, 5), 1.35, 1.3), "Weapon ray above furniture stays clear")
	check(nav.shot_exposure(Vector2(1, 5), 1.35, crouched) == 0.0, "Hidden crouched body has no unobstructed physical aim sample")
	var wall := {"x": 4, "z": 5, "w": 0.25, "d": 4, "height": 2.6, "material": "concrete"}
	nav.build(data([wall]), [])
	check(nav.exposed_fraction(observer, subject) == 0.0, "Full wall conceals every body sample")
	check(not nav.sight_clear_height(Vector2(1, 5), Vector2(7, 5), 1.62, 1.62), "Logical wall height is independent of visual cutaway")
	check(not nav.shot_clear_height(Vector2(1, 5), Vector2(7, 5), 1.35, 1.2, 1.0), "Concrete stops insufficient penetration budget")
	wall.material = "glass"
	nav.build(data([wall]), [])
	check(nav.exposed_fraction(observer, subject) == 1.0, "Transparent glass permits observation")
	check(not nav.physical_clear_height(Vector2(1, 5), Vector2(7, 5), 1.62, 1.62), "Transparent glass still stops physical sensor or weapon placement")
	check(not nav.shot_clear_height(Vector2(1, 5), Vector2(7, 5), 1.35, 1.2), "Visible glass remains a physical obstacle")
	check(nav.shot_clear_height(Vector2(1, 5), Vector2(7, 5), 1.35, 1.2, 0.3), "Configured material resistance controls penetration")
	var shot_profile := nav.shot_profile_height(Vector2(1, 5), Vector2(7, 5), 1.35, 1.2, 0.3)
	check(shot_profile.penetrations == 1 and shot_profile.transmission > 0.0 and shot_profile.transmission < 1.0, "Penetration reduces transmission instead of removing wall cost")
	wall.opaque = true
	nav.build(data([wall]), [])
	check(nav.exposed_fraction(observer, subject) == 0.0, "Legacy opaque explicitly overrides transparent material default")
	wall.opacity = 0.0
	nav.build(data([wall]), [])
	check(nav.exposed_fraction(observer, subject) == 1.0, "Explicit opacity takes precedence over legacy opaque")
	wall.material = "plaster"
	wall.opacity = 1.0
	nav.build(data([wall]), [])
	check(nav.exposed_fraction(observer, subject) == 0.0 and nav.shot_clear_height(Vector2(1, 5), Vector2(7, 5), 1.35, 1.2, 0.6), "Penetrable opaque material never grants visual information")
	wall = {"x": 4, "z": 5.25, "w": 0.25, "d": 0.6, "height": 2.6}
	nav.build(data([wall]), [])
	var side_exposure := nav.exposed_fraction(observer, subject)
	check(side_exposure > 0.0 and side_exposure < 0.5, "Shoulder partially exposed around wall edge can be observed")
	var embedded := subject.duplicate(true)
	embedded.x = 4.0
	embedded.z = 5.15
	check(nav.exposed_fraction(observer, embedded) == 0.0, "Samples never become sensors through a wall crossing the subject body")
	var rotated := {"type": "cabinet", "cover": "full", "x": 5, "z": 5, "w": 3.0, "d": 0.4, "rotation": PI * 0.25, "height": 2.0}
	nav.build(data([], [rotated]), [])
	check(not nav.walkable(Vector2(5.7, 4.3)), "Arbitrary rotated footprint blocks the actual long axis")
	check(nav.walkable(Vector2(5.7, 5.7)), "Rotated footprint does not occupy empty AABB corners")
	check(not nav.sight_clear_height(Vector2(3, 6), Vector2(7, 4), 1.62, 1.62), "Rotated prop uses same footprint for sight")
	var vehicle := {"type": "vehicle", "cover": "full", "x": 6, "z": 5, "w": 4, "d": 2, "height": 1.5, "material": "metal"}
	var vehicle_nav := Navigation.new()
	vehicle_nav.build(data([], [vehicle]), [])
	check(vehicle_nav.sight_clear_height(Vector2(2, 5.8), Vector2(10, 5.8), 1.35, 1.35), "Standing eye/weapon can clear rendered low hood away from cabin")
	check(not vehicle_nav.sight_clear_height(Vector2(2, 4.86), Vector2(10, 4.86), 1.35, 1.35), "Vehicle cabin blocks ray below roof")
	check(not vehicle_nav.sight_clear_height(Vector2(2, 5.8), Vector2(10, 5.8), 0.9, 0.9), "Low ray strikes actual hood height")
	check(vehicle_nav.sight_clear_height(Vector2(2, 4.86), Vector2(10, 4.86), 1.6, 1.6), "Ray above authored maximum roof height stays clear")
	var vehicle_shot := vehicle_nav.shot_profile_height(Vector2(2, 4.86), Vector2(10, 4.86), 0.93, 0.93, 6.5)
	check(vehicle_shot.clear and vehicle_shot.penetrations == 1, "Overlapping vehicle components consume one physical material resistance")
	var field := Field.new()
	var room_data := data([], [rotated])
	field.build(room_data)
	field.update([observer], [])
	for x in range(2, 43, 3):
		for z in range(2, 37, 3):
			var point := Vector2(x * 0.25 + 0.019, z * 0.25 + 0.011)
			var offset := point - Vector2(1, 5)
			var cone := offset.length() <= 10.0 and absf(offset.angle()) <= deg_to_rad(55.0)
			check(field.contains(point) == (cone and nav.sight_clear_height(Vector2(1, 5), point, 1.62, 1.62)), "Polygon and rotated height-aware sight agree at %s" % point)
	room_data = data([], [{"type": "cabinet", "cover": "full", "x": 4, "z": 5, "w": 0.4, "d": 4, "height": 1.2}])
	field.build(room_data)
	field.update([observer], [])
	check(field.contains(Vector2(7, 5)), "Standing sight polygon sees above cabinet")
	var low_observer := actor(1, 5, "crouched")
	field.update([low_observer], [])
	check(not field.contains(Vector2(7, 5)), "Stance invalidates cached polygon and lowers sight below cabinet")
	var dark_data := data()
	dark_data.environment = {"lighting": 0.25}
	dark_data.rooms = [{"x": 2, "z": 5, "w": 3, "d": 4, "lighting": 0.5}]
	nav.build(dark_data, [])
	var range_before: float = observer.vision_range
	check(nav.effective_vision_range(observer) < 6.2 and observer.vision_range == range_before, "Lighting combines room and environment without mutating authored range")
	nav._lighting = 0.0
	check(is_equal_approx(nav.effective_vision_range(observer), range_before * 0.55), "Cached room geometry reads the current environment light each query")
	nav._lighting = 0.25
	var overlap_data := data()
	overlap_data.environment = {"lighting": 0.4}
	overlap_data.rooms = [
		{"x": 2, "z": 5, "w": 3, "d": 4, "lighting": 1.0},
		{"x": 2, "z": 5, "w": 3, "d": 4, "lighting": 0.2},
	]
	var overlap_nav := Navigation.new()
	overlap_nav.build(overlap_data, [])
	check(is_equal_approx(overlap_nav.effective_vision_range(observer), range_before * (0.55 + 0.45 * 0.4)), "Prebuilt lighting regions preserve first authored overlapping room including neutral light")
	field.build(dark_data)
	field.update([observer], [])
	check(not field.contains(Vector2(8, 5)) and field.contains(Vector2(5, 5)), "Darkness affects displayed visibility range")
	var door := {"id": "d1", "x": 5, "z": 5, "w": 1.6, "d": 0.25, "axis": "x", "state": "CLOSED", "progress": 0.0, "height": 2.1, "hinge_side": -1.0, "swing_sign": -1.0}
	nav.build(data(), [door])
	check(not nav.sight_clear_height(Vector2(5, 3), Vector2(5, 7), 1.62, 1.62), "Closed door blocks eye-height ray")
	var exact_revision := nav._exact_door_revision
	nav._ray_key(Vector2(5, 3), Vector2(5, 7), 1.62, 1.62)
	check(nav._exact_door_revision == exact_revision, "Unchanged exact door pose reuses integer cache generation")
	door.progress = 0.0001
	nav._ray_key(Vector2(5, 3), Vector2(5, 7), 1.62, 1.62)
	check(nav._exact_door_revision > exact_revision, "Sub-revision in-place door progress still changes integer cache generation")
	door.state = "AJAR"
	door.progress = 0.52
	var aperture_data := data([
		{"x": 2.1, "z": 5, "w": 4.2, "d": 0.25},
		{"x": 8.9, "z": 5, "w": 6.2, "d": 0.25},
	])
	var door_observer := actor(5, 3)
	door_observer.facing = PI * 0.5
	field.build(aperture_data)
	for progress: float in [0.0, 0.35, 0.52, 0.8, 1.0]:
		door.progress = progress
		door.state = "OPEN" if progress >= 1.0 else "AJAR"
		nav.build(aperture_data, [door])
		field.update([door_observer], [door])
		var aperture_visible := 0
		for sample_index in range(15):
			var point := Vector2(4.25 + sample_index * 0.105, 6.7)
			var clear := nav.sight_clear_height(Vector2(5, 3), point, 1.62, 1.62)
			if clear: aperture_visible += 1
			check(field.contains(point) == clear, "Partial door aperture matches sight polygon at progress %.2f" % progress)
		if progress == 0.0: check(aperture_visible == 0, "Closed framed doorway never reveals room")
		if progress == 1.0: check(aperture_visible > 0, "Open framed doorway reveals real aperture")
	door.progress = 0.52
	door.state = "AJAR"
	nav.build(data(), [door])
	var first_leaf := nav._leaf_obstacle(door).duplicate(true)
	door.hinge_side = 1.0
	var second_leaf := nav._leaf_obstacle(door)
	check(first_leaf != second_leaf, "Changing fixed hinge invalidates cached door pose")
	door.material = "glass"
	door.opacity = 0.0
	door.resistance = 0.25
	var leaf: Dictionary = nav._leaf_obstacle(door)
	var cross_start := Vector2(float(leaf.x), float(leaf.z)) + Vector2.from_angle(float(leaf.leaf_angle) + PI * 0.5) * 0.5
	var cross_end := Vector2(float(leaf.x), float(leaf.z)) - Vector2.from_angle(float(leaf.leaf_angle) + PI * 0.5) * 0.5
	check(nav.shot_clear_height(cross_start, cross_end, 1.35, 1.35, 0.3), "Glass door resistance permits adequate penetration budget")
	door.resistance = 10.0
	check(not nav.shot_clear_height(cross_start, cross_end, 1.35, 1.35, 0.3), "Live door resistance mutation invalidates physical ray cache")
	door.destroyed = true
	check(nav.sight_clear_height(Vector2(5, 3), Vector2(5, 7), 1.62, 1.62) and nav._door_blockers([], true).is_empty(), "Destroyed door removes physical and observation blockers")
	door.destroyed = false
	door.state = "CLOSED"
	door.progress = 0.0
	door.opacity = 1.0
	nav.begin_geometry_scope()
	check(not nav.sight_clear_height(Vector2(5, 3), Vector2(5, 7), 1.62, 1.62), "Scoped geometry starts from exact current closed pose")
	door.destroyed = true
	nav.invalidate_sensory_pose()
	check(nav.sight_clear_height(Vector2(5, 3), Vector2(5, 7), 1.62, 1.62), "Exceptional mid-step destruction invalidates scoped geometry")
	nav.end_geometry_scope()
	door.destroyed = false
	check(not nav.sight_clear_height(Vector2(5, 3), Vector2(5, 7), 1.62, 1.62), "Outside scope direct in-place mutations remain visible without grid rebuild")
	var sim := Simulation.new()
	room_data = data([{"x": 5, "z": 5, "w": 8, "d": 0.25, "height": 2.6}])
	sim.load_mission(room_data)
	observer = actor(5, 3)
	observer.facing = PI * 0.5
	observer["_peek_origin"] = [5, 7]
	observer["_peek_facing"] = PI * 0.5
	observer["_peek_remaining"] = 1.0
	subject = actor(5, 8)
	check(not sim.can_see(observer, subject), "Invalid peek across wall cannot reveal subject")
	observer._peek_origin = [5.1, 3]
	check(not sim.can_see(observer, subject), "Reachable lean still respects wall to subject")
	print("BREACH_SPATIAL_REALISM_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
