class_name BreachReplay
extends RefCounted
## State-based, bounded replay. No simulation or scene nodes are run by seek().
## Numeric sample vectors keep the ten-minute record within the P1 memory budget.

const MissionCatalog = preload("res://scripts/mission_catalog.gd")
const EquipmentCatalog = preload("res://scripts/equipment_catalog.gd")
const DoctrineMetrics = preload("res://scripts/doctrine_metrics.gd")
const RoomControl = preload("res://scripts/room_control.gd")
const SCHEMA_VERSION := 1
const BUILD_ID := "0.1.0"
const CATALOG_HASH := "breach-original-v1"
const ENCODING := "numeric-state-v1"
const LIMIT_SECONDS := 600.0
const SAMPLE_INTERVAL := 0.1
const MAX_FILE_BYTES := 20 * 1024 * 1024
const MAX_MEMORY_BYTES := 40 * 1024 * 1024
const MAX_FRAMES := 24001
const MAX_STATES := 32000
const MAX_COMMANDS := 16000
const MAX_EVENTS := 50000
const MAX_ENTITY_COMMANDS := 128
const MAX_SAFE_SEED := 2147483647
const GROUPS := ["units", "enemies", "civilians", "doors"]
const GROUP_LIMITS := [4, 32, 32, 64]
const EQUIPMENT_STATIC_KEYS := ["sidearm", "armor", "helmet", "attachments", "appearance", "preset", "active_weapon", "current_weapon", "camera_origin", "camera_observations", "last_hit_part", "last_hit_direction", "last_hit_protection"]
const EQUIPMENT_NUMBER_KEYS := ["primary_ammo", "primary_reserve_ammo", "secondary_ammo", "secondary_reserve_ammo", "weapon_length", "equipment_weight", "flash_recover_remaining", "camera_remaining", "camera_facing", "cameras"]
const REALISM_STATIC_KEYS := ["stance", "movement_mode", "hold_position", "injury", "injury_status", "awareness_state", "observation_source", "aim_state"]
const REALISM_NUMBER_KEYS := ["reserve_ammo", "body_facing", "aim_progress", "mobility_multiplier", "velocity_x", "velocity_z", "awareness_confidence", "exposure", "action_multiplier", "reload_duration", "weapon_height", "current_weapon_height", "weapon_origin_x", "weapon_origin_z", "weapon_origin_height", "base_height"]
const ENTITY_STATIC_KEYS := ["status_reason", "id", "name", "kind", "role", "weapon", "status", "state", "visible", "secured", "alive", "detected", "alert", "facing_locked", "facing_persistent", "target", "passive", "animation", "animation_state", "strength", "enemy_type", "surrendered", "arrested", "suppressed", "follow_unit_id", "trait", "base_id", "roster_id", "hostage_id", "civilian_state", "can_surrender", "peek_origin", "training", "door_ready", "sector"] + REALISM_STATIC_KEYS + EQUIPMENT_STATIC_KEYS
const DOOR_STATIC_KEYS := ["owner_id", "owner_command_id", "blocked", "reason", "id", "name", "label", "axis", "state", "opening", "locked", "observed", "destroyed", "material", "opaque", "glass_broken", "reinforced"]
const ENTITY_STATUSES := ["IDLE", "READY", "BLOCKED", "EMPTY", "ENGAGING", "HOLD_FIRE", "INCAPACITATED", "MOVING", "OPENING", "PATROL", "REACTING", "ALERT", "RELOADING", "OUT_OF_AMMO", "SECURED", "SECURING", "SIGNAL_A", "SIGNAL_B", "SIGNAL_C", "STUNNED", "SUSPICIOUS", "TARGET", "THROWING", "WAITING", "UNKNOWN", "PANIC", "FOLLOW", "SURRENDERED", "ARRESTED", "ARRESTING", "PEEKING", "BREACHING", "YIELDING", "AIMING", "SWITCHING", "CAMERA_PEEK", "CAMERA", "RECOVERING", "COVERING_RELOAD"]
const REQUIRED_TOP_KEYS := ["schema_version", "game_build_id", "map_id", "map_revision", "asset_catalog_hash", "duration", "complete", "encoding", "bounds", "states", "commands", "metadata", "events", "frames"]
const TOP_KEYS := REQUIRED_TOP_KEYS + ["seed", "variant", "modifiers", "loadout", "roster", "mission_data", "environment"]
const COMMAND_TYPES := ["MOVE", "FACE", "WAIT", "OPEN_DOOR", "OPEN_AND_FLASH", "KICK_DOOR", "PEEK_DOOR", "PEEK_CAMERA", "BREACH_DOOR", "SHOTGUN_BREACH", "HOLD_AT_DOOR", "SWITCH_WEAPON", "RELOAD", "THROW_STUN", "THROW_SMOKE", "THROW_FRAG", "WAIT_FOR_SIGNAL", "SECURE_CIVILIAN", "ESCORT_CIVILIAN", "ARREST"]
const DOOR_ACTION_PHASES := ["KICK_RECOVER", "SHOTGUN_PREPARE", "BREACH_INSTALL", "BREACH_RETREAT", "BREACH_SAFE_WAIT", "SHOTGUN_RETREAT"]
const DRILL_STAGES := ["stack", "ready", "door", "safe", "entry", "domination", "guard", "go_long"]
const FORMATION_KINDS := ["SERPENTINE", "ROLLING_T", "T_JUNCTION"]
const FORMATION_STAGES := ["stack", "ready", "move", "cover"]
const SIGNAL_PROVENANCE_KEYS := ["signal_mode", "source_unit_id", "receiver_unit_ids", "signal_radius"]
const MAX_SECTOR_DURATION := 120.0
const COMMAND_STATES := ["PENDING", "RUNNING", "WAITING", "SUCCEEDED", "FAILED", "CANCELLED"]
const ENTITY_KEYS := ["status_reason", "id", "name", "kind", "role", "weapon", "x", "z", "facing", "aim_facing", "move_facing", "travel_distance", "turn_started_at", "turn_delta", "hp", "ammo", "max_ammo", "stuns", "stunned", "status", "visible", "last_seen", "secured", "commands", "animation", "animation_state", "animation_phase", "speed", "cooldown", "reload_remaining", "alive", "detected", "alert", "state", "radius", "fov", "range", "vision_range", "max_hp", "vision_angle", "facing_locked", "facing_persistent", "last_seen_time", "last_seen_age", "target", "passive", "strength", "enemy_type", "surrendered", "arrested", "surrender_remaining", "suppressed", "suppression_remaining", "follow_unit_id", "peek_remaining", "smokes", "breaches", "trait", "base_id", "roster_id", "hostage_id", "civilian_state", "can_surrender", "hostage_damage", "peek_origin", "peek_facing", "training", "charges", "door_ready", "available_shotgun_breaches", "available_breaches", "frags", "available_frags", "sector"] + REALISM_STATIC_KEYS + REALISM_NUMBER_KEYS + EQUIPMENT_STATIC_KEYS + EQUIPMENT_NUMBER_KEYS
const DOOR_KEYS := ["owner_id", "owner_command_id", "blocked", "reason", "swing_sign", "hinge_side", "id", "x", "z", "w", "d", "axis", "state", "progress", "opening", "locked", "hp", "durability", "destroyed", "material", "height", "base_height", "opacity", "resistance", "penetration_resistance", "opaque", "name", "label", "observed", "duration", "sound_radius", "glass_broken", "reinforced", "kick_resistance"]
const STAT_KEYS := ["command_failures", "shots_fired", "plan_revisions", "stuns_used", "reloads", "hits_taken", "units_deployed", "arrests", "kills", "unlawful_shots", "smokes_used", "breaches_used"]
const P5_STAT_KEYS := ["civilian_damage", "unit_damage", "civilian_losses", "frags_used"]
const OBSERVED_STAT_KEYS := ["neutralized", "rescued", "kills", "arrests", "civilian_damage", "civilian_losses", "unlawful_shots", "score"]
const P5_META_KEYS := ["stats_observed", "frag_projectiles", "roe"] + P5_STAT_KEYS
const P5_RESULT_KEYS := ["stats_observed", "stars_observed"] + P5_STAT_KEYS
const MAX_FRAG_FUSE := 1.2
const DOCTRINE_KEYS := ["doorway_dwell", "time_to_dominate", "enemy_first_shot", "threat_order_violations", "rear_hits"]
const ROOM_DOCTRINE_KEYS := ["room_doctrine"]
const ROOM_DOCTRINE_METRICS := ["stealth", "doorway_dwell", "time_to_dominate", "threat_order_violations", "identification", "control", "marked", "rear_hits"]
const ROOM_STATE_KEYS := ["room_states", "room_states_observed"]
const ROOM_STATES := ["UNKNOWN", "CONTACT", "DOMINATED", "CLEAR", "MARKED"]
const CALL_EVENT_TYPES := ["CALL_CLEAR", "CALL_ROOM_CLEAR", "CALL_SHORT_ROOM", "CALL_RELOADING", "CALL_GUN_UP", "CALL_MAN_DOWN"]
const META_KEYS := ["result", "objectives", "pause_requested", "pause_reason", "pause_unit_id", "sound_zones", "smoke_zones", "seed", "variant", "modifiers", "win", "fail", "stars", "loadout", "roster", "first_alert_time", "environment", "flash_projectiles", "broken_glass"] + STAT_KEYS + DOCTRINE_KEYS + ROOM_STATE_KEYS + P5_META_KEYS + ROOM_DOCTRINE_KEYS
const V2_META_KEYS := ["interactive_targets"]
const EVENT_KEYS := ["seq", "tick", "time", "type", "message", "from", "to", "entity_id", "target_id", "unit_id", "enemy_id", "door_id", "civilian_id", "command_id", "radius", "channel", "released", "attacker_id", "hostile", "hit", "kind", "method", "enemy_type", "duration", "unlawful", "requested", "resolved", "weapon_origin", "target_height", "transmission", "projectile_id", "source_height", "flight_duration", "detonate_at", "hit_part", "hit_direction", "protection", "armor_id", "panel", "damage", "damage_multiplier", "slot", "weapon", "object_id", "object_kind", "sync_id", "auto_signal", "room_id", "cover_unit_id", "observed"] + SIGNAL_PROVENANCE_KEYS
const EVENT_TYPES := ["MISSION_START", "MISSION_END", "SIGNAL", "DOOR_OPEN", "DOOR_KICK", "DOOR_PEEK", "DOOR_BREACH", "DOOR_ACTION", "DOOR_DESTROYED", "DESTINATION_ADJUSTED", "RELOAD", "CIVILIAN_SECURED", "CIVILIAN_PANIC", "CIVILIAN_ESCORTED", "COMMAND_FAILED", "STUN", "SMOKE", "CONTACT", "SHOT", "INCAPACITATED", "SURRENDER", "ARREST", "REARM", "SUPPRESSED", "HOSTAGE_ATTACK", "FLASH_RELEASE", "WEAPON_SWITCH", "CAMERA_PEEK", "ARMOR_HIT", "CAMERA", "GLASS_BREAK", "KICK_FAILED", "BREACH_RETREAT", "FRAG_RELEASE", "FRAG"] + CALL_EVENT_TYPES
const V2_EVENT_TYPES := ["TARGET_COMPLETE"]
const RESULT_KEYS := ["success", "status", "title", "reason", "score", "rank", "time", "duration", "neutralized", "enemies_total", "rescued", "civilians_total", "survivors", "units_total", "losses", "first_alert_time", "seed", "variant", "modifiers", "stars"] + STAT_KEYS + DOCTRINE_KEYS + ROOM_STATE_KEYS + P5_RESULT_KEYS + ROOM_DOCTRINE_KEYS
const MODIFIERS := ["night", "dim", "low_ammo", "fast_reaction", "no_stun"]
const MATERIALS := ["wood", "concrete", "metal", "fabric", "glass", "masonry", "plaster", "foliage", "steel", "drywall", "brick", "cloth"]
const AWARENESS := ["UNAWARE", "DETECTED", "IDENTIFIED", "TRACKING", "SUSPICIOUS"]
const SOURCES := ["none", "sight", "sound", "report", "camera"]

var duration: float = 0.0
var complete: bool = false
var content_revision: int = 0
var data: Dictionary = {}
var frames: Array = []
var _states: Array = []
var _commands: Array = []
var _metadata: Array = []
var _events: Array = []
var _state_lookup: Dictionary = {}
var _command_lookup: Dictionary = {}
var _meta_lookup: Dictionary = {}
var _event_lookup: Dictionary = {}
var _last_sample: float = -1.0
var _last_event_seq: int = -1
var _stopped: bool = false
var _finished: bool = false
var _memory_bytes: int = 0
var _serialized_bytes: int = 0
var _last_discrete: Array = []
var _neutralized_cursor: int = 0
var _neutralized_ids: Dictionary = {}
var _validated_memory_bytes: int = 0
var _error: String = ""
var _valid_entity_ids: Dictionary = {}
var _valid_door_ids: Dictionary = {}
var _valid_room_ids: Dictionary = {}
var _validation_bounds: Array = [32.0, 32.0]
var _validation_map_version: int = 1
var _valid_target_definitions: Dictionary = {}
var _valid_star_ids: Dictionary = {}
var _validation_p5_record: bool = false

func begin(mission: Dictionary) -> void:
	content_revision += 1
	duration = 0.0
	complete = false
	frames = []
	_states = []
	_commands = []
	_metadata = []
	_events = []
	_state_lookup = {}
	_command_lookup = {}
	_meta_lookup = {}
	_event_lookup = {}
	_last_sample = -1.0
	_last_event_seq = -1
	_stopped = false
	_finished = false
	_memory_bytes = 1024
	_serialized_bytes = 1024
	_last_discrete = []
	_neutralized_cursor = 0
	_neutralized_ids.clear()
	data = {"schema_version": SCHEMA_VERSION, "game_build_id": BUILD_ID,
		"map_id": str(mission.get("id", "T01")), "map_revision": int(mission.get("revision", 1)),
		"seed": int(mission.get("seed", 1)), "variant": str(mission.get("variant", mission.get("id", "T01"))),
		"modifiers": mission.get("modifiers", []).duplicate(),
		"environment": mission.get("environment", {}).duplicate(true),
		"loadout": mission.get("loadout", {}).duplicate(true), "roster": mission.get("roster", []).duplicate(true),
		"asset_catalog_hash": CATALOG_HASH, "encoding": ENCODING,
		"bounds": mission.get("bounds", [32, 32]).duplicate(), "duration": 0.0,
		"complete": false, "states": _states, "commands": _commands,
		"metadata": _metadata, "events": _events, "frames": frames}
	if bool(mission.get("custom", false)) or not MissionCatalog.MAPS.has(str(mission.get("id", "T01"))):
		data["mission_data"] = mission.get("mission_data", mission).duplicate(true)
	var header_bytes: int = JSON.stringify(data).to_utf8_buffer().size()
	_memory_bytes += header_bytes * 4
	_serialized_bytes += header_bytes

