extends SceneTree
## Import security and timeline fidelity for actual recorded equipment/flash state.
const Replay = preload("res://scripts/replay.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Presentation = preload("res://scripts/presentation_state.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	var mission: Dictionary = Catalog.load("M01")
	var unit: Dictionary = mission.units[0]
	var door: Dictionary = mission.doors[0]
	var enemy: Dictionary = mission.enemies[0]
	var civilian: Dictionary = mission.civilians[0]
	var observation := {"id": enemy.id, "kind": "enemy", "name": str(enemy.get("name", enemy.id)), "x": enemy.x, "z": enemy.z, "facing": 0.0, "hp": 100.0, "status": "IDLE", "observed_at": 0.0}
	var actor := {"id": unit.id, "kind": "unit", "name": "Raven", "weapon": "standard", "x": unit.x, "z": unit.z, "facing": 0.0, "hp": 100.0, "ammo": 24, "max_ammo": 24, "stuns": 1, "stunned": 0.0, "status": "IDLE", "visible": true, "sidearm": "pico_p1", "armor": "frame_v2", "helmet": "crown_h1", "attachments": ["dot"], "appearance": {"name": "Raven", "callsign": "R-1", "color": "#53675e", "patch": "raven"}, "preset": "custom", "active_weapon": "primary", "current_weapon": "standard", "primary_ammo": 24, "primary_reserve_ammo": 48, "secondary_ammo": 15, "secondary_reserve_ammo": 30, "weapon_length": 0.78, "equipment_weight": 10.0, "flash_recover_remaining": 0.0, "camera_remaining": 0.0, "camera_origin": [unit.x, unit.z], "camera_facing": 0.0, "camera_observations": [observation], "commands": [{"id": "gear-1", "type": "OPEN_AND_FLASH", "args": {"door_id": door.id, "target": [door.x, float(door.z) + 1.5]}, "state": "RUNNING", "phase": "WAIT_EXPLOSION", "projectile_id": "flash-1"}, {"id": "gear-2", "type": "SWITCH_WEAPON", "args": {"slot": "secondary"}, "state": "PENDING"}, {"id": "gear-3", "type": "PEEK_CAMERA", "args": {"door_id": door.id}, "state": "PENDING"}]}
	var state := {"time": 0.0, "tick": 0, "units": [actor], "enemies": [], "civilians": [{"id": civilian.id, "kind": "civilian", "x": civilian.x, "z": civilian.z, "hp": 100.0, "status": "IDLE", "stunned": 0.0, "visible": true}], "doors": [], "events": [], "flash_projectiles": [], "broken_glass": []}
	var recorder := Replay.new()
	recorder.begin(mission)
	recorder.capture(state)
	var projectile := {"id": "flash-1", "unit_id": unit.id, "command_id": "gear-1", "door_id": door.id, "source": [unit.x, unit.z, 1.2], "target": [float(unit.x) + 3.0, unit.z, 0.12], "position": [unit.x, unit.z, 1.2], "released_at": 0.2, "flight_duration": 0.6, "detonate_at": 1.4, "phase": "FLIGHT"}
	state.time = 0.2
	state.tick = 6
	state.flash_projectiles = [projectile]
	recorder.capture(state, [{"seq": 1, "tick": 6, "time": 0.2, "type": "FLASH_RELEASE", "projectile_id": "flash-1", "unit_id": unit.id, "door_id": door.id, "from": [unit.x, unit.z], "to": [float(unit.x) + 3.0, unit.z], "radius": 3.0, "source_height": 1.2, "target_height": 0.12, "flight_duration": 0.6, "detonate_at": 1.4}])
	state.time = 0.9
	state.tick = 27
	state.flash_projectiles = Replay.sample_flash_projectiles([projectile], 0.9)
	state.broken_glass = [{"object_id": "wall-0", "object_kind": "wall", "x": unit.x, "z": unit.z, "broken_at": 0.9}]
	recorder.capture(state, [{"seq": 2, "tick": 27, "time": 0.9, "type": "GLASS_BREAK", "object_id": "wall-0", "object_kind": "wall", "unit_id": unit.id, "projectile_id": "flash-1", "from": [unit.x, unit.z]}])
	state.time = 1.4
	state.tick = 42
	state.flash_projectiles = []
	state.civilians[0].status = "STUNNED"
	state.civilians[0].stunned = 2.0
	state.units[0].active_weapon = "secondary"
	state.units[0].current_weapon = "pico_p1"
	recorder.capture(state, [{"seq": 3, "tick": 42, "time": 1.4, "type": "STUN", "projectile_id": "flash-1", "unit_id": unit.id, "door_id": door.id, "to": [float(unit.x) + 3.0, unit.z], "radius": 3.0}])
	state.time = 2.0
	state.tick = 60
	recorder.finish(state)
	var exported: Dictionary = JSON.parse_string(JSON.stringify(recorder.export_data()))
	var imported := Replay.new()
	var result: Dictionary = imported.load_data(exported)
	check(bool(result.get("ok", false)), "New equipment and flash replay did not import: " + str(result.get("message", "")))
	if bool(result.get("ok", false)):
		var flight: Dictionary = imported.seek(0.5)
		check(flight.flash_projectiles.size() == 1 and flight.flash_projectiles[0].phase == "FLIGHT", "Seeking midflight lost the projectile")
		check(absf(float(flight.flash_projectiles[0].position[0]) - (float(unit.x) + 1.5)) < 0.0001, "Seeking did not derive flash flight from the simulation clock")
		check(float(flight.flash_projectiles[0].position[2]) > 0.66, "Flash flight lost its arc")
		var fuse: Dictionary = imported.seek(1.1)
		check(fuse.broken_glass.size() == 1 and imported.seek(0.5).broken_glass.is_empty(), "Replay lost persistent glass break or leaked it before impact")
		check(fuse.flash_projectiles.size() == 1 and fuse.flash_projectiles[0].phase == "FUSE", "Fuse state was not retained before detonation")
		var burst: Dictionary = imported.seek(1.4)
		check(burst.flash_projectiles.is_empty() and burst.civilians[0].stunned == 2.0 and burst.civilians[0].hp == 100.0, "Explosion seek lost harmless civilian stun")
		check(burst.units[0].armor == "frame_v2" and burst.units[0].current_weapon == "pico_p1" and burst.units[0].secondary_ammo == 15, "Seek lost protection or independent sidearm state")
		check(imported.seek(0.5).units[0].camera_observations[0].observed_at == 0.0, "Camera memory silently refreshed on a replay seek")
	var malicious := exported.duplicate(true)
	for definition: Dictionary in malicious.states:
		if definition.group == "units":
			definition.base.appearance = {"path": "res://bad.gd"}
			break
	check(not Replay.new().load_data(malicious).get("ok", true), "Replay gear whitelist accepted an injected resource path")
	malicious = exported.duplicate(true)
	for metadata: Dictionary in malicious.metadata:
		if not metadata.get("flash_projectiles", []).is_empty():
			metadata.flash_projectiles[0].target = [999999, 1, 1]
			break
	check(not Replay.new().load_data(malicious).get("ok", true), "Replay allowed an out-of-map flash trajectory")
	var presentation := Presentation.new()
	var previous := state.duplicate(true)
	previous.time = 0.9
	previous.flash_projectiles = [projectile]
	var following := previous.duplicate(true)
	following.time = 0.9 + 1.0 / 30.0
	following.flash_projectiles = []
	projectile.detonate_at = float(following.time)
	presentation.reset(previous)
	presentation.capture(following)
	check(presentation.sample(0.5).flash_projectiles.size() == 1, "Presentation removed a flash before the actual detonation frame")
	check(presentation.sample(1.0).flash_projectiles.is_empty(), "Presentation kept a projectile after explosion")
	print("BREACH_CUSTOMIZATION_REPLAY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
