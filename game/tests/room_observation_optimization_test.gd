extends SceneTree
## The reference retains the pre-optimization loop. Both implementations run
## the complete simulation at fixed STEP; no timing threshold accepts a result.
const Catalog = preload("res://scripts/mission_catalog.gd")
const STEP := 1.0 / 30.0

class Original extends "res://scripts/simulation.gd":
	var observation: Dictionary = {}
	func _room_observation() -> Dictionary:
		var observed: Dictionary = {}
		for room: Dictionary in mission.get("rooms", []):
			var id := str(room.id)
			var exploration: Dictionary = _room_exploration[id]
			var rect: Rect2 = exploration.rect
			var current := false
			var center := false
			var floor_height := float(room.get("base_height", 0.0))
			for unit: Dictionary in units:
				if not _can_act(unit) or absf(float(unit.get("base_height", 0.0)) - floor_height) > 0.01: continue
				var distance := effective_vision_range(unit)
				if not rect.intersects(Rect2(_position(unit) - Vector2.ONE * distance, Vector2.ONE * distance * 2.0)): continue
				if _room_point_seen(unit, _position(room), floor_height): center = true
				if room_control.room_at(_position(unit), floor_height) == id: current = true
				for index: int in range(exploration.points.size()):
					var point := _point(exploration.points[index])
					if _position(unit).distance_squared_to(point) > distance * distance: continue
					if _room_point_seen(unit, point, floor_height):
						exploration.seen[index] = true
						current = true
			observed[id] = {"fraction":float(exploration.seen.size()) / float(exploration.points.size()),"center":center,"current":current}
		observation = observed.duplicate(true)
		return observed

class Optimized extends "res://scripts/simulation.gd":
	var observation: Dictionary = {}
	func _room_observation() -> Dictionary:
		var observed := super._room_observation()
		observation = observed.duplicate(true)
		return observed

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture(seed_value: int) -> Dictionary:
	return {"id":"OBSERVATION_OPTIMIZATION","seed":seed_value,"bounds":[16,12],
		"rooms":[{"id":"room","x":8.0,"z":6.0,"w":4.0,"d":4.0}],
		"walls":[],"props":[],"doors":[],
		"units":[{"id":"alpha","x":4.0,"z":6.0,"facing":0.0,"vision_range":12.0,"fov":90.0,"ammo":0,"reserve_ammo":0}],
		"enemies":[],"civilians":[],"win":[{"type":"reach_zone","zone":[15.0,11.0,0.1,0.1]}],"fail":[]}

func divided(seed_value: int) -> Dictionary:
	var data := fixture(seed_value)
	data.rooms = [{"id":"left","x":4.0,"z":6.0,"w":6.0,"d":8.0}, {"id":"right","x":10.0,"z":6.0,"w":6.0,"d":8.0}]
	data.walls = [{"x":7.0,"z":3.05,"w":0.24,"d":3.9}, {"x":7.0,"z":9.95,"w":0.24,"d":3.9}]
	data.doors = [{"id":"door","x":7.0,"z":6.0,"w":0.24,"d":1.8,"axis":"z","state":"CLOSED","swing_sign":1.0}]
	data.units[0].x = 6.6
	data.units[0].z = 6.612
	return data

func issue(sim: RefCounted, type: String, args: Dictionary) -> void:
	var answer: Dictionary = sim.issue("alpha", type, args, true)
	check(bool(answer.get("ok", false)), "%s accepted in observation comparison: %s" % [type, str(answer)])

func setup(sim: RefCounted, data: Dictionary, kind: String) -> void:
	sim.load_mission(data.duplicate(true))
	match kind:
		"scan":
			issue(sim, "WAIT", {"duration":0.3})
			issue(sim, "FACE", {"target":[1.0,6.0],"persistent":true})
			issue(sim, "WAIT", {"duration":0.3})
			issue(sim, "FACE", {"target":[10.0,6.0],"persistent":true})
			issue(sim, "MOVE", {"target":[7.0,6.0]})
		"door": issue(sim, "OPEN_DOOR", {"door_id":"door"})
		"camera": issue(sim, "PEEK_CAMERA", {"door_id":"door"})
		"peek":
			issue(sim, "FACE", {"target":[6.6,10.0],"persistent":true})
			issue(sim, "PEEK_DOOR", {"door_id":"door"})
		"smoke": issue(sim, "THROW_SMOKE", {"target":[6.0,6.0]})
		"M01":
			issue(sim, "FACE", {"unlock":true})
			issue(sim, "OPEN_DOOR", {"door_id":"d1"})
			issue(sim, "MOVE", {"target":[11.2,13.6]})
			issue(sim, "FACE", {"target":[12.0,10.0]})