func capture(state: Dictionary, new_events: Variant = null) -> void:
	_record(state, false, new_events)

func finish(state: Dictionary) -> void:
	if _finished:
		return
	_record(state, true)
	_finished = true
	complete = not _stopped and float(state.get("time", 0.0)) <= LIMIT_SECONDS
	data["complete"] = complete
	data["duration"] = duration

func _record(state: Dictionary, force: bool, new_events: Variant = null) -> void:
	if _stopped or _finished or data.is_empty():
		return
	var now := float(state.get("time", 0.0))
	if not is_finite(now) or now < 0.0 or now < duration - 0.000001:
		return
	if now > LIMIT_SECONDS + 0.000001:
		_stop_recording()
		return
	var event_changed := _append_events(state.get("events", []) if new_events == null else new_events, now)
	if _stopped:
		_stop_recording()
		return
	var discrete := _discrete_signature(state)
	var state_changed := discrete != _last_discrete
	if not force and not event_changed and not state_changed and _last_sample >= 0.0 and now - _last_sample < SAMPLE_INTERVAL - 0.000001:
		return
	for group: String in GROUPS:
		for entity: Dictionary in state.get(group, []):
			if entity.get("commands", []).size() > MAX_ENTITY_COMMANDS:
				_stop_recording()
				return
	if _states.size() >= MAX_STATES - 132 or _commands.size() >= MAX_COMMANDS - 512:
		_stop_recording()
		return
	if frames.size() >= MAX_FRAMES or _memory_bytes >= MAX_MEMORY_BYTES - 262144 or _serialized_bytes >= MAX_FILE_BYTES - 262144:
		_stop_recording()
		return
	var frame: Array = [now, int(state.get("tick", roundi(now * 30.0)))]
	for group: String in GROUPS:
		var packed := PackedFloat64Array()
		for entity: Dictionary in state.get(group, []):
			var row := _pack_entity(entity, group)
			packed.append(float(row.size()))
			packed.append_array(row)
		frame.append(packed)
		_memory_bytes += packed.size() * 12 + 128
	var metadata := state.duplicate(false)
	for key: String in ["time", "tick", "units", "enemies", "civilians", "doors", "events"]:
		metadata.erase(key)
	# Snapshots normally own these maps, but callers can reuse and mutate one
	# input dictionary. Interned metadata must retain each historical room row.
	_copy_room_state_maps(metadata)
	_copy_p5_metadata(metadata)
	_copy_room_doctrine(metadata)
	if metadata.get("result") is Dictionary:
		metadata.result = metadata.result.duplicate(false)
		_copy_room_state_maps(metadata.result)
	frame.append(_intern(metadata, _metadata, _meta_lookup))
	_memory_bytes += 384
	var frame_bytes := JSON.stringify(frame, "", true, true).to_utf8_buffer().size() + 1
	if not frames.is_empty() and is_equal_approx(float(frames[-1][0]), now):
		_memory_bytes -= 384
		for group_index in range(2, 6):
			_memory_bytes -= frames[-1][group_index].size() * 12 + 128
		_serialized_bytes -= JSON.stringify(frames[-1], "", true, true).to_utf8_buffer().size() + 1
		frames[-1] = frame
	else:
		frames.append(frame)
	_serialized_bytes += frame_bytes
	content_revision += 1
	duration = now
	_last_sample = now
	_last_discrete = discrete
	data["duration"] = duration
	if now >= LIMIT_SECONDS - 0.000001 and not force:
		_stopped = true
		data["complete"] = false

func _stop_recording() -> void:
	_stopped = true
	complete = false
	data["complete"] = false
	# A resource cap can be reached after events were read but before a frame
	# was accepted. Never export events beyond the retained replay prefix.
	while not _events.is_empty() and float(_events[-1].get("time", 0.0)) > duration:
		_event_lookup.erase(int(_events[-1].get("seq", -1)))
		_events.pop_back()

func _discrete_signature(state: Dictionary) -> Array:
	var signature: Array = []
	for group: String in GROUPS:
		for entity: Dictionary in state.get(group, []):
			var item: Array = []
			for key: String in ["id", "status", "status_reason", "state", "owner_id", "owner_command_id", "blocked", "reason", "visible", "secured", "hp", "ammo", "stuns", "smokes", "breaches", "surrendered", "arrested", "suppressed", "follow_unit_id", "facing_locked", "facing_persistent", "turn_started_at", "stance", "movement_mode", "hold_position", "reserve_ammo", "injury", "injury_status", "awareness_state", "observation_source", "aim_state", "destroyed", "locked", "hinge_side", "swing_sign", "material", "active_weapon", "current_weapon", "armor", "helmet", "primary_ammo", "secondary_ammo", "door_ready", "reinforced", "available_shotgun_breaches", "available_breaches", "frags", "available_frags"]:
				item.append(entity.get(key))
			# Sector changes are discrete doctrine state. A deep copy keeps an
			# in-place expansion from also mutating the previous signature.
			item.append(entity.get("sector", {}).duplicate(true))
			for command: Dictionary in entity.get("commands", []):
				item.append(command.get("id"))
				item.append(command.get("state"))
				item.append(command.get("reason"))
				item.append(command.get("phase"))
				# Macro metadata may be edited before execution; retain its exact
				# revision without sharing the caller's nested dictionaries.
				item.append(command.get("args", {}).get("formation", {}).duplicate(true))
				item.append(command.get("args", {}).get("stance"))
				if command.get("type") == "WAIT_FOR_SIGNAL":
					for key: String in ["signal", "sync_id", "auto_signal", "delay_ticks"]: item.append(command.get("args", {}).get(key))
			signature.append(item)
	var result_signature: Dictionary = state.get("result", {}).duplicate(true)
	result_signature.erase("room_doctrine")
	signature.append(result_signature)
	# A cumulative dwell value changes continuously. Force an exact retained
	# tick only when the public first/worst-exit evidence receipt changes.
	signature.append(_room_doctrine_evidence(state))
	signature.append(_room_doctrine_evidence(state.get("result", {})))
	for key: String in ROOM_STATE_KEYS:
		signature.append(state.get(key, {}).duplicate(true))
	for key: String in ["pause_requested", "pause_reason", "pause_unit_id"]:
		signature.append(state.get(key))
	if state.has("stats_observed"): signature.append(state.stats_observed.duplicate(true))
	for key: String in P5_STAT_KEYS: signature.append(state.get(key))
	if state.has("frag_projectiles"):
		signature.append(state.frag_projectiles.map(func(item: Dictionary) -> String: return str(item.get("id", "")) + str(item.get("phase", ""))))
	signature.append(state.get("smoke_zones", []).size())
	signature.append(state.get("flash_projectiles", []).map(func(item: Dictionary) -> String: return str(item.get("id", "")) + str(item.get("phase", ""))))
	return signature

static func _copy_room_state_maps(state: Dictionary) -> void:
	for key: String in ROOM_STATE_KEYS:
		if state.get(key) is Dictionary:
			state[key] = state[key].duplicate(true)

static func _copy_p5_metadata(state: Dictionary) -> void:
	if state.get("stats_observed") is Dictionary: state.stats_observed = state.stats_observed.duplicate(true)
	if state.get("frag_projectiles") is Array: state.frag_projectiles = state.frag_projectiles.duplicate(true)
	if state.get("result") is Dictionary:
		state.result = state.result.duplicate(false)
		for key: String in ["stats_observed", "stars", "stars_observed"]:
			if state.result.get(key) is Dictionary: state.result[key] = state.result[key].duplicate(true)

static func _copy_room_doctrine(state: Dictionary) -> void:
	if state.get("room_doctrine") is Dictionary: state.room_doctrine = state.room_doctrine.duplicate(true)
	if state.get("result") is Dictionary and state.result.get("room_doctrine") is Dictionary:
		state.result = state.result.duplicate(false)
		state.result.room_doctrine = state.result.room_doctrine.duplicate(true)

static func _room_doctrine_evidence(value: Dictionary) -> Array:
	var signature: Array = []
	if not value.get("room_doctrine") is Dictionary: return signature
	var room_ids: Array = value.room_doctrine.keys()
	room_ids.sort()
	for room_id: String in room_ids:
		signature.append(room_id)
		for metric: String in ROOM_DOCTRINE_METRICS:
			var row: Dictionary = value.room_doctrine[room_id].get(metric, {})
			signature.append([row.get("tick"), row.get("time"), row.get("unit_id"), row.get("door_id")])
	return signature

func _pack_entity(entity: Dictionary, group: String) -> PackedFloat64Array:
	var base := entity.duplicate(true)
	for key: Variant in base.keys():
		if str(key).begins_with("_"): base.erase(key)
	# World-space weapon position changes every sample. Encode its coordinates
	# numerically so moving actors reuse a finite set of static definitions.
	if base.get("weapon_origin") is Array and base.weapon_origin.size() == 3 and base.weapon_origin.all(func(value: Variant) -> bool: return _is_number(value)):
		base["weapon_origin_x"] = base.weapon_origin[0]
		base["weapon_origin_z"] = base.weapon_origin[1]
		base["weapon_origin_height"] = base.weapon_origin[2]
		base.erase("weapon_origin")
	var fields: Array = []
	var values := PackedFloat64Array()
	var keys := base.keys()
	keys.sort()
	for key: String in keys:
		if _is_number(base[key]):
			fields.append(key)
			values.append(float(base[key]))
			base.erase(key)
	var has_last_seen := false
	if base.get("last_seen") is Array and base["last_seen"].size() == 2:
		has_last_seen = true
		values.append(float(base["last_seen"][0]))
		values.append(float(base["last_seen"][1]))
		base.erase("last_seen")
	var command_ids: Array = []
	var remaining_indices: Array = []
	var has_commands := base.has("commands")
	if has_commands:
		var queue: Array = base["commands"]
		base.erase("commands")
		for i in queue.size():
			# base already owns a deep copy, including its commands and args.
			var command: Dictionary = queue[i]
			for key: Variant in command.keys():
				if str(key).begins_with("_"): command.erase(key)
			var remaining := float(command.get("remaining", 0.0))
			if command.has("remaining"):
				command["remaining"] = 0.0
			if remaining != 0.0:
				remaining_indices.append(i)
				values.append(remaining)
			command_ids.append(_intern(command, _commands, _command_lookup))
	var definition := {"group": group, "base": base, "fields": fields,
		"last_seen": has_last_seen, "has_commands": has_commands,
		"commands": command_ids, "remaining": remaining_indices}
	var row := PackedFloat64Array([float(_intern(definition, _states, _state_lookup))])
	row.append_array(values)
	return row

func _intern(value: Dictionary, table: Array, lookup: Dictionary) -> int:
	# Most definitions/commands repeat while only their numeric sample changes.
	# Check exact owned values before serializing them again. A hash collision
	# only adds an equality check; the canonical JSON lookup remains fallback.
	var fingerprint := hash(value)
	for candidate: int in lookup.get(fingerprint, []):
		if table[candidate] == value: return candidate
	var signature := JSON.stringify(value, "", true, true)
	var index: int
	if lookup.has(signature):
		index = int(lookup[signature])
	else:
		index = table.size()
		table.append(value)
		lookup[signature] = index
		_memory_bytes += signature.to_utf8_buffer().size() * 4 + 384
		_serialized_bytes += signature.to_utf8_buffer().size() + 1
	if not lookup.has(fingerprint):
		lookup[fingerprint] = []
		_memory_bytes += 80
	lookup[fingerprint].append(index)
	_memory_bytes += 16
	return index

func _append_events(events: Array, now: float) -> bool:
	var changed := false
	for event: Dictionary in events:
		var seq := int(event.get("seq", event.get("sequence", -1)))
		if seq < 0 or _event_lookup.has(seq) or float(event.get("time", now)) > LIMIT_SECONDS:
			continue
		if _events.size() >= MAX_EVENTS:
			_stopped = true
			break
		_events.append(event.duplicate(true))
		_event_lookup[seq] = true
		_last_event_seq = maxi(seq, _last_event_seq)
		var bytes := JSON.stringify(event, "", true, true).to_utf8_buffer().size()
		_memory_bytes += bytes * 4 + 384
		_serialized_bytes += bytes + 1
		changed = true
	return changed

func export_data() -> Dictionary:
	data["duration"] = duration
	data["complete"] = complete
	return data.duplicate(true)

func estimate_memory_bytes() -> int:
	return _memory_bytes

func get_memory_bytes() -> int:
	return estimate_memory_bytes()

func export_size_bytes() -> int:
	return JSON.stringify(data).to_utf8_buffer().size()

func is_partial() -> bool:
	return _stopped or (_finished and not complete)

func seek(at_time: float, reveal: bool = false) -> Dictionary:
	if frames.is_empty() or not is_finite(at_time):
		return {}
	var target := clampf(at_time, 0.0, duration)
	var index := _frame_at(target)
	var frame: Array = frames[index]
	var state: Dictionary = _metadata[int(frame[6])].duplicate(true)
	for key: String in ["seed", "variant", "modifiers", "loadout", "roster", "environment"]:
		if not state.has(key):
			state[key] = data.get(key, {} if key in ["loadout", "environment"] else ([] if key in ["modifiers", "roster"] else (1 if key == "seed" else "")))
	state["flash_projectiles"] = sample_flash_projectiles(state.get("flash_projectiles", []), target)
	# Retained samples own the authoritative (Vector3 precision) pose. Only
	# seek between samples synthesizes the established physical throw arc.
	if state.has("frag_projectiles") and absf(target - float(frame[0])) > 0.000001:
		state.frag_projectiles = sample_frag_projectiles(state.frag_projectiles, target)
	state["time"] = target
	state["tick"] = int(frame[1])
	for group_index in GROUPS.size():
		state[GROUPS[group_index]] = _unpack_group(frame[group_index + 2])
	if index + 1 < frames.size() and float(frame[0]) < target:
		var following: Array = frames[index + 1]
		var span := float(following[0]) - float(frame[0])
		if span > 0.0:
			var weight := clampf((target - float(frame[0])) / span, 0.0, 1.0)
			for group_index in GROUPS.size():
				_interpolate_group(state[GROUPS[group_index]], _unpack_group(following[group_index + 2]), weight, reveal)
	if not reveal:
		# Capture the marker before the shared projection erases its private
		# bundle. A failed subsequent import must not alter this loaded record.
		var observed_p5: bool = state.has("stats_observed") or state.get("result", {}).has("stats_observed")
		DoctrineMetrics.filter_observed_statistics(state)
		RoomControl.project_observed_state(state)
		var observed: Array = []
		for enemy: Dictionary in state.get("enemies", []):
			if bool(enemy.get("visible", false)):
				observed.append(enemy)
		state["enemies"] = observed
		var known_civilians: Array = []
		for civilian: Dictionary in state.get("civilians", []):
			if bool(civilian.get("visible", false)) or (not observed_p5 and (civilian.has("last_seen") or bool(civilian.get("secured", false)))):
				known_civilians.append(civilian)
		state["civilians"] = known_civilians
	var cursor := _event_end_at(target)
	var visible_events: Array = []
	for i in range(maxi(0, cursor - 40), cursor):
		visible_events.append(_events[i].duplicate(true))
	if not reveal:
		visible_events = RoomControl.filter_observed_call_events(visible_events)
	state["events"] = visible_events
	state["neutralized_ids"] = _neutralized_at(cursor)
	return state

