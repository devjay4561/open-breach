class_name BreachSimulation
extends RefCounted

const MissionCatalog = preload("res://scripts/mission_catalog.gd")
const DoorGeometry = preload("res://scripts/door_geometry.gd")
const Navigation = preload("res://scripts/navigation.gd")
const AcousticModel = preload("res://scripts/acoustic_model.gd")
const SensoryGait = preload("res://scripts/locomotion_profile.gd")
# AI hearing is gameplay tuning. Replacing visual motion must not change combat
# or replay outcomes; presentation footsteps follow the current animation rig.
const FOOTSTEP_CADENCE := {
	"RifleWalk": [1.133652, 0.216667, 0.625],
	"RifleWalkBack": [1.279287, 0.308333, 0.85],
	"RifleRun": [1.837625, 0.216667, 0.791667],
	"RifleRunBack": [1.145754, 0.391667, 0.825],
	"RifleStrafeLeft": [1.111064, 0.258333, 0.766667],
	"RifleStrafeRight": [0.89983, 0.291667, 0.675],
}
const CombatSpatial = preload("res://scripts/spatial_profile.gd")
const EquipmentCatalog = preload("res://scripts/equipment_catalog.gd")
const DoctrineMetrics = preload("res://scripts/doctrine_metrics.gd")
const RoomDrill = preload("res://scripts/room_drill.gd")
const FormationDrill = preload("res://scripts/formation_drill.gd")
const TeamCommunication = preload("res://scripts/team_communication.gd")
const RoomControl = preload("res://scripts/room_control.gd")
const ObservedStatistics = preload("res://scripts/observed_statistics.gd")
const CQBSeed = preload("res://scripts/cqb_seed.gd")
const COMMANDS: Array[String] = ["MOVE", "FACE", "WAIT", "OPEN_DOOR", "KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "OPEN_AND_FLASH", "PEEK_CAMERA", "SWITCH_WEAPON", "RELOAD", "THROW_STUN", "THROW_SMOKE", "THROW_FRAG", "WAIT_FOR_SIGNAL", "SECURE_CIVILIAN", "ARREST", "CANCEL_PENDING"]
const DOOR_COMMANDS: Array[String] = ["OPEN_DOOR", "KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "OPEN_AND_FLASH", "PEEK_CAMERA"]
const OPEN_COMMANDS: Array[String] = ["OPEN_DOOR", "KICK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "OPEN_AND_FLASH"]
const FINISHED: Array[String] = ["SUCCEEDED", "CANCELLED"]
## RD (plan 2-5): the web event log previously showed the raw command enum
## next to the Korean prefix (e.g. "문 처리 · KICK_DOOR"). This supplies a
## human label matching web/app.js's commandNames, while `kind` in the event
## extra payload below keeps the stable enum code so the web can translate
## independently when settings.language === 'en'.
const DOOR_ACTION_LABELS: Dictionary = {"OPEN_DOOR": "조용히 열기", "KICK_DOOR": "문 차기", "PEEK_DOOR": "들여다보기", "BREACH_DOOR": "문 파괴 장약", "SHOTGUN_BREACH": "산탄총 브리칭", "OPEN_AND_FLASH": "문 열고 섬광탄", "PEEK_CAMERA": "문 아래 카메라"}
const AUTO_SURRENDER_ENABLED: bool = true
const BREACH_SAFE_DISTANCE: float = 2.0
const DOOR_READY_SECONDS: float = 8.0
const AIM_HOLD_SECONDS: float = 0.65
const HIT_REACTION_SECONDS: float = 1.5
const PRESENTATION_TURN_SECONDS: float = 0.75
const WEAPONS: Dictionary = {
	"standard": {"ammo": 24, "damage": 44.0, "interval": 0.45, "accuracy": 0.97, "reload": 1.8, "range": 10.0},
	"light": {"ammo": 32, "damage": 32.0, "interval": 0.30, "accuracy": 0.95, "reload": 1.4, "range": 8.5},
	"shotgun": {"ammo": 8, "damage": 84.0, "interval": 0.9, "accuracy": 0.97, "reload": 2.4, "range": 5.0, "sound": 14.0},
	"suppressed": {"ammo": 18, "damage": 44.0, "interval": 0.45, "accuracy": 0.97, "reload": 2.2, "range": 10.0, "sound": 3.0}
}
const STATUS_REASONS: Dictionary = {"READY": "다음 명령을 기다리는 중", "IDLE": "대기 중", "PATROL": "정해진 경로로 이동 중", "STUNNED": "상태 효과가 끝날 때까지 대기 중", "INCAPACITATED": "행동할 수 없는 상태", "EMPTY": "탄약이 없습니다. 재장전 명령이 필요합니다", "HOLD_FIRE": "아군 또는 민간인이 사선에 있어 사격 보류", "REACTING": "관측한 대상에 반응 중", "ALERT": "현재 관측한 대상에 대응 중", "SUSPICIOUS": "마지막으로 확인한 구역을 주시 중", "TARGET": "반격하지 않는 퍼즐 표적", "RECOVERING": "섬광탄 기절 후 무기를 다시 준비하는 중", "SWITCHING": "무기 전환 중", "CAMERA": "정찰 카메라로 관측 중", "RELOADING": "재장전 중", "THROWING": "장비 사용 중", "SECURING": "민간인 확보 중", "OPENING": "담당 대원이 문을 조작하는 중", "AIMING": "대상을 식별하고 조준하는 중", "OUT_OF_AMMO": "탄창과 예비 탄약이 모두 소진되었습니다", "YIELDING": "팀원이 통과할 공간으로 비켜서는 중", "COVERING_RELOAD": "재장전하는 대원의 구역을 엄호 중"}
var mission: Dictionary = {}
var enemy_rules: Dictionary = MissionCatalog.NORMAL
var challenge: bool = false
var units: Array = []
var enemies: Array = []
var civilians: Array = []
var interactive_targets: Array = []
var _elevated_rooms: Array = []
var doors: Array = []
var time: float = 0.0
var tick: int = 0
var result: Dictionary = {}
var events: Array = []
var _record_events_enabled: bool = false
var _pending_record_events: Array = []
var _recovery_grid: AStarGrid2D
var _recovery_navigation: BreachNavigation
var _recovery_revision: int = -1
var _recovery_body_cells: Dictionary = {}
var _recovery_door_cells: Dictionary = {}
var _preview_batch_depth: int = 0
var _preview_dirty_units: Dictionary = {}
var nav: BreachNavigation = Navigation.new()
var pause_requested: bool = false
var pause_reason: String = ""
var pause_unit_id: String = ""
var auto_pause_man_down: bool = false
var room_control: RefCounted
var room_states: Dictionary = {}
var _room_exploration: Dictionary = {}
var _room_tick_origins: Dictionary = {}
var _room_busy_tick: Dictionary = {}
var _room_fired_tick: Dictionary = {}
var _room_contacts_tick: Array = []
var _room_drill_layouts: Dictionary = {}
var _room_registered: Dictionary = {}
var _room_active_entries: Dictionary = {}
var _room_stack_epochs: Dictionary = {}
var _man_down_handled: Dictionary = {}
var _reload_covers: Dictionary = {}
var command_failures: int = 0
var shots_fired: int = 0
var plan_revisions: int = 0
var stuns_used: int = 0
var reloads: int = 0
var hits_taken: int = 0
var units_deployed: int = 0
var first_alert_time: float = -1.0
var arrests: int = 0
var kills: int = 0
var unlawful_shots: int = 0
var breaches_used: int = 0
var smokes_used: int = 0
var _deployed: Dictionary = {}
var _smoke_zones: Array = []
var _known_flash_navigation: BreachNavigation
var _known_flash_doors: Array = []
var _known_flash_key: String = ""
var _broken_glass: Array = []
var _flash_projectiles: Array = []
var _frag_projectiles: Array = []
var _p5_active: bool = false
var observed_statistics: RefCounted = ObservedStatistics.new()
var civilian_damage: float = 0.0
var unit_damage: float = 0.0
var frags_used: int = 0
var _p5_initial_dead: Dictionary = {}
var _flash_door_barriers: Dictionary = {}
var _sequence: int = 0
var _command_sequence: int = 0
var _perception_time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Cosmetic/body-region sampling must not perturb accuracy or AI reaction RNG.
var _hit_region_rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Breaching and surrender decisions never consume the accuracy/reaction stream.
var _breach_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _surrender_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _reservations: Dictionary = {}
var _movement_door_queues: Dictionary = {}
var _movement_door_queue_ticks: Dictionary = {}
var _requests: Dictionary = {}
var _insert_resource_index: int = -1
var _sound_zones: Array = []
var _door_observations: Dictionary = {}
var _acoustic: RefCounted = AcousticModel.new()
var doctrine: RefCounted = DoctrineMetrics.new()
var _drill_sequence: int = 0
var _sync_waits: Dictionary = {}
var _sync_requests: Dictionary = {}
var _sync_sources: Dictionary = {}
var _sync_members: Dictionary = {}

func _initialize_cognition() -> void:
	_acoustic.build(mission, doors, nav)
	for entity: Dictionary in units + enemies:
		entity["awareness_state"] = "UNAWARE"
		entity["awareness_confidence"] = 0.0
		entity["observation_source"] = "none"
		entity["_sensory_memory"] = {}
		entity["_heard_memory"] = {}
		entity["_report_memory"] = {}
		entity["_sense_updated_at"] = -0.1
		entity["_footstep_distance"] = float(entity.get("travel_distance", 0.0))
		entity["_alert_level"] = 0.0
		entity["_alert_updated_at"] = time
		entity["_alert_repetitions"] = 0
	for civilian: Dictionary in civilians:
		civilian["_fear"] = 0.0
		civilian["_fear_updated_at"] = time
		civilian["_panic_pause_until"] = 0.0
		civilian["_panic_origin"] = []
		civilian["_panic_recheck_at"] = 0.0
		civilian["_footstep_distance"] = float(civilian.get("travel_distance", 0.0))

func _footstep_contact_count(clip: String, distance: float, actor: Dictionary) -> int:
	var cadence: Array = FOOTSTEP_CADENCE.get(clip, FOOTSTEP_CADENCE.RifleWalk)
	var stride: float = float(cadence[0]) * (0.72 if actor.get("stance", "standing") == "crouched" else 1.0)
	var cycle: float = maxf(0.0, distance) / stride
	return floori(cycle - float(cadence[1]) + 0.000001) + floori(cycle - float(cadence[2]) + 0.000001) + 2

func _update_footstep_stimuli(dt: float) -> void:
	if dt <= 0.0: return
	for actor: Dictionary in units + enemies + civilians:
		if float(actor.get("hp", 0.0)) <= 0.0: continue
		var travelled: float = float(actor.get("travel_distance", 0.0))
		var last: float = float(actor.get("_footstep_distance", travelled))
		actor["_footstep_distance"] = travelled
		var clip: String = SensoryGait.base_clip(actor)
		var prior_clip: String = str(actor.get("_footstep_clip", clip))
		actor["_footstep_clip"] = clip
		if prior_clip != clip or travelled <= last or _footstep_contact_count(clip, travelled, actor) <= _footstep_contact_count(clip, last, actor): continue
		var strength: float = 3.1
		strength *= float({"careful": 0.65, "slow": 0.65, "fast": 1.3}.get(str(actor.get("movement_mode", "normal")), 1.0))
		if str(actor.get("stance", "standing")) == "crouched": strength *= 0.65
		for room: Dictionary in mission.get("rooms", []):
			if absf(float(room.get("base_height",0.0))-float(actor.get("base_height",0.0)))>0.0001: continue
			var rectangle := Rect2(_position(room) - Vector2(float(room.w), float(room.d)) * 0.5, Vector2(float(room.w), float(room.d)))
			if rectangle.has_point(_position(actor)):
				strength *= float({"carpet": 0.55, "wood": 1.15, "gravel": 1.35, "tile": 1.05}.get(str(room.get("floor_surface", "concrete")), 1.0))
				break
		var floor_height := float(actor.get("base_height",0.0))
		var context := {"source_floor":floor_height}
		var contact: Dictionary = _acoustic.wall_contact(_position(actor),floor_height)
		if not contact.is_empty():
			strength *= 1.5
			context["wall_contact"] = contact
		_emit_sound(_position(actor), strength, "발소리 감지", str(actor.get("kind", "civilian")),context)

func _sense_observations(observer: Dictionary, subjects: Array) -> Array:
	var previous_time: float = float(observer.get("_sense_updated_at", -0.1))
	var elapsed: float = clampf(time - previous_time, 0.0, 0.25)
	observer["_sense_updated_at"] = time
	var memories: Dictionary = observer.get("_sensory_memory", {})
	var seen_ids: Dictionary = {}
	var observations: Array = []
	for subject: Dictionary in subjects:
		if float(subject.get("hp", 0.0)) <= 0.0: continue
		var exposure: float = float(call("visual_exposure", observer, subject)) if has_method("visual_exposure") else (1.0 if can_see(observer, subject) else 0.0)
		if exposure <= 0.0: continue
		var id: String = str(subject.id)
		var previous: Dictionary = memories.get(id, {})
		var confidence: float = minf(1.0, float(previous.get("confidence", 0.0)) + exposure * elapsed * 3.0)
		if observer.get("kind", "") == "unit": confidence = maxf(confidence, 0.62)
		if observer.get("kind", "") == "enemy" and _door_ready_contact(observer, subject): confidence = maxf(confidence, 0.62)
		var observation: Dictionary = {"id": id, "position": _array_position(subject), "time": time, "confidence": confidence, "identified": confidence >= 0.62, "source": "sight", "exposure": exposure, "threat": 1.0 if float(subject.get("_cooldown", 0.0)) > 0.0 else 0.0}
		memories[id] = observation.duplicate(true)
		seen_ids[id] = true
		observations.append(observation)
	for id: String in memories.keys():
		if seen_ids.has(id): continue
		var memory: Dictionary = memories[id]
		memory["confidence"] = maxf(0.0, float(memory.get("confidence", 0.0)) - elapsed * 0.11)
		if float(memory.confidence) <= 0.0 or time - float(memory.time) > 20.0: memories.erase(id)
	observer["_sensory_memory"] = memories
	for key: String in ["_heard_memory", "_report_memory"]:
		var uncertain: Dictionary = observer.get(key, {})
		if not uncertain.is_empty():
			uncertain["confidence"] = maxf(0.0, float(uncertain.get("confidence", 0.0)) - elapsed * 0.06)
			if float(uncertain.confidence) <= 0.0: observer[key] = {}
	observations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: float = _observation_score(observer, a)
		var sb: float = _observation_score(observer, b)
		return str(a.id) < str(b.id) if is_equal_approx(sa, sb) else sa > sb)
	observer["_observed"] = observations
	if not observations.is_empty():
		var chosen: Dictionary = observations[0]
		observer["awareness_confidence"] = float(chosen.confidence)
		observer["awareness_state"] = "IDENTIFIED" if bool(chosen.identified) else "DETECTED"
		observer["observation_source"] = "sight"
		if str(observer.get("_target", "")) != str(chosen.id):
			var ready_contact: bool = observer.get("kind", "") == "enemy" and _door_ready_contact(observer, _find(subjects, str(chosen.id)))
			observer["_reaction"] = _rng.randf_range(0.10, 0.15) if ready_contact else (_rng.randf_range(_enemy_combat_stat(observer, "reaction_min"), _enemy_combat_stat(observer, "reaction_max")) if str(observer.kind) == "enemy" else 0.0)
			observer["_reaction"] += 0.12 if float(observer.get("suppressed", 0.0)) > 0.0 else 0.0
		if observer.get("kind", "") == "enemy" and bool(observer.get("door_ready", false)):
			# First visual contact ends portal preparation, even before identity
			# confidence reaches the firing threshold. Only an already completed
			# door aim may survive that transition.
			_remember_aim(observer, _find(subjects, str(chosen.id)))
		observer["_target"] = chosen.id
	elif not memories.is_empty() or not observer.get("_heard_memory", {}).is_empty() or not observer.get("_report_memory", {}).is_empty():
		var strongest: float = 0.0
		for memory: Dictionary in memories.values(): strongest = maxf(strongest, float(memory.confidence))
		var source: String = "sight"
		for key: String in ["_heard_memory", "_report_memory"]:
			var uncertain: Dictionary = observer.get(key, {})
			if float(uncertain.get("confidence", 0.0)) > strongest:
				strongest = float(uncertain.confidence)
				source = "sound" if key == "_heard_memory" else "report"
		observer["awareness_confidence"] = strongest
		observer["awareness_state"] = "TRACKING" if source == "sight" else "SUSPICIOUS"
		observer["observation_source"] = source
		observer["_target"] = ""
	else:
		observer["_target"] = ""
		observer["awareness_confidence"] = maxf(0.0, float(observer.get("awareness_confidence", 0.0)) - elapsed * 0.11)
		if float(observer.awareness_confidence) < 0.05:
			observer["awareness_state"] = "UNAWARE"
			observer["observation_source"] = "none"
	return observations

func _observation_score(observer: Dictionary, observation: Dictionary) -> float:
	var distance: float = _position(observer).distance_to(_point(observation.position))
	var retention: float = 0.6 if str(observer.get("_target", "")) == str(observation.id) else 0.0
	return float(observation.confidence) * 2.0 + (1.0 if bool(observation.identified) else 0.0) + retention + float(observation.get("threat", 0.0)) * 0.75 - distance * 0.08

func observation_ready(observer: Dictionary, subject: Dictionary) -> bool:
	if float(observer.get("_reaction", 0.0)) > 0.0: return false
	for observation: Dictionary in observer.get("_observed", []):
		if str(observation.id) == str(subject.get("id", "")):
			return bool(observation.get("identified", false)) and time - float(observation.get("time", -100.0)) <= 0.25
	return false

func load_mission(data: Dictionary) -> void:
	if not bool(data.get("_modifiers_applied", false)) and not data.get("modifiers", []).is_empty():
		data = MissionCatalog.apply_modifiers(data)
	if CQBSeed.is_mission(str(data.get("id", ""))): data = CQBSeed.materialize(data)
	mission = data.duplicate(true)
	mission.erase("_modifiers_applied")
	_p5_active = int(data.get("schema_version", 1)) >= 6 or data.has("roe")
	for source: Dictionary in _configured_units(data):
		if int(EquipmentCatalog.resolve_loadout(source).equipment.get("frag", 0)) > 0: _p5_active = true
	observed_statistics.reset(mission)
	_p5_initial_dead.clear()
	for actor: Dictionary in data.get("enemies", []) + data.get("civilians", []):
		if float(actor.get("hp", 72.0)) <= 0.0: _p5_initial_dead[str(actor.id)] = true
	civilian_damage = 0.0
	unit_damage = 0.0
	frags_used = 0
	_frag_projectiles.clear()
	challenge = bool(data.get("challenge", false)) or str(data.get("difficulty", "")) == "challenge" or MissionCatalog.CHALLENGE_IDS.has(str(data.get("id", "")))
	enemy_rules = MissionCatalog.rules_for(data)
	units.clear()
	enemies.clear()
	civilians.clear()
	interactive_targets.clear()
	_elevated_rooms.clear()
	if int(data.get("schema_version", 1)) >= 2:
		for room: Dictionary in data.get("rooms", []):
			if float(room.get("base_height", 0.0)) > 0.0: _elevated_rooms.append(room)
	doors.clear()
	events.clear()
	_record_events_enabled = false
	_pending_record_events.clear()
	_recovery_grid = null
	_recovery_navigation = null
	_recovery_body_cells.clear()
	_recovery_door_cells.clear()
	_preview_batch_depth = 0
	_preview_dirty_units.clear()
	result = {}
	doctrine.reset(mission)
	time = 0.0
	tick = 0
	_sequence = 0
	_command_sequence = 0
	_drill_sequence = 0
	_sync_waits.clear()
	_sync_requests.clear()
	_sync_sources.clear()
	_sync_members.clear()
	command_failures = 0
	shots_fired = 0
	plan_revisions = 0
	stuns_used = 0
	reloads = 0
	hits_taken = 0
	units_deployed = 0
	first_alert_time = -1.0
	arrests = 0
	kills = 0
	unlawful_shots = 0
	breaches_used = 0
	smokes_used = 0
	_deployed.clear()
	_smoke_zones.clear()
	_flash_projectiles.clear()
	_broken_glass.clear()
	_known_flash_navigation = null
	_known_flash_doors.clear()
	_known_flash_key = ""
	_flash_door_barriers.clear()
	pause_requested = false
	pause_reason = ""
	pause_unit_id = ""
	room_control = RoomControl.new()
	room_control.reset(mission)
	room_states = room_control.room_states
	_room_exploration.clear()
	_room_tick_origins.clear()
	_room_busy_tick.clear()
	_room_fired_tick.clear()
	_room_contacts_tick.clear()
	_room_drill_layouts.clear()
	_room_registered.clear()
	_room_active_entries.clear()
	_room_stack_epochs.clear()
	_man_down_handled.clear()
	_reload_covers.clear()
	_initialize_room_exploration()
	_perception_time = 0.0
	_reservations.clear()
	_movement_door_queues.clear()
	_movement_door_queue_ticks.clear()
	_requests.clear()
	_insert_resource_index = -1
	_sound_zones.clear()
	_door_observations.clear()
	_rng.seed = int(data.get("seed", 42))
	_hit_region_rng.seed = int(data.get("seed", 42)) ^ 0x5F356495
	_breach_rng.seed = int(data.get("seed", 42)) ^ 0x49B37A21
	_surrender_rng.seed = int(data.get("seed", 42)) ^ 0x6C8E9CF5
	for source: Dictionary in _configured_units(data):
		var unit := _make_entity(source, "unit")
		units.append(unit)
		if float(unit.hp) <= 0.0: _man_down_handled[str(unit.id)] = true
	for source: Dictionary in data.get("enemies", []):
		var spawn: Dictionary = source.duplicate(true)
		if int(data.get("seed", 42)) != int(data.get("default_seed", data.get("seed", 42))) and not source.get("spawns", []).is_empty():
			var chosen: Dictionary = source.spawns[_rng.randi_range(0, source.spawns.size() - 1)]
			for key: String in chosen:
				spawn[key] = chosen[key]
		spawn.erase("spawns")
		enemies.append(_make_entity(spawn, "enemy"))
	for source: Dictionary in data.get("civilians", []):
		var civilian: Dictionary = _make_entity(source, "civilian")
		civilian["secured"] = bool(source.get("secured", false))
		civilian["visible"] = false
		civilians.append(civilian)
	for source: Dictionary in data.get("interactive_targets", []):
		var target: Dictionary = source.duplicate(true)
		target["progress"] = 0.0
		target["completed"] = false
		interactive_targets.append(target)
	for source: Dictionary in data.get("doors", []):
		var door: Dictionary = source.duplicate(true)
		door["state"] = str(source.get("state", "CLOSED"))
		if int(data.get("seed", 42)) != int(data.get("default_seed", data.get("seed", 42))) and not source.get("initial_states", []).is_empty():
			door["state"] = str(source.initial_states[_rng.randi_range(0, source.initial_states.size() - 1)])
		door.erase("initial_states")
		door["progress"] = float(source.get("progress", 1.0 if door["state"] == "OPEN" else (0.52 if door["state"] == "AJAR" else 0.0)))
		door["hinge_side"] = float(source.get("hinge_side", -1.0))
		door["locked"] = bool(source.get("locked", false))
		door["hp"] = float(source.get("hp", source.get("durability", 100.0)))
		door["destroyed"] = bool(source.get("destroyed", false)) or door["state"] == "DESTROYED"
		if door["destroyed"]:
			door["state"] = "OPEN"
			door["progress"] = 1.0
			door["locked"] = false
			door["hp"] = 0.0
		door["owner_id"] = ""
		door["owner_command_id"] = ""
		door["blocked"] = false
		door["reason"] = ""
		door["swing_sign"] = float(source.get("swing_sign", -1.0))
		doors.append(door)
	nav.build(mission, doors)
	for actor: Dictionary in units + enemies + civilians:
		_refresh_weapon_state(actor)
	_initialize_tactical_entities()
	_initialize_cognition()
	_update_perception()
	doctrine.update(self, 0.0)
	_event("MISSION_START", str(mission.get("title", "작전")) + " · 계획을 수립하세요")

func _make_entity(source: Dictionary, kind: String) -> Dictionary:
	var entity: Dictionary = source.duplicate(true)
	entity["id"] = str(source.get("id", kind + str(units.size() + enemies.size())))
	entity["name"] = str(source.get("name", entity["id"].to_upper()))
	entity["kind"] = kind
	entity["x"] = float(source.get("x", 1.0))
	entity["z"] = float(source.get("z", 1.0))
	if not _elevated_rooms.is_empty():
		entity["base_height"] = CombatSpatial.floor_base_at(_elevated_rooms, Vector2(float(entity.x), float(entity.z)))
	entity["facing"] = float(source.get("facing", -PI * 0.5))
	# Presentation metadata is independent of authoritative FOV / shooting facing.
	entity["aim_facing"] = entity["facing"]
	entity["move_facing"] = entity["facing"]
	entity["travel_distance"] = 0.0
	entity["turn_started_at"] = 0.0
	entity["turn_delta"] = 0.0
	entity["_turn_last_aim"] = entity["facing"]
	entity["_turn_last_travel"] = 0.0
	entity["_aim_position"] = []
	entity["_aim_target"] = ""
	entity["_aim_observed_at"] = -100.0
	entity["hp"] = float(source.get("hp", 100.0 if kind != "enemy" else 72.0))
	entity["max_hp"] = entity["hp"]
	var weapon: String = str(source.get("weapon", "standard"))
	if not WEAPONS.has(weapon):
		weapon = "standard"
	entity["weapon"] = weapon
	entity["max_ammo"] = int(WEAPONS[weapon]["ammo"])
	entity["ammo"] = int(source.get("ammo", entity["max_ammo"]))
	entity["stuns"] = int(source.get("stuns", 2 if kind == "unit" else 0))
	entity["smokes"] = int(source.get("smokes", 0))
	if _p5_active and kind == "unit": entity["frags"] = 0
	entity["breaches"] = int(source.get("breaches", 0))
	entity["_peek_remaining"] = 0.0
	entity["stunned"] = 0.0
	entity["status"] = "IDLE"
	entity["status_reason"] = ""
	entity["commands"] = []
	entity["vision_range"] = float(source.get("vision_range", 10.0 if kind == "unit" else 8.0))
	entity["fov"] = float(source.get("fov", 110.0 if kind == "unit" else 95.0))
	entity["facing_locked"] = false
	entity["facing_persistent"] = false
	entity["visible"] = kind == "unit"
	entity["_cooldown"] = 0.0
	entity["_enemy_reload"] = 0.0
	entity["_reaction"] = 0.0
	entity["_target"] = ""
	entity["_observed"] = []
	entity["_last_known"] = []
	entity["_last_known_time"] = -100.0
	entity["_ai_state"] = "PATROL" if source.get("patrol", []).size() > 1 else "IDLE"
	entity["_patrol_index"] = 0
	entity["_ai_path"] = []
	entity["_ai_cursor"] = 0
	entity["_ai_revision"] = -1
	entity["velocity_x"] = 0.0
	entity["velocity_z"] = 0.0
	entity["hold_position"] = bool(source.get("hold_position", false))
	if kind == "unit":
		entity["sector"] = {}
		var gear: Dictionary = EquipmentCatalog.resolve_loadout(source)
		for field: String in ["sidearm", "armor", "helmet", "attachments", "appearance", "preset"]:
			entity[field] = gear[field]
		entity["_loadout"] = gear
		entity["_gear_stats"] = EquipmentCatalog.loadout_stats(gear)
		var primary_stats: Dictionary = EquipmentCatalog.weapon_stats(weapon, entity.attachments)
		entity["_primary_stats"] = primary_stats
		entity["_secondary_stats"] = EquipmentCatalog.weapon_stats(str(gear.sidearm)) if str(gear.sidearm) != "none" else {}
		entity["max_ammo"] = int(primary_stats.ammo)
		entity["ammo"] = int(source.get("ammo", entity.max_ammo))
		entity["cameras"] = int(source.get("cameras", gear.get("equipment", {}).get("probe_c1", 0)))
		if _p5_active: entity["frags"] = int(gear.get("equipment", {}).get("frag", 0))
		if source.has("equipment"):
			entity["stuns"] = int(source.get("stuns", gear.equipment.get("stun", 0)))
			entity["smokes"] = int(source.get("smokes", gear.equipment.get("smoke", 0)))
			entity["breaches"] = int(source.get("breaches", gear.equipment.get("breach", 0)))
	else:
		entity["sidearm"] = "none"
		entity["armor"] = "none"
		entity["helmet"] = "none"
		entity["attachments"] = []
	entity["active_weapon"] = "primary"
	entity["current_weapon"] = weapon
	entity["flash_recover_remaining"] = 0.0
	entity["camera_remaining"] = 0.0
	entity["camera_observations"] = []
	_initialize_combat_state(entity, source)
	entity["primary_ammo"] = entity.ammo
	entity["primary_reserve_ammo"] = entity.reserve_ammo
	var secondary: Dictionary = EquipmentCatalog.weapon_stats(str(entity.sidearm)) if str(entity.sidearm) != "none" else {}
	var supply_scale: float = 0.5 if kind == "unit" and mission.get("modifiers", []).has("low_ammo") else 1.0
	entity["secondary_ammo"] = int(source.get("secondary_ammo", floori(float(secondary.get("ammo", 0)) * supply_scale)))
	entity["secondary_reserve_ammo"] = int(source.get("secondary_reserve_ammo", floori(float(secondary.get("ammo", 0)) * 3.0 * supply_scale)))
	return entity

func _unit_covering_reload(unit: Dictionary) -> bool:
	return not str(unit.get("_reload_cover_for", "")).is_empty()

func _begin_reload_cover(reloader: Dictionary) -> void:
	reloader["_reload_call_pending"] = true
	var cover: Dictionary = {}
	var nearest := INF
	for candidate: Dictionary in units:
		if candidate.id == reloader.id or not _can_act(candidate) or _unit_covering_reload(candidate) or int(candidate.get("ammo",0)) <= 0 or _command_hands_busy(candidate): continue
		if not TeamCommunication.can_receive(_communication_context(reloader),_communication_context(candidate),nav,TeamCommunication.discipline(mission),_smoke_zones): continue
		var active := _active(candidate)
		if active.get("type", "") in ["RELOAD","SWITCH_WEAPON","THROW_STUN","THROW_SMOKE","THROW_FRAG","INTERACT"]: continue
		var distance := _position(candidate).distance_squared_to(_position(reloader))
		if distance < nearest or (is_equal_approx(distance,nearest) and (cover.is_empty() or str(candidate.id)<str(cover.id))):
			nearest = distance
			cover = candidate
	var borrowed: Dictionary = reloader.get("sector", {}).duplicate(true)
	if borrowed.is_empty(): borrowed = {"start":wrapf(float(reloader.facing)-deg_to_rad(40),-PI,PI),"end":wrapf(float(reloader.facing)+deg_to_rad(40),-PI,PI),"until":time+float(reloader.reload_duration)}
	var lease := {"cover_unit_id":str(cover.get("id","")),"sector":borrowed,"facing":float(reloader.facing)}
	if not cover.is_empty():
		lease["previous"] = {"facing":cover.facing,"facing_locked":cover.facing_locked,"facing_persistent":cover.facing_persistent,"sector":cover.get("sector",{}).duplicate(true)}
		var command := _active(cover)
		lease["command_id"] = str(command.get("id",""))
		lease["command_args"] = command.get("args",{}).duplicate(true)
		cover["_reload_cover_for"] = str(reloader.id)
	_reload_covers[str(reloader.id)] = lease
	_emit_room_call("CALL_RELOADING",reloader,room_control.room_at(_position(reloader),float(reloader.get("base_height",0.0))),str(cover.get("id","")))
	_update_reload_covers()

func _finish_reload_cover(reloader: Dictionary, completed: bool = true) -> void:
	var lease: Dictionary = _reload_covers.get(str(reloader.id),{})
	var cover := _find(units,str(lease.get("cover_unit_id","")))
	if not cover.is_empty() and str(cover.get("_reload_cover_for","")) == str(reloader.id):
		cover.erase("_reload_cover_for")
		for key: String in lease.get("previous",{}): cover[key] = lease.previous[key]
		_refresh_weapon_state(cover)
	_reload_covers.erase(str(reloader.id))
	# A coverer's death or an explicit plan edit can end the temporary lease
	# before the real reload finishes. Its completion call still belongs to
	# the reloader and is emitted exactly once for that actual reload.
	if completed and bool(reloader.get("_reload_call_pending",false)):
		reloader.erase("_reload_call_pending")
		_emit_room_call("CALL_GUN_UP",reloader,room_control.room_at(_position(reloader),float(reloader.get("base_height",0.0))),str(lease.get("cover_unit_id","")))

func _update_reload_covers() -> void:
	for id: String in _reload_covers.keys():
		var reloader := _find(units,id)
		var lease: Dictionary = _reload_covers[id]
		var cover := _find(units,str(lease.get("cover_unit_id","")))
		if reloader.is_empty():
			_reload_covers.erase(id)
			continue
		var active := _active(reloader)
		if not _can_act(reloader) or float(reloader.get("reload_remaining",0.0)) <= 0.0 or active.get("type","") != "RELOAD":
			_finish_reload_cover(reloader,false)
			continue
		if cover.is_empty(): continue
		var command := _active(cover)
		if not _can_act(cover) or str(command.get("id","")) != str(lease.get("command_id","")) or command.get("args",{}) != lease.get("command_args",{}):
			_finish_reload_cover(reloader,false)
			continue
		cover["sector"] = lease.sector.duplicate(true)
		cover.sector["until"] = time+float(reloader.reload_remaining)
		cover["facing"] = float(lease.facing)
		cover["facing_locked"] = true
		cover["facing_persistent"] = true
		cover["status"] = "COVERING_RELOAD"
		cover["_movement_speed"] = 0.0
		cover["velocity_x"] = 0.0
		cover["velocity_z"] = 0.0
		_room_busy_tick[str(cover.id)] = true

func _update_man_down() -> void:
	for unit: Dictionary in units:
		if float(unit.hp)>0.0 or _man_down_handled.has(str(unit.id)): continue
		_man_down_handled[str(unit.id)] = true
		var affected: Dictionary = {}
		var loss_room: String = room_control.room_at(_position(unit),float(unit.get("base_height",0.0)))
		for command: Dictionary in unit.commands:
			var drill: Dictionary = command.args.get("drill",{})
			var base := str(drill.get("sync_id",""))
			if base.is_empty(): continue
			if str(drill.get("stage","")) == "door" and command.state == "CANCELLED" and str(command.get("reason","")) == "대원 행동 불능" and not _room_registered.has(base):
				_halt_room_entry(base,"문 조작 대원이 행동 불능이 되어 진입을 안전하게 중단했습니다")
			if not _room_registered.has(base): continue
			var target_room := str(_room_registered[base].room_id)
			if str(_room_active_entries.get(target_room,"")) != base: continue
			var running := false
			for survivor: Dictionary in units:
				if float(survivor.hp)<=0.0: continue
				for next: Dictionary in survivor.commands:
					if not FINISHED.has(str(next.state)) and str(next.args.get("drill",{}).get("sync_id","")) == base: running = true
			if loss_room == target_room or running: affected[base] = true
		for base: String in affected:
			_reform_room_entry(base)
		_emit_room_call("CALL_MAN_DOWN",unit,room_control.room_at(_position(unit),float(unit.get("base_height",0.0))))
		if auto_pause_man_down and pause_reason != "command_failure":
			pause_requested = true
			pause_reason = "man_down"
			pause_unit_id = str(unit.id)

func _halt_room_entry(base: String, reason: String) -> void:
	# An unfinished door action may already own a charge, a shotgun round or
	# a moving leaf. A casualty cannot safely clone it onto another operator.
	for unit: Dictionary in units:
		if float(unit.hp) <= 0.0: continue
		var command := _active(unit)
		if command.is_empty() or str(command.args.get("drill",{}).get("sync_id","")) != base:
			command = {}
			for pending: Dictionary in unit.commands:
				if not FINISHED.has(str(pending.state)) and str(pending.args.get("drill",{}).get("sync_id","")) == base:
					command = pending
					break
		if not command.is_empty() and str(command.args.get("drill",{}).get("sync_id","")) == base:
			_fail(unit,command,reason)
			return

func _reform_room_entry(base: String) -> void:
	# Casualties never duplicate a door action or a consumed charge/round.
	# Only MOVE/FACE nodes are replaced; signal contracts retain their identity.
	var contract: Dictionary = _room_registered.get(base,{})
	var layout: Dictionary = _room_drill_layouts.get(base,{})
	if contract.is_empty() or layout.is_empty(): return
	var order: Array = []
	var positions: Dictionary = {}
	for slot: Dictionary in layout.get("slots",[]):
		var unit := _find(units,str(slot.unit_id))
		if unit.is_empty() or float(unit.hp)<=0.0: continue
		order.append(str(unit.id))
		positions[str(unit.id)] = _array_position(unit)
	if order.size()!=3: return
	var answer: Dictionary = RoomDrill.recalculate_three(_drill_geometry(str(contract.door_id)),layout,order,positions,{})
	if not bool(answer.get("ok",false)):
		_halt_room_entry(base,"사상자 발생 후 진입 지점을 안전하게 재편성할 수 없습니다")
		return
	var staged: Dictionary = {}
	var targets: Dictionary = {}
	var next_sequence := _command_sequence
	for target: Dictionary in answer.targets:
		var unit := _find(units,str(target.unit_id))
		var queue: Array = unit.commands.duplicate(true)
		var insertion := -1
		for index: int in range(queue.size()):
			var command: Dictionary = queue[index]
			var drill: Dictionary = command.args.get("drill",{})
			if str(drill.get("sync_id",""))!=base or FINISHED.has(str(command.state)): continue
			if command.type not in ["MOVE","FACE","WAIT_FOR_SIGNAL"]: continue
			if command.type == "WAIT_FOR_SIGNAL" or str(drill.get("stage","")) == "go_long": drill["order"] = int(target.order)
			if command.type in ["MOVE","FACE"] and str(drill.get("stage","")) in ["entry","domination","guard"]:
				if insertion<0: insertion = index
				command["state"] = "CANCELLED"
				command["reason"] = "사상자 발생 후 진입 재편성"
				command["completed_tick"] = tick
		if insertion<0:
			insertion = queue.size()
			for index: int in range(queue.size()):
				if not FINISHED.has(str(queue[index].state)):
					insertion = index
					break
		var nodes: Array = []
		var checkpoints: Array = target.get("entry_waypoints",[])
		for point: Array in checkpoints: nodes.append({"type":"MOVE","stage":"entry","target":point})
		nodes.append({"type":"MOVE","stage":"domination" if bool(target.entry) else "guard","target":target.target})
		nodes.append({"type":"FACE","stage":"domination" if bool(target.entry) else "guard","target":target.face_target})
		var replacements: Array = []
		for node: Dictionary in nodes:
			next_sequence += 1
			var args := {"target":node.target.duplicate(),"sector":_drill_sector(target.sector),"drill":{"sync_id":base,"door_id":str(contract.door_id),"room_id":str(contract.room_id),"order":int(target.order),"stage":str(node.stage)}}
			if node.type == "FACE": args["persistent"] = false
			args = JSON.parse_string(JSON.stringify(args))
			replacements.append({"id":"%s-%04d"%[str(unit.id),next_sequence],"sequence":next_sequence,"owner_id":str(unit.id),"type":str(node.type),"args":args,"state":"PENDING","reason":"","remaining":0.0,"issued_tick":tick,"path":[],"path_cursor":0,"conditional":false,"_elapsed":0.0,"_blocked":0.0,"_revision":-1,"_started":false})
		for index: int in range(replacements.size()): queue.insert(insertion+index,replacements[index])
		var unfinished := 0
		for command: Dictionary in queue:
			if not FINISHED.has(str(command.state)): unfinished+=1
		if unfinished>32:
			_halt_room_entry(base,"사상자 발생 후 진입 지점을 안전하게 재편성할 수 없습니다")
			return
		staged[str(unit.id)] = queue
		if bool(target.entry): targets[str(unit.id)] = target.target.duplicate()
	for id: String in staged:
		var unit := _find(units,id)
		unit.commands = staged[id]
		unit["_movement_detour"] = []
		unit["_movement_speed"] = 0.0
		_refresh_preview(unit)
	_command_sequence = next_sequence
	contract["participants"] = targets.keys()
	contract["targets"] = targets
	room_control.register_entry(contract)
	_room_registered[base] = contract

func _initialize_room_exploration() -> void:
	for room: Dictionary in mission.get("rooms", []):
		var rect := Rect2(_position(room) - Vector2(float(room.w), float(room.d)) * 0.5, Vector2(float(room.w), float(room.d)))
		var spacing := maxf(1.0, sqrt(rect.get_area() / 1024.0))
		var points: Array = []
		var z := rect.position.y + spacing * 0.5
		while z < rect.end.y:
			var x := rect.position.x + spacing * 0.5
			while x < rect.end.x:
				points.append([x,z])
				x += spacing
			z += spacing
		if points.is_empty(): points.append(_array_position(room))
		_room_exploration[str(room.id)] = {"rect":rect,"points":points,"seen":{}}

func _room_point_seen(unit: Dictionary, point: Vector2, floor_height: float) -> bool:
	if not _can_act(unit) or absf(float(unit.get("base_height", 0.0)) - floor_height) > 0.01: return false
	# A unit sees the floor immediately beneath it even at a zero cone vector.
	if _position(unit).distance_squared_to(point) <= 0.02: return true
	return can_see(unit, {"x":point.x,"z":point.y})

func _room_observation() -> Dictionary:
	var observed: Dictionary = {}
	for room: Dictionary in mission.get("rooms", []):
		var id := str(room.id)
		var exploration: Dictionary = _room_exploration[id]
		var rect: Rect2 = exploration.rect
		var current := false
		var center := false
		var floor_height := float(room.get("base_height", 0.0))
		var candidates: Array = []
		for unit: Dictionary in units:
			if not _can_act(unit) or absf(float(unit.get("base_height", 0.0)) - floor_height) > 0.01: continue
			var distance := effective_vision_range(unit)
			if not rect.intersects(Rect2(_position(unit) - Vector2.ONE * distance, Vector2.ONE * distance * 2.0)): continue
			candidates.append({"unit": unit, "distance_squared": distance * distance})
			if not center and _room_point_seen(unit, _position(room), floor_height): center = true
			if room_control.room_at(_position(unit), floor_height) == id: current = true
			for index: int in range(exploration.points.size()):
				if exploration.seen.has(index): continue
				var point := _point(exploration.points[index])
				if _position(unit).distance_squared_to(point) > distance * distance: continue
				if _room_point_seen(unit, point, floor_height):
					exploration.seen[index] = true
					current = true
		# Seen samples still need fresh evidence when no actual presence or new
		# visible sample established current observation. Historical exploration
		# alone cannot reveal a room through a closed leaf, smoke, or turned FOV.
		# Center remains a separate fresh query; it need not be a grid sample.
		if not current:
			for candidate: Dictionary in candidates:
				for index: int in exploration.seen:
					var point := _point(exploration.points[index])
					if _position(candidate.unit).distance_squared_to(point) > float(candidate.distance_squared): continue
					if _room_point_seen(candidate.unit, point, floor_height):
						current = true
						break
				if current: break
		observed[id] = {"fraction":float(exploration.seen.size()) / float(exploration.points.size()),"center":center,"current":current}
	return observed

func _primary_drill_targets(base: String) -> Dictionary:
	var targets: Dictionary = {}
	for unit: Dictionary in units:
		for command: Dictionary in unit.commands:
			var drill: Dictionary = command.args.get("drill", {})
			if command.type != "MOVE" or str(drill.get("sync_id", "")) != base or str(drill.get("stage", "")) not in ["entry","domination"]: continue
			if command.state == "CANCELLED" and float(unit.hp) > 0.0: continue
			targets[str(unit.id)] = command.args.target.duplicate()
	return targets

func _register_room_entry(base: String, door_id: String, room_id: String) -> void:
	var targets := _primary_drill_targets(base)
	var participants: Array = targets.keys()
	var contract := {"sync_id":base,"door_id":door_id,"room_id":room_id,"participants":participants,"targets":targets}
	_room_registered[base] = contract.duplicate(true)
	_room_active_entries[room_id] = base
	room_control.register_entry(contract)
	if not _room_drill_layouts.has(base):
		var ranked: Array = []
		var approaches: Dictionary = {}
		var method := "OPEN_DOOR"
		var operator_id := ""
		for unit: Dictionary in units:
			var rank := 0
			for command: Dictionary in unit.commands:
				var drill: Dictionary = command.args.get("drill",{})
				if str(drill.get("sync_id","")) != base: continue
				rank = int(drill.order)
				if command.type in OPEN_COMMANDS:
					method = str(command.type)
					operator_id = str(unit.id)
			if rank>0:
				ranked.append({"id":str(unit.id),"order":rank})
				approaches[str(unit.id)] = _array_position(unit)
			ranked.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return int(a.order)<int(b.order))
		var ids: Array = []
		for member: Dictionary in ranked: ids.append(str(member.id))
		if ids.size()>=2:
			var options := {"room_id":room_id,"method":method}
			if not operator_id.is_empty(): options["operator_id"] = operator_id
			var restored := RoomDrill.calculate(_drill_geometry(door_id),door_id,ids,approaches,options)
			if bool(restored.get("ok",false)): _room_drill_layouts[base] = restored
	var layout: Dictionary = _room_drill_layouts.get(base, {})
	for slot: Dictionary in layout.get("slots",[]):
		if targets.has(str(slot.unit_id)): slot["domination"] = targets[str(slot.unit_id)].duplicate()
		var member := _find(units,str(slot.unit_id))
		for command: Dictionary in member.get("commands",[]):
			var drill: Dictionary = command.args.get("drill",{})
			if command.type == "FACE" and str(drill.get("sync_id","")) == base and str(drill.get("stage","")) in ["domination","guard"]:
				slot["face_target"] = command.args.target.duplicate()
	# A non-operator can fall while the stack or door barrier is still active.
	# Keep the original four-person contract until this actual entry point,
	# then explicitly recalculate the three survivors. Merely omitting the
	# dead participant would falsely credit the old unmodified formation.
	if layout.get("slots",[]).size() == 4:
		var survivors := 0
		for slot: Dictionary in layout.slots:
			var member := _find(units,str(slot.unit_id))
			if not member.is_empty() and float(member.hp)>0.0: survivors += 1
		if survivors == 3: _reform_room_entry(base)
	if bool(layout.get("short_room", false)):
		var unit := _find(units, str(participants[0])) if not participants.is_empty() else {}
		if not unit.is_empty(): _emit_room_call("CALL_SHORT_ROOM", unit, room_id)

func _emit_room_call(kind: String, unit: Dictionary, room_id: String = "", cover_id: String = "") -> void:
	if unit.is_empty() or str(unit.get("kind", "")) != "unit": return
	var labels := {"CALL_CLEAR":"구역 통제", "CALL_ROOM_CLEAR":"방 정리 완료", "CALL_SHORT_ROOM":"짧은 방", "CALL_RELOADING":"재장전 · 엄호 인계", "CALL_GUN_UP":"재장전 완료 · 구역 복귀", "CALL_MAN_DOWN":"대원 행동 불능 · 진입 재편성"}
	var extra := {"unit_id":str(unit.id),"observed":true}
	if not room_id.is_empty(): extra["room_id"] = room_id
	if not cover_id.is_empty(): extra["cover_unit_id"] = cover_id
	var sender := unit if _can_act(unit) else _call_witness(unit)
	if not sender.is_empty():
		var contexts: Array = []
		for receiver: Dictionary in units: contexts.append(_communication_context(receiver))
		var receipt: Dictionary = TeamCommunication.delivery(_communication_context(sender),contexts,nav,TeamCommunication.discipline(mission),_smoke_zones)
		var bundle := _communication_bundle(sender,receipt.receiver_unit_ids)
		for key: String in bundle: extra[key] = bundle[key]
		_emit_signal_sound(sender,bundle)
	_event(kind, str(unit.name) + " · " + str(labels.get(kind, kind)), _array_position(unit), [], extra)

func _communication_context(unit: Dictionary) -> Dictionary:
	if unit.is_empty(): return {}
	return {"id":str(unit.id),"kind":"unit","x":float(unit.x),"z":float(unit.z),"base_height":float(unit.get("base_height",0.0)),"facing":float(unit.facing),"fov":float(unit.get("fov",110.0)),"vision_range":float(unit.get("vision_range",10.0)),"effective_vision_range":effective_vision_range(unit),"stance":str(unit.get("stance","standing")),"body_height":CombatSpatial.body_height(unit),"eye_height":CombatSpatial.eye_height(unit)-float(unit.get("base_height",0.0)),"can_act":_can_act(unit)}

func _communication_bundle(sender: Dictionary, receivers: Array) -> Dictionary:
	var mode := TeamCommunication.discipline(mission)
	return {"signal_mode":mode,"source_unit_id":str(sender.id),"receiver_unit_ids":receivers.duplicate(),"signal_radius":6.0 if mode == "verbal" else 0.0}

func _emit_signal_sound(sender: Dictionary, bundle: Dictionary) -> void:
	if float(bundle.signal_radius) > 0.0: _emit_sound(_position(sender),float(bundle.signal_radius),"팀 신호 감지","unit",{"source_floor":float(sender.get("base_height",0.0))})

func _call_witness(subject: Dictionary) -> Dictionary:
	var witness: Dictionary = {}
	var nearest := INF
	for candidate: Dictionary in units:
		if not _can_act(candidate) or not _body_witness_sees(candidate,subject): continue
		var distance := _position(candidate).distance_squared_to(_position(subject))
		if distance < nearest or (is_equal_approx(distance,nearest) and (witness.is_empty() or str(candidate.id)<str(witness.id))):
			nearest = distance
			witness = candidate
	return witness

func _body_witness_sees(observer: Dictionary, subject: Dictionary) -> bool:
	if absf(float(observer.get("base_height",0.0))-float(subject.get("base_height",0.0))) > 0.0001: return false
	var origin := _position(observer)
	var destination := _position(subject)
	var offset := destination-origin
	if offset.length() > effective_vision_range(observer): return false
	if offset.length_squared() > 0.02 and absf(angle_difference(float(observer.facing),offset.angle())) > deg_to_rad(float(observer.get("fov",110.0)))*0.5: return false
	return not _smoke_blocks(origin,destination) and nav.sight_clear_height(origin,destination,CombatSpatial.eye_height(observer),CombatSpatial.eye_height(subject))

func _update_room_control(dt: float) -> void:
	var own: Array = []
	var hostile: Array = []
	var noncombatants: Array = []
	var contacts: Array = _room_contacts_tick.duplicate(true)
	var exits: Array = []
	for unit: Dictionary in units:
		var floor_height := float(unit.get("base_height", 0.0))
		var position := _position(unit)
		var origin: Vector2 = _point(_room_tick_origins.get(str(unit.id), _array_position(unit)))
		var stationary := origin.distance_squared_to(position) <= 0.000001
		var eligible := _can_act(unit) and stationary and not bool(_room_busy_tick.get(str(unit.id), false)) and not bool(_room_fired_tick.get(str(unit.id), false)) and not is_equal_approx(float(unit.get("_last_hit_time", -1.0)), time) and not _unit_covering_reload(unit)
		own.append({"id":str(unit.id),"position":_array_position(unit),"floor_height":floor_height,"alive":float(unit.hp)>0.0,"can_act":_can_act(unit),"search_eligible":eligible})
		var previous_room: String = room_control.room_at(origin, floor_height)
		if previous_room.is_empty() or previous_room == room_control.room_at(position, floor_height): continue
		for door: Dictionary in doors:
			var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
			var across := Vector2.RIGHT if door.get("axis", "x") == "x" else Vector2.DOWN
			var a := (origin - _position(door)).dot(normal)
			var b := (position - _position(door)).dot(normal)
			if a * b > 0.0 or absf(a - b) < 0.00001 or absf(float(door.get("base_height",0.0))-floor_height)>0.01: continue
			var crossing := origin.lerp(position, a / (a-b))
			if absf((crossing-_position(door)).dot(across)) <= DoorGeometry.width(door)*0.5: exits.append({"unit_id":str(unit.id),"room_id":previous_room,"door_id":str(door.id)})
	for enemy: Dictionary in enemies:
		var floor_height := float(enemy.get("base_height", 0.0))
		var id: String = room_control.room_at(_position(enemy),floor_height)
		hostile.append({"position":_array_position(enemy),"floor_height":floor_height,"room_id":id,"alive":float(enemy.hp)>0.0,"can_act":_can_act(enemy),"surrendered":bool(enemy.get("surrendered",false)),"arrested":bool(enemy.get("arrested",false))})
		# The 10 Hz visible flag can be stale. Only this tick's actual LOS is
		# evidence of the enemy's present room; floor visibility is insufficient.
		for unit: Dictionary in units:
			if _can_act(unit) and can_see(unit,enemy):
				if not id.is_empty(): contacts.append({"room_id":id})
				break
	for civilian: Dictionary in civilians:
		var floor_height := float(civilian.get("base_height", 0.0))
		noncombatants.append({"position":_array_position(civilian),"floor_height":floor_height,"room_id":room_control.room_at(_position(civilian),floor_height),"alive":float(civilian.hp)>0.0,"secured":bool(civilian.get("secured",false))})
	var transitions: Dictionary = room_control.tick({"tick":tick,"time":time,"dt":dt,"units":own,"enemies":hostile,"civilians":noncombatants,"observation":_room_observation(),"contacts":contacts,"exits":exits})
	room_states = room_control.room_states
	for transition: Dictionary in transitions.get("public_transitions", []):
		var state := str(transition.get("state", ""))
		if state not in ["DOMINATED","CLEAR"]: continue
		var room_id := str(transition.get("room_id", ""))
		var unit := _find(units,str(transition.get("unit_id", "")))
		if unit.is_empty():
			for candidate: Dictionary in units:
				if _can_act(candidate) and room_control.room_at(_position(candidate),float(candidate.get("base_height",0.0))) == room_id:
					unit = candidate
					break
		_emit_room_call("CALL_ROOM_CLEAR" if state == "CLEAR" else "CALL_CLEAR",unit,room_id)

func configure_team_settings(settings: Dictionary) -> Dictionary:
	for key: Variant in settings:
		if key != "auto_pause_man_down" or not settings[key] is bool:
			return {"ok":false, "reason":"팀 설정 값이 올바르지 않습니다", "message_key":"team.invalid_settings", "i18n_key":"team.invalid_settings"}
	if settings.has("auto_pause_man_down"): auto_pause_man_down = settings.auto_pause_man_down
	return {"ok":true}

func configure_unit(unit_id: String, settings: Dictionary) -> Dictionary:
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty() or float(unit.hp) <= 0.0 or not result.is_empty():
		return _rejected("행동 가능한 대원을 선택하세요")
	for key: Variant in settings:
		if key not in ["stance", "movement_mode", "hold_position"]:
			return _rejected("지원하지 않는 대원 설정입니다")
	if settings.has("stance") and settings.stance not in ["standing", "crouched"]:
		return _rejected("자세 설정이 올바르지 않습니다")
	if settings.has("movement_mode") and settings.movement_mode not in ["careful", "normal", "fast"]:
		return _rejected("이동 방식이 올바르지 않습니다")
	if settings.has("hold_position") and not settings.hold_position is bool:
		return _rejected("위치 유지 설정이 올바르지 않습니다")
	for key: String in settings:
		unit[key] = settings[key]
	unit["aim_progress"] = 0.0
	_refresh_weapon_state(unit)
	plan_revisions += 1
	_update_perception()
	return {"ok": true, "message": "대원 행동 방식을 설정했습니다"}

func unlock_facing(unit_id: String) -> bool:
	# The HUD toggle changes the current facing mode immediately, including paused
	# planning. A queued FACE remains a deliberate future waypoint instruction.
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty() or float(unit.hp) <= 0 or not result.is_empty(): return false
	unit.facing_locked = false
	unit.facing_persistent = false
	plan_revisions += 1
	return true

func issue(unit_id: String, type: String, args: Dictionary, append: bool = true) -> Dictionary:
	if not result.is_empty():
		return _rejected("종료된 작전에는 명령을 추가할 수 없습니다")
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty() or float(unit["hp"]) <= 0.0:
		return _rejected("행동 가능한 대원을 선택하세요")
	if not COMMANDS.has(type):
		return _rejected("지원하지 않는 명령입니다")
	var reason: String = _validate(type, args)
	if not reason.is_empty():
		return _rejected(reason)
	args = _canonical_args(type, args)
	var cached_request: String = str(args.get("request_id", ""))
	if not cached_request.is_empty() and _requests.has(unit_id + ":" + cached_request):
		return _requests[unit_id + ":" + cached_request].duplicate(true)
	if type == "WAIT_FOR_SIGNAL" and args.has("sync_id"):
		for other: Dictionary in units:
			if not append and str(other.id) == unit_id: continue
			for queued: Dictionary in other.commands:
				if queued.type == "WAIT_FOR_SIGNAL" and not FINISHED.has(str(queued.state)) and str(queued.args.get("sync_id", "")) == str(args.sync_id) and not _same_sync_contract(args, queued.args): return _rejected("드릴 대기 신호가 단계와 일치하지 않습니다")
	if type in ["THROW_STUN", "OPEN_AND_FLASH"]:
		if mission.get("modifiers", []).has("no_stun") or _available_stuns(unit, append) <= 0:
			return _rejected("예약분을 제외한 섬광탄이 없습니다")
	if type == "THROW_FRAG":
		var frag_options := {"append":append}
		if _insert_resource_index >= 0: frag_options["index"] = _insert_resource_index
		var frag_preview := frag_target_preview(unit_id, args.target, frag_options)
		if not bool(frag_preview.get("ok", false)): return frag_preview
	if type == "SWITCH_WEAPON" and str(args.get("slot", "secondary")) == "secondary" and str(unit.get("sidearm", "none")) == "none":
		return _rejected("보조무기를 장착하지 않았습니다")
	if type == "PEEK_CAMERA" and int(unit.get("cameras", 0)) <= 0:
		return _rejected("정찰 카메라를 장착하지 않았습니다")
	var resource_reason := _door_resource_reason(unit, type, args, append)
	if not resource_reason.is_empty(): return _rejected(resource_reason)
	if type == "OPEN_AND_FLASH":
		var prepared: Dictionary = _prepare_flash_plan(unit, args, append)
		if not bool(prepared.get("ok", false)): return _rejected(str(prepared.get("message", "유효한 섬광탄 계획이 필요합니다")))
		args = prepared.args
	elif DOOR_COMMANDS.has(type):
		var door: Dictionary = _find(doors, str(args.door_id))
		var projected: Dictionary = _project_movement_plan(unit, append)
		if not bool(projected.get("ok", false)): return _rejected(str(projected.get("message", "문까지 접근할 수 없습니다")))
		if door.state != "OPEN" and nav.approach(projected.origin, door, 0.85, projected.open).is_empty():
			return _rejected("문 앞까지 접근할 수 없습니다. 가까운 문부터 차례로 열도록 계획하세요. 기존 계획은 유지됩니다")
	if type == "CANCEL_PENDING":
		cancel_pending(unit_id)
		return {"ok": true, "message": "대기 명령을 취소했습니다"}
	var request_id: String = str(args.get("request_id", ""))
	if not request_id.is_empty() and _requests.has(unit_id + ":" + request_id):
		return _requests[unit_id + ":" + request_id].duplicate(true)
	var commands: Array = unit["commands"]
	var pending_count: int = 0
	for command: Dictionary in commands:
		if not FINISHED.has(str(command["state"])):
			pending_count += 1
	if append and pending_count >= 32:
		return _rejected("대원당 미완료 명령은 최대 32개입니다")
	if not append:
		_cancel_replaceable(unit)
	_prune_history(commands)
	_command_sequence += 1
	var command: Dictionary = {"id": "%s-%04d" % [unit_id, _command_sequence], "sequence": _command_sequence, "owner_id": unit_id, "type": type, "args": args.duplicate(true), "state": "PENDING", "reason": "", "remaining": 0.0, "issued_tick": tick, "path": [], "path_cursor": 0, "conditional": false, "_elapsed": 0.0, "_blocked": 0.0, "_revision": -1, "_started": false}
	commands.append(command)
	plan_revisions += 1
	_refresh_preview(unit)
	var response: Dictionary = {"ok": true, "message": "명령을 추가했습니다", "id": command["id"]}
	_add_breach_warning(response, type, args)
	if not request_id.is_empty():
		_requests[unit_id + ":" + request_id] = response.duplicate(true)
	return response

func _drill_rejected(key: String, message: String) -> Dictionary:
	return {"ok": false, "message": message, "message_key": key, "i18n_key": key}

func _drill_geometry(_door_id: String = "") -> Dictionary:
	var geometry: Dictionary = {}
	# A floor plan is known; live NPCs, seeded door changes and room states are not.
	for key: String in ["bounds", "schema_version", "walkable_areas", "rooms", "walls", "props", "doors"]:
		if mission.has(key): geometry[key] = mission[key].duplicate(true) if mission[key] is Array or mission[key] is Dictionary else mission[key]
	# A later entry must account for every leaf already observed on its route.
	# Unseen leaves keep the authored pose; never read the authoritative doors.
	for known: Dictionary in geometry.get("doors", []):
		var observed: Dictionary = _door_observations.get(str(known.id), {})
		for key: String in ["state", "progress", "destroyed", "hp", "locked", "hinge_side", "swing_sign"]:
			if observed.has(key): known[key] = observed[key]
	return geometry

func _drill_origin(unit: Dictionary, append: bool, planning_nav: RefCounted, planning_doors: Array) -> Dictionary:
	var origin := _position(unit)
	var opened: Array = []
	if not append: return {"ok": true, "origin": [origin.x, origin.y]}
	for command: Dictionary in unit.commands:
		if FINISHED.has(str(command.state)): continue
		if str(command.state) == "FAILED": return _drill_rejected("drill.failed_prefix", "앞선 실패 명령을 먼저 수정하세요")
		_forecast_drill_open(command, opened)
		if command.type == "MOVE":
			var destination := _point(command.args.target)
			if planning_nav.path(origin, destination, opened).is_empty(): return _drill_rejected("drill.blocked_prefix", "앞선 이동 경로가 막혀 있습니다")
			origin = destination
		elif DOOR_COMMANDS.has(str(command.type)):
			var door := _find(planning_doors, str(command.args.door_id))
			if door.is_empty(): continue
			var route: Array = planning_nav.approach(origin, door, 0.85, opened)
			if route.is_empty(): return _drill_rejected("drill.blocked_prefix", "앞선 이동 경로가 막혀 있습니다")
			origin = _point(route.back())
			if OPEN_COMMANDS.has(str(command.type)): opened.append(str(door.id))
		elif str(command.type) in ["SECURE_CIVILIAN", "ARREST"]:
			var route: Array = command.get("path", [])
			if route.is_empty(): return _drill_rejected("drill.blocked_prefix", "앞선 이동 경로가 막혀 있습니다")
			origin = _point(route.back())
	return {"ok": true, "origin": [origin.x, origin.y]}

func _formation_geometry() -> Dictionary:
	var geometry := _drill_geometry()
	# Every known portal on the route uses its last observed physical pose.
	# Unobserved leaves remain their authored baseline, never their live state.
	for door: Dictionary in geometry.get("doors", []):
		var observed: Dictionary = _door_observations.get(str(door.id), {})
		for key: String in ["state", "progress", "destroyed", "hp", "locked", "hinge_side", "swing_sign"]:
			if observed.has(key): door[key] = observed[key]
	return geometry

func formation_preview(target: Array, kind: String, order_ids: Array, options: Dictionary = {}) -> Dictionary:
	if not result.is_empty(): return _drill_rejected("formation.error.finished", "종료된 작전에는 대형을 계획할 수 없습니다")
	if kind not in ["AUTO", "SERPENTINE", "ROLLING_T", "T_JUNCTION"]: return _drill_rejected("formation.error.kind", "유효한 대형을 선택하세요")
	if not _valid_target(target): return _drill_rejected("formation.error.target", "맵 안의 유효한 위치를 지정하세요")
	if order_ids.size() < 2 or order_ids.size() > 4: return _drill_rejected("formation.error.team", "서로 다른 대원 2~4명을 선택하세요")
	if kind == "T_JUNCTION" and order_ids.size() != 4: return _drill_rejected("formation.error.team_four", "T자 교차로 드릴에는 대원 4명이 필요합니다")
	for key: Variant in options:
		if key not in ["append", "signal", "delay_ticks"]: return _drill_rejected("formation.error.options", "대형 설정이 올바르지 않습니다")
	if options.has("append") and not options.append is bool: return _drill_rejected("formation.error.options", "대형 설정이 올바르지 않습니다")
	var signal_name := str(options.get("signal", "AUTO"))
	if signal_name not in ["AUTO", "A", "B", "C"]: return _drill_rejected("formation.error.signal", "대형 신호는 자동 또는 A, B, C로 지정하세요")
	if not _drill_integer(options.get("delay_ticks", 0), 0, 3600): return _drill_rejected("formation.error.delay", "동기화 지연은 0~3600 틱으로 지정하세요")
	var geometry := _formation_geometry()
	var planning_doors: Array = geometry.get("doors", []).duplicate(true)
	var planning_nav := Navigation.new()
	planning_nav.build(geometry, planning_doors)
	var approaches: Dictionary = {}
	var seen: Dictionary = {}
	for id: Variant in order_ids:
		if not id is String or seen.has(id): return _drill_rejected("formation.error.team", "서로 다른 대원 2~4명을 선택하세요")
		var unit := _find(units, str(id))
		if unit.is_empty() or not _can_act(unit): return _drill_rejected("formation.error.team", "서로 다른 대원 2~4명을 선택하세요")
		for command: Dictionary in unit.commands:
			if command.state in ["RUNNING", "WAITING"]: return _drill_rejected("formation.error.active", "실행 중인 대원의 대형은 계획할 수 없습니다")
		var projected := _drill_origin(unit, bool(options.get("append", true)), planning_nav, planning_doors)
		if not bool(projected.get("ok", false)): return projected
		approaches[id] = projected.origin
		seen[id] = true
	var calculation := options.duplicate(true)
	calculation["kind"] = kind
	var answer: Dictionary = FormationDrill.calculate(geometry, order_ids, approaches, target, calculation)
	if not bool(answer.get("ok", false)):
		if answer.has("message_key"): answer["i18n_key"] = answer.message_key
		return answer
	answer["signal"] = signal_name
	answer["delay_ticks"] = int(options.get("delay_ticks", 0))
	answer["noise_discipline"] = TeamCommunication.discipline(mission)
	if str(answer.kind) != "T_JUNCTION":
		for slot: Dictionary in answer.slots: slot["stance"] = str(_find(units,str(slot.unit_id)).get("stance","standing"))
	return answer

func _formation_args(preview: Dictionary, slot: Dictionary, base: String, stage: String, args: Dictionary) -> Dictionary:
	var answer := args.duplicate(true)
	answer["formation"] = {"sync_id":base, "kind":str(preview.kind), "order":int(slot.index), "stage":stage, "source_unit_id":str(preview.source_unit_id)}
	return answer

func _formation_commands(preview: Dictionary, slot: Dictionary, base: String) -> Array:
	var nodes: Array = []
	var hand := TeamCommunication.discipline(mission) == "hand_signals"
	var initial: Array = slot.initial_face_target
	nodes.append({"type":"FACE", "args":_formation_args(preview,slot,base,"stack",{"target":initial,"persistent":true,"sector":{"start":0.0,"end":0.0,"duration":0.0}})})
	for point: Array in slot.get("stack_waypoints", []): nodes.append({"type":"MOVE", "args":_formation_args(preview,slot,base,"stack",{"target":point})})
	nodes.append({"type":"MOVE", "args":_formation_args(preview,slot,base,"stack",{"target":slot.stack})})
	var ready: Array = slot.ready_face_target if hand else slot.stack_face_target
	var ready_args := {"target":ready,"persistent":true}
	if str(preview.kind) == "T_JUNCTION": ready_args["stance"] = str(slot.stance)
	nodes.append({"type":"FACE", "args":_formation_args(preview,slot,base,"ready",ready_args)})
	nodes.append({"type":"WAIT_FOR_SIGNAL", "args":_formation_args(preview,slot,base,"ready",{"signal":"A" if preview.signal == "AUTO" else str(preview.signal),"sync_id":base+":ready","auto_signal":preview.signal == "AUTO","delay_ticks":int(preview.delay_ticks)})})
	var route: Array = slot.get("move_waypoints",slot.get("move_route",[])).duplicate(true)
	if route.is_empty() or _point(route.back()).distance_to(_point(slot.target)) > 0.00001: route.append(slot.target)
	var faces: Array = slot.get("move_face_targets",[])
	for index: int in range(route.size()):
		var face: Array = faces[index] if index < faces.size() else slot.face_target
		nodes.append({"type":"FACE", "args":_formation_args(preview,slot,base,"move",{"target":face,"persistent":true})})
		nodes.append({"type":"MOVE", "args":_formation_args(preview,slot,base,"move",{"target":route[index]})})
	nodes.append({"type":"FACE", "args":_formation_args(preview,slot,base,"cover",{"target":slot.face_target,"persistent":true,"sector":_drill_sector(slot.sector)})})
	return nodes

func plan_formation(target: Array, kind: String, order_ids: Array, options: Dictionary = {}) -> Dictionary:
	var preview := formation_preview(target,kind,order_ids,options)
	if not bool(preview.get("ok",false)): return preview
	var sequence := _drill_sequence + 1
	var base := "formation-%04d" % sequence
	while _formation_id_exists(base):
		sequence += 1
		base = "formation-%04d" % sequence
	var planned: Dictionary = {}
	for slot: Dictionary in preview.slots:
		planned[slot.unit_id] = _formation_commands(preview,slot,base)
		var count := 0
		if bool(options.get("append",true)):
			for command: Dictionary in _find(units,str(slot.unit_id)).commands:
				if not FINISHED.has(str(command.state)): count += 1
		if count+planned[slot.unit_id].size()>32: return _drill_rejected("formation.error.capacity","대원당 미완료 명령은 최대 32개입니다")
	var original_units: Array = units
	var original_doors: Array = doors
	var original_nav: RefCounted = nav
	var old_sequence := _command_sequence
	var old_revisions := plan_revisions
	var old_requests := _requests.duplicate(true)
	var old_dirty := _preview_dirty_units
	var old_depth := _preview_batch_depth
	var old_pause := pause_requested
	var old_reservations := _reservations.duplicate(true)
	var old_barriers := _flash_door_barriers.duplicate(true)
	units = units.duplicate(true)
	var geometry := _formation_geometry()
	doors = geometry.get("doors",[]).duplicate(true)
	nav = Navigation.new()
	nav.build(geometry,doors)
	_preview_batch_depth = 1
	_preview_dirty_units = {}
	var failure: Dictionary = {}
	var ids: Dictionary = {}
	for unit: Dictionary in units:
		if not planned.has(unit.id): continue
		ids[unit.id] = []
		var first := true
		for node: Dictionary in planned[unit.id]:
			var answer := issue(str(unit.id),str(node.type),node.args,bool(options.get("append",true)) if first else true)
			first = false
			if not bool(answer.get("ok",false)):
				failure = answer
				break
			ids[unit.id].append(answer.id)
		if not failure.is_empty(): break
	if failure.is_empty():
		_end_preview_batch()
		for unit: Dictionary in units:
			if planned.has(unit.id) and (not _preview_valid(unit) or not _weapon_queue_resources_valid(unit)):
				failure = _drill_rejected("formation.error.route","벽·문·가구 때문에 대형 경로에 접근할 수 없습니다")
				break
	var staged_units: Array = units
	var staged_sequence := _command_sequence
	units = original_units
	doors = original_doors
	nav = original_nav
	_command_sequence = old_sequence
	plan_revisions = old_revisions
	_requests = old_requests
	_preview_dirty_units = old_dirty
	_preview_batch_depth = old_depth
	pause_requested = old_pause
	_reservations = old_reservations
	_flash_door_barriers = old_barriers
	if not failure.is_empty(): return failure
	for unit: Dictionary in units:
		if planned.has(unit.id):
			unit.commands = _find(staged_units,str(unit.id)).commands
			_refresh_preview(unit)
	_command_sequence = staged_sequence
	_drill_sequence = sequence
	plan_revisions += 1
	preview["sync_id"] = base
	preview["command_ids"] = ids
	preview["message_key"] = "formation.planned"
	preview["i18n_key"] = "formation.planned"
	preview["message"] = "대형 이동을 계획했습니다"
	return preview

func _formation_id_exists(base: String) -> bool:
	for unit: Dictionary in units:
		for command: Dictionary in unit.commands:
			if str(command.args.get("formation",{}).get("sync_id","")) == base: return true
	return false

func room_entry_preview(door_id: String, method: String, order_ids: Array, options: Dictionary = {}) -> Dictionary:
	if not result.is_empty(): return _drill_rejected("drill.finished", "종료된 작전에는 진입 드릴을 계획할 수 없습니다")
	if method not in OPEN_COMMANDS: return _drill_rejected("drill.method", "유효한 문 개방 방법을 선택하세요")
	if order_ids.size() < 2 or order_ids.size() > 4: return _drill_rejected("drill.roster", "서로 다른 대원 2~4명을 선택하세요")
	for key: Variant in options:
		if key not in ["append", "signal", "go_long", "room_id", "operator_id", "delay_ticks"]: return _drill_rejected("drill.options", "진입 드릴 설정이 올바르지 않습니다")
	if (options.has("append") and not options.append is bool) or (options.has("go_long") and not options.go_long is bool): return _drill_rejected("drill.options", "진입 드릴 설정이 올바르지 않습니다")
	var signal_name := str(options.get("signal", "AUTO"))
	if signal_name not in ["AUTO", "A", "B", "C"]: return _drill_rejected("drill.signal", "드릴 신호는 자동 또는 A, B, C로 지정하세요")
	var delay: Variant = options.get("delay_ticks", 0)
	if not _drill_integer(delay, 0, 3600): return _drill_rejected("drill.delay", "동기화 지연은 0~3600 틱으로 지정하세요")
	var geometry := _drill_geometry(door_id)
	var planning_doors: Array = geometry.get("doors", []).duplicate(true)
	if _find(planning_doors, door_id).is_empty(): return _drill_rejected("drill.door", "유효한 문을 선택하세요")
	if not _door_observations.has(door_id): return _drill_rejected("drill.unobserved", "관측한 문에만 진입 드릴을 계획할 수 있습니다")
	var planning_nav := Navigation.new()
	planning_nav.build(geometry, planning_doors)
	var approach_by_id: Dictionary = {}
	var seen: Dictionary = {}
	var append: bool = bool(options.get("append", true))
	for id: Variant in order_ids:
		if not id is String or seen.has(id): return _drill_rejected("drill.roster", "서로 다른 대원 2~4명을 선택하세요")
		var unit := _find(units, str(id))
		if unit.is_empty() or float(unit.hp) <= 0.0: return _drill_rejected("drill.roster", "서로 다른 대원 2~4명을 선택하세요")
		for command: Dictionary in unit.commands:
			if str(command.state) in ["RUNNING", "WAITING"]: return _drill_rejected("drill.active", "실행 중인 대원의 드릴은 계획할 수 없습니다")
		for door: Dictionary in doors:
			if str(door.get("owner_id", "")) == id: return _drill_rejected("drill.active", "실행 중인 대원의 드릴은 계획할 수 없습니다")
		var projected := _drill_origin(unit, append, planning_nav, planning_doors)
		if not bool(projected.get("ok", false)): return projected
		approach_by_id[id] = projected.origin
		seen[id] = true
	var operator_id := str(options.get("operator_id", order_ids[0]))
	if not seen.has(operator_id): return _drill_rejected("drill.operator", "문 처리 담당은 선택한 대원이어야 합니다")
	var operator := _find(units, operator_id)
	var resource := _door_resource_reason(operator, method, {"door_id": door_id}, append)
	if not resource.is_empty(): return _drill_rejected("drill.resources", resource)
	if method == "OPEN_AND_FLASH" and (_available_stuns(operator, append) <= 0 or mission.get("modifiers", []).has("no_stun")): return _drill_rejected("drill.resources", "예약분을 제외한 섬광탄이 없습니다")
	var effective: Array = order_ids.duplicate()
	if method == "SHOTGUN_BREACH":
		effective.erase(operator_id)
		effective.append(operator_id)
	var calculation := options.duplicate(true)
	calculation["operator_id"] = operator_id
	calculation["method"] = method
	var answer: Dictionary = RoomDrill.calculate(geometry, door_id, effective, approach_by_id, calculation)
	if not bool(answer.get("ok", false)):
		if answer.has("message_key"): answer["i18n_key"] = answer.message_key
		return answer
	answer["operator_id"] = operator_id
	answer["order_ids"] = effective
	answer["signal"] = signal_name
	answer["delay_ticks"] = int(delay)
	return answer

func _drill_args(preview: Dictionary, base: String, slot: Dictionary, stage: String, args: Dictionary) -> Dictionary:
	var answer := args.duplicate(true)
	answer["drill"] = {"sync_id": base, "door_id": str(preview.door_id), "room_id": str(preview.room_id), "order": int(slot.index), "stage": stage}
	return answer

func _drill_sector(sector: Dictionary) -> Dictionary:
	return {"start": float(sector.start), "end": float(sector.end), "duration": float(sector.get("duration", 12.0))}

func _drill_commands(preview: Dictionary, slot: Dictionary, base: String, options: Dictionary) -> Array:
	var planned: Array = []
	var channel: String = "A" if preview.signal == "AUTO" else str(preview.signal)
	for point: Array in slot.get("stack_waypoints", []):
		planned.append({"type": "MOVE", "args": _drill_args(preview, base, slot, "stack", {"target": point})})
	planned.append({"type": "MOVE", "args": _drill_args(preview, base, slot, "stack", {"target": slot.stack})})
	planned.append({"type": "WAIT_FOR_SIGNAL", "args": _drill_args(preview, base, slot, "ready", {"signal": channel, "sync_id": base + ":ready", "auto_signal": preview.signal == "AUTO", "delay_ticks": preview.delay_ticks})})
	if str(slot.unit_id) == str(preview.operator_id):
		planned.append({"type": str(preview.method), "args": _drill_args(preview, base, slot, "door", {"door_id": preview.door_id})})
	elif preview.method == "BREACH_DOOR":
		planned.append({"type": "MOVE", "args": _drill_args(preview, base, slot, "safe", {"target": slot.safe_retreat})})
	planned.append({"type": "WAIT_FOR_SIGNAL", "args": _drill_args(preview, base, slot, "entry", {"signal": channel, "sync_id": base + ":entry", "auto_signal": true, "delay_ticks": 0})})
	if bool(slot.entry):
		var checkpoints: Array = slot.get("entry_waypoints", [])
		for point: Array in checkpoints:
			planned.append({"type": "MOVE", "args": _drill_args(preview, base, slot, "entry", {"target": point, "sector": _drill_sector(slot.sector_entry)})})
		planned.append({"type": "MOVE", "args": _drill_args(preview, base, slot, "domination" if not checkpoints.is_empty() else "entry", {"target": slot.domination, "sector": _drill_sector(slot.sector_entry)})})
		planned.append({"type": "FACE", "args": _drill_args(preview, base, slot, "domination", {"target": slot.face_target, "persistent": false, "sector": _drill_sector(slot.sector_domination)})})
	else:
		planned.append({"type": "FACE", "args": _drill_args(preview, base, slot, "guard", {"target": slot.face_target, "persistent": false, "sector": _drill_sector(slot.sector_domination)})})
	if bool(options.get("go_long", false)):
		planned.append({"type": "WAIT_FOR_SIGNAL", "args": _drill_args(preview, base, slot, "go_long", {"signal": channel, "sync_id": base + ":go_long", "auto_signal": true, "delay_ticks": 0})})
		for goal: Dictionary in preview.get("go_long", []):
			if str(goal.unit_id) == str(slot.unit_id):
				planned.append({"type": "MOVE", "args": _drill_args(preview, base, slot, "go_long", {"target": goal.target, "sector": _drill_sector(goal.sector)})})
				planned.append({"type": "FACE", "args": _drill_args(preview, base, slot, "go_long", {"target": goal.face_target, "persistent": false, "sector": _drill_sector(goal.sector)})})
	return planned

func plan_room_entry(door_id: String, method: String, order_ids: Array, options: Dictionary = {}) -> Dictionary:
	var preview := room_entry_preview(door_id, method, order_ids, options)
	if not bool(preview.get("ok", false)): return preview
	var next_sequence := _drill_sequence + 1
	var base := "drill-%04d" % next_sequence
	while _drill_id_exists(base):
		next_sequence += 1
		base = "drill-%04d" % next_sequence
	var planned: Dictionary = {}
	for slot: Dictionary in preview.slots:
		planned[slot.unit_id] = _drill_commands(preview, slot, base, options)
		var unit := _find(units, str(slot.unit_id))
		var unfinished: int = 0
		if bool(options.get("append", true)):
			for command: Dictionary in unit.commands:
				if not FINISHED.has(str(command.state)): unfinished += 1
		if unfinished + planned[slot.unit_id].size() > 32: return _drill_rejected("drill.capacity", "대원당 미완료 명령은 최대 32개입니다")
	# Stage ordinary issue() calls against owned copies. Rejection cannot alter
	# any live actor, door ownership, request cache, RNG or command numbering.
	var original_units: Array = units
	var original_doors: Array = doors
	var original_nav: RefCounted = nav
	var old_sequence := _command_sequence
	var old_revisions := plan_revisions
	var old_requests := _requests.duplicate(true)
	var old_dirty := _preview_dirty_units
	var old_depth := _preview_batch_depth
	var old_pause := pause_requested
	var old_flash_nav: RefCounted = _known_flash_navigation
	var old_flash_doors: Array = _known_flash_doors
	var old_flash_key := _known_flash_key
	var old_barriers := _flash_door_barriers.duplicate(true)
	var old_reservations := _reservations.duplicate(true)
	units = units.duplicate(true)
	var geometry := _drill_geometry(door_id)
	doors = geometry.get("doors", []).duplicate(true)
	nav = Navigation.new()
	nav.build(geometry, doors)
	_preview_batch_depth = 1
	_preview_dirty_units = {}
	var failure: Dictionary = {}
	var ids: Dictionary = {}
	# Roster order is also the plan import order; tactical rank stays metadata.
	for unit: Dictionary in units:
		if not planned.has(unit.id): continue
		ids[unit.id] = []
		var first := true
		for node: Dictionary in planned[unit.id]:
			var answer := issue(str(unit.id), str(node.type), node.args, bool(options.get("append", true)) if first else true)
			first = false
			if not bool(answer.get("ok", false)):
				failure = answer
				break
			ids[unit.id].append(answer.id)
		if not failure.is_empty(): break
	if failure.is_empty():
		_end_preview_batch()
		for unit: Dictionary in units:
			if planned.has(unit.id) and (not _preview_valid(unit) or not _weapon_queue_resources_valid(unit)):
				failure = _drill_rejected("drill.blocked", "벽·문·가구 때문에 드릴 경로에 접근할 수 없습니다")
				break
	var staged_units: Array = units
	var staged_sequence := _command_sequence
	units = original_units
	doors = original_doors
	nav = original_nav
	_command_sequence = old_sequence
	plan_revisions = old_revisions
	_requests = old_requests
	_preview_dirty_units = old_dirty
	_preview_batch_depth = old_depth
	pause_requested = old_pause
	_known_flash_navigation = old_flash_nav
	_known_flash_doors = old_flash_doors
	_known_flash_key = old_flash_key
	_flash_door_barriers = old_barriers
	_reservations = old_reservations
	if not failure.is_empty():
		failure["message_key"] = str(failure.get("message_key", "drill.blocked"))
		failure["i18n_key"] = failure.message_key
		return failure
	for unit: Dictionary in units:
		if planned.has(unit.id):
			unit.commands = _find(staged_units, str(unit.id)).commands
			_refresh_preview(unit)
	_command_sequence = staged_sequence
	_drill_sequence = next_sequence
	_room_drill_layouts[base] = preview.duplicate(true)
	plan_revisions += 1
	pause_requested = false
	preview["sync_id"] = base
	preview["command_ids"] = ids
	preview["message"] = "진입 드릴을 계획했습니다"
	preview["message_key"] = "drill.planned"
	preview["i18n_key"] = "drill.planned"
	return preview

func _drill_id_exists(base: String) -> bool:
	for unit: Dictionary in units:
		for command: Dictionary in unit.commands:
			if str(command.args.get("drill", {}).get("sync_id", "")) == base: return true
	return false

func update_room_drill_delay(sync_id: String, delay_ticks: int) -> Dictionary:
	if delay_ticks < 0 or delay_ticks > 3600 or not _valid_request_id(sync_id) or not sync_id.ends_with(":ready"): return _drill_rejected("drill.delay", "동기화 지연은 0~3600 틱으로 지정하세요")
	var matching: Array = []
	for unit: Dictionary in units:
		for command: Dictionary in unit.commands:
			if command.type == "WAIT_FOR_SIGNAL" and str(command.args.get("sync_id", "")) == sync_id:
				if command.state != "PENDING": return _drill_rejected("drill.delay_pending", "미실행 준비 신호만 함께 수정할 수 있습니다")
				matching.append(command)
	if matching.is_empty(): return _drill_rejected("drill.delay_pending", "미실행 준비 신호만 함께 수정할 수 있습니다")
	for command: Dictionary in matching: command.args["delay_ticks"] = delay_ticks
	plan_revisions += 1
	return {"ok": true, "sync_id": sync_id, "delay_ticks": delay_ticks, "updated": matching.size(), "message_key": "drill.delay_updated", "i18n_key": "drill.delay_updated", "message": "드릴 신호 지연을 수정했습니다"}

func plan_move(unit_id: String, args: Dictionary, append: bool = true) -> Dictionary:
	_preview_batch_depth += 1
	var response := _plan_move(unit_id, args, append)
	_end_preview_batch()
	return response

func _end_preview_batch() -> void:
	_preview_batch_depth -= 1
	if _preview_batch_depth > 0: return
	for unit: Dictionary in _preview_dirty_units.values(): _refresh_preview(unit)
	_preview_dirty_units.clear()

func _plan_move(unit_id: String, args: Dictionary, append: bool) -> Dictionary:
	# Validate a player's plan before mutating their queue. Execution still rechecks it.
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty():
		return _rejected("먼저 대원을 선택하세요")
	var reason: String = _validate("MOVE", args)
	if not reason.is_empty():
		return _rejected(reason)
	if not result.is_empty() or float(unit["hp"]) <= 0.0:
		return _rejected("행동 가능한 작전과 대원을 선택하세요")
	var request_id: String = str(args.get("request_id", ""))
	if not request_id.is_empty() and _requests.has(unit_id + ":" + request_id):
		return _requests[unit_id + ":" + request_id].duplicate(true)
	var automatic_doors: Array = []
	var target: Vector2 = _point(args["target"])
	var projected: Dictionary = _project_movement_plan(unit, append)
	var route: Array = []
	if bool(projected["ok"]):
		route = nav.path(projected["origin"], target, projected["open"])
	var preserve_doors: bool = false
	if route.is_empty() and not append:
		# A right-click beyond a door must not silently erase its explicit OPEN order.
		var queued: Dictionary = _project_movement_plan(unit, true)
		if bool(queued["ok"]) and not queued["open"].is_empty():
			route = nav.path(queued["origin"], target, queued["open"])
			if not route.is_empty():
				projected = queued
				preserve_doors = true
	# An open loop is not necessarily the best route: consider opening a
	# connecting door even when a longer, already-open route exists.
	if not route.is_empty() and not preserve_doors:
		var shortcut_open: Array = projected["open"].duplicate()
		for door: Dictionary in doors:
			if not shortcut_open.has(str(door["id"])):
				shortcut_open.append(str(door["id"]))
		var shortcut: Array = nav.path(projected["origin"], target, shortcut_open)
		if not shortcut.is_empty():
			var shortcut_cost: float = _movement_route_length(projected["origin"], shortcut)
			var cursor: Vector2 = projected["origin"]
			var counted: Array = projected["open"].duplicate()
			for waypoint: Array in shortcut:
				var endpoint: Vector2 = _point(waypoint)
				for door: Dictionary in doors:
					if door["state"] != "OPEN" and not counted.has(str(door["id"])) and nav._segment_rect(cursor, endpoint, nav._rect(door, nav.RADIUS)):
						# Two metres of travel cost avoids opening doors for tiny savings.
						shortcut_cost += 2.0
						counted.append(str(door["id"]))
				cursor = endpoint
			if shortcut_cost + 0.1 < _movement_route_length(projected["origin"], route):
				route = []
	if route.is_empty():
		if not bool(projected["ok"]):
			return _rejected(str(projected["message"]))
		var all_open: Array = []
		for door: Dictionary in doors:
			all_open.append(str(door["id"]))
		if not nav.walkable(target, all_open):
			return _rejected("문짝·벽·가구에 너무 가깝습니다. 장애물에서 조금 떨어진 빈 바닥을 지정하세요. 기존 계획은 유지됩니다")
		var future_route: Array = nav.path(projected["origin"], target, all_open)
		if future_route.is_empty():
			return _rejected("이 위치까지 이어지는 통로가 없습니다. 기존 계획은 유지됩니다")
		var cursor: Vector2 = projected["origin"]
		var opened: Array = projected["open"].duplicate()
		for waypoint: Array in future_route:
			var endpoint: Vector2 = _point(waypoint)
			var crossed: Array = []
			for door: Dictionary in doors:
				if door["state"] != "OPEN" and not opened.has(str(door["id"])) and nav._segment_rect(cursor, endpoint, nav._rect(door, nav.RADIUS)):
					crossed.append(door)
			crossed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return cursor.distance_squared_to(_position(a)) < cursor.distance_squared_to(_position(b)))
			for door: Dictionary in crossed:
				automatic_doors.append(str(door["id"]))
				opened.append(str(door["id"]))
			cursor = endpoint
		# Check the whole sequence before changing any existing order.
		cursor = projected["origin"]
		opened = projected["open"].duplicate()
		for door_id: String in automatic_doors:
			var planned_door: Dictionary = _find(doors, door_id)
			var approach: Array = nav.approach(cursor, planned_door, 0.85, opened)
			if approach.is_empty():
				return _rejected("문 앞까지 접근할 수 없습니다. 다른 목적지를 지정하세요. 기존 계획은 유지됩니다")
			cursor = _point(approach.back())
			projected["predicted"][door_id] = _predict_open_leaf(planned_door, cursor)
			opened.append(door_id)
		if nav.path(cursor, target, opened).is_empty():
			return _rejected("목적지까지 접근할 수 없습니다. 기존 계획은 유지됩니다")
	# Validate a known future leaf before replacing any active or queued order.
	# Its direction follows this plan's actual operator approach, not a global
	# assumption that all closed leaves rotate to the same side.
	for predicted: Dictionary in projected.get("predicted", {}).values():
		if DoorGeometry.overlaps_actor(predicted, 1.0, target, Navigation.RADIUS):
			return _rejected("예정된 문짝 회전 공간과 목적지가 겹칩니다. 문짝에서 떨어진 바닥을 지정하세요. 기존 계획은 유지됩니다")
	var retained: int = 0
	for command: Dictionary in unit["commands"]:
		if not FINISHED.has(str(command["state"])) and (append or preserve_doors or (not command["state"] in ["PENDING", "FAILED"] and not command["type"] in ["MOVE", "FACE", "WAIT", "WAIT_FOR_SIGNAL", "OPEN_DOOR", "KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "OPEN_AND_FLASH", "PEEK_CAMERA"])):
			retained += 1
	if retained + automatic_doors.size() + 1 > 32:
		return _rejected("자동 문 열기를 포함해 대원당 명령은 최대 32개입니다. 기존 계획은 유지됩니다")
	for door_id: String in automatic_doors:
		if bool(_door_observations.get(door_id, {}).get("locked", false)):
			return _rejected("경로에 잠긴 문이 있습니다. 차기 또는 문 파괴를 먼저 계획하세요. 기존 계획은 유지됩니다")
	for door_id: String in automatic_doors:
		issue(unit_id, "OPEN_DOOR", {"door_id": door_id}, append or preserve_doors)
		append = true
	var response: Dictionary = issue(unit_id, "MOVE", args, append or preserve_doors)
	if bool(response.get("ok", false)) and preserve_doors:
		response["preserved_door_plan"] = true
		response["message"] = "문 열기 계획을 유지하고 그 뒤에 이동을 추가했습니다"
	if bool(response.get("ok", false)) and not automatic_doors.is_empty():
		response["message"] = "경로의 문 %d개를 자동으로 열고 이동합니다" % automatic_doors.size()
	if not request_id.is_empty() and bool(response.get("ok", false)):
		_requests[unit_id + ":" + request_id] = response.duplicate(true)
	return response

func _movement_route_length(origin: Vector2, route: Array) -> float:
	var length: float = 0.0
	for waypoint: Array in route:
		var endpoint: Vector2 = _point(waypoint)
		length += origin.distance_to(endpoint)
		origin = endpoint
	return length

func _project_movement_plan(unit: Dictionary, include_pending: bool) -> Dictionary:
	var origin: Vector2 = _position(unit)
	var assumed_open: Array = []
	var predicted: Dictionary = {}
	for command: Dictionary in unit["commands"]:
		var state: String = str(command["state"])
		var type: String = str(command["type"])
		if FINISHED.has(state):
			continue
		if not include_pending and (state in ["PENDING", "FAILED"] or type in ["MOVE", "FACE", "WAIT", "WAIT_FOR_SIGNAL", "OPEN_DOOR", "KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "OPEN_AND_FLASH", "PEEK_CAMERA"]):
			continue
		if state == "FAILED":
			return {"ok": false, "origin": origin, "open": assumed_open, "message": "앞선 실패 명령이 대기열을 막고 있습니다. 명령 목록에서 실패 명령을 삭제하거나, 빈 바닥을 우클릭해 이동 계획을 새로 지정하세요"}
		var args: Dictionary = command["args"]
		_forecast_drill_open(command, assumed_open)
		if type == "MOVE":
			var destination: Vector2 = _point(args["target"])
			if nav.path(origin, destination, assumed_open).is_empty():
				return {"ok": false, "origin": origin, "open": assumed_open, "message": "앞선 이동 명령의 경로가 막혀 있습니다. 해당 이동을 지우고 문 열기부터 계획하세요"}
			origin = destination
		elif DOOR_COMMANDS.has(type):
			var door: Dictionary = _find(doors, str(args["door_id"]))
			if door.is_empty():
				continue
			if str(door["state"]) != "OPEN":
				var approach_path: Array = nav.approach(origin, door, 0.85, assumed_open)
				if approach_path.is_empty():
					return {"ok": false, "origin": origin, "open": assumed_open, "message": "예약한 문까지 접근할 수 없습니다. 가까운 문부터 차례로 열도록 계획하세요"}
				origin = _point(approach_path.back())
				predicted[str(door["id"])] = _predict_open_leaf(door, origin)
				if OPEN_COMMANDS.has(type): assumed_open.append(str(door["id"]))
		elif type == "SECURE_CIVILIAN":
			var civilian: Dictionary = _find(civilians, str(args["civilian_id"]))
			if not civilian.is_empty():
				var approach_path: Array = nav.approach(origin, civilian, 0.8, assumed_open)
				if not approach_path.is_empty():
					origin = _point(approach_path.back())
	return {"ok": true, "origin": origin, "open": assumed_open, "predicted": predicted}

func _predict_open_leaf(door: Dictionary, operator_position: Vector2) -> Dictionary:
	var predicted: Dictionary = door.duplicate(true)
	predicted["swing_sign"] = DoorGeometry.opening_sign(door, operator_position)
	predicted["state"] = "OPEN"
	predicted["progress"] = 1.0
	return predicted

func _validate(type: String, args: Dictionary) -> String:
	if type == "THROW_FRAG" and MissionCatalog.roe(mission) != "high_intensity": return "정밀 교전수칙에서는 파편 수류탄을 사용할 수 없습니다"
	var allowed: Array = ["request_id"]
	if args.has("formation"):
		allowed.append("formation")
		if args.has("drill") or type not in ["MOVE","FACE","WAIT_FOR_SIGNAL"] or not _valid_formation_metadata(args.formation): return "대형 명령 정보가 올바르지 않습니다"
	if args.has("drill"):
		allowed.append("drill")
		if not _valid_drill_metadata(args.drill): return "진입 드릴 정보가 올바르지 않습니다"
	if args.has("sector"):
		allowed.append("sector")
		if type not in ["MOVE", "FACE"] or bool(args.get("unlock", false)) or not _valid_sector(args.sector): return "사격 구역 정보가 올바르지 않습니다"
	match type:
		"MOVE", "THROW_STUN", "THROW_SMOKE", "THROW_FRAG": allowed.append("target")
		"FACE":
			if args.has("unlock"):
				if not args["unlock"] is bool or args["unlock"] != true:
					return "주시 해제 인수가 올바르지 않습니다"
				allowed.append("unlock")
			else:
				allowed.append("target")
				allowed.append("persistent")
				allowed.append("stance")
				if args.has("stance") and args.stance not in ["standing","crouched"]: return "자세 설정이 올바르지 않습니다"
				if args.has("persistent") and not args["persistent"] is bool:
					return "주시 고정 인수가 올바르지 않습니다"
		"WAIT": allowed.append("duration")
		"WAIT_FOR_SIGNAL": allowed.append_array(["signal", "sync_id", "auto_signal", "delay_ticks"])
		"KICK_DOOR": allowed.append_array(["door_id", "fallback"])
		"OPEN_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "PEEK_CAMERA": allowed.append("door_id")
		"OPEN_AND_FLASH": allowed.append_array(["door_id", "target"])
		"SWITCH_WEAPON": allowed.append("slot")
		"SECURE_CIVILIAN": allowed.append("civilian_id")
		"ARREST": allowed.append("enemy_id")
	for key: Variant in args:
		if not key is String or not allowed.has(key):
			return "명령에 지원하지 않는 인수가 있습니다"
	if args.has("request_id") and not _valid_request_id(args["request_id"]):
		return "명령 요청 ID가 올바르지 않습니다"
	if type == "FACE" and args.get("unlock", false) == true:
		return ""
	if type in ["MOVE", "FACE", "THROW_STUN", "THROW_SMOKE", "THROW_FRAG"] or (type == "OPEN_AND_FLASH" and args.has("target")):
		if not _valid_target(args.get("target", null)):
			return "맵 안의 유효한 위치를 지정하세요"
		var target: Vector2 = _point(args["target"])
		if target.x < 0.0 or target.y < 0.0 or target.x > nav.bounds.x or target.y > nav.bounds.y:
			return "맵 밖에는 명령을 지정할 수 없습니다"
	if type == "SWITCH_WEAPON" and str(args.get("slot", "secondary")) not in ["primary", "secondary"]:
		return "전환할 무기 슬롯이 올바르지 않습니다"
	if type == "WAIT":
		var duration: Variant = args.get("duration", 1.0)
		if not (duration is int or duration is float) or not is_finite(float(duration)) or float(duration) < 0.0 or float(duration) > 120.0:
			return "대기 시간은 0~120초로 지정하세요"
	if type == "WAIT_FOR_SIGNAL" and not ["A", "B", "C"].has(str(args.get("signal", "A"))):
		return "신호는 A, B, C 중에서 선택하세요"
	if type == "WAIT_FOR_SIGNAL":
		if args.has("sync_id") and not _valid_request_id(args.sync_id): return "동기화 신호 ID가 올바르지 않습니다"
		if args.has("auto_signal") and (not args.auto_signal is bool or not args.has("sync_id")): return "자동 신호 정보가 올바르지 않습니다"
		if args.has("delay_ticks") and (not args.has("sync_id") or not _drill_integer(args.delay_ticks, 0, 3600)): return "동기화 지연은 0~3600 틱으로 지정하세요"
		if args.has("drill"):
			var stage := str(args.drill.stage)
			if stage not in ["ready", "entry", "go_long"] or str(args.get("sync_id", "")) != str(args.drill.sync_id) + ":" + stage: return "드릴 대기 신호가 단계와 일치하지 않습니다"
			if stage == "entry" and not bool(args.get("auto_signal", false)): return "진입 안전 신호는 자동으로만 해제할 수 있습니다"
		if args.has("formation") and (str(args.formation.stage) != "ready" or str(args.get("sync_id","")) != str(args.formation.sync_id)+":ready"): return "대형 대기 신호가 단계와 일치하지 않습니다"
	if DOOR_COMMANDS.has(type) and _find(doors, str(args.get("door_id", ""))).is_empty():
		return "유효한 문을 선택하세요"
	if type == "KICK_DOOR" and args.has("fallback") and (not args.fallback is String or args.fallback != "breach"):
		return "차기 실패 분기는 장약으로만 지정할 수 있습니다"
	if type in ["OPEN_DOOR", "PEEK_DOOR", "OPEN_AND_FLASH"] and bool(_door_observations.get(str(args.get("door_id", "")), {}).get("locked", false)):
		return "잠긴 문입니다. 차기 또는 문 파괴로 개방하세요"
	if type in ["KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH"] and _find(doors, str(args.get("door_id", ""))).get("state", "") == "OPEN":
		return "이미 열린 문입니다"
	if type == "ARREST":
		var enemy: Dictionary = _find(enemies, str(args.get("enemy_id", "")))
		if enemy.is_empty() or not bool(enemy.get("visible", false)) or enemy.get("status", "") != "SURRENDERED":
			return "관측된 투항 대상을 선택하세요"
	if type == "SECURE_CIVILIAN" and _find(civilians, str(args.get("civilian_id", ""))).is_empty():
		return "유효한 민간인을 선택하세요"
	return ""

func _valid_drill_metadata(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 5: return false
	for key: Variant in value:
		if key not in ["sync_id", "door_id", "room_id", "order", "stage"]: return false
	if not _valid_request_id(value.get("sync_id", "")) or str(value.sync_id).length() > 55: return false
	if not _drill_integer(value.get("order"), 1, 4): return false
	for key: String in ["door_id", "room_id", "stage"]:
		if not value.get(key) is String: return false
	if str(value.get("stage", "")) not in ["stack", "ready", "door", "safe", "entry", "domination", "guard", "go_long"]: return false
	return not _find(doors, str(value.get("door_id", ""))).is_empty() and not _find(mission.get("rooms", []), str(value.get("room_id", ""))).is_empty()

func _drill_integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= lower and float(value) <= upper

func _valid_sector(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3: return false
	for key: Variant in value:
		if key not in ["start", "end", "duration"]: return false
	for key: String in ["start", "end", "duration"]:
		if not (value.get(key) is int or value.get(key) is float) or not is_finite(float(value[key])): return false
	return absf(float(value.start)) <= PI and absf(float(value.end)) <= PI and float(value.duration) >= 0.0 and float(value.duration) <= 120.0

func _valid_formation_metadata(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 5: return false
	for key: Variant in value:
		if key not in ["sync_id","kind","order","stage","source_unit_id"]: return false
	if not _valid_request_id(value.get("sync_id")) or str(value.sync_id).length() > 55: return false
	if value.get("kind") not in ["SERPENTINE","ROLLING_T","T_JUNCTION"] or value.get("stage") not in ["stack","ready","move","cover"]: return false
	if not _drill_integer(value.get("order"),1,4): return false
	return value.get("source_unit_id") is String and not _find(units,str(value.source_unit_id)).is_empty()

func _valid_request_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64:
		return false
	for i: int in range(value.length()):
		var code: int = value.unicode_at(i)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code in [45, 46, 58, 95]):
			return false
	return true

func _canonical_args(type: String, args: Dictionary) -> Dictionary:
	var canonical: Dictionary = args.duplicate(true)
	match type:
		"WAIT": canonical["duration"] = float(args.get("duration", 1.0))
		"WAIT_FOR_SIGNAL":
			canonical["signal"] = str(args.get("signal", "A"))
			if args.has("sync_id"):
				canonical["auto_signal"] = bool(args.get("auto_signal", false))
				canonical["delay_ticks"] = int(args.get("delay_ticks", 0))
		"SWITCH_WEAPON": canonical["slot"] = str(args.get("slot", "secondary"))
		"KICK_DOOR":
			if args.has("fallback"): canonical["fallback"] = str(args.fallback)
		"MOVE", "FACE", "THROW_STUN", "THROW_SMOKE", "THROW_FRAG", "OPEN_AND_FLASH":
			if args.has("target"):
				canonical["target"] = [float(args["target"][0]), float(args["target"][1])]
	if args.has("sector"):
		canonical["sector"] = {"start": float(args.sector.start), "end": float(args.sector.end), "duration": float(args.sector.duration)}
	if args.has("drill"): canonical.drill["order"] = int(args.drill.order)
	if args.has("formation"): canonical.formation["order"] = int(args.formation.order)
	if args.has("drill") or args.has("formation") or args.has("sector"):
		# The existing web plan bridge writes JSON with 15 significant digits.
		# Canonicalize new metadata once so saving/reloading cannot alter aim.
		canonical = JSON.parse_string(JSON.stringify(canonical))
		if canonical.has("drill"): canonical.drill["order"] = int(canonical.drill.order)
		if canonical.has("formation"): canonical.formation["order"] = int(canonical.formation.order)
		if type == "WAIT_FOR_SIGNAL" and canonical.has("sync_id"): canonical["delay_ticks"] = int(canonical.get("delay_ticks", 0))
	return canonical

func _valid_target(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))

func _rejected(message: String) -> Dictionary:
	var answer := {"ok": false, "message": message}
	var drill_keys := {"진입 드릴 정보가 올바르지 않습니다": "drill.invalid_metadata", "사격 구역 정보가 올바르지 않습니다": "drill.invalid_sector", "동기화 신호 ID가 올바르지 않습니다": "drill.invalid_sync", "자동 신호 정보가 올바르지 않습니다": "drill.invalid_auto", "드릴 대기 신호가 단계와 일치하지 않습니다": "drill.invalid_wait", "진입 안전 신호는 자동으로만 해제할 수 있습니다": "drill.invalid_auto", "동기화 지연은 0~3600 틱으로 지정하세요": "drill.delay"}
	if drill_keys.has(message):
		answer["message_key"] = drill_keys[message]
		answer["i18n_key"] = drill_keys[message]
	var frag_keys := {"정밀 교전수칙에서는 파편 수류탄을 사용할 수 없습니다":"frag.forbidden", "예약분을 제외한 파편 수류탄이 없습니다":"frag.no_inventory", "파편 수류탄 투척 범위 8m를 벗어났습니다":"frag.range", "벽 또는 닫힌 문이 파편 수류탄 투척 경로를 막습니다":"frag.path", "파편 수류탄 재고 또는 투척 경로가 변경되었습니다":"frag.changed"}
	if frag_keys.has(message):
		answer["message_key"] = frag_keys[message]
		answer["i18n_key"] = frag_keys[message]
	var formation_keys := {"대형 명령 정보가 올바르지 않습니다":"formation.error.metadata", "대형 대기 신호가 단계와 일치하지 않습니다":"formation.error.wait", "자세 설정이 올바르지 않습니다":"formation.error.stance"}
	if formation_keys.has(message):
		answer["message_key"] = formation_keys[message]
		answer["i18n_key"] = formation_keys[message]
	return answer

func _prune_history(commands: Array) -> void:
	var finished: int = 0
	for command: Dictionary in commands:
		if FINISHED.has(str(command["state"])):
			finished += 1
	var index: int = 0
	while finished > 64 and index < commands.size():
		if FINISHED.has(str(commands[index]["state"])):
			commands.remove_at(index)
			finished -= 1
		else:
			index += 1

func cancel_pending(unit_id: String) -> void:
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty():
		return
	for command: Dictionary in unit["commands"]:
		if command["state"] == "PENDING" or command["state"] == "FAILED":
			command["state"] = "CANCELLED"
			command["reason"] = "사용자가 취소함"
	pause_requested = false
	plan_revisions += 1
	_refresh_preview(unit)

func _cancel_replaceable(unit: Dictionary) -> void:
	for command: Dictionary in unit["commands"]:
		if FINISHED.has(str(command["state"])):
			continue
		if command["state"] in ["PENDING", "FAILED"] or command["type"] in ["MOVE", "FACE", "WAIT", "WAIT_FOR_SIGNAL", "OPEN_DOOR", "KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "OPEN_AND_FLASH", "PEEK_CAMERA", "THROW_STUN", "THROW_FRAG", "SWITCH_WEAPON"]:
			_release_door_owner(str(unit["id"]), str(command["id"]))
			command["state"] = "CANCELLED"
			command["reason"] = "새 계획으로 교체됨"
			_release_flash_barrier(command)
	pause_requested = false

func remove_command(unit_id: String, index: int) -> void:
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty() or index < 0 or index >= unit["commands"].size():
		return
	var command: Dictionary = unit["commands"][index]
	if command["state"] in ["PENDING", "FAILED", "SUCCEEDED", "CANCELLED"]:
		unit["commands"].remove_at(index)
	elif command["type"] in ["MOVE", "FACE", "WAIT", "WAIT_FOR_SIGNAL", "OPEN_DOOR", "KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "OPEN_AND_FLASH", "PEEK_CAMERA", "THROW_STUN", "THROW_FRAG", "SWITCH_WEAPON"]:
		_release_door_owner(str(unit["id"]), str(command["id"]))
		command["state"] = "CANCELLED"
		command["reason"] = "사용자가 중단함"
		_release_flash_barrier(command)
	else:
		return
	pause_requested = false
	plan_revisions += 1
	_refresh_preview(unit)

func reorder_command(unit_id: String, index: int, direction: int) -> void:
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty():
		return
	var commands: Array = unit["commands"]
	var target: int = index + clampi(direction, -1, 1)
	if index < 0 or target < 0 or index >= commands.size() or target >= commands.size():
		return
	if commands[index]["state"] != "PENDING" or commands[target]["state"] != "PENDING":
		return
	var swap: Dictionary = commands[index]
	commands[index] = commands[target]
	commands[target] = swap
	# A weapon switch or reload must still precede each reserved shotgun round.
	if not _weapon_queue_resources_valid(unit):
		commands[target] = commands[index]
		commands[index] = swap
		return
	plan_revisions += 1
	_refresh_preview(unit)

func release_signal(channel: String, sender_id: String = "") -> Dictionary:
	if channel not in ["A","B","C"] or not result.is_empty(): return _drill_rejected("team.invalid_signal","신호는 A, B, C 중에서 선택하세요")
	if not sender_id.is_empty() and not _can_act(_find(units,sender_id)): return _drill_rejected("team.invalid_sender","행동 가능한 아군 신호 발신자를 선택하세요")
	var requested: Dictionary = {}
	var plain: Array = []
	var grouped: Array = []
	for unit: Dictionary in units:
		var command := _active(unit)
		if command.is_empty() or command.type != "WAIT_FOR_SIGNAL" or command.state != "WAITING" or str(command.args.get("signal","A")) != channel: continue
		var sync_id := str(command.args.get("sync_id",""))
		if not sync_id.is_empty():
			if not bool(command.args.get("auto_signal",false)): requested[sync_id] = true
		else: plain.append({"unit":unit,"command":command})
	for sync_id: String in requested:
		var group := _sync_group(sync_id)
		if not _sync_group_ready(group): continue
		_record_room_stack(group)
		var sender := _sync_sender(group,sender_id)
		var receipt := _signal_receipt(group,sender)
		if not bool(receipt.get("complete",false)): continue
		# A gesture authorizes these existing waits, never a later node on the
		# same channel. A positive delay retains this actual received gesture.
		var members: Array = []
		for member: Dictionary in group: members.append({"unit_id":str(member.unit.id),"command_id":str(member.command.id),"args":member.command.args.duplicate(true)})
		_sync_requests[sync_id] = {"members":members,"sender":sender.duplicate(true),"receipt":receipt.duplicate(true),"tick":tick}
		_sync_sources[sync_id] = sender_id
		grouped.append_array(group)
		_emit_signal_sound(sender,_communication_bundle(sender,receipt.receiver_unit_ids))
	var released := 0
	if not plain.is_empty():
		var sender := _sync_sender(plain,sender_id)
		released = _deliver_signal(plain,sender,channel).size() if not sender.is_empty() else 0
	elif requested.is_empty():
		var sender := _sync_sender([],sender_id)
		if not sender.is_empty(): _record_signal(sender,[],channel)
	_advance_sync_waits()
	for member: Dictionary in grouped:
		if str(member.command.state) == "SUCCEEDED": released += 1
	return {"ok":true,"released":released}

func _sync_sender(group: Array, explicit_id: String = "") -> Dictionary:
	if not explicit_id.is_empty():
		var explicit := _find(units,explicit_id)
		return explicit if _can_act(explicit) else {}
	if not group.is_empty():
		var formation: Dictionary = group[0].command.args.get("formation",{})
		var declared := _find(units,str(formation.get("source_unit_id","")))
		if not declared.is_empty() and _can_act(declared): return declared
		var sender: Dictionary = {}
		var rank := -1
		for member: Dictionary in group:
			if not _can_act(member.unit): continue
			var metadata: Dictionary = member.command.args.get("formation",member.command.args.get("drill",{}))
			var candidate_rank := int(metadata.get("order",0))
			if candidate_rank >= rank:
				rank = candidate_rank
				sender = member.unit
		if not sender.is_empty(): return sender
	for index: int in range(units.size()-1,-1,-1):
		if _can_act(units[index]): return units[index]
	return {}

func _record_signal(sender: Dictionary, receiver_ids: Array, channel: String, sync_id: String = "", automatic: bool = false, emit_sound: bool = true) -> void:
	var bundle := _communication_bundle(sender,receiver_ids)
	var extra := {"channel":channel,"released":receiver_ids.size()}
	if not sync_id.is_empty():
		extra["sync_id"] = sync_id
		extra["auto_signal"] = automatic
	for key: String in bundle: extra[key] = bundle[key]
	if emit_sound: _emit_signal_sound(sender,bundle)
	_event("SIGNAL","%s 신호 · 대원 %d명 대기 해제" % [channel,receiver_ids.size()],[],[],extra)

func _signal_receipt(group: Array, sender: Dictionary) -> Dictionary:
	var contexts: Array = []
	for member: Dictionary in group: contexts.append(_communication_context(member.unit))
	return TeamCommunication.delivery(_communication_context(sender),contexts,nav,TeamCommunication.discipline(mission),_smoke_zones)

func _signal_request_matches(group: Array, request: Dictionary) -> bool:
	var members: Array = request.get("members",[])
	if members.size() != group.size(): return false
	for index: int in range(group.size()):
		var member: Dictionary = group[index]
		var received: Dictionary = members[index]
		if str(member.unit.id) != str(received.unit_id) or str(member.command.id) != str(received.command_id) or member.command.args != received.args: return false
	return true

func _deliver_signal(group: Array, sender: Dictionary, channel: String, sync_id: String = "", automatic: bool = false, stored_receipt: Dictionary = {}) -> Array:
	if sender.is_empty(): return []
	var receipt := _signal_receipt(group,sender) if stored_receipt.is_empty() else stored_receipt
	# Named barriers keep the cohort together. Plain legacy waits still let
	# individually received hand signals release their actual active nodes.
	if not sync_id.is_empty() and not bool(receipt.get("complete",false)): return []
	var received: Array = []
	# Receipts apply only to these actual active command objects in this tick.
	# No channel-wide receipt is retained for future waits or edited nodes.
	for member: Dictionary in group:
		if receipt.receiver_unit_ids.has(str(member.unit.id)) and _can_act(member.unit) and member.command.state == "WAITING" and _active(member.unit) == member.command:
			_succeed(member.unit,member.command)
			received.append(str(member.unit.id))
	received.sort()
	if not received.is_empty(): _record_signal(sender,received,channel,sync_id,automatic,stored_receipt.is_empty())
	return received

func _sync_group(sync_id: String) -> Array:
	var group: Array = []
	for unit: Dictionary in units:
		if float(unit.hp) <= 0.0: continue
		for command: Dictionary in unit.commands:
			if command.type == "WAIT_FOR_SIGNAL" and not FINISHED.has(str(command.state)) and str(command.args.get("sync_id", "")) == sync_id:
				group.append({"unit": unit, "command": command})
				break
	return group

func _sync_group_ready(group: Array) -> bool:
	if group.is_empty(): return false
	for member: Dictionary in group:
		if not _can_act(member.unit) or member.command.state != "WAITING" or _active(member.unit) != member.command: return false
	return true

func _same_sync_contract(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("signal", "A")) != str(b.get("signal", "A")) or bool(a.get("auto_signal", false)) != bool(b.get("auto_signal", false)) or int(a.get("delay_ticks", 0)) != int(b.get("delay_ticks", 0)): return false
	if a.has("drill") != b.has("drill"): return false
	if a.has("drill"):
		for key: String in ["sync_id", "door_id", "room_id", "stage"]:
			if str(a.drill.get(key, "")) != str(b.drill.get(key, "")): return false
	if a.has("formation") != b.has("formation"): return false
	if a.has("formation"):
		for key: String in ["sync_id","kind","stage","source_unit_id"]:
			if str(a.formation.get(key,"")) != str(b.formation.get(key,"")): return false
	return true

func _drill_door_finished(base: String, door_id: String) -> bool:
	var found := false
	for unit: Dictionary in units:
		for command: Dictionary in unit.commands:
			var drill: Dictionary = command.args.get("drill", {})
			if str(drill.get("sync_id", "")) == base and str(drill.get("stage", "")) == "door":
				found = true
				if str(command.state) != "SUCCEEDED": return false
	var door := _find(doors, door_id)
	return found and not door.is_empty() and str(door.state) == "OPEN" and str(door.get("owner_id", "")).is_empty()

func _drill_dominated(base: String) -> bool:
	var found := false
	for unit: Dictionary in units:
		if float(unit.hp) <= 0.0: continue
		var goal: Dictionary = {}
		for command: Dictionary in unit.commands:
			var drill: Dictionary = command.args.get("drill", {})
			if str(drill.get("sync_id", "")) == base and str(drill.get("stage", "")) in ["entry", "domination"] and command.type == "MOVE": goal = command
		if not goal.is_empty():
			found = true
			if goal.state != "SUCCEEDED" or _position(unit).distance_to(_point(goal.args.target)) > 0.1: return false
	return found

func _advance_sync_waits() -> void:
	var ids: Dictionary = {}
	for unit: Dictionary in units:
		for command: Dictionary in unit.commands:
			if command.type == "WAIT_FOR_SIGNAL" and not FINISHED.has(str(command.state)) and command.args.has("sync_id"): ids[str(command.args.sync_id)] = true
	var ordered: Array = ids.keys()
	ordered.sort()
	for sync_id: String in ordered:
		var group := _sync_group(sync_id)
		if group.is_empty(): continue
		var first: Dictionary = group[0].command.args
		var consistent := true
		for member: Dictionary in group:
			if not _same_sync_contract(first, member.command.args): consistent = false
		if not consistent: continue
		var drill: Dictionary = first.get("drill", {})
		var stage := str(drill.get("stage", ""))
		if stage == "entry" and not _drill_door_finished(str(drill.sync_id), str(drill.door_id)): continue
		if stage == "entry" and bool(first.get("auto_signal", false)):
			# The door action has already finished this tick, including charge
			# safety or the shotgun operator's retreat. A signal wait takes no
			# action time: prepare its now-active node here without advancing a
			# second movement or consuming the next tick's movement budget.
			for member: Dictionary in group:
				if member.command.state == "PENDING" and _active(member.unit) == member.command and _can_act(member.unit): _start_command(member.unit, member.command)
		if not _sync_group_ready(group):
			_sync_waits.erase(sync_id)
			continue
		var members: Array = []
		for member: Dictionary in group: members.append({"unit_id":str(member.unit.id),"command_id":str(member.command.id),"args":member.command.args.duplicate(true)})
		if _sync_members.get(sync_id,[]) != members:
			_sync_waits.erase(sync_id)
			_sync_members[sync_id] = members
			var old_request: Dictionary = _sync_requests.get(sync_id,{})
			if not old_request.is_empty() and not _signal_request_matches(group,old_request):
				_sync_requests.erase(sync_id)
				_sync_sources.erase(sync_id)
		if stage == "go_long" and not _drill_dominated(str(drill.sync_id)): continue
		_record_room_stack(group)
		if not _sync_waits.has(sync_id): _sync_waits[sync_id] = tick
		if tick < int(_sync_waits[sync_id]) + int(first.get("delay_ticks", 0)): continue
		var automatic := bool(first.get("auto_signal",false))
		var request: Dictionary = _sync_requests.get(sync_id,{})
		if not automatic and request.is_empty(): continue
		if not automatic and not _signal_request_matches(group,request):
			_sync_requests.erase(sync_id)
			_sync_sources.erase(sync_id)
			continue
		var sender: Dictionary = _sync_sender(group) if automatic else request.sender
		var received := _deliver_signal(group,sender,str(first.get("signal","A")),sync_id,automatic,{} if automatic else request.receipt)
		if received.is_empty(): continue
		if _sync_group(sync_id).is_empty():
			if stage == "entry": _register_room_entry(str(drill.sync_id), str(drill.door_id), str(drill.room_id))
			_sync_waits.erase(sync_id)
			_sync_requests.erase(sync_id)
			_sync_sources.erase(sync_id)
			_sync_members.erase(sync_id)

func _forecast_drill_open(command: Dictionary, assumed_open: Array) -> void:
	var drill: Dictionary = command.get("args", {}).get("drill", {})
	if str(drill.get("stage", "")) in ["entry", "domination", "guard", "go_long"]:
		var door_id := str(drill.get("door_id", ""))
		if not door_id.is_empty() and not assumed_open.has(door_id): assumed_open.append(door_id)

func _refresh_preview(unit: Dictionary) -> void:
	if _preview_batch_depth > 0:
		_preview_dirty_units[unit.id] = unit
		return
	var origin: Vector2 = _position(unit)
	var assumed_open: Array = []
	for command: Dictionary in unit["commands"]:
		if FINISHED.has(str(command["state"])):
			continue
		_forecast_drill_open(command, assumed_open)
		if bool(command.get("_started", false)):
			var active_path: Array = command.get("path", [])
			if not active_path.is_empty():
				origin = _point(active_path.back())
			if OPEN_COMMANDS.has(str(command["type"])):
				assumed_open.append(str(command["args"].get("door_id", "")))
			continue
		var args: Dictionary = command["args"]
		if command["type"] == "MOVE":
			command["path"] = nav.path(origin, _point(args["target"]), assumed_open)
			command["conditional"] = not assumed_open.is_empty()
			if not command["path"].is_empty():
				origin = _point(args["target"])
		elif DOOR_COMMANDS.has(str(command["type"])):
			var door: Dictionary = _find(doors, str(args["door_id"]))
			if not door.is_empty():
				command["path"] = nav.approach(origin, door, 0.85, assumed_open)
				if not command["path"].is_empty():
					origin = _point(command["path"].back())
				if OPEN_COMMANDS.has(str(command["type"])): assumed_open.append(str(door["id"]))
		elif command["type"] == "SECURE_CIVILIAN":
			var civilian: Dictionary = _find(civilians, str(args["civilian_id"]))
			if not civilian.is_empty():
				command["path"] = nav.approach(origin, civilian, 0.8, assumed_open)
				if not command["path"].is_empty():
					origin = _point(command["path"].back())
		elif command["type"] == "ARREST":
			var enemy: Dictionary = _find(enemies, str(args["enemy_id"]))
			if not enemy.is_empty() and bool(enemy.get("visible", false)):
				command["path"] = nav.approach(origin, enemy, 1.0, assumed_open)
				if not command["path"].is_empty(): origin = _point(command["path"].back())

func step(dt: float) -> void:
	if not result.is_empty() or dt <= 0.0 or not is_finite(dt):
		return
	if tick == 0:
		# Initial planning is free; a revision means editing after execution began.
		plan_revisions = 0
	dt = minf(dt, 0.1)
	time += dt
	tick += 1
	_room_tick_origins.clear()
	_room_busy_tick.clear()
	_room_fired_tick.clear()
	_room_contacts_tick.clear()
	for unit: Dictionary in units: _room_tick_origins[str(unit.id)] = _array_position(unit)
	_update_reload_covers()
	_update_tactical_effects(dt)
	for zone: Dictionary in _smoke_zones:
		zone["remaining"] = maxf(0.0, float(zone.remaining) - dt)
	_smoke_zones = _smoke_zones.filter(func(zone: Dictionary) -> bool: return float(zone.remaining) > 0.0)
	for unit: Dictionary in units:
		unit["_peek_remaining"] = maxf(0.0, float(unit.get("_peek_remaining", 0.0)) - dt)
		unit["camera_remaining"] = maxf(0.0, float(unit.get("camera_remaining", 0.0)) - dt)
	for actor: Dictionary in units + enemies + civilians:
		actor["velocity_x"] = 0.0
		actor["velocity_z"] = 0.0
	_advance_doors(dt)
	nav.begin_geometry_scope()
	_cleanup_reservations()
	for entity: Dictionary in units + enemies + civilians:
		_update_combat_state(entity, dt)
		entity["_cooldown"] = maxf(0.0, float(entity["_cooldown"]) - dt)
		entity["_reaction"] = maxf(0.0, float(entity["_reaction"]) - dt)
		var prior_stun: float = float(entity.get("stunned", 0.0))
		entity["stunned"] = maxf(0.0, prior_stun - dt)
		if prior_stun <= 0.0: entity["flash_recover_remaining"] = maxf(0.0, float(entity.get("flash_recover_remaining", 0.0)) - dt)
		if prior_stun > 0.0 and float(entity.stunned) <= 0.0 and entity.kind == "civilian":
			entity["status"] = str(entity.get("_pre_flash_status", "IDLE"))
		if float(entity["hp"]) <= 0.0:
			entity["status"] = "INCAPACITATED"
		elif float(entity["stunned"]) > 0.0:
			entity["status"] = "STUNNED"
		elif float(entity.get("flash_recover_remaining", 0.0)) > 0.0:
			entity["status"] = "RECOVERING"
	_update_flash_projectiles(dt)
	_update_frag_projectiles(dt)
	var ordered_units: Array = units.duplicate()
	ordered_units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for unit: Dictionary in ordered_units:
		if _can_act(unit):
			if not _unit_covering_reload(unit): _advance_command(unit, dt)
		elif float(unit.hp) <= 0.0:
			for command: Dictionary in unit.commands:
				_release_flash_barrier(command)
	_advance_sync_waits()
	for unit: Dictionary in units:
		if not unit.get("sector", {}).is_empty() and time >= float(unit.sector.get("until", 0.0)): unit["sector"] = {}
	_advance_civilians(dt)
	_update_footstep_stimuli(dt)
	_perception_time -= dt
	if _perception_time <= 0.0:
		_update_perception()
		_perception_time = 0.1
	_update_surrender(dt)
	for enemy: Dictionary in enemies:
		if _can_act(enemy):
			_advance_enemy(enemy, dt)
	for unit: Dictionary in units:
		if _can_act(unit):
			_combat(unit, enemies, false)
	for entity: Dictionary in units + enemies:
		_update_presentation_aim(entity)
		_update_presentation_turn(entity)
		_update_status_reason(entity)
	_sound_zones = _sound_zones.filter(func(zone: Dictionary) -> bool: return time - float(zone["time"]) < 3.0)
	_advance_interactive_targets(dt)
	doctrine.update(self, dt)
	_update_man_down()
	_update_reload_covers()
	_update_room_control(dt)
	doctrine.update_room_doctrine(self, dt)
	_check_result()
	nav.end_geometry_scope()

func _release_door_owner(unit_id: String, command_id: String = "") -> void:
	for door: Dictionary in doors:
		if str(door.get("owner_id", "")) != unit_id or (not command_id.is_empty() and str(door.get("owner_command_id", "")) != command_id):
			continue
		door["owner_id"] = ""
		door["owner_command_id"] = ""
		door["blocked"] = door["state"] == "OPENING"
		door["reason"] = "문 조작 대원을 기다리는 중" if door["blocked"] else ""
	var unit: Dictionary = _find(units, unit_id)
	if not unit.is_empty() and (command_id.is_empty() or _active(unit).get("id", "") == command_id):
		unit["_peek_remaining"] = 0.0
		unit["camera_remaining"] = 0.0

func _door_owner_valid(door: Dictionary) -> bool:
	if bool(door.get("_enemy_opening", false)):
		return _enemy_door_owner_valid(door)
	var owner: Dictionary = _find(units, str(door.get("owner_id", "")))
	if owner.is_empty() or not _can_act(owner):
		return false
	var command: Dictionary = _active(owner)
	var reach: float = 2.5 if door.has("_operator_clearance") else 0.9
	var handle3: Vector3 = DoorGeometry.handle_world(door, float(door.get("progress", 0.0)))
	var distance: float = minf(_position(owner).distance_to(DoorGeometry.handle_floor(door)), _position(owner).distance_to(Vector2(handle3.x, handle3.z)))
	return not command.is_empty() and command.get("id", "") == door.get("owner_command_id", "") and DOOR_COMMANDS.has(str(command.get("type", ""))) and command.get("state", "") in ["RUNNING", "WAITING"] and distance <= reach

func _door_sweep_shapes(door: Dictionary, target: float) -> Array:
	var current: float = float(door.get("progress", 0.0))
	var shapes: Array = []
	for sample: int in range(17):
		shapes.append(DoorGeometry.movement_obstacle(door, lerpf(current, target, float(sample) / 16.0)))
	return shapes

func _door_sweep_clear(door: Dictionary, position: Vector2, target: float, shapes: Array = []) -> bool:
	if shapes.is_empty(): shapes = _door_sweep_shapes(door, target)
	for shape: Dictionary in shapes:
		if DoorGeometry.obstacle_overlaps_actor(shape, position, Navigation.RADIUS + 0.015):
			return false
	return true

func _door_clearance_position(door: Dictionary, actor: Dictionary, target: float) -> Array:
	var origin: Vector2 = _position(actor)
	var sweep := _door_sweep_shapes(door, target)
	if _door_sweep_clear(door, origin, target, sweep):
		return []
	var normal: Vector2 = Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var across: Vector2 = Vector2.RIGHT if door.get("axis", "x") == "x" else Vector2.DOWN
	var side: float = 1.0 if (origin - _position(door)).dot(normal) >= 0.0 else -1.0
	var best: Vector2 = origin
	var best_distance: float = INF
	# The operator releases the latch and steps out of the authored sweep. Every
	# retreat stays on their original side and has a collision-free floor route.
	for depth: float in [0.45, 0.75, 1.05, 1.35, 1.65, 1.95, 2.15]:
		for lateral: float in [0.0, -0.35, 0.35, -0.7, 0.7, -1.0, 1.0]:
			var candidate: Vector2 = DoorGeometry.handle_floor(door) + normal * side * depth + across * lateral
			var distance: float = origin.distance_to(candidate)
			if distance >= best_distance or not _door_sweep_clear(door, candidate, target, sweep):
				continue
			if not nav.walkable(candidate) or not nav.segment_clear(origin, candidate, Navigation.RADIUS) or not _tactical_actor_space_clear(actor, candidate):
				continue
			best = candidate
			best_distance = distance
	return [best.x, best.y] if is_finite(best_distance) else []

func _move_door_operator(door: Dictionary, dt: float) -> bool:
	var destination: Array = door.get("_operator_clearance", [])
	if destination.size() != 2:
		return true
	var actor: Dictionary = _find(enemies if bool(door.get("_enemy_opening", false)) else units, str(door.get("owner_id", "")))
	if actor.is_empty():
		return false
	var origin: Vector2 = _position(actor)
	var candidate: Vector2 = origin.move_toward(_point(destination), 1.15 * float(actor.get("mobility_multiplier", 1.0)) * dt)
	if not nav.walkable(candidate) or not nav.segment_clear(origin, candidate, Navigation.RADIUS) or not _tactical_actor_space_clear(actor, candidate):
		actor["status"] = "WAITING"
		return false
	_movement_apply(actor, candidate, dt)
	actor["status"] = "MOVING" if candidate.distance_to(_point(destination)) > 0.035 else "OPENING"
	return candidate.distance_to(_point(destination)) <= 0.035

func _invalidate_door_navigation() -> void:
	if nav.has_method("invalidate_dynamic"):
		nav.call("invalidate_dynamic")
	else:
		nav.rebuild()
	for unit: Dictionary in units:
		_refresh_preview(unit)

func _door_yield_step(door: Dictionary, actor: Dictionary, requester: Dictionary, dt: float) -> void:
	var command := _active(actor)
	# A timed wait reserves time, not an unsafe point in the leaf's future arc.
	# Explicit position holds and signal stacks still retain their position.
	var timed_wait: bool = not bool(actor.get("hold_position", false)) and command.get("type", "") == "WAIT"
	if (_movement_is_held(actor) and not timed_wait) or not _can_act(actor) or int(actor.get("_movement_moved_tick", -1)) == tick:
		return
	var target: float = float(door.get("_open_target", 1.0))
	var destination: Array = actor.get("_door_yield_destination", []) if actor.get("_door_yield_id", "") == door.id else []
	if destination.is_empty() or not _door_sweep_clear(door, _point(destination), target):
		destination = _door_clearance_position(door, actor, target)
		actor["_door_yield_destination"] = destination
		actor["_door_yield_id"] = door.id
	if destination.is_empty():
		return
	var origin: Vector2 = _position(actor)
	var candidate: Vector2 = origin.move_toward(_point(destination), 1.15 * float(actor.get("mobility_multiplier", 1.0)) * dt)
	if not nav.walkable(candidate) or not nav.segment_clear(origin, candidate, Navigation.RADIUS) or not _tactical_actor_space_clear(actor, candidate):
		return
	_movement_apply(actor, candidate, dt)
	actor["status"] = "YIELDING"
	actor["status_reason"] = str(requester.get("name", "대원")) + " 대원의 문 회전 공간을 비워주는 중"

func _advance_doors(dt: float) -> void:
	var changed: bool = false
	for door: Dictionary in doors:
		if door["state"] != "OPENING":
			continue
		if not _door_owner_valid(door):
			_release_door_owner(str(door.get("owner_id", "")), str(door.get("owner_command_id", "")))
			door["blocked"] = true
			door["reason"] = "문 조작 대원을 기다리는 중"
			continue
		var owner: Dictionary = _find(enemies if bool(door.get("_enemy_opening", false)) else units, str(door.get("owner_id", "")))
		if owner.get("kind", "") == "unit":
			var sweep := _door_sweep_shapes(door, float(door.get("_open_target", 1.0)))
			for enemy: Dictionary in enemies:
				if enemy.get("_door_knockdown_id", "") == door.id:
					_advance_door_knockdown(door, enemy, dt)
			for bystander: Dictionary in units:
				if bystander.id != owner.id and not _door_sweep_clear(door, _position(bystander), float(door.get("_open_target", 1.0)), sweep):
					_door_yield_step(door, bystander, owner, dt)
		if not _move_door_operator(door, dt):
			door["blocked"] = true
			door["reason"] = "문 회전 공간에서 물러나는 중"
			continue
		var start: float = float(door["progress"])
		var target: float = float(door.get("_open_target", 1.0))
		var next: float = minf(target, start + dt / float(door.get("_open_duration", 0.8)))
		# Subsample the swept leaf, independently from its navigation-grid cache.
		var blocked: bool = false
		var actors: Array = units + enemies + civilians
		for sample: int in range(1, 9):
			var progress: float = lerpf(start, next, float(sample) / 8.0)
			var shape := DoorGeometry.movement_obstacle(door, progress)
			for actor: Dictionary in actors:
				if float(actor.get("hp", 100.0)) > 0.0 and DoorGeometry.obstacle_overlaps_actor(shape, _position(actor), Navigation.RADIUS):
					blocked = true
					break
			if blocked:
				break
			door["progress"] = progress
		door["blocked"] = blocked
		door["reason"] = "문 회전 공간이 막혀 대기 중" if blocked else ""
		if float(door["progress"]) >= target:
			door["state"] = "OPEN" if target >= 1.0 else "AJAR"
			if target >= 1.0:
				door["owner_id"] = ""
				door["owner_command_id"] = ""
			door["blocked"] = false
			door["reason"] = ""
			changed = true
			if target >= 1.0:
				_event("DOOR_OPEN", "출입문 개방 완료", _array_position(door), [], {"door_id": door["id"]})
		elif absf(float(door["progress"]) - float(door.get("_nav_progress", 0.0))) >= 0.08:
			changed = true
		if changed:
			door["_nav_progress"] = door["progress"]
	if changed:
		_invalidate_door_navigation()

func _advance_open_door(unit: Dictionary, command: Dictionary, dt: float) -> void:
	var door: Dictionary = _find(doors, str(command["args"]["door_id"]))
	if door.is_empty():
		_fail(unit, command, "문이 존재하지 않습니다")
		return
	var phase := str(command.get("phase", ""))
	if phase == "KICK_RECOVER":
		command["remaining"] = maxf(0.0, float(command.remaining) - dt)
		unit["status"] = "OPENING"
		if float(command.remaining) <= 0.0:
			if command.args.get("fallback", "") == "breach":
				_begin_charge_install(unit, command, door)
			else:
				_fail(unit, command, "문 차기에 실패했습니다. 다시 차거나 다른 방법을 선택하세요")
		return
	if phase in ["BREACH_INSTALL", "BREACH_RETREAT", "BREACH_SAFE_WAIT"]:
		_advance_charge_breach(unit, command, door, dt)
		return
	if phase in ["SHOTGUN_PREPARE", "SHOTGUN_RETREAT"]:
		_advance_shotgun_breach(unit, command, door, dt)
		return
	if door["state"] == "OPEN":
		_succeed(unit, command)
		return
	if bool(door.get("locked", false)) and command.type in ["OPEN_DOOR", "PEEK_DOOR"]:
		_fail(unit, command, "잠긴 문입니다. 강제 개방 또는 문 파괴가 필요합니다")
		return
	var owner_id: String = str(door.get("owner_id", ""))
	if command.type == "PEEK_DOOR" and bool(command.get("_peeking", false)) and owner_id == str(unit.id):
		_advance_peek(unit, command, door, dt)
		return
	if not owner_id.is_empty() and owner_id != str(unit["id"]):
		var owner: Dictionary = _find(units, owner_id)
		if not owner.is_empty() and _position(unit).distance_to(_position(owner)) <= 1.1:
			command["state"] = "WAITING"
			command["reason"] = str(owner["name"]) + " 대원의 문 조작을 기다리는 중"
			command["remaining"] = 0.0
			command["_progress_time"] = 0.0
			unit["status"] = "WAITING"
		else:
			unit["status"] = "MOVING"
			_follow_command_path(unit, command, dt)
		return
	if owner_id == str(unit["id"]) and door.get("owner_command_id", "") == command["id"]:
		command["remaining"] = (float(door.get("_open_target", 1.0)) - float(door["progress"])) * float(door.get("_open_duration", 0.8))
		command["reason"] = str(door.get("reason", ""))
		command["state"] = "WAITING" if bool(door.get("blocked", false)) else "RUNNING"
		if unit.get("status", "") != "MOVING": unit["status"] = "WAITING" if bool(door.get("blocked", false)) else "OPENING"
		return
	var interaction_reach: float = 0.65 if DoorGeometry.leaf_progress(float(door.get("progress", 0.0))) > 0.01 else 0.425
	if door["state"] == "AJAR" and door.has("_operator_clearance") and door.get("_clearance_operator_id", "") == unit.id: interaction_reach = 2.4
	var handle3: Vector3 = DoorGeometry.handle_world(door, float(door.get("progress", 0.0)))
	var handle_distance: float = minf(_position(unit).distance_to(DoorGeometry.handle_floor(door)), _position(unit).distance_to(Vector2(handle3.x, handle3.z)))
	if handle_distance > interaction_reach:
		unit["status"] = "MOVING"
		_follow_command_path(unit, command, dt)
		return
	if str(command.type) == "PEEK_DOOR":
		_advance_peek(unit, command, door, dt)
		return
	unit["facing"] = (DoorGeometry.handle_floor(door) - _position(unit)).angle()
	if command.type == "BREACH_DOOR":
		_begin_charge_install(unit, command, door)
		return
	if command.type == "SHOTGUN_BREACH":
		if not EquipmentCatalog.can_shotgun_breach(unit):
			_fail(unit, command, "활성 주무기 산탄총과 탄약이 필요합니다")
			return
		var stats := EquipmentCatalog.shotgun_breach_stats()
		command["phase"] = "SHOTGUN_PREPARE"
		command["remaining"] = float(stats.duration) * float(unit.get("action_multiplier", 1.0))
		command["_door_action_start"] = time
		command["_breach_entry_side"] = _door_side(door, _position(unit))
		door["owner_id"] = unit.id
		door["owner_command_id"] = command.id
		unit["status"] = "OPENING"
		_emit_sound(_position(door), float(stats.sound), "출입문 소리", "unit")
		_register_shotgun_exposure(unit, command, door, float(stats.sound))
		return
	var clearance: Array = _door_clearance_position(door, unit, 1.0)
	if clearance.is_empty() and not _door_sweep_clear(door, _position(unit), 1.0):
		_fail(unit, command, "문 회전 공간에서 안전하게 물러날 자리가 없습니다")
		return
	if command.type == "KICK_DOOR":
		_emit_sound(_position(door), 9.0, "출입문 소리", "unit")
		command["_door_action_start"] = time
		if _breach_rng.randf() >= MissionCatalog.kick_success_probability(door, mission.get("rooms", [])):
			command["phase"] = "KICK_RECOVER"
			command["remaining"] = 0.6
			door["owner_id"] = unit.id
			door["owner_command_id"] = command.id
			unit["status"] = "OPENING"
			_event("KICK_FAILED", "문 차기 실패", _array_position(door), [], {"door_id":door.id, "unit_id":unit.id, "radius":9.0, "kind":"KICK_DOOR"})
			return
		_door_sweep_knockdown(door)
		_door_force_action(unit, command, door)
		if bool(door.get("destroyed", false)): return
	door["state"] = "OPENING"
	door["owner_id"] = unit["id"]
	door["owner_command_id"] = command["id"]
	door["_enemy_opening"] = false
	door["_open_target"] = 1.0
	if not clearance.is_empty():
		door["_operator_clearance"] = clearance
		door["_clearance_operator_id"] = unit.id
	else:
		door.erase("_operator_clearance")
		door.erase("_clearance_operator_id")
	door["_open_duration"] = (0.4 if command.type == "KICK_DOOR" else 0.8) * (0.5 if unit.get("trait", "") == "breacher" else 1.0) * float(unit.get("action_multiplier", 1.0))
	door["blocked"] = false
	door["reason"] = ""
	command["state"] = "RUNNING"
	command["reason"] = ""
	command["remaining"] = (1.0 - float(door["progress"])) * float(door._open_duration)
	unit["status"] = "OPENING"
	var sound_radius: float = 9.0 if command.type == "KICK_DOOR" else 2.0
	if command.type != "KICK_DOOR": _emit_sound(_position(door), sound_radius, "출입문 소리", "unit")
	_event("DOOR_ACTION", "문 처리 · " + str(DOOR_ACTION_LABELS.get(command.type, command.type)), _array_position(door), [], {"door_id":door.id, "unit_id":unit.id, "radius":sound_radius, "kind":command.type})

func _door_side(door: Dictionary, position: Vector2) -> float:
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	return 1.0 if (position - _position(door)).dot(normal) >= 0.0 else -1.0

func _door_sweep_knockdown(door: Dictionary) -> void:
	var shapes := _door_sweep_shapes(door, 1.0)
	for enemy: Dictionary in enemies:
		if float(enemy.hp) <= 0.0 or _door_sweep_clear(door, _position(enemy), 1.0, shapes): continue
		enemy["stunned"] = maxf(0.6, float(enemy.get("stunned", 0.0)))
		enemy["status"] = "STUNNED"
		enemy["door_ready"] = false
		enemy["aim_progress"] = 0.0
		enemy.erase("_door_contact_prepared")
		enemy["_door_knockdown_id"] = door.id
		enemy["_door_knockdown_target"] = _door_clearance_position(door, enemy, 1.0)

func _advance_door_knockdown(door: Dictionary, enemy: Dictionary, dt: float) -> void:
	if _door_sweep_clear(door, _position(enemy), float(door.get("_open_target", 1.0))):
		enemy.erase("_door_knockdown_id")
		enemy.erase("_door_knockdown_target")
		return
	enemy["stunned"] = maxf(float(enemy.get("stunned", 0.0)), 0.6)
	var destination: Array = enemy.get("_door_knockdown_target", [])
	if destination.is_empty(): return
	var origin := _position(enemy)
	var candidate := origin.move_toward(_point(destination), 1.15 * dt)
	if nav.walkable(candidate) and nav.segment_clear(origin, candidate, Navigation.RADIUS) and _tactical_actor_space_clear(enemy, candidate): _movement_apply(enemy, candidate, dt)

func _begin_charge_install(unit: Dictionary, command: Dictionary, door: Dictionary) -> void:
	if int(unit.get("breaches", 0)) <= 0:
		_fail(unit, command, "문 파괴 장비가 없습니다")
		return
	command["phase"] = "BREACH_INSTALL"
	command["state"] = "RUNNING"
	command["remaining"] = 0.2 * float(unit.get("action_multiplier", 1.0))
	command["_door_action_start"] = time
	command["_breach_entry_side"] = _door_side(door, _position(unit))
	door["owner_id"] = unit.id
	door["owner_command_id"] = command.id
	unit["status"] = "OPENING"

func _breach_retreat_target(unit: Dictionary, door: Dictionary, side: float, shotgun: bool = false) -> Array:
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var across := Vector2(-normal.y, normal.x)
	var depth := BREACH_SAFE_DISTANCE + 0.15
	if shotgun:
		for teammate: Dictionary in units:
			if teammate.id != unit.id and float(teammate.hp) > 0.0 and _door_side(door, _position(teammate)) == side:
				depth = maxf(depth, (_position(teammate) - _position(door)).dot(normal) * side + 0.7)
	var best: Array = []
	var cost := INF
	for extra: float in [0.0, 0.4, 0.8, 1.2]:
		for lateral: float in [0.0, -0.5, 0.5, -1.0, 1.0, -1.5, 1.5]:
			var point := _position(door) + normal * side * (depth + extra) + across * lateral
			if not nav.walkable(point) or not _tactical_actor_space_clear(unit, point): continue
			var route := nav.path(_position(unit), point)
			if route.is_empty(): continue
			var value := _movement_route_length(_position(unit), route)
			if value < cost:
				cost = value
				best = [point.x, point.y]
	return best

func _begin_breach_retreat(unit: Dictionary, command: Dictionary, door: Dictionary, shotgun: bool) -> bool:
	var target := _breach_retreat_target(unit, door, float(command.get("_breach_entry_side", _door_side(door, _position(unit)))), shotgun)
	if target.is_empty():
		_fail(unit, command, "브리칭 뒤 안전하게 물러날 경로가 없습니다")
		return false
	command["phase"] = "SHOTGUN_RETREAT" if shotgun else "BREACH_RETREAT"
	command["_retreat_target"] = target
	command["path"] = nav.path(_position(unit), _point(target))
	command["path_cursor"] = 0
	command["_revision"] = nav.revision
	command["state"] = "RUNNING"
	command["remaining"] = 0.0
	return true

func _advance_charge_breach(unit: Dictionary, command: Dictionary, door: Dictionary, dt: float) -> void:
	if command.phase == "BREACH_INSTALL":
		command["remaining"] = maxf(0.0, float(command.remaining) - dt)
		unit["status"] = "OPENING"
		if float(command.remaining) <= 0.0:
			unit["breaches"] = int(unit.get("breaches", 0)) - 1
			breaches_used += 1
			command["_charge_consumed"] = true
			_begin_breach_retreat(unit, command, door, false)
		return
	if command.phase == "BREACH_RETREAT":
		unit["status"] = "MOVING"
		if not _follow_command_path(unit, command, dt): return
		command["phase"] = "BREACH_SAFE_WAIT"
		_event("BREACH_RETREAT", "장약 설치 대원 안전거리 확보", _array_position(door), _array_position(unit), {"door_id":door.id, "unit_id":unit.id, "kind":"BREACH_DOOR"})
	unit["status"] = "WAITING"
	command["state"] = "WAITING"
	command["reason"] = "안전거리 안 대원의 후퇴를 기다리는 중"
	if _breach_team_safe(door): _door_force_action(unit, command, door)

func _advance_shotgun_breach(unit: Dictionary, command: Dictionary, door: Dictionary, dt: float) -> void:
	if command.phase == "SHOTGUN_RETREAT":
		unit["status"] = "MOVING"
		if _follow_command_path(unit, command, dt):
			_event("BREACH_RETREAT", "산탄총 사수 후방 자리 확보", _array_position(door), _array_position(unit), {"door_id":door.id, "unit_id":unit.id, "kind":"SHOTGUN_BREACH"})
			_succeed(unit, command)
		return
	unit["status"] = "OPENING"
	command["remaining"] = maxf(0.0, float(command.remaining) - dt)
	if float(command.remaining) > 0.0: return
	if not EquipmentCatalog.can_shotgun_breach(unit):
		_fail(unit, command, "활성 주무기 산탄총과 탄약이 필요합니다")
		return
	unit["ammo"] = int(unit.ammo) - 1
	_store_weapon_resource(unit)
	command["_round_consumed"] = true
	var stats := EquipmentCatalog.shotgun_breach_stats()
	_emit_sound(_position(door), float(stats.sound), "출입문 소리", "unit")
	if _breach_rng.randf() >= float(stats.success):
		_fail(unit, command, "산탄총 브리칭에 실패했습니다. 다른 방법을 선택하세요")
		return
	_door_force_action(unit, command, door)
	if command.state != "FAILED": _begin_breach_retreat(unit, command, door, true)

func _door_force_action(unit: Dictionary, command: Dictionary, door: Dictionary) -> void:
	var breach: bool = command.type == "BREACH_DOOR" or bool(command.get("_charge_consumed", false))
	var shotgun: bool = command.type == "SHOTGUN_BREACH"
	door["hp"] = maxf(0.0, float(door.get("hp", 100.0)) - (1000.0 if breach or shotgun else 65.0))
	door["locked"] = false
	if float(door["hp"]) > 0.0: return
	door["destroyed"] = true
	door["state"] = "OPEN"
	door["progress"] = 1.0
	door["owner_id"] = ""
	door["owner_command_id"] = ""
	door["blocked"] = false
	door["reason"] = ""
	var radius: float = 14.0 if breach or shotgun else 9.0
	var kind := "BREACH_DOOR" if breach else str(command.type)
	_emit_sound(_position(door), radius, "출입문 파손 소리", "unit")
	_event("DOOR_ACTION", "문 처리 · " + str(DOOR_ACTION_LABELS.get(kind, kind)), _array_position(door), [], {"door_id":door.id, "unit_id":unit.id, "radius":radius, "kind":kind})
	_event("DOOR_DESTROYED", "출입문 파손", _array_position(door), [], {"door_id":door.id, "unit_id":unit.id})
	_event("DOOR_OPEN", "파손된 출입문 통행 가능", _array_position(door), [], {"door_id":door.id})
	_invalidate_door_navigation()
	if not shotgun: _succeed(unit, command)

func _active(unit: Dictionary) -> Dictionary:
	for command: Dictionary in unit["commands"]:
		if not FINISHED.has(str(command["state"])):
			return command
	return {}

func _advance_command(unit: Dictionary, dt: float) -> void:
	var command: Dictionary = _active(unit)
	if command.is_empty():
		unit["status"] = "READY"
		return
	if command["state"] == "FAILED":
		unit["status"] = "BLOCKED"
		return
	if command.type not in ["FACE", "WAIT", "WAIT_FOR_SIGNAL"]: _room_busy_tick[str(unit.id)] = true
	if not bool(command["_started"]):
		_start_command(unit, command)
		if command["state"] in ["FAILED", "SUCCEEDED"]:
			return
	command["_elapsed"] = float(command["_elapsed"]) + dt
	var type: String = command["type"]
	var args: Dictionary = command["args"]
	match type:
		"MOVE":
			unit["status"] = "MOVING"
			if _follow_command_path(unit, command, dt):
				_succeed(unit, command)
		"FACE":
			if bool(args.get("unlock", false)):
				unit["facing_locked"] = false
				unit["facing_persistent"] = false
				_succeed(unit, command)
				return
			var direction: Vector2 = _point(args["target"]) - _position(unit)
			if args.has("stance"):
				unit["stance"] = str(args.stance)
				_refresh_weapon_state(unit)
			if direction.length_squared() > 0.001:
				unit["facing"] = direction.angle()
			unit["facing_locked"] = true
			unit["facing_persistent"] = bool(args.get("persistent", false))
			_succeed(unit, command)
		"WAIT":
			unit["status"] = "WAITING"
			command["remaining"] = maxf(0.0, float(command["remaining"]) - dt)
			if float(command["remaining"]) <= 0.0:
				_succeed(unit, command)
		"WAIT_FOR_SIGNAL":
			command["state"] = "WAITING"
			unit["status"] = "SIGNAL_" + str(args.get("signal", "A"))
		"OPEN_AND_FLASH":
			_advance_open_and_flash(unit, command, dt)
		"PEEK_CAMERA":
			_advance_camera(unit, command, dt)
		"SWITCH_WEAPON":
			unit["status"] = "SWITCHING"
			command["remaining"] = maxf(0.0, float(command["remaining"]) - dt)
			if float(command.remaining) <= 0.0:
				_switch_weapon_slot(unit, str(args.get("slot", "secondary")))
				_event("WEAPON_SWITCH", str(unit.name) + " · 무기 전환", _array_position(unit), [], {"unit_id": unit.id, "slot": unit.active_weapon, "weapon": unit.current_weapon})
				_succeed(unit, command)
		"OPEN_DOOR", "KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH":
			_advance_open_door(unit, command, dt)
		"RELOAD":
			unit["status"] = "RELOADING"
			command["remaining"] = maxf(0.0, float(command["remaining"]) - dt)
			unit["reload_remaining"] = command["remaining"]
			if float(command["remaining"]) <= 0.0:
				_finish_resource_reload(unit)
				reloads += 1
				_event("RELOAD", str(unit["name"]) + " · 재장전 완료", _array_position(unit), [], {"unit_id": unit["id"]})
				_succeed(unit, command)
		"THROW_STUN":
			_advance_flash_throw(unit, command, dt)
		"THROW_FRAG":
			_advance_frag_throw(unit, command, dt)
		"THROW_SMOKE":
			unit["status"] = "THROWING"
			command["remaining"] = maxf(0.0, float(command["remaining"]) - dt)
			if float(command["remaining"]) <= 0.0:
				_detonate_smoke(unit, command)
		"ARREST":
			_advance_arrest(unit, command, dt)
		"SECURE_CIVILIAN":
			var civilian: Dictionary = _find(civilians, str(args["civilian_id"]))
			if bool(civilian["secured"]):
				civilian["follow_unit_id"] = unit.id
				civilian["status"] = "FOLLOW"
				_succeed(unit, command)
			elif float(civilian["hp"]) <= 0.0:
				_fail(unit, command, "민간인을 확보할 수 없습니다")
			elif _position(unit).distance_to(_position(civilian)) > 1.1 or not nav.segment_clear(_position(unit), _position(civilian)):
				var path: Array = command.get("path", [])
				if path.is_empty() or _point(path.back()).distance_to(_position(civilian)) > 1.05:
					_repath(unit, command)
				unit["status"] = "MOVING"
				_follow_command_path(unit, command, dt)
			else:
				unit["status"] = "SECURING"
				command["remaining"] = maxf(0.0, float(command["remaining"]) - dt)
				if float(command["remaining"]) <= 0.0:
					civilian["secured"] = true
					civilian["status"] = "FOLLOW"
					civilian["follow_unit_id"] = unit.id
					if _p5_active: observed_statistics.control("secure", civilian, tick)
					_record_room_control(civilian, unit, "secure")
					_event("CIVILIAN_SECURED", "민간인 안전 확보", _array_position(civilian), [], {"civilian_id": civilian["id"], "unit_id": unit["id"]})
					_succeed(unit, command)

func _start_command(unit: Dictionary, command: Dictionary) -> void:
	_mark_deployed(unit)
	command["_started"] = true
	command["started_tick"] = tick
	command["state"] = "RUNNING"
	command["_elapsed"] = 0.0
	command["_blocked"] = 0.0
	command["_progress_time"] = 0.0
	command["_progress_best"] = INF
	command["_progress_cursor"] = -1
	command["path_cursor"] = 0
	command["_revision"] = nav.revision
	var args: Dictionary = command["args"]
	if args.has("sector"):
		var sector: Dictionary = args.sector
		unit["sector"] = {"start": float(sector.start), "end": float(sector.end), "until": time + float(sector.duration)} if float(sector.duration) > 0.0 else {}
	# A normal look belongs to this stop. Only explicit strafe facing survives
	# a new movement or an approach to a door/person. Queuing does not release it.
	if (command["type"] == "MOVE" or DOOR_COMMANDS.has(str(command["type"])) or command["type"] in ["SECURE_CIVILIAN", "ARREST"]) and not bool(unit.get("facing_persistent", false)):
		unit["facing_locked"] = false
	match str(command["type"]):
		"MOVE":
			command["path"] = nav.path(_position(unit), _point(args["target"]))
		"OPEN_DOOR", "KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "OPEN_AND_FLASH", "PEEK_CAMERA":
			var door: Dictionary = _find(doors, str(args["door_id"]))
			if command.type == "BREACH_DOOR" and int(unit.get("breaches", 0)) <= 0:
				_fail(unit, command, "문 파괴 장비가 없습니다")
				return
			if command.type == "SHOTGUN_BREACH" and not EquipmentCatalog.can_shotgun_breach(unit):
				_fail(unit, command, "활성 주무기 산탄총과 탄약이 필요합니다")
				return
			if command.type in ["OPEN_AND_FLASH", "PEEK_CAMERA"]:
				if command.type == "OPEN_AND_FLASH" and (int(unit.stuns) <= 0 or mission.get("modifiers", []).has("no_stun")):
					_fail(unit, command, "섬광탄이 없습니다")
					return
				command["phase"] = "APPROACH"
				command["path"] = nav.approach(_position(unit), door, 0.85)
			elif door["state"] == "OPEN":
				_succeed(unit, command)
			else:
				command["path"] = nav.approach(_position(unit), door, 0.85)
		"WAIT":
			command["remaining"] = float(args.get("duration", 1.0))
		"WAIT_FOR_SIGNAL":
			command["state"] = "WAITING"
		"SWITCH_WEAPON":
			if str(args.get("slot", "secondary")) == str(unit.get("active_weapon", "primary")):
				_succeed(unit, command)
			else:
				var destination_weapon: String = str(unit.get("sidearm", "none")) if str(args.get("slot", "secondary")) == "secondary" else str(unit.weapon)
				var destination_stats: Dictionary = EquipmentCatalog.weapon_stats(destination_weapon, unit.get("attachments", []) if str(args.get("slot", "secondary")) == "primary" else [])
				command["remaining"] = float(destination_stats.get("switch_time", 0.35)) * float(unit.get("action_multiplier", 1.0))
				unit["aim_progress"] = 0.0
		"RELOAD":
			if int(unit["ammo"]) >= int(unit["max_ammo"]):
				_succeed(unit, command)
			elif int(unit.get("reserve_ammo", 0)) <= 0:
				_fail(unit, command, "예비 탄약이 없습니다")
			else:
				command["remaining"] = _begin_resource_reload(unit)
		"THROW_FRAG":
			var frag_reason := _frag_runtime_reason(unit, _point(args.target))
			if not frag_reason.is_empty():
				_fail(unit, command, frag_reason)
			else:
				command["phase"] = "PREPARE"
				command["remaining"] = float(EquipmentCatalog.frag_stats().prepare)
		"THROW_STUN", "THROW_SMOKE":
			if int(unit.get("stuns" if command.type == "THROW_STUN" else "smokes", 0)) <= 0:
				_fail(unit, command, "상태 효과 장비가 없습니다")
			elif _position(unit).distance_to(_point(args["target"])) > 8.0:
				_fail(unit, command, "투척 범위 8m를 벗어났습니다")
			elif command.type == "THROW_SMOKE" and not nav.segment_clear(_position(unit), _point(args["target"])):
				_fail(unit, command, "벽 또는 닫힌 문이 투척 경로를 막습니다")
			elif command.type == "THROW_STUN" and _flash_release_origin(unit, _point(args["target"])).is_empty():
				_fail(unit, command, "벽 또는 닫힌 문이 투척 경로를 막습니다")
			else:
				command["phase"] = "PREPARE"
				command["remaining"] = 0.45 * float(unit.get("action_multiplier", 1.0))
		"SECURE_CIVILIAN":
			var civilian: Dictionary = _find(civilians, str(args["civilian_id"]))
			command["remaining"] = (0.6 if unit.get("trait", "") == "rescuer" else 1.2) * float(unit.get("action_multiplier", 1.0))
			command["path"] = nav.approach(_position(unit), civilian, 0.8)
		"ARREST":
			var enemy: Dictionary = _find(enemies, str(args["enemy_id"]))
			command["remaining"] = 2.0 * float(unit.get("action_multiplier", 1.0))
			command["path"] = nav.approach(_position(unit), enemy, 1.0)

func _follow_command_path(unit: Dictionary, command: Dictionary, dt: float) -> bool:
	if int(unit.get("_movement_moved_tick", -1)) == tick: return false
	if time < float(unit.get("_movement_lane_hold_until", -1.0)):
		if _recover_formation_lane_hold(unit,command): return false
		command["state"] = "WAITING"
		command["reason"] = "맞은편 대원이 지나갈 간격 유지 중"
		unit["status"] = "YIELDING"
		_movement_stop(unit)
		return false
	if bool(unit.get("hold_position", false)):
		command["state"] = "WAITING"
		command["reason"] = "위치 유지 명령 · 이동 보류"
		_movement_stop(unit)
		return false
	if int(command["_revision"]) != nav.revision:
		_repath(unit, command)
	if command["type"] == "MOVE" and not _drill_exact_destination(command) and not bool(command.get("_movement_destination_checked", false)):
		_movement_resolve_destination(unit, command)
	var path: Array = command["path"]
	if path.is_empty():
		command["state"] = "WAITING"
		unit["status"] = "BLOCKED"
		command["reason"] = "경로 확인 중 · 닫힌 문과 장애물을 확인하세요"
		command["_blocked"] = float(command["_blocked"]) + dt
		_movement_stop(unit)
		if float(command["_blocked"]) >= 1.5:
			var message := "이동 경로가 없습니다. 먼저 문을 열거나 목적지를 변경하세요"
			if command["type"] == "MOVE" and nav.blocked_by_leaf(_point(command["args"]["target"])):
				message = "목적지가 문짝과 겹칩니다. 문짝에서 떨어진 바닥을 지정하세요"
			_fail(unit, command, message)
		return false
	var cursor: int = int(command["path_cursor"])
	if cursor >= path.size():
		_movement_stop(unit)
		return true
	var position: Vector2 = _position(unit)
	if str(command.args.get("drill", {}).get("stage", "")) in ["entry", "domination"] and command.get("_drill_recovery_path", []) != path:
		# Navigation corners are route samples, not stops in an entry drill.
		# Look ahead only over an actually clear swept segment; the final
		# authored goal, speed limit and live body collision remain unchanged.
		while cursor + 1 < path.size() and position.distance_to(_point(path[cursor])) < _movement_body_spacing() and nav.segment_clear(position, _point(path[cursor + 1]), Navigation.RADIUS):
			cursor += 1
			command["path_cursor"] = cursor
	if command["type"] == "MOVE" and not _drill_exact_destination(command) and cursor == path.size() - 1 and position.distance_to(_point(command["args"]["target"])) < 1.25 and not command.has("resolved_target") and time >= float(command.get("_movement_destination_recheck_at", 0.0)):
		command["_movement_destination_recheck_at"] = time + 0.5
		_movement_resolve_destination(unit, command)
		path = command["path"]
		cursor = mini(int(command["path_cursor"]), path.size() - 1)
	var destination: Vector2 = _point(path[cursor])
	var temporary: Array = unit.get("_movement_detour", [])
	if not temporary.is_empty():
		destination = _point(temporary[0])
		if position.distance_to(destination) < 0.08:
			temporary.pop_front()
			unit["_movement_detour"] = temporary
			if not temporary.is_empty(): destination = _point(temporary[0])
			else: destination = _point(path[cursor])
	var distance_to_goal: float = position.distance_to(destination)
	if temporary.is_empty() and distance_to_goal < (0.02 if DOOR_COMMANDS.has(str(command["type"])) or command["type"] in ["SECURE_CIVILIAN", "ARREST"] else 0.08) and (cursor + 1 >= path.size() or nav.segment_clear(position, _point(path[cursor + 1]), Navigation.RADIUS)):
		command["path_cursor"] = cursor + 1
		if cursor + 1 >= path.size():
			_movement_stop(unit)
			return true
		return false
	var direction: Vector2 = (destination - position).normalized()
	var speed: float = _movement_speed(unit, 2.4 if unit["weapon"] == "light" else 2.16, direction, distance_to_goal, dt)
	var amount: float = minf(speed * dt, distance_to_goal)
	var candidate: Vector2 = position + direction * amount
	var passage_clear: bool = _door_permission(unit, candidate)
	var blocker: Dictionary = _unit_blocker(unit, candidate)
	var can_move: bool = passage_clear and blocker.is_empty() and nav.walkable(candidate) and nav.segment_clear(position, candidate, Navigation.RADIUS)
	if not passage_clear:
		var queue_advanced := false
		var occupant := _movement_find_actor(str(unit.get("_movement_door_blocker", "")))
		if not occupant.is_empty() and (_active(occupant).is_empty() or _active(occupant).get("state", "") == "FAILED") and _movement_has_priority(unit,occupant):
			_movement_yield(occupant,unit,destination,dt)
		var queue: Array = unit.get("_movement_queue_point", [])
		if queue.size() == 2:
			var queue_point := _point(queue)
			var queued_candidate := position.move_toward(queue_point, amount)
			if nav.walkable(queued_candidate) and nav.segment_clear(position, queued_candidate, Navigation.RADIUS) and _unit_space_clear(unit, queued_candidate):
				_movement_apply(unit, queued_candidate, dt)
				queue_advanced = true
		if not queue_advanced: _movement_stop(unit)
		command["state"] = "WAITING"
		command["reason"] = "문 통행 순서 대기 · 조작자와 통로 간격 확보"
		unit["status"] = "WAITING"
		command["_progress_time"] = 0.0
		return false
	if not blocker.is_empty():
		command["_traffic_wait"] = float(command.get("_traffic_wait", 0.0)) + dt
		command["_progress_time"] = 0.0
		var own_drill: Dictionary = command.args.get("drill", {})
		var other_drill: Dictionary = _active(blocker).get("args", {}).get("drill", {})
		var own_formation: Dictionary = command.args.get("formation",{})
		var other_formation: Dictionary = _active(blocker).get("args",{}).get("formation",{})
		if other_formation.is_empty() and _active(blocker).is_empty() and not blocker.get("commands",[]).is_empty(): other_formation = blocker.commands[-1].args.get("formation",{})
		var own_lane: Dictionary = own_formation if not own_formation.is_empty() else own_drill
		var other_lane: Dictionary = other_formation if not own_formation.is_empty() else other_drill
		if not temporary.is_empty() and str(own_lane.get("stage","")) in ["stack","move"] and not str(own_lane.get("sync_id","")).is_empty() and str(own_lane.sync_id) == str(other_lane.get("sync_id","")):
			if _formation_recovery_route_clear(unit,path.slice(cursor)):
				# Two cohort members may finish their previous avoidance legs at
				# the same time. Resume an original divergent leg only after its
				# whole live body/leaf sweep is clear; this tick performs no move.
				unit["_movement_detour"] = []
				command["state"] = "WAITING"
				command["reason"] = "변경된 통로를 다시 확인하는 중"
				_movement_stop(unit)
				return false
			var other_move := _active(blocker)
			if command.type == "MOVE" and other_move.get("type","") == "MOVE" and command.state == "WAITING" and other_move.get("state","") == "WAITING" and str(other_lane.get("stage","")) in ["stack","move"] and int(unit.get("_movement_moved_tick",-5)) < tick-1 and int(blocker.get("_movement_moved_tick",-5)) < tick-1 and time >= float(unit.get("_movement_dynamic_route_at",0.0)):
				# The old detour can itself become occupied. A stopped named
				# cohort may refresh it at the existing recovery cadence, only
				# with a complete live body/leaf-safe route to the original goal.
				unit["_movement_dynamic_route_at"] = time + 2.0
				var alternative := _movement_dynamic_route(unit,_point(path.back()))
				if not alternative.is_empty() and _point(alternative.back()).distance_to(_point(command.args.target)) < 0.00001 and _formation_recovery_route_clear(unit,alternative):
					command["path"] = alternative
					command["path_cursor"] = 0
					unit["_movement_detour"] = []
					command["state"] = "WAITING"
					command["reason"] = "점유된 통로를 피해 다른 경로로 이동 중"
					_movement_stop(unit)
					return false
		if not own_drill.is_empty() and str(own_drill.get("stage", "")) in ["entry", "domination"] and str(own_drill.get("sync_id", "")) == str(other_drill.get("sync_id", "")) and int(other_drill.get("order", 5)) < int(own_drill.order):
			# Follow the preceding teammate's lane instead of overtaking across
			# another entry lane. Swept collision remains the spacing authority.
			command["state"] = "WAITING"
			command["reason"] = "앞 대원의 진입 간격 유지 중"
			unit["status"] = "WAITING"
			_movement_stop(unit)
			return false
		if _movement_door_precedes(blocker, unit):
			command["state"] = "WAITING"
			command["reason"] = "앞 대원의 진입 간격 유지 중"
			unit["status"] = "WAITING"
			_movement_stop(unit)
			return false
		# A stopped person's body is avoided with a complete, validated detour;
		# the first leg is lateral, so a head-on blockage cannot reject it.
		if temporary.is_empty() and time >= float(unit.get("_movement_recovery_at", 0.0)):
			unit["_movement_recovery_at"] = time + 0.6
			var bypass: Array = _movement_bypass(unit, blocker, direction)
			if not bypass.is_empty():
				unit["_movement_detour"] = bypass
				command["reason"] = "앞 인물을 피해 우회 중"
				return false
		var timed_wait: bool = blocker.get("kind", "") == "unit" and _active(blocker).get("type", "") == "WAIT"
		# Escort traffic can occupy an old bypass after it was validated.
		if (temporary.is_empty() or (own_drill.is_empty() and own_formation.is_empty())) and not timed_wait and float(command["_traffic_wait"]) > 1.0 and time >= float(unit.get("_movement_dynamic_route_at", 0.0)):
			unit["_movement_dynamic_route_at"] = time + 2.0
			var alternative := _movement_dynamic_route(unit, _point(path.back()))
			if not alternative.is_empty():
				command["path"] = alternative
				command["path_cursor"] = 0
				unit["_movement_detour"] = []
				command["reason"] = "점유된 통로를 피해 다른 경로로 이동 중"
				return false
		if _movement_has_priority(unit, blocker):
			_movement_yield(blocker, unit, destination, dt)
		command["state"] = "WAITING"
		var blocker_name := str(blocker.get("name", "앞 인물")) if blocker.get("kind", "") == "unit" or bool(blocker.get("visible", false)) else "앞 인물"
		command["reason"] = blocker_name + ("의 위치 유지 · 다른 경로 확인 중" if _movement_is_held(blocker) else "과 통행 간격 조정 중")
		unit["status"] = "WAITING"
		_movement_stop(unit)
		return false
	if can_move:
		_movement_apply(unit, candidate, dt)
		if not bool(unit["facing_locked"]) and not _reacting_to_hit(unit):
			unit["facing"] = lerp_angle(float(unit["facing"]), direction.angle(), minf(1.0, dt * 13.0))
		command["state"] = "RUNNING"
		command["reason"] = "앞 인물을 피해 우회 중" if not temporary.is_empty() else str(command.get("_destination_reason", ""))
		command["_blocked"] = 0.0
		command["_traffic_wait"] = 0.0
		command["_progress_time"] = 0.0
	else:
		_movement_stop(unit)
		command["state"] = "WAITING"
		command["reason"] = "변경된 통로를 다시 확인하는 중"
		unit["status"] = "WAITING"
		command["_blocked"] = float(command["_blocked"]) + dt
		if float(command["_blocked"]) >= 0.8:
			unit["_movement_detour"] = []
			_repath(unit, command)
		if float(command["_blocked"]) >= 8.0:
			_fail(unit, command, "고정 장애물 때문에 통과할 수 없습니다. 목적지를 변경하세요")
	return false

func _recover_formation_lane_hold(unit: Dictionary, command: Dictionary) -> bool:
	var own: Dictionary = command.get("args",{}).get("formation",{})
	if own.is_empty(): return _recover_drill_entry_lane_hold(unit, command)
	if not _can_act(unit) or bool(unit.get("hold_position",false)) or command.get("type","") != "MOVE" or str(own.get("stage","")) != "stack" or str(own.get("sync_id","")).is_empty(): return false
	var lane: Array = unit.get("_movement_lane_goal",[])
	if lane.size() != 2 or _position(unit).distance_to(_point(lane)) > 0.02: return false
	var requester := _find(units,str(unit.get("_movement_lane_requester","")))
	if requester.is_empty() or not _can_act(requester) or bool(requester.get("hold_position",false)): return false
	var other_command := _active(requester)
	var other: Dictionary = other_command.get("args",{}).get("formation",{})
	if other_command.get("type","") != "MOVE" or str(other.get("stage","")) != "stack" or str(other.get("sync_id","")) != str(own.sync_id): return false
	if command.get("state","") != "WAITING" or other_command.get("state","") != "WAITING" or float(other_command.get("_traffic_wait",0.0)) <= 1.0: return false
	if int(unit.get("_movement_moved_tick",-5)) >= tick-1 or int(requester.get("_movement_moved_tick",-5)) >= tick-1 or time < float(unit.get("_movement_dynamic_route_at",0.0)): return false
	unit["_movement_dynamic_route_at"] = time + 2.0
	var alternative := _movement_dynamic_route(unit,_point(command.args.target))
	if alternative.is_empty() or _point(alternative.back()).distance_to(_point(command.args.target)) >= 0.00001 or not _formation_recovery_route_clear(unit,alternative): return false
	# A stopped requester can renew a reached yield lane forever. Only a
	# complete body/leaf-safe departure may end that same-cohort hold. Its
	# original primitive goal and the single-tick movement budget are intact.
	command["path"] = alternative
	command["path_cursor"] = 0
	command["_revision"] = nav.revision
	command["_progress_time"] = 0.0
	unit["_movement_detour"] = []
	unit["_movement_lane_hold_until"] = -1.0
	unit["_formation_lane_departure"] = {"requester_id":str(requester.id),"requester_moved_tick":int(requester.get("_movement_moved_tick",-5)),"command_id":str(command.id),"sync_id":str(own.sync_id)}
	command["state"] = "WAITING"
	command["reason"] = "점유된 통로를 피해 다른 경로로 이동 중"
	_movement_stop(unit)
	return true

func _drill_entry_recovery_pair(unit: Dictionary, command: Dictionary, requester: Dictionary) -> Dictionary:
	if unit.get("kind", "") != "unit" or requester.get("kind", "") != "unit" or not _can_act(unit) or not _can_act(requester) or bool(unit.get("hold_position", false)) or bool(requester.get("hold_position", false)): return {}
	var other_command := _active(requester)
	var own: Dictionary = command.get("args", {}).get("drill", {})
	var other: Dictionary = other_command.get("args", {}).get("drill", {})
	if command.get("type", "") != "MOVE" or other_command.get("type", "") != "MOVE" or str(own.get("stage", "")) not in ["entry", "domination"] or str(other.get("stage", "")) not in ["entry", "domination"]: return {}
	if str(own.get("sync_id", "")).is_empty() or str(own.sync_id) != str(other.get("sync_id", "")) or str(own.get("door_id", "")) != str(other.get("door_id", "")) or str(own.get("room_id", "")) != str(other.get("room_id", "")) or int(own.get("order", 0)) <= int(other.get("order", 0)): return {}
	var door := _find(doors, str(own.get("door_id", "")))
	var room := _find(mission.get("rooms", []), str(own.get("room_id", "")))
	if door.is_empty() or room.is_empty() or not _drill_recovery_inside(door, room, _position(unit)) or not _drill_recovery_inside(door, room, _position(requester)): return {}
	return {"door":door,"room":room,"sync_id":str(own.sync_id)}

func _drill_recovery_inside(door: Dictionary, room: Dictionary, point: Vector2) -> bool:
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var sign := 1.0 if (_position(room) - _position(door)).dot(normal) >= 0.0 else -1.0
	return (point - _position(door)).dot(normal) * sign > 0.0

func _drill_entry_recovery_route_clear(unit: Dictionary, pair: Dictionary, route: Array) -> bool:
	if route.is_empty() or not _drill_recovery_inside(pair.door, pair.room, _position(unit)): return false
	for coordinate: Array in route:
		if not _drill_recovery_inside(pair.door, pair.room, _point(coordinate)): return false
	return _formation_recovery_route_clear(unit, route)

func _recover_drill_entry_lane_hold(unit: Dictionary, command: Dictionary) -> bool:
	var lane: Array = unit.get("_movement_lane_goal", [])
	if lane.size() != 2 or _position(unit).distance_to(_point(lane)) > 0.02: return false
	var requester := _find(units, str(unit.get("_movement_lane_requester", "")))
	var pair := _drill_entry_recovery_pair(unit, command, requester)
	if pair.is_empty(): return false
	var other_command := _active(requester)
	if command.get("state", "") != "WAITING" or other_command.get("state", "") != "WAITING" or float(other_command.get("_traffic_wait", 0.0)) <= 1.0 or int(unit.get("_movement_moved_tick", -5)) >= tick - 1 or int(requester.get("_movement_moved_tick", -5)) >= tick - 1 or time < float(unit.get("_movement_dynamic_route_at", 0.0)): return false
	unit["_movement_dynamic_route_at"] = time + 2.0
	var target := _point(command.args.target)
	# Leaving a reached yield lane begins laterally away from the stopped
	# requester. Every leg then stays inside the already crossed door plane.
	var alternative := _movement_bypass(unit, requester, (target - _position(unit)).normalized())
	if not alternative.is_empty():
		var suffix := nav.path(_point(alternative.back()), target)
		if suffix.is_empty(): alternative = []
		else: alternative.append_array(suffix)
	if alternative.is_empty() or _point(alternative.back()).distance_to(target) >= 0.00001 or not _drill_entry_recovery_route_clear(unit, pair, alternative):
		alternative = _movement_dynamic_route(unit, target)
	if alternative.is_empty() or _point(alternative.back()).distance_to(target) >= 0.00001 or not _drill_entry_recovery_route_clear(unit, pair, alternative): return false
	command["path"] = alternative
	command["path_cursor"] = 0
	command["_revision"] = nav.revision
	command["_progress_time"] = 0.0
	command["_drill_recovery_path"] = alternative.duplicate(true)
	unit["_movement_detour"] = []
	unit["_movement_lane_hold_until"] = -1.0
	unit["_formation_lane_departure"] = {"cohort_type":"drill_entry","requester_id":str(requester.id),"requester_moved_tick":int(requester.get("_movement_moved_tick", -5)),"requester_command_id":str(other_command.id),"command_id":str(command.id),"sync_id":str(pair.sync_id)}
	command["state"] = "WAITING"
	command["reason"] = "점유된 통로를 피해 다른 경로로 이동 중"
	_movement_stop(unit)
	return true

func _formation_recovery_route_clear(actor: Dictionary, route: Array) -> bool:
	if not _movement_route_clear(actor,route): return false
	var previous := _position(actor)
	for raw: Variant in route:
		var point := _point(raw)
		if not FormationDrill._floor_segment_clear(nav,previous,point): return false
		previous = point
	return true

func _drill_exact_destination(command: Dictionary) -> bool:
	var args: Dictionary = command.get("args",{})
	return str(args.get("drill",{}).get("stage","")) in ["stack","safe","entry","domination","go_long"] or str(args.get("formation",{}).get("stage","")) in ["stack","move"]

func _repath(unit: Dictionary, command: Dictionary) -> void:
	command["_revision"] = nav.revision
	command["path_cursor"] = 0
	command["_progress_cursor"] = -1
	command["_progress_time"] = 0.0
	unit["_movement_detour"] = []
	var args: Dictionary = command["args"]
	if command.has("_retreat_target") and command.get("phase", "") in ["BREACH_RETREAT", "SHOTGUN_RETREAT"]:
		command["path"] = nav.path(_position(unit), _point(command._retreat_target))
		return
	if command["type"] == "MOVE":
		command["path"] = nav.path(_position(unit), _point(args["target"]))
		command["_movement_destination_checked"] = false
		if not _drill_exact_destination(command): _movement_resolve_destination(unit, command)
	elif DOOR_COMMANDS.has(str(command["type"])):
		command["path"] = nav.approach(_position(unit), _find(doors, str(args["door_id"])), 0.85)
	elif command["type"] == "SECURE_CIVILIAN":
		command["path"] = nav.approach(_position(unit), _find(civilians, str(args["civilian_id"])), 0.8)
	elif command["type"] == "ARREST":
		command["path"] = nav.approach(_position(unit), _find(enemies, str(args["enemy_id"])), 1.0)

# Common live-body movement geometry. Dead bodies are presentation objects;
# live actors share one radius irrespective of faction and movement caller.
func _movement_body_spacing() -> float:
	return Navigation.RADIUS * 2.0 + 0.02

func _movement_find_actor(id: String) -> Dictionary:
	for collection: Array in [units, enemies, civilians]:
		var actor := _find(collection, id)
		if not actor.is_empty(): return actor
	return {}

func _movement_segment_distance_squared(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var delta := finish - start
	var fraction := clampf((point - start).dot(delta) / maxf(delta.length_squared(), 0.00000001), 0.0, 1.0)
	return point.distance_squared_to(start + delta * fraction)

func _movement_swept_blocker(actor: Dictionary, origin: Vector2, candidate: Vector2, prediction: bool = false) -> Dictionary:
	var spacing := _movement_body_spacing()
	var segment := candidate - origin
	var reach_squared := pow(segment.length() + spacing + (0.40 if prediction else 0.0), 2.0)
	var closest: Dictionary = {}
	var nearest: float = INF
	for collection: Array in [units, enemies, civilians]:
		for other: Dictionary in collection:
			if other.get("id", "") == actor.get("id", "") or float(other.get("hp", 0.0)) <= 0.0:
				continue
			var center := _position(other)
			var start_distance := origin.distance_squared_to(center)
			if start_distance > reach_squared: continue
			var end_distance := candidate.distance_squared_to(center)
			# Legacy spawn overlap can be escaped, but never made worse.
			if start_distance < spacing * spacing - 0.000001 and end_distance > start_distance + 0.000001 and (candidate - origin).dot(origin - center) >= -0.000001:
				continue
			var distance := _movement_segment_distance_squared(center, origin, candidate)
			if prediction and end_distance < start_distance:
				var own_velocity := segment.normalized() * float(actor.get("_movement_speed", 0.0))
				var relative := center - origin
				var relative_velocity := _movement_expected_velocity(other) - own_velocity
				if relative.dot(relative_velocity) < 0.0:
					distance = minf(distance, _movement_segment_distance_squared(Vector2.ZERO, relative, relative + relative_velocity * 0.12))
			if distance < spacing * spacing - 0.000001 and start_distance < nearest:
				closest = other
				nearest = start_distance
	return closest

func _movement_point_clear(actor: Dictionary, point: Vector2) -> bool:
	if not nav.walkable(point): return false
	var spacing := _movement_body_spacing() + 0.03
	for collection: Array in [units, enemies, civilians]:
		for other: Dictionary in collection:
			if other.get("id", "") != actor.get("id", "") and float(other.get("hp", 0.0)) > 0.0 and point.distance_squared_to(_position(other)) < spacing * spacing:
				return false
	return true

func _movement_route_clear(actor: Dictionary, route: Array) -> bool:
	var previous := _position(actor)
	for coordinate: Array in route:
		var point := _point(coordinate)
		if not nav.walkable(point) or not nav.segment_clear(previous, point, Navigation.RADIUS) or not _movement_swept_blocker(actor, previous, point).is_empty():
			return false
		previous = point
	return true

func _movement_bypass(actor: Dictionary, blocker: Dictionary, direction: Vector2) -> Array:
	var origin := _position(actor)
	var center := _position(blocker)
	var right := Vector2(-direction.y, direction.x)
	for side: float in [1.0, -1.0]:
		for clearance: float in [0.28, 0.51, 0.68, 0.95]:
			var offset := right * side * clearance
			var first := origin + offset
			var second := first + direction * maxf(0.0, (center - origin).dot(direction))
			var last := second + direction * 0.70
			var route: Array = [[first.x, first.y], [second.x, second.y], [last.x, last.y]]
			if _movement_route_clear(actor, route): return route
	return []

func _movement_dynamic_route(actor: Dictionary, destination: Vector2) -> Array:
	# Build a temporary grid only during sustained congestion. Static occupancy
	# remains cached; live bodies mark a few nearby cells each. The simulation's
	# regular navigation grid is never mutated by this recovery query.
	if _recovery_grid == null or _recovery_navigation != nav or _recovery_revision != nav.revision:
		_recovery_grid = nav._make_grid([])
		_recovery_navigation = nav
		_recovery_revision = nav.revision
		_recovery_body_cells.clear()
		_recovery_door_cells = nav._door_grid_cells([])
	else:
		var door_cells: Dictionary = nav._door_grid_cells([])
		for coordinate: Vector2i in _recovery_body_cells:
			_recovery_grid.set_point_solid(coordinate, nav._static_cell_solid(coordinate) or door_cells.has(coordinate))
		for coordinate: Vector2i in _recovery_door_cells:
			if not door_cells.has(coordinate):
				_recovery_grid.set_point_solid(coordinate, nav._static_cell_solid(coordinate))
		for coordinate: Vector2i in door_cells:
			_recovery_grid.set_point_solid(coordinate)
		_recovery_door_cells = door_cells
		_recovery_body_cells.clear()
	var astar := _recovery_grid
	var margin := _movement_body_spacing() + Navigation.CELL * 0.5
	for collection: Array in [units, enemies, civilians]:
		for other: Dictionary in collection:
			if other.get("id", "") == actor.get("id", "") or float(other.get("hp", 0.0)) <= 0.0: continue
			var center := _position(other)
			var low := nav.cell(center - Vector2.ONE * margin)
			var high := nav.cell(center + Vector2.ONE * margin)
			for y: int in range(maxi(astar.region.position.y, low.y), mini(astar.region.end.y - 1, high.y) + 1):
				for x: int in range(maxi(astar.region.position.x, low.x), mini(astar.region.end.x - 1, high.x) + 1):
					var cell := Vector2i(x, y)
					if astar.get_point_position(cell).distance_squared_to(center) < margin * margin:
						astar.set_point_solid(cell)
						_recovery_body_cells[cell] = true
	var origin := _position(actor)
	var start_cell := nav.cell(origin)
	if not astar.is_in_boundsv(start_cell): return []
	astar.set_point_solid(start_cell, false)
	_recovery_body_cells[start_cell] = true
	var target_cell := nav._nearest_cell(destination, astar)
	if target_cell.x < 0: return []
	var raw := astar.get_point_path(start_cell, target_cell)
	if raw.is_empty(): return []
	var points: Array[Vector2] = [origin]
	for index: int in range(1, raw.size()): points.append(raw[index])
	points.append(destination)
	var route: Array = []
	var cursor := 0
	while cursor < points.size() - 1:
		var next := -1
		for index: int in range(points.size() - 1, cursor, -1):
			if nav.walkable(points[index]) and nav.segment_clear(points[cursor], points[index], Navigation.RADIUS) and _movement_swept_blocker(actor, points[cursor], points[index]).is_empty():
				next = index
				break
		if next < 0: return []
		route.append([points[next].x, points[next].y])
		cursor = next
	return route

func _movement_is_held(actor: Dictionary) -> bool:
	if bool(actor.get("hold_position", false)): return true
	if _unit_covering_reload(actor): return true
	for door: Dictionary in doors:
		if str(door.get("owner_id", "")) == str(actor.get("id", "")) and not str(door.get("owner_id", "")).is_empty(): return true
	if actor.get("kind", "") == "unit":
		var command := _active(actor)
		if not command.is_empty() and command.get("type", "") in ["WAIT", "WAIT_FOR_SIGNAL", "FACE", "RELOAD", "THROW_STUN", "THROW_SMOKE", "THROW_FRAG", "SECURE_CIVILIAN", "ARREST"]:
			return true
	return actor.get("status", "") in ["OPENING", "STUNNED", "SECURING", "RELOADING", "THROWING"]

func _movement_has_priority(actor: Dictionary, blocker: Dictionary) -> bool:
	# Cooperation applies to squadmates; hostile/civilian bodies are avoided.
	if actor.get("kind", "") != "unit" or blocker.get("kind", "") != "unit" or _movement_is_held(blocker): return false
	var other_command := _active(blocker)
	if other_command.is_empty() and not blocker.get("commands",[]).is_empty():
		var cover: Dictionary = blocker.commands[-1]
		var own: Dictionary = _active(actor).get("args",{}).get("formation",{})
		var other: Dictionary = cover.args.get("formation",{})
		if cover.type == "FACE" and cover.state == "SUCCEEDED" and str(other.get("stage","")) == "cover" and not own.is_empty() and str(own.sync_id) == str(other.get("sync_id","")): return false
	if other_command.is_empty() or other_command.get("state", "") == "FAILED": return true
	var own_command := _active(actor)
	var own_formation: Dictionary = own_command.get("args",{}).get("formation",{})
	var other_formation: Dictionary = other_command.get("args",{}).get("formation",{})
	var departure: Dictionary = blocker.get("_formation_lane_departure",{})
	if not departure.is_empty() and str(departure.get("requester_id","")) == str(actor.id) and int(departure.get("requester_moved_tick",-6)) == int(actor.get("_movement_moved_tick",-5)) and str(departure.get("command_id","")) == str(other_command.get("id","")) and str(own_formation.get("stage","")) == "stack" and str(other_formation.get("stage","")) == "stack" and str(own_formation.get("sync_id","")) == str(departure.get("sync_id","")) and str(other_formation.get("sync_id","")) == str(departure.get("sync_id","")):
		# Let the validated departure run while this same requester is still
		# stopped. A different requester or actual movement restores priority.
		return false
	if str(departure.get("cohort_type", "")) == "drill_entry" and str(departure.get("requester_id", "")) == str(actor.id) and int(departure.get("requester_moved_tick", -6)) == int(actor.get("_movement_moved_tick", -5)) and str(departure.get("requester_command_id", "")) == str(own_command.get("id", "")) and str(departure.get("command_id", "")) == str(other_command.get("id", "")):
		var pair := _drill_entry_recovery_pair(blocker, other_command, actor)
		if not pair.is_empty() and str(pair.sync_id) == str(departure.get("sync_id", "")): return false
	var own_drill: Dictionary = own_command.get("args", {}).get("drill", {})
	var other_drill: Dictionary = other_command.get("args", {}).get("drill", {})
	if str(own_drill.get("stage", "")) in ["entry", "domination"] and str(other_drill.get("stage", "")) in ["entry", "domination"] and not str(own_drill.get("sync_id", "")).is_empty() and str(own_drill.sync_id) == str(other_drill.get("sync_id", "")) and own_command.get("state", "") == "WAITING" and other_command.get("state", "") == "WAITING" and int(actor.get("_movement_moved_tick", -5)) < tick - 1 and int(blocker.get("_movement_moved_tick", -5)) < tick - 1:
		# A later entrant waiting at the throat must yield to the earlier rank.
		return int(own_drill.order) < int(other_drill.order)
	if own_command.get("type","") == "MOVE" and other_command.get("type","") == "MOVE" and own_command.get("state","") == "WAITING" and other_command.get("state","") == "WAITING" and str(own_formation.get("stage","")) == "stack" and str(other_formation.get("stage","")) == "stack" and str(own_formation.get("sync_id","")) == str(other_formation.get("sync_id","")) and int(actor.get("_movement_moved_tick",-5)) < tick-1 and int(blocker.get("_movement_moved_tick",-5)) < tick-1:
		# Two stopped approach lanes can converge onto one temporary corner.
		# Neither actor is moving ahead of the other: tactical rank chooses
		# which one keeps its lane, using the existing swept-safe yield move.
		var own_rank := int(own_formation.get("order",0))
		var other_rank := int(other_formation.get("order",0))
		return own_rank < other_rank if own_rank != other_rank else str(actor.id) < str(blocker.id)
	var other_velocity := _movement_expected_velocity(blocker)
	var own_direction := (_point(_active(actor).get("args", {}).get("target", _array_position(blocker))) - _position(actor)).normalized()
	if own_command.get("args", {}).get("drill", {}).is_empty() and own_formation.is_empty() and not actor.get("_movement_detour", []).is_empty(): own_direction = _movement_expected_velocity(actor).normalized()
	if other_velocity.length_squared() > 0.01 and other_velocity.normalized().dot(own_direction) > 0.65:
		return false
	return str(actor.get("id", "")) < str(blocker.get("id", ""))

func _movement_expected_velocity(actor: Dictionary) -> Vector2:
	var velocity := Vector2(float(actor.get("velocity_x", 0.0)), float(actor.get("velocity_z", 0.0)))
	if velocity.length_squared() > 0.001: return velocity
	if not _can_act(actor) or _movement_is_held(actor): return Vector2.ZERO
	if actor.get("kind", "") == "unit" and not _movement_is_held(actor):
		var command := _active(actor)
		if not command.is_empty() and command.get("type", "") == "MOVE":
			var detour: Array = actor.get("_movement_detour", [])
			var route: Array = command.get("path", []) if detour.is_empty() else detour
			var cursor := int(command.get("path_cursor", 0)) if detour.is_empty() else 0
			var goal := _point(command["args"]["target"]) if cursor >= route.size() else _point(route[cursor])
			var factor: float = 0.72 if actor.get("movement_mode", "normal") == "careful" else (1.28 if actor.get("movement_mode", "normal") == "fast" else 1.0)
			return (goal - _position(actor)).normalized() * 2.16 * factor * float(actor.get("mobility_multiplier", 1.0))
	else:
		var route: Array = actor.get("_ai_path", [])
		var cursor := int(actor.get("_ai_cursor", 0))
		if cursor < route.size():
			var nominal := float(enemy_rules.get("patrol_speed", 0.84)) if actor.get("kind", "") == "enemy" else float(mission.get("civilian_follow_speed", 2.1))
			return (_point(route[cursor]) - _position(actor)).normalized() * nominal * float(actor.get("mobility_multiplier", 1.0))
	return velocity

func _movement_yield(actor: Dictionary, requester: Dictionary, destination: Vector2, dt: float) -> void:
	if _movement_is_held(actor) or not _can_act(actor) or int(actor.get("_movement_moved_tick", -1)) == tick:
		return
	var route: Array = actor.get("_movement_yield_route", [])
	var requester_id := str(requester.get("id", ""))
	if str(actor.get("_movement_yield_requester", "")) != requester_id:
		route = []
	var origin := _position(actor)
	if not route.is_empty() and not _movement_route_clear(actor, route): route = []
	if route.is_empty() and _movement_yield_lane(actor, requester, destination, dt): return
	while not route.is_empty() and origin.distance_to(_point(route[0])) < 0.07:
		route.pop_front()
	if route.is_empty() and time >= float(actor.get("_movement_yield_search_at", 0.0)):
		actor["_movement_yield_search_at"] = time + 0.75
		var best_score: float = INF
		var incoming := (_position(requester) - origin).normalized()
		# Nearby room/bay points are checked first. The line-distance rule also
		# lets opposing traffic back into a bay instead of oscillating head-on.
		for radius: float in [0.7, 1.2, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0]:
			for index: int in range(16):
				var offset := Vector2.from_angle(float(index) * TAU / 16.0) * radius
				var point := origin + offset
				if offset.dot(incoming) > 0.05 or not _movement_point_clear(actor, point): continue
				if _movement_segment_distance_squared(point, _position(requester), destination) < pow(_movement_body_spacing() + 0.12, 2.0): continue
				var candidate_route := nav.path(origin, point)
				if candidate_route.is_empty() or not _movement_route_clear(actor, candidate_route): continue
				var score := radius + absf(offset.dot(incoming)) * 0.15
				if score < best_score:
					best_score = score
					route = candidate_route
			if not route.is_empty(): break
	actor["_movement_yield_requester"] = requester_id
	actor["_movement_yield_route"] = route
	if route.is_empty(): return
	# Finish a validated bay departure instead of returning to the old lane.
	actor.erase("_movement_lane_goal")
	actor["_movement_lane_hold_until"] = -1.0
	var waypoint := _point(route[0])
	var candidate := origin.move_toward(waypoint, 1.3 * float(actor.get("mobility_multiplier", 1.0)) * dt)
	if nav.walkable(candidate) and nav.segment_clear(origin, candidate, Navigation.RADIUS) and _movement_swept_blocker(actor, origin, candidate).is_empty():
		_movement_apply(actor, candidate, dt)
		actor["status"] = "YIELDING"
		actor["status_reason"] = "통행을 위해 잠시 비켜서는 중"
		actor["_movement_detour"] = route.duplicate(true)

func _movement_yield_lane(actor: Dictionary, requester: Dictionary, destination: Vector2, dt: float) -> bool:
	if _active(actor).get("type", "") != "MOVE": return false
	var origin := _position(actor)
	var forward := (destination - _position(requester)).normalized()
	var lateral := Vector2(-forward.y, forward.x)
	var requester_id := str(requester.get("id", ""))
	var saved: Array = actor.get("_movement_lane_goal", [])
	var goal := _point(saved) if saved.size() == 2 and actor.get("_movement_lane_requester", "") == requester_id else origin - lateral * 0.28
	# A reached lane that still blocks a stopped requester needs a new bay.
	if origin.distance_to(goal) <= 0.02 and float(_active(requester).get("_traffic_wait", 0.0)) > 1.0 and int(actor.get("_movement_moved_tick", -5)) < tick - 1 and int(requester.get("_movement_moved_tick", -5)) < tick - 1: return false
	# Both sides require enough wall clearance; a one-body corridor instead
	# uses the bay/backtrack recovery. This never attempts an impossible squeeze.
	var requester_lane := _position(requester) + lateral * 0.28
	if not nav.walkable(goal) or not nav.walkable(requester_lane) or not nav.segment_clear(origin, goal, Navigation.RADIUS) or not nav.segment_clear(_position(requester), requester_lane, Navigation.RADIUS): return false
	if not _movement_swept_blocker(actor, origin, goal).is_empty(): return false
	actor["_movement_lane_goal"] = [goal.x, goal.y]
	actor["_movement_lane_requester"] = requester_id
	actor["_movement_lane_hold_until"] = time + 0.8
	if origin.distance_to(goal) > 0.02:
		var candidate := origin.move_toward(goal, 1.3 * float(actor.get("mobility_multiplier", 1.0)) * dt)
		_movement_apply(actor, candidate, dt)
	actor["status"] = "YIELDING"
	actor["status_reason"] = "맞은편 대원이 지나갈 간격 유지 중"
	return true

func _movement_destination_clear(actor: Dictionary, point: Vector2) -> bool:
	if not _movement_point_clear(actor, point): return false
	# A teammate en route already owns its chosen arrival space.
	var spacing := _movement_body_spacing() + 0.03
	for other: Dictionary in units:
		if other.id == actor.id or not _can_act(other): continue
		var command := _active(other)
		if command.get("type", "") != "MOVE" or command.get("state", "") == "FAILED" or not bool(command.get("_movement_destination_checked", false)): continue
		var destination: Array = command.get("resolved_target", command.args.target)
		if point.distance_to(_point(destination)) < spacing: return false
	return true

func _movement_resolve_destination(actor: Dictionary, command: Dictionary) -> void:
	command["_movement_destination_checked"] = true
	var requested := _point(command["args"]["target"])
	for other: Dictionary in units:
		if other.get("id", "") == actor.get("id", "") or requested.distance_to(_position(other)) >= _movement_body_spacing() + 0.03: continue
		var other_command := _active(other)
		if not _movement_is_held(other) and not other_command.is_empty() and other_command.get("type", "") == "MOVE" and _point(other_command["args"]["target"]).distance_to(requested) > 0.6:
			command["_movement_destination_checked"] = false
			return
	# Remote hidden people must not be revealed by an automatic path adjustment.
	# Resolve their occupancy only when the actor is close enough to encounter it.
	for collection: Array in [enemies, civilians]:
		for other: Dictionary in collection:
			if float(other.get("hp", 0.0)) > 0.0 and not bool(other.get("visible", false)) and requested.distance_to(_position(other)) < _movement_body_spacing() + 0.03 and (_position(actor).distance_to(requested) > 2.0 or not nav.segment_clear(_position(actor), _position(other))):
				command["_movement_destination_checked"] = false
				return
	if _movement_destination_clear(actor, requested):
		command.erase("_destination_reason")
		command.erase("resolved_target")
		return
	# Static invalid targets still use normal path errors; only live-body
	# occupancy is adjusted, so a wall never silently changes the destination.
	if not nav.walkable(requested): return
	var best_route: Array = []
	var best_point := requested
	for radius: float in [0.56, 0.8, 1.1, 1.5]:
		var candidates: Array = []
		for index: int in range(16):
			var point := requested + Vector2.from_angle(float(index) * TAU / 16.0) * radius
			if not _movement_destination_clear(actor, point): continue
			var score := _position(actor).distance_to(point) + radius * 2.0
			candidates.append([point, score, index])
		# The selected candidate depends on distance, not route length. Try the
		# same scores in order and stop at the first reachable one instead of
		# running A* for every other candidate that cannot beat it.
		candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]) if float(a[1]) != float(b[1]) else int(a[2]) < int(b[2]))
		for entry: Array in candidates:
			var route := nav.path(_position(actor), entry[0])
			if route.is_empty(): continue
			best_route = route
			best_point = entry[0]
			break
		if not best_route.is_empty(): break
	if best_route.is_empty(): return
	command["path"] = best_route
	command["path_cursor"] = 0
	command["resolved_target"] = [best_point.x, best_point.y]
	command["_destination_reason"] = "목적지에 인물이 있어 가장 가까운 빈 위치로 이동"
	command["completion_reason"] = command["_destination_reason"]
	_event("DESTINATION_ADJUSTED", str(actor.get("name", actor.get("id", "대원"))) + " · 목적지가 점유되어 인접한 빈 위치로 조정", [best_point.x, best_point.y], [], {"unit_id": actor.get("id", ""), "requested": [requested.x, requested.y], "resolved": [best_point.x, best_point.y]})

func _movement_door_crossing(unit: Dictionary, door: Dictionary) -> Dictionary:
	if unit.get("kind", "") != "unit" or float(unit.hp) <= 0.0: return {}
	var command := _active(unit)
	var approaching := DOOR_COMMANDS.has(str(command.get("type", ""))) and str(command.args.get("door_id", "")) == str(door.id)
	if approaching:
		var index: int = unit.commands.find(command) + 1
		command = unit.commands[index] if index < unit.commands.size() else {}
	var type := str(command.get("type", ""))
	if (type != "MOVE" and not DOOR_COMMANDS.has(type)) or command.get("state", "") == "FAILED" or not command.args.get("drill", {}).is_empty(): return {}
	var target: Vector2
	var next_door: Dictionary = {}
	if type == "MOVE": target = _point(command.args.target)
	else:
		next_door = _find(doors,str(command.args.get("door_id","")))
		if next_door.is_empty(): return {}
		target = _position(next_door)
	var origin := _position(unit)
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var side := 1.0 if (origin - _position(door)).dot(normal) >= 0.0 else -1.0
	# A latch approach can occupy the future leaf; its queued crossing is
	# already explicit even when that future pose has no path from this spot.
	if approaching and (target - _position(door)).dot(normal) * side < 0.0:
		return {"unit_id":str(unit.id),"command_id":str(command.id),"side":side}
	var route: Array = command.get("path", []).slice(int(command.get("path_cursor", 0)))
	if route.is_empty() and not bool(command.get("_started", false)):
		route = nav.path(origin, target, [str(door.id)]) if type == "MOVE" else nav.approach(origin,next_door,0.85,[str(door.id)])
	for coordinate: Array in route:
		var next := _point(coordinate)
		var start_depth := (origin - _position(door)).dot(normal) * side
		var end_depth := (next - _position(door)).dot(normal) * side
		if start_depth >= 0.0 and end_depth < 0.0:
			var crossing := origin.lerp(next, start_depth / (start_depth - end_depth))
			if absf((crossing - _position(door)).cross(normal)) <= DoorGeometry.width(door) * 0.5:
				return {"unit_id":str(unit.id),"command_id":str(command.id),"side":side}
		origin = next
	return {}

func _movement_refresh_door_queue(door: Dictionary) -> void:
	var key := str(door.id)
	if int(_movement_door_queue_ticks.get(key, -1)) == tick: return
	_movement_door_queue_ticks[key] = tick
	var queue: Array = _movement_door_queues.get(key, [])
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var retained: Array = []
	for entry: Dictionary in queue:
		var unit := _find(units, str(entry.unit_id))
		if unit.is_empty() or float(unit.hp) <= 0.0: continue
		var command := _find(unit.commands, str(entry.command_id))
		if command.is_empty() or FINISHED.has(str(command.state)) or command.state == "FAILED": continue
		if (_position(unit) - _position(door)).dot(normal) * float(entry.side) < -1.3: continue
		var active := _active(unit)
		if str(active.get("id", "")) != str(entry.command_id) and (not DOOR_COMMANDS.has(str(active.get("type", ""))) or str(active.args.get("door_id", "")) != key): continue
		retained.append(entry)
	var arrivals: Array = []
	for unit: Dictionary in units:
		if _position(unit).distance_to(_position(door)) > 4.5 or retained.any(func(entry: Dictionary) -> bool: return str(entry.unit_id) == str(unit.id)): continue
		var entry := _movement_door_crossing(unit, door)
		if not entry.is_empty(): arrivals.append(entry)
	# Admit simultaneous arrivals by physical approach order, then keep it fixed.
	arrivals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance := _position(_find(units, str(a.unit_id))).distance_squared_to(_position(door))
		var b_distance := _position(_find(units, str(b.unit_id))).distance_squared_to(_position(door))
		return a_distance < b_distance if not is_equal_approx(a_distance, b_distance) else str(a.unit_id) < str(b.unit_id))
	retained.append_array(arrivals)
	var operator_id := str(_flash_door_barriers.get(key, {}).get("unit_id", door.get("owner_id", "")))
	if operator_id.is_empty() and door.state != "OPEN": operator_id = str(_reservations.get(key, ""))
	# A designated door/flash operator must clear the door before its followers.
	for index: int in range(1, retained.size()):
		if str(retained[index].unit_id) == operator_id:
			var operator: Dictionary = retained[index]
			retained.remove_at(index)
			retained.push_front(operator)
			break
	if retained.is_empty(): _movement_door_queues.erase(key)
	else: _movement_door_queues[key] = retained

func _movement_door_precedes(front: Dictionary, follower: Dictionary) -> bool:
	for key: String in _movement_door_queues:
		var queue: Array = _movement_door_queues[key]
		var ahead: Dictionary = {}
		for entry: Dictionary in queue:
			if str(entry.unit_id) == str(front.id): ahead = entry
			if str(entry.unit_id) == str(follower.id) and not ahead.is_empty() and float(ahead.side) == float(entry.side): return true
	return false

func _movement_door_wait_distance(door: Dictionary) -> float:
	# Keep the operator's retreat free until opening is finished.
	return 2.65 if door.state != "OPEN" or not door.get("_operator_clearance", []).is_empty() else _movement_body_spacing() + 0.05

func _movement_set_door_queue(actor: Dictionary, door: Dictionary) -> void:
	actor["_movement_wait_door"] = str(door["id"])
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var center := _position(door)
	var depth := (_position(actor) - center).dot(normal)
	var side := 1.0 if depth >= 0.0 else -1.0
	var queue_distance := _movement_door_wait_distance(door)
	var squad_queue := not _drill_passage(actor, door).is_empty()
	for entry: Dictionary in _movement_door_queues.get(str(door.id), []):
		if str(entry.unit_id) == str(actor.id) and depth * float(entry.side) > 0.0: squad_queue = true
	if actor.get("kind", "") == "unit" and squad_queue:
		# Close the squad queue in its lane without pushing the front backward.
		if absf(depth) <= queue_distance: return
	else:
		# Escorts still retreat out of the throat so their leader can pass.
		var rank := 0
		for other: Dictionary in units + enemies + civilians:
			if float(other.get("hp", 0.0)) <= 0.0: continue
			if str(other.get("_movement_wait_door", "")) != str(door.id) or str(other.id) >= str(actor.id): continue
			if (_position(other) - center).dot(normal) * side >= 0.0: rank += 1
		queue_distance = (2.65 if door.state != "OPEN" or not door.get("_operator_clearance", []).is_empty() else 1.45) + float(rank) * 0.60
	var point := _position(actor) + normal * (side * queue_distance - depth)
	if nav.walkable(point) and nav.segment_clear(_position(actor), point, Navigation.RADIUS):
		actor["_movement_queue_point"] = [point.x, point.y]

func _movement_speed(actor: Dictionary, nominal: float, direction: Vector2, remaining: float, dt: float) -> float:
	var mode := str(actor.get("movement_mode", "normal"))
	var factor: float = 0.72 if mode == "careful" else (1.28 if mode == "fast" else 1.0)
	if str(actor.get("stance", "standing")) == "crouched": factor *= 0.62
	factor *= clampf(float(actor.get("mobility_multiplier", 1.0)), 0.1, 1.5)
	# A fixed watch direction is retained while the body translates; reverse
	# and lateral motion have independent mobility limits.
	if bool(actor.get("facing_locked", false)):
		var forward := Vector2.from_angle(float(actor.get("facing", 0.0)))
		var alignment := direction.dot(forward)
		factor *= 0.62 if alignment < -0.4 else (0.82 if alignment < 0.6 else 1.0)
	if tick - int(actor.get("_movement_moved_tick", -5)) <= 1:
		var turn := absf(angle_difference(float(actor.get("_movement_heading", direction.angle())), direction.angle()))
		factor *= lerpf(1.0, 0.45, clampf(turn / PI, 0.0, 1.0))
	var target := nominal * factor
	var previous := float(actor.get("_movement_speed", 0.0))
	if tick - int(actor.get("_movement_moved_tick", -5)) > 1: previous = 0.0
	var acceleration: float = 5.0 if mode == "careful" else 7.0
	var limited := minf(target, previous + acceleration * dt)
	limited = minf(limited, sqrt(maxf(0.0, remaining) * acceleration * 2.0))
	actor["_movement_speed"] = limited
	return limited

func _movement_apply(actor: Dictionary, candidate: Vector2, dt: float) -> void:
	var previous := _position(actor)
	var delta := candidate - previous
	_set_position(actor, candidate)
	actor["velocity_x"] = delta.x / maxf(dt, 0.000001)
	actor["velocity_z"] = delta.y / maxf(dt, 0.000001)
	actor["_movement_moved_tick"] = tick
	if delta.length_squared() > 0.0000001:
		actor["_movement_heading"] = delta.angle()
		if not _reacting_to_hit(actor):
			var desired := float(actor.get("facing", 0.0)) if bool(actor.get("facing_locked", false)) else delta.angle()
			actor["body_facing"] = lerp_angle(float(actor.get("body_facing", actor.get("facing", desired))), desired, minf(1.0, dt * 7.0))

func _movement_stop(actor: Dictionary) -> void:
	actor["velocity_x"] = 0.0
	actor["velocity_z"] = 0.0
	actor["_movement_speed"] = 0.0

func _unit_space_clear(unit: Dictionary, candidate: Vector2) -> bool:
	return _unit_blocker(unit, candidate).is_empty()

func _unit_blocker(unit: Dictionary, candidate: Vector2) -> Dictionary:
	return _movement_swept_blocker(unit, _position(unit), candidate, true)

func _door_permission(unit: Dictionary, candidate: Vector2) -> bool:
	unit.erase("_movement_queue_point")
	unit.erase("_movement_door_blocker")
	var command := _active(unit)
	var drill_door_id := str(command.get("args",{}).get("drill",{}).get("door_id",""))
	for door: Dictionary in doors:
		var center := _position(door)
		var cohort: Dictionary = _drill_passage(unit,door) if drill_door_id == str(door.id) else {}
		if not cohort.is_empty() and not _drill_passage_order_clear(unit,door,cohort,candidate):
			_movement_set_door_queue(unit, door)
			# Keep the authored stack/retreat lane free for earlier entrants.
			unit.erase("_movement_queue_point")
			return false
		if unit.get("kind", "") == "unit" and (candidate.distance_to(center) <= 4.5 or _movement_door_queues.has(str(door.id))):
			_movement_refresh_door_queue(door)
			var queue: Array = _movement_door_queues.get(str(door.id), [])
			for index: int in range(1, queue.size()):
				if str(queue[index].unit_id) != str(unit.id): continue
				var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
				var depth := (candidate - center).dot(normal) * float(queue[index].side)
				# Once through, finish clearing the throat without backing up.
				if (_position(unit) - center).dot(normal) * float(queue[index].side) <= 0.0: break
				var spacing := _movement_door_wait_distance(door)
				# Followers may approach closely without claiming the front operator's slot.
				if depth < maxf(spacing, 1.0 + Navigation.RADIUS + 0.05):
					_movement_set_door_queue(unit, door)
					return false
		var approaching := DOOR_COMMANDS.has(str(command.get("type", ""))) and str(command.get("args", {}).get("door_id", "")) == str(door["id"])
		var approach_radius := maxf(1.0, DoorGeometry.width(door) + Navigation.RADIUS) if door["state"] != "OPEN" and approaching else 1.0
		var near_door := DoorGeometry.funnel_rect(door,1.0).grow(Navigation.RADIUS).has_point(candidate) if door.state == "OPEN" else candidate.distance_to(center) <= approach_radius
		if not near_door:
			continue
		var key: String = str(door["id"])
		var barrier: Dictionary = _flash_door_barriers.get(key, {})
		if unit.get("kind", "") == "unit" and not barrier.is_empty() and str(barrier.get("unit_id", "")) != str(unit.id):
			_movement_set_door_queue(unit, door)
			return false
		var operator: String = str(door.get("owner_id", ""))
		if not operator.is_empty() and operator != str(unit["id"]):
			_movement_set_door_queue(unit, door)
			return false
		if door["state"] != "OPEN":
			if not approaching: continue
			# Reserve the latch approach before followers can occupy the operator's retreat.
			if _reservations.has(key) and _reservations[key] != unit["id"]:
				_movement_set_door_queue(unit, door)
				return false
			_reservations[key] = unit["id"]
			continue
		var portal: Rect2 = nav._rect(door,Navigation.RADIUS)
		if portal.has_point(candidate) and not portal.has_point(_position(unit)):
			for other: Dictionary in units + enemies + civilians:
				if other.get("id", "") != unit.id and float(other.get("hp",0.0)) > 0.0 and portal.has_point(_position(other)):
					if not cohort.is_empty() and str(_drill_passage(other, door).get("sync_id", "")) == str(cohort.sync_id): continue
					unit["_movement_door_blocker"] = str(other.id)
					_movement_set_door_queue(unit,door)
					return false
		if not cohort.is_empty():
			if not portal.has_point(candidate): continue
			var reserved := _movement_find_actor(str(_reservations.get(key, "")))
			if not reserved.is_empty() and reserved.id != unit.id and str(_drill_passage(reserved, door).get("sync_id", "")) != str(cohort.sync_id):
				_movement_set_door_queue(unit, door)
				return false
			# Ordered squad lanes share a wide portal; swept body collision still applies.
			for other: Dictionary in units + enemies + civilians:
				if other.id == unit.id or float(other.get("hp", 0.0)) <= 0.0: continue
				if str(_drill_passage(other, door).get("sync_id", "")) == str(cohort.sync_id): continue
				if _position(other).distance_to(center) < 0.65 and _position(unit).distance_to(center) > 0.8:
					_movement_set_door_queue(unit, door)
					return false
			_reservations[key] = unit.id
			continue
		if _reservations.has(key) and _reservations[key] != unit["id"]:
			_movement_set_door_queue(unit, door)
			return false
		# The current owner must be able to clear the throat past a close follower.
		if str(_reservations.get(key, "")) == str(unit.id): continue
		# A physically present person always owns the passage before an arrival.
		for other: Dictionary in units + enemies + civilians:
			if other.get("id", "") == unit["id"] or float(other.get("hp", 0.0)) <= 0.0:
				continue
			if _position(other).distance_to(center) < 0.65 and _position(unit).distance_to(center) > 0.8:
				_movement_set_door_queue(unit, door)
				return false
		_reservations[key] = unit["id"]
	unit.erase("_movement_wait_door")
	return true

func _drill_passage(unit: Dictionary, door: Dictionary) -> Dictionary:
	if unit.get("kind", "") != "unit": return {}
	var command := _active(unit)
	var drill: Dictionary = command.get("args", {}).get("drill", {})
	if command.get("type", "") != "MOVE" or str(drill.get("door_id", "")) != str(door.id) or str(drill.get("stage", "")) not in ["entry", "domination"]: return {}
	return drill

func _drill_passage_order_clear(unit: Dictionary, door: Dictionary, cohort: Dictionary, candidate: Vector2) -> bool:
	var room := _find(mission.get("rooms", []), str(cohort.room_id))
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var inside_sign := 1.0 if (_position(room) - _position(door)).dot(normal) >= 0.0 else -1.0
	if (_position(unit) - _position(door)).dot(normal) * inside_sign > 0.0: return true
	# Order applies at the doorway, while approach lanes may move concurrently.
	if (candidate - _position(door)).dot(normal) * inside_sign < -Navigation.RADIUS - float(door.get("d" if door.get("axis", "x") == "x" else "w", 0.2)) * 0.5: return true
	for other: Dictionary in units:
		if other.id == unit.id or float(other.hp) <= 0.0: continue
		var participant := false
		for command: Dictionary in other.commands:
			var drill: Dictionary = command.args.get("drill", {})
			if command.state != "CANCELLED" and command.type == "MOVE" and str(drill.get("sync_id", "")) == str(cohort.sync_id) and int(drill.get("order", 5)) < int(cohort.order) and str(drill.get("stage", "")) in ["entry", "domination"]:
				participant = true
				break
		if participant and (_position(other) - _position(door)).dot(normal) * inside_sign <= 0.0: return false
	return true

func _cleanup_reservations() -> void:
	for key: String in _movement_door_queues.keys():
		var queued_door := _find(doors, key)
		if not queued_door.is_empty(): _movement_refresh_door_queue(queued_door)
	for key: String in _reservations.keys():
		var actor: Dictionary = _movement_find_actor(str(_reservations[key]))
		var door: Dictionary = _find(doors, key)
		var reach := maxf(1.3, DoorGeometry.width(door) + Navigation.RADIUS + 0.3) if not door.is_empty() and door["state"] != "OPEN" else 1.3
		if actor.is_empty() or door.is_empty() or not _can_act(actor) or _position(actor).distance_to(_position(door)) > reach or _movement_is_held(actor):
			_reservations.erase(key)
		elif actor.get("kind", "") == "unit":
			var command := _active(actor)
			if command.is_empty() or command.get("state", "") == "FAILED" or command["type"] not in ["MOVE", "OPEN_DOOR", "KICK_DOOR", "PEEK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH", "OPEN_AND_FLASH", "PEEK_CAMERA", "SECURE_CIVILIAN", "ARREST"]:
				_reservations.erase(key)

func _succeed(unit: Dictionary, command: Dictionary) -> void:
	command["state"] = "SUCCEEDED"
	command["reason"] = ""
	command["remaining"] = 0.0
	command["completed_tick"] = tick
	unit["status"] = "INCAPACITATED" if float(unit["hp"]) <= 0.0 else ("STUNNED" if float(unit["stunned"]) > 0.0 else "READY")
	if _active(unit).is_empty():
		for door_id: String in _reservations.keys():
			if _reservations[door_id] == unit.id: _reservations.erase(door_id)

func _fail(unit: Dictionary, command: Dictionary, reason: String) -> void:
	if command["state"] == "FAILED":
		return
	_release_flash_barrier(command)
	command["state"] = "FAILED"
	command["reason"] = reason
	command["completed_tick"] = tick
	unit["status"] = "BLOCKED"
	_release_door_owner(str(unit["id"]), str(command["id"]))
	for door_id: String in _reservations.keys():
		if _reservations[door_id] == unit["id"]:
			_reservations.erase(door_id)
	pause_requested = true
	pause_reason = "command_failure"
	pause_unit_id = ""
	command_failures += 1
	_event("COMMAND_FAILED", str(unit["name"]) + " · " + reason, _array_position(unit), [], {"unit_id": unit["id"], "command_id": command["id"]})

func _available_stuns(unit: Dictionary, include_pending: bool) -> int:
	var available: int = int(unit.get("stuns", 0))
	if include_pending:
		for command: Dictionary in unit.get("commands", []):
			if not FINISHED.has(str(command.state)) and command.type in ["THROW_STUN", "OPEN_AND_FLASH"] and not command.has("projectile_id"):
				available -= 1
	return maxi(0, available)

func _available_frags(unit: Dictionary, include_pending: bool = true) -> int:
	var available := int(unit.get("frags", 0))
	if include_pending:
		for command: Dictionary in unit.get("commands", []):
			if not FINISHED.has(str(command.state)) and command.type == "THROW_FRAG" and not command.has("projectile_id"): available -= 1
	return maxi(0, available)

func frag_target_preview(unit_id: String, target: Array, options: Dictionary = {}) -> Dictionary:
	var unit := _find(units, unit_id)
	if unit.is_empty() or float(unit.hp) <= 0.0: return _rejected("행동 가능한 대원을 선택하세요")
	var reason := _validate("THROW_FRAG", {"target":target})
	if not reason.is_empty(): return _rejected(reason)
	for key: Variant in options:
		if key not in ["append", "index", "replace"]: return _rejected("명령에 지원하지 않는 인수가 있습니다")
	if (options.has("append") and not options.append is bool) or (options.has("replace") and not options.replace is bool): return _rejected("명령에 지원하지 않는 인수가 있습니다")
	var index := int(options.get("index", unit.commands.size()))
	if options.has("index") and not _drill_integer(options.index, 0, unit.commands.size()): return _rejected("명령 위치가 범위를 벗어났습니다")
	var append := bool(options.get("append", true))
	var view := unit.duplicate(false)
	view["commands"] = unit.commands.duplicate()
	if bool(options.get("replace", false)) and index < view.commands.size(): view.commands.remove_at(index)
	var available := _available_frags(view, append)
	if available <= 0: return _rejected("예약분을 제외한 파편 수류탄이 없습니다")
	# Prefix movement and leaf poses come only from the owned plan and observed
	# doors. Live hidden doors/NPCs never participate in this planning query.
	view["commands"] = unit.commands.slice(0, index)
	var saved := _begin_flash_planning_geometry()
	var projected := _project_movement_plan(view, append)
	var answer: Dictionary
	if not bool(projected.get("ok", false)):
		answer = _rejected(str(projected.get("message", "벽 또는 닫힌 문이 파편 수류탄 투척 경로를 막습니다")))
	else:
		var actor := unit.duplicate(false)
		actor.x = projected.origin.x
		actor.z = projected.origin.y
		actor.base_height = CombatSpatial.floor_base_at(_elevated_rooms, projected.origin)
		var point := _point(target)
		var source := _flash_release_origin(actor, point, projected.open)
		var profile := EquipmentCatalog.frag_stats()
		if projected.origin.distance_to(point) > float(profile.range): answer = _rejected("파편 수류탄 투척 범위 8m를 벗어났습니다")
		elif source.is_empty(): answer = _rejected("벽 또는 닫힌 문이 파편 수류탄 투척 경로를 막습니다")
		else: answer = {"ok":true, "source":source, "target":[point.x, point.y, CombatSpatial.floor_base_at(_elevated_rooms, point) + 0.10], "radius":profile.radius, "core_radius":profile.core_radius, "available_frags":available}
	_end_flash_planning_geometry(saved)
	return answer

func _frag_runtime_reason(unit: Dictionary, target: Vector2) -> String:
	if MissionCatalog.roe(mission) != "high_intensity": return "정밀 교전수칙에서는 파편 수류탄을 사용할 수 없습니다"
	if int(unit.get("frags", 0)) <= 0: return "예약분을 제외한 파편 수류탄이 없습니다"
	if _position(unit).distance_to(target) > float(EquipmentCatalog.frag_stats().range): return "파편 수류탄 투척 범위 8m를 벗어났습니다"
	if _flash_release_origin(unit, target).is_empty(): return "벽 또는 닫힌 문이 파편 수류탄 투척 경로를 막습니다"
	return ""

func _advance_frag_throw(unit: Dictionary, command: Dictionary, dt: float) -> void:
	if command.has("projectile_id"):
		command["phase"] = "WAIT_EXPLOSION"
		command["reason"] = "파편 수류탄 폭발까지 대기"
		unit["status"] = "WAITING"
		var projectile := _find(_frag_projectiles, str(command.projectile_id))
		if projectile.is_empty(): _succeed(unit, command)
		else: command["remaining"] = maxf(0.0, float(projectile.detonate_at) - time)
		return
	unit["status"] = "THROWING"
	command["remaining"] = maxf(0.0, float(command.remaining) - dt)
	if float(command.remaining) > 0.0: return
	var point := _point(command.args.target)
	if not _frag_runtime_reason(unit, point).is_empty():
		_fail(unit, command, "파편 수류탄 재고 또는 투척 경로가 변경되었습니다")
		return
	var source := _flash_release_origin(unit, point)
	var profile := EquipmentCatalog.frag_stats()
	var flight := maxf(0.12, _point(source).distance_to(point) / float(profile.flight_speed))
	var projectile := {"id":"frag-" + str(command.id), "unit_id":unit.id, "command_id":command.id, "source":source, "target":[point.x,point.y,CombatSpatial.floor_base_at(_elevated_rooms, point) + 0.10], "position":source.duplicate(), "released_at":time, "flight_duration":flight, "detonate_at":time + maxf(float(profile.fuse), flight + 0.10), "phase":"FLIGHT"}
	unit["frags"] = int(unit.frags) - 1
	frags_used += 1
	_frag_projectiles.append(projectile)
	command["projectile_id"] = projectile.id
	command["phase"] = "WAIT_EXPLOSION"
	command["remaining"] = float(projectile.detonate_at) - time
	_event("FRAG_RELEASE", str(unit.name) + " · 파편 수류탄 투척", [source[0],source[1]], [point.x,point.y], {"projectile_id":projectile.id,"unit_id":unit.id,"radius":profile.radius,"source_height":source[2],"target_height":projectile.target[2],"flight_duration":flight,"detonate_at":projectile.detonate_at,"observed":true})

func _update_frag_projectiles(_dt: float) -> void:
	var active: Array = []
	for projectile: Dictionary in _frag_projectiles:
		var source: Array = projectile.source
		var target: Array = projectile.target
		var fraction := clampf((time - float(projectile.released_at)) / float(projectile.flight_duration), 0.0, 1.0)
		var next := _flash_curve(Vector3(source[0],source[2],source[1]), Vector3(target[0],target[2],target[1]), fraction)
		var previous: Array = projectile.position
		if not _flash_segment_clear(Vector3(previous[0],previous[2],previous[1]), next):
			projectile["target"] = previous.duplicate()
			projectile["flight_duration"] = maxf(0.001, time - float(projectile.released_at))
			next = Vector3(previous[0],previous[2],previous[1])
			fraction = 1.0
		_break_flash_glass(Vector3(previous[0],previous[2],previous[1]), next, projectile)
		projectile["position"] = [next.x,next.z,next.y]
		projectile["phase"] = "FUSE" if fraction >= 1.0 else "FLIGHT"
		if time >= float(projectile.detonate_at): _explode_frag(projectile)
		else: active.append(projectile)
	_frag_projectiles = active

func _refresh_frag_observations() -> void:
	# This is a squad-only LOS refresh, not an extra AI/perception/RNG update.
	# Every NPC is refreshed, including undamaged actors with stale 10 Hz flags.
	for actor: Dictionary in enemies + civilians:
		actor["visible"] = _currently_observed(actor)
		if not bool(actor.visible): continue
		if actor.kind == "enemy": _remember_enemy_state(actor)
		else:
			actor["last_seen"] = _array_position(actor)
			actor["last_seen_time"] = time
			observed_statistics.observe(actor, tick)
			_record_room_observation(actor)

func _record_health_damage(actor: Dictionary, before: float, after: float) -> void:
	if actor.kind == "unit" or _currently_observed(actor):
		var fact := _room_person_fact(actor)
		fact["before"] = before
		fact["after"] = after
		doctrine.record_room_damage(fact)
	if not _p5_active: return
	var damage := maxf(0.0, before - after)
	if actor.kind == "unit": unit_damage += damage
	elif actor.kind == "civilian": civilian_damage += damage
	if actor.kind != "unit" and _currently_observed(actor): observed_statistics.observe_damage(actor, before, after, tick)

func _room_person_fact(actor: Dictionary) -> Dictionary:
	return {"tick":tick,"time":time,"room_id":room_control.room_at(_position(actor),float(actor.get("base_height",0.0))),"id":str(actor.id),"kind":str(actor.kind)}

func _record_room_observation(actor: Dictionary) -> void:
	# visible is sampled at 10 Hz. A metric receipt always checks the current
	# physical observation instead of reading a hidden actor through that flag.
	if not _currently_observed(actor): return
	var fact := _room_person_fact(actor)
	for key: String in ["hp","max_hp","status","awareness_state","door_ready","surrendered","arrested","secured"]:
		if actor.has(key): fact[key] = actor[key]
	doctrine.record_room_observation(fact)

func _record_room_control(actor: Dictionary, unit: Dictionary, action: String) -> void:
	var fact := _room_person_fact(actor)
	fact["unit_id"] = str(unit.id)
	fact["action"] = action
	doctrine.record_room_control(fact)

func _record_room_stack(group: Array) -> void:
	if group.is_empty() or not _sync_group_ready(group): return
	var drill: Dictionary = group[0].command.args.get("drill",{})
	if drill.get("stage", "") != "ready": return
	var context := {"tick":tick,"time":time,"sync_id":str(drill.sync_id),"door_id":str(drill.door_id),"room_id":str(drill.room_id),"unit_ids":[],"command_ids":[],"observed_enemies":[]}
	for member: Dictionary in group:
		context.unit_ids.append(str(member.unit.id))
		context.command_ids.append(str(member.command.id))
	var epoch := str(drill.sync_id) + ":" + JSON.stringify(context.command_ids)
	if _room_stack_epochs.has(epoch): return
	_room_stack_epochs[epoch] = true
	for enemy: Dictionary in enemies:
		if not _currently_observed(enemy): continue
		if room_control.room_at(_position(enemy),float(enemy.get("base_height",0.0))) != str(drill.room_id): continue
		context.observed_enemies.append({"id":str(enemy.id),"status":str(enemy.status),"awareness_state":str(enemy.get("awareness_state","UNAWARE")),"door_ready":bool(enemy.get("door_ready",false))})
	# The metrics helper latches each command cohort once. Both manual and
	# automatic paths invoke this before delay expiry or any spoken signal.
	doctrine.record_room_stack(context)

func _frag_damage(projectile: Dictionary, actor: Dictionary) -> float:
	var profile := EquipmentCatalog.frag_stats()
	var impact: Array = projectile.target
	var origin := Vector2(impact[0],impact[1])
	var height := float(impact[2])
	var total := 0.0
	var relative := angle_difference(float(actor.get("body_facing",actor.get("facing",0.0))), (origin - _position(actor)).angle())
	for sample: Dictionary in CombatSpatial.samples(actor):
		var point: Vector2 = sample.point
		var distance := Vector3(point.x-origin.x,float(sample.height)-height,point.y-origin.y).length()
		if distance >= float(profile.radius): continue
		if not nav.sight_clear_height(_position(actor), point, sample.height, sample.height): continue
		var ray := nav.shot_profile_height(origin, point, height, sample.height, float(profile.wall_penetration))
		if not bool(ray.clear): continue
		var falloff := 1.0 if distance <= float(profile.core_radius) else (float(profile.radius)-distance)/(float(profile.radius)-float(profile.core_radius))
		var reduction := 0.0
		if actor.kind == "unit" or actor.has("armor") or actor.has("helmet"):
			var protection := EquipmentCatalog.protection(actor.get("_loadout",actor),str(sample.region),relative,float(profile.armor_penetration))
			reduction = clampf(float(protection.get("reduction",0.0)),0.0,1.0)
		total += float(profile.damage) * falloff * float(sample.weight) * float(ray.transmission) * (1.0-reduction)
	return total

func _explode_frag(projectile: Dictionary) -> void:
	_refresh_frag_observations()
	var victims: Array = units + enemies + civilians
	# Resolve all samples against one geometry before actor deaths cancel plans.
	var damages: Array = []
	for actor: Dictionary in victims: damages.append(_frag_damage(projectile,actor) if float(actor.hp)>0.0 else 0.0)
	for index: int in range(victims.size()):
		var actor: Dictionary = victims[index]
		var before := float(actor.hp)
		if float(damages[index]) <= 0.0 or before <= 0.0: continue
		actor["hp"] = maxf(0.0,before-float(damages[index]))
		_record_health_damage(actor,before,float(actor.hp))
		actor["_last_hit_time"] = time
		_update_combat_state(actor,1.0/30.0)
		if actor.kind == "unit": hits_taken += 1
		if float(actor.hp)>0.0: continue
		actor["status"] = "INCAPACITATED"
		if actor.kind == "enemy": kills += 1
		if actor.kind == "unit": _release_door_owner(str(actor.id))
		for command: Dictionary in actor.commands:
			if command.state not in ["SUCCEEDED","CANCELLED","FAILED"]:
				command["state"] = "CANCELLED"
				command["reason"] = "대원 행동 불능"
		# Hidden damage/deaths consume no public event sequence or memory update.
		if actor.kind == "unit" or _currently_observed(actor):
			_event("INCAPACITATED","위협 무력화" if actor.kind == "enemy" else str(actor.name)+" · 행동 불능",[],_array_position(actor),{"entity_id":actor.id,"kind":actor.kind})
	_refresh_frag_observations()
	var profile := EquipmentCatalog.frag_stats()
	var target: Array = projectile.target
	_event("FRAG","파편 수류탄 폭발",[target[0],target[1]],[target[0],target[1]],{"projectile_id":projectile.id,"unit_id":projectile.unit_id,"radius":profile.radius,"target_height":target[2],"observed":true})
	_emit_sound(Vector2(target[0],target[1]),float(profile.sound),"총성 감지","unit")

func _available_breaches(unit: Dictionary, include_pending: bool = true) -> int:
	var available := int(unit.get("breaches", 0))
	if include_pending:
		for command: Dictionary in unit.get("commands", []):
			if not FINISHED.has(str(command.state)) and not bool(command.get("_charge_consumed", false)) and (command.type == "BREACH_DOOR" or (command.type == "KICK_DOOR" and command.args.get("fallback", "") == "breach")):
				available -= 1
	return maxi(0, available)

func _project_weapon_resources(unit: Dictionary, include_pending: bool = true, limit: int = -1) -> Dictionary:
	var slot := str(unit.get("active_weapon", "primary"))
	var primary := int(unit.get("ammo", 0)) if slot == "primary" else int(unit.get("primary_ammo", 0))
	var secondary := int(unit.get("ammo", 0)) if slot == "secondary" else int(unit.get("secondary_ammo", 0))
	var reserves := {"primary":int(unit.get("reserve_ammo", 0)) if slot == "primary" else int(unit.get("primary_reserve_ammo", 0)), "secondary":int(unit.get("reserve_ammo", 0)) if slot == "secondary" else int(unit.get("secondary_reserve_ammo", 0))}
	var ammunition := {"primary":primary, "secondary":secondary}
	var index := -1
	for command: Dictionary in unit.get("commands", []):
		index += 1
		if limit >= 0 and index >= limit: break
		if FINISHED.has(str(command.state)) or (not include_pending and (command.state in ["PENDING", "FAILED"] or command.type in ["SWITCH_WEAPON", "SHOTGUN_BREACH"])): continue
		if command.type == "SWITCH_WEAPON":
			slot = str(command.args.get("slot", "secondary"))
		elif command.type == "RELOAD":
			var capacity := int(unit.get("max_ammo", 0)) if slot == str(unit.get("active_weapon", "primary")) else int(unit.get("_primary_stats" if slot == "primary" else "_secondary_stats", {}).get("ammo", 0))
			var transferred := mini(maxi(0, capacity - int(ammunition[slot])), int(reserves[slot]))
			ammunition[slot] = int(ammunition[slot]) + transferred
			reserves[slot] = int(reserves[slot]) - transferred
		elif command.type == "SHOTGUN_BREACH" and not bool(command.get("_round_consumed", false)):
			ammunition["primary"] = maxi(0, int(ammunition.primary) - 1)
	return {"active_weapon":slot, "current_weapon":str(unit.get("weapon", "standard")) if slot == "primary" else str(unit.get("sidearm", "none")), "ammo":int(ammunition[slot]), "primary_ammo":int(ammunition.primary)}

func _available_shotgun_breaches(unit: Dictionary, include_pending: bool = true, limit: int = -1) -> int:
	var projected := _project_weapon_resources(unit, include_pending, limit)
	return int(projected.ammo) if EquipmentCatalog.can_shotgun_breach(projected) else 0

func _door_resource_reason(unit: Dictionary, type: String, args: Dictionary, include_pending: bool) -> String:
	if (type == "BREACH_DOOR" or (type == "KICK_DOOR" and args.get("fallback", "") == "breach")) and _available_breaches(unit, include_pending) <= 0:
		return "예약분을 제외한 문 파괴 장비가 없습니다"
	if type == "THROW_FRAG":
		if MissionCatalog.roe(mission) != "high_intensity": return "정밀 교전수칙에서는 파편 수류탄을 사용할 수 없습니다"
		if _available_frags(unit, include_pending) <= 0: return "예약분을 제외한 파편 수류탄이 없습니다"
	if type == "SHOTGUN_BREACH" and _available_shotgun_breaches(unit, include_pending, _insert_resource_index) <= 0:
		return "활성 주무기 산탄총과 예약분을 제외한 탄약이 필요합니다"
	return ""

func _breach_has_cover(door: Dictionary, unit: Dictionary) -> bool:
	var source := _position(door)
	var destination := _position(unit)
	var height := float(door.get("base_height", 0.0)) + 1.1
	# The leaf being destroyed cannot count as blast cover.
	for obstacle: Dictionary in nav.blockers([str(door.id)], false):
		if float(obstacle.get("base_height", 0.0)) <= height and float(obstacle.get("base_height", 0.0)) + nav.obstacle_height(obstacle) >= height and nav._segment_obstacle(source, destination, obstacle, 0.0):
			return true
	return false

func _breach_team_safe(door: Dictionary) -> bool:
	for actor: Dictionary in units:
		if float(actor.hp) > 0.0 and _position(actor).distance_to(_position(door)) < BREACH_SAFE_DISTANCE and not _breach_has_cover(door, actor): return false
	return true

func _add_breach_warning(response: Dictionary, type: String, args: Dictionary) -> void:
	if type != "BREACH_DOOR" and not (type == "KICK_DOOR" and args.get("fallback", "") == "breach"): return
	var door := _find(doors, str(args.get("door_id", "")))
	if door.is_empty(): return
	var nearby: Array = []
	for actor: Dictionary in units:
		if float(actor.hp) > 0.0 and _position(actor).distance_to(_position(door)) < BREACH_SAFE_DISTANCE and not _breach_has_cover(door, actor): nearby.append(str(actor.id))
	if not nearby.is_empty():
		response["warning"] = "breach_safety"
		response["i18n_key"] = "door.breach_safety"
		response["warning_units"] = nearby

func _default_flash_target(door: Dictionary, origin: Vector2, opened: Array = []) -> Array:
	var center := _position(door)
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var sign_from: float = 1.0 if (origin - center).dot(normal) >= 0.0 else -1.0
	var across := Vector2(-normal.y, normal.x)
	for depth: float in [1.5, 1.0, 2.0, 0.75]:
		for lateral: float in [0.0, 0.35, -0.35]:
			var point := center - normal * sign_from * depth + across * lateral
			if nav.walkable(point, opened + [str(door.id)]): return [point.x, point.y]
	return []

func _begin_flash_planning_geometry() -> Dictionary:
	var saved: Dictionary = {"nav": nav, "doors": doors}
	var known: Array = _public_doors(false)
	var key: String = JSON.stringify(known) + JSON.stringify(_broken_glass)
	if _known_flash_navigation == null or key != _known_flash_key:
		_known_flash_key = key
		_known_flash_doors = known
		_known_flash_navigation = Navigation.new()
		_known_flash_navigation.build(mission, _known_flash_doors)
		for obstacle: Dictionary in _known_flash_navigation.walls:
			var identity: Dictionary = _glass_identity(obstacle)
			if _broken_glass.any(func(record: Dictionary) -> bool: return record.object_id == identity.get("object_id", "") and record.object_kind == identity.get("object_kind", "")):
				obstacle["opacity"] = 0.0
				obstacle["glass_broken"] = true
	nav = _known_flash_navigation
	doors = _known_flash_doors
	return saved

func _end_flash_planning_geometry(saved: Dictionary) -> void:
	nav = saved.nav
	doors = saved.doors

func _prepare_flash_plan(unit: Dictionary, args: Dictionary, append: bool) -> Dictionary:
	# Door states in a plan are observations. Unknown leaves remain closed in
	# this private navigation model regardless of their hidden live state.
	var saved: Dictionary = _begin_flash_planning_geometry()
	var projected: Dictionary = _project_movement_plan(unit, append)
	var answer: Dictionary
	if not bool(projected.get("ok", false)):
		answer = _rejected(str(projected.get("message", "문까지 접근할 수 없습니다")))
	else:
		var canonical: Dictionary = args.duplicate(true)
		var door: Dictionary = _find(doors, str(canonical.door_id))
		if not canonical.has("target"):
			var landing: Array = _default_flash_target(door, projected.origin, projected.open)
			if not landing.is_empty(): canonical["target"] = landing
		if not canonical.has("target"):
			answer = _rejected("문 안쪽에 유효한 섬광탄 투척 지점이 없습니다")
		else:
			answer = _flash_plan_preview(unit, door, _point(canonical.target), projected.origin, projected.open)
			if bool(answer.get("ok", false)): answer["args"] = canonical
	_end_flash_planning_geometry(saved)
	return answer

func _flash_plan_preview(unit: Dictionary, door: Dictionary, target: Vector2, origin: Vector2, opened: Array = []) -> Dictionary:
	var failed: Dictionary = {"ok": false, "message": "문 안쪽으로 섬광탄을 던질 경로가 없습니다", "target": [target.x, target.y], "radius": 3.0}
	var assumed: Array = opened.duplicate()
	if not assumed.has(str(door.id)): assumed.append(str(door.id))
	if not nav.walkable(target, assumed):
		failed.message = "섬광탄 착지점이 벽·문짝·가구와 겹칩니다"
		return failed
	var route: Array = nav.approach(origin, door, 0.85, opened)
	if route.is_empty():
		failed.message = "문 앞까지 접근할 수 없습니다"
		return failed
	var approach: Vector2 = _point(route.back())
	var predicted: Dictionary = _predict_open_leaf(door, approach)
	if DoorGeometry.overlaps_actor(predicted, 1.0, target, Navigation.RADIUS):
		failed.message = "섬광탄 착지점이 열릴 문짝과 겹칩니다"
		return failed
	var center := _position(door)
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var side: float = 1.0 if (origin - center).dot(normal) >= 0.0 else -1.0
	var across := Vector2(-normal.y, normal.x)
	var candidates: Array[Vector2] = [approach, center + normal * side * 0.65, center + normal * side * 0.65 + across * 0.35, center + normal * side * 0.65 - across * 0.35]
	if origin.distance_to(center) < 1.4: candidates.push_front(origin)
	var within_range: bool = false
	for point: Vector2 in candidates:
		if point.distance_to(target) > 8.0: continue
		within_range = true
		if not nav.walkable(point, assumed) or DoorGeometry.overlaps_actor(predicted, 1.0, point, Navigation.RADIUS): continue
		if nav.path(approach, point, assumed).is_empty(): continue
		var actor: Dictionary = unit.duplicate(false)
		actor.x = point.x
		actor.z = point.y
		actor.base_height = CombatSpatial.floor_base_at(_elevated_rooms, point)
		var source: Array = _flash_release_origin(actor, target, assumed, DoorGeometry.leaf_obstacle(predicted, 1.0))
		if not source.is_empty():
			return {"ok": true, "message": "", "source": [source[0], source[1]], "target": [target.x, target.y], "launch_position": [point.x, point.y], "radius": 3.0}
	if not within_range: failed.message = "투척 범위 8m를 벗어났습니다"
	return failed

func flash_target_preview(unit_id: String, index: int, target: Array) -> Dictionary:
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty() or index < 0 or index >= unit.commands.size() or not _valid_target(target): return _rejected("유효한 섬광탄 계획과 위치가 필요합니다")
	var command: Dictionary = unit.commands[index]
	if command.type != "OPEN_AND_FLASH" or command.state != "PENDING": return _rejected("미실행 문 섬광탄 계획이 필요합니다")
	var reason: String = _validate("OPEN_AND_FLASH", {"door_id": command.args.door_id, "target": target})
	if not reason.is_empty(): return _rejected(reason)
	var earlier: Dictionary = unit.duplicate(false)
	earlier["commands"] = unit.commands.slice(0, index)
	return _prepare_flash_plan(earlier, {"door_id": command.args.door_id, "target": target}, true)

func _release_flash_barrier(command: Dictionary) -> void:
	var key: String = str(command.get("args", {}).get("door_id", ""))
	var barrier: Dictionary = _flash_door_barriers.get(key, {})
	if str(barrier.get("command_id", "")) == str(command.get("id", "")) and not command.has("projectile_id"):
		_flash_door_barriers.erase(key)

func _advance_open_and_flash(unit: Dictionary, command: Dictionary, dt: float) -> void:
	var door: Dictionary = _find(doors, str(command.args.door_id))
	if door.is_empty():
		_fail(unit, command, "문이 존재하지 않습니다")
		return
	var phase: String = str(command.get("phase", "APPROACH"))
	if phase in ["PREPARE", "WAIT_EXPLOSION"]:
		_advance_flash_throw(unit, command, dt)
		return
	var key: String = str(door.id)
	var barrier: Dictionary = _flash_door_barriers.get(key, {})
	if not barrier.is_empty() and str(barrier.command_id) != str(command.id):
		command["state"] = "WAITING"
		command["reason"] = "앞선 섬광탄의 폭발을 기다리는 중"
		unit["status"] = "WAITING"
		return
	_flash_door_barriers[key] = {"unit_id": unit.id, "command_id": command.id}
	if bool(door.get("locked", false)):
		_fail(unit, command, "잠긴 문은 조용히 열 수 없습니다")
		return
	if door.state != "OPEN":
		command["phase"] = "OPEN"
		_advance_open_door(unit, command, dt)
		return
	if _position(unit).distance_to(_position(door)) > maxf(1.4, DoorGeometry.width(door) * 0.5 + 0.6):
		unit["status"] = "MOVING"
		_follow_command_path(unit, command, dt)
		return
	var target: Vector2 = _point(command.args.target)
	if command.has("_flash_approach_target"):
		if _position(unit).distance_to(_point(command._flash_approach_target)) > 0.10:
			unit["status"] = "MOVING"
			_follow_command_path(unit, command, dt)
			return
		command.erase("_flash_approach_target")
	if _position(unit).distance_to(target) > 8.0 or _flash_release_origin(unit, target).is_empty():
		# An open leaf may require a real, short step toward the aperture. The
		# route and body space are checked; the hand is never teleported through it.
		var preview: Dictionary = _flash_plan_preview(unit, door, target, _position(unit))
		var candidate: Vector2 = _point(preview.get("launch_position", _array_position(unit)))
		var route: Array = nav.path(_position(unit), candidate) if bool(preview.get("ok", false)) else []
		if not route.is_empty() and _unit_space_clear(unit, candidate) and not bool(command.get("_flash_repositioned", false)):
			command["_flash_repositioned"] = true
			command["path"] = route
			command["path_cursor"] = 0
			command["_flash_approach_target"] = [candidate.x, candidate.y]
		else:
			_fail(unit, command, "열린 문짝이나 벽이 섬광탄 투척 경로를 막습니다")
			return
	if command.has("_flash_approach_target"):
		if _position(unit).distance_to(_point(command._flash_approach_target)) > 0.10:
			unit["status"] = "MOVING"
			_follow_command_path(unit, command, dt)
			return
		command.erase("_flash_approach_target")
	command["phase"] = "PREPARE"
	command["state"] = "RUNNING"
	command["reason"] = "섬광탄 투척 준비"
	command["remaining"] = 0.45 * float(unit.get("action_multiplier", 1.0)) * (1.0 + maxf(0.0, float(unit.get("weapon_length", 0.86)) - 0.86) * 0.35)
	unit["status"] = "THROWING"

func _flash_curve(source: Vector3, target: Vector3, fraction: float) -> Vector3:
	var position: Vector3 = source.lerp(target, fraction)
	var distance: float = Vector2(source.x, source.z).distance_to(Vector2(target.x, target.z))
	position.y += sin(fraction * PI) * minf(1.4, 0.6 + distance * 0.08)
	return position

func _flash_segment_clear(source: Vector3, target: Vector3, allow_glass: bool = true, assumed_open: Array = []) -> bool:
	var start := Vector2(source.x, source.z)
	var finish := Vector2(target.x, target.z)
	for obstacle: Dictionary in nav._static_candidates(start, finish, 0.0) + nav._door_blockers(assumed_open, false):
		if allow_glass and str(obstacle.get("material", "")) == "glass": continue
		if nav._height_intersects(start, finish, source.y, target.y, obstacle): return false
	return true

func _flash_arc_clear(source: Vector3, target: Vector3, assumed_open: Array = [], planned_leaf: Dictionary = {}) -> bool:
	var previous := source
	for index: int in range(1, 17):
		var next := _flash_curve(source, target, float(index) / 16.0)
		if not _flash_segment_clear(previous, next, true, assumed_open): return false
		if not planned_leaf.is_empty() and nav._height_intersects(Vector2(previous.x, previous.z), Vector2(next.x, next.z), previous.y, next.y, planned_leaf): return false
		previous = next
	return true

func _flash_release_origin(unit: Dictionary, target: Vector2, assumed_open: Array = [], planned_leaf: Dictionary = {}) -> Array:
	var origin := _position(unit)
	var height: float = float(unit.get("base_height", 0.0)) + 1.2
	var landing_height: float = CombatSpatial.floor_base_at(_elevated_rooms, target) + 0.10
	var landing := Vector3(target.x, landing_height, target.y)
	var heading := (target - origin).normalized()
	var lateral := Vector2(-heading.y, heading.x)
	for offset: Vector2 in [Vector2.ZERO, heading * 0.28, lateral * 0.35, -lateral * 0.35, heading * 0.18 + lateral * 0.25, heading * 0.18 - lateral * 0.25]:
		var point := origin + offset
		if assumed_open.is_empty():
			if not nav.physical_clear_height(origin, point, height, height): continue
		else:
			if not _flash_segment_clear(Vector3(origin.x, height, origin.y), Vector3(point.x, height, point.y), false, assumed_open): continue
			if not planned_leaf.is_empty() and nav._height_intersects(origin, point, height, height, planned_leaf): continue
		if _flash_arc_clear(Vector3(point.x, height, point.y), landing, assumed_open, planned_leaf): return [point.x, point.y, height]
	return []

func _advance_flash_throw(unit: Dictionary, command: Dictionary, dt: float) -> void:
	if command.has("projectile_id"):
		command["phase"] = "WAIT_EXPLOSION"
		command["reason"] = "섬광탄 폭발까지 진입 대기"
		unit["status"] = "WAITING"
		var projectile: Dictionary = _find(_flash_projectiles, str(command.projectile_id))
		if projectile.is_empty():
			_succeed(unit, command)
		else:
			command["remaining"] = maxf(0.0, float(projectile.detonate_at) - time)
		return
	unit["status"] = "THROWING"
	command["phase"] = "PREPARE"
	command["remaining"] = maxf(0.0, float(command.remaining) - dt)
	if float(command.remaining) <= 0.0: _release_flash(unit, command)

func _release_flash(unit: Dictionary, command: Dictionary) -> void:
	var target: Vector2 = _point(command.args.target)
	var origin: Array = _flash_release_origin(unit, target)
	if int(unit.get("stuns", 0)) <= 0 or origin.is_empty() or _position(unit).distance_to(target) > 8.0:
		_fail(unit, command, "섬광탄 재고 또는 투척 경로가 변경되었습니다")
		return
	unit["stuns"] = int(unit.stuns) - 1
	stuns_used += 1
	var flight: float = maxf(0.12, _point(origin).distance_to(target) / 12.0)
	var id: String = "flash-" + str(command.id)
	var projectile: Dictionary = {"id": id, "unit_id": unit.id, "command_id": command.id, "source": origin, "target": [target.x, target.y, CombatSpatial.floor_base_at(_elevated_rooms, target) + 0.10], "position": origin.duplicate(), "released_at": time, "flight_duration": flight, "detonate_at": time + maxf(0.35, flight + 0.10), "phase": "FLIGHT"}
	var door_id: String = str(command.args.get("door_id", ""))
	if not door_id.is_empty():
		projectile["door_id"] = door_id
		_flash_door_barriers[door_id] = {"unit_id": unit.id, "command_id": command.id, "projectile_id": id}
	_flash_projectiles.append(projectile)
	command["projectile_id"] = id
	command["phase"] = "WAIT_EXPLOSION"
	command["remaining"] = float(projectile.detonate_at) - time
	var extra: Dictionary = {"projectile_id": id, "unit_id": unit.id, "radius": 3.0, "source_height": origin[2], "target_height": projectile.target[2], "flight_duration": flight, "detonate_at": projectile.detonate_at}
	if not door_id.is_empty(): extra["door_id"] = door_id
	_event("FLASH_RELEASE", str(unit.name) + " · 섬광탄 투척", [origin[0], origin[1]], [target.x, target.y], extra)

func _update_flash_projectiles(_dt: float) -> void:
	for key: String in _flash_door_barriers.keys():
		var barrier: Dictionary = _flash_door_barriers[key]
		if barrier.has("projectile_id"): continue
		var unit: Dictionary = _find(units, str(barrier.unit_id))
		var command: Dictionary = _active(unit) if not unit.is_empty() else {}
		if unit.is_empty() or not _can_act(unit) or str(command.get("id", "")) != str(barrier.command_id) or command.get("state", "") in ["FAILED", "CANCELLED", "SUCCEEDED"]:
			_flash_door_barriers.erase(key)
	var active: Array = []
	for projectile: Dictionary in _flash_projectiles:
		var source: Array = projectile.source
		var target: Array = projectile.target
		var fraction: float = clampf((time - float(projectile.released_at)) / float(projectile.flight_duration), 0.0, 1.0)
		var next: Vector3 = _flash_curve(Vector3(source[0], source[2], source[1]), Vector3(target[0], target[2], target[1]), fraction)
		var previous: Array = projectile.position
		if not _flash_segment_clear(Vector3(previous[0], previous[2], previous[1]), next):
			projectile["target"] = previous.duplicate()
			projectile["flight_duration"] = maxf(0.001, time - float(projectile.released_at))
			next = Vector3(previous[0], previous[2], previous[1])
			fraction = 1.0
		_break_flash_glass(Vector3(previous[0], previous[2], previous[1]), next, projectile)
		projectile["position"] = [next.x, next.z, next.y]
		projectile["phase"] = "FUSE" if fraction >= 1.0 else "FLIGHT"
		if time >= float(projectile.detonate_at):
			_explode_flash(projectile)
		else:
			active.append(projectile)
	_flash_projectiles = active

func _glass_identity(obstacle: Dictionary) -> Dictionary:
	for group: String in ["walls", "props"]:
		var objects: Array = mission.get(group, [])
		for index: int in range(objects.size()):
			var object: Dictionary = objects[index]
			var same_id: bool = not str(obstacle.get("id", "")).is_empty() and str(obstacle.get("id", "")) == str(object.get("id", ""))
			if same_id or (is_equal_approx(float(obstacle.get("x", -100.0)), float(object.get("x", -200.0))) and is_equal_approx(float(obstacle.get("z", -100.0)), float(object.get("z", -200.0)))):
				var kind: String = "wall" if group == "walls" else "prop"
				return {"object_id": str(object.get("id", kind + "-" + str(index))), "object_kind": kind}
	return {}

func _break_flash_glass(source: Vector3, destination: Vector3, projectile: Dictionary) -> void:
	var start := Vector2(source.x, source.z)
	var finish := Vector2(destination.x, destination.z)
	var broken: Array = []
	for obstacle: Dictionary in nav._static_candidates(start, finish, 0.0):
		if str(obstacle.get("material", "")) != "glass" or bool(obstacle.get("glass_broken", false)): continue
		if not nav._height_intersects(start, finish, source.y, destination.y, obstacle): continue
		var identity: Dictionary = _glass_identity(obstacle)
		if identity.is_empty(): continue
		obstacle["glass_broken"] = true
		obstacle["opacity"] = 0.0
		broken.append(identity)
	for door: Dictionary in doors:
		if str(door.get("material", "")) != "glass" or bool(door.get("glass_broken", false)): continue
		var leaf: Dictionary = DoorGeometry.leaf_obstacle(door)
		if leaf.is_empty() or not nav._height_intersects(start, finish, source.y, destination.y, leaf): continue
		door["glass_broken"] = true
		door["opacity"] = 0.0
		broken.append({"object_id": str(door.id), "object_kind": "door"})
	if broken.is_empty(): return
	nav.invalidate_dynamic()
	for identity: Dictionary in broken:
		var point: Vector2 = start.lerp(finish, 0.5)
		var record: Dictionary = identity.duplicate()
		record.merge({"x": point.x, "z": point.y, "broken_at": time})
		_broken_glass.append(record)
		var extra: Dictionary = identity.duplicate()
		extra.merge({"unit_id": projectile.unit_id, "projectile_id": projectile.id})
		_event("GLASS_BREAK", "섬광탄이 유리를 깨고 통과했습니다", [point.x, point.y], [], extra)

func _explode_flash(projectile: Dictionary) -> void:
	var coordinate: Array = projectile.position
	var target := Vector2(coordinate[0], coordinate[1])
	var affected: Array = []
	for entity: Dictionary in enemies + civilians:
		if float(entity.hp) <= 0.0 or _position(entity).distance_to(target) > 3.0: continue
		if not nav.sight_clear_height(target, _position(entity), float(coordinate[2]), CombatSpatial.eye_height(entity)): continue
		if entity.kind == "civilian" and float(entity.get("stunned", 0.0)) <= 0.0: entity["_pre_flash_status"] = entity.status
		entity["stunned"] = maxf(float(entity.get("stunned", 0.0)), 2.0)
		entity["flash_recover_remaining"] = 0.35 if entity.kind == "enemy" else 0.0
		entity["status"] = "STUNNED"
		entity["_target"] = ""
		entity["_observed"] = []
		entity["_aim_position"] = []
		entity["aim_progress"] = 0.0
		entity["aim_state"] = "lowered"
		if entity.kind == "enemy":
			entity["door_ready"] = false
			entity["_door_ready_until"] = -1.0
			entity.erase("_shotgun_exposure")
			entity.erase("_door_contact_prepared")
		entity["reload_remaining"] = 0.0
		entity["_enemy_reload"] = 0.0
		entity["_hostage_attack_cooldown"] = 0.0
		if entity.kind == "enemy": _release_door_owner(str(entity.id))
		if _currently_observed(entity): affected.append(entity.id)
	var extra: Dictionary = {"radius": 3.0, "unit_id": projectile.unit_id, "projectile_id": projectile.id}
	if projectile.has("door_id"):
		extra["door_id"] = projectile.door_id
		var barrier: Dictionary = _flash_door_barriers.get(str(projectile.door_id), {})
		if str(barrier.get("projectile_id", "")) == str(projectile.id): _flash_door_barriers.erase(str(projectile.door_id))
	_event("STUN", "섬광탄 폭발", [coordinate[0], coordinate[1]], [coordinate[0], coordinate[1]], extra)
	_emit_sound(target, 9.0, "섬광탄 폭발음", "unit")

func _detonate_stun(unit: Dictionary, command: Dictionary) -> void:
	# Compatibility entry point: direct and door-assisted throws share release,
	# projectile motion and detonation on the authoritative simulation clock.
	_release_flash(unit, command)

func _camera_sensor(unit: Dictionary) -> Dictionary:
	var position: Array = unit.get("camera_origin", [])
	if float(unit.get("camera_remaining", 0.0)) <= 0.0 or position.size() != 2: return {}
	var sensor: Dictionary = unit.duplicate(false)
	sensor["x"] = position[0]
	sensor["z"] = position[1]
	sensor["eye_height"] = 0.08
	sensor["facing"] = float(unit.get("camera_facing", 0.0))
	sensor["fov"] = 80.0
	sensor["vision_range"] = 8.0
	return sensor

func _advance_camera(unit: Dictionary, command: Dictionary, dt: float) -> void:
	var door: Dictionary = _find(doors, str(command.args.door_id))
	if door.is_empty() or int(unit.get("cameras", 0)) <= 0:
		_fail(unit, command, "사용 가능한 정찰 카메라와 문이 필요합니다")
		return
	if command.get("phase", "APPROACH") == "CAMERA":
		unit["status"] = "CAMERA"
		command["remaining"] = maxf(0.0, float(command.remaining) - dt)
		unit["camera_remaining"] = float(command.remaining)
		_capture_camera_observations(unit)
		if float(command.remaining) <= 0.0: _succeed(unit, command)
		return
	if _position(unit).distance_to(DoorGeometry.handle_floor(door)) > 0.65:
		unit["status"] = "MOVING"
		_follow_command_path(unit, command, dt)
		return
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var side: float = 1.0 if (_position(unit) - _position(door)).dot(normal) >= 0.0 else -1.0
	var start := _position(door) + normal * side * 0.18
	var lens := _position(door) - normal * side * 0.18
	var height: float = float(door.get("base_height", 0.0)) + 0.08
	for obstacle: Dictionary in nav._static_candidates(start, lens, 0.0):
		if nav._height_intersects(start, lens, height, height, obstacle):
			_fail(unit, command, "문 아래 카메라를 넣을 틈이 없습니다")
			return
	command["phase"] = "CAMERA"
	command["remaining"] = 1.0 * float(unit.get("action_multiplier", 1.0))
	unit["camera_origin"] = [lens.x, lens.y]
	unit["camera_facing"] = (-normal * side).angle()
	unit["camera_remaining"] = float(command.remaining)
	_capture_camera_observations(unit)
	_event("CAMERA", str(unit.name) + " · 문 아래 정찰", _array_position(door), [], {"unit_id": unit.id, "door_id": door.id})

func _capture_camera_observations(unit: Dictionary) -> void:
	var sensor: Dictionary = _camera_sensor(unit)
	if sensor.is_empty(): return
	var captured: Array = []
	for entity: Dictionary in enemies + civilians:
		if float(entity.get("hp", 0.0)) <= 0.0 or _sensor_exposure(sensor, entity) <= 0.0: continue
		captured.append({"id": entity.id, "kind": entity.kind, "name": entity.name, "x": entity.x, "z": entity.z, "facing": entity.facing, "hp": entity.hp, "status": entity.status, "observed_at": time})
	unit["camera_observations"] = captured

func can_see(observer: Dictionary, subject: Dictionary) -> bool:
	return visual_exposure(observer, subject) > 0.000001

func effective_vision_range(observer: Dictionary) -> float:
	return nav.effective_vision_range(observer)

func exposure(observer: Dictionary, subject: Dictionary) -> float:
	return visual_exposure(observer, subject)

func visual_exposure(observer: Dictionary, subject: Dictionary) -> float:
	if float(observer.get("hp", 0.0)) <= 0.0 or float(observer.get("stunned", 0.0)) > 0.0:
		return 0.0
	var result := _sensor_exposure(observer, subject)
	if observer.get("kind", "") == "unit":
		var camera: Dictionary = _camera_sensor(observer)
		if not camera.is_empty(): result = maxf(result, _sensor_exposure(camera, subject))
	var peek_origin: Array = observer.get("_peek_origin", [])
	if observer.get("kind", "") == "unit" and float(observer.get("_peek_remaining", 0.0)) > 0.0 and peek_origin.size() == 2:
		var eye_height: float = nav.Spatial.eye_height(observer)
		var peek_point := _point(peek_origin)
		# A lean is another physically reachable eye position, never a sensor
		# teleported through the closed leaf, frame, or adjacent wall.
		if _position(observer).distance_to(peek_point) <= nav.Spatial.MAX_PEEK_LEAN and nav.physical_clear_height(_position(observer), peek_point, eye_height, eye_height):
			var sensor: Dictionary = observer.duplicate(false)
			sensor.x = peek_point.x
			sensor.z = peek_point.y
			sensor.facing = float(observer.get("_peek_facing", observer.get("facing", 0.0)))
			sensor.fov = 70.0
			result = maxf(result, _sensor_exposure(sensor, subject))
	return result

func _sensor_exposure(observer: Dictionary, subject: Dictionary) -> float:
	var origin := _position(observer)
	var destination := _position(subject)
	var eye_height: float = nav.Spatial.eye_height(observer)
	var vision_range: float = effective_vision_range(observer)
	var facing := float(observer.get("facing", 0.0))
	var fov := float(observer.get("fov", 110.0))
	# Geometry points (door observations and floor exploration) represent the
	# observer's eye plane. Actors expose their actual stance-dependent body.
	if not subject.has("kind") and not subject.has("hp") and not subject.has("stance"):
		return 1.0 if _vision_cone_clear(origin, destination, facing, fov, vision_range, eye_height, eye_height) else 0.0
	var offset := destination - origin
	var distance_squared := offset.length_squared()
	var shoulder_radius: float = nav.Spatial.SHOULDER_HALF_WIDTH
	if distance_squared > pow(vision_range + shoulder_radius, 2):
		return 0.0
	# Every body sample is inside this disk. Keep the close-range exception
	# used by exposed_fraction; only reject when even the nearest shoulder is
	# outside it and the entire disk is beyond the cone's angular boundary.
	if distance_squared > pow(shoulder_radius + sqrt(0.02) + 0.0001, 2):
		var margin := asin(shoulder_radius / sqrt(distance_squared)) + 0.0001
		if absf(angle_difference(facing, offset.angle())) > deg_to_rad(fov) * 0.5 + margin:
			return 0.0
	if has_method("_smoke_blocks") and bool(call("_smoke_blocks", origin, destination)):
		return 0.0
	var sensor: Dictionary = observer.duplicate(false)
	sensor["_cone_facing"] = facing
	sensor["_cone_fov"] = fov
	sensor["_cone_range"] = vision_range
	return nav.exposed_fraction(sensor, subject)

func _enemy_can_watch_door(enemy: Dictionary, door: Dictionary) -> bool:
	if _position(enemy).distance_to(_position(door)) > effective_vision_range(enemy): return false
	var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	var point := _position(door) + normal * _door_side(door, _position(enemy)) * 0.35
	if not mission.get("rooms", []).is_empty() and _acoustic.room_at(_position(enemy)) != _acoustic.room_at(point): return false
	return can_see(enemy, {"x":point.x, "z":point.y})

func _prepare_door_ready(enemy: Dictionary, door: Dictionary) -> bool:
	if not _can_act(enemy) or _is_target(enemy) or not enemy.get("_observed", []).is_empty() or not _enemy_can_watch_door(enemy, door): return false
	var previous := _find(doors, str(enemy.get("_door_ready_id", "")))
	if bool(enemy.get("door_ready", false)) and not previous.is_empty() and previous.id != door.id:
		var current_distance := _position(enemy).distance_to(_position(previous))
		var new_distance := _position(enemy).distance_to(_position(door))
		if current_distance < new_distance or (is_equal_approx(current_distance, new_distance) and str(previous.id) < str(door.id)): return false
	enemy["door_ready"] = true
	enemy["_door_ready_id"] = str(door.id)
	enemy["_door_ready_until"] = time + DOOR_READY_SECONDS
	return true

func _observe_door_motion(enemy: Dictionary) -> void:
	var remembered: Dictionary = enemy.get("_door_leaf_memory", {})
	for door: Dictionary in doors:
		var value := DoorGeometry.leaf_progress(float(door.get("progress", 0.0)))
		var previous := float(remembered.get(str(door.id), value))
		# Latch preparation (progress <= .22) is not visible leaf movement.
		if absf(value - previous) > 0.001 and _enemy_can_watch_door(enemy, door): _prepare_door_ready(enemy, door)
		remembered[str(door.id)] = value
	enemy["_door_leaf_memory"] = remembered
	if enemy.get("_observed", []).is_empty() and float(enemy.get("_alert_level", 0.0)) > 0.12:
		for door: Dictionary in doors: _prepare_door_ready(enemy, door)

func _door_ready_contact(enemy: Dictionary, target: Dictionary) -> bool:
	if target.is_empty() or not bool(enemy.get("door_ready", false)) or time > float(enemy.get("_door_ready_until", -1.0)) or str(enemy.get("aim_state", "")) != "ready": return false
	var door := _find(doors, str(enemy.get("_door_ready_id", "")))
	if door.is_empty() or not DoorGeometry.funnel_rect(door).has_point(_position(target)): return false
	return absf(angle_difference(float(enemy.get("aim_facing", enemy.facing)), (_position(target) - _position(enemy)).angle())) <= deg_to_rad(18.0)

func _advance_door_ready(enemy: Dictionary) -> bool:
	if not bool(enemy.get("door_ready", false)): return false
	var door := _find(doors, str(enemy.get("_door_ready_id", "")))
	if door.is_empty() or time > float(enemy.get("_door_ready_until", -1.0)) or not _can_act(enemy) or not _enemy_can_watch_door(enemy, door):
		enemy["door_ready"] = false
		return false
	var point := _position(door)
	enemy["facing"] = point.direction_to(_position(enemy)).angle() + PI
	_remember_aim(enemy, {"id":"door:" + str(door.id), "x":point.x, "z":point.y})
	_advance_authoritative_aim(enemy, true)
	enemy["status"] = "SUSPICIOUS"
	enemy["_ai_state"] = "SUSPICIOUS"
	# A clear portal still permits investigation, cover movement and alert decay.
	return door.get("state", "") != "OPEN"

func _register_shotgun_exposure(unit: Dictionary, command: Dictionary, door: Dictionary, radius: float) -> void:
	for enemy: Dictionary in enemies:
		if not _can_act(enemy) or not bool(enemy.get("door_ready", false)) or enemy.get("_door_ready_id", "") != door.id or _door_sound_audibility(_position(door), _position(enemy), radius) <= 0.0: continue
		# The audible breaching station is fixed at preparation time; it is never
		# refreshed with a hidden operator's movement or propagated to allies.
		enemy["_shotgun_exposure"] = {"unit_id":unit.id, "command_id":command.id, "position":_array_position(unit), "time":time}

func _shotgun_exposure_ready(enemy: Dictionary, target: Dictionary) -> bool:
	var memory: Dictionary = enemy.get("_shotgun_exposure", {})
	if memory.is_empty() or memory.get("unit_id", "") != target.get("id", "") or not _can_act(enemy): return false
	var command := _active(target)
	return command.get("id", "") == memory.command_id and command.get("phase", "") == "SHOTGUN_PREPARE" and _position(target).distance_to(_point(memory.position)) <= 0.15

func _advance_shotgun_exposure(enemy: Dictionary) -> bool:
	var memory: Dictionary = enemy.get("_shotgun_exposure", {})
	if memory.is_empty(): return false
	var target := _find(units, str(memory.unit_id))
	if target.is_empty() or not _shotgun_exposure_ready(enemy, target):
		enemy.erase("_shotgun_exposure")
		return false
	var point := _point(memory.position)
	enemy["facing"] = (point - _position(enemy)).angle()
	_remember_aim(enemy, {"id":target.id, "x":point.x, "z":point.y})
	_advance_authoritative_aim(enemy, true)
	enemy["status"] = "ALERT"
	_combat(enemy, [target], true, str(target.id))
	return true

func _update_perception() -> void:
	# The individual observations already perform the same current visibility
	# query. Reuse their IDs for team display instead of casting a second time.
	var visible_enemy_ids: Dictionary = {}
	for unit: Dictionary in units:
		for sight: Dictionary in _sense_observations(unit, enemies):
			if float(sight.get("exposure", 0.0)) > 0.000001: visible_enemy_ids[str(sight.id)] = true
	for door: Dictionary in doors:
		var normal := Vector2(0, 1) if door.get("axis", "x") == "x" else Vector2(1, 0)
		var observed: bool = false
		for unit: Dictionary in units:
			for side: float in [-1.0, 1.0]:
				var point := _position(door) + normal * side * 0.3
				if can_see(unit, {"x": point.x, "z": point.y}):
					observed = true
					break
			if observed: break
		if observed:
			var observation: Dictionary = door.duplicate(true)
			observation["observed"] = true
			observation["_observed_at"] = time
			_door_observations[str(door.id)] = observation
	for enemy: Dictionary in enemies:
		var visible: bool = visible_enemy_ids.has(str(enemy.id))
		# Living sensory contacts omit corpses; their physical display still
		# requires a fresh ordinary visibility query.
		if float(enemy.get("hp", 0.0)) <= 0.0:
			for unit: Dictionary in units:
				if can_see(unit, enemy):
					visible = true
					break
		enemy["visible"] = visible
		if visible:
			if not enemy.has("last_seen") and float(enemy["hp"]) > 0.0:
				_event("CONTACT", "새 위협 발견", [], _array_position(enemy), {"enemy_id": enemy["id"]})
			_remember_enemy_state(enemy)
		if not _can_act(enemy) or _is_target(enemy):
			enemy["_observed"] = []
			continue
		_observe_door_motion(enemy)
		# Memories hold snapshots of sensory information, never live hidden actors.
		var observations: Array = _sense_observations(enemy, units)
		if not observations.is_empty():
			var observation: Dictionary = observations[0]
			enemy["_ai_state"] = "REACTING" if not bool(observation.identified) or float(enemy._reaction) > 0.0 else "ALERT"
			enemy["_last_known"] = observation["position"].duplicate()
			enemy["_last_known_time"] = time
			enemy["_detect_reason"] = "sight"
			enemy["_investigate_arrived_at"] = -1.0
		elif not enemy.get("_last_known", []).is_empty():
			enemy["_ai_state"] = "SUSPICIOUS"
		if not observations.is_empty() and bool(observations[0].identified):
			var seen_position: Vector2 = _point(observations[0]["position"])
			enemy["_last_known"] = [seen_position.x, seen_position.y]
			enemy["_last_known_time"] = time
			_raise_combat_alert(enemy, seen_position)
			_take_enemy_cover(enemy, seen_position)
	for civilian: Dictionary in civilians:
		# Secured civilians are known to their escort; hidden civilians expose no motion.
		var visible: bool = bool(civilian.get("secured", false)) and not _p5_active
		if not visible:
			for unit: Dictionary in units:
				if can_see(unit, civilian):
					visible = true
					break
		civilian["visible"] = visible
		if visible:
			civilian["last_seen"] = _array_position(civilian)
			civilian["last_seen_time"] = time
			if _p5_active: observed_statistics.observe(civilian, tick)
			_record_room_observation(civilian)

func _advance_enemy(enemy: Dictionary, dt: float) -> void:
	if _is_target(enemy):
		enemy["status"] = "TARGET"
		return
	if not _can_act(enemy):
		return
	if int(enemy.ammo) <= 0 and int(enemy.get("reserve_ammo", 0)) > 0:
		if float(enemy._enemy_reload) <= 0.0: enemy._enemy_reload = _begin_resource_reload(enemy)
		enemy._enemy_reload = maxf(0.0, float(enemy._enemy_reload) - dt)
		enemy["reload_remaining"] = enemy._enemy_reload
		enemy.status = "RELOADING"
		if float(enemy._enemy_reload) <= 0.0: _finish_resource_reload(enemy)
		return
	var observations: Array = enemy["_observed"]
	if not observations.is_empty():
		var sight: Dictionary = observations[0]
		var target_position: Vector2 = _point(sight["position"])
		enemy["facing"] = lerp_angle(float(enemy["facing"]), (target_position - _position(enemy)).angle(), minf(1.0, dt * 7.0))
		enemy["status"] = "REACTING" if float(enemy["_reaction"]) > 0.0 or not bool(sight.get("identified", false)) else "ALERT"
		enemy["_ai_state"] = enemy["status"]
		if enemy["status"] == "ALERT" and first_alert_time < 0.0:
			first_alert_time = time
		enemy["_alert_action"] = "guard"
		var cover_target: Array = enemy.get("_cover_target", [])
		if cover_target.size() == 2 and _position(enemy).distance_to(_point(cover_target)) > 0.18:
			enemy["_alert_action"] = "cover"
			var watch_facing: float = float(enemy.facing)
			_move_tactical_actor(enemy, _point(cover_target), float(enemy_rules.patrol_speed), dt, bool(enemy_rules.get("enemy_opens_doors", true)))
			enemy["facing"] = lerp_angle(watch_facing, (target_position - _position(enemy)).angle(), minf(1.0, dt * 7.0))
		elif _enemy_type(enemy) == "rusher":
			# Rushers close only on an observed or remembered point.
			if _position(enemy).distance_to(target_position) > 1.8:
				_move_tactical_actor(enemy, target_position, float(enemy_rules.patrol_speed) * 1.5, dt, bool(enemy_rules.get("enemy_opens_doors", true)))
		elif _enemy_type(enemy) == "hostage_taker":
			_maintain_hostage_distance(enemy, dt)
		if _enemy_type(enemy) == "hostage_taker" and _advance_hostage_threat(enemy, dt):
			return
		_combat(enemy, units, true)
		return
	enemy["_hostage_alert_elapsed"] = 0.0
	if _advance_shotgun_exposure(enemy): return
	# A delayed support order through a cleared room supersedes a static
	# doorway watch; the shot-exposed breacher and actual contacts still lead.
	if _advance_rear_response(enemy, dt): return
	if _advance_door_ready(enemy): return
	if _advance_combat_alert(enemy, dt):
		return
	var last_known: Array = enemy["_last_known"]
	if not last_known.is_empty():
		enemy["status"] = "SUSPICIOUS"
		enemy["_ai_state"] = "SUSPICIOUS"
		var destination: Vector2 = _nearest_tactical_point(_point(last_known), _all_closed_door_ids() if bool(enemy_rules.get("enemy_opens_doors", true)) else [])
		if _position(enemy).distance_to(destination) > 0.3:
			enemy["_investigate_arrived_at"] = -1.0
			_move_tactical_actor(enemy, destination, float(enemy_rules.patrol_speed) * (1.5 if _enemy_type(enemy) == "rusher" else 1.0), dt, bool(enemy_rules.get("enemy_opens_doors", true)))
			return
		if float(enemy.get("_investigate_arrived_at", -1.0)) < 0.0:
			enemy["_investigate_arrived_at"] = time
			enemy["_investigate_facing"] = float(enemy["facing"])
		var search_elapsed: float = time - float(enemy["_investigate_arrived_at"])
		if search_elapsed < 3.0:
			enemy["facing"] = float(enemy.get("_investigate_facing", enemy["facing"])) + sin(search_elapsed * 2.4) * 1.15
			return
		enemy["_last_known"] = []
		enemy["_ai_path"] = []
		enemy["_investigate_arrived_at"] = -1.0
	if _enemy_type(enemy) == "hostage_taker":
		_maintain_hostage_distance(enemy, dt)
	var patrol: Array = enemy.get("patrol", [])
	if patrol.size() < 2 or _enemy_type(enemy) in ["sentry", "hostage_taker"]:
		enemy["status"] = "IDLE"
		enemy["_ai_state"] = "IDLE"
		return
	enemy["status"] = "PATROL"
	enemy["_ai_state"] = "PATROL"
	var index: int = int(enemy["_patrol_index"]) % patrol.size()
	var destination: Vector2 = _point(patrol[index])
	if _position(enemy).distance_to(destination) < 0.18:
		enemy["_patrol_index"] = (index + 1) % patrol.size()
		enemy["_ai_path"] = []
		return
	_move_tactical_actor(enemy, destination, float(enemy_rules.patrol_speed), dt, bool(enemy_rules.get("enemy_opens_doors", true)))

func _is_target(enemy: Dictionary) -> bool:
	return bool(enemy.get("target", false)) or bool(enemy.get("passive", false)) or bool(enemy.get("training", false))

func _initialize_combat_state(entity: Dictionary, source: Dictionary = {}) -> void:
	# These values describe a consistent game model; they are not calibrated
	# human or weapon performance measurements.
	entity["body_facing"] = float(source.get("body_facing", entity["facing"]))
	entity["aim_facing"] = float(source.get("aim_facing", entity["facing"]))
	entity["stance"] = str(source.get("stance", "standing")) if str(source.get("stance", "standing")) in ["standing", "crouched"] else "standing"
	entity["movement_mode"] = str(source.get("movement_mode", "normal")) if str(source.get("movement_mode", "normal")) in ["careful", "normal", "fast"] else "normal"
	entity["max_hp"] = maxf(float(source.get("max_hp", entity["max_hp"])), float(entity["hp"]))
	entity["ammo"] = clampi(int(entity["ammo"]), 0, int(entity["max_ammo"]))
	entity["reserve_ammo"] = clampi(int(source.get("reserve_ammo", int(entity["max_ammo"]) * 3 if entity["kind"] != "civilian" else 0)), 0, 10000)
	entity["aim_progress"] = 0.0
	entity["aim_state"] = "idle"
	entity["injury_status"] = "none"
	entity["mobility_multiplier"] = 1.0
	entity["action_multiplier"] = 1.0
	entity["reload_duration"] = 0.0
	entity["reload_remaining"] = 0.0
	entity["_combat_dt"] = 1.0 / 30.0
	entity["_combat_travel"] = float(entity.get("travel_distance", 0.0))
	entity["_combat_moving_until"] = -1.0
	entity["_aim_advanced_at"] = time
	entity["_aim_ready_error"] = PI
	_update_combat_state(entity, 0.0)
	_refresh_weapon_state(entity)

func _update_combat_state(entity: Dictionary, dt: float) -> void:
	entity["_combat_dt"] = maxf(0.0, dt)
	var health: float = float(entity.get("hp", 0.0)) / maxf(1.0, float(entity.get("max_hp", 100.0)))
	var injury: String = "wounded" if health <= 0.4 else ("hurt" if health <= 0.75 else "none")
	entity["injury_status"] = injury
	entity["mobility_multiplier"] = 0.0 if health <= 0.0 else (0.65 if injury == "wounded" else (0.85 if injury == "hurt" else 1.0))
	entity["action_multiplier"] = 1.45 if injury == "wounded" else (1.18 if injury == "hurt" else 1.0)
	if entity.get("kind", "") == "unit":
		var gear_stats: Dictionary = entity.get("_gear_stats", {})
		entity["mobility_multiplier"] *= float(gear_stats.get("movement_multiplier", 1.0))
		entity["action_multiplier"] *= float(gear_stats.get("action_multiplier", 1.0))
		entity["equipment_weight"] = float(gear_stats.get("weight", 0.0))
	var travel: float = float(entity.get("travel_distance", 0.0))
	if travel - float(entity.get("_combat_travel", travel)) > 0.0005:
		entity["_combat_moving_until"] = time + 0.07
	entity["_combat_travel"] = travel
	if float(entity.get("hp", 0.0)) <= 0.0:
		entity["aim_progress"] = 0.0
		entity["aim_state"] = "lowered"
		if entity.get("kind", "") == "enemy": entity["door_ready"] = false
	_refresh_weapon_state(entity)

func _combat_moving(entity: Dictionary) -> bool:
	return float(entity.get("travel_distance", 0.0)) - float(entity.get("_combat_travel", 0.0)) > 0.0005 or time < float(entity.get("_combat_moving_until", -1.0))

func _reacting_to_hit(entity: Dictionary) -> bool:
	return entity.get("kind", "") == "unit" and _can_act(entity) and not bool(entity.get("facing_locked", false)) and time < float(entity.get("_incoming_fire_until", -1.0))

func _advance_authoritative_aim(entity: Dictionary, acquire: bool = true) -> void:
	if time <= float(entity.get("_aim_advanced_at", -1.0)) + 0.000001:
		_refresh_weapon_state(entity)
		return
	var dt: float = minf(0.1, time - float(entity.get("_aim_advanced_at", time - float(entity.get("_combat_dt", 1.0 / 30.0)))))
	entity["_aim_advanced_at"] = time
	var desired: float = float(entity["facing"])
	var remembered: Array = entity.get("_aim_position", [])
	var holding: bool = remembered.size() == 2 and time - float(entity.get("_aim_observed_at", -100.0)) <= AIM_HOLD_SECONDS
	if holding:
		var offset: Vector2 = _point(remembered) - _position(entity)
		if offset.length_squared() > 0.001:
			desired = offset.angle()
	var reacting := _reacting_to_hit(entity)
	# A hit gives a fixed direction; only an identified contact can refine it.
	if reacting and (not holding or absf(angle_difference(desired, float(entity["_incoming_fire_facing"]))) > PI / 4.0):
		desired = float(entity["_incoming_fire_facing"])
	var moving: bool = _combat_moving(entity)
	var body_goal: float = float(entity["facing"]) if bool(entity.get("facing_locked", false)) else (desired if holding or reacting else (float(entity.get("move_facing", desired)) if moving else float(entity["facing"])))
	var injury_rate: float = 1.0 / float(entity.get("action_multiplier", 1.0))
	var body_rate: float = (4.2 if moving else 5.2) * injury_rate
	entity["body_facing"] = _turn_towards(float(entity.get("body_facing", entity["facing"])), body_goal, body_rate * dt)
	if reacting: entity["facing"] = entity["body_facing"]
	var torso_limit: float = deg_to_rad(65.0)
	desired = float(entity["body_facing"]) + clampf(angle_difference(float(entity["body_facing"]), desired), -torso_limit, torso_limit)
	var before: float = float(entity.get("aim_facing", entity["facing"]))
	var angular_rate: float = (4.3 if moving else 6.4) * injury_rate
	entity["aim_facing"] = _turn_towards(before, desired, angular_rate * dt)
	var goal: float = (_point(remembered) - _position(entity)).angle() if holding else float(entity["facing"])
	var error: float = absf(angle_difference(float(entity["aim_facing"]), goal))
	entity["_aim_ready_error"] = error
	var progress: float = float(entity.get("aim_progress", 0.0))
	if not acquire or not holding:
		progress = maxf(0.0, progress - dt * 4.0)
	elif error > deg_to_rad(12.0):
		progress = maxf(0.0, progress - dt * 3.0)
	else:
		var acquisition: float = 0.22
		if moving:
			acquisition = {"careful": 0.28, "normal": 0.36, "fast": 0.52}.get(str(entity.get("movement_mode", "normal")), 0.36)
		elif entity.get("stance", "standing") == "crouched":
			acquisition = 0.19
		if entity.get("kind", "") == "unit":
			acquisition *= float(_weapon_stats(entity).get("aim_time", 0.22)) / 0.22
			acquisition *= 1.0 + maxf(0.0, float(entity.get("weapon_length", 0.86)) - float(EquipmentCatalog.catalog().get("handling", {}).get("reference_length", 0.86))) * float(EquipmentCatalog.catalog().get("handling", {}).get("length_aim_penalty", 0.30))
		progress = minf(1.0, progress + dt / (acquisition * float(entity.get("action_multiplier", 1.0))))
	entity["aim_progress"] = progress
	# Both sides may fire once aligned; enemy identification and reaction still gate contact.
	entity["aim_state"] = "ready" if acquire and holding and error <= deg_to_rad(6.0) else ("acquiring" if holding and acquire else "idle")
	_refresh_weapon_state(entity)

func _turn_towards(from: float, to: float, amount: float) -> float:
	return wrapf(from + clampf(angle_difference(from, to), -amount, amount), -PI, PI)

func _refresh_weapon_state(entity: Dictionary) -> void:
	if entity.get("kind", "") == "unit": entity["weapon_length"] = float(_weapon_stats(entity).get("length", 0.86))
	var origin: Vector2 = CombatSpatial.weapon_origin(entity)
	var height: float = CombatSpatial.weapon_height(entity)
	var aim_point: Array = entity.get("_aim_position", [])
	if aim_point.size() == 2:
		var actor_position := _position(entity)
		var aim_distance: float = actor_position.distance_to(_point(aim_point))
		if actor_position.distance_to(origin) >= aim_distance:
			origin = actor_position + (origin - actor_position).normalized() * maxf(0.0, aim_distance - 0.10)
	# The muzzle cannot teleport through a wall while the body is beside it.
	if not nav.physical_clear_height(_position(entity), origin, height, height):
		origin = _position(entity)
	entity["weapon_origin"] = [origin.x, origin.y, height]
	entity["current_weapon_height"] = height

func _begin_resource_reload(entity: Dictionary) -> float:
	if int(entity.get("reserve_ammo", 0)) <= 0 or int(entity.get("ammo", 0)) >= int(entity.get("max_ammo", 0)):
		return 0.0
	var duration: float = float(_weapon_stats(entity)["reload"]) * float(entity.get("action_multiplier", 1.0))
	entity["reload_duration"] = duration
	entity["reload_remaining"] = duration
	entity["aim_progress"] = 0.0
	entity["aim_state"] = "lowered"
	if str(entity.get("kind","")) == "unit":
		_room_busy_tick[str(entity.id)] = true
		_begin_reload_cover(entity)
	return duration

func _finish_resource_reload(entity: Dictionary) -> int:
	var transferred: int = mini(maxi(0, int(entity.get("max_ammo", 0)) - int(entity.get("ammo", 0))), maxi(0, int(entity.get("reserve_ammo", 0))))
	entity["ammo"] = int(entity.get("ammo", 0)) + transferred
	entity["reserve_ammo"] = int(entity.get("reserve_ammo", 0)) - transferred
	entity["reload_remaining"] = 0.0
	entity["aim_progress"] = 0.0
	entity["aim_state"] = "idle"
	_store_weapon_resource(entity)
	if str(entity.get("kind","")) == "unit": _finish_reload_cover(entity)
	return transferred

func _weapon_penetration(entity: Dictionary) -> float:
	return float({"standard": 0.6, "light": 0.45, "shotgun": 0.65, "suppressed": 0.6, "pico_p1": 0.4}.get(str(entity.get("current_weapon", entity.get("weapon", "standard"))), 0.6))

func _shot_solution(attacker: Dictionary, target: Dictionary, choose_hit: bool = false) -> Dictionary:
	_refresh_weapon_state(attacker)
	var origin: Vector2 = Vector2(float(attacker.weapon_origin[0]), float(attacker.weapon_origin[1]))
	var height: float = float(attacker.weapon_origin[2])
	var preferred: float = CombatSpatial.target_height(target)
	var best: Dictionary = {}
	var best_cost: float = INF
	var available: Array = []
	var total_weight: float = 0.0
	for sample: Dictionary in CombatSpatial.samples(target):
		var point: Vector2 = sample.point
		var sample_height: float = float(sample.height)
		var profile: Dictionary = nav.shot_profile_height(origin, point, height, sample_height, _weapon_penetration(attacker))
		if not bool(profile.clear):
			continue
		var region: String = str(sample.get("region", "head" if sample_height - float(target.get("base_height", 0.0)) > CombatSpatial.body_height(target) * 0.82 else ("limb" if sample_height - float(target.get("base_height", 0.0)) < CombatSpatial.body_height(target) * 0.50 else "torso")))
		var candidate: Dictionary = {"origin": origin, "origin_height": height, "point": point, "target_height": sample_height, "transmission": float(profile.transmission), "hit_part": region}
		var weight: float = float(sample.get("weight", 0.25)) * float(profile.transmission)
		available.append({"solution": candidate, "weight": weight})
		total_weight += weight
		var cost: float = absf(sample_height - preferred) + (1.0 - float(profile.transmission))
		if cost < best_cost:
			best_cost = cost
			best = candidate
	if choose_hit and not available.is_empty():
		var draw: float = _hit_region_rng.randf() * total_weight
		for entry: Dictionary in available:
			draw -= float(entry.weight)
			if draw <= 0.0: return entry.solution
	return best

func _remember_aim(attacker: Dictionary, target: Dictionary) -> void:
	# Only an observed point is retained. Neither simulation nor animation follows
	# a hidden target's live transform after contact is lost.
	var previous: Array = attacker.get("_aim_position", [])
	var prepared: bool = attacker.get("kind", "") == "enemy" and bool(attacker.get("door_ready", false)) and str(attacker.get("_aim_target", "")).begins_with("door:") and str(attacker.get("aim_state", "")) == "ready" and absf(angle_difference(float(attacker.get("aim_facing", attacker.facing)), (_position(target) - _position(attacker)).angle())) <= deg_to_rad(18.0)
	if prepared: attacker["_door_contact_prepared"] = true
	elif str(attacker.get("_aim_target", "")) != str(target.id): attacker.erase("_door_contact_prepared")
	if (str(attacker.get("_aim_target", "")) != str(target["id"]) and not prepared) or (previous.size() == 2 and absf(angle_difference((_point(previous) - _position(attacker)).angle(), (_position(target) - _position(attacker)).angle())) > deg_to_rad(18.0)):
		attacker["aim_progress"] = 0.0
	attacker["_aim_position"] = _array_position(target)
	attacker["_aim_target"] = str(target["id"])
	attacker["_aim_observed_at"] = time
	if attacker.get("kind", "") == "enemy" and not str(target.id).begins_with("door:"): attacker["door_ready"] = false

func _command_hands_busy(entity: Dictionary) -> bool:
	if str(entity.get("status", "")) == "RELOADING":
		return true
	var command: Dictionary = _active(entity)
	if command.is_empty() or str(command.get("state", "")) not in ["RUNNING", "WAITING"]:
		return false
	var type: String = str(command.get("type", ""))
	if command.get("phase", "") in ["BREACH_RETREAT", "BREACH_SAFE_WAIT", "SHOTGUN_RETREAT"]: return false
	if type in ["RELOAD", "SWITCH_WEAPON", "THROW_STUN", "THROW_SMOKE", "THROW_FRAG"]:
		return true
	if type in ["SECURE_CIVILIAN", "ARREST"]:
		return str(entity.get("status", "")) == "SECURING"
	if type == "PEEK_CAMERA":
		return str(command.get("phase", "APPROACH")) == "CAMERA"
	if type == "OPEN_AND_FLASH" and str(command.get("phase", "APPROACH")) in ["PREPARE", "WAIT_EXPLOSION"]:
		return true
	if DOOR_COMMANDS.has(type):
		# An approach or a wait for another operator leaves both hands free.
		# The actual leaf owner still lowers the weapon while opening/peeking,
		# including a blocked sweep or a short clearance step.
		var door: Dictionary = _find(doors, str(command.get("args", {}).get("door_id", "")))
		return not door.is_empty() and str(door.get("owner_id", "")) == str(entity.get("id", "")) and str(door.get("owner_command_id", "")) == str(command.get("id", ""))
	return false

func _update_presentation_aim(entity: Dictionary) -> void:
	if not _can_act(entity):
		entity["aim_progress"] = 0.0
		entity["aim_state"] = "lowered"
		return
	if bool(entity.get("_hostage_aiming", false)):
		_advance_authoritative_aim(entity, true)
		return
	if _command_hands_busy(entity):
		entity["aim_progress"] = 0.0
		_advance_authoritative_aim(entity, false)
		entity["aim_state"] = "lowered"
		return
	var hostile: bool = entity["kind"] == "enemy"
	if hostile and bool(entity.get("_door_contact_prepared", false)) and str(entity.get("_aim_target", "")) == str(entity.get("_target", "")) and not entity.get("_observed", []).is_empty():
		_advance_authoritative_aim(entity, true)
		return
	if hostile and bool(entity.get("door_ready", false)) and str(entity.get("_aim_target", "")).begins_with("door:"):
		_advance_authoritative_aim(entity, true)
		return
	var candidates: Array = units if hostile else enemies
	if not hostile:
		var chosen := _combat_target(entity, candidates, false)
		if not chosen.is_empty(): _remember_aim(entity, chosen)
		_advance_authoritative_aim(entity, not chosen.is_empty())
		return
	var nearest: float = INF
	var observed: Dictionary = {}
	for candidate: Dictionary in candidates:
		if float(candidate["hp"]) <= 0.0 or not observation_ready(entity, candidate) or not can_see(entity, candidate):
			continue
		if hostile and (str(candidate["id"]) != str(entity["_target"]) or _is_target(entity)):
			continue
		# A friendly pose must not reveal a contact still absent from perception.
		if not hostile and not bool(candidate.get("visible", false)):
			continue
		var distance: float = _position(entity).distance_to(_position(candidate))
		if distance > float(_weapon_stats(entity)["range"]):
			continue
		if str(candidate["id"]) == str(entity["_aim_target"]):
			observed = candidate
			break
		if distance < nearest:
			nearest = distance
			observed = candidate
	if not observed.is_empty():
		_remember_aim(entity, observed)
	_advance_authoritative_aim(entity, not observed.is_empty())

func _friendly_threat_score(unit: Dictionary, enemy: Dictionary) -> float:
	var distance := _position(unit).distance_to(_position(enemy))
	var score := -distance * 2.0
	var aiming: bool = str(enemy.get("aim_state", "")) == "ready" and int(enemy.get("ammo", 0)) > 0 and _can_act(enemy) and absf(angle_difference(float(enemy.get("aim_facing", enemy.facing)), (_position(unit) - _position(enemy)).angle())) <= deg_to_rad(15.0)
	if aiming: score += 100.0
	if distance <= 1.0: score += 60.0
	var command := _active(unit)
	if command.get("type", "") == "MOVE":
		var path: Array = command.get("path", [])
		var cursor := int(command.get("path_cursor", 0))
		var origin := _position(unit)
		for waypoint: Array in path.slice(cursor):
			var point := _point(waypoint)
			if _movement_segment_distance_squared(_position(enemy), origin, point) <= pow(_movement_body_spacing() + 0.1, 2):
				score += 50.0
				break
			origin = point
	for door: Dictionary in doors:
		if _position(enemy).distance_to(_position(door)) <= 1.5:
			score += 40.0
			break
	if int(enemy.get("ammo", 0)) > 0 and not bool(enemy.get("surrendered", false)) and absf(angle_difference(float(enemy.facing), (_position(unit) - _position(enemy)).angle())) <= PI / 4.0: score += 20.0
	var sector: Dictionary = unit.get("sector", {})
	if not aiming and distance > 1.0 and not sector.is_empty() and time < float(sector.get("until", 0.0)):
		var bearing := (_position(enemy) - _position(unit)).angle()
		if not _sector_contains(sector, bearing): score -= 60.0
	return score

func _sector_contains(sector: Dictionary, bearing: float) -> bool:
	var start := float(sector.start)
	if absf(float(sector.end) - start) >= TAU - 0.000001: return true
	var width := fposmod(float(sector.end) - start, TAU)
	return fposmod(bearing - start, TAU) <= width + 0.000001

func _combat_target(attacker: Dictionary, candidates: Array, hostile: bool, forced_target: String = "") -> Dictionary:
	var target: Dictionary = {}
	var best := -INF
	var nearest := INF
	for candidate: Dictionary in candidates:
		if float(candidate.hp) <= 0.0 or bool(candidate.get("arrested", false)): continue
		if not forced_target.is_empty() and str(candidate.id) != forced_target: continue
		var breach_exposure: bool = hostile and not forced_target.is_empty() and _shotgun_exposure_ready(attacker, candidate)
		if hostile and str(candidate.id) != str(attacker.get("_target", "")) and not breach_exposure: continue
		if not hostile and bool(candidate.get("surrendered", false)) and forced_target.is_empty(): continue
		if not breach_exposure and (not observation_ready(attacker, candidate) or not _can_engage_target(attacker, candidate, hostile)): continue
		var distance := _position(attacker).distance_to(_position(candidate))
		if distance > _effective_weapon_range(attacker): continue
		var score: float = -distance if hostile else _friendly_threat_score(attacker, candidate)
		if score > best or (is_equal_approx(score, best) and (distance < nearest or (is_equal_approx(distance, nearest) and (target.is_empty() or str(candidate.id) < str(target.id))))):
			best = score
			nearest = distance
			target = candidate
	return target

func _combat(attacker: Dictionary, candidates: Array, hostile: bool, forced_target: String = "") -> void:
	if not _can_act(attacker) or float(attacker["_cooldown"]) > 0.0 or float(attacker["_reaction"]) > 0.0 or int(attacker["ammo"]) <= 0:
		if int(attacker["ammo"]) <= 0 and not hostile and attacker["status"] not in ["RELOADING", "BLOCKED"]:
			attacker["status"] = "OUT_OF_AMMO" if int(attacker.get("reserve_ammo", 0)) <= 0 else "EMPTY"
		return
	if _command_hands_busy(attacker):
		return
	if float(attacker.get("_peek_remaining", 0.0)) > 0.0:
		return
	var weapon: Dictionary = _weapon_stats(attacker)
	var target := _combat_target(attacker, candidates, hostile, forced_target)
	if target.is_empty():
		return
	_remember_aim(attacker, target)
	_advance_authoritative_aim(attacker, true)
	if str(attacker.get("aim_state", "idle")) != "ready":
		if not hostile and attacker["status"] not in ["MOVING", "WAITING"]:
			attacker["status"] = "AIMING"
		return
	# Physical shot checks use the simulated muzzle and target body samples,
	# independent of skeleton animation or temporary peek perception.
	var solution: Dictionary = _shot_solution(attacker, target, true)
	if solution.is_empty() or not fire_line_clear(attacker, target, solution):
		if not hostile:
			attacker["status"] = "HOLD_FIRE"
		return
	attacker["ammo"] = int(attacker["ammo"]) - 1
	if not hostile:
		_room_fired_tick[str(attacker.id)] = true
		var contact_room: String = room_control.room_at(_position(target), float(target.get("base_height", 0.0)))
		if not contact_room.is_empty(): _room_contacts_tick.append({"room_id":contact_room})
	attacker.erase("_door_contact_prepared")
	_store_weapon_resource(attacker)
	attacker["_cooldown"] = (_enemy_combat_stat(attacker, "interval") if hostile else float(weapon["interval"])) * float(attacker.get("fire_interval_multiplier", 1.0)) * (float(EquipmentCatalog.catalog().get("traits", {}).get("marksman", {}).get("interval_multiplier", 1.5)) if str(attacker.get("trait", "")) == "marksman" else 1.0)
	var hit: bool = _rng.randf() < _shot_accuracy(attacker, target, hostile)
	var damage: float = (_enemy_combat_stat(attacker, "damage") if hostile else float(weapon["damage"])) * float(solution.transmission)
	if not hostile:
		shots_fired += 1
		_mark_deployed(attacker)
		if bool(target.get("surrendered", false)):
			unlawful_shots += 1
			if _p5_active: observed_statistics.record_unlawful_shot()
			if _currently_observed(target):
				var fact := _room_person_fact(target)
				fact["unit_id"] = str(attacker.id)
				doctrine.record_room_unlawful(fact)
		attacker["status"] = "ENGAGING"
		if not bool(attacker["facing_locked"]):
			attacker["facing"] = (_position(target) - _position(attacker)).angle()
	_apply_suppression(attacker, target)
	var protection: Dictionary = _hit_protection(attacker, target, solution)
	doctrine.record_shot(self, attacker, target, hostile, hit)
	if hit:
		damage *= float(protection.damage_multiplier)
		var health_before := float(target.hp)
		target["hp"] = maxf(0.0, health_before - damage)
		_record_health_damage(target, health_before, float(target.hp))
		target["last_hit_part"] = protection.hit_part
		target["last_hit_direction"] = protection.hit_direction
		target["last_hit_protection"] = protection.protection
		if protection.protection == "blocked":
			target["_reaction"] = maxf(float(target.get("_reaction", 0.0)), 0.16)
			target["aim_progress"] = minf(float(target.get("aim_progress", 0.0)), 0.55)
		_update_combat_state(target, float(target.get("_combat_dt", 1.0 / 30.0)))
		if target["kind"] == "unit":
			hits_taken += 1
			target["_last_hit_time"] = time
			if float(target["hp"]) > 0.0:
				target["_incoming_fire_facing"] = snappedf((_position(attacker) - _position(target)).angle(), PI / 8.0)
				target["_incoming_fire_until"] = time + HIT_REACTION_SECONDS
			if str(target.get("trait", "")) == "hold_after_hit":
				target["_reaction"] = maxf(1.0, float(target["_reaction"]))
		elif target["kind"] == "enemy" and float(target["hp"]) > 0.0 and not _is_target(target):
			# A hit supplies a coarse incoming direction, not the shooter's live location.
			_receive_combat_alert(target, _heard_region(_position(attacker)))
			_take_enemy_cover(target, _heard_region(_position(attacker)))
	var shot_data: Dictionary = {"attacker_id": attacker["id"], "target_id": target["id"], "hostile": hostile, "hit": hit, "weapon_origin": attacker.weapon_origin.duplicate(), "target_height": solution.target_height, "transmission": solution.transmission}
	shot_data.merge(protection)
	shot_data["damage"] = damage if hit else 0.0
	shot_data["weapon"] = str(attacker.get("current_weapon", attacker.weapon))
	# An unseen attacker is represented only by a coarse sound region.
	if not hostile or _currently_observed(attacker):
		_event("SHOT", "위협 대응" if not hostile else "대원 피격 위험", _array_position(attacker), _array_position(target), shot_data)
	_emit_sound(_position(attacker), float(weapon.get("sound", 10.0)), "총성 감지", "enemy" if hostile else "unit")
	if float(target["hp"]) <= 0.0:
		target["status"] = "INCAPACITATED"
		if target["kind"] == "unit":
			_release_door_owner(str(target["id"]))
		if target["kind"] == "enemy":
			kills += 1
			target["visible"] = true
			_remember_enemy_state(target)
		_event("INCAPACITATED", "위협 무력화" if target["kind"] == "enemy" else str(target["name"]) + " · 행동 불능", [], _array_position(target), {"entity_id": target["id"], "kind": target["kind"]})
		for command: Dictionary in target["commands"]:
			if command["state"] not in ["SUCCEEDED", "CANCELLED", "FAILED"]:
				command["state"] = "CANCELLED"
				command["reason"] = "대원 행동 불능"

func _effective_weapon_range(entity: Dictionary) -> float:
	return float(_weapon_stats(entity).range) + float(entity.get("range_bonus", 0.0)) + (float(EquipmentCatalog.catalog().get("traits", {}).get("marksman", {}).get("range_add", 2.0)) if str(entity.get("trait", "")) == "marksman" else 0.0)

func _weapon_stats(entity: Dictionary) -> Dictionary:
	var id: String = str(entity.get("current_weapon", entity.get("weapon", "standard")))
	if entity.get("kind", "") != "unit":
		return WEAPONS.get(id, WEAPONS.standard)
	var cached: Dictionary = entity.get("_secondary_stats", {}) if str(entity.get("active_weapon", "primary")) == "secondary" else entity.get("_primary_stats", {})
	if not cached.is_empty() and str(cached.get("id", "")) == id: return cached
	return EquipmentCatalog.weapon_stats(id, entity.get("attachments", []) if str(entity.get("active_weapon", "primary")) == "primary" else [])

func _armor_penetration(entity: Dictionary) -> float:
	var id: String = str(entity.get("current_weapon", entity.get("weapon", "standard")))
	return float(EquipmentCatalog.weapon_stats(id, entity.get("attachments", []) if entity.get("kind", "") == "unit" and entity.get("active_weapon", "primary") == "primary" else []).get("penetration", 22.0))

func _store_weapon_resource(entity: Dictionary) -> void:
	var slot: String = str(entity.get("active_weapon", "primary"))
	entity[slot + "_ammo"] = int(entity.get("ammo", 0))
	entity[slot + "_reserve_ammo"] = int(entity.get("reserve_ammo", 0))

func _switch_weapon_slot(entity: Dictionary, slot: String) -> void:
	_store_weapon_resource(entity)
	entity["active_weapon"] = slot
	entity["current_weapon"] = str(entity.get("sidearm", "none")) if slot == "secondary" else str(entity.weapon)
	var stats: Dictionary = _weapon_stats(entity)
	entity["max_ammo"] = int(stats.ammo)
	entity["ammo"] = int(entity.get(slot + "_ammo", 0))
	entity["reserve_ammo"] = int(entity.get(slot + "_reserve_ammo", 0))
	entity["aim_progress"] = 0.0
	entity["aim_state"] = "lowered"
	entity["_cooldown"] = 0.0
	_refresh_weapon_state(entity)

func _hit_protection(attacker: Dictionary, target: Dictionary, solution: Dictionary) -> Dictionary:
	var region: String = str(solution.get("hit_part", "torso"))
	var relative: float = angle_difference(float(target.get("body_facing", target.get("facing", 0.0))), (_position(attacker) - _position(target)).angle())
	var direction: String = "front" if absf(relative) <= PI / 3.0 else ("back" if absf(relative) >= PI * 2.0 / 3.0 else "side")
	var protection: Dictionary = EquipmentCatalog.protection(target.get("_loadout", target), region, relative, _armor_penetration(attacker)) if target.get("kind", "") == "unit" else {"protected": false, "reduction": 0.0, "armor_id": "none", "panel": "none"}
	var protected: bool = bool(protection.get("protected", false))
	var reduction: float = clampf(float(protection.get("reduction", 0.0)), 0.0, 1.0)
	return {"hit_part": region, "hit_direction": direction, "protection": "blocked" if protected and reduction > 0.0 else ("penetrated" if str(protection.get("panel", "none")) != "none" else "unprotected"), "armor_id": str(protection.get("armor_id", "none")), "panel": str(protection.get("panel", "none")), "damage_multiplier": 1.0 - reduction}

func fire_line_clear(attacker: Dictionary, target: Dictionary, solution: Dictionary = {}) -> bool:
	if solution.is_empty(): solution = _shot_solution(attacker, target)
	if solution.is_empty():
		return false
	var origin: Vector2 = solution.origin
	var end: Vector2 = solution.point
	var friends: Array = enemies if attacker["kind"] == "enemy" else units
	var protected_enemies: Array = []
	if attacker["kind"] == "unit":
		for enemy: Dictionary in enemies:
			if bool(enemy.get("surrendered", false)) or bool(enemy.get("arrested", false)):
				protected_enemies.append(enemy)
	for entity: Dictionary in friends + civilians + protected_enemies:
		if entity["id"] == attacker["id"] or entity["id"] == target["id"] or float(entity["hp"]) <= 0.0:
			continue
		# A longer rifle can extend past an adjacent teammate. Check its full
		# body-to-muzzle prefix as well as the outgoing bullet segment, so the
		# raised weapon cannot bypass the existing friendly/civilian safety rule.
		var grip: Vector2 = _position(attacker)
		var prefix: Vector2 = Geometry2D.get_closest_point_to_segment(_position(entity), grip, origin)
		var base: float = float(entity.get("base_height", 0.0))
		var muzzle_height: float = float(solution.origin_height)
		if prefix.distance_to(_position(entity)) < 0.29 and muzzle_height >= base and muzzle_height <= base + CombatSpatial.body_height(entity):
			return false
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(_position(entity), origin, end)
		if closest.distance_to(_position(entity)) < 0.29 and origin.distance_to(_position(entity)) < origin.distance_to(end):
			var distance_ratio: float = origin.distance_to(closest) / maxf(0.001, origin.distance_to(end))
			var line_height: float = lerpf(float(solution.origin_height), float(solution.target_height), distance_ratio)
			var base_height: float = float(entity.get("base_height", 0.0))
			if line_height >= base_height and line_height <= base_height + CombatSpatial.body_height(entity):
				return false
	return true

func _door_sound_audibility(position: Vector2, listener: Vector2, radius: float) -> float:
	var heard: float = _acoustic.audibility(position, listener, radius)
	for door: Dictionary in doors:
		if _position(door).distance_to(position) > 0.2: continue
		var normal := Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
		# A vibrating leaf is a source on both faces of its portal. Evaluate
		# both real acoustic routes so the room-label boundary does not charge
		# an extra closed-door loss on the leaf's own interior sound.
		for side: float in [-1.0, 1.0]: heard = maxf(heard, _acoustic.audibility(position + normal * side * 0.3, listener, radius))
	return heard

func _stimulus_audibility(position: Vector2, listener: Dictionary, radius: float, context: Dictionary) -> float:
	if context.is_empty(): return _acoustic.audibility(position,_position(listener),radius)
	var acoustic_context := context.duplicate(true)
	acoustic_context["listener_floor"] = float(listener.get("base_height",0.0))
	return _acoustic.audibility(position,_position(listener),radius,acoustic_context)

func _emit_sound(position: Vector2, radius: float, label: String, source_kind: String, context: Dictionary = {}) -> void:
	if radius <= 0.0:
		return
	var coarse: Vector2 = _heard_region(position)
	for enemy: Dictionary in enemies:
		# These listeners have no response branch for this stimulus. In
		# particular, friendly guard footsteps do not re-alert their own team,
		# and a directly observed contact already supersedes ordinary noise.
		if label != "총성 감지" and (source_kind != "unit" or not enemy.get("_observed", []).is_empty()):
			continue
		if not _can_act(enemy) or _is_target(enemy):
			continue
		if _position(enemy).distance_to(position) < 0.3:
			continue
		var audibility: float = _door_sound_audibility(position, _position(enemy), radius) if context.is_empty() and label in ["출입문 소리", "출입문 파손 소리"] else _stimulus_audibility(position,enemy,radius,context)
		if audibility <= 0.0:
			continue
		if source_kind == "unit" and label in ["출입문 소리", "출입문 파손 소리"]:
			for door: Dictionary in doors:
				if _position(door).distance_to(position) <= 0.2: _prepare_door_ready(enemy, door)
		if label == "총성 감지":
			_begin_rear_response(enemy, coarse)
			_receive_combat_alert(enemy, coarse)
		elif source_kind == "unit" and enemy["_observed"].is_empty():
			enemy["_heard_memory"] = {"position": [coarse.x, coarse.y], "time": time, "confidence": 0.15 + audibility * 0.35, "label": label}
			enemy["_last_known"] = [coarse.x, coarse.y]
			enemy["_last_known_time"] = time
			enemy["_detect_reason"] = "sound"
			enemy["awareness_state"] = "SUSPICIOUS"
			enemy["awareness_confidence"] = maxf(float(enemy.get("awareness_confidence", 0.0)), 0.15 + audibility * 0.35)
			enemy["observation_source"] = "sound"
			enemy["_ai_state"] = "SUSPICIOUS"
			enemy["_investigate_arrived_at"] = -1.0
			enemy["_ai_path"] = []
			enemy["_ai_route_attempted"] = false
	if label == "총성 감지":
		for civilian: Dictionary in civilians:
			if float(civilian.get("hp", 0.0)) > 0.0 and _stimulus_audibility(position,civilian,radius,context) > 0.0:
				var was_calm: bool = float(civilian.get("_fear", 0.0)) < 0.15
				civilian["_fear"] = minf(1.5, float(civilian.get("_fear", 0.0)) + 0.75)
				civilian["_fear_updated_at"] = time
				civilian["_panic_origin"] = [coarse.x, coarse.y]
				if was_calm: civilian["_panic_pause_until"] = time + 0.3 + float(absi(str(civilian.id).hash()) % 5) * 0.1
				civilian["status"] = "PANIC"
				if time >= float(civilian.get("_panic_recheck_at", 0.0)):
					civilian["_panic_recheck_at"] = time + 2.0
					civilian["_panic_target"] = _civilian_panic_target(civilian)
					civilian["_ai_path"] = []
	if source_kind != "enemy":
		return
	var heard: bool = false
	for unit: Dictionary in units:
		if float(unit["hp"]) > 0.0 and _stimulus_audibility(position,unit,radius,context) > 0.0:
			heard = true
			if unit.get("_observed", []).is_empty():
				unit["_heard_memory"] = {"position": [coarse.x, coarse.y], "time": time, "confidence": 0.3, "label": label}
				unit["awareness_state"] = "SUSPICIOUS"
				unit["awareness_confidence"] = maxf(float(unit.get("awareness_confidence", 0.0)), 0.3)
				unit["observation_source"] = "sound"
			break
	if heard:
		var zone: Dictionary = {"x": coarse.x, "z": coarse.y, "radius": 2.8, "time": time, "label": label}
		_sound_zones.append(zone)
		if _sound_zones.size() > 12:
			_sound_zones.pop_front()

func _advance_interactive_targets(dt: float) -> void:
	# Inspection/recovery/boarding is an explicit objective, independent of
	# eliminating every threat. It advances only during the simulation clock.
	for target: Dictionary in interactive_targets:
		if bool(target.get("completed", false)): continue
		var operator: Dictionary = {}
		for unit: Dictionary in units:
			if not _can_act(unit): continue
			if absf(float(unit.x) - float(target.x)) > float(target.w) * 0.5 or absf(float(unit.z) - float(target.z)) > float(target.d) * 0.5: continue
			if Vector2(float(unit.get("velocity_x", 0.0)), float(unit.get("velocity_z", 0.0))).length() > 0.15: continue
			operator = unit
			break
		# Targets are ordered stages. Extraction near the insertion point must
		# remain pending until the inspection/recovery stages are complete.
		if operator.is_empty(): return
		target["progress"] = minf(float(target.duration), float(target.progress) + dt)
		if float(target.progress) + 0.000001 >= float(target.duration):
			target["completed"] = true
			_event("TARGET_COMPLETE", str(target.label) + " 완료", [], [], {"target_id": str(target.id), "unit_id": str(operator.id)})
		return

func _check_result() -> void:
	var alive: int = 0
	var neutralized: int = 0
	var rescued: int = 0
	var total_health: float = 0.0
	var civilian_failed: bool = false
	for unit: Dictionary in units:
		if float(unit["hp"]) > 0.0:
			alive += 1
		total_health += maxf(0.0, float(unit["hp"])) / maxf(1.0, float(unit["max_hp"]))
	for enemy: Dictionary in enemies:
		if float(enemy["hp"]) <= 0.0 or bool(enemy.get("arrested", false)):
			neutralized += 1
	for civilian: Dictionary in civilians:
		if bool(civilian["secured"]):
			rescued += 1
		if float(civilian["hp"]) <= 0.0:
			civilian_failed = true
	var win_rules: Array = mission.get("win", [{"type": "neutralize_all"}, {"type": "secure_all_civilians"}])
	var fail_rules: Array = mission.get("fail", [{"type": "no_civilian_loss"}])
	var win: bool = not win_rules.is_empty()
	var failure_reason: String = ""
	for rule: Dictionary in win_rules:
		win = win and _rule_satisfied(rule)
		if rule.get("type", "") in ["time_limit", "before_alert", "no_civilian_loss"] and not _rule_satisfied(rule):
			failure_reason = _rule_failure_reason(rule)
	for rule: Dictionary in fail_rules:
		if not _rule_satisfied(rule): failure_reason = _rule_failure_reason(rule)
	if not mission.has("win") and enemies.is_empty() and civilians.is_empty() and not bool(mission.get("allow_empty_result", false)):
		win = false
	if (alive > 0 and failure_reason.is_empty() and not win) or units.is_empty():
		return
	if win and failure_reason.is_empty():
		if not _frag_projectiles.is_empty(): return
		for unit: Dictionary in units:
			if unit.commands.any(func(command: Dictionary) -> bool: return command.type == "THROW_FRAG" and command.state in ["PENDING","RUNNING","WAITING"]): return
	var success: bool = win and alive > 0 and failure_reason.is_empty()
	var objective_score: float = 40.0 * float(neutralized) / float(maxi(1, enemies.size())) if not enemies.is_empty() else 40.0
	var civilian_score: float = 40.0 * float(rescued) / float(maxi(1, civilians.size())) if not civilians.is_empty() else 0.0
	var squad_score: float = 20.0 * total_health / float(maxi(1, units.size()))
	var score: int = roundi((objective_score + civilian_score + squad_score) * (100.0 / 60.0 if civilians.is_empty() else 1.0))
	if success and neutralized < enemies.size():
		score = roundi(80.0 + squad_score)
	score = maxi(0, score - unlawful_shots * 40)
	var rank: String = "S" if score >= 95 else ("A" if score >= 80 else ("B" if score >= 65 else "C"))
	result = {"success": success, "status": "SUCCESS" if success else "FAILED", "title": "작전 완료" if success else "작전 중단", "reason": "모든 목표를 달성했습니다" if success else (failure_reason if not failure_reason.is_empty() else "모든 대원이 행동 불능입니다"), "score": score, "rank": rank if success else "—", "time": time, "duration": time, "neutralized": neutralized, "enemies_total": enemies.size(), "rescued": rescued, "civilians_total": civilians.size(), "survivors": alive, "units_total": units.size(), "losses": units.size() - alive, "command_failures": command_failures, "shots_fired": shots_fired, "plan_revisions": plan_revisions}
	result.merge(_statistics())
	result["room_states"] = room_control.snapshot(true)
	result["room_states_observed"] = room_control.snapshot(false)
	if _p5_active:
		_refresh_frag_observations()
		result["stats_observed"] = observed_statistics.bundle(units, success)
		var awarded: Dictionary = observed_statistics.stars(mission.get("stars", []), result, units, success, tick)
		result["stars"] = awarded.actual
		result["stars_observed"] = awarded.observed
	result["seed"] = int(mission.get("seed", 42))
	result["variant"] = str(mission.get("variant", "normal"))
	result["modifiers"] = mission.get("modifiers", []).duplicate()
	_event("MISSION_END", str(result["title"]) + " · " + str(result["reason"]))

func snapshot(reveal: bool = false) -> Dictionary:
	var full: bool = reveal
	var exposed_enemies: Array = []
	for enemy: Dictionary in enemies:
		if full or bool(enemy["visible"]):
			exposed_enemies.append(_public_entity(enemy))
		elif enemy.has("last_seen"):
			# A minimal observation record cannot leak hidden movement, ammo, FSM or health.
			exposed_enemies.append(_last_seen_entity(enemy))
	var exposed_civilians: Array = []
	for civilian: Dictionary in civilians:
		if full or bool(civilian["visible"]):
			exposed_civilians.append(_public_entity(civilian))
	var neutralized: int = 0
	var rescued: int = 0
	for enemy: Dictionary in enemies:
		if float(enemy["hp"]) <= 0.0 or bool(enemy.get("arrested", false)):
			neutralized += 1
	for civilian: Dictionary in civilians:
		if bool(civilian["secured"]):
			rescued += 1
	var exposed_units: Array = []
	for unit: Dictionary in units:
		exposed_units.append(_public_entity(unit))
	var state: Dictionary = {"time": time, "tick": tick, "units": exposed_units, "enemies": exposed_enemies, "civilians": exposed_civilians, "doors": _public_doors(full), "events": events.duplicate(true), "result": result.duplicate(true), "objectives": {"neutralized": neutralized, "total": enemies.size(), "rescued": rescued, "civilians_total": civilians.size()}, "pause_requested": pause_requested, "command_failures": command_failures, "shots_fired": shots_fired, "plan_revisions": plan_revisions, "sound_zones": _sound_zones.duplicate(true), "smoke_zones": _smoke_zones.duplicate(true), "flash_projectiles": _flash_projectiles.duplicate(true), "broken_glass": _broken_glass.duplicate(true), "seed": int(mission.get("seed", 42)), "variant": str(mission.get("variant", "normal")), "modifiers": mission.get("modifiers", []).duplicate(), "win": mission.get("win", []).duplicate(true), "fail": mission.get("fail", []).duplicate(true), "stars": mission.get("stars", []).duplicate(true)}
	if not interactive_targets.is_empty():
		state["interactive_targets"] = interactive_targets.duplicate(true)
		state.objectives["targets_completed"] = interactive_targets.filter(func(target: Dictionary) -> bool: return bool(target.completed)).size()
		state.objectives["targets_total"] = interactive_targets.size()
	state.merge(_statistics())
	if _p5_active:
		state["frag_projectiles"] = _frag_projectiles.duplicate(true)
		state["stats_observed"] = observed_statistics.bundle(units, bool(result.get("success", false)))
		state["roe"] = MissionCatalog.roe(mission)
	state["room_states"] = room_control.snapshot(true)
	state["room_states_observed"] = room_control.snapshot(false)
	state["pause_reason"] = pause_reason
	if not pause_unit_id.is_empty(): state["pause_unit_id"] = pause_unit_id
	if not reveal:
		DoctrineMetrics.filter_observed_statistics(state)
		RoomControl.project_observed_state(state)
		state["events"] = RoomControl.filter_observed_call_events(state.events)
	return state

func snapshot_pair() -> Dictionary:
	# Recording and presentation consume immutable snapshots of the same tick.
	# Copy owned common data once, then independently filter hidden observations.
	# Ordinary snapshot() remains independently owned for callers that edit it.
	var record: Dictionary = snapshot(true)
	var observed: Dictionary = record.duplicate(false)
	if _p5_active:
		observed["objectives"] = record.objectives.duplicate(true)
		observed["result"] = record.result.duplicate(true)
	var visible_enemies: Array = []
	for index: int in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		if bool(enemy["visible"]):
			visible_enemies.append(record.enemies[index])
		elif enemy.has("last_seen"):
			visible_enemies.append(_last_seen_entity(enemy))
	observed["enemies"] = visible_enemies
	var visible_civilians: Array = []
	for index: int in range(civilians.size()):
		if bool(civilians[index]["visible"]):
			visible_civilians.append(record.civilians[index])
	observed["civilians"] = visible_civilians
	observed["doors"] = _public_doors(false)
	DoctrineMetrics.filter_observed_statistics(observed)
	RoomControl.project_observed_state(observed)
	observed["events"] = RoomControl.filter_observed_call_events(observed.events)
	return {"record": record, "observed": observed}

func _last_seen_entity(enemy: Dictionary) -> Dictionary:
	var point: Array = enemy["last_seen"]
	return {"id": enemy["id"], "name": enemy["name"], "kind": "enemy", "visible": false, "x": point[0], "z": point[1], "last_seen": point.duplicate(), "last_seen_time": enemy["last_seen_time"], "last_seen_age": time - float(enemy["last_seen_time"]), "hp": float(enemy.get("_last_seen_hp", 72.0)), "facing": float(enemy.get("_last_seen_facing", 0.0)), "status": str(enemy.get("_last_seen_status", "UNKNOWN")), "commands": []}

func _public_doors(full: bool = true) -> Array:
	var exposed: Array = []
	for actual: Dictionary in doors:
		var door: Dictionary = actual
		if not full:
			if _door_observations.has(str(actual.id)):
				door = _door_observations[str(actual.id)]
			else:
				# Door locations belong to the supplied floor plan; their state does not.
				door = {"id": actual.id, "x": actual.x, "z": actual.z, "axis": actual.axis, "w": actual.w, "d": actual.d, "state": "CLOSED", "progress": 0.0, "observed": false}
		var safe: Dictionary = {}
		for key: String in door:
			if not key.begins_with("_") and key != "initial_states":
				safe[key] = door[key]
		exposed.append(safe)
	return exposed

func _public_entity(entity: Dictionary) -> Dictionary:
	_store_weapon_resource(entity)
	var copy: Dictionary = {}
	for key: String in entity:
		if key.begins_with("_") or key in ["patrol", "spawns", "equipment", "response_role"]:
			continue
		if key == "door_ready" and (entity.get("kind", "") != "enemy" or not bool(entity.get("visible", false))): continue
		if key == "sector" and entity.get("kind", "") != "unit": continue
		if key == "commands":
			var commands: Array = []
			for command: Dictionary in entity["commands"]:
				var safe_command: Dictionary = {}
				for field: String in command:
					if not field.begins_with("_"):
						safe_command[field] = command[field]
				# The outer entity copy owns this whole nested queue once.
				commands.append(safe_command)
			copy[key] = commands
		else:
			copy[key] = entity[key]
	if entity.get("kind", "") == "unit" and float(entity.get("_peek_remaining", 0.0)) > 0.0:
		copy["peek_origin"] = entity.get("_peek_origin", []).duplicate()
		copy["peek_facing"] = float(entity.get("_peek_facing", 0.0))
		copy["peek_remaining"] = float(entity.get("_peek_remaining", 0.0))
	if entity.get("kind", "") == "unit":
		copy["available_shotgun_breaches"] = _available_shotgun_breaches(entity)
		copy["available_breaches"] = _available_breaches(entity)
		if _p5_active: copy["available_frags"] = _available_frags(entity)
	return copy.duplicate(true)

func _event(type: String, message: String, from: Array = [], to: Array = [], extra: Dictionary = {}) -> void:
	_sequence += 1
	var event: Dictionary = {"seq": _sequence, "tick": tick, "time": time, "type": type, "message": message}
	if not from.is_empty():
		event["from"] = from.duplicate()
	if not to.is_empty():
		event["to"] = to.duplicate()
	for key: String in extra:
		event[key] = extra[key]
	events.append(event)
	if _record_events_enabled: _pending_record_events.append(event)
	if events.size() > 40:
		events.pop_front()

func take_record_events() -> Array:
	# Subscribers drain after each tick/action; simulation-only callers keep no backlog.
	if not _record_events_enabled:
		_record_events_enabled = true
		return events.duplicate(true)
	var batch := _pending_record_events
	_pending_record_events = []
	return batch

func _can_act(entity: Dictionary) -> bool:
	return float(entity.get("hp", 0.0)) > 0.0 and float(entity.get("stunned", 0.0)) <= 0.0 and float(entity.get("flash_recover_remaining", 0.0)) <= 0.0 and not bool(entity.get("surrendered", false)) and not bool(entity.get("arrested", false))

func _update_status_reason(entity: Dictionary) -> void:

	entity["status_reason"] = STATUS_REASONS.get(str(entity["status"]), "")
	if entity["kind"] == "enemy" and _can_act(entity) and float(entity.get("_alert_until", 0.0)) > time:
		entity["status_reason"] = {"cover":"교전 경보 · 엄폐 이동", "guard":"교전 경보 · 접근로 경계", "support":"교전 경보 · 지원 위치 이동"}.get(str(entity.get("_alert_action", "guard")), "교전 경보 · 경계 중")
	if entity["kind"] != "unit" or not _can_act(entity):
		return
	var command: Dictionary = _active(entity)
	if command.is_empty():
		return
	if not str(command.get("reason", "")).is_empty():
		entity["status_reason"] = command["reason"]
	elif command["type"] == "WAIT_FOR_SIGNAL":
		entity["status_reason"] = str(command["args"].get("signal", "A")) + " 신호를 기다리는 중"
	elif command["type"] == "WAIT":
		entity["status_reason"] = "지정한 시간이 끝나기를 기다리는 중"

func _update_presentation_turn(entity: Dictionary) -> void:
	# Foot-turn animation follows the body's authoritative turn, not the gun.
	var facing: float = float(entity.get("body_facing", entity["facing"]))
	var delta_angle: float = angle_difference(float(entity["_turn_last_aim"]), facing)
	var moving: bool = float(entity["travel_distance"]) - float(entity["_turn_last_travel"]) > 0.0005
	entity["_turn_last_aim"] = facing
	entity["_turn_last_travel"] = entity["travel_distance"]
	if moving or not _can_act(entity):
		entity["turn_delta"] = 0.0
		return
	var active: bool = absf(float(entity["turn_delta"])) > 0.001 and time - float(entity["turn_started_at"]) <= PRESENTATION_TURN_SECONDS
	if active:
		entity["turn_delta"] = clampf(float(entity["turn_delta"]) + delta_angle, -PI, PI)
	elif absf(delta_angle) >= deg_to_rad(5.0):
		entity["turn_started_at"] = time
		entity["turn_delta"] = delta_angle
	else:
		entity["turn_delta"] = 0.0

func _find(list: Array, id: String) -> Dictionary:
	for entity: Dictionary in list:
		if str(entity.get("id", "")) == id:
			return entity
	return {}

static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func _position(entity: Dictionary) -> Vector2:
	return Vector2(float(entity.get("x", 0.0)), float(entity.get("z", 0.0)))

func _array_position(entity: Dictionary) -> Array:
	return [float(entity.get("x", 0.0)), float(entity.get("z", 0.0))]

func _set_position(entity: Dictionary, position: Vector2) -> void:
	var displacement: Vector2 = position - _position(entity)
	if displacement.length_squared() > 0.00000001:
		entity["move_facing"] = displacement.angle()
		entity["travel_distance"] = float(entity.get("travel_distance", 0.0)) + displacement.length()
	entity["x"] = position.x
	entity["z"] = position.y
	if not _elevated_rooms.is_empty(): entity["base_height"] = CombatSpatial.floor_base_at(_elevated_rooms, position)

func _configured_units(data: Dictionary) -> Array:
	var sources: Array = data.get("units", []).duplicate(true)
	var roster: Array = data.get("roster", [])
	if not roster.is_empty():
		var selected_sources: Array = []
		var seen: Dictionary = {}
		for member: Variant in roster:
			if not member is Dictionary: continue
			var base_id: String = str(member.get("base_id", member.get("id", "")))
			var source: Dictionary = _find(sources, base_id).duplicate(true)
			if source.is_empty() or seen.has(base_id): continue
			seen[base_id] = true
			source["roster_id"] = str(member.get("id", base_id))
			source["name"] = str(member.get("name", source.get("name", base_id)))
			source["trait"] = str(member.get("trait", ""))
			selected_sources.append(source)
			if selected_sources.size() == 4: break
		if not selected_sources.is_empty(): sources = selected_sources
	var loadout: Dictionary = data.get("loadout", {})
	for source: Dictionary in sources:
		var selected_choice: Variant = loadout.get(str(source.id), loadout.get(str(source.get("roster_id", "")), {}))
		var choice: Dictionary = selected_choice if selected_choice is Dictionary else {}
		if WEAPONS.has(str(choice.get("weapon", ""))):
			if str(source.get("weapon", "standard")) != str(choice.weapon):
				var capacity: int = int(WEAPONS[str(choice.weapon)].ammo)
				var scale: float = 0.5 if data.get("modifiers", []).has("low_ammo") else 1.0
				source["ammo"] = floori(capacity * scale)
				source["reserve_ammo"] = floori(capacity * 3 * scale)
			source["weapon"] = str(choice.weapon)
		for field: String in ["sidearm", "armor", "helmet", "attachments", "appearance", "preset"]:
			if choice.has(field): source[field] = choice[field]
		if choice.has("attachments"):
			var base_capacity: int = int(WEAPONS.get(str(source.get("weapon", "standard")), WEAPONS.standard).ammo)
			var selected_capacity: int = int(EquipmentCatalog.weapon_stats(str(source.get("weapon", "standard")), choice.attachments).ammo)
			if selected_capacity != base_capacity:
				var ammo_scale: float = 0.5 if data.get("modifiers", []).has("low_ammo") else 1.0
				source["ammo"] = floori(float(source.get("ammo", float(base_capacity) * ammo_scale)) * float(selected_capacity) / float(base_capacity))
				source["reserve_ammo"] = floori(float(source.get("reserve_ammo", float(base_capacity * 3) * ammo_scale)) * float(selected_capacity) / float(base_capacity))
		if source.get("appearance") is Dictionary and not str(source.appearance.get("name", "")).is_empty(): source["name"] = str(source.appearance.name)
		if choice.has("equipment"): source["equipment"] = EquipmentCatalog.resolve_loadout(choice).equipment
		var equipment: Variant = source.get("equipment", {})
		if equipment is Array:
			equipment = {"stun": equipment.count("stun"), "smoke": equipment.count("smoke"), "breach": equipment.count("breach")}
		if equipment is Dictionary and choice.has("equipment"):
			source["stuns"] = _equipment_count(equipment.get("stun", 0))
			source["smokes"] = _equipment_count(equipment.get("smoke", 0))
			source["breaches"] = _equipment_count(equipment.get("breach", 0))
		if data.get("modifiers", []).has("no_stun"): source["stuns"] = 0
	return sources

func _equipment_count(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)): return 0
	return clampi(int(value), 0, 2)

func _statistics() -> Dictionary:
	var stats: Dictionary = {"stuns_used": stuns_used, "reloads": reloads, "hits_taken": hits_taken, "units_deployed": units_deployed, "first_alert_time": first_alert_time, "arrests": arrests, "kills": kills, "unlawful_shots": unlawful_shots, "breaches_used": breaches_used, "smokes_used": smokes_used}
	if _p5_active:
		stats["civilian_damage"] = civilian_damage
		stats["unit_damage"] = unit_damage
		stats["frags_used"] = frags_used
		stats["civilian_losses"] = civilians.filter(func(actor: Dictionary) -> bool: return float(actor.hp) <= 0.0 and not _p5_initial_dead.has(str(actor.id))).size()
	stats.merge(doctrine.statistics())
	return stats

func _mark_deployed(unit: Dictionary) -> void:
	if unit.get("kind", "") == "unit" and not _deployed.has(str(unit.id)):
		_deployed[str(unit.id)] = true
		units_deployed = _deployed.size()

func _rule_satisfied(rule: Dictionary) -> bool:
	match str(rule.get("type", "")):
		"rooms_cleared":
			var ids: Array = rule.get("room_ids", [])
			if not rule.has("room_ids"):
				for room: Dictionary in mission.get("rooms", []): ids.append(str(room.id))
			return room_control.cleared(ids)
		"neutralize_all":
			return enemies.all(func(enemy: Dictionary) -> bool: return float(enemy.hp) <= 0.0 or bool(enemy.get("arrested", false)))
		"secure_all_civilians":
			return civilians.all(func(civilian: Dictionary) -> bool: return bool(civilian.secured) and float(civilian.hp) > 0.0)
		"no_civilian_loss":
			return civilians.all(func(civilian: Dictionary) -> bool: return float(civilian.hp) > 0.0)
		"before_alert":
			return first_alert_time < 0.0
		"no_shots":
			return shots_fired == 0
		"targets_complete":
			for target_id: String in rule.get("targets", []):
				var target := _find(interactive_targets, target_id)
				if target.is_empty() or not bool(target.get("completed", false)): return false
			return not rule.get("targets", []).is_empty()
		"time_limit":
			return time <= float(rule.get("seconds", 0.0))
		"reach_zone":
			return units.any(func(unit: Dictionary) -> bool: return float(unit.hp) > 0.0 and _in_zone(_position(unit), rule))
		"escort_to_zone":
			return not civilians.is_empty() and civilians.all(func(civilian: Dictionary) -> bool: return bool(civilian.secured) and float(civilian.hp) > 0.0 and _in_zone(_position(civilian), rule))
	return false

func _in_zone(point: Vector2, rule: Dictionary) -> bool:
	var zone: Variant = rule.get("zone", [])
	if zone is String:
		for item: Dictionary in mission.get("zones", []):
			if item.get("id", "") == zone: zone = [item.x, item.z, item.w, item.d]; break
	if zone is Dictionary: zone = [zone.get("x", 0), zone.get("z", 0), zone.get("w", 0), zone.get("d", 0)]
	if not zone is Array or zone.size() != 4: return false
	return absf(point.x - float(zone[0])) <= float(zone[2]) * 0.5 and absf(point.y - float(zone[1])) <= float(zone[3]) * 0.5

func _rule_failure_reason(rule: Dictionary) -> String:
	match str(rule.get("type", "")):
		"before_alert": return "적 경계 발동으로 잠입 목표 실패"
		"time_limit": return "제한 시간 초과"
		"no_civilian_loss": return "필수 민간인 목표 실패"
		"no_shots": return "무발포 작전에서 사격이 발생했습니다"
	return "임무 규칙 위반"

func _advance_peek(unit: Dictionary, command: Dictionary, door: Dictionary, dt: float) -> void:
	if not bool(command.get("_peeking", false)):
		var target: float = maxf(0.52, float(door.get("progress", 0.0)))
		var clearance: Array = _door_clearance_position(door, unit, target)
		if clearance.is_empty() and not _door_sweep_clear(door, _position(unit), target):
			_fail(unit, command, "문 회전 공간에서 안전하게 물러날 자리가 없습니다")
			return
		var normal: Vector2 = Vector2.RIGHT if door.get("axis", "x") == "z" else Vector2.DOWN
		if normal.dot(_position(door) - _position(unit)) < 0.0: normal = -normal
		unit["_peek_facing"] = normal.angle()
		unit["_peek_remaining"] = 0.0
		command["remaining"] = 1.5 * float(unit.get("action_multiplier", 1.0))
		command["_peeking"] = true
		door["state"] = "OPENING"
		door["_open_target"] = target
		door["_open_duration"] = 0.8 * float(unit.get("action_multiplier", 1.0))
		door["_enemy_opening"] = false
		door["owner_id"] = unit.id
		door["owner_command_id"] = command.id
		if not clearance.is_empty():
			door["_operator_clearance"] = clearance
			door["_clearance_operator_id"] = unit.id
		else:
			door.erase("_operator_clearance")
			door.erase("_clearance_operator_id")
		_emit_sound(_position(door), 2.0, "출입문 소리", "unit")
		_event("DOOR_ACTION", "문을 조금 열어 관측", _array_position(door), [], {"door_id": door.id, "unit_id": unit.id, "radius": 2.0, "kind": "PEEK_DOOR"})
	if door["state"] == "OPENING":
		unit["_peek_remaining"] = 0.0
		command["reason"] = str(door.get("reason", ""))
		if unit.get("status", "") != "MOVING": unit["status"] = "OPENING"
		return
	# Lean only a small, reachable distance on the operator's own side. The
	# actual rotated leaf and jambs still occlude every ray from this eye point.
	var origin: Vector2 = _position(unit)
	var across: Vector2 = Vector2.RIGHT if door.get("axis", "x") == "x" else Vector2.DOWN
	var candidate: Vector2 = origin - across * DoorGeometry.hinge_side(door) * 0.16
	var normal: Vector2 = Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
	if nav.segment_clear(origin, candidate) and (origin - _position(door)).dot(normal) * (candidate - _position(door)).dot(normal) >= 0.0:
		origin = candidate
	unit["_peek_origin"] = [origin.x, origin.y]
	unit["_peek_remaining"] = 0.1
	unit["status"] = "PEEKING"
	command["reason"] = ""
	if not bool(command.get("_peek_observed", false)):
		command["_peek_observed"] = true
		_event("DOOR_PEEK", "실제 문틈 관측", _array_position(door), [], {"door_id": door.id, "unit_id": unit.id, "radius": 0.0})
	command["remaining"] = maxf(0.0, float(command.remaining) - dt)
	if float(command.remaining) <= 0.0:
		unit["_peek_remaining"] = 0.0
		_release_door_owner(str(unit.id), str(command.id))
		_succeed(unit, command)

func _advance_arrest(unit: Dictionary, command: Dictionary, dt: float) -> void:
	var enemy: Dictionary = _find(enemies, str(command.args.enemy_id))
	if enemy.is_empty() or float(enemy.get("hp", 0.0)) <= 0.0:
		_fail(unit, command, "체포 대상을 확보할 수 없습니다")
		return
	if bool(enemy.get("arrested", false)): _succeed(unit, command); return
	if enemy.get("status", "") != "SURRENDERED":
		_fail(unit, command, "대상이 다시 무장했습니다")
		return
	if _position(unit).distance_to(_position(enemy)) > 1.2 or not nav.segment_clear(_position(unit), _position(enemy)):
		unit["status"] = "MOVING"
		_follow_command_path(unit, command, dt)
		return
	unit["status"] = "SECURING"
	unit["facing"] = (_position(enemy) - _position(unit)).angle()
	command["remaining"] = maxf(0.0, float(command.remaining) - dt)
	if float(command.remaining) <= 0.0:
		enemy["arrested"] = true
		enemy["status"] = "ARRESTED"
		enemy["_target"] = ""
		enemy["_observed"] = []
		arrests += 1
		if _p5_active: observed_statistics.control("arrest", enemy, tick)
		_record_room_control(enemy, unit, "arrest")
		_event("ARREST", "투항 대상 체포", _array_position(unit), _array_position(enemy), {"unit_id": unit.id, "enemy_id": enemy.id})
		_succeed(unit, command)

func _detonate_smoke(unit: Dictionary, command: Dictionary) -> void:
	var target: Vector2 = _point(command.args.target)
	if int(unit.get("smokes", 0)) <= 0 or not nav.segment_clear(_position(unit), target):
		_fail(unit, command, "투척 경로가 변경되었습니다")
		return
	unit["smokes"] = int(unit.smokes) - 1
	smokes_used += 1
	_smoke_zones.append({"x": target.x, "z": target.y, "radius": 2.0, "remaining": 4.0})
	_event("SMOKE", "연막 전개 · 시야 차단 4초", _array_position(unit), [target.x, target.y], {"unit_id": unit.id, "radius": 2.0})
	_succeed(unit, command)

func _smoke_blocks(origin: Vector2, destination: Vector2) -> bool:
	for zone: Dictionary in _smoke_zones:
		var center: Vector2 = Vector2(float(zone.x), float(zone.z))
		if Geometry2D.get_closest_point_to_segment(center, origin, destination).distance_to(center) < float(zone.radius): return true
	return false

func context_actions(unit_id: String, target: String, id: String = "", index: int = -1) -> Dictionary:
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty() or float(unit.hp) <= 0.0: return {"actions": [], "disabled": {}, "message": "먼저 대원을 선택하세요"}
	var actions: Array = []
	var disabled: Dictionary = {}
	var args: Dictionary = {}
	match target:
		"door":
			var door: Dictionary = _find(doors, id)
			if door.is_empty() or not _door_observations.has(id): return {"actions": [], "disabled": {}}
			actions = ["OPEN_DOOR", "OPEN_AND_FLASH", "KICK_DOOR", "PEEK_DOOR", "HOLD_AT_DOOR"]
			if int(unit.get("cameras", 0)) > 0: actions.append("PEEK_CAMERA")
			if _available_stuns(unit, true) <= 0 or mission.get("modifiers", []).has("no_stun"):
				disabled["OPEN_AND_FLASH"] = "예약분을 제외한 섬광탄이 없습니다"
			args = {"door_id": id}
			if _door_observations[id].get("state", "CLOSED") == "OPEN":
				disabled.merge({"KICK_DOOR": "이미 열린 문입니다", "PEEK_DOOR": "이미 열린 문입니다"})
			if bool(_door_observations[id].get("locked", false)):
				disabled["OPEN_DOOR"] = "잠긴 문입니다. 강제 개방이 필요합니다"
				disabled["OPEN_AND_FLASH"] = "잠긴 문입니다. 강제 개방이 필요합니다"
				disabled["PEEK_DOOR"] = "잠긴 문입니다. 강제 개방이 필요합니다"
			if int(unit.get("breaches", 0)) > 0:
				actions.append("BREACH_DOOR")
				if _available_breaches(unit) <= 0: disabled["BREACH_DOOR"] = "예약분을 제외한 문 파괴 장비가 없습니다"
			actions.append("SHOTGUN_BREACH")
			if _available_shotgun_breaches(unit) <= 0: disabled["SHOTGUN_BREACH"] = "활성 주무기 산탄총과 예약분을 제외한 탄약이 필요합니다"
			if _door_observations[id].get("state", "CLOSED") == "OPEN": disabled["SHOTGUN_BREACH"] = "이미 열린 문입니다"
		"civilian":
			var civilian: Dictionary = _find(civilians, id)
			if civilian.is_empty() or not bool(civilian.visible): return {"actions": [], "disabled": {}}
			actions = ["SECURE_CIVILIAN", "ESCORT"]
			args = {"civilian_id": id}
		"enemy":
			var enemy: Dictionary = _find(enemies, id)
			if enemy.is_empty() or not bool(enemy.visible) or enemy.status != "SURRENDERED": return {"actions": [], "disabled": {}}
			actions = ["ARREST"]
			args = {"enemy_id": id}
		"unit":
			actions = ["RELOAD", "SWITCH_WEAPON", "WAIT_FOR_SIGNAL_A", "WAIT_FOR_SIGNAL_B", "WAIT_FOR_SIGNAL_C", "WAIT_3", "WAIT_5", "WAIT_10", "CANCEL_PENDING"]
		"waypoint":
			if index < 0 or index >= unit.commands.size() or unit.commands[index].state != "PENDING": return {"actions": [], "disabled": {}}
			actions = ["FACE", "WAIT_3", "WAIT_5", "WAIT_10", "WAIT_FOR_SIGNAL_A", "WAIT_FOR_SIGNAL_B", "WAIT_FOR_SIGNAL_C", "DELETE_NODE"]
	return {"actions": actions, "disabled": disabled, "args": args}

func plan_hold(unit_id: String, args: Dictionary, append: bool = true) -> Dictionary:
	var unit: Dictionary = _find(units, unit_id)
	var door: Dictionary = _find(doors, str(args.get("door_id", "")))
	if unit.is_empty(): return _rejected("먼저 대원을 선택하세요")
	if door.is_empty(): return _rejected("유효한 문을 선택하세요")
	var projected: Dictionary = _project_movement_plan(unit, append)
	if not bool(projected.get("ok", false)): return _rejected(str(projected.get("message", "접근할 수 없습니다")))
	var route: Array = nav.approach(projected.origin, door, 0.85, projected.open)
	if route.is_empty(): return _rejected("문 앞까지 접근할 수 없습니다. 기존 계획은 유지됩니다")
	return plan_move(unit_id, {"target": route.back()}, append)

func insert_command(unit_id: String, index: int, type: String, args: Dictionary) -> Dictionary:
	if type == "CANCEL_PENDING": return _rejected("대기 취소는 명령으로 삽입할 수 없습니다")
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty(): return _rejected("먼저 대원을 선택하세요")
	var commands: Array = unit.commands
	if index < 0 or index > commands.size(): return _rejected("명령 위치가 범위를 벗어났습니다")
	for i: int in range(index, commands.size()):
		if commands[i].state in ["RUNNING", "WAITING"]: return _rejected("실행 중인 명령 앞에는 삽입할 수 없습니다")
	if index < commands.size() and commands[index].state != "PENDING": return _rejected("미실행 명령 위치에만 삽입할 수 있습니다")
	var old_commands: Array = commands.duplicate(true)
	var old_revisions: int = plan_revisions
	var old_sequence: int = _command_sequence
	var old_requests: Dictionary = _requests.duplicate(true)
	_insert_resource_index = index
	var answer: Dictionary = issue(unit_id, type, args, true)
	_insert_resource_index = -1
	if not bool(answer.get("ok", false)): return answer
	# A repeated request returns its cached answer without adding a command.
	if _command_sequence == old_sequence: return answer
	# History pruning can remove completed commands before the insertion point.
	var removed_before: int = 0
	for prior: Dictionary in old_commands.slice(0, index):
		if not commands.any(func(current: Dictionary) -> bool: return current.id == prior.id): removed_before += 1
	index -= removed_before
	var added: Dictionary = commands.pop_back()
	commands.insert(index, added)
	_refresh_preview(unit)
	if not _preview_valid(unit) or not _weapon_queue_resources_valid(unit):
		unit.commands = old_commands
		plan_revisions = old_revisions
		_command_sequence = old_sequence
		_requests = old_requests
		return _rejected("이 위치에서 명령 목적지까지 접근할 수 없습니다. 기존 계획은 유지됩니다")
	_resequence(unit)
	return answer

func update_command_args(unit_id: String, index: int, args: Dictionary) -> Dictionary:
	var unit: Dictionary = _find(units, unit_id)
	if unit.is_empty() or index < 0 or index >= unit.commands.size(): return _rejected("명령 위치가 범위를 벗어났습니다")
	var command: Dictionary = unit.commands[index]
	if command.state != "PENDING": return _rejected("미실행 명령만 수정할 수 있습니다")
	args = args.duplicate(true)
	if command.args.has("drill") and not args.has("drill"): args["drill"] = command.args.drill.duplicate(true)
	if command.args.has("formation") and not args.has("formation"): args["formation"] = command.args.formation.duplicate(true)
	if command.args.has("sector") and not args.has("sector") and not bool(args.get("unlock", false)): args["sector"] = command.args.sector.duplicate(true)
	var reason: String = _validate(str(command.type), args)
	if not reason.is_empty(): return _rejected(reason)
	var prospective: Dictionary = _canonical_args(str(command.type), args)
	if command.type == "WAIT_FOR_SIGNAL" and command.args.has("sync_id"):
		return _update_synced_wait_args(command, prospective)
	var reservation_view := unit.duplicate(false)
	reservation_view["commands"] = unit.commands.duplicate()
	reservation_view.commands.remove_at(index)
	_insert_resource_index = index
	var resource_reason := _door_resource_reason(reservation_view, str(command.type), prospective, true)
	_insert_resource_index = -1
	if not resource_reason.is_empty(): return _rejected(resource_reason)
	if command.type == "THROW_FRAG":
		var frag_preview := frag_target_preview(unit_id, prospective.target, {"index":index, "replace":true})
		if not bool(frag_preview.get("ok", false)): return frag_preview
	if command.type == "OPEN_AND_FLASH":
		var earlier: Dictionary = unit.duplicate(false)
		earlier["commands"] = unit.commands.slice(0, index)
		var prepared: Dictionary = _prepare_flash_plan(earlier, prospective, true)
		if not bool(prepared.get("ok", false)): return _rejected(str(prepared.get("message", "섬광탄 투척 지점이 유효하지 않습니다")))
		prospective = prepared.args
	var old_commands: Array = unit.commands.duplicate(true)
	command.args = prospective
	_refresh_preview(unit)
	if not _preview_valid(unit) or not _weapon_queue_resources_valid(unit):
		unit.commands = old_commands
		return _rejected("벽·문·가구 때문에 목적지에 접근할 수 없습니다. 기존 계획은 유지됩니다")
	plan_revisions += 1
	var answer := {"ok": true, "message": "명령 목적지를 수정했습니다", "id": command.id}
	_add_breach_warning(answer, str(command.type), prospective)
	return answer

func _update_synced_wait_args(edited: Dictionary, prospective: Dictionary) -> Dictionary:
	var old_id := str(edited.args.sync_id)
	var new_id := str(prospective.get("sync_id", old_id))
	var changes: Array = []
	for unit: Dictionary in units:
		for command: Dictionary in unit.commands:
			if command.type != "WAIT_FOR_SIGNAL" or str(command.args.get("sync_id", "")) != old_id: continue
			if command.state != "PENDING": return _drill_rejected("drill.delay_pending", "미실행 준비 신호만 함께 수정할 수 있습니다")
			var args: Dictionary = command.args.duplicate(true)
			for key: String in ["signal", "sync_id", "auto_signal", "delay_ticks"]:
				if prospective.has(key): args[key] = prospective[key]
				else: args.erase(key)
			# Shared timing changes never overwrite another operator's rank.
			if command == edited and prospective.has("drill"): args["drill"] = prospective.drill.duplicate(true)
			if command == edited and prospective.has("formation"): args["formation"] = prospective.formation.duplicate(true)
			var reason := _validate("WAIT_FOR_SIGNAL", args)
			if not reason.is_empty(): return _rejected(reason)
			changes.append({"command": command, "args": _canonical_args("WAIT_FOR_SIGNAL", args)})
	if old_id != new_id:
		for unit: Dictionary in units:
			for command: Dictionary in unit.commands:
				if command.type != "WAIT_FOR_SIGNAL" or FINISHED.has(str(command.state)) or str(command.args.get("sync_id", "")) != new_id: continue
				if not _same_sync_contract(command.args, prospective):
					return _drill_rejected("drill.invalid_wait", "드릴 대기 신호가 단계와 일치하지 않습니다")
	for change: Dictionary in changes:
		if not _same_sync_contract(changes[0].args, change.args): return _drill_rejected("drill.invalid_wait", "드릴 대기 신호가 단계와 일치하지 않습니다")
	for change: Dictionary in changes: change.command.args = change.args
	_sync_waits.erase(old_id)
	_sync_requests.erase(old_id)
	_sync_sources.erase(old_id)
	_sync_members.erase(old_id)
	plan_revisions += 1
	return {"ok": true, "id": edited.id, "updated": changes.size(), "message": "명령 목적지를 수정했습니다"}

func _preview_valid(unit: Dictionary) -> bool:
	for command: Dictionary in unit.commands:
		if command.state == "PENDING" and (command.type == "MOVE" or DOOR_COMMANDS.has(str(command.type)) or command.type in ["SECURE_CIVILIAN", "ARREST"]):
			if command.get("path", []).is_empty(): return false
	return true

func _weapon_queue_resources_valid(unit: Dictionary) -> bool:
	var frags := int(unit.get("frags", 0))
	for command: Dictionary in unit.commands:
		if not FINISHED.has(str(command.state)) and command.type == "THROW_FRAG" and not command.has("projectile_id"):
			frags -= 1
			if frags < 0 or MissionCatalog.roe(mission) != "high_intensity": return false
	for index: int in range(unit.commands.size()):
		var command: Dictionary = unit.commands[index]
		if FINISHED.has(str(command.state)) or command.type != "SHOTGUN_BREACH" or bool(command.get("_round_consumed", false)): continue
		if _available_shotgun_breaches(unit, true, index) <= 0: return false
	return true

func _resequence(unit: Dictionary) -> void:
	var sequence: int = 0
	for command: Dictionary in unit.commands:
		sequence += 1
		command.sequence = sequence

func plan_drag(unit_id: String, points: Array, append: bool = true) -> Dictionary:
	var simplified: Array = []
	if points.size() > 4096: return _rejected("그린 경로의 샘플이 너무 많습니다")
	for point: Variant in points:
		if not _valid_target(point): return _rejected("경로에 유효하지 않은 좌표가 있습니다")
	var tolerance: float = 0.12
	while true:
		simplified = simplify_path(points, tolerance)
		if simplified.size() <= 32: break
		tolerance *= 1.4
	var accepted: int = 0
	_preview_batch_depth += 1
	for point: Array in simplified:
		var answer: Dictionary = plan_move(unit_id, {"target": point}, append if accepted == 0 else true)
		if not bool(answer.get("ok", false)):
			answer["accepted"] = accepted
			_end_preview_batch()
			return answer
		accepted += 1
	_end_preview_batch()
	return {"ok": true, "message": "경로 %d개 지점을 계획했습니다" % accepted, "accepted": accepted}

static func simplify_path(points: Array, tolerance: float) -> Array:
	if points.size() <= 2: return points.duplicate(true)
	var keep: Dictionary = {0:true}
	keep[points.size() - 1] = true
	var spans: Array = [[0, points.size() - 1]]
	while not spans.is_empty():
		var span: Array = spans.pop_back()
		var first: int = span[0]
		var last: int = span[1]
		var maximum: float = tolerance
		var split: int = -1
		for i: int in range(first + 1, last):
			var point: Vector2 = _point(points[i])
			var distance: float = point.distance_to(Geometry2D.get_closest_point_to_segment(point, _point(points[first]), _point(points[last])))
			if distance > maximum:
				maximum = distance
				split = i
		if split >= 0:
			keep[split] = true
			spans.append([first, split])
			spans.append([split, last])
	var out: Array = []
	for i: int in range(points.size()):
		if keep.has(i): out.append(points[i])
	return out
func _initialize_tactical_entities() -> void:
	for entity: Dictionary in units + enemies:
		entity["suppressed"] = float(entity.get("suppressed", 0.0))
		entity["suppression_remaining"] = entity["suppressed"]
	for enemy: Dictionary in enemies:
		enemy["enemy_type"] = _enemy_type(enemy)
		enemy["strength"] = str(enemy.get("strength", "weak"))
		enemy["surrendered"] = bool(enemy.get("surrendered", false))
		enemy["arrested"] = bool(enemy.get("arrested", false))
		enemy["surrender_remaining"] = 5.0
		enemy["_surrender_susceptible"] = _surrender_rng.randf() < 0.22
		enemy["door_ready"] = false
		enemy["_door_ready_id"] = ""
		enemy["_door_ready_until"] = -1.0
		enemy["_door_leaf_memory"] = {}
		enemy["_investigate_arrived_at"] = -1.0
		enemy["_cover_attempted"] = false
		enemy["_cover_target"] = []
		enemy["_cover_recheck_at"] = 0.0
		enemy["_alert_until"] = 0.0
		enemy["_alert_position"] = []
		enemy["_alert_react_at"] = 0.0
		enemy["_report_after"] = 0.0
		enemy["_alert_action"] = ""
		enemy["_response_role"] = str(enemy.get("response_role", "reserve" if _enemy_type(enemy) == "rusher" else "guard"))
		enemy["_hostage_alert_elapsed"] = 0.0
		enemy["_hostage_attack_cooldown"] = 0.0
		if enemy["enemy_type"] == "sentry":
			enemy["vision_range"] = 12.0
			enemy["fov"] = 70.0
			enemy["patrol"] = []
		if enemy["enemy_type"] == "hostage_taker" and not enemy.has("hostage_id"):
			var nearest: float = INF
			for civilian: Dictionary in civilians:
				var distance: float = _position(enemy).distance_to(_position(civilian))
				if distance < nearest:
					nearest = distance
					enemy["hostage_id"] = civilian["id"]
	for civilian: Dictionary in civilians:
		civilian["status"] = "SECURED" if bool(civilian.get("secured", false)) else str(civilian.get("civilian_state", "IDLE"))
		civilian["follow_unit_id"] = str(civilian.get("follow_unit_id", ""))
		civilian["_panic_target"] = []

func _enemy_combat_stat(enemy: Dictionary, stat: String) -> float:
	var profile: Dictionary = MissionCatalog.ENEMY_STRENGTHS.get(str(enemy.get("strength", "weak")), MissionCatalog.ENEMY_STRENGTHS.weak)
	# Keep existing challenge/modifier scaling on top of the authored NPC tier.
	return float(profile[stat]) * float(enemy_rules[stat]) / float(MissionCatalog.NORMAL[stat])

func _enemy_type(enemy: Dictionary) -> String:
	var value: String = str(enemy.get("enemy_type", enemy.get("type", "normal")))
	if value == "guard":
		return "sentry"
	return value if value in ["normal", "sentry", "rusher", "hostage_taker"] else "normal"

func _vision_cone_clear(origin: Vector2, destination: Vector2, facing: float, fov: float, vision_range: float, eye_height: float = 1.62, target_height: float = 1.62) -> bool:
	var offset: Vector2 = destination - origin
	if offset.length() > vision_range:
		return false
	if offset.length_squared() > 0.02 and absf(angle_difference(facing, offset.angle())) > deg_to_rad(fov) * 0.5:
		return false
	if has_method("_smoke_blocks") and bool(call("_smoke_blocks", origin, destination)):
		return false
	return nav.sight_clear_height(origin, destination, eye_height, target_height)

func _remember_enemy_state(enemy: Dictionary) -> void:
	enemy["last_seen"] = _array_position(enemy)
	enemy["last_seen_time"] = time
	enemy["_last_seen_hp"] = enemy["hp"]
	enemy["_last_seen_facing"] = enemy["facing"]
	enemy["_last_seen_status"] = enemy["status"]
	if _p5_active: observed_statistics.observe(enemy, tick)
	_record_room_observation(enemy)

func _update_tactical_effects(dt: float) -> void:
	for entity: Dictionary in units + enemies:
		entity["suppressed"] = maxf(0.0, float(entity.get("suppressed", 0.0)) - dt)
		entity["suppression_remaining"] = entity["suppressed"]

func _update_surrender(dt: float) -> void:
	for enemy: Dictionary in enemies:
		if float(enemy.get("hp", 0.0)) <= 0.0 or _is_target(enemy):
			continue
		if bool(enemy.get("arrested", false)):
			enemy["status"] = "ARRESTED"
			continue
		# Existing surrendered actors retain the uninterrupted observation timer.
		if not bool(enemy.get("surrendered", false)) and (not AUTO_SURRENDER_ENABLED or _enemy_type(enemy) == "rusher" or not bool(enemy.get("can_surrender", true))):
			continue
		var observers: Array = []
		for unit: Dictionary in units:
			if _can_act(unit) and can_see(unit, enemy):
				observers.append(unit)
		if bool(enemy.get("surrendered", false)):
			enemy["status"] = "SURRENDERED"
			if observers.is_empty():
				enemy["surrender_remaining"] = maxf(0.0, float(enemy.get("surrender_remaining", 5.0)) - dt)
			else:
				enemy["surrender_remaining"] = 5.0
			if float(enemy["surrender_remaining"]) <= 0.0:
				enemy["surrendered"] = false
				enemy["ammo"] = maxi(0, int(enemy.get("_surrender_ammo", enemy.get("max_ammo", 32))))
				enemy["status"] = "SUSPICIOUS"
				enemy["_ai_state"] = "SUSPICIOUS"
				enemy["_reaction"] = _enemy_combat_stat(enemy, "reaction_max")
				if _currently_observed(enemy):
					_remember_enemy_state(enemy)
					_event("REARM", "감시가 끊긴 인원이 다시 무장했습니다", [], _array_position(enemy), {"enemy_id": enemy["id"]})
			continue
		if not AUTO_SURRENDER_ENABLED or _enemy_type(enemy) == "rusher" or not bool(enemy.get("can_surrender", true)):
			continue
		var surprised: bool = observers.size() >= 2 and enemy.get("_observed", []).is_empty()
		var stun_approach: bool = false
		var exposed_wounded: bool = false
		for unit: Dictionary in units:
			if float(unit.get("hp", 0.0)) <= 0.0 or float(unit.get("stunned", 0.0)) > 0.0:
				continue
			if float(enemy.get("stunned", 0.0)) > 0.0 and _position(unit).distance_to(_position(enemy)) <= 2.5 and nav.segment_clear(_position(unit), _position(enemy)):
				stun_approach = true
			if float(enemy["hp"]) <= 30.0 and can_see(unit, enemy) and fire_line_clear(unit, enemy):
				exposed_wounded = true
		var cross_observed := false
		if float(enemy.get("suppressed", 0.0)) > 0.0:
			for a: int in range(observers.size()):
				for b: int in range(a + 1, observers.size()):
					if absf(angle_difference((_position(observers[a]) - _position(enemy)).angle(), (_position(observers[b]) - _position(enemy)).angle())) >= PI / 4.0: cross_observed = true
		var surrender: bool = surprised if _enemy_type(enemy) == "hostage_taker" else bool(enemy.get("_surrender_susceptible", false)) and (surprised or stun_approach or exposed_wounded or cross_observed)
		if surrender:
			_set_surrendered(enemy)

func _set_surrendered(enemy: Dictionary) -> void:
	enemy["surrendered"] = true
	enemy["_surrender_ammo"] = int(enemy.get("ammo", 0))
	enemy["ammo"] = 0
	enemy["status"] = "SURRENDERED"
	enemy["_ai_state"] = "SURRENDERED"
	enemy["_observed"] = []
	enemy["_target"] = ""
	enemy["_ai_path"] = []
	enemy["_cover_target"] = []
	enemy["door_ready"] = false
	enemy.erase("_door_contact_prepared")
	enemy["surrender_remaining"] = 5.0
	_release_door_owner(str(enemy["id"]))
	if _currently_observed(enemy):
		_remember_enemy_state(enemy)
		_event("SURRENDER", "무장 인원이 투항했습니다 · 감시와 체포가 필요합니다", [], _array_position(enemy), {"enemy_id": enemy["id"]})

func _shot_accuracy(attacker: Dictionary, target: Dictionary, hostile: bool) -> float:
	var accuracy: float = _enemy_combat_stat(attacker, "accuracy") if hostile else float(_weapon_stats(attacker)["accuracy"])
	if hostile and _enemy_type(attacker) == "sentry":
		accuracy += 0.1
	accuracy = clampf(accuracy, 0.0, 1.0)
	_refresh_weapon_state(attacker)
	var origin: Vector2 = Vector2(float(attacker.weapon_origin[0]), float(attacker.weapon_origin[1]))
	# Cover affects the actual exposed body fraction, rather than the count of
	# furniture boxes anywhere along the line.
	accuracy *= nav.shot_exposure(origin, float(attacker.weapon_origin[2]), target, _weapon_penetration(attacker))
	if _combat_moving(attacker):
		accuracy *= ({"careful": 0.88, "normal": 0.76, "fast": 0.60} if hostile else EquipmentCatalog.catalog().get("friendly_movement_accuracy", {"careful": 0.94, "normal": 0.84, "fast": 0.68})).get(str(attacker.get("movement_mode", "normal")), 0.76 if hostile else 0.84)
	elif str(attacker.get("stance", "standing")) == "crouched":
		accuracy *= 1.025
	var health: float = float(attacker.get("hp", 100.0)) / maxf(1.0, float(attacker.get("max_hp", 100.0)))
	accuracy *= 0.72 if health <= 0.4 else (0.88 if health <= 0.75 else 1.0)
	if float(attacker.get("suppressed", 0.0)) > 0.0:
		accuracy *= 0.8 if str(attacker.get("trait", "")) == "cautious" else 0.5
	return clampf(accuracy, 0.0, 1.0)

func _apply_suppression(attacker: Dictionary, target: Dictionary) -> void:
	var threatened: Array = units if attacker.get("kind", "") == "enemy" else enemies
	_refresh_weapon_state(attacker)
	var origin: Vector2 = Vector2(float(attacker.weapon_origin[0]), float(attacker.weapon_origin[1]))
	var end: Vector2 = _position(target)
	for entity: Dictionary in threatened:
		if float(entity.get("hp", 0.0)) <= 0.0 or bool(entity.get("surrendered", false)) or bool(entity.get("arrested", false)):
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(_position(entity), origin, end)
		if closest.distance_to(_position(entity)) > 1.0 or nav.shot_exposure(origin, float(attacker.weapon_origin[2]), entity, _weapon_penetration(attacker)) <= 0.0:
			continue
		if float(entity.get("suppressed", 0.0)) <= 0.0:
			entity["_reaction"] = float(entity.get("_reaction", 0.0)) + 0.12
		entity["suppressed"] = 1.5
		entity["suppression_remaining"] = 1.5

func fire_at(unit_id: String, enemy_id: String) -> Dictionary:
	var unit: Dictionary = _find(units, unit_id)
	var enemy: Dictionary = _find(enemies, enemy_id)
	if not result.is_empty() or unit.is_empty() or enemy.is_empty() or not _can_act(unit) or not _can_engage_target(unit, enemy, false) or bool(enemy.get("arrested", false)) or float(enemy.get("hp", 0.0)) <= 0.0:
		return {"ok": false, "message": "현재 관측한 행동 가능한 대상이 필요합니다"}
	var before: int = int(unit["ammo"])
	_combat(unit, [enemy], false, enemy_id)
	return {"ok": int(unit["ammo"]) < before, "message": "지정 대상에 사격했습니다" if int(unit["ammo"]) < before else "현재 사격할 수 없습니다"}

func _take_enemy_cover(enemy: Dictionary, threat_position: Vector2) -> void:
	if _enemy_type(enemy) in ["rusher", "hostage_taker"] or bool(enemy.get("surrendered", false)) or _is_target(enemy):
		return
	if time < float(enemy.get("_cover_recheck_at", 0.0)):
		return
	enemy["_cover_recheck_at"] = time + 2.5
	enemy["_cover_attempted"] = true
	var current: Array = enemy.get("_cover_target", [])
	var current_score: float = INF
	if current.size() == 2 and nav.walkable(_point(current)) and not _cover_reserved(enemy, _point(current)):
		current_score = _cover_exposure(enemy, _point(current), threat_position, str(enemy.get("_cover_stance", enemy.get("stance", "standing")))) * 5.0 + _position(enemy).distance_to(_point(current)) * 0.3
	# All candidate costs are nonnegative. A current score below the switch
	# penalty cannot be improved enough, regardless of the candidate routes.
	if current_score <= 0.65 - 0.0001:
		return
	var best_score: float = INF
	var best: Array = []
	var best_stance: String = "standing"
	for prop: Dictionary in mission.get("props", []):
		var cover: String = str(prop.get("cover", Navigation.cover_default(str(prop.get("type", "")), prop.get("solid"))))
		if cover not in ["low", "full"]:
			continue
		var center: Vector2 = _position(prop)
		if center.distance_to(_position(enemy)) > 6.0:
			continue
		var away: Vector2 = (center - threat_position).normalized()
		for offset: float in [-PI / 4.0, 0.0, PI / 4.0]:
			var direction: Vector2 = away.rotated(offset)
			var extent: float = absf(direction.x) * float(prop.get("w", 1.0)) * 0.5 + absf(direction.y) * float(prop.get("d", 1.0)) * 0.5
			var candidate: Vector2 = center + direction * (extent + Navigation.RADIUS + 0.18)
			var direct_distance := _position(enemy).distance_to(candidate)
			# A route cannot be shorter than the straight-line distance. Use a
			# conservative allowance and preserve original ordering for ties.
			if direct_distance > 7.0 + 0.0001 or direct_distance * 0.3 > best_score + 0.0001:
				continue
			if not nav.walkable(candidate) or _cover_reserved(enemy, candidate) or _cover_point_occupied(enemy, candidate):
				continue
			var standing_exposure: float = _cover_exposure(enemy, candidate, threat_position, "standing")
			var crouching_exposure: float = _cover_exposure(enemy, candidate, threat_position, "crouched")
			var stance: String = "crouched" if crouching_exposure + 0.15 < standing_exposure else "standing"
			var exposure: float = crouching_exposure if stance == "crouched" else standing_exposure
			if exposure >= 0.85:
				continue
			if direct_distance * 0.3 + exposure * 5.0 > best_score + 0.0001:
				continue
			var route: Array = nav.path(_position(enemy), candidate)
			if route.is_empty():
				continue
			var distance: float = _movement_route_length(_position(enemy), route)
			if distance > 7.0:
				continue
			var score: float = distance * 0.3 + exposure * 5.0
			# Penalize exposed transit rather than judging only the final location.
			if route.size() > 1:
				score += _cover_exposure(enemy, _point(route[route.size() / 2]), threat_position, "standing") * 0.8
			if score < best_score:
				best_score = score
				best = [candidate.x, candidate.y]
				best_stance = stance
	# Keep a useful current position until an alternative is meaningfully better.
	if current_score < INF and (best.is_empty() or best_score + 0.65 >= current_score): return
	enemy["_cover_target"] = best
	enemy["_cover_stance"] = best_stance
	enemy["stance"] = best_stance
	enemy["_ai_path"] = []
	enemy["_ai_route_attempted"] = false

func _cover_exposure(enemy: Dictionary, point: Vector2, threat: Vector2, stance: String) -> float:
	var subject: Dictionary = {"id": str(enemy.id), "kind": "enemy", "x": point.x, "z": point.y, "hp": 1.0, "stance": stance, "base_height":CombatSpatial.floor_base_at(_elevated_rooms, point)}
	var observer: Dictionary = {"x": threat.x, "z": threat.y, "stance": "standing", "base_height":CombatSpatial.floor_base_at(_elevated_rooms, threat)}
	return float(nav.call("exposed_fraction", observer, subject)) if nav.has_method("exposed_fraction") else (1.0 if nav.shot_clear(threat, point) else 0.0)

func _cover_point_occupied(enemy: Dictionary, point: Vector2) -> bool:
	for other: Dictionary in units + enemies + civilians:
		if str(other.get("id", "")) != str(enemy.id) and float(other.get("hp", 0.0)) > 0.0 and point.distance_to(_position(other)) < Navigation.RADIUS * 2.0 + 0.1: return true
	return false

# Hearing and reports carry an uncertain region. No target ID or live player
# reference is shared; every shot still requires the shooter's own current sight.
func _heard_region(position: Vector2) -> Vector2:
	return Vector2(floorf(position.x / 4.0) * 4.0 + 2.0, floorf(position.y / 4.0) * 4.0 + 2.0)

func _begin_rear_response(enemy: Dictionary, region: Vector2) -> void:
	var role := str(enemy.get("_response_role","guard"))
	if role not in ["reserve","patrol"] or enemy.has("_rear_heard_at"): return
	enemy["_rear_heard_at"] = time
	enemy["_rear_ready_at"] = time + (2.0 if role == "reserve" else 3.0)
	enemy["_rear_region"] = [region.x,region.y]
	enemy["_rear_room_id"] = ""
	enemy["_rear_goal"] = []
	enemy["_rear_path"] = []
	enemy["_rear_state"] = "delay"

func _room_has_own_units(id: String) -> bool:
	for unit: Dictionary in units:
		if float(unit.hp)>0.0 and room_control.room_at(_position(unit),float(unit.get("base_height",0.0))) == id: return true
	return false

func _rear_point_covered(point: Vector2, floor_height: float) -> bool:
	for unit: Dictionary in units:
		if not _can_act(unit) or int(unit.get("ammo",0))<=0 or absf(float(unit.get("base_height",0.0))-floor_height)>0.01: continue
		# A weapon guard uses its own current eye/cone, not a camera or an old
		# exploration mask. This grants no live target to the response element.
		if _sensor_exposure(unit,{"x":point.x,"z":point.y})>0.0: return true
	return false

func _marked_room_covered(id: String) -> bool:
	if str(room_states.get(id,{}).get("state","UNKNOWN")) != "MARKED": return false
	var room := _find(mission.get("rooms",[]),id)
	if room.is_empty(): return false
	return _rear_point_covered(_position(room),float(room.get("base_height",0.0)))

func _rear_guard_limit(enemy: Dictionary, goal: Vector2) -> Vector2:
	var path: Array = nav.path(_position(enemy),goal,_all_closed_door_ids())
	var safe := _position(enemy)
	for coordinate: Array in path:
		var destination := _point(coordinate)
		var length := safe.distance_to(destination)
		var origin := safe
		var steps := maxi(1,ceili(length/0.15))
		for index: int in range(1,steps+1):
			var point := origin.lerp(destination,float(index)/float(steps))
			if _rear_point_covered(point,float(enemy.get("base_height",0.0))): return safe
			safe = point
	return goal

func _select_rear_room(enemy: Dictionary) -> String:
	var best := ""
	var cost := INF
	for id: String in room_states:
		if str(room_states[id].state) not in ["CLEAR","MARKED"] or _room_has_own_units(id): continue
		var room := _find(mission.get("rooms",[]),id)
		if room.is_empty() or absf(float(room.get("base_height",0.0))-float(enemy.get("base_height",0.0)))>0.01: continue
		var route: Array = nav.path(_position(enemy),_position(room),_all_closed_door_ids())
		if route.is_empty(): continue
		var distance := 0.0
		var previous := _position(enemy)
		for coordinate: Array in route:
			var point := _point(coordinate)
			distance += previous.distance_to(point)
			previous = point
		if distance<cost or (is_equal_approx(distance,cost) and (best.is_empty() or id<best)):
			cost = distance
			best = id
	return best

func _rear_forward_goal(enemy: Dictionary, room: Dictionary) -> Vector2:
	var heard := _point(enemy.get("_rear_region",enemy.get("_alert_position",_array_position(room))))
	var best := _position(room)
	var cost := INF
	for door: Dictionary in doors:
		var normal := Vector2.DOWN if door.get("axis","x")=="x" else Vector2.RIGHT
		for side: float in [-1.0,1.0]:
			if room_control.room_at(_position(door)+normal*side*0.6,float(door.get("base_height",0.0))) != str(room.id): continue
			var destination := _position(door)-normal*side*0.9
			if _position(enemy).distance_to(destination)<0.2: continue
			var distance := destination.distance_squared_to(heard)
			if distance<cost:
				cost = distance
				best = destination
	return best

func _advance_rear_response(enemy: Dictionary, dt: float) -> bool:
	if not enemy.has("_rear_heard_at") or str(enemy.get("_rear_state","")) == "complete": return false
	var room_id := str(enemy.get("_rear_room_id",""))
	if room_id.is_empty():
		room_id = _select_rear_room(enemy)
		if room_id.is_empty(): return false
		enemy["_rear_room_id"] = room_id
	var room := _find(mission.get("rooms",[]),room_id)
	if room.is_empty(): return false
	if time+0.000001<float(enemy._rear_ready_at):
		_advance_door_ready(enemy)
		enemy["_rear_state"] = "delay"
		enemy["status"] = "SUSPICIOUS"
		return true
	var goal := _position(room)
	enemy["door_ready"] = false
	if bool(enemy.get("_rear_crossed_room",false)): goal = _rear_forward_goal(enemy,room)
	if _marked_room_covered(room_id):
		goal = _rear_guard_limit(enemy,goal)
		enemy["_rear_state"] = "guarded"
	else:
		enemy["_rear_state"] = "flank"
	enemy["_rear_goal"] = [goal.x,goal.y]
	enemy["_rear_path"] = nav.path(_position(enemy),goal,_all_closed_door_ids()).duplicate(true)
	enemy["_alert_action"] = "rear_guard" if enemy._rear_state == "guarded" else "rear_flank"
	enemy["status"] = "SUSPICIOUS"
	if _move_tactical_actor(enemy,goal,float(enemy_rules.patrol_speed)*1.2,dt,bool(enemy_rules.get("enemy_opens_doors",true))):
		if enemy._rear_state == "guarded": return true
		if not bool(enemy.get("_rear_crossed_room",false)):
			enemy["_rear_crossed_room"] = true
			enemy["_ai_path"] = []
		else:
			enemy["_rear_state"] = "complete"
	return true

func _receive_combat_alert(enemy: Dictionary, region: Vector2, priority: int = 1) -> void:
	if not _can_act(enemy) or _is_target(enemy):
		return
	_decay_alert_memory(enemy)
	var fresh: bool = float(enemy.get("_alert_level", 0.0)) <= 0.12
	var repeated: bool = priority < 3 and time - float(enemy.get("_alert_counted_at", -100.0)) >= 0.8
	var severity: float = 1.0 if priority == 3 else (0.75 if priority == 2 else 0.6)
	if fresh or repeated: enemy["_alert_counted_at"] = time
	if repeated and not fresh: enemy["_alert_repetitions"] = mini(5, int(enemy.get("_alert_repetitions", 0)) + 1)
	enemy["_alert_level"] = minf(1.6, maxf(float(enemy.get("_alert_level", 0.0)), severity) + (0.12 if repeated and not fresh else 0.0))
	enemy["_alert_until"] = time + (float(enemy._alert_level) - 0.12) / 0.05
	if fresh:
		enemy["_support_completed"] = false
		enemy["_support_goal"] = []
		enemy["_alert_react_at"] = time + 0.25 + float(absi(str(enemy.id).hash()) % 5) * 0.08
		enemy["_alert_action"] = "guard"
		enemy["_cover_recheck_at"] = 0.0
	if not enemy.get("_observed", []).is_empty() and priority < 3:
		return
	if not fresh and priority < int(enemy.get("_alert_priority", 0)) and time - float(enemy.get("_alert_received_at", 0.0)) < 3.0:
		return
	enemy["_alert_priority"] = priority
	enemy["_alert_received_at"] = time
	enemy["_alert_position"] = [region.x, region.y]
	enemy["_last_known"] = [region.x, region.y]
	enemy["_last_known_time"] = time
	enemy["_detect_reason"] = "sight" if priority == 3 else ("report" if priority == 2 else "gunfire")
	if priority < 3:
		enemy["_report_memory" if priority == 2 else "_heard_memory"] = {"position": [region.x, region.y], "time": time, "confidence": 0.55 if priority == 2 else 0.35}
		enemy["awareness_state"] = "SUSPICIOUS"
		enemy["awareness_confidence"] = maxf(float(enemy.get("awareness_confidence", 0.0)), 0.55 if priority == 2 else 0.35)
		enemy["observation_source"] = "report" if priority == 2 else "sound"

func _decay_alert_memory(enemy: Dictionary) -> void:
	var elapsed: float = maxf(0.0, time - float(enemy.get("_alert_updated_at", time)))
	enemy["_alert_updated_at"] = time
	enemy["_alert_level"] = maxf(0.0, float(enemy.get("_alert_level", 0.0)) - elapsed * 0.05)
	if float(enemy._alert_level) <= 0.12:
		enemy["_alert_repetitions"] = 0

func _raise_combat_alert(observer: Dictionary, seen_position: Vector2) -> void:
	_receive_combat_alert(observer, seen_position, 3)
	if time < float(observer.get("_report_after", 0.0)):
		return
	observer["_report_after"] = time + 3.0
	for ally: Dictionary in enemies:
		if ally.id != observer.id and _position(ally).distance_to(_position(observer)) <= 14.0:
			_receive_combat_alert(ally, _heard_region(seen_position), 2)
	# Audible warning supplies a region only. It does not reveal an unseen actor.
	_emit_sound(_position(observer), 7.0, "경계 통신", "enemy")

func _cover_reserved(enemy: Dictionary, point: Vector2) -> bool:
	for other: Dictionary in enemies:
		if other.id == enemy.id or float(other.hp) <= 0.0:
			continue
		var reserved: Array = other.get("_cover_target", [])
		if reserved.size() == 2 and _point(reserved).distance_to(point) < 0.8:
			return true
	return false

func _alert_hold_point(enemy: Dictionary, threat: Vector2) -> Array:
	# Local wall/corner fallback when authored furniture supplies no cover.
	var origin: Vector2 = _position(enemy)
	var best: Array = []
	var score: float = INF
	for radius: float in [0.8, 1.6, 2.4]:
		for index: int in range(8):
			var point: Vector2 = origin + Vector2.from_angle(float(index) * TAU / 8.0) * radius
			if not nav.walkable(point) or not nav.segment_clear(origin, point, Navigation.RADIUS) or _cover_reserved(enemy, point) or _cover_point_occupied(enemy, point):
				continue
			var standing: float = _cover_exposure(enemy, point, threat, "standing")
			var crouching: float = _cover_exposure(enemy, point, threat, "crouched")
			var exposure: float = minf(standing, crouching)
			if exposure >= 0.85:
				continue
			var value: float = radius * 0.3 + exposure * 5.0
			if value < score:
				score = value
				best = [point.x, point.y]
				enemy["_fallback_hold_stance"] = "crouched" if crouching + 0.15 < standing else "standing"
	if not best.is_empty():
		enemy["stance"] = str(enemy.get("_fallback_hold_stance", "standing"))
		enemy["_cover_stance"] = enemy["stance"]
	return best

func _alert_peek_point(enemy: Dictionary, threat: Vector2) -> Array:
	return _cognition_peek_point(enemy, threat)

func _advance_combat_alert(enemy: Dictionary, dt: float) -> bool:
	if enemy.get("_alert_position", []).is_empty():
		return false
	_decay_alert_memory(enemy)
	if float(enemy.get("_alert_level", 0.0)) <= 0.12:
		enemy["_alert_position"] = []
		enemy["_last_known"] = []
		enemy["_cover_target"] = []
		enemy["_ai_path"] = []
		enemy["_alert_action"] = ""
		return false
	var threat: Vector2 = _point(enemy["_alert_position"])
	enemy["status"] = "SUSPICIOUS"
	enemy["_ai_state"] = "SUSPICIOUS"
	if time < float(enemy.get("_alert_react_at", 0.0)):
		return true
	if _enemy_type(enemy) == "hostage_taker":
		_maintain_hostage_distance(enemy, dt)
	else:
		var previous_check: float = float(enemy.get("_cover_recheck_at", 0.0))
		_take_enemy_cover(enemy, threat)
		var cover: Array = enemy.get("_cover_target", [])
		var reserve: bool = str(enemy.get("_response_role", "guard")) == "reserve"
		if reserve and not bool(enemy.get("_support_completed", false)) and (_position(enemy).distance_to(threat) > 5.5 or not enemy.get("_support_goal", []).is_empty()):
			# A support element advances to a standoff point, not straight onto the shooter.
			var support_goal: Array = enemy.get("_support_goal", [])
			if support_goal.is_empty():
				var destination: Vector2 = _nearest_tactical_point(threat + (_position(enemy) - threat).normalized() * 4.0, _all_closed_door_ids())
				support_goal = [destination.x, destination.y]
				enemy["_support_goal"] = support_goal
			var support: Vector2 = _point(support_goal)
			enemy["_alert_action"] = "support"
			if _move_tactical_actor(enemy, support, float(enemy_rules.patrol_speed) * 1.2, dt, bool(enemy_rules.get("enemy_opens_doors", true))):
				enemy["_support_completed"] = true
				enemy["_cover_target"] = []
				enemy["_cover_recheck_at"] = 0.0
			return true
		if cover.is_empty() and time >= previous_check:
			cover = _alert_hold_point(enemy, threat)
			enemy["_cover_target"] = cover
		if cover.size() == 2 and _position(enemy).distance_to(_point(cover)) > 0.25:
			enemy["_alert_action"] = "cover"
			var watch_facing: float = float(enemy.facing)
			_move_tactical_actor(enemy, _point(cover), float(enemy_rules.patrol_speed) * 1.25, dt, bool(enemy_rules.get("enemy_opens_doors", true)))
			enemy["facing"] = lerp_angle(watch_facing, (threat - _position(enemy)).angle(), minf(1.0, dt * 7.0))
			return true
		if time >= float(enemy.get("_peek_after", 0.0)) and not _alert_weapon_line(enemy, _position(enemy), threat):
			enemy["_peek_after"] = time + 3.0
			var peek: Array = _cognition_peek_point(enemy, threat)
			if not peek.is_empty():
				enemy["_cover_target"] = peek
				enemy["_cover_recheck_at"] = time + 2.0
	enemy["_alert_action"] = "guard"
	var bearing: float = (threat - _position(enemy)).angle()
	enemy["facing"] = lerp_angle(float(enemy.facing), bearing + sin(time * 1.3) * 0.18, minf(1.0, dt * 5.0))
	return true

func _alert_weapon_line(enemy: Dictionary, origin: Vector2, threat: Vector2, stance: String = "") -> bool:
	var posture: String = str(enemy.get("stance", "standing")) if stance.is_empty() else stance
	var height: float = CombatSpatial.weapon_height({"stance":posture, "base_height":CombatSpatial.floor_base_at(_elevated_rooms, origin)})
	var subject: Dictionary = {"kind": "unit", "x": threat.x, "z": threat.y, "hp": 1.0, "stance": "standing", "base_height":CombatSpatial.floor_base_at(_elevated_rooms, threat)}
	return float(nav.call("shot_exposure", origin, height, subject)) > 0.25 if nav.has_method("shot_exposure") else nav.shot_clear(origin, threat)

func _cognition_peek_point(enemy: Dictionary, threat: Vector2) -> Array:
	var origin: Vector2 = _position(enemy)
	for radius: float in [0.0, 0.7, 1.2]:
		for index: int in range(8):
			var point: Vector2 = origin + Vector2.from_angle(float(index) * TAU / 8.0) * radius
			if not nav.walkable(point) or not nav.segment_clear(origin, point, Navigation.RADIUS) or _cover_reserved(enemy, point) or _cover_point_occupied(enemy, point): continue
			for posture: String in [str(enemy.get("stance", "standing")), "standing"]:
				if _alert_weapon_line(enemy, point, threat, posture):
					enemy["stance"] = posture
					enemy["_cover_stance"] = posture
					return [point.x, point.y]
	return []

func _all_closed_door_ids() -> Array:
	var ids: Array = []
	for door: Dictionary in doors:
		if door.get("state", "CLOSED") != "OPEN" and not bool(door.get("locked", false)):
			ids.append(str(door["id"]))
	return ids

func _nearest_tactical_point(destination: Vector2, assumed_open: Array = []) -> Vector2:
	if nav.walkable(destination, assumed_open):
		return destination
	for ring: int in range(1, 13):
		for direction: int in range(16):
			var candidate: Vector2 = destination + Vector2.from_angle(float(direction) * TAU / 16.0) * float(ring) * Navigation.CELL
			if nav.walkable(candidate, assumed_open):
				return candidate
	return destination

func _move_tactical_actor(actor: Dictionary, destination: Vector2, speed: float, dt: float, open_doors: bool = false) -> bool:
	if bool(actor.get("hold_position", false)):
		_movement_stop(actor)
		return false
	var origin: Vector2 = _position(actor)
	if origin.distance_to(destination) <= 0.12:
		_movement_stop(actor)
		return true
	var goal: Array = actor.get("_ai_goal", [])
	var goal_changed: bool = goal.size() != 2 or _point(goal).distance_to(destination) > 0.2
	if (actor.get("_ai_path", []).is_empty() and not bool(actor.get("_ai_route_attempted", false))) or int(actor.get("_ai_revision", -1)) != nav.revision or goal_changed:
		var route: Array = nav.path(origin, destination)
		var assumed: Array = []
		if route.is_empty() and open_doors:
			assumed = _all_closed_door_ids()
			route = nav.path(origin, destination, assumed)
		actor["_ai_route_attempted"] = true
		actor["_ai_path"] = route
		actor["_ai_assumed_open"] = assumed
		actor["_ai_cursor"] = 0
		actor["_ai_revision"] = nav.revision
		actor["_ai_goal"] = [destination.x, destination.y]
		actor["_movement_detour"] = []
	var path: Array = actor.get("_ai_path", [])
	var cursor: int = int(actor.get("_ai_cursor", 0))
	if cursor >= path.size():
		actor["_ai_path"] = []
		_movement_stop(actor)
		return false
	var waypoint: Vector2 = _point(path[cursor])
	var temporary: Array = actor.get("_movement_detour", [])
	if not temporary.is_empty():
		waypoint = _point(temporary[0])
		if origin.distance_to(waypoint) < 0.08:
			temporary.pop_front()
			actor["_movement_detour"] = temporary
			waypoint = _point(path[cursor]) if temporary.is_empty() else _point(temporary[0])
	var direction: Vector2 = waypoint - origin
	if temporary.is_empty() and direction.length() < 0.12 and (cursor + 1 >= path.size() or nav.segment_clear(origin, _point(path[cursor + 1]), Navigation.RADIUS, actor.get("_ai_assumed_open", []))):
		actor["_ai_cursor"] = cursor + 1
		return false
	if open_doors and not actor.get("_ai_assumed_open", []).is_empty() and _approach_enemy_route_door(actor, waypoint, speed, dt):
		return false
	var actual_speed := _movement_speed(actor, speed, direction.normalized(), direction.length(), dt)
	var candidate: Vector2 = origin.move_toward(waypoint, actual_speed * dt)
	if not _door_permission(actor, candidate):
		actor["status"] = "WAITING"
		_movement_stop(actor)
		return false
	var blocker: Dictionary = _movement_swept_blocker(actor, origin, candidate, true)
	if not blocker.is_empty():
		if temporary.is_empty() and time >= float(actor.get("_movement_recovery_at", 0.0)):
			actor["_movement_recovery_at"] = time + 0.6
			actor["_movement_detour"] = _movement_bypass(actor, blocker, direction.normalized())
			if actor["_movement_detour"].is_empty() and time >= float(actor.get("_movement_dynamic_route_at", 0.0)):
				actor["_movement_dynamic_route_at"] = time + 2.0
				var alternative := _movement_dynamic_route(actor, destination)
				if not alternative.is_empty():
					actor["_ai_path"] = alternative
					actor["_ai_cursor"] = 0
		if _movement_has_priority(actor, blocker):
			_movement_yield(blocker, actor, waypoint, dt)
		_movement_stop(actor)
		return false
	if nav.walkable(candidate) and nav.segment_clear(origin, candidate, Navigation.RADIUS):
		_movement_apply(actor, candidate, dt)
		actor["facing"] = lerp_angle(float(actor["facing"]), direction.angle(), minf(1.0, dt * 5.0))
	else:
		actor["_ai_route_attempted"] = false
		actor["_movement_detour"] = []
		_movement_stop(actor)
	return _position(actor).distance_to(destination) <= 0.18

func _tactical_actor_space_clear(actor: Dictionary, candidate: Vector2) -> bool:
	return _movement_swept_blocker(actor, _position(actor), candidate).is_empty()

func _approach_enemy_route_door(enemy: Dictionary, waypoint: Vector2, speed: float, dt: float) -> bool:
	var origin: Vector2 = _position(enemy)
	var nearest: Dictionary = {}
	var nearest_distance: float = INF
	for door: Dictionary in doors:
		if door.get("state", "CLOSED") == "OPEN":
			continue
		var normal: Vector2 = Vector2.DOWN if door.get("axis", "x") == "x" else Vector2.RIGHT
		var first_side: float = (origin - _position(door)).dot(normal)
		var final_side: float = (waypoint - _position(door)).dot(normal)
		if first_side * final_side >= 0.0:
			continue
		var fraction: float = absf(first_side) / maxf(0.00001, absf(first_side) + absf(final_side))
		var crossing: Vector2 = origin.lerp(waypoint, fraction)
		var across: Vector2 = Vector2.RIGHT if door.get("axis", "x") == "x" else Vector2.DOWN
		if absf((crossing - _position(door)).dot(across)) > DoorGeometry.width(door) * 0.5 + Navigation.RADIUS:
			continue
		var distance: float = origin.distance_to(crossing)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = door
	if nearest.is_empty():
		return false
	if bool(nearest.get("locked", false)):
		enemy["status"] = "WAITING"
		enemy["_ai_path"] = []
		enemy["_ai_door"] = ""
		return true
	var owner: String = str(nearest.get("owner_id", ""))
	if not owner.is_empty() and owner != str(enemy["id"]):
		enemy["status"] = "WAITING"
		return true
	if owner == str(enemy["id"]) and nearest.get("state", "") == "OPENING":
		enemy["_ai_door"] = str(nearest["id"])
		if enemy.get("status", "") != "MOVING": enemy["status"] = "OPENING"
		return true
	var normal: Vector2 = Vector2.DOWN if nearest.get("axis", "x") == "x" else Vector2.RIGHT
	var side: float = 1.0 if (origin - _position(nearest)).dot(normal) >= 0.0 else -1.0
	var handle3: Vector3 = DoorGeometry.handle_world(nearest, float(nearest.get("progress", 0.0)))
	var approach: Vector2 = Vector2(handle3.x, handle3.z) + normal * side * DoorGeometry.APPROACH_DISTANCE
	if origin.distance_to(approach) > 0.12:
		# Resolve the reachable handle side using the real, closed-door grid.
		var route: Array = nav.path(origin, approach)
		if route.is_empty():
			return true
		var point: Vector2 = _point(route[0])
		var candidate: Vector2 = origin.move_toward(point, speed * dt)
		if nav.walkable(candidate) and nav.segment_clear(origin, candidate, Navigation.RADIUS) and _tactical_actor_space_clear(enemy, candidate):
			_set_position(enemy, candidate)
			enemy["facing"] = lerp_angle(float(enemy["facing"]), (point - origin).angle(), minf(1.0, dt * 5.0))
		return true
	enemy["status"] = "OPENING"
	enemy["_ai_door"] = str(nearest["id"])
	if owner != str(enemy["id"]):
		nearest["state"] = "OPENING"
		nearest["owner_id"] = enemy["id"]
		nearest["owner_command_id"] = "enemy-" + str(enemy["id"])
		nearest["_enemy_opening"] = true
		nearest["_open_target"] = 1.0
		nearest["_open_duration"] = 0.8
		var clearance: Array = _door_clearance_position(nearest, enemy, 1.0)
		if not clearance.is_empty():
			nearest["_operator_clearance"] = clearance
			nearest["_clearance_operator_id"] = enemy.id
		else:
			nearest.erase("_operator_clearance")
			nearest.erase("_clearance_operator_id")
		nearest["blocked"] = false
		nearest["reason"] = ""
		_emit_sound(_position(nearest), 2.0, "출입문 소리", "enemy")
	return true

func _enemy_door_owner_valid(door: Dictionary) -> bool:
	var enemy: Dictionary = _find(enemies, str(door.get("owner_id", "")))
	var reach: float = 2.5 if door.has("_operator_clearance") else 0.9
	return not enemy.is_empty() and _can_act(enemy) and str(enemy.get("_ai_door", "")) == str(door.get("id", "")) and _position(enemy).distance_to(DoorGeometry.handle_floor(door)) <= reach

func _advance_civilians(dt: float) -> void:
	for civilian: Dictionary in civilians:
		if float(civilian.get("hp", 0.0)) <= 0.0:
			civilian["status"] = "INCAPACITATED"
			continue
		if float(civilian.get("stunned", 0.0)) > 0.0:
			civilian["status"] = "STUNNED"
			continue
		civilian["_fear"] = maxf(0.0, float(civilian.get("_fear", 0.0)) - dt * 0.12)
		if bool(civilian.get("secured", false)):
			var leader: Dictionary = _find(units, str(civilian.get("follow_unit_id", "")))
			if leader.is_empty() or float(leader.get("hp", 0.0)) <= 0.0:
				civilian["status"] = "SECURED"
				continue
			if float(civilian.get("_fear", 0.0)) > 0.5 and time < float(civilian.get("_panic_pause_until", 0.0)):
				civilian["status"] = "PANIC"
				continue
			civilian["status"] = "FOLLOW"
			var behind: Vector2 = _position(leader) - Vector2.from_angle(float(leader.get("move_facing", leader["facing"])))
			var destination: Vector2 = _nearest_tactical_point(behind)
			if _position(civilian).distance_to(destination) > 0.2:
				_move_tactical_actor(civilian, destination, float(mission.get("civilian_follow_speed", 2.1)), dt)
		elif float(civilian.get("_fear", 0.0)) > 0.15:
			civilian["status"] = "PANIC"
			if time < float(civilian.get("_panic_pause_until", 0.0)): continue
			var target: Array = civilian.get("_panic_target", [])
			if target.is_empty():
				civilian["_panic_target"] = _civilian_panic_target(civilian)
				target = civilian["_panic_target"]
			if target.size() == 2 and _position(civilian).distance_to(_point(target)) > 0.18:
				_move_tactical_actor(civilian, _point(target), 1.5, dt)
		elif civilian.get("status", "IDLE") == "PANIC":
			civilian["status"] = "IDLE"
			civilian["_panic_target"] = []
			civilian["_ai_path"] = []
			civilian["_ai_route_attempted"] = false

func _civilian_panic_target(civilian: Dictionary) -> Array:
	var origin: Vector2 = _position(civilian)
	var corners: Array[Vector2] = []
	for room: Dictionary in mission.get("rooms", []):
		var rect: Rect2 = Rect2(_position(room) - Vector2(float(room.get("w", 1.0)), float(room.get("d", 1.0))) * 0.5, Vector2(float(room.get("w", 1.0)), float(room.get("d", 1.0))))
		if not rect.has_point(origin):
			continue
		var inset: Rect2 = rect.grow(-0.6)
		corners = [inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]
		break
	if corners.is_empty():
		corners = [Vector2(0.6, 0.6), Vector2(nav.bounds.x - 0.6, 0.6), nav.bounds - Vector2.ONE * 0.6, Vector2(0.6, nav.bounds.y - 0.6)]
	var best: Vector2 = origin
	var best_score: float = INF
	var threat: Array = civilian.get("_panic_origin", [])
	for corner: Vector2 in corners:
		var candidate: Vector2 = _nearest_tactical_point(corner)
		var route: Array = nav.path(origin, candidate)
		if route.is_empty():
			continue
		var distance: float = _movement_route_length(origin, route)
		var score: float = distance
		if threat.size() == 2:
			score -= candidate.distance_to(_point(threat)) * 0.5
			if nav.segment_clear(candidate, _point(threat)): score += 3.0
		if score < best_score:
			best_score = score
			best = candidate
	return [best.x, best.y]

func _maintain_hostage_distance(enemy: Dictionary, dt: float) -> void:
	var hostage: Dictionary = _find(civilians, str(enemy.get("hostage_id", "")))
	if hostage.is_empty() or float(hostage.get("hp", 0.0)) <= 0.0:
		return
	if _position(enemy).distance_to(_position(hostage)) <= 1.8:
		return
	var away: Vector2 = (_position(enemy) - _position(hostage)).normalized()
	var destination: Vector2 = _nearest_tactical_point(_position(hostage) + away * 1.5)
	_move_tactical_actor(enemy, destination, maxf(float(enemy_rules.patrol_speed), 2.4), dt, bool(enemy_rules.get("enemy_opens_doors", true)))

func _advance_hostage_threat(enemy: Dictionary, dt: float) -> bool:
	enemy["_hostage_aiming"] = false
	if enemy.get("status", "") != "ALERT":
		enemy["_hostage_alert_elapsed"] = 0.0
		enemy["_hostage_observed_elapsed"] = 0.0
		return false
	enemy["_hostage_alert_elapsed"] = float(enemy.get("_hostage_alert_elapsed", 0.0)) + dt
	enemy["_hostage_attack_cooldown"] = maxf(0.0, float(enemy.get("_hostage_attack_cooldown", 0.0)) - dt)
	var hostage: Dictionary = _find(civilians, str(enemy.get("hostage_id", "")))
	if hostage.is_empty() or float(hostage.get("hp", 0.0)) <= 0.0 or _position(enemy).distance_to(_position(hostage)) > 2.0 or not can_see(enemy, hostage):
		enemy["_hostage_observed_elapsed"] = 0.0
		return false
	# A named hostage still has to be directly observed. The authored ID is not
	# permission to obtain a hidden civilian's current position.
	enemy["_hostage_observed_elapsed"] = float(enemy.get("_hostage_observed_elapsed", 0.0)) + dt
	if float(enemy["_hostage_alert_elapsed"]) < 4.0 or float(enemy["_hostage_observed_elapsed"]) < 0.3 or float(enemy["_hostage_attack_cooldown"]) > 0.0 or float(enemy.get("_cooldown", 0.0)) > 0.0 or int(enemy.get("ammo", 0)) <= 0:
		return false
	enemy["_hostage_aiming"] = true
	_remember_aim(enemy, hostage)
	_advance_authoritative_aim(enemy, true)
	# Faster return fire must not shorten the separate hostage execution preparation.
	if enemy.get("aim_state", "idle") != "ready" or float(enemy.aim_progress) < 0.999:
		return true
	var solution: Dictionary = _shot_solution(enemy, hostage)
	if solution.is_empty():
		return true
	enemy["ammo"] = int(enemy.ammo) - 1
	enemy["_cooldown"] = maxf(1.0, float(WEAPONS[enemy.weapon].interval))
	enemy["_hostage_attack_cooldown"] = 1.0
	var health_before := float(hostage.hp)
	hostage["hp"] = maxf(0.0, health_before - float(enemy.get("hostage_damage", 25.0)) * float(solution.transmission))
	_record_health_damage(hostage, health_before, float(hostage.hp))
	_update_combat_state(hostage, dt)
	var attacker_observed: bool = _currently_observed(enemy)
	var hostage_observed: bool = (bool(hostage.get("secured", false)) and not _p5_active) or _currently_observed(hostage)
	if attacker_observed or hostage_observed:
		var observed_ids: Dictionary = {"civilian_id": hostage["id"]} if hostage_observed else {"enemy_id": enemy["id"]}
		_event("HOSTAGE_ATTACK", "경계가 지속되어 민간인이 공격받았습니다", _array_position(enemy) if attacker_observed else [], _array_position(hostage) if hostage_observed else [], observed_ids)
		if attacker_observed and hostage_observed:
			_event("SHOT", "민간인 피격 위험", _array_position(enemy), _array_position(hostage), {"attacker_id": enemy.id, "target_id": hostage.id, "hostile": true, "hit": true, "weapon_origin": enemy.weapon_origin.duplicate(), "target_height": solution.target_height, "transmission": solution.transmission})
	_emit_sound(_position(enemy), 10.0, "총성 감지", "enemy")
	if float(hostage["hp"]) <= 0.0:
		hostage["status"] = "INCAPACITATED"
	return true

func _can_engage_target(attacker: Dictionary, target: Dictionary, hostile: bool) -> bool:
	if can_see(attacker, target):
		return true
	# Selective penetration uses a current team observation. It does not grant
	# the shooter vision, refresh last_seen, or add a surrender observer.
	if hostile or attacker.get("kind", "") != "unit" or not bool(target.get("visible", false)):
		return false
	var origin: Vector2 = _position(attacker)
	var destination: Vector2 = _position(target)
	if nav.segment_clear(origin, destination) or not nav.shot_clear(origin, destination):
		return false
	var offset: Vector2 = destination - origin
	var weapon: Dictionary = _weapon_stats(attacker)
	var effective_range: float = float(weapon["range"]) + float(attacker.get("range_bonus", 0.0)) + (float(EquipmentCatalog.catalog().get("traits", {}).get("marksman", {}).get("range_add", 2.0)) if str(attacker.get("trait", "")) == "marksman" else 0.0)
	if offset.length() > minf(effective_range, float(attacker.get("vision_range", 10.0))) or (offset.length_squared() > 0.02 and absf(angle_difference(float(attacker["facing"]), offset.angle())) > deg_to_rad(float(attacker.get("fov", 110.0))) * 0.5):
		return false
	if has_method("_smoke_blocks") and bool(call("_smoke_blocks", origin, destination)):
		return false
	for observer: Dictionary in units:
		if observer.get("id", "") != attacker.get("id", "") and can_see(observer, target):
			return true
	return false

func _currently_observed(entity: Dictionary) -> bool:
	for observer: Dictionary in units:
		if can_see(observer, entity):
			return true
	return false