func seen_snapshot(sim: RefCounted) -> Dictionary:
	var seen: Dictionary = {}
	for id: String in sim._room_exploration:
		seen[id] = sim._room_exploration[id].seen.duplicate(true)
	return seen

func rng_states(sim: RefCounted) -> Array:
	return [sim._rng.state,sim._hit_region_rng.state,sim._breach_rng.state,sim._surrender_rng.state]

func compare_tick(original: RefCounted, optimized: RefCounted, label: String) -> void:
	check(original.observation == optimized.observation, label + " exact raw fraction/center/current")
	check(seen_snapshot(original) == seen_snapshot(optimized), label + " exact accumulated sample set")
	check(JSON.stringify(original.snapshot(true)) == JSON.stringify(optimized.snapshot(true)), label + " exact full authoritative snapshot")
	check(rng_states(original) == rng_states(optimized), label + " exact four RNG streams")

func pair(data: Dictionary, kind: String, frames: int) -> Dictionary:
	var original := Original.new()
	var optimized := Optimized.new()
	setup(original, data, kind)
	setup(optimized, data, kind)
	var facts := {"known_without_current":false,"camera":false,"peek":false,"smoke_hidden":false,"smoke_recovered":false,"right_seen":false,"opening":false,"opened":false}
	for frame: int in range(frames):
		original.step(STEP)
		optimized.step(STEP)
		compare_tick(original, optimized, "%s seed %d tick %d" % [kind,int(data.seed),frame + 1])
		for row: Dictionary in original.observation.values():
			if float(row.fraction) > 0.0 and not bool(row.current): facts.known_without_current = true
		if original.observation.has("right") and float(original.observation.right.fraction) > 0.0: facts.right_seen = true
		if float(original.units[0].camera_remaining) > 0.0: facts.camera = true
		if float(original.units[0].get("_peek_remaining",0.0)) > 0.0: facts.peek = true
		if kind == "smoke":
			if not original._smoke_zones.is_empty() and not bool(original.observation.room.current): facts.smoke_hidden = true
			if bool(facts.smoke_hidden) and original._smoke_zones.is_empty() and bool(original.observation.room.current): facts.smoke_recovered = true
		if not original.doors.is_empty():
			if original.doors[0].state == "OPENING" and float(original.doors[0].progress) > 0.0 and float(original.doors[0].progress) < 1.0: facts.opening = true
			if original.doors[0].state == "OPEN": facts.opened = true
	return {"original":original,"optimized":optimized,"facts":facts}