func _neutralized_at(cursor: int) -> Array:
	if cursor < _neutralized_cursor:
		_neutralized_cursor = 0
		_neutralized_ids.clear()
	for i in range(_neutralized_cursor, cursor):
		var event: Dictionary = _events[i]
		if event.get("type", "") == "INCAPACITATED" and event.get("kind", "") == "enemy":
			_neutralized_ids[str(event.get("entity_id", ""))] = true
		elif event.get("type", "") == "ARREST":
			_neutralized_ids[str(event.get("enemy_id", ""))] = true
	_neutralized_cursor = cursor
	return _neutralized_ids.keys()

func _frame_at(target: float) -> int:
	var lo := 0
	var hi := frames.size() - 1
	while lo < hi:
		var middle := (lo + hi + 1) / 2
		if float(frames[middle][0]) <= target + 0.00000001:
			lo = middle
		else:
			hi = middle - 1
	return lo

func _event_end_at(target: float) -> int:
	var lo := 0
	var hi := _events.size()
	while lo < hi:
		var middle := (lo + hi) / 2
		if float(_events[middle].get("time", 0.0)) <= target + 0.00000001:
			lo = middle + 1
		else:
			hi = middle
	return lo

func events_since(sequence: int, at_time: float, reveal: bool = true) -> Array:
	if not is_finite(at_time): return []
	var end := _event_end_at(clampf(at_time, 0.0, duration))
	var lo := 0
	var hi := end
	while lo < hi:
		var middle := (lo + hi) / 2
		if int(_events[middle].get("seq", 0)) <= sequence:
			lo = middle + 1
		else:
			hi = middle
	var events: Array = []
	for i in range(lo, end): events.append(_events[i].duplicate(true))
	return events if reveal else RoomControl.filter_observed_call_events(events)

func _unpack_group(packed: Variant) -> Array:
	var entities: Array = []
	var cursor := 0
	while cursor < packed.size():
		var length := int(packed[cursor])
		cursor += 1
		var definition: Dictionary = _states[int(packed[cursor])]
		var entity: Dictionary = definition["base"].duplicate(true)
		var offset := cursor + 1
		for key: String in definition["fields"]:
			entity[key] = packed[offset]
			offset += 1
		if definition["last_seen"]:
			entity["last_seen"] = [packed[offset], packed[offset + 1]]
			offset += 2
		if definition["has_commands"]:
			var queue: Array = []
			for command_id: Variant in definition["commands"]:
				queue.append(_commands[int(command_id)].duplicate(true))
			for command_index: Variant in definition["remaining"]:
				queue[int(command_index)]["remaining"] = packed[offset]
				offset += 1
			entity["commands"] = queue
		if entity.has("weapon_origin_x") and entity.has("weapon_origin_z") and entity.has("weapon_origin_height"):
			entity["weapon_origin"] = [entity.weapon_origin_x,entity.weapon_origin_z,entity.weapon_origin_height]
			for key: String in ["weapon_origin_x","weapon_origin_z","weapon_origin_height"]: entity.erase(key)
		_legacy_defaults(entity, str(definition.group))
		entities.append(entity)
		cursor += length
	return entities

func _legacy_defaults(entity: Dictionary, group: String) -> void:
	if group == "doors":
		for key: String in ["hinge_side","swing_sign","destroyed"]:
			if not entity.has(key): entity[key] = false if key == "destroyed" else -1.0
		return
	# These defaults only fill omitted fields on old v1 records. They never
	# infer private perception memory or mutate the imported file definitions.
	var defaults := {"stance":"standing","movement_mode":"normal","hold_position":false,"reserve_ammo":0,"body_facing":entity.get("facing",0.0),"aim_progress":1.0,"injury_status":"none","mobility_multiplier":1.0,"velocity_x":0.0,"velocity_z":0.0,"awareness_state":"UNAWARE","awareness_confidence":0.0,"observation_source":"none","exposure":1.0,"aim_state":"idle","action_multiplier":1.0}
	for key: String in defaults:
		if not entity.has(key): entity[key] = defaults[key]
	if group == "enemies" and not entity.has("door_ready"): entity["door_ready"] = false

func _interpolate_group(previous: Array, following: Array, weight: float, reveal: bool = false) -> void:
	var by_id: Dictionary = {}
	for entity: Dictionary in following:
		by_id[str(entity.get("id", ""))] = entity
	for entity: Dictionary in previous:
		var next: Dictionary = by_id.get(str(entity.get("id", "")), {})
		if next.is_empty():
			continue
		# The following record contains omniscient coordinates. An observed
		# replay must not move a visible actor toward a future hidden position,
		# or pre-position an unseen actor before the actual contact frame.
		if not reveal and entity.has("visible"):
			if not bool(entity.get("visible", false)) or not bool(next.get("visible", false)):
				continue
		if entity.has("x") and next.has("x") and entity.has("z") and next.has("z"):
			var distance := Vector2(float(entity["x"]), float(entity["z"])).distance_to(Vector2(float(next["x"]), float(next["z"])))
			if distance <= 3.0:
				entity["x"] = lerpf(float(entity["x"]), float(next["x"]), weight)
				entity["z"] = lerpf(float(entity["z"]), float(next["z"]), weight)
		for angle: String in ["facing", "aim_facing", "move_facing", "body_facing"]:
			if entity.has(angle) and next.has(angle):
				entity[angle] = lerp_angle(float(entity[angle]), float(next[angle]), weight)
		for key: String in ["animation_phase", "progress", "travel_distance", "aim_progress", "current_weapon_height", "velocity_x", "velocity_z"]:
			if entity.has(key) and next.has(key):
				entity[key] = lerpf(float(entity[key]), float(next[key]), weight)
		if entity.has("weapon_origin") and next.has("weapon_origin"):
			for axis: int in range(3): entity.weapon_origin[axis] = lerpf(float(entity.weapon_origin[axis]),float(next.weapon_origin[axis]),weight)

func load_data(candidate: Dictionary) -> Dictionary:
	_error = ""
	if not _validate(candidate):
		return {"ok": false, "message": _error if not _error.is_empty() else "올바른 리플레이 파일이 아닙니다."}
	# Commit only after the entire file has passed validation.
	data = candidate.duplicate(true)
	# Version 1 recordings produced before sustained play omit these keys.
	var mission: Dictionary = data.get("mission_data", MissionCatalog.load(str(data["map_id"])))
	data["seed"] = candidate.get("seed", int(mission.get("seed", 1)))
	data["variant"] = candidate.get("variant", str(mission.get("variant", data["map_id"])))
	data["modifiers"] = candidate.get("modifiers", [])
	data["loadout"] = candidate.get("loadout", {})
	data["roster"] = candidate.get("roster", [])
	data["environment"] = candidate.get("environment", mission.get("environment", {}))
	frames = data["frames"]
	for frame: Array in frames:
		for i in range(2, 6):
			frame[i] = PackedFloat64Array(frame[i])
	_states = data["states"]
	_commands = data["commands"]
	_metadata = data["metadata"]
	_events = data["events"]
	duration = float(data["duration"])
	complete = bool(data["complete"])
	_finished = true
	_stopped = not complete
	_last_sample = duration
	_state_lookup = {}
	_command_lookup = {}
	_meta_lookup = {}
	_event_lookup = {}
	_neutralized_cursor = 0
	_neutralized_ids.clear()
	_memory_bytes = _validated_memory_bytes
	content_revision += 1
	return {"ok": true, "message": "리플레이를 불러왔습니다."}

func _fail(message: String) -> bool:
	_error = message
	return false

func _validate(candidate: Dictionary) -> bool:
	_validation_map_version = 1
	_valid_target_definitions.clear()
	if not _exact_keys(candidate, TOP_KEYS, REQUIRED_TOP_KEYS):
		return _fail("리플레이 구조에 누락되거나 지원하지 않는 항목이 있습니다.")
	if not _integer(candidate["schema_version"], 1, 1) or not candidate["encoding"] is String or candidate["encoding"] != ENCODING:
		return _fail("지원하지 않는 리플레이 형식 버전입니다.")
	if not candidate["game_build_id"] is String or candidate["game_build_id"] != BUILD_ID:
		return _fail("이 게임 버전에서 재생할 수 없는 리플레이입니다.")
	if not _identifier(candidate["map_id"]) or (not MissionCatalog.MAPS.has(candidate["map_id"]) and not candidate.has("mission_data")) or not _integer(candidate["map_revision"], 1, 2147483647):
		return _fail("지원하지 않는 맵 또는 맵 버전입니다.")
	if not candidate.has("mission_data"):
		var authored: Dictionary = MissionCatalog.load(str(candidate.map_id))
		var current_revision: int = int(authored.get("revision",1))
		if int(candidate.map_revision) != current_revision and (int(candidate.map_revision) != 1 or MissionCatalog.HISTORICAL_IDS.has(str(candidate.map_id))):
			return _fail("지원하지 않는 맵 또는 맵 버전입니다.")
	if candidate.has("mission_data"):
		var embedded: Variant = candidate["mission_data"]
		if not embedded is Dictionary or str(embedded.get("id", "")) != candidate["map_id"] or embedded.get("revision") != candidate["map_revision"] or not MissionCatalog.validate_custom(embedded).get("ok", false):
			return _fail("리플레이에 포함된 사용자 맵이 올바르지 않습니다.")
	var source_map: Dictionary = candidate.get("mission_data", MissionCatalog.load(str(candidate.map_id)))
	_valid_room_ids.clear()
	for room: Dictionary in source_map.get("rooms", []): _valid_room_ids[str(room.id)] = true
	_validation_map_version = int(source_map.get("schema_version",1))
	for key: String in ["loadout", "roster"]:
		var correct_shape: bool = candidate.get(key, {} if key == "loadout" else []) is Dictionary if key == "loadout" else candidate.get(key, []) is Array
		if candidate.has(key) and (not correct_shape or not _safe_small_tree(candidate[key], 0)):
			return _fail("리플레이 대원 구성 정보가 올바르지 않습니다.")
	if not candidate["asset_catalog_hash"] is String or candidate["asset_catalog_hash"] != CATALOG_HASH:
		return _fail("리플레이의 에셋 카탈로그가 일치하지 않습니다.")
	if not _number(candidate["duration"], 0.0, LIMIT_SECONDS) or not candidate["complete"] is bool:
		return _fail("리플레이의 기록 시간 또는 완료 상태가 잘못되었습니다.")
	if not _point(candidate["bounds"], 1.0, 512.0 if _validation_map_version >= 2 else 32.0):
		return _fail("리플레이 맵 크기가 올바르지 않습니다.")
	_validation_bounds = candidate["bounds"]
	if not _load_known_map(str(candidate["map_id"]), candidate.get("mission_data", {})):
		return false
	if not _validate_run_identity(candidate): return false
	var limits := {"states": MAX_STATES, "commands": MAX_COMMANDS, "metadata": MAX_FRAMES, "events": MAX_EVENTS, "frames": MAX_FRAMES}
	for key: String in limits:
		if not candidate[key] is Array or candidate[key].size() > int(limits[key]):
			return _fail("리플레이 기록 개수가 제한을 초과했습니다: " + key)
	if candidate["frames"].is_empty() or candidate["states"].is_empty() or candidate["metadata"].is_empty():
		return _fail("리플레이에 재생할 기록이 없습니다.")
	_validation_p5_record = _candidate_uses_p5(candidate)
	for command: Variant in candidate["commands"]:
		if not _validate_command(command):
			return false
	for definition: Variant in candidate["states"]:
		if not _validate_definition(definition, candidate["commands"]):
			return false
	var room_clocks: Array = []
	var doctrine_clocks: Array = []
	for meta: Variant in candidate["metadata"]:
		if not _validate_meta(meta):
			return false
		room_clocks.append(_room_transition_clock(meta))
		doctrine_clocks.append(_room_doctrine_clock(meta))
	if not candidate["frames"][0] is Array or candidate["frames"][0].is_empty() or not _number(candidate["frames"][0][0], 0.0, 0.0):
		return _fail("리플레이는 작전 시작 시점부터 기록되어야 합니다.")
	var last_time := -1.0
	var last_tick := -1
	var total_numbers := 0
	var sync_queues: Dictionary = {}
	var has_sync_commands: bool = candidate.commands.any(func(command: Dictionary) -> bool: return command.type == "WAIT_FOR_SIGNAL" and command.args.has("sync_id"))
	for frame: Variant in candidate["frames"]:
		if not frame is Array or frame.size() != 7:
			return _fail("리플레이 샘플 구조가 올바르지 않습니다.")
		if not _number(frame[0], 0.0, float(candidate["duration"])) or float(frame[0]) <= last_time or not _integer(frame[1], 0, 36000000) or int(frame[1]) < last_tick:
			return _fail("리플레이 샘플 시간 순서가 올바르지 않습니다.")
		if not _integer(frame[6], 0, candidate["metadata"].size() - 1):
			return _fail("리플레이 상태 참조가 올바르지 않습니다.")
		if not _validate_frag_clock(candidate.metadata[int(frame[6])], float(frame[0])): return _fail("리플레이 파편탄 궤적 시각이 샘플과 일치하지 않습니다.")
		var room_clock: Array = room_clocks[int(frame[6])]
		if int(room_clock[0]) > int(frame[1]) or float(room_clock[1]) > float(frame[0]) + 0.000001:
			return _fail("리플레이 방 전이가 샘플 시각보다 앞서 있습니다.")
		var doctrine_clock: Array = doctrine_clocks[int(frame[6])]
		if int(doctrine_clock[0]) > int(frame[1]) or float(doctrine_clock[1]) > float(frame[0]) + 0.000001:
			return _fail("리플레이 방 교범 증거가 샘플 시각보다 앞서 있습니다.")
		for group_index in GROUPS.size():
			if not _validate_group(frame[group_index + 2], group_index, candidate["states"]):
				return false
			total_numbers += frame[group_index + 2].size()
		if has_sync_commands and not _validate_sync_groups(frame[2], candidate.states, candidate.commands, sync_queues): return false
		if total_numbers * 12 > MAX_MEMORY_BYTES - 4 * 1024 * 1024:
			return _fail("리플레이 메모리 제한을 초과했습니다.")
		last_time = float(frame[0])
		last_tick = int(frame[1])
	if absf(last_time - float(candidate["duration"])) > 0.000001:
		return _fail("리플레이 길이와 마지막 샘플 시간이 일치하지 않습니다.")
	var last_seq := -1
	last_time = -1.0
	last_tick = -1
	for event: Variant in candidate["events"]:
		if not _validate_event(event, float(candidate["duration"])):
			return false
		var seq := int(event.get("seq", event.get("sequence", -1)))
		if seq <= last_seq or float(event["time"]) < last_time or int(event["tick"]) < last_tick:
			return _fail("리플레이 사건 순서가 올바르지 않습니다.")
		last_seq = seq
		last_time = float(event["time"])
		last_tick = int(event["tick"])
	var estimated: int = _estimate_header_memory(candidate) + total_numbers * 12 + candidate["frames"].size() * (384 + 4 * 128)
	for table_key: String in ["states", "commands", "metadata", "events"]:
		for item: Variant in candidate[table_key]:
			estimated += JSON.stringify(item).to_utf8_buffer().size() * 4 + 384
			if estimated > MAX_MEMORY_BYTES:
				return _fail("리플레이 메모리 제한을 초과했습니다.")
	if JSON.stringify(candidate).to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _fail("리플레이 파일은 최대 20 MB까지 열 수 있습니다.")
	_validated_memory_bytes = estimated
	return true

