extends SceneTree
## P3 casualty geometry is pure. Actual MAN_DOWN/primitive execution is
## covered separately by room_control_test; these checks isolate its draft.
const Drill = preload("res://scripts/room_drill.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const STEP := 1.0 / 30.0
const IDS: Array[String] = ["alpha", "bravo", "charlie", "delta"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func fixture(width: float = 5.0, depth: float = 5.0, axis: String = "x") -> Dictionary:
	var portal := 8.0 + depth * 0.5
	var jamb := (width - 1.6) * 0.5
	var data := {"schema_version":4, "id":"ROOM_REFORMATION", "seed":0, "bounds":[20.0,20.0],
		"rooms":[{"id":"inside", "x":8.0, "z":8.0, "w":width, "d":depth, "indoor":true}, {"id":"staging", "x":8.0, "z":portal + 2.5, "w":5.0, "d":5.0, "indoor":true}],
		"walls":[{"id":"north", "x":8.0, "z":8.0 - depth * 0.5, "w":width, "d":0.2},
			{"id":"west", "x":8.0 - width * 0.5, "z":8.0, "w":0.2, "d":depth}, {"id":"east", "x":8.0 + width * 0.5, "z":8.0, "w":0.2, "d":depth},
			{"id":"jamb_west", "x":8.0 - (1.6 + jamb) * 0.5, "z":portal, "w":jamb, "d":0.2}, {"id":"jamb_east", "x":8.0 + (1.6 + jamb) * 0.5, "z":portal, "w":jamb, "d":0.2},
			{"id":"stage_west", "x":5.5, "z":portal + 2.5, "w":0.2, "d":5.0}, {"id":"stage_east", "x":10.5, "z":portal + 2.5, "w":0.2, "d":5.0},
			{"id":"south", "x":8.0, "z":portal + 5.0, "w":5.0, "d":0.2}],
		"doors":[{"id":"entry", "x":8.0, "z":portal, "w":1.6, "d":0.2, "axis":"x", "hinge_side":-1.0, "swing_sign":1.0, "state":"CLOSED", "progress":0.0}],
		"props":[], "units":[], "enemies":[], "civilians":[]}
	if axis == "z":
		for group: String in ["rooms", "walls", "doors"]:
			for object: Dictionary in data[group]:
				var x := float(object.x)
				var w := float(object.w)
				object.x = object.z
				object.z = x
				object.w = object.d
				object.d = w
		data.doors[0].axis = "z"
	return data

func layout(data: Dictionary, method: String = "OPEN_DOOR") -> Dictionary:
	var origins: Dictionary = {}
	var door: Dictionary = data.doors[0]
	for index: int in range(4):
		var offset := 1.4 + float(index) * 0.7
		origins[IDS[index]] = [float(door.x), float(door.z) + offset] if door.axis == "x" else [float(door.x) + offset, float(door.z)]
	return Drill.calculate(data, "entry", IDS, origins, {"method":method})

func positions(prior: Dictionary, ids: Array, outside: bool = false) -> Dictionary:
	var result: Dictionary = {}
	for slot: Dictionary in prior.get("slots", []):
		if ids.has(slot.unit_id): result[slot.unit_id] = slot.stack.duplicate() if outside else slot.domination.duplicate()
	return result

func planned_nav(data: Dictionary, prior: Dictionary) -> RefCounted:
	var doors: Array = data.doors.duplicate(true)
	for door: Dictionary in doors:
		if door.id == prior.door_id:
			door.state = "OPEN"
			door.progress = 1.0
			if prior.method in ["BREACH_DOOR", "SHOTGUN_BREACH"]: door.destroyed = true
	var nav = Navigation.new()
	nav.build(data, doors)
	return nav

func sector_contains(sector: Dictionary, angle: float) -> bool:
	var difference := float(sector.end) - float(sector.start)
	if absf(difference) >= TAU - 0.0001: return true
	return fposmod(angle - float(sector.start), TAU) <= fposmod(difference, TAU) + 0.0001

func json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING: return true
		TYPE_FLOAT: return is_finite(float(value))
		TYPE_ARRAY:
			for item: Variant in value:
				if not json_safe(item): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not json_safe(value[key]): return false
			return true
	return false

func assert_reformation(data: Dictionary, prior: Dictionary, ids: Array, starts: Dictionary, result: Dictionary, label: String) -> void:
	check(bool(result.get("ok", false)), label + " complete remap: " + str(result.get("reason_code", "")))
	if not bool(result.get("ok", false)): return
	check(json_safe(result), label + " finite JSON output")
	check(result.room_id == prior.room_id and result.entry_side == prior.entry_side, label + " retains room and entry side for inside actors")
	check(not result.has("commands") and not result.has("breaches") and not result.has("ammo"), label + " returns geometry without reissuing door/resources")
	check(result.targets.size() == 3 and result.entry_count == (2 if prior.short_room else 3), label + " exact surviving roles")
	var nav := planned_nav(data, prior)
	var assigned: Array[Vector2] = []
	for index: int in range(result.targets.size()):
		var target: Dictionary = result.targets[index]
		check(target.unit_id == ids[index] and target.order == index + 1, label + " compresses surviving tactical order")
		var goal := point(target.target)
		check(nav.walkable(goal), label + " legal goal " + str(index))
		for other: Vector2 in assigned: check(goal.distance_to(other) >= 0.7 - 0.0001, label + " target body spacing")
		assigned.append(goal)
		check(is_equal_approx(float(target.floor_height), Spatial.floor_base_at(data.rooms, goal)), label + " physical floor height")
		var previous := point(starts[target.unit_id])
		check(not target.route.is_empty(), label + " reachable route")
		for raw: Array in target.route:
			var next := point(raw)
			check(nav.walkable(next) and nav.segment_clear(previous, next, Navigation.RADIUS), label + " full swept route segment")
			previous = next
		check(previous.distance_to(goal) < 0.0001, label + " route ends at exact goal")
		check(point(target.sector.origin).distance_to(goal) < 0.0001, label + " sector uses remapped origin")
		check(sector_contains(target.sector, (point(target.face_target) - goal).angle()), label + " FACE heading uses simulation angle convention")
		if index < 2:
			check(goal.distance_to(point(prior.slots[0].domination)) < 0.0001 or goal.distance_to(point(prior.slots[1].domination)) < 0.0001, label + " retains one of the original near control points")
	if prior.short_room:
		check(not result.targets[2].entry and result.targets[2].role == "guard", label + " SHORT keeps third outside")
	else:
		check(result.targets[2].entry and result.targets[2].role == "merged_far", label + " third merges far roles")
		for old_index: int in [2, 3]:
			var old_fan: Dictionary = prior.slots[old_index].sector_domination
			for sample: int in range(17):
				var width := fposmod(float(old_fan.end) - float(old_fan.start), TAU)
				var bearing := float(old_fan.start) + width * float(sample) / 16.0
				check(sector_contains(result.targets[2].sector, bearing), label + " merged sector covers both old arcs")

func run() -> void:
	_determinism()
	_casualties_axes_and_methods()
	_short_and_blocked()
	_height_and_translation()
	_sector_wrap_and_rejections()
	print("BREACH_ROOM_REFORMATION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _determinism() -> void:
	var reference := ""
	for seed_value: int in range(30):
		var data := fixture()
		data.seed = seed_value
		data.tick = seed_value
		data.time = float(seed_value) * STEP
		var prior := layout(data)
		check(bool(prior.get("ok", false)), "seed prior layout " + str(seed_value))
		if not bool(prior.get("ok", false)): continue
		var ids := IDS.slice(0, 3)
		var starts := positions(prior, ids)
		var before := JSON.stringify([data, prior, starts])
		var result := Drill.recalculate_three(data, prior, ids, starts)
		assert_reformation(data, prior, ids, starts, result, "seed " + str(seed_value))
		check(JSON.stringify([data, prior, starts]) == before, "remap does not mutate geometry/layout/current positions")
		check(JSON.stringify(Drill.recalculate_three(data, prior, ids, starts)) == JSON.stringify(result), "repeat has identical remap")
		if seed_value == 0: reference = JSON.stringify(result)
		check(JSON.stringify(result) == reference, "seed/STEP clock does not change pure geometry")
		seed(seed_value)
		var expected := randi()
		seed(seed_value)
		Drill.recalculate_three(data, prior, ids, starts)
		check(randi() == expected, "reformation consumes no RNG stream")
		if result.get("ok", false):
			var midpoint := (point(prior.slots[2].domination) + point(prior.slots[3].domination)) * 0.5
			check(point(result.targets[2].target).distance_to(midpoint) < 0.0001, "unblocked far role is the exact 3/4 midpoint")
		data.enemies = [{"id":"hidden", "x":8.0, "z":8.0, "can_act":true}]
		data["_live_doors"] = [{"id":"entry", "state":"CLOSED", "owner_id":"hidden"}]
		check(JSON.stringify(Drill.recalculate_three(data, prior, ids, starts)) == reference, "hidden enemies/door state do not influence remap")

func _casualties_axes_and_methods() -> void:
	for axis: String in ["x", "z"]:
		for method: String in ["OPEN_DOOR", "SHOTGUN_BREACH", "BREACH_DOOR"]:
			var data := fixture(5.0, 5.0, axis)
			var prior := layout(data, method)
			check(bool(prior.get("ok", false)), "orientation/method prior")
			if not prior.get("ok", false): continue
			for casualty: int in range(4):
				var ids := IDS.duplicate()
				ids.remove_at(casualty)
				for outside: bool in [false, true]:
					var starts := positions(prior, ids, outside)
					var result := Drill.recalculate_three(data, prior, ids, starts)
					assert_reformation(data, prior, ids, starts, result, axis + method + str(casualty) + str(outside))
					if casualty == 3 and not outside and result.get("ok", false):
						check(point(result.targets[0].target).distance_to(point(prior.slots[0].domination)) < 0.0001 and point(result.targets[1].target).distance_to(point(prior.slots[1].domination)) < 0.0001, "Zero-distance surviving near covers beat an unnecessary side swap")
					# Actual alpha-loss evidence exposed a forced left/right swap
					# deadlock. Retaining BRAVO's existing near cover avoids it;
					# both original corners and compressed tactical order remain.
					if casualty == 0 and not outside and result.get("ok", false):
						check(point(result.targets[0].target).distance_to(point(prior.slots[1].domination)) < 0.0001, "First casualty preserves surviving BRAVO's near cover")

func _short_and_blocked() -> void:
	var short_data := fixture(3.0, 3.0)
	var short_prior := layout(short_data)
	check(bool(short_prior.get("ok", false)) and bool(short_prior.get("short_room", false)), "SHORT original layout")
	if short_prior.get("ok", false):
		for casualty: int in range(4):
			var ids := IDS.duplicate()
			ids.remove_at(casualty)
			var starts := positions(short_prior, ids)
			assert_reformation(short_data, short_prior, ids, starts, Drill.recalculate_three(short_data, short_prior, ids, starts), "SHORT casualty " + str(casualty))
	var data := fixture()
	var prior := layout(data)
	var ids := IDS.slice(0, 3)
	var starts := positions(prior, ids)
	var midpoint := (point(prior.slots[2].domination) + point(prior.slots[3].domination)) * 0.5
	data.props.append({"id":"cabinet", "type":"cabinet", "cover":"full", "x":midpoint.x, "z":midpoint.y, "w":0.6, "d":0.6})
	var result := Drill.recalculate_three(data, prior, ids, starts)
	assert_reformation(data, prior, ids, starts, result, "blocked midpoint")
	if result.get("ok", false): check(point(result.targets[2].target).distance_to(midpoint) > 0.5, "blocked midpoint selects reachable far-zone alternative")
	data.props = [{"id":"sealed_far", "type":"cabinet", "cover":"full", "x":8.0, "z":6.8, "w":5.0, "d":3.0}]
	var before := JSON.stringify([data, prior, starts])
	var failure := Drill.recalculate_three(data, prior, ids, starts)
	check(not failure.ok and failure.targets.is_empty() and str(failure.message_key).begins_with("drill.error."), "blocked far zone rejects complete draft atomically with translated reason")
	check(JSON.stringify([data, prior, starts]) == before, "blocked rejection does not mutate inputs")

func _height_and_translation() -> void:
	var data := fixture()
	for group: String in ["rooms", "walls", "doors"]:
		for object: Dictionary in data[group]: object.base_height = 2.022
	data.rooms.push_front({"id":"apron", "x":10.0, "z":10.0, "w":20.0, "d":20.0, "indoor":false, "base_height":0.0})
	var prior := layout(data)
	check(prior.get("ok", false), "elevated overlap prior")
	if prior.get("ok", false):
		var ids := IDS.slice(0, 3)
		var starts := positions(prior, ids)
		var result := Drill.recalculate_three(data, prior, ids, starts)
		assert_reformation(data, prior, ids, starts, result, "elevated overlap")
		if result.get("ok", false):
			for target: Dictionary in result.targets: check(is_equal_approx(float(target.floor_height), 2.022), "authored base_height determines floor result")
	var near := fixture()
	var far := near.duplicate(true)
	far.bounds = [512.0,512.0]
	for group: String in ["rooms", "walls", "doors"]:
		for object: Dictionary in far[group]:
			object.x = float(object.x) + 472.0
			object.z = float(object.z) + 472.0
	var near_prior := layout(near)
	var far_prior := layout(far)
	check(near_prior.get("ok", false) and far_prior.get("ok", false), "512m translated priors")
	if near_prior.get("ok", false) and far_prior.get("ok", false):
		var ids := IDS.slice(0, 3)
		var near_result := Drill.recalculate_three(near, near_prior, ids, positions(near_prior, ids))
		var far_result := Drill.recalculate_three(far, far_prior, ids, positions(far_prior, ids))
		check(near_result.ok and far_result.ok, "512m translated remaps")
		if near_result.ok and far_result.ok:
			for index: int in range(3): check((point(far_result.targets[index].target) - Vector2(472.0,472.0)).distance_to(point(near_result.targets[index].target)) < 0.0001, "translation retains local role goal")

func _sector_wrap_and_rejections() -> void:
	var data := fixture()
	var prior := layout(data)
	var ids := IDS.slice(0, 3)
	var starts := positions(prior, ids)
	prior.slots[2].sector_domination = {"start":3.0, "end":-2.8, "center":PI, "duration":12.0}
	prior.slots[3].sector_domination = {"start":-3.0, "end":-2.5, "center":-2.75, "duration":12.0}
	var result := Drill.recalculate_three(data, prior, ids, starts)
	assert_reformation(data, prior, ids, starts, result, "PI seam union")
	if result.ok: check(fposmod(float(result.targets[2].sector.end) - float(result.targets[2].sector.start), TAU) < 1.0, "wrap union takes shorter covered arc")
	prior.slots[2].sector_domination.end = float(prior.slots[2].sector_domination.start) + TAU
	var full := Drill.recalculate_three(data, prior, ids, starts)
	check(full.ok and absf(float(full.targets[2].sector.end) - float(full.targets[2].sector.start)) >= TAU - 0.0001, "full circle retains explicit TAU width")
	for bad_ids: Array in [["alpha","alpha","bravo"], ["alpha","bravo"], ["alpha","bravo","hidden"]]:
		var rejected := Drill.recalculate_three(data, prior, bad_ids, starts)
		check(not rejected.ok and rejected.targets.is_empty(), "malformed survivor cohort rejects atomically")
	var malformed := prior.duplicate(true)
	malformed.slots[3].sector_domination = {"start":0.0,"end":1.0,"center":0.5,"duration":NAN}
	var invalid_sector := Drill.recalculate_three(data, malformed, ids, starts)
	check(not invalid_sector.ok and invalid_sector.targets.is_empty(), "non-finite sector rejects atomically")
	var malformed_geometry := data.duplicate(true)
	malformed_geometry.props = {"not":"an array"}
	var invalid_geometry := Drill.recalculate_three(malformed_geometry, prior, ids, starts)
	check(not invalid_geometry.ok and invalid_geometry.targets.is_empty(), "malformed static geometry rejects atomically")