func directed() -> void:
	var data := fixture(17)
	data.rooms = [{"id":"room","x":6.0,"z":5.0,"w":2.0,"d":2.0}]
	data.units[0].z = 5.0
	data.units[0].fov = 2.0
	var result := pair(data,"center",90)
	check(bool(result.original.observation.room.center) and not bool(result.original.observation.room.current), "Fresh center LOS is independent of grid current observation")
	data = fixture(29)
	data.units[0].x = 8.0
	data.units[0].vision_range = 0.0
	pair(data,"zero_range",90)
	data = fixture(17)
	data.units[0].x = 8.0
	data.units[0].base_height = 0.005
	result = pair(data,"floor_tolerance",90)
	check(bool(result.original.observation.room.current) and float(result.original.units[0].base_height) == 0.005, "Presence retains authored-floor room_at and the original 0.01 eligibility tolerance")
	data = fixture(29)
	data.rooms.append({"id":"upper","x":8.0,"z":6.0,"w":4.0,"d":4.0,"base_height":3.0})
	data.units.append({"id":"bravo","x":8.0,"z":6.0,"base_height":3.0,"facing":0.0,"stance":"crouched","ammo":0})
	pair(data,"overlapping_floors",90)
	data = divided(0)
	data.units[0].cameras = 1
	result = pair(data,"camera",120)
	check(bool(result.facts.camera) and bool(result.facts.right_seen), "Actual camera command provides behind-leaf floor observations")
	data = divided(17)
	data.units[0].fov = 20.0
	result = pair(data,"peek",150)
	check(bool(result.facts.peek) and bool(result.facts.right_seen), "Actual partial-leaf peek supplies a reachable additional eye origin")
	data = fixture(29)
	data.units[0].smokes = 1
	result = pair(data,"smoke",180)
	check(bool(result.facts.smoke_hidden) and bool(result.facts.smoke_recovered), "Actual smoke hides historical samples and fresh observation returns after expiry")
	# These are sensory-input boundary comparisons, not authored command outcomes.
	# Can-act flags are identical on both sides and exercised through real STEP.
	for predicate: String in ["stunned","flash_recover_remaining","surrendered","arrested"]:
		data = fixture(0)
		var original := Original.new()
		var optimized := Optimized.new()
		setup(original,data,"eligibility")
		setup(optimized,data,"eligibility")
		for sim: RefCounted in [original,optimized]: sim.units[0][predicate] = true if predicate in ["surrendered","arrested"] else 0.1
		for frame: int in range(6):
			original.step(STEP)
			optimized.step(STEP)
			compare_tick(original,optimized,"eligibility %s tick %d" % [predicate,frame + 1])
	# Authoritative door-pose inputs isolate exact sensory boundaries. This
	# comparison does not claim that a player command can close or destroy a leaf.
	for seed_value: int in [0,17,29]:
		data = divided(seed_value)
		data.doors[0].state = "OPEN"
		var original := Original.new()
		var optimized := Optimized.new()
		setup(original,data,"door_pose")
		setup(optimized,data,"door_pose")
		for frame: int in range(5):
			original.step(STEP)
			optimized.step(STEP)
			compare_tick(original,optimized,"door initial seed %d tick %d" % [seed_value,frame + 1])
		var known := float(original.observation.right.fraction)
		check(known > 0.0, "seed %d initially open leaf actually exposes right-room samples" % seed_value)
		for pose: Dictionary in [{"state":"CLOSED","progress":0.0,"destroyed":false}, {"state":"AJAR","progress":0.499,"destroyed":false}, {"state":"AJAR","progress":0.501,"destroyed":false}, {"state":"OPEN","progress":1.0,"destroyed":true}]:
			for sim: RefCounted in [original,optimized]:
				for key: String in pose: sim.doors[0][key] = pose[key]
			for frame: int in range(5):
				original.step(STEP)
				optimized.step(STEP)
				compare_tick(original,optimized,"door %s seed %d tick %d" % [str(pose),seed_value,frame + 1])
			if pose.state == "CLOSED": check(float(original.observation.right.fraction) == known and not bool(original.observation.right.current), "seed %d closing a leaf retains historical samples without current visibility" % seed_value)

func run() -> void:
	for seed_value: int in range(30):
		var scan := pair(fixture(seed_value),"scan",90)
		check(bool(scan.facts.known_without_current), "seed %d retains explored samples when actual FOV turns away" % seed_value)
		var data := divided(seed_value)
		data.units.append({"id":"bravo","x":3.0,"z":3.0,"facing":0.0,"fov":110.0,"ammo":0})
		data.props = [{"x":10.0,"z":6.0,"w":0.5,"d":1.2,"height":2.2,"opaque":true}]
		pair(data,"wall_and_prop",90)
		var door := pair(divided(seed_value),"door",90)
		check(bool(door.facts.opening) and bool(door.facts.opened), "seed %d compares actual partial and fully opened leaf poses" % seed_value)
	for seed_value: int in [0,17,29]:
		var data: Dictionary = Catalog.load("M01")
		data.seed = seed_value
		pair(data,"M01",90)
	directed()
	print("BREACH_ROOM_OBSERVATION_OPTIMIZATION_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