func _load_known_map(map_id: String, embedded: Dictionary = {}) -> bool:
	_valid_entity_ids = {}
	_valid_door_ids = {}
	_valid_target_definitions = {}
	_valid_star_ids = {}
	var map: Dictionary = embedded if not embedded.is_empty() else MissionCatalog.load(map_id)
	if map.is_empty():
		return _fail("이 리플레이의 맵 데이터가 설치되어 있지 않습니다.")
	# JSON round trips can change the last floating-point bits of authored bounds.
	if not map.get("bounds") is Array or map["bounds"].size() != 2 or not is_equal_approx(float(map["bounds"][0]), float(_validation_bounds[0])) or not is_equal_approx(float(map["bounds"][1]), float(_validation_bounds[1])):
		return _fail("리플레이 맵 크기가 설치된 맵과 일치하지 않습니다.")
	for group: String in GROUPS:
		for entity: Dictionary in map.get(group, []):
			if group == "doors":
				_valid_door_ids[str(entity["id"])] = true
			else:
				_valid_entity_ids[str(entity["id"])] = group
	for star: Dictionary in map.get("stars", []): _valid_star_ids[str(star.id)] = true
	if _validation_map_version >= 2:
		for target: Dictionary in map.get("interactive_targets",[]):
			_valid_target_definitions[str(target.id)] = target
	return true

func _validate_sync_groups(packed: Variant, definitions: Array, commands: Array, checked: Dictionary) -> bool:
	# Command tables retain earlier revisions. Compare queues within each
	# sample, so an atomic pending-group edit remains valid across time.
	var references: Array = []
	var cursor := 0
	while cursor < packed.size():
		references.append(int(packed[cursor + 1]))
		cursor += int(packed[cursor]) + 1
	var key := str(references)
	if checked.has(key): return true
	var groups: Dictionary = {}
	for reference: int in references:
		for command_index: Variant in definitions[reference].commands:
			var command: Dictionary = commands[int(command_index)]
			if command.type != "WAIT_FOR_SIGNAL" or command.state in ["SUCCEEDED", "FAILED", "CANCELLED"] or not command.args.has("sync_id"): continue
			var args: Dictionary = command.args
			var common_drill: Dictionary = args.get("drill", {}).duplicate(false)
			common_drill.erase("order")
			var common_formation: Dictionary = args.get("formation", {}).duplicate(false)
			common_formation.erase("order")
			var signature := [args.signal, bool(args.get("auto_signal", false)), int(args.get("delay_ticks", 0)), common_drill, common_formation]
			if groups.has(args.sync_id) and groups[args.sync_id] != signature: return _fail("리플레이 동기화 그룹의 설정이 일치하지 않습니다.")
			groups[args.sync_id] = signature
	checked[key] = true
	return true

func _validate_command(command: Variant) -> bool:
	if not command is Dictionary or not _exact_keys(command, ["id", "type", "args", "state", "reason", "remaining", "sequence", "owner_id", "issued_tick", "started_tick", "completed_tick", "path", "path_cursor", "conditional", "resolved_target", "completion_reason", "phase", "projectile_id"], ["id", "type", "args", "state"]):
		return _fail("리플레이 명령 구조가 올바르지 않습니다.")
	if not _identifier(command["id"]) or not command["type"] in COMMAND_TYPES or not command["state"] in COMMAND_STATES:
		return _fail("리플레이 명령 종류 또는 ID가 올바르지 않습니다.")
	if command.has("reason") and not _text(command["reason"], 256):
		return _fail("리플레이 명령 설명이 올바르지 않습니다.")
	if command.has("completion_reason") and not _text(command["completion_reason"],256):
		return _fail("리플레이 도착 설명이 올바르지 않습니다.")
	if command.has("resolved_target") and (command.type != "MOVE" or not _coordinate(command.resolved_target)):
		return _fail("리플레이 조정 목적지가 올바르지 않습니다.")
	if command.has("phase") and command.phase not in ["APPROACH", "OPEN", "PREPARE", "WAIT_EXPLOSION", "CAMERA"] + DOOR_ACTION_PHASES: return _fail("리플레이 복합 명령 단계가 올바르지 않습니다.")
	var door_phase := str(command.get("phase", ""))
	if door_phase in DOOR_ACTION_PHASES:
		var phase_types: Array = ["SHOTGUN_BREACH"] if door_phase.begins_with("SHOTGUN") else (["KICK_DOOR"] if door_phase == "KICK_RECOVER" else ["KICK_DOOR", "BREACH_DOOR"])
		if command.type not in phase_types: return _fail("리플레이 문 처리 단계의 명령 종류가 올바르지 않습니다.")
	if command.has("projectile_id") and not _identifier(command.projectile_id): return _fail("리플레이 투척물 ID가 올바르지 않습니다.")
	if command.has("remaining") and not _number(command["remaining"], 0.0, LIMIT_SECONDS):
		return _fail("리플레이 명령 시간이 올바르지 않습니다.")
	for key: String in ["sequence", "issued_tick", "started_tick", "completed_tick", "path_cursor"]:
		if command.has(key) and not _integer(command[key], 0, 36000000):
			return _fail("리플레이 명령 순번 또는 진행 상태가 올바르지 않습니다.")
	if command.has("owner_id") and not _known_entity(command["owner_id"], "units"):
		return _fail("리플레이 명령 소유자 ID가 올바르지 않습니다.")
	if command.has("conditional") and not command["conditional"] is bool:
		return _fail("리플레이 조건부 명령 상태가 올바르지 않습니다.")
	if command.has("path"):
		if not command["path"] is Array or command["path"].size() > 2048:
			return _fail("리플레이 이동 경로가 제한을 초과했습니다.")
		for point: Variant in command["path"]:
			if not _coordinate(point):
				return _fail("리플레이 이동 경로 좌표가 올바르지 않습니다.")
		if int(command.get("path_cursor", 0)) > command["path"].size():
			return _fail("리플레이 경로 진행 위치가 올바르지 않습니다.")
	var args: Variant = command["args"]
	if not args is Dictionary:
		return _fail("리플레이 명령 인수가 올바르지 않습니다.")
	if args.has("request_id") and not _identifier(args["request_id"]):
		return _fail("리플레이 명령 요청 ID가 올바르지 않습니다.")
	args = args.duplicate(false)
	args.erase("request_id")
	if command.type == "THROW_FRAG" and (not _exact_keys(args, ["target"], ["target"]) or not _coordinate(args.target) or (command.has("phase") and command.phase not in ["PREPARE", "WAIT_EXPLOSION"])): return _fail("리플레이 파편탄 명령이 올바르지 않습니다.")
	var formation: Dictionary = {}
	if args.has("formation"):
		if command.type not in ["MOVE", "FACE", "WAIT_FOR_SIGNAL"] or args.has("drill") or not _validate_formation(args.formation): return _fail("리플레이 대형 정보가 올바르지 않습니다.")
		formation = args.formation
		args.erase("formation")
	var drill: Dictionary = {}
	if args.has("drill"):
		if not _validate_drill(args.drill): return _fail("리플레이 진입 드릴 정보가 올바르지 않습니다.")
		drill = args.drill
		args.erase("drill")
	if args.has("sector"):
		if command.type not in ["MOVE", "FACE"] or not _validate_sector(args.sector, false) or (command.type == "FACE" and args.has("unlock")): return _fail("리플레이 사격 구역 명령이 올바르지 않습니다.")
		args.erase("sector")
	if door_phase.begins_with("BREACH_") and command.type == "KICK_DOOR" and args.get("fallback", "") != "breach": return _fail("리플레이 장약 전환 단계의 실패 분기가 올바르지 않습니다.")
	match str(command["type"]):
		"FACE":
			if args.has("unlock"):
				if not _exact_keys(args, ["unlock"], ["unlock"]) or not args["unlock"] is bool or not args["unlock"]:
					return _fail("리플레이 주시 해제 명령이 올바르지 않습니다.")
			elif not _exact_keys(args, ["target", "persistent", "stance"], ["target"]) or not _coordinate(args["target"]):
				return _fail("리플레이 명령 목표 좌표가 올바르지 않습니다.")
			elif args.has("persistent") and not args["persistent"] is bool:
				return _fail("리플레이 주시 고정 인수가 올바르지 않습니다.")
			elif args.has("stance") and args.stance not in ["standing", "crouched"]:
				return _fail("리플레이 계획 자세가 올바르지 않습니다.")
		"MOVE", "THROW_STUN", "THROW_SMOKE", "THROW_FRAG":
			if not _exact_keys(args, ["target"], ["target"]) or not _coordinate(args["target"]):
				return _fail("리플레이 명령 목표 좌표가 올바르지 않습니다.")
		"WAIT":
			if not _exact_keys(args, ["duration"], ["duration"]) or not _number(args["duration"], 0.0, LIMIT_SECONDS):
				return _fail("리플레이 대기 시간이 올바르지 않습니다.")
		"OPEN_DOOR", "PEEK_DOOR", "PEEK_CAMERA", "BREACH_DOOR", "SHOTGUN_BREACH", "HOLD_AT_DOOR":
			if not _exact_keys(args, ["door_id"], ["door_id"]) or not _known_door(args["door_id"]):
				return _fail("리플레이 문 ID가 올바르지 않습니다.")
		"KICK_DOOR":
			if not _exact_keys(args, ["door_id", "fallback"], ["door_id"]) or not _known_door(args["door_id"]): return _fail("리플레이 문 차기 인수가 올바르지 않습니다.")
			if args.has("fallback") and args.fallback != "breach": return _fail("리플레이 문 차기 실패 분기가 올바르지 않습니다.")
		"OPEN_AND_FLASH":
			if not _exact_keys(args, ["door_id", "target"], ["door_id"]) or not _known_door(args.door_id): return _fail("리플레이 문·섬광탄 명령이 올바르지 않습니다.")
			if args.has("target") and not _coordinate(args.target): return _fail("리플레이 섬광탄 착지점이 올바르지 않습니다.")
		"SWITCH_WEAPON":
			if not _exact_keys(args, ["slot"], ["slot"]) or args.slot not in ["primary", "secondary"]: return _fail("리플레이 무기 전환 슬롯이 올바르지 않습니다.")
		"SECURE_CIVILIAN", "ESCORT_CIVILIAN":
			if not _exact_keys(args, ["civilian_id"], ["civilian_id"]) or not _known_entity(args["civilian_id"], "civilians"):
				return _fail("리플레이 민간인 ID가 올바르지 않습니다.")
		"ARREST":
			if not _exact_keys(args, ["enemy_id"], ["enemy_id"]) or not _known_entity(args["enemy_id"], "enemies"):
				return _fail("리플레이 체포 대상 ID가 올바르지 않습니다.")
		"WAIT_FOR_SIGNAL":
			if not _exact_keys(args, ["signal", "sync_id", "auto_signal", "delay_ticks"], ["signal"]) or not args["signal"] in ["A", "B", "C"]:
				return _fail("리플레이 신호가 올바르지 않습니다.")
			if args.has("sync_id") and not _identifier(args.sync_id): return _fail("리플레이 드릴 동기화 ID가 올바르지 않습니다.")
			if args.has("auto_signal") and not args.auto_signal is bool: return _fail("리플레이 자동 신호 상태가 올바르지 않습니다.")
			if args.has("delay_ticks") and not _integer(args.delay_ticks, 0, 3600): return _fail("리플레이 신호 지연이 올바르지 않습니다.")
			if (args.has("auto_signal") or args.has("delay_ticks")) and not args.has("sync_id"): return _fail("리플레이 자동·지연 신호에 동기화 ID가 없습니다.")
			if not formation.is_empty() and (formation.stage != "ready" or args.get("sync_id", "") != formation.sync_id + ":ready"): return _fail("리플레이 신호와 대형 그룹이 일치하지 않습니다.")
			if not drill.is_empty():
				if drill.stage not in ["ready", "entry", "go_long"] or args.get("sync_id", "") != drill.sync_id + ":" + drill.stage: return _fail("리플레이 신호와 드릴 그룹이 일치하지 않습니다.")
				if drill.stage == "entry" and not bool(args.get("auto_signal", false)): return _fail("리플레이 진입 안전 신호는 자동이어야 합니다.")
		"RELOAD":
			if not args.is_empty():
				return _fail("재장전 명령에는 추가 인수를 사용할 수 없습니다.")
	return true

func _validate_formation(value: Variant) -> bool:
	var keys := ["sync_id", "kind", "order", "stage", "source_unit_id"]
	if not value is Dictionary or not _exact_keys(value, keys, keys): return false
	return _identifier(value.sync_id) and str(value.sync_id).length() <= 55 and value.kind in FORMATION_KINDS and _integer(value.order, 1, 4) and value.stage in FORMATION_STAGES and _known_entity(value.source_unit_id, "units")

func _validate_drill(value: Variant) -> bool:
	var keys := ["sync_id", "door_id", "room_id", "order", "stage"]
	if not value is Dictionary or not _exact_keys(value, keys, keys): return false
	return _identifier(value.sync_id) and str(value.sync_id).length() <= 55 and _known_door(value.door_id) and value.room_id is String and _valid_room_ids.has(value.room_id) and _integer(value.order, 1, 4) and value.stage in DRILL_STAGES

func _validate_sector(value: Variant, runtime: bool) -> bool:
	if not value is Dictionary: return false
	if runtime and value.is_empty(): return true
	var clock_key := "until" if runtime else "duration"
	var keys := ["start", "end", clock_key]
	# start > end is a valid fan crossing the world-angle -PI/PI boundary.
	return _exact_keys(value, keys, keys) and _number(value.start, -PI, PI) and _number(value.end, -PI, PI) and _number(value[clock_key], 0.0, LIMIT_SECONDS + MAX_SECTOR_DURATION if runtime else MAX_SECTOR_DURATION)

