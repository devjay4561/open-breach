extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const Equipment = preload("res://scripts/equipment_catalog.gd")
const STEP: float = 1.0 / 30.0
var checks: int = 0
var failures: Array[String] = []
var case_reached_end: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func fixture() -> Dictionary:
	return {
		"id": "CUSTOM_TACTICS", "seed": 71, "bounds": [20, 16],
		"walls": [], "props": [], "doors": [], "rooms": [],
		"units": [{"id": "alpha", "x": 2.0, "z": 5.0, "facing": 0.0, "weapon": "standard", "ammo": 0, "reserve_ammo": 0}],
		"enemies": [], "civilians": [],
		"win": [{"type": "reach_zone", "zone": [18, 14, 1, 1]}], "fail": []
	}

func make(data: Dictionary) -> BreachSimulation:
	var sim := Simulation.new()
	sim.load_mission(data)
	return sim

func advance(sim: BreachSimulation, seconds: float) -> void:
	for index: int in range(ceili(seconds / STEP)):
		sim.step(STEP)

func has_event(sim: BreachSimulation, type: String) -> bool:
	for event: Dictionary in sim.events:
		if str(event.get("type", "")) == type:
			return true
	return false

func run() -> void:
	for method: String in ["_flash_lifecycle_and_targets", "_flash_cancellation_and_validation", "_door_flash_sequence", "_opened_door_flash", "_last_flash_idempotency", "_flash_through_glass", "_friendly_accuracy", "_secondary_ammunition", "_switch_destination_timing", "_displayed_action_times", "_weapon_geometry", "_directional_protection", "_hit_metadata", "_camera_memory", "_cancelled_camera", "_person_approach_arrival", "_approach_defense_and_busy_hands"]:
		case_reached_end = false
		call(method)
		check(case_reached_end, method + " reaches its final assertion without script errors")
	print("BREACH_CUSTOMIZATION_TACTICS_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func flash_fixture() -> Dictionary:
	var data: Dictionary = fixture()
	data.units.append({"id": "bravo", "x": 5.0, "z": 5.8, "facing": 0.0, "ammo": 0, "reserve_ammo": 0})
	data.enemies = [
		{"id": "inside", "x": 6.0, "z": 5.0, "facing": 0.0, "passive": true, "ammo": 0, "reserve_ammo": 0},
		{"id": "outside", "x": 9.2, "z": 5.0, "facing": 0.0, "passive": true, "ammo": 0, "reserve_ammo": 0},
		{"id": "behind_wall", "x": 6.0, "z": 8.0, "facing": 0.0, "passive": true, "ammo": 0, "reserve_ammo": 0}
	]
	data.civilians = [{"id": "hostage", "x": 6.0, "z": 5.8}]
	data.walls = [{"x": 6.0, "z": 6.5, "w": 3.0, "d": 0.3}]
	return data

func _flash_lifecycle_and_targets() -> void:
	var sim := make(flash_fixture())
	var health: Array = (sim.units + sim.enemies + sim.civilians).map(func(entity: Dictionary) -> float: return float(entity.hp))
	var response: Dictionary = sim.issue("alpha", "THROW_STUN", {"target": [6.0, 5.0], "request_id": "one-flash"}, true)
	check(bool(response.get("ok", false)), "Flash command is accepted")
	var duplicate: Dictionary = sim.issue("alpha", "THROW_STUN", {"target": [6.0, 5.0], "request_id": "one-flash"}, true)
	check(response.get("id") == duplicate.get("id") and sim.units[0].commands.size() == 1, "Repeated browser request reserves only one flash")
	sim.issue("alpha", "MOVE", {"target": [3.0, 5.0]}, true)
	advance(sim, 0.3)
	check(int(sim.units[0].stuns) == 2 and not has_event(sim, "FLASH_RELEASE"), "Preparation does not consume the grenade before release")
	var released: bool = false
	var detonated: bool = false
	var waited: bool = true
	for index: int in range(150):
		sim.step(STEP)
		if not released and int(sim.units[0].stuns) == 1:
			released = true
			check(sim.time >= 0.43, "Release respects the 0.45 second preparation")
			check(not sim.snapshot(true).get("flash_projectiles", []).is_empty(), "Released grenade has an authoritative in-flight snapshot")
			check(float(sim.enemies[0].stunned) == 0.0, "Release precedes explosion and stun")
		if not has_event(sim, "STUN"):
			waited = waited and Vector2(float(sim.units[0].x), float(sim.units[0].z)).distance_to(Vector2(2, 5)) < 0.02
		else:
			detonated = true
			break
	check(released and detonated, "Prepared grenade releases and subsequently detonates")
	check(waited, "Following movement waits for actual detonation")
	check(int(sim.units[0].stuns) == 1 and sim.stuns_used == 1, "One release consumes exactly one grenade")
	check(float(sim.enemies[0].stunned) > 1.9 and float(sim.enemies[0].stunned) <= 2.01, "Enemy in clear blast radius receives two seconds of stun")
	check(float(sim.enemies[1].stunned) == 0.0, "Enemy outside three meter radius is unaffected")
	check(float(sim.enemies[2].stunned) == 0.0, "Opaque wall blocks flash effect")
	check(float(sim.units[0].stunned) == 0.0 and float(sim.units[1].stunned) == 0.0, "Friendly operators are immune to flash stun")
	check(float(sim.civilians[0].stunned) > 1.9, "Civilian receives temporary stun")
	var after: Array = (sim.units + sim.enemies + sim.civilians).map(func(entity: Dictionary) -> float: return float(entity.hp))
	check(health == after, "Flash causes no health damage to enemies, operators or civilians")
	var civilian_start := Vector2(float(sim.civilians[0].x), float(sim.civilians[0].z))
	advance(sim, 0.5)
	check(Vector2(float(sim.civilians[0].x), float(sim.civilians[0].z)).distance_to(civilian_start) < 0.01, "Stunned civilian does not panic-move")
	advance(sim, 2.0)
	check(float(sim.enemies[0].stunned) == 0.0 and float(sim.civilians[0].stunned) == 0.0, "Enemy and civilian stun timers expire")
	check(str(sim.units[0].commands.back().state) == "SUCCEEDED", "Queued movement resumes after flash explosion")
	check(sim.snapshot(true).get("flash_projectiles", []).is_empty(), "Exploded projectile is removed from live state")
	case_reached_end = true

func _flash_cancellation_and_validation() -> void:
	var data: Dictionary = fixture()
	data.enemies = [{"id": "guard", "x": 6.0, "z": 5.0, "facing": 0.0, "passive": true, "ammo": 0, "reserve_ammo": 0}]
	var before := make(data)
	before.issue("alpha", "THROW_STUN", {"target": [6.0, 5.0]}, true)
	advance(before, 0.2)
	before.remove_command("alpha", 0)
	advance(before, 1.5)
	check(int(before.units[0].stuns) == 2 and not has_event(before, "STUN"), "Cancelling before release preserves unused grenade")
	var after := make(data)
	after.issue("alpha", "THROW_STUN", {"target": [6.0, 5.0]}, true)
	for index: int in range(60):
		after.step(STEP)
		if has_event(after, "FLASH_RELEASE"):
			break
	after.remove_command("alpha", 0)
	after.units[0].hp = 0.0
	# Keep a second living operator so the operation does not end before flight.
	var survivor: Dictionary = after._make_entity({"id": "bravo", "x": 2.0, "z": 7.0, "ammo": 0, "reserve_ammo": 0}, "unit")
	after.units.append(survivor)
	advance(after, 1.5)
	check(has_event(after, "STUN") and int(after.units[0].stuns) == 1, "Released grenade still detonates after cancellation and thrower incapacitation")
	var range_sim := make(data)
	range_sim.issue("alpha", "THROW_STUN", {"target": [11.0, 5.0]}, true)
	advance(range_sim, 1.5)
	check(int(range_sim.units[0].stuns) == 2 and not has_event(range_sim, "FLASH_RELEASE"), "Out-of-range flash does not consume stock")
	data.walls = [{"x": 4.0, "z": 6.0, "w": 0.4, "d": 12.0}]
	var wall_sim := make(data)
	wall_sim.issue("alpha", "THROW_STUN", {"target": [6.0, 5.0]}, true)
	advance(wall_sim, 1.5)
	check(int(wall_sim.units[0].stuns) == 2 and not has_event(wall_sim, "STUN"), "Solid wall blocks throw without consuming stock")
	case_reached_end = true

func doorway_fixture() -> Dictionary:
	var data: Dictionary = fixture()
	data.units[0].x = 7.0
	data.units[0].z = 4.0
	data.units[0].facing = PI / 2.0
	data.units.append({"id": "bravo", "x": 8.0, "z": 4.0, "facing": PI / 2.0, "ammo": 0, "reserve_ammo": 0})
	data.walls = [{"x": 3.0, "z": 6.0, "w": 6.0, "d": 0.3}, {"x": 12.0, "z": 6.0, "w": 8.0, "d": 0.3}]
	data.doors = [{"id": "entry", "x": 7.0, "z": 6.0, "w": 2.0, "d": 0.3, "axis": "x", "state": "CLOSED", "progress": 0.0}]
	return data

func _door_flash_sequence() -> void:
	var sim := make(doorway_fixture())
	var response: Dictionary = sim.issue("alpha", "OPEN_AND_FLASH", {"door_id": "entry"}, true)
	check(bool(response.get("ok", false)), "Closed-door composite command accepts a geometry-derived landing point")
	if not bool(response.get("ok", false)):
		case_reached_end = true
		return
	check(bool(sim.issue("alpha", "MOVE", {"target": [7.0, 8.5]}, true).get("ok", false)), "Movement can be queued after composite entry")
	check(bool(sim.plan_move("bravo", {"target": [8.5, 8.0]}).get("ok", false)), "Teammate can plan movement through same door")
	var held: bool = true
	var released: bool = false
	var opened_first: bool = true
	var completed: bool = false
	for index: int in range(600):
		sim.step(STEP)
		if has_event(sim, "FLASH_RELEASE"):
			released = true
			opened_first = opened_first and str(sim.doors[0].state) == "OPEN"
		if not has_event(sim, "STUN"):
			for unit: Dictionary in sim.units:
				held = held and float(unit.z) < 6.0
		completed = str(sim.units[0].commands.back().state) == "SUCCEEDED" and str(sim.units[1].commands.back().state) == "SUCCEEDED"
		if completed or sim.command_failures > 0:
			break
	check(released and opened_first, "Door opens before composite grenade release")
	check(held, "Thrower and same-door teammate stay outside until explosion")
	check(completed and sim.command_failures == 0, "Both operators continue queued entry after explosion")
	check(int(sim.units[0].stuns) == 1 and str(sim.doors[0].owner_id).is_empty(), "Composite completion consumes once and releases door ownership")
	check(sim._reservations.is_empty(), "Completed composite entry leaves no passage reservation")
	var locked_data: Dictionary = doorway_fixture()
	locked_data.doors[0].locked = true
	var locked := make(locked_data)
	locked.issue("alpha", "OPEN_AND_FLASH", {"door_id": "entry"}, true)
	advance(locked, 3.0)
	check(str(locked.doors[0].state) != "OPEN" and int(locked.units[0].stuns) == 2, "Locked door is not silently kicked and consumes no grenade")
	var cancelled := make(doorway_fixture())
	cancelled.issue("alpha", "OPEN_AND_FLASH", {"door_id": "entry"}, true)
	advance(cancelled, 0.2)
	cancelled.remove_command("alpha", 0)
	advance(cancelled, 1.0)
	check(int(cancelled.units[0].stuns) == 2 and cancelled._flash_door_barriers.is_empty(), "Cancelling composite before release preserves stock and releases entry barrier")
	check(str(cancelled.doors[0].owner_id).is_empty(), "Cancelled composite releases door operator ownership")
	var released_cancel := make(doorway_fixture())
	released_cancel.issue("alpha", "OPEN_AND_FLASH", {"door_id": "entry"}, true)
	for index: int in range(240):
		released_cancel.step(STEP)
		if has_event(released_cancel, "FLASH_RELEASE"):
			break
	check(has_event(released_cancel, "FLASH_RELEASE"), "Composite release is reached before cancellation regression")
	released_cancel.remove_command("alpha", 0)
	check(released_cancel._flash_door_barriers.has("entry"), "Released composite retains same-door explosion barrier after cancellation")
	advance(released_cancel, 1.5)
	check(has_event(released_cancel, "STUN") and released_cancel._flash_door_barriers.is_empty(), "Actual explosion clears cancelled composite entry barrier")
	case_reached_end = true

func _friendly_accuracy() -> void:
	var data: Dictionary = fixture()
	data.enemies = [{"id": "target", "x": 6.0, "z": 5.0, "facing": PI, "ammo": 0, "reserve_ammo": 0}]
	var sim := make(data)
	var unit: Dictionary = sim.units[0]
	var enemy: Dictionary = sim.enemies[0]
	check(is_equal_approx(sim._shot_accuracy(unit, enemy, false), 0.97), "Healthy stationary standard rifle has 97 percent open-target accuracy")
	for mode: String in ["careful", "normal", "fast"]:
		unit.movement_mode = mode
		unit._combat_moving_until = sim.time + 1.0
		var expected: float = {"careful": 0.9118, "normal": 0.8148, "fast": 0.6596}[mode]
		check(is_equal_approx(sim._shot_accuracy(unit, enemy, false), expected), "Friendly %s movement uses improved accuracy" % mode)
		enemy.movement_mode = mode
		enemy._combat_moving_until = sim.time + 1.0
		var hostile: float = float(sim.enemy_rules.accuracy) * float({"careful": 0.88, "normal": 0.76, "fast": 0.60}[mode])
		check(is_equal_approx(sim._shot_accuracy(enemy, unit, true), hostile), "Hostile %s movement retains old accuracy" % mode)
	unit._combat_moving_until = -1.0
	unit.suppressed = 1.0
	check(is_equal_approx(sim._shot_accuracy(unit, enemy, false), 0.485), "Suppression still halves ordinary operator accuracy")
	unit.suppressed = 0.0
	unit.hp = unit.max_hp * 0.3
	check(is_equal_approx(sim._shot_accuracy(unit, enemy, false), 0.6984), "Severe wound still reduces friendly accuracy")
	data.units[0].weapon = "light"
	var light := make(data)
	check(is_equal_approx(light._shot_accuracy(light.units[0], light.enemies[0], false), 0.95), "Light weapon has 95 percent stationary open-target accuracy")
	case_reached_end = true

func _opened_door_flash() -> void:
	var data: Dictionary = doorway_fixture()
	data.units = [data.units[0]]
	data.doors[0].state = "OPEN"
	data.doors[0].progress = 1.0
	var sim := make(data)
	var response: Dictionary = sim.issue("alpha", "OPEN_AND_FLASH", {"door_id": "entry"}, true)
	check(bool(response.get("ok", false)), "Already-open door accepts composite flash command")
	if not bool(response.get("ok", false)):
		case_reached_end = true
		return
	advance(sim, 5.0)
	check(has_event(sim, "FLASH_RELEASE") and has_event(sim, "STUN"), "Already-open door skips opening and executes flash release and explosion")
	check(int(sim.units[0].stuns) == 1 and str(sim.units[0].commands[0].state) == "SUCCEEDED", "Already-open composite completes with one grenade consumed")
	check(str(sim.doors[0].state) == "OPEN" and sim._flash_door_barriers.is_empty(), "Already-open composite leaves passage open without stale barrier")
	case_reached_end = true

func _last_flash_idempotency() -> void:
	for type: String in ["THROW_STUN", "OPEN_AND_FLASH"]:
		var data: Dictionary = fixture() if type == "THROW_STUN" else doorway_fixture()
		data.units[0].stuns = 1
		var sim := make(data)
		var args: Dictionary = {"target": [6.0, 5.0], "request_id": "last-direct"} if type == "THROW_STUN" else {"door_id": "entry", "request_id": "last-composite"}
		var first: Dictionary = sim.issue("alpha", type, args, true)
		var repeated: Dictionary = sim.issue("alpha", type, args, true)
		check(bool(first.get("ok", false)) and repeated == first and sim.units[0].commands.size() == 1, type + " duplicate last-stock reservation returns original response")
		if not bool(first.get("ok", false)):
			continue
		var other_args: Dictionary = args.duplicate(true)
		other_args.request_id = "new-reservation"
		check(not bool(sim.issue("alpha", type, other_args, true).get("ok", false)), type + " cannot reserve a second grenade after last-stock reservation")
		for index: int in range(240):
			sim.step(STEP)
			if has_event(sim, "FLASH_RELEASE"):
				break
		check(int(sim.units[0].stuns) == 0 and sim.issue("alpha", type, args, true) == first, type + " duplicate request remains idempotent after stock is consumed")
		advance(sim, 2.0)
		check(sim.issue("alpha", type, args, true) == first and sim.units[0].commands.size() == 1 and sim.stuns_used == 1, type + " completed request replay returns original response without another throw")
	case_reached_end = true

func _flash_through_glass() -> void:
	var data: Dictionary = fixture()
	data.walls = [{"id": "glass_window", "x": 4.0, "z": 5.0, "w": 0.12, "d": 4.0, "height": 2.4, "material": "glass", "opacity": 0.8}]
	data.enemies = [{"id": "behind_glass", "x": 6.0, "z": 5.0, "facing": 0.0, "passive": true, "ammo": 0, "reserve_ammo": 0}]
	var sim := make(data)
	check(not sim.nav.sight_clear_height(Vector2(2, 5), Vector2(6, 5), 1.5, 1.5), "Opaque glass initially blocks sight")
	check(not sim.nav.walkable(Vector2(4, 5)), "Window frame initially blocks walking")
	var response: Dictionary = sim.issue("alpha", "THROW_STUN", {"target": [6.0, 5.0]}, true)
	check(bool(response.get("ok", false)), "Flash can be planned through glass")
	if not bool(response.get("ok", false)):
		case_reached_end = true
		return
	var release_time: float = -1.0
	var break_time: float = -1.0
	var seen_release: bool = false
	for index: int in range(150):
		sim.step(STEP)
		if not seen_release and has_event(sim, "FLASH_RELEASE"):
			seen_release = true
			release_time = sim.time
			check(not has_event(sim, "GLASS_BREAK"), "Glass does not break before projectile reaches window")
		if break_time < 0.0 and has_event(sim, "GLASS_BREAK"):
			break_time = sim.time
		if has_event(sim, "STUN"):
			break
	check(seen_release and break_time > release_time, "In-flight glass impact occurs after grenade release")
	var impact: Dictionary = {}
	var break_events: int = 0
	for event: Dictionary in sim.events:
		if str(event.get("type", "")) == "GLASS_BREAK":
			impact = event
			break_events += 1
	check(break_events == 1 and impact.get("object_id", "") == "glass_window" and impact.get("object_kind", "") == "wall", "Glass impact identifies exactly one struck wall")
	check(impact.get("from", []).size() == 2, "Glass impact records a two-dimensional world point")
	check(float(sim.enemies[0].stunned) > 1.9, "Flash reaches and stuns enemy beyond glass")
	check(sim.nav.sight_clear_height(Vector2(2, 5), Vector2(6, 5), 1.5, 1.5), "Broken glass restores physical line of sight")
	check(not sim.nav.walkable(Vector2(4, 5)) and not sim.nav.segment_clear(Vector2(2, 5), Vector2(6, 5), sim.nav.RADIUS), "Breaking glass preserves window frame walking collision")
	check(int(sim.units[0].stuns) == 1, "Glass impact does not consume a second grenade")
	var broken: Array = sim.snapshot(true).get("broken_glass", [])
	check(broken.size() == 1 and broken[0].get("object_id", "") == "glass_window" and broken[0].get("object_kind", "") == "wall", "Snapshot records the same glass destruction for presentation and replay")
	check(not broken.is_empty() and float(broken[0].get("broken_at", -1.0)) == break_time, "Glass snapshot retains its actual impact timestamp")
	case_reached_end = true

func _secondary_ammunition() -> void:
	var data: Dictionary = fixture()
	data.units[0].sidearm = "pico_p1"
	var sim := make(data)
	var unit: Dictionary = sim.units[0]
	unit.ammo = 3
	unit.primary_ammo = 3
	unit.reserve_ammo = 5
	unit.primary_reserve_ammo = 5
	unit.secondary_ammo = 2
	unit.secondary_reserve_ammo = 5
	var response: Dictionary = sim.issue("alpha", "SWITCH_WEAPON", {"slot": "secondary"}, true)
	check(bool(response.get("ok", false)), "Equipped sidearm can be selected")
	if not bool(response.get("ok", false)):
		case_reached_end = true
		return
	sim.step(STEP)
	check(str(unit.get("active_weapon", "primary")) == "primary", "Weapon switch takes simulation time")
	advance(sim, 1.0)
	check(str(unit.get("active_weapon", "")) == "secondary" and str(unit.get("current_weapon", "")) == "pico_p1", "Completed switch activates equipped pistol")
	check(int(unit.ammo) == 2 and int(unit.reserve_ammo) == 5 and int(unit.primary_ammo) == 3, "Switch preserves separate pistol and rifle magazines")
	sim.issue("alpha", "RELOAD", {}, true)
	advance(sim, 3.0)
	check(int(unit.ammo) == 7 and int(unit.secondary_ammo) == 7 and int(unit.reserve_ammo) == 0, "Pistol reload transfers only its finite reserve")
	check(int(unit.primary_ammo) == 3 and int(unit.primary_reserve_ammo) == 5, "Pistol reload leaves rifle resources unchanged")
	sim.issue("alpha", "SWITCH_WEAPON", {"slot": "primary"}, true)
	advance(sim, 1.0)
	check(str(unit.get("active_weapon", "")) == "primary" and int(unit.ammo) == 3 and int(unit.reserve_ammo) == 5, "Switching back restores rifle ammunition")
	var no_sidearm := make(fixture())
	var rejected: Dictionary = no_sidearm.issue("alpha", "SWITCH_WEAPON", {"slot": "secondary"}, true)
	advance(no_sidearm, 1.0)
	check(not bool(rejected.get("ok", false)) or str(no_sidearm.units[0].get("active_weapon", "primary")) == "primary", "Missing sidearm cannot create a free pistol")
	case_reached_end = true

func _directional_protection() -> void:
	var catalog: Script = load("res://scripts/equipment_catalog.gd")
	check(catalog != null, "Shared equipment catalog is available")
	if catalog == null:
		case_reached_end = true
		return
	var armor: Dictionary = {"armor": "frame_v2", "helmet": "crown_h1"}
	var front: Dictionary = catalog.protection(armor, "torso", 0.0, 0.0)
	var back: Dictionary = catalog.protection(armor, "torso", PI, 0.0)
	var side: Dictionary = catalog.protection(armor, "torso", PI / 2.0, 0.0)
	var limb: Dictionary = catalog.protection(armor, "limb", 0.0, 0.0)
	check(float(front.get("reduction", 0.0)) > 0.0 and float(back.get("reduction", 0.0)) > 0.0, "Frame plates protect torso front and rear")
	check(float(side.get("reduction", 0.0)) < float(front.get("reduction", 0.0)), "Side coverage does not falsely equal front plate protection")
	check(float(limb.get("reduction", 0.0)) == 0.0, "Torso armor does not protect exposed limbs")
	var swift_side: Dictionary = catalog.protection({"armor": "swift_v3"}, "torso", PI / 2.0, 0.0)
	check(not bool(swift_side.get("protected", false)) and float(swift_side.get("reduction", 0.0)) == 0.0, "Swift plate carrier leaves the side exposed")
	var head: Dictionary = catalog.protection(armor, "head", 0.0, 0.0)
	var bare_head: Dictionary = catalog.protection({"armor": "frame_v2", "helmet": "none"}, "head", 0.0, 0.0)
	check(float(head.get("reduction", 0.0)) > float(bare_head.get("reduction", 0.0)), "Helmet changes actual head-hit protection")
	var penetrating: Dictionary = catalog.protection(armor, "torso", 0.0, 100.0)
	check(float(penetrating.get("reduction", 0.0)) < float(front.get("reduction", 0.0)), "High penetration reduces armor effectiveness")
	case_reached_end = true

func _switch_destination_timing() -> void:
	var data: Dictionary = fixture()
	data.units[0].sidearm = "pico_p1"
	var sim := make(data)
	var unit: Dictionary = sim.units[0]
	sim.issue("alpha", "SWITCH_WEAPON", {"slot": "secondary"}, true)
	var secondary_command: Dictionary = unit.commands[0]
	sim._start_command(unit, secondary_command)
	check(is_equal_approx(float(secondary_command.remaining), float(Equipment.weapon_stats("pico_p1").switch_time)), "Drawing pistol uses destination pistol switch time")
	advance(sim, 1.0)
	sim.issue("alpha", "SWITCH_WEAPON", {"slot": "primary"}, true)
	var primary_command: Dictionary = unit.commands.back()
	sim._start_command(unit, primary_command)
	check(is_equal_approx(float(primary_command.remaining), float(Equipment.weapon_stats("standard").switch_time)), "Returning to rifle uses destination rifle switch time")
	advance(sim, 1.0)
	unit.hp = 25.0
	sim._update_combat_state(unit, STEP)
	sim.issue("alpha", "SWITCH_WEAPON", {"slot": "secondary"}, true)
	var wounded_command: Dictionary = unit.commands.back()
	sim._start_command(unit, wounded_command)
	check(float(unit.action_multiplier) > 1.0 and is_equal_approx(float(wounded_command.remaining), float(Equipment.weapon_stats("pico_p1").switch_time) * float(unit.action_multiplier)), "Injury slows destination weapon switch time")
	case_reached_end = true

func _displayed_action_times() -> void:
	var data: Dictionary = fixture()
	data.units[0].merge({"weapon":"suppressed", "sidearm":"pico_p1", "armor":"bastion_v4", "helmet":"crown_h2", "trait":"marksman", "reserve_ammo":72}, true)
	var displayed: Dictionary = Equipment.loadout_stats(data.units[0], "marksman")
	var sim := make(data)
	var unit: Dictionary = sim.units[0]
	check(is_equal_approx(sim._begin_resource_reload(unit), float(displayed.final_reload_time)), "Displayed heavy-armor reload equals authoritative reload duration")
	unit.reload_remaining = 0.0
	unit._aim_position = [6.0, 5.0]
	unit._aim_observed_at = sim.time
	unit._aim_advanced_at = sim.time - STEP
	unit.aim_progress = 0.0
	sim._advance_authoritative_aim(unit)
	check(is_equal_approx(float(unit.aim_progress), STEP / float(displayed.final_aim_time)), "Displayed long-gun aim includes armor and physical handling penalties")
	sim.issue("alpha", "SWITCH_WEAPON", {"slot":"secondary"}, true)
	sim._start_command(unit, unit.commands[0])
	check(is_equal_approx(float(unit.commands[0].remaining), float(displayed.secondary_switch_time)), "Displayed pistol draw time equals authoritative heavy-armor action")
	check(is_equal_approx(float(displayed.range), 12.0) and is_equal_approx(float(displayed.interval), 0.675), "Displayed marksman range includes its firing cadence tradeoff")
	case_reached_end = true

func _weapon_geometry() -> void:
	var offsets: Dictionary = {}
	for id: String in ["standard", "light", "shotgun"]:
		var data: Dictionary = fixture()
		data.units[0].weapon = id
		var sim := make(data)
		var unit: Dictionary = sim.units[0]
		offsets[id] = (Vector2(float(unit.weapon_origin[0]), float(unit.weapon_origin[1])) - sim._position(unit)).dot(Vector2.RIGHT)
		check(is_equal_approx(float(unit.weapon_origin[2]), Spatial.weapon_height(unit)), id + " authoritative muzzle height matches spatial profile")
	check(float(offsets.shotgun) > float(offsets.standard) and float(offsets.standard) > float(offsets.light), "Different gun models produce long shotgun, rifle and short SMG muzzle reach")
	var suppressed_data: Dictionary = fixture()
	suppressed_data.units[0].attachments = ["suppressor"]
	var suppressed := make(suppressed_data)
	var suppressor_reach: float = float(suppressed.units[0].weapon_origin[0]) - float(suppressed.units[0].x)
	check(is_equal_approx(suppressor_reach - float(offsets.standard), 0.2), "Fitted suppressor extends actual muzzle by twenty centimeters")
	var data: Dictionary = fixture()
	data.units[0].sidearm = "pico_p1"
	var sim := make(data)
	var unit: Dictionary = sim.units[0]
	sim._switch_weapon_slot(unit, "secondary")
	var pistol_reach: float = float(unit.weapon_origin[0]) - float(unit.x)
	check(pistol_reach < float(offsets.light), "Drawing compact pistol shortens authoritative muzzle reach")
	sim._switch_weapon_slot(unit, "primary")
	unit.aim_facing = PI / 2.0
	sim._refresh_weapon_state(unit)
	var rotated := Vector2(float(unit.weapon_origin[0]), float(unit.weapon_origin[1])) - sim._position(unit)
	check(is_equal_approx(rotated.dot(Vector2.DOWN), float(offsets.standard)), "Muzzle reach rotates with authoritative aim")
	var standing_height: float = float(unit.weapon_origin[2])
	unit.stance = "crouched"
	sim._refresh_weapon_state(unit)
	check(float(unit.weapon_origin[2]) < standing_height, "Crouching lowers the actual muzzle")
	var wall_data: Dictionary = fixture()
	wall_data.units[0].sidearm = "pico_p1"
	wall_data.walls = [{"x": 2.6, "z": 5.0, "w": 0.2, "d": 4.0, "height": 2.4}]
	var wall := make(wall_data)
	check(Vector2(float(wall.units[0].weapon_origin[0]), float(wall.units[0].weapon_origin[1])) == wall._position(wall.units[0]), "Long rifle muzzle does not teleport through nearby wall")
	wall._switch_weapon_slot(wall.units[0], "secondary")
	check(float(wall.units[0].weapon_origin[0]) > float(wall.units[0].x) and float(wall.units[0].weapon_origin[0]) < 2.5, "Short pistol can stay ready on near side of the same wall")
	case_reached_end = true

func _cancelled_camera() -> void:
	var data: Dictionary = doorway_fixture()
	data.units = [data.units[0]]
	data.units[0].equipment = {"probe_c1": 1}
	data.enemies = [{"id": "hidden", "x": 7.0, "z": 8.0, "facing": 0.0, "passive": true, "ammo": 0, "reserve_ammo": 0}]
	var sim := make(data)
	sim.issue("alpha", "PEEK_CAMERA", {"door_id": "entry"}, true)
	for index: int in range(240):
		sim.step(STEP)
		if float(sim.units[0].get("camera_remaining", 0.0)) > 0.0:
			break
	check(float(sim.units[0].get("camera_remaining", 0.0)) > 0.0, "Camera cancellation fixture reaches live probe phase")
	var remembered: Array = sim.units[0].get("camera_observations", []).duplicate(true)
	sim.remove_command("alpha", 0)
	check(float(sim.units[0].get("camera_remaining", -1.0)) == 0.0 and sim._camera_sensor(sim.units[0]).is_empty(), "Cancelling active camera immediately closes live probe")
	sim.enemies[0].x = 12.0
	sim.enemies[0].z = 9.0
	advance(sim, 0.2)
	check(sim.units[0].get("camera_observations", []) == remembered, "Cancelled camera preserves only observed memory without fresh hidden tracking")
	check(str(sim.doors[0].owner_id).is_empty(), "Cancelled camera releases door interaction ownership")
	case_reached_end = true

func _camera_memory() -> void:
	var data: Dictionary = doorway_fixture()
	data.units = [data.units[0]]
	data.units[0].equipment = {"probe_c1": 1}
	data.enemies = [{"id": "hidden", "x": 7.0, "z": 8.0, "facing": 0.0, "passive": true, "ammo": 0, "reserve_ammo": 0}]
	var sim := make(data)
	check(sim.snapshot().enemies.is_empty() or not bool(sim.snapshot().enemies[0].get("visible", false)), "Closed room does not reveal enemy before camera use")
	var response: Dictionary = sim.issue("alpha", "PEEK_CAMERA", {"door_id": "entry"}, true)
	check(bool(response.get("ok", false)), "Equipped camera can inspect a known door")
	if not bool(response.get("ok", false)):
		case_reached_end = true
		return
	for index: int in range(240):
		sim.step(STEP)
		if str(sim.units[0].commands[0].state) == "SUCCEEDED":
			break
	var observations: Array = sim.units[0].get("camera_observations", [])
	check(not observations.is_empty(), "Camera creates actual opposite-side observations")
	check(str(sim.doors[0].state) == "CLOSED", "Camera inspection does not open the door")
	if observations.is_empty():
		case_reached_end = true
		return
	var remembered: Dictionary = observations[0].duplicate(true)
	check(remembered.has("observed_at") and str(remembered.get("id", "")) == "hidden", "Camera memory records contact identity and observation time")
	sim.enemies[0].x = 12.0
	sim.enemies[0].z = 9.0
	advance(sim, 2.0)
	var later: Array = sim.units[0].get("camera_observations", [])
	check(not later.is_empty() and later[0] == remembered, "Expired camera observation retains its timestamp and point without tracking hidden live movement")
	data.walls.append({"x": 7.0, "z": 7.0, "w": 4.0, "d": 0.3})
	var obscured := make(data)
	obscured.issue("alpha", "PEEK_CAMERA", {"door_id": "entry"}, true)
	advance(obscured, 8.0)
	check(obscured.units[0].get("camera_observations", []).is_empty(), "Camera cannot reveal target through an opaque internal wall")
	case_reached_end = true

func _hit_metadata() -> void:
	var data: Dictionary = fixture()
	data.units[0].armor = "frame_v2"
	data.units[0].helmet = "crown_h2"
	data.units[0].hp = 10000.0
	data.units[0].fov = 360.0
	data.enemies = [{"id": "shooter", "x": 6.0, "z": 5.0, "facing": PI, "ammo": 1, "reserve_ammo": 0}]
	var sim := make(data)
	var attacker: Dictionary = sim.enemies[0]
	var target: Dictionary = sim.units[0]
	var front: Dictionary = sim._hit_protection(attacker, target, {"hit_part": "torso"})
	check(front.hit_part == "torso" and front.hit_direction == "front" and front.protection == "blocked", "Physical torso hit records front panel protection")
	check(is_equal_approx(float(front.damage_multiplier), 0.38), "Front plate damage reduction is applied to the shot")
	attacker.x = 2.0
	attacker.z = 9.0
	var side: Dictionary = sim._hit_protection(attacker, target, {"hit_part": "torso"})
	check(side.hit_direction == "side" and side.protection == "penetrated" and float(side.damage_multiplier) == 1.0, "Standard rifle penetrates weaker side panel without gaining front protection")
	attacker.x = 6.0
	attacker.z = 5.0
	var head: Dictionary = sim._hit_protection(attacker, target, {"hit_part": "head"})
	check(head.armor_id == "crown_h2" and head.protection == "blocked", "Head hit uses helmet instead of torso armor")
	var limb: Dictionary = sim._hit_protection(attacker, target, {"hit_part": "limb"})
	check(limb.protection == "unprotected" and float(limb.damage_multiplier) == 1.0, "Exposed limb hit remains unprotected")
	sim.enemy_rules.accuracy = 1.0
	for index: int in range(180):
		sim.step(STEP)
		if has_event(sim, "SHOT"):
			break
	var shot: Dictionary = {}
	for event: Dictionary in sim.events:
		if str(event.get("type", "")) == "SHOT":
			shot = event
	check(not shot.is_empty(), "Ordinary hostile combat emits a shot for armor metadata regression")
	if shot.is_empty():
		case_reached_end = true
		return
	check(shot.get("hit_part", "") in ["head", "torso", "limb"] and shot.get("hit_direction", "") in ["front", "side", "back"], "Shot event records resolved body part and incoming direction")
	check(shot.get("protection", "") in ["blocked", "penetrated", "unprotected"] and shot.has("damage_multiplier") and shot.has("armor_id") and shot.has("panel"), "Shot event carries armor outcome and damage factor for presentation and replay")
	check(bool(shot.get("hit", false)) and is_equal_approx(10000.0 - float(target.hp), float(shot.get("damage", -1.0))), "Recorded hit damage equals authoritative health change")
	var public: Dictionary = sim.snapshot(true).units[0]
	check(public.get("last_hit_part", "") == shot.hit_part and public.get("last_hit_protection", "") == shot.protection, "Public actor hit state matches the recorded physical hit")
	case_reached_end = true

func _person_approach_arrival() -> void:
	# A civilian moved during panic. Its still-valid final approach point is
	# 1.05m away, with the operator 7.5cm short of that waypoint.
	var data: Dictionary = fixture()
	data.bounds = [24, 16]
	data.units[0].x = 19.447649
	data.units[0].z = 4.438222
	data.units[0].facing = -0.845648
	data.civilians = [{"id": "civilian", "x": 20.272984, "z": 3.681654}]
	var sim := make(data)
	var response: Dictionary = sim.issue("alpha", "SECURE_CIVILIAN", {"civilian_id": "civilian"}, true)
	check(bool(response.get("ok", false)), "Person approach regression accepts observed civilian")
	if not bool(response.get("ok", false)):
		case_reached_end = true
		return
	var command: Dictionary = sim.units[0].commands[0]
	sim._start_command(sim.units[0], command)
	command.path = [[19.497004, 4.382529]]
	command.path_cursor = 0
	advance(sim, 3.0)
	check(bool(sim.civilians[0].secured) and command.state == "SUCCEEDED", "Person approach reaches interaction distance instead of hanging at waypoint tolerance")
	check(sim._position(sim.units[0]).distance_to(sim._position(sim.civilians[0])) <= 1.1 and sim.command_failures == 0, "Completed person approach respects physical interaction reach")
	case_reached_end = true

func _approach_defense_and_busy_hands() -> void:
	var data: Dictionary = fixture()
	data.units[0].ammo = 24
	data.units[0].reserve_ammo = 72
	data.units[0].equipment = {"probe_c1": 1, "stun": 1}
	data.enemies = [{"id": "blocker", "x": 4.0, "z": 5.0, "facing": PI, "hp": 10000.0, "training": true, "ammo": 0, "reserve_ammo": 0}]
	data.doors = [{"id": "far_door", "x": 10.0, "z": 5.0, "w": 0.3, "d": 2.0, "axis": "z", "state": "CLOSED", "progress": 0.0}]
	for type: String in ["OPEN_DOOR", "OPEN_AND_FLASH", "PEEK_CAMERA"]:
		var approaching := make(data)
		check(bool(approaching.issue("alpha", type, {"door_id": "far_door"}, true).get("ok", false)), type + " distant approach is accepted")
		advance(approaching, 1.6)
		check(int(approaching.units[0].ammo) < 24 and approaching.shots_fired > 0, type + " approach can aim and defend against armed body blocker")
		check(approaching.doors[0].state == "CLOSED", type + " defense occurs before actual door manipulation")
	var sim := make(data)
	advance(sim, 1.0)
	var unit: Dictionary = sim.units[0]
	var enemy: Dictionary = sim.enemies[0]
	sim.issue("alpha", "OPEN_DOOR", {"door_id": "far_door"}, true)
	var command: Dictionary = unit.commands[0]
	sim._start_command(unit, command)
	command.state = "WAITING"
	unit.status = "WAITING"
	sim.doors[0].owner_id = "another_operator"
	unit._cooldown = 0.0
	unit.aim_progress = 1.0
	unit.aim_state = "ready"
	var ammunition: int = int(unit.ammo)
	sim._combat(unit, [enemy], false)
	check(int(unit.ammo) < ammunition, "Waiting for another door owner still permits observed threat response")
	sim.doors[0].owner_id = unit.id
	sim.doors[0].owner_command_id = command.id
	unit.status = "OPENING"
	unit._cooldown = 0.0
	ammunition = int(unit.ammo)
	sim._combat(unit, [enemy], false)
	check(int(unit.ammo) == ammunition, "Actual door leaf owner cannot shoot while manipulating it")
	sim.doors[0].owner_id = ""
	sim.doors[0].owner_command_id = ""
	for type: String in ["PEEK_CAMERA", "THROW_STUN"]:
		var args: Dictionary = {"door_id": "far_door"} if type == "PEEK_CAMERA" else {"target": [4.0, 5.0]}
		sim.issue("alpha", type, args, false)
		var busy: Dictionary = unit.commands.back()
		sim._start_command(unit, busy)
		busy.phase = "CAMERA" if type == "PEEK_CAMERA" else "PREPARE"
		unit._cooldown = 0.0
		ammunition = int(unit.ammo)
		sim._combat(unit, [enemy], false)
		check(int(unit.ammo) == ammunition, type + " active manipulation keeps shooting disabled")
	case_reached_end = true
