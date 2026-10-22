extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
const Actor = preload("res://scripts/actor_visual.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
const STEP := 1.0 / 30.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture() -> Dictionary:
	return {"id": "M01", "seed": 71, "bounds": [12, 12], "walls": [], "props": [], "doors": [], "rooms": [], "units": [{"id": "alpha", "x": 2.0, "z": 5.0, "facing": 0.0, "fov": 360.0}], "enemies": [{"id": "e1", "x": 6.0, "z": 5.0, "facing": PI, "hp": 10000.0, "training": true, "ammo": 0, "reserve_ammo": 0}], "civilians": [], "win": [{"type": "reach_zone", "zone": [10, 10, 1, 1]}], "fail": [{"type": "no_civilian_loss"}]}

func make_sim(data: Dictionary = {}) -> BreachSimulation:
	var sim := Simulation.new()
	sim.load_mission(fixture() if data.is_empty() else data)
	return sim

func direct_identified(sim: BreachSimulation) -> void:
	var unit: Dictionary = sim.units[0]
	unit._reaction = 0.0
	unit._observed = [{"id": "e1", "position": [sim.enemies[0].x, sim.enemies[0].z], "time": sim.time, "identified": true, "confidence": 1.0}]
	sim.enemies[0].visible = true

func run() -> void:
	_aim_state()
	_moving_glimpse()
	_enemy_contact()
	_resource_state()
	_accuracy_and_height()
	_protection_and_geometry()
	_hostage_resource_geometry()
	_visual_state()
	_determinism()
	print("BREACH_COMBAT_STATE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _aim_state() -> void:
	var sim := make_sim()
	direct_identified(sim)
	var ammo: int = sim.units[0].ammo
	sim._combat(sim.units[0], sim.enemies, false)
	check(sim.units[0].ammo == ammo and sim.units[0].aim_state != "ready", "Identified contact cannot bypass initial weapon acquisition at the same clock")
	var first_shot: float = -1.0
	for index: int in range(20):
		sim.time += STEP
		sim._update_combat_state(sim.units[0], STEP)
		direct_identified(sim)
		sim._combat(sim.units[0], sim.enemies, false)
		if sim.shots_fired > 0:
			first_shot = sim.time
			break
	check(is_equal_approx(first_shot, STEP), "Aligned operators fire on the first simulation tick")
	check(sim.units[0].aim_progress < 1.0 and sim.units[0].aim_state == "ready", "Muzzle alignment permits fire before aim finishes settling")
	var data: Dictionary = fixture()
	data.enemies[0].x = 2.0
	data.enemies[0].z = 9.0
	sim = make_sim(data)
	direct_identified(sim)
	var initial_ammo: int = sim.units[0].ammo
	var last_body: float = sim.units[0].body_facing
	var last_aim: float = sim.units[0].aim_facing
	for index: int in range(4):
		sim.time += STEP
		sim._update_combat_state(sim.units[0], STEP)
		direct_identified(sim)
		sim._combat(sim.units[0], sim.enemies, false)
		check(absf(angle_difference(last_body, sim.units[0].body_facing)) <= 5.2 * STEP + 0.00001, "Body turn is bounded on tick %d" % index)
		check(absf(angle_difference(last_aim, sim.units[0].aim_facing)) <= 6.4 * STEP + 0.00001, "Weapon turn is bounded on tick %d" % index)
		last_body = sim.units[0].body_facing
		last_aim = sim.units[0].aim_facing
	check(sim.units[0].ammo == initial_ammo, "A large angular change cannot produce an immediate shot")
	var held: Array = sim.units[0]._aim_position.duplicate()
	sim.enemies[0].x = 10.0
	sim.enemies[0].visible = false
	sim.units[0]._observed = []
	sim.units[0].fov = 20.0
	sim.time += STEP
	sim._update_presentation_aim(sim.units[0])
	check(sim.units[0]._aim_position == held, "Lost contact retains the last observation rather than hidden live coordinates")

func _moving_glimpse() -> void:
	var data := fixture()
	data.units[0].facing = PI
	data.units[0].fov = 110.0
	var sim := make_sim(data)
	var unit: Dictionary = sim.units[0]
	check(not sim.can_see(unit, sim.enemies[0]), "Glimpse starts with the enemy outside the operator's view")
	unit.facing = 0.0
	unit.body_facing = 0.0
	unit.aim_facing = 0.0
	sim.issue("alpha", "MOVE", {"target": [9.0, 5.0]}, true)
	sim._perception_time = 0.0
	var ammunition := int(unit.ammo)
	sim.step(STEP)
	check(float(unit.x) > 2.0 and int(unit.ammo) == ammunition - 1, "A newly spotted enemy receives immediate fire while the operator keeps moving")
	check(float(unit._reaction) == 0.0 and unit.aim_progress < 1.0, "First-contact firing does not wait for reaction or aim accumulation")
	sim.enemies[0].x = 0.5
	for index: int in range(20): sim.step(STEP)
	check(int(unit.ammo) == ammunition - 1, "Lost sight never permits fire using the last observed position")

func _enemy_contact() -> void:
	for seed_value: int in [42, 51, 71, 99, 123]:
		var data := fixture()
		data.seed = seed_value
		data.units[0].fov = 110.0
		data.units[0].ammo = 0
		data.units[0].reserve_ammo = 0
		data.enemies[0].x = 7.0
		data.enemies[0].hp = 72.0
		data.enemies[0].training = false
		data.enemies[0].can_surrender = false
		data.enemies[0].ammo = 24
		var sim := make_sim(data)
		var first_shot := -1.0
		for index: int in range(30):
			sim.step(STEP)
			if int(sim.enemies[0].ammo) < 24:
				first_shot = sim.time
				break
		check(first_shot > 0.0 and first_shot <= float(sim.enemy_rules.reaction_max) + STEP * 2.0, "seed %d: aligned enemy fires after reaction without a second aim-settling delay" % seed_value)
		data.units[0].ammo = 24
		sim = make_sim(data)
		for index: int in range(90): sim.step(STEP)
		check(int(sim.enemies[0].ammo) < 24 and float(sim.enemies[0].hp) <= 0.0, "seed %d: frontal enemy returns fire before being neutralized" % seed_value)
		data.enemies[0].facing = 0.0
		sim = make_sim(data)
		for index: int in range(12): sim.step(STEP)
		check(sim.shots_fired > 0 and int(sim.enemies[0].ammo) == 24, "seed %d: a rear ambush still wins initiative; enemy cannot fire backward" % seed_value)
	# A real flash effect must still block the otherwise faster shot and recovery.
	var data := fixture()
	data.units[0].ammo = 0
	data.units[0].reserve_ammo = 0
	data.enemies[0].training = false
	data.enemies[0].can_surrender = false
	data.enemies[0].ammo = 24
	var sim := make_sim(data)
	sim._explode_flash({"id":"contact-flash","position":[6.0,5.0,1.5],"unit_id":"alpha"})
	for index: int in range(65): sim.step(STEP)
	check(int(sim.enemies[0].ammo) == 24 and sim.enemies[0].flash_recover_remaining > 0.0, "Flash stun and recovery still prevent enemy fire")
	for index: int in range(60): sim.step(STEP)
	check(int(sim.enemies[0].ammo) < 24, "Enemy can fire again after flash recovery and reacquisition")
	data.enemies[0].training = true
	sim = make_sim(data)
	for index: int in range(30): sim.step(STEP)
	check(int(sim.enemies[0].ammo) == 24, "Passive tutorial targets remain non-combatants")

func _resource_state() -> void:
	var sim := make_sim()
	var unit: Dictionary = sim.units[0]
	unit.ammo = 3
	unit.reserve_ammo = 5
	var duration: float = sim._begin_resource_reload(unit)
	check(duration > 0.0 and unit.ammo == 3 and unit.reserve_ammo == 5, "Beginning reload reserves time without creating or consuming rounds")
	check(sim._finish_resource_reload(unit) == 5 and unit.ammo == 8 and unit.reserve_ammo == 0, "Partial reload transfers only the remaining finite reserve")
	check(sim._begin_resource_reload(unit) == 0.0 and sim._finish_resource_reload(unit) == 0 and unit.ammo == 8, "Exhausted reserve cannot refill a magazine")
	unit.ammo = unit.max_ammo
	unit.reserve_ammo = 12
	check(sim._begin_resource_reload(unit) == 0.0 and unit.reserve_ammo == 12, "A full magazine leaves reserve untouched")
	unit.ammo = 0
	unit.hp = 25.0
	sim._update_combat_state(unit, STEP)
	check(unit.injury_status == "wounded" and unit.mobility_multiplier < 1.0 and unit.action_multiplier > 1.0, "Wound state consistently changes mobility and action pace")
	check(sim._begin_resource_reload(unit) > duration, "Wound state slows reload timing in the game model")
	var enemy: Dictionary = sim.enemies[0]
	enemy.training = false
	enemy.ammo = 0
	enemy.reserve_ammo = 0
	for index: int in range(100):
		sim.time += STEP
		sim._advance_enemy(enemy, STEP)
	check(enemy.ammo == 0 and enemy.reserve_ammo == 0 and enemy.status != "RELOADING", "An enemy with no loaded or reserve rounds never starts an infinite refill loop")

func _accuracy_and_height() -> void:
	var sim := make_sim()
	var unit: Dictionary = sim.units[0]
	var target: Dictionary = sim.enemies[0]
	var stationary: float = sim._shot_accuracy(unit, target, false)
	unit._combat_moving_until = sim.time + 1.0
	unit.movement_mode = "careful"
	var careful: float = sim._shot_accuracy(unit, target, false)
	unit.movement_mode = "normal"
	var normal: float = sim._shot_accuracy(unit, target, false)
	unit.movement_mode = "fast"
	var fast: float = sim._shot_accuracy(unit, target, false)
	check(stationary > careful and careful > normal and normal > fast, "Authoritative motion mode changes shot stability consistently")
	unit._combat_moving_until = -1.0
	unit.hp = 25.0
	sim._update_combat_state(unit, STEP)
	check(sim._shot_accuracy(unit, target, false) < stationary, "Wounded state changes shot stability even before the next hit animation")
	unit.hp = 100.0
	unit.stance = "standing"
	sim._refresh_weapon_state(unit)
	var standing_height: float = unit.weapon_origin[2]
	unit.stance = "crouched"
	sim._refresh_weapon_state(unit)
	check(float(unit.weapon_origin[2]) < standing_height and is_equal_approx(float(unit.weapon_origin[2]), Spatial.weapon_height(unit)), "Stance changes the physical muzzle height independently of skeleton sampling")
	var data: Dictionary = fixture()
	data.props = [{"id": "desk", "x": 5.1, "z": 5.0, "w": 0.6, "d": 2.0, "cover": "low", "height": 1.05, "material": "steel"}]
	sim = make_sim(data)
	var covered: float = sim._shot_accuracy(sim.units[0], sim.enemies[0], false)
	check(covered > 0.0 and covered < stationary, "Partial body occlusion affects accuracy by actual exposure")
	sim.enemies[0].stance = "crouched"
	check(sim._shot_accuracy(sim.units[0], sim.enemies[0], false) < covered, "Crouching behind the same cover changes exposed target geometry")

func _protection_and_geometry() -> void:
	var data: Dictionary = fixture()
	data.units.append({"id": "bravo", "x": 4.0, "z": 5.0})
	var sim := make_sim(data)
	check(not sim.fire_line_clear(sim.units[0], sim.enemies[0]), "Friendly body blocks the simulated muzzle line")
	data.units.pop_back()
	data.civilians = [{"id": "c1", "x": 4.0, "z": 5.0}]
	sim = make_sim(data)
	check(not sim.fire_line_clear(sim.units[0], sim.enemies[0]), "Civilian body blocks the simulated muzzle line")
	data.civilians = []
	data.walls = [{"x": 2.2, "z": 5.0, "w": 0.1, "d": 3.0, "height": 2.7, "material": "concrete"}]
	sim = make_sim(data)
	check(sim.units[0].weapon_origin[0] <= 2.001 and not sim.fire_line_clear(sim.units[0], sim.enemies[0]), "Muzzle cannot cross a wall before the body and fire from the far side")
	data.walls[0].material = "glass"
	data.walls[0].opacity = 0.15
	sim = make_sim(data)
	check(sim.units[0].weapon_origin[0] <= 2.001, "Transparent glass remains a physical barrier to muzzle placement")
	sim = make_sim()
	sim._set_surrendered(sim.enemies[0])
	direct_identified(sim)
	sim.units[0].aim_progress = 1.0
	sim.units[0].aim_state = "ready"
	var ammo: int = sim.units[0].ammo
	sim._combat(sim.units[0], sim.enemies, false)
	check(sim.units[0].ammo == ammo, "Automatic engagement continues protecting a surrendered target")

func _hostage_resource_geometry() -> void:
	var data: Dictionary = fixture()
	data.enemies[0].training = false
	data.enemies[0].enemy_type = "hostage_taker"
	data.enemies[0].hostage_id = "c1"
	data.enemies[0].ammo = 1
	data.civilians = [{"id": "c1", "x": 5.0, "z": 5.0}]
	var sim := make_sim(data)
	var enemy: Dictionary = sim.enemies[0]
	enemy.status = "ALERT"
	enemy._hostage_alert_elapsed = 4.0
	for index: int in range(60):
		sim.time += STEP
		enemy._cooldown = maxf(0.0, float(enemy._cooldown) - STEP)
		sim._update_combat_state(enemy, STEP)
		enemy.status = "ALERT"
		var before := int(enemy.ammo)
		sim._advance_hostage_threat(enemy, STEP)
		if int(enemy.ammo) < before:
			check(float(enemy.aim_progress) >= 0.999, "Faster combat return fire does not bypass hostage execution preparation")
	check(enemy.ammo == 0 and sim.civilians[0].hp == 75.0, "Hostage threat requires acquisition and consumes a finite loaded round")
	for index: int in range(100):
		sim.time += STEP
		enemy._cooldown = maxf(0.0, float(enemy._cooldown) - STEP)
		enemy.status = "ALERT"
		sim._advance_hostage_threat(enemy, STEP)
	check(sim.civilians[0].hp == 75.0 and enemy.reserve_ammo == 0, "Exhausted hostile resource cannot continue damaging a hostage")
	data.walls = [{"x": 5.5, "z": 5.0, "w": 0.2, "d": 3.0, "height": 2.6, "material": "concrete"}]
	sim = make_sim(data)
	enemy = sim.enemies[0]
	enemy.status = "ALERT"
	enemy._hostage_alert_elapsed = 4.0
	for index: int in range(60):
		sim.time += STEP
		enemy.status = "ALERT"
		sim._advance_hostage_threat(enemy, STEP)
	check(sim.civilians[0].hp == 100.0 and enemy.ammo == 1, "An authored hostage ID cannot bypass direct observation or solid height geometry")

func _visual_state() -> void:
	var body := Node3D.new()
	root.add_child(body)
	var visual: Dictionary = Actor.create(body, false)
	var entity: Dictionary = make_sim().units[0].duplicate(true)
	Actor.sync(visual, entity, [], 0.0, 0.0, false)
	var sk: Skeleton3D = visual.skeleton
	var hips: int = sk.find_bone("Hips")
	var foot: int = sk.find_bone("Foot.L")
	var standing_hips: float = (sk.global_transform * sk.get_bone_global_pose(hips).origin).y
	var original_foot: Vector3 = sk.global_transform * sk.get_bone_global_pose(foot).origin
	entity.stance = "crouched"
	Actor.sync(visual, entity, [], 0.2, 0.0, false)
	var crouched_hips: float = (sk.global_transform * sk.get_bone_global_pose(hips).origin).y
	check(crouched_hips < standing_hips - 0.4, "Crouched simulation posture produces a lower visual pelvis")
	check((sk.global_transform * sk.get_bone_global_pose(foot).origin).distance_to(original_foot) < 0.04, "Crouch leg solve preserves planted foot contact")
	Actor.sync(visual, entity, [{"type": "SHOT", "attacker_id": "alpha", "time": 0.21}], 0.21, 0.0, false)
	check(absf((sk.global_transform * sk.get_bone_global_pose(hips).origin).y - crouched_hips) < 0.03, "Fire transition does not apply crouch lowering twice")
	entity.stance = "standing"
	entity.body_facing = 0.0
	entity.aim_facing = 0.6
	Actor.sync(visual, entity, [], 1.0, 0.0, false)
	var torso: Transform3D = sk.get_bone_global_pose(sk.find_bone("Abdomen"))
	entity.aim_facing = 0.0
	Actor.sync(visual, entity, [], 1.0, 0.0, false)
	check(not sk.get_bone_global_pose(sk.find_bone("Abdomen")).basis.is_equal_approx(torso.basis), "Same-clock weapon aim changes rotate the upper body independently of body facing")
	body.queue_free()

func _determinism() -> void:
	var first := make_sim()
	var second := make_sim()
	for sim: BreachSimulation in [first, second]:
		sim.units[0].ammo = 2
		sim.units[0].reserve_ammo = 3
		sim.issue("alpha", "WAIT", {"duration": 1.1})
		sim.issue("alpha", "RELOAD", {})
	for index: int in range(120):
		first.step(STEP)
		second.step(STEP)
	check(JSON.stringify(first.snapshot(true)) == JSON.stringify(second.snapshot(true)), "Fixed-seed aim, finite resource, injury and events remain reproducible")
	var entity: Dictionary = first.snapshot(true).units[0]
	for key: String in ["body_facing", "aim_facing", "aim_progress", "aim_state", "stance", "movement_mode", "injury_status", "reserve_ammo", "mobility_multiplier", "weapon_origin"]:
		check(entity.has(key), "Snapshot exposes authoritative combat state " + key)