func _validate_definition(definition: Variant, commands: Array) -> bool:
	var keys := ["group", "base", "fields", "last_seen", "has_commands", "commands", "remaining"]
	if not definition is Dictionary or not _exact_keys(definition, keys, keys) or not definition["group"] in GROUPS:
		return _fail("리플레이 개체 정의가 올바르지 않습니다.")
	var group: String = definition["group"]
	var base: Variant = definition["base"]
	var allowed := DOOR_KEYS if group == "doors" else ENTITY_KEYS
	if not base is Dictionary or not _exact_keys(base, DOOR_STATIC_KEYS if group == "doors" else ENTITY_STATIC_KEYS, ["id"]):
		return _fail("리플레이 개체 속성에 지원하지 않는 항목이 있습니다.")
	if not (_known_door(base["id"]) if group == "doors" else _known_entity(base["id"], group)):
		return _fail("리플레이 개체 ID가 맵과 일치하지 않습니다.")
	for key: String in base:
		var value: Variant = base[key]
		if key == "last_seen" and value == null:
			continue
		if key in ["attachments", "appearance"]:
			if not EquipmentCatalog.loadout_error({"weapon": base.get("weapon", "standard"), key: value}).is_empty(): return _fail("리플레이 장착 장비 정보가 올바르지 않습니다.")
		elif key == "camera_observations":
			if not _validate_camera_observations(value) or (group != "units" and not value.is_empty()): return _fail("리플레이 카메라 관측 정보가 올바르지 않습니다.")
		elif key == "camera_origin":
			if group != "units" or not _coordinate(value): return _fail("리플레이 카메라 관측 원점이 올바르지 않습니다.")
		elif key == "peek_origin":
			if group != "units" or not _coordinate(value):
				return _fail("리플레이 문 관측 원점이 올바르지 않습니다.")
		elif key == "sector":
			if group != "units" or not _validate_sector(value, true): return _fail("리플레이 대원 사격 구역이 올바르지 않습니다.")
		elif key == "door_ready" and (group != "enemies" or not value is bool):
			return _fail("리플레이 문틀 경계 상태가 올바르지 않습니다.")
		elif key in ["visible", "secured", "alive", "detected", "alert", "locked", "opening", "blocked", "facing_locked", "facing_persistent", "target", "passive", "surrendered", "arrested", "suppressed", "observed", "can_surrender", "training", "hold_position", "destroyed", "opaque", "glass_broken", "door_ready", "reinforced"]:
			if not value is bool:
				return _fail("리플레이 개체의 논리 상태가 올바르지 않습니다.")
		elif not _text(value, 128):
			return _fail("리플레이 개체의 정적 속성이 올바르지 않습니다.")
	if group == "doors":
		if not str(base.get("owner_id", "")).is_empty() and not (_known_entity(base["owner_id"], "units") or _known_entity(base["owner_id"], "enemies")):
			return _fail("리플레이 문의 조작 담당자가 올바르지 않습니다.")
		if not str(base.get("owner_command_id", "")).is_empty() and not _identifier(base["owner_command_id"]):
			return _fail("리플레이 문의 담당 명령 ID가 올바르지 않습니다.")
	if base.has("kind") and base["kind"] != {"units": "unit", "enemies": "enemy", "civilians": "civilian"}.get(group, ""):
		return _fail("리플레이 개체 종류와 그룹이 일치하지 않습니다.")
	if base.has("status") and not base["status"] in ENTITY_STATUSES:
		return _fail("리플레이 개체 행동 상태를 지원하지 않습니다.")
	if group != "doors" and base.has("state") and not base["state"] in ENTITY_STATUSES:
		return _fail("리플레이 개체 상태를 지원하지 않습니다.")
	if base.has("weapon") and not base["weapon"] in ["standard", "light", "shotgun", "suppressed"]:
		return _fail("리플레이 개체 장비를 지원하지 않습니다.")
	for key: String in ["sidearm", "armor", "helmet", "preset"]:
		if base.has(key) and not EquipmentCatalog.loadout_error({key: base[key]}).is_empty(): return _fail("리플레이 장비 슬롯을 지원하지 않습니다: " + key)
	for key: String in ["last_hit_part", "last_hit_direction", "last_hit_protection"]:
		var values: Array = {"last_hit_part": ["head", "torso", "limb"], "last_hit_direction": ["front", "side", "back"], "last_hit_protection": ["blocked", "penetrated", "unprotected"]}[key]
		if base.has(key) and base[key] not in values: return _fail("리플레이 최근 피격 결과가 올바르지 않습니다.")
	if base.has("active_weapon") and base.active_weapon not in ["primary", "secondary"]: return _fail("리플레이 활성 무기 슬롯이 올바르지 않습니다.")
	if base.has("current_weapon") and base.current_weapon not in ["standard", "light", "shotgun", "suppressed", "pico_p1"]: return _fail("리플레이 활성 무기를 지원하지 않습니다.")
	if base.has("strength") and base.strength not in ["weak", "medium", "strong"]:
		return _fail("리플레이 적 전투 등급을 지원하지 않습니다.")
	if base.has("enemy_type") and not base["enemy_type"] in ["normal", "guard", "rusher", "hostage", "regular", "sentry", "assault", "hostage_taker"]:
		return _fail("리플레이 적 유형을 지원하지 않습니다.")
	if base.has("follow_unit_id") and not str(base["follow_unit_id"]).is_empty() and not _known_entity(base["follow_unit_id"], "units"):
		return _fail("리플레이 민간인의 호송 담당자가 올바르지 않습니다.")
	if base.has("base_id") and not _known_entity(base["base_id"], "units"):
		return _fail("리플레이 대원의 원래 ID가 올바르지 않습니다.")
	if base.has("roster_id") and not _identifier(base["roster_id"]):
		return _fail("리플레이 대원 명부 ID가 올바르지 않습니다.")
	if base.has("hostage_id") and not _known_entity(base["hostage_id"], "civilians"):
		return _fail("리플레이 인질 대상 ID가 올바르지 않습니다.")
	if base.has("civilian_state") and not base["civilian_state"] in ["IDLE", "PANIC", "FOLLOW", "SECURED"]:
		return _fail("리플레이 민간인 상태가 올바르지 않습니다.")
	for key: String in ["stance","movement_mode","injury","injury_status","aim_state","awareness_state","observation_source","material"]:
		if not base.has(key): continue
		var choices: Array = {"stance":["standing","crouched"],"movement_mode":["careful","normal","fast"],"injury":["none","hurt","wounded"],"injury_status":["none","hurt","wounded"],"aim_state":["idle","acquiring","ready","lowered"],"awareness_state":AWARENESS,"observation_source":SOURCES,"material":MATERIALS}[key]
		if not base[key] in choices: return _fail("리플레이 자세·인지·재질 상태가 올바르지 않습니다: " + key)
	if base.has("axis") and not base["axis"] in ["x", "z"]:
		return _fail("리플레이 문 방향이 올바르지 않습니다.")
	if group == "doors" and (not base.has("state") or not base["state"] in ["CLOSED", "OPENING", "AJAR", "OPEN", "DESTROYED"]):
		return _fail("리플레이 문 상태가 올바르지 않습니다.")
	if not definition["fields"] is Array or definition["fields"].size() > 96:
		return _fail("리플레이 수치 속성 개수가 올바르지 않습니다.")
	var seen: Dictionary = {}
	for key: Variant in definition["fields"]:
		if not key is String or not key in allowed or (key != "suppressed" and key in (DOOR_STATIC_KEYS if group == "doors" else ENTITY_STATIC_KEYS)) or key in ["commands", "last_seen"] or seen.has(key) or base.has(key):
			return _fail("리플레이 수치 속성이 올바르지 않습니다: " + str(key))
		if key in ["available_shotgun_breaches", "available_breaches", "frags", "available_frags"] and group != "units": return _fail("리플레이 브리칭 예약 정보의 대원 종류가 올바르지 않습니다.")
		if key == "base_height" and group != "doors" and _validation_map_version < 2: return _fail("기존 지도 리플레이의 대원 바닥 높이는 지원하지 않습니다.")
		seen[key] = true
	if not seen.has("x") or not seen.has("z"):
		return _fail("리플레이 개체 위치가 누락되었습니다.")
	var weapon_coordinates: int = int(seen.has("weapon_origin_x")) + int(seen.has("weapon_origin_z")) + int(seen.has("weapon_origin_height"))
	if weapon_coordinates != 0 and weapon_coordinates != 3:
		return _fail("리플레이 무기 위치 좌표가 완전하지 않습니다.")
	if not definition["last_seen"] is bool or not definition["has_commands"] is bool:
		return _fail("리플레이 개체 표시 정보가 올바르지 않습니다.")
	if definition["last_seen"] and (not group in ["enemies", "civilians"] or base.has("last_seen")):
		return _fail("리플레이 관측 위치가 올바르지 않습니다.")
	if not definition["commands"] is Array or definition["commands"].size() > MAX_ENTITY_COMMANDS or not definition["remaining"] is Array or definition["remaining"].size() > MAX_ENTITY_COMMANDS:
		return _fail("리플레이 명령 대기열이 제한을 초과했습니다.")
	if (not definition["has_commands"] or group != "units") and not definition["commands"].is_empty():
		return _fail("리플레이 명령 소유자가 올바르지 않습니다.")
	seen = {}
	for index: Variant in definition["commands"]:
		if not _integer(index, 0, commands.size() - 1) or seen.has(str(commands[int(index)]["id"])):
			return _fail("리플레이 명령 참조가 올바르지 않습니다.")
		seen[str(commands[int(index)]["id"])] = true
	seen = {}
	for index: Variant in definition["remaining"]:
		if not _integer(index, 0, definition["commands"].size() - 1) or seen.has(int(index)):
			return _fail("리플레이 명령 시간 참조가 올바르지 않습니다.")
		seen[int(index)] = true
	return true

func _validate_group(packed: Variant, group_index: int, definitions: Array) -> bool:
	if not packed is Array and not packed is PackedFloat64Array:
		return _fail("리플레이 위치 샘플이 올바르지 않습니다.")
	if packed.size() > int(GROUP_LIMITS[group_index]) * 300:
		return _fail("리플레이 위치 샘플이 제한을 초과했습니다.")
	var cursor := 0
	var count := 0
	var ids: Dictionary = {}
	while cursor < packed.size():
		if not _integer(packed[cursor], 1, 300):
			return _fail("리플레이 위치 샘플 길이가 올바르지 않습니다.")
		var length := int(packed[cursor])
		cursor += 1
		if cursor + length > packed.size() or not _integer(packed[cursor], 0, definitions.size() - 1):
			return _fail("리플레이 위치 샘플 참조가 올바르지 않습니다.")
		var definition: Dictionary = definitions[int(packed[cursor])]
		if definition["group"] != GROUPS[group_index] or ids.has(definition["base"]["id"]):
			return _fail("리플레이 개체 그룹 또는 중복 ID가 올바르지 않습니다.")
		ids[definition["base"]["id"]] = true
		var expected: int = 1 + definition["fields"].size() + (2 if definition["last_seen"] else 0) + definition["remaining"].size()
		if expected != length:
			return _fail("리플레이 수치 샘플 개수가 일치하지 않습니다.")
		var offset := cursor + 1
		for key: String in definition["fields"]:
			if not _validate_number_field(key, packed[offset]):
				return _fail("리플레이 수치 또는 좌표가 허용 범위를 벗어났습니다: " + key)
			offset += 1
		if definition["last_seen"]:
			if not _coordinate([packed[offset], packed[offset + 1]]):
				return _fail("리플레이 마지막 관측 좌표가 올바르지 않습니다.")
			offset += 2
		for _unused: Variant in definition["remaining"]:
			if not _number(packed[offset], 0.0, LIMIT_SECONDS):
				return _fail("리플레이 명령 남은 시간이 올바르지 않습니다.")
			offset += 1
		cursor += length
		count += 1
	if count > int(GROUP_LIMITS[group_index]) or (group_index == 0 and count == 0):
		return _fail("리플레이 개체 수가 허용 범위를 벗어났습니다.")
	return true

func _validate_number_field(key: String, value: Variant) -> bool:
	match key:
		"x": return _number(value, 0.0, float(_validation_bounds[0]))
		"z": return _number(value, 0.0, float(_validation_bounds[1]))
		"facing", "aim_facing", "move_facing", "peek_facing", "camera_facing", "body_facing": return _number(value, -TAU * 100.0, TAU * 100.0)
		"swing_sign", "hinge_side": return _number(value,-1.0,1.0) and absf(float(value)) == 1.0
		"turn_delta": return _number(value, -PI, PI)
		"progress", "animation_phase", "aim_progress", "mobility_multiplier", "awareness_confidence", "exposure", "opacity": return _number(value, 0.0, 1.0)
		"kick_resistance": return _number(value, 0.0, 1.0)
		# Derived availability keeps the existing replay resource range; valid
		# legacy inventories must not be hidden or truncated by a new HUD field.
		"available_shotgun_breaches", "available_breaches", "frags", "available_frags": return _integer(value, 0, 10000)
		"hp": return _number(value, 0.0, 10000.0)
		"ammo", "max_ammo", "reserve_ammo", "stuns", "smokes", "breaches", "charges", "cameras", "primary_ammo", "primary_reserve_ammo", "secondary_ammo", "secondary_reserve_ammo": return _integer(value, 0, 10000)
		"stunned", "cooldown", "reload_remaining", "reload_duration", "surrender_remaining", "suppressed", "suppression_remaining", "peek_remaining", "duration", "camera_remaining", "flash_recover_remaining": return _number(value, 0.0, LIMIT_SECONDS)
		"height", "base_height": return _number(value,0.0,64.0 if _validation_map_version >= 2 else 8.0)
		"weapon_height": return _number(value,0.0,8.0)
		"current_weapon_height", "weapon_origin_height": return _number(value,0.0,72.0 if _validation_map_version >= 2 else 8.0)
		"velocity_x", "velocity_z": return _number(value,-32.0,32.0)
		"weapon_origin_x": return _number(value,-1.0,float(_validation_bounds[0])+1.0)
		"weapon_origin_z": return _number(value,-1.0,float(_validation_bounds[1])+1.0)
		"weapon_length": return _number(value, 0.0, 3.0)
		"equipment_weight": return _number(value, 0.0, 100.0)
		"action_multiplier": return _number(value,1.0,4.0)
		"resistance", "penetration_resistance", "durability": return _number(value,0.0,1000.0)
		"sound_radius": return _number(value, 0.0, 32.0)
		"w", "d": return _number(value, 0.001, 512.0 if _validation_map_version >= 2 else 32.0)
		_: return _number(value, 0.0, 10000.0)

func _validate_meta(meta: Variant) -> bool:
	if not meta is Dictionary or not _exact_keys(meta, META_KEYS+(V2_META_KEYS if _validation_map_version >= 2 else []), []):
		return _fail("리플레이 임무 정보에 지원하지 않는 항목이 있습니다.")
	var ordinary: Dictionary = meta.duplicate(false)
	for key: String in DOCTRINE_KEYS + ROOM_STATE_KEYS + P5_META_KEYS + ROOM_DOCTRINE_KEYS: ordinary.erase(key)
	if ordinary.get("result") is Dictionary:
		ordinary["result"] = ordinary.result.duplicate(false)
		for key: String in DOCTRINE_KEYS + ROOM_STATE_KEYS + P5_RESULT_KEYS + ROOM_DOCTRINE_KEYS: ordinary.result.erase(key)
	if not _safe_small_tree(ordinary, 0):
		return _fail("리플레이 임무 정보가 올바르지 않습니다.")
	if not _validate_run_identity(meta):
		return false
	if not _validate_doctrine(meta): return _fail("리플레이 교범 계측이 올바르지 않습니다.")
	if not _validate_room_doctrine(meta): return false
	if not _validate_room_states(meta): return _fail("리플레이 방 상태가 올바르지 않습니다.")
	if not _validate_p5_statistics(meta): return false
	if meta.has("frag_projectiles") and not _validate_frag_projectiles(meta.frag_projectiles): return _fail("리플레이 파편탄 궤적 정보가 올바르지 않습니다.")
	if meta.has("result"):
		var result: Variant = meta["result"]
		if not result is Dictionary or not _exact_keys(result, RESULT_KEYS, []):
			return _fail("리플레이 작전 결과에 지원하지 않는 항목이 있습니다.")
		if not _validate_doctrine(result): return _fail("리플레이 결과 교범 계측이 올바르지 않습니다.")
		if not _validate_room_doctrine(result): return false
		if not _validate_room_states(result): return _fail("리플레이 결과 방 상태가 올바르지 않습니다.")
		if not result.is_empty() and not _validate_p5_statistics(result, true): return false
		for key: String in result:
			if key in DOCTRINE_KEYS + ROOM_STATE_KEYS + P5_RESULT_KEYS + ROOM_DOCTRINE_KEYS:
				continue
			elif key == "success":
				if not result[key] is bool:
					return _fail("리플레이 작전 성공 상태가 올바르지 않습니다.")
			elif key in ["time", "duration"]:
				if not _number(result[key], 0.0, LIMIT_SECONDS):
					return _fail("리플레이 작전 결과 시간이 올바르지 않습니다.")
			elif key == "first_alert_time":
				if not _number(result[key], -1.0, LIMIT_SECONDS):
					return _fail("리플레이 최초 경계 시간이 올바르지 않습니다.")
			elif key in ["seed", "variant", "modifiers"]:
				continue
			elif key == "stars":
				if not result[key] is Dictionary or result[key].size() > 16:
					return _fail("리플레이 별 과제 결과가 올바르지 않습니다.")
				for star: Variant in result[key]:
					if not _identifier(star) or not result[key][star] is bool:
						return _fail("리플레이 별 과제 결과가 올바르지 않습니다.")
			elif key in ["title", "reason", "rank", "status"]:
				if not _text(result[key], 256):
					return _fail("리플레이 작전 결과 설명이 올바르지 않습니다.")
			elif not _integer(result[key], 0, 10000000):
				return _fail("리플레이 작전 결과 수치가 올바르지 않습니다.")
		if result.has("status") and not result["status"] in ["SUCCESS", "FAILED"]:
			return _fail("리플레이 작전 결과 상태가 올바르지 않습니다.")
		if not _validate_run_identity(result):
			return false
	if meta.has("pause_requested") and not meta["pause_requested"] is bool:
		return _fail("리플레이 정지 상태가 올바르지 않습니다.")
	if meta.has("pause_reason") and meta.pause_reason not in ["", "command_failure", "man_down"]:
		return _fail("리플레이 정지 사유가 올바르지 않습니다.")
	if meta.has("pause_unit_id") and meta.pause_unit_id != "" and not _known_entity(meta.pause_unit_id, "units"):
		return _fail("리플레이 정지 대원 ID가 올바르지 않습니다.")
	if meta.get("pause_reason", "") == "man_down" and not _known_entity(meta.get("pause_unit_id"), "units"):
		return _fail("리플레이 정지 대원 ID가 올바르지 않습니다.")
	for key: String in STAT_KEYS:
		if meta.has(key) and not _integer(meta[key], 0, 10000000):
			return _fail("리플레이 작전 통계가 올바르지 않습니다.")
	if meta.has("first_alert_time") and not _number(meta["first_alert_time"], -1.0, LIMIT_SECONDS):
		return _fail("리플레이 최초 경계 시간이 올바르지 않습니다.")
	for key: String in ["win", "fail"]:
		if meta.has(key) and not _validate_rules(meta[key]):
			return false
	if meta.has("stars"):
		if not meta["stars"] is Array or meta["stars"].size() > 16:
			return _fail("리플레이 별 과제 정의가 올바르지 않습니다.")
		var ids: Dictionary = {}
		for star: Variant in meta["stars"]:
			if not star is Dictionary or not _identifier(star.get("id")) or ids.has(star["id"]):
				return _fail("리플레이 별 과제 ID가 올바르지 않습니다.")
			ids[star["id"]] = true
	for key: String in ["loadout", "roster"]:
		var correct_shape: bool = meta.get(key, {} if key == "loadout" else []) is Dictionary if key == "loadout" else meta.get(key, []) is Array
		if meta.has(key) and not correct_shape:
			return _fail("리플레이 대원 구성 정보가 올바르지 않습니다.")
	if meta.has("broken_glass"):
		if not meta.broken_glass is Array or meta.broken_glass.size() > 64: return _fail("리플레이 유리 파손 기록이 제한을 초과했습니다.")
		var glass_ids: Dictionary = {}
		for pane: Variant in meta.broken_glass:
			var fields := ["object_id", "object_kind", "x", "z", "broken_at"]
			if not pane is Dictionary or not _exact_keys(pane, fields, fields) or not _identifier(pane.object_id) or pane.object_kind not in ["wall", "prop", "door"] or not _coordinate([pane.x, pane.z]) or not _number(pane.broken_at, 0.0, LIMIT_SECONDS): return _fail("리플레이 유리 파손 정보가 올바르지 않습니다.")
			var pane_key := str(pane.object_kind) + ":" + str(pane.object_id)
			if glass_ids.has(pane_key): return _fail("리플레이 유리 파손 ID가 중복되었습니다.")
			glass_ids[pane_key] = true
	if meta.has("flash_projectiles") and not _validate_flash_projectiles(meta.flash_projectiles): return _fail("리플레이 섬광탄 궤적 정보가 올바르지 않습니다.")
	if meta.has("smoke_zones"):
		if not meta["smoke_zones"] is Array or meta["smoke_zones"].size() > 16:
			return _fail("리플레이 연막 정보가 올바르지 않습니다.")
		for zone: Variant in meta["smoke_zones"]:
			if not zone is Dictionary or not _exact_keys(zone, ["x", "z", "radius", "remaining"], ["x", "z", "radius", "remaining"]):
				return _fail("리플레이 연막 구조가 올바르지 않습니다.")
			if not _coordinate([zone["x"], zone["z"]]) or not _number(zone["radius"], 0.0, 32.0) or not _number(zone["remaining"], 0.0, LIMIT_SECONDS):
				return _fail("리플레이 연막 수치가 올바르지 않습니다.")
	if meta.has("sound_zones"):
		if not meta["sound_zones"] is Array or meta["sound_zones"].size() > 12:
			return _fail("리플레이 소리 관측 정보가 올바르지 않습니다.")
		for zone: Variant in meta["sound_zones"]:
			if not zone is Dictionary or not _exact_keys(zone, ["x", "z", "radius", "time", "label"], ["x", "z", "radius", "time", "label"]):
				return _fail("리플레이 소리 관측 구조가 올바르지 않습니다.")
			if not _coordinate([zone["x"], zone["z"]]) or not _number(zone["radius"], 0.0, 32.0) or not _number(zone["time"], 0.0, LIMIT_SECONDS) or not _text(zone["label"], 128):
				return _fail("리플레이 소리 관측 수치가 올바르지 않습니다.")
	if meta.has("objectives"):
		var objectives: Variant = meta["objectives"]
		var objective_fields: Array = ["neutralized", "total", "rescued", "civilians_total", "complete"] + (["targets_completed","targets_total"] if _validation_map_version >= 2 else [])
		if not objectives is Dictionary or not _exact_keys(objectives, objective_fields, []):
			return _fail("리플레이 목표 정보가 올바르지 않습니다.")
		for key: String in objectives:
			if key == "complete":
				if not objectives[key] is bool:
					return _fail("리플레이 목표 완료 상태가 올바르지 않습니다.")
			elif not _integer(objectives[key], 0, 128):
				return _fail("리플레이 목표 수치가 올바르지 않습니다.")
	if meta.has("interactive_targets") and not _validate_targets(meta.interactive_targets): return false
	return true

func _candidate_uses_p5(candidate: Dictionary) -> bool:
	if _validation_map_version >= 6: return true
	for command: Variant in candidate.commands:
		if command is Dictionary and command.get("type") == "THROW_FRAG": return true
	for event: Variant in candidate.events:
		if event is Dictionary and event.get("type") in ["FRAG_RELEASE", "FRAG"]: return true
	for definition: Variant in candidate.states:
		if definition is Dictionary and definition.get("fields") is Array:
			for key: String in ["frags", "available_frags"]:
				if definition.fields.has(key): return true
	for meta: Variant in candidate.metadata:
		if not meta is Dictionary: continue
		for key: String in ["roe", "frag_projectiles"] + P5_STAT_KEYS:
			if meta.has(key): return true
		if meta.get("result") is Dictionary:
			for key: String in P5_STAT_KEYS:
				if meta.result.has(key): return true
	return false

func _validate_p5_statistics(value: Dictionary, terminal: bool = false) -> bool:
	if value.has("roe") and value.roe not in ["precision", "high_intensity"]: return _fail("리플레이 교전수칙이 올바르지 않습니다.")
	if _validation_p5_record and not value.has("stats_observed"):
		return _fail("리플레이 파편탄 관측 통계가 누락되었습니다.")
	if value.has("stats_observed"):
		var observed: Variant = value.stats_observed
		if not observed is Dictionary or not _exact_keys(observed, OBSERVED_STAT_KEYS, OBSERVED_STAT_KEYS):
			return _fail("리플레이 관측 통계 구조가 올바르지 않습니다.")
		for key: String in OBSERVED_STAT_KEYS:
			if key == "civilian_damage":
				if not _number(observed[key], 0.0, 10000000.0): return _fail("리플레이 관측 피해 수치가 올바르지 않습니다.")
			elif not _integer(observed[key], 0, 100 if key == "score" else 10000000):
				return _fail("리플레이 관측 통계 수치가 올바르지 않습니다.")
	for key: String in P5_STAT_KEYS:
		if not value.has(key): continue
		if (key.ends_with("_damage") and not _number(value[key], 0.0, 10000000.0)) or (not key.ends_with("_damage") and not _integer(value[key], 0, 10000000)):
			return _fail("리플레이 파편탄 피해 통계가 올바르지 않습니다.")
	if terminal and (_validation_p5_record or value.has("stars_observed")):
		for key: String in ["stars", "stars_observed"]:
			var stars: Variant = value.get(key)
			if not stars is Dictionary or stars.size() != _valid_star_ids.size(): return _fail("리플레이 관측 별 과제 결과가 올바르지 않습니다.")
			for id: Variant in stars:
				if not _valid_star_ids.has(id) or not stars[id] is bool or ((value.get("success") == false or value.get("status") == "FAILED") and stars[id]):
					return _fail("리플레이 관측 별 과제 결과가 올바르지 않습니다.")
	return true

func _validate_frag_clock(meta: Dictionary, clock: float) -> bool:
	for projectile: Dictionary in meta.get("frag_projectiles", []):
		if float(projectile.released_at) > clock + 0.000001 or float(projectile.detonate_at) <= clock: return false
		var phase := "FLIGHT" if clock < float(projectile.released_at) + float(projectile.flight_duration) else "FUSE"
		if projectile.phase != phase: return false
	return true

func _validate_room_states(value: Dictionary) -> bool:
	# This dedicated bound deliberately does not relax _safe_small_tree's
	# ordinary 32-key dictionary limit. Missions can contain 64 room rows.
	var fields := ["state", "changed_tick", "changed_at", "observed"]
	for key: String in ROOM_STATE_KEYS:
		if not value.has(key): continue
		var rooms: Variant = value[key]
		if not rooms is Dictionary or rooms.size() > 64: return false
		for room_id: Variant in rooms:
			var row: Variant = rooms[room_id]
			if not _identifier(room_id) or not _valid_room_ids.has(room_id) or not row is Dictionary or not _exact_keys(row, fields + ["door_id"], fields): return false
			if row.state not in ROOM_STATES or not _integer(row.changed_tick, 0, 36000000) or not _number(row.changed_at, 0.0, LIMIT_SECONDS) or not row.observed is bool: return false
			# Memory rows are produced only by owned observation evidence. A
			# hidden authority transition may be unobserved, but cannot be copied
			# into memory by a malformed record to manufacture a public marker.
			if key == "room_states_observed" and row.state != "UNKNOWN" and not row.observed: return false
			if row.has("door_id") and (row.state != "MARKED" or not _known_door(row.door_id)): return false
	return true

func _room_transition_clock(value: Dictionary) -> Array:
	var max_tick := 0
	var max_time := 0.0
	var values: Array = [value]
	if value.get("result") is Dictionary: values.append(value.result)
	for entry: Dictionary in values:
		for key: String in ROOM_STATE_KEYS:
			for row: Dictionary in entry.get(key, {}).values():
				max_tick = maxi(max_tick, int(row.changed_tick))
				max_time = maxf(max_time, float(row.changed_at))
	return [max_tick, max_time]

func _validate_room_doctrine(value: Dictionary) -> bool:
	if not value.has("room_doctrine"): return true
	var rooms: Variant = value.room_doctrine
	if not rooms is Dictionary or rooms.size() > 64:
		return _fail("리플레이 방 교범 구조가 올바르지 않습니다.")
	for room_id: Variant in rooms:
		if not _identifier(room_id) or not _valid_room_ids.has(room_id):
			return _fail("리플레이 방 교범의 공개 참조가 올바르지 않습니다.")
		var metrics: Variant = rooms[room_id]
		if not metrics is Dictionary or not _exact_keys(metrics, ROOM_DOCTRINE_METRICS, ROOM_DOCTRINE_METRICS):
			return _fail("리플레이 방 교범 구조가 올바르지 않습니다.")
		for metric: String in ROOM_DOCTRINE_METRICS:
			var row: Variant = metrics[metric]
			var extra_keys: Array = ["civilian_damage", "unlawful_shots"] if metric == "identification" else (["arrested", "surrendered", "secured", "civilians"] if metric == "control" else [])
			if not row is Dictionary or not _exact_keys(row, ["value", "tick", "time", "unit_id", "door_id"] + extra_keys, ["value", "tick", "time"]):
				return _fail("리플레이 방 교범 구조가 올바르지 않습니다.")
			if row.value != null and not _number(row.value, 0.0, 10000000.0):
				return _fail("리플레이 방 교범 수치가 올바르지 않습니다.")
			for key: String in extra_keys:
				if row.has(key) and (not _number(row[key], 0.0, 10000000.0) if key == "civilian_damage" else not _integer(row[key], 0, 10000000)):
					return _fail("리플레이 방 교범 수치가 올바르지 않습니다.")
			if row.has("unit_id") and not _known_entity(row.unit_id, "units"):
				return _fail("리플레이 방 교범의 공개 참조가 올바르지 않습니다.")
			if row.has("door_id") and not _known_door(row.door_id):
				return _fail("리플레이 방 교범의 공개 참조가 올바르지 않습니다.")
			if (row.tick == null) != (row.time == null) or (row.value == null and row.tick != null):
				return _fail("리플레이 방 교범 증거 시각이 올바르지 않습니다.")
			if row.tick != null and (not _integer(row.tick, 0, int(LIMIT_SECONDS * 30.0)) or not _number(row.time, 0.0, LIMIT_SECONDS) or absf(float(row.time) - float(row.tick) / 30.0) > 0.000001):
				return _fail("리플레이 방 교범 증거 시각이 올바르지 않습니다.")
	return true

func _room_doctrine_clock(value: Dictionary) -> Array:
	var max_tick := 0
	var max_time := 0.0
	var entries: Array = [value]
	if value.get("result") is Dictionary: entries.append(value.result)
	for entry: Dictionary in entries:
		for metrics: Dictionary in entry.get("room_doctrine", {}).values():
			for row: Dictionary in metrics.values():
				if row.tick != null:
					max_tick = maxi(max_tick, int(row.tick))
					max_time = maxf(max_time, float(row.time))
	return [max_tick, max_time]

func _validate_doctrine(value: Dictionary) -> bool:
	for key: String in ["threat_order_violations", "rear_hits"]:
		if value.has(key) and not _integer(value[key], 0, 10000000): return false
	if value.has("doorway_dwell"):
		if not value.doorway_dwell is Dictionary or value.doorway_dwell.size() > 4: return false
		for id: Variant in value.doorway_dwell:
			if not _known_entity(id, "units") or not _number(value.doorway_dwell[id], 0, LIMIT_SECONDS * 64): return false
	if value.has("time_to_dominate"):
		if not value.time_to_dominate is Dictionary or value.time_to_dominate.size() > 64: return false
		for id: Variant in value.time_to_dominate:
			var entry: Variant = value.time_to_dominate[id]
			if not _known_door(id) or not entry is Dictionary or not _exact_keys(entry, ["room_id", "opened_at", "participants", "arrived", "seconds", "observed", "targets"], ["room_id", "opened_at", "participants", "arrived", "seconds"]): return false
			if entry.has("observed") and not entry.observed is bool: return false
			if not entry.room_id is String or not _valid_room_ids.has(entry.room_id) or not _number(entry.opened_at, 0, LIMIT_SECONDS) or not _number(entry.seconds, -1, LIMIT_SECONDS): return false
			for field: String in ["participants", "arrived"]:
				if not entry[field] is Array or entry[field].size() > 4: return false
				var seen: Array = []
				for unit_id: Variant in entry[field]:
					if not _known_entity(unit_id, "units") or seen.has(unit_id): return false
					seen.append(unit_id)
			for unit_id: Variant in entry.arrived:
				if not entry.participants.has(unit_id): return false
			if entry.has("targets"):
				if not entry.targets is Dictionary or entry.targets.size() != entry.participants.size(): return false
				for unit_id: Variant in entry.targets:
					if not entry.participants.has(unit_id) or not _known_entity(unit_id, "units") or not _coordinate(entry.targets[unit_id]): return false
	if value.has("enemy_first_shot"):
		if not value.enemy_first_shot is Array or value.enemy_first_shot.size() > 2000: return false
		for shot: Variant in value.enemy_first_shot:
			if not shot is Dictionary or not _exact_keys(shot, ["room_id", "time", "tick", "enemy_first"], ["room_id", "time", "tick", "enemy_first"]): return false
			if not shot.room_id is String or (shot.room_id != "" and not _valid_room_ids.has(shot.room_id)) or not _number(shot.time, 0, LIMIT_SECONDS) or not _integer(shot.tick, 0, 10000000) or not shot.enemy_first is bool: return false
	return true

func _validate_targets(value: Variant) -> bool:
	if not value is Array or value.size() > 64 or value.size() != _valid_target_definitions.size(): return _fail("리플레이 상호작용 목표 배열이 올바르지 않습니다.")
	var seen: Dictionary = {}
	for target: Variant in value:
		if not target is Dictionary or not _exact_keys(target,["id","x","z","w","d","label","action","duration","progress","completed"],["id","x","z","w","d","label","action","duration","progress","completed"]):
			return _fail("리플레이 상호작용 목표 구조가 올바르지 않습니다.")
		if not _identifier(target.id) or not _valid_target_definitions.has(target.id) or seen.has(target.id): return _fail("리플레이 상호작용 목표 ID가 올바르지 않습니다.")
		seen[target.id] = true
		var authored: Dictionary = _valid_target_definitions[target.id]
		for key: String in authored:
			if target.get(key) != authored[key]: return _fail("리플레이 상호작용 목표가 설치된 지도와 일치하지 않습니다.")
		if not _number(target.progress,0.0,float(authored.duration)) or not target.completed is bool: return _fail("리플레이 목표 진행 수치가 올바르지 않습니다.")
		if target.completed and not is_equal_approx(float(target.progress),float(authored.duration)): return _fail("리플레이 완료된 목표의 작업 시간이 올바르지 않습니다.")
	return true

func _validate_run_identity(value: Dictionary) -> bool:
	if value.has("environment"):
		var environment: Variant = value.environment
		var environment_fields: Array = ["time_of_day","lighting"] + (["biome","ground_color","water","ground_surface","water_level"] if _validation_map_version >= 2 else [])
		if not environment is Dictionary or not _exact_keys(environment,environment_fields,[]): return _fail("리플레이 조명 환경이 올바르지 않습니다.")
		if environment.has("time_of_day") and environment.time_of_day not in ["day","dim","night"]: return _fail("리플레이 시간대가 올바르지 않습니다.")
		if environment.has("lighting") and not _number(environment.lighting,0,1): return _fail("리플레이 조명 수치가 올바르지 않습니다.")
		if environment.has("biome") and not _text(environment.biome,64): return _fail("리플레이 지형 환경이 올바르지 않습니다.")
		if environment.has("ground_surface") and environment.ground_surface not in ["concrete","tile","wood","carpet","gravel"]+(["ship_deck"] if _validation_map_version >= 2 else []): return _fail("리플레이 바닥 재질이 올바르지 않습니다.")
		if environment.has("water") and not environment.water is bool: return _fail("리플레이 수면 환경이 올바르지 않습니다.")
		if environment.has("water_level") and not _number(environment.water_level,-16,0): return _fail("리플레이 수면 높이가 올바르지 않습니다.")
		if environment.has("ground_color"):
			var color_regex := RegEx.new()
			color_regex.compile("^#[0-9A-Fa-f]{6}$")
			if not environment.ground_color is String or color_regex.search(environment.ground_color) == null: return _fail("리플레이 바닥 색상이 올바르지 않습니다.")
	if value.has("seed") and not _integer(value["seed"], 0, MAX_SAFE_SEED):
		return _fail("리플레이 시드가 올바르지 않습니다.")
	if value.has("variant") and not _identifier(value["variant"]):
		return _fail("리플레이 임무 변형이 올바르지 않습니다.")
	if value.has("modifiers"):
		if not value["modifiers"] is Array or value["modifiers"].size() > MODIFIERS.size():
			return _fail("리플레이 변형 규칙이 올바르지 않습니다.")
		var seen: Dictionary = {}
		for modifier: Variant in value["modifiers"]:
			if not modifier is String or not modifier in MODIFIERS or seen.has(modifier):
				return _fail("리플레이 변형 규칙을 지원하지 않습니다.")
			seen[modifier] = true
	return true

func _validate_rules(rules: Variant) -> bool:
	if not rules is Array or rules.size() > 16:
		return _fail("리플레이 승패 규칙이 올바르지 않습니다.")
	for rule: Variant in rules:
		if not rule is Dictionary or not _exact_keys(rule, ["type", "zone", "seconds", "unit_id", "civilian_id"]+(["targets"] if _validation_map_version >= 2 else [])+(["room_ids"] if _validation_map_version >= 4 else []), ["type"]):
			return _fail("리플레이 승패 규칙 구조가 올바르지 않습니다.")
		if not rule["type"] in ["neutralize_all", "secure_all_civilians", "reach_zone", "before_alert", "time_limit", "escort_to_zone", "no_civilian_loss"]+(["targets_complete","no_shots"] if _validation_map_version >= 2 else [])+(["rooms_cleared"] if _validation_map_version >= 4 else []):
			return _fail("리플레이 승패 규칙을 지원하지 않습니다.")
		if rule.type == "rooms_cleared":
			if not _exact_keys(rule, ["type", "room_ids"], ["type"]) or _valid_room_ids.is_empty(): return _fail("리플레이 방 정리 규칙이 올바르지 않습니다.")
			if rule.has("room_ids"):
				if not rule.room_ids is Array or rule.room_ids.is_empty() or rule.room_ids.size() > 64: return _fail("리플레이 방 정리 규칙이 올바르지 않습니다.")
				var seen_rooms: Dictionary = {}
				for room_id: Variant in rule.room_ids:
					if not _identifier(room_id) or not _valid_room_ids.has(room_id) or seen_rooms.has(room_id): return _fail("리플레이 방 정리 규칙이 올바르지 않습니다.")
					seen_rooms[room_id] = true
		elif rule.has("room_ids"):
			return _fail("리플레이 방 정리 규칙이 올바르지 않습니다.")
		if rule["type"] == "time_limit" and not _number(rule.get("seconds"), 0.001, 3600.0):
			return _fail("리플레이 제한 시간이 올바르지 않습니다.")
		if rule["type"] in ["reach_zone", "escort_to_zone"]:
			var zone: Variant = rule.get("zone")
			if not zone is Array or zone.size() != 4 or not _coordinate([zone[0], zone[1]]) or not _number(zone[2], 0.001, float(_validation_bounds[0])) or not _number(zone[3], 0.001, float(_validation_bounds[1])):
				return _fail("리플레이 목표 구역이 올바르지 않습니다.")
		if rule.has("unit_id") and not _known_entity(rule["unit_id"], "units"):
			return _fail("리플레이 목표 대원 ID가 올바르지 않습니다.")
		if rule.has("civilian_id") and not _known_entity(rule["civilian_id"], "civilians"):
			return _fail("리플레이 목표 민간인 ID가 올바르지 않습니다.")
		if rule.type == "targets_complete":
			if not rule.get("targets") is Array or rule.targets.is_empty() or rule.targets.size() > 64: return _fail("리플레이 상호작용 목표 규칙이 올바르지 않습니다.")
			var seen: Dictionary = {}
			for id: Variant in rule.targets:
				if not _identifier(id) or not _valid_target_definitions.has(id) or seen.has(id): return _fail("리플레이 상호작용 목표 참조가 올바르지 않습니다.")
				seen[id] = true
	return true

func _validate_event(event: Variant, record_duration: float) -> bool:
	if not event is Dictionary or not _exact_keys(event, EVENT_KEYS, ["tick", "time"]):
		return _fail("리플레이 사건 구조가 올바르지 않습니다.")
	if not _integer(event.get("seq", event.get("sequence", null)), 0, 100000000) or not _integer(event["tick"], 0, 36000000) or not _number(event["time"], 0.0, record_duration):
		return _fail("리플레이 사건 시간 또는 순번이 올바르지 않습니다.")
	if not event.get("type", "") in EVENT_TYPES+(V2_EVENT_TYPES if _validation_map_version >= 2 else []):
		return _fail("리플레이 사건 종류가 올바르지 않습니다.")
	var is_call: bool = event.get("type") in CALL_EVENT_TYPES
	var provenance_count := 0
	for key: String in SIGNAL_PROVENANCE_KEYS:
		if event.has(key): provenance_count += 1
	if provenance_count > 0:
		if provenance_count != SIGNAL_PROVENANCE_KEYS.size() or (not is_call and event.get("type") != "SIGNAL"): return _fail("리플레이 신호 전달 정보가 완전하지 않습니다.")
		if event.signal_mode not in ["verbal", "hand_signals"] or not _number(event.signal_radius, 0.0, 6.0) or float(event.signal_radius) != (6.0 if event.signal_mode == "verbal" else 0.0): return _fail("리플레이 신호 방식 또는 소리 범위가 올바르지 않습니다.")
		if not _known_entity(event.source_unit_id, "units"): return _fail("리플레이 신호 발신 대원 ID가 올바르지 않습니다.")
		if not event.receiver_unit_ids is Array or event.receiver_unit_ids.size() > 4: return _fail("리플레이 신호 수신 대원 목록이 올바르지 않습니다.")
		var previous_id := ""
		for receiver: Variant in event.receiver_unit_ids:
			if not _known_entity(receiver, "units") or (not previous_id.is_empty() and str(receiver) <= previous_id): return _fail("리플레이 신호 수신 대원 목록이 올바르지 않습니다.")
			previous_id = str(receiver)
	if is_call:
		if not _known_entity(event.get("unit_id"), "units") or not event.get("observed") is bool: return _fail("리플레이 팀 신호의 대원 또는 관측 상태가 올바르지 않습니다.")
		if event.has("cover_unit_id") and not _known_entity(event.cover_unit_id, "units"): return _fail("리플레이 팀 신호의 엄호 대원 ID가 올바르지 않습니다.")
		if event.has("room_id") and (not _identifier(event.room_id) or not _valid_room_ids.has(event.room_id)): return _fail("리플레이 팀 신호의 방 ID가 올바르지 않습니다.")
	elif event.has("room_id") or event.has("cover_unit_id") or (event.has("observed") and event.get("type") not in ["FRAG_RELEASE", "FRAG"]):
		return _fail("리플레이 팀 신호 정보의 사건 종류가 올바르지 않습니다.")
	if event.get("type") in ["KICK_FAILED", "BREACH_RETREAT"]:
		var kinds: Array = ["KICK_DOOR"] if event.type == "KICK_FAILED" else ["KICK_DOOR", "BREACH_DOOR", "SHOTGUN_BREACH"]
		if not _known_door(event.get("door_id")) or not _known_entity(event.get("unit_id"), "units") or event.get("kind") not in kinds: return _fail("리플레이 문 처리 사건의 문·대원·방법이 올바르지 않습니다.")
	if event.get("type") == "TARGET_COMPLETE" and (not _identifier(event.get("target_id")) or not _valid_target_definitions.has(event.target_id) or not _known_entity(event.get("unit_id"),"units")):
		return _fail("리플레이 목표 완료 사건의 목표 또는 대원 ID가 올바르지 않습니다.")
	if event.has("sync_id") and (event.get("type") != "SIGNAL" or not _identifier(event.sync_id)): return _fail("리플레이 신호 사건의 동기화 ID가 올바르지 않습니다.")
	if event.has("auto_signal") and (event.get("type") != "SIGNAL" or not event.auto_signal is bool or (event.auto_signal and not event.has("sync_id"))): return _fail("리플레이 신호 사건의 자동 상태가 올바르지 않습니다.")
	if event.has("command_id") and not _identifier(event["command_id"]):
		return _fail("리플레이 사건 명령 ID가 올바르지 않습니다.")
	for key: String in ["hostile", "hit", "unlawful"]:
		if event.has(key) and not event[key] is bool:
			return _fail("리플레이 사건 결과 상태가 올바르지 않습니다.")
	if event.has("radius") and not _number(event["radius"], 0.0, 32.0):
		return _fail("리플레이 사건 범위가 올바르지 않습니다.")
	if event.has("duration") and not _number(event["duration"], 0.0, LIMIT_SECONDS):
		return _fail("리플레이 사건 지속 시간이 올바르지 않습니다.")
	if event.has("object_id") and not _identifier(event.object_id): return _fail("리플레이 파손 대상 ID가 올바르지 않습니다.")
	if event.has("object_kind") and event.object_kind not in ["wall", "prop", "door"]: return _fail("리플레이 파손 대상 종류가 올바르지 않습니다.")
	if event.has("projectile_id") and not _identifier(event.projectile_id): return _fail("리플레이 사건 투척물 ID가 올바르지 않습니다.")
	if event.get("type") in ["FRAG_RELEASE", "FRAG"] and not _validate_frag_event(event): return _fail("리플레이 파편탄 사건의 공개 정보가 올바르지 않습니다.")
	for key: String in ["flight_duration", "detonate_at"]:
		if event.has(key) and not _number(event[key], 0.0, LIMIT_SECONDS + (MAX_FRAG_FUSE if event.get("type") == "FRAG_RELEASE" and key == "detonate_at" else 0.0)): return _fail("리플레이 투척 시각이 올바르지 않습니다.")
	if event.has("source_height") and not _number(event.source_height, 0.0, 72.0 if _validation_map_version >= 2 else 8.0): return _fail("리플레이 투척 높이가 올바르지 않습니다.")
	if event.has("hit_part") and event.hit_part not in ["head", "torso", "limb"]: return _fail("리플레이 피격 부위가 올바르지 않습니다.")
	if event.has("hit_direction") and event.hit_direction not in ["front", "side", "back"]: return _fail("리플레이 피격 방향이 올바르지 않습니다.")
	if event.has("protection") and event.protection not in ["blocked", "penetrated", "unprotected"]: return _fail("리플레이 방호 결과가 올바르지 않습니다.")
	if event.has("armor_id") and event.armor_id != "none" and EquipmentCatalog.definition(str(event.armor_id)).is_empty(): return _fail("리플레이 방호 장비 ID가 올바르지 않습니다.")
	if event.has("panel") and not _text(event.panel, 64): return _fail("리플레이 방호 패널이 올바르지 않습니다.")
	if event.has("damage_multiplier") and not _number(event.damage_multiplier, 0.0, 1.0): return _fail("리플레이 방호 피해 배율이 올바르지 않습니다.")
	if event.has("damage") and not _number(event.damage, 0.0, 10000.0): return _fail("리플레이 피격 피해가 올바르지 않습니다.")
	if event.has("slot") and event.slot not in ["primary", "secondary"]: return _fail("리플레이 무기 슬롯이 올바르지 않습니다.")
	if event.has("weapon") and event.weapon not in ["standard", "light", "shotgun", "suppressed", "pico_p1"]: return _fail("리플레이 무기 사건이 올바르지 않습니다.")
	if event.has("weapon_origin"):
		var origin: Variant = event.weapon_origin
		if not origin is Array or origin.size() != 3 or not _number(origin[0],-1.0,float(_validation_bounds[0])+1.0) or not _number(origin[1],-1.0,float(_validation_bounds[1])+1.0) or not _number(origin[2],0.0,72.0 if _validation_map_version >= 2 else 8.0): return _fail("리플레이 사격 원점이 올바르지 않습니다.")
	if event.has("target_height") and not _number(event.target_height,0.0,72.0 if _validation_map_version >= 2 else 8.0): return _fail("리플레이 사격 대상 높이가 올바르지 않습니다.")
	if event.has("transmission") and not _number(event.transmission,0.0,1.0): return _fail("리플레이 차폐 통과율이 올바르지 않습니다.")
	for key: String in ["method", "enemy_type"]:
		if event.has(key) and not _identifier(event[key]):
			return _fail("리플레이 사건 행동 종류가 올바르지 않습니다.")
	if event.has("channel") and not event["channel"] in ["A", "B", "C"]:
		return _fail("리플레이 사건 신호가 올바르지 않습니다.")
	if event.has("released") and not _integer(event["released"], 0, 4):
		return _fail("리플레이 사건 대원 수가 올바르지 않습니다.")
	if event.has("kind") and not (event["kind"] in ["unit", "enemy", "civilian"] or (event.get("type") in ["DOOR_ACTION", "KICK_FAILED", "BREACH_RETREAT"] and event["kind"] in COMMAND_TYPES)):
		return _fail("리플레이 사건 개체 종류가 올바르지 않습니다.")
	if event.has("message") and not _text(event["message"], 512):
		return _fail("리플레이 사건 설명이 올바르지 않습니다.")
	for key: String in event:
		if key in ["from", "to", "position", "requested", "resolved"] and not _coordinate(event[key]):
			return _fail("리플레이 사건 좌표가 올바르지 않습니다.")
		var target_event: bool = key == "target_id" and event.get("type") == "TARGET_COMPLETE" and _identifier(event[key]) and _valid_target_definitions.has(event[key])
		if key in ["entity_id", "target_id", "unit_id", "enemy_id", "door_id", "civilian_id", "attacker_id"] and not (_known_entity(event[key], "") or _known_door(event[key]) or target_event):
			return _fail("리플레이 사건 개체 ID가 올바르지 않습니다.")
	if not _safe_small_tree(event, 0):
		return _fail("리플레이 사건 내용이 올바르지 않습니다.")
	return true

func _validate_frag_event(event: Dictionary) -> bool:
	var fields := ["seq", "tick", "time", "type", "from", "to", "projectile_id", "unit_id", "radius", "target_height", "observed"]
	if event.type == "FRAG_RELEASE": fields += ["source_height", "flight_duration", "detonate_at"]
	if not _exact_keys(event, fields + ["message"], fields) or event.observed != true or not event.observed is bool or not _known_entity(event.unit_id, "units"): return false
	if not _coordinate(event.from) or not _coordinate(event.to): return false
	if event.type == "FRAG_RELEASE" and (not _number(event.flight_duration, 0.0, MAX_FRAG_FUSE) or not _number(event.detonate_at, float(event.time) + float(event.flight_duration), float(event.time) + MAX_FRAG_FUSE)): return false
	return true

static func sample_frag_projectiles(projectiles: Array, clock: float) -> Array:
	# FRAG follows the established own-throw arc, with an independently owned
	# list. The FLASH data, sampler, phase clocks and event names stay intact.
	return sample_flash_projectiles(projectiles, clock)

func _validate_frag_projectiles(value: Variant) -> bool:
	if not value is Array or value.size() > 16: return false
	var ids: Dictionary = {}
	var fields := ["id", "unit_id", "command_id", "source", "target", "position", "released_at", "flight_duration", "detonate_at", "phase"]
	for projectile: Variant in value:
		if not projectile is Dictionary or not _exact_keys(projectile, fields, fields): return false
		if not _identifier(projectile.id) or ids.has(projectile.id) or not _known_entity(projectile.unit_id, "units") or not _identifier(projectile.command_id): return false
		ids[projectile.id] = true
		for key: String in ["source", "target", "position"]:
			var point: Variant = projectile[key]
			if not point is Array or point.size() != 3 or not _number(point[0], -1.0, float(_validation_bounds[0]) + 1.0) or not _number(point[1], -1.0, float(_validation_bounds[1]) + 1.0) or not _number(point[2], 0.0, 72.0 if _validation_map_version >= 2 else 8.0): return false
		if not _number(projectile.released_at, 0.0, LIMIT_SECONDS) or not _number(projectile.flight_duration, 0.0, MAX_FRAG_FUSE) or not _number(projectile.detonate_at, float(projectile.released_at) + float(projectile.flight_duration), minf(LIMIT_SECONDS + MAX_FRAG_FUSE, float(projectile.released_at) + MAX_FRAG_FUSE)): return false
		if projectile.phase not in ["FLIGHT", "FUSE"]: return false
	return true

static func sample_flash_projectiles(projectiles: Array, clock: float) -> Array:
	var sampled: Array = []
	for projectile: Dictionary in projectiles:
		if clock < float(projectile.get("released_at", 0.0)) or clock >= float(projectile.get("detonate_at", 0.0)): continue
		var item := projectile.duplicate(true)
		var source: Array = item.get("source", [])
		var target: Array = item.get("target", [])
		if source.size() != 3 or target.size() != 3: continue
		var age := clock - float(item.released_at)
		var duration := maxf(float(item.flight_duration), 0.000001)
		var weight := clampf(age / duration, 0.0, 1.0)
		var height := lerpf(float(source[2]), float(target[2]), weight)
		var distance := Vector2(float(source[0]), float(source[1])).distance_to(Vector2(float(target[0]), float(target[1])))
		height += sin(weight * PI) * minf(1.4, 0.6 + distance * 0.08)
		item["position"] = [lerpf(float(source[0]), float(target[0]), weight), lerpf(float(source[1]), float(target[1]), weight), height]
		item["phase"] = "FLIGHT" if age < duration else "FUSE"
		sampled.append(item)
	return sampled

func _validate_flash_projectiles(value: Variant) -> bool:
	if not value is Array or value.size() > 16: return false
	var ids: Dictionary = {}
	var required := ["id", "unit_id", "command_id", "source", "target", "position", "released_at", "flight_duration", "detonate_at", "phase"]
	for projectile: Variant in value:
		if not projectile is Dictionary or not _exact_keys(projectile, required + ["door_id"], required): return false
		if not _identifier(projectile.id) or ids.has(projectile.id) or not _known_entity(projectile.unit_id, "units") or not _identifier(projectile.command_id): return false
		ids[projectile.id] = true
		if projectile.has("door_id") and not _known_door(projectile.door_id): return false
		for point_key: String in ["source", "target", "position"]:
			var point: Variant = projectile[point_key]
			if not point is Array or point.size() != 3 or not _number(point[0], -1.0, float(_validation_bounds[0]) + 1.0) or not _number(point[1], -1.0, float(_validation_bounds[1]) + 1.0) or not _number(point[2], 0.0, 72.0 if _validation_map_version >= 2 else 8.0): return false
		if not _number(projectile.released_at, 0.0, LIMIT_SECONDS) or not _number(projectile.flight_duration, 0.0, 10.0) or not _number(projectile.detonate_at, float(projectile.released_at) + float(projectile.flight_duration), LIMIT_SECONDS): return false
		if projectile.phase not in ["FLIGHT", "FUSE"]: return false
	return true

func _validate_camera_observations(value: Variant) -> bool:
	if not value is Array or value.size() > 64: return false
	var ids: Dictionary = {}
	var required := ["id", "kind", "name", "x", "z", "facing", "hp", "status", "observed_at"]
	for observation: Variant in value:
		if not observation is Dictionary or not _exact_keys(observation, required, required): return false
		if observation.kind not in ["enemy", "civilian"] or not _known_entity(observation.id, "enemies" if observation.kind == "enemy" else "civilians") or ids.has(observation.id): return false
		ids[observation.id] = true
		if not _text(observation.name, 128) or not _coordinate([observation.x, observation.z]) or not _number(observation.facing, -TAU * 100.0, TAU * 100.0) or not _number(observation.hp, 0.0, 10000.0) or observation.status not in ENTITY_STATUSES or not _number(observation.observed_at, 0.0, LIMIT_SECONDS): return false
	return true

func _safe_small_tree(value: Variant, depth: int) -> bool:
	if depth > 5:
		return false
	if value == null or value is bool:
		return true
	if _is_number(value):
		return _number(value, -float(MAX_SAFE_SEED), float(MAX_SAFE_SEED))
	if value is String:
		return _text(value, 512)
	if value is Array:
		if value.size() > 64:
			return false
		for item: Variant in value:
			if not _safe_small_tree(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > 32:
			return false
		for key: Variant in value:
			if not key is String or key.length() > 64 or key in ["__proto__", "prototype", "constructor", "script", "url", "resource", "path"] or not _safe_small_tree(value[key], depth + 1):
				return false
		return true
	return false

func _known_entity(value: Variant, group: String) -> bool:
	if not _identifier(value):
		return false
	return _valid_entity_ids.has(value) and (group.is_empty() or _valid_entity_ids[value] == group)

func _known_door(value: Variant) -> bool:
	if not _identifier(value):
		return false
	return _valid_door_ids.has(value)

func _identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64:
		return false
	for i in value.length():
		var c: int = value.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c in [45, 46, 58, 95]):
			return false
	return true

func _text(value: Variant, maximum: int) -> bool:
	return value is String and value.length() <= maximum

func _coordinate(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0], 0.0, float(_validation_bounds[0])) and _number(value[1], 0.0, float(_validation_bounds[1]))

func _point(value: Variant, minimum: float, maximum: float) -> bool:
	return value is Array and value.size() == 2 and _number(value[0], minimum, maximum) and _number(value[1], minimum, maximum)

func _is_number(value: Variant) -> bool:
	return value is int or value is float

func _number(value: Variant, minimum: float, maximum: float) -> bool:
	# Fixed-step recording may end a fraction above 600 due to float accumulation.
	# Match capture() at that boundary while retaining strict limits elsewhere.
	return _is_number(value) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum + (0.000001 if maximum == LIMIT_SECONDS else 0.0)

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, float(minimum), float(maximum)) and float(value) == floorf(float(value))

func _exact_keys(value: Dictionary, allowed: Array, required: Array) -> bool:
	for key: Variant in value:
		if not key is String or not key in allowed:
			return false
	for key: String in required:
		if not value.has(key):
			return false
	return true

func _estimate_header_memory(record: Dictionary) -> int:
	var estimate: int = 1024
	for key: String in ["seed", "variant", "modifiers", "loadout", "roster", "mission_data"]:
		if record.has(key): estimate += JSON.stringify(record[key]).to_utf8_buffer().size() * 4 + 128
	return estimate
