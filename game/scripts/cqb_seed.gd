extends RefCounted
## P7 spawn materialization is independent of all simulation RNG streams.
## Legacy missions retain their existing spawn selection and input identity.
const SHOOT_HOUSE_IDS: Array[String] = ["SH01", "SH02", "SH03", "SH04", "SH05_PRECISION", "SH05_HIGH_INTENSITY"]
const PUZZLE_IDS: Array[String] = ["CQB01", "CQB02", "CQB03", "CQB04", "CQB05", "CQB06", "CQB07", "CQB08", "CQB09", "CQB10", "CQB11", "CQB12"]
const IDS: Array[String] = SHOOT_HOUSE_IDS + PUZZLE_IDS
const SPAWN_FIELDS: Array[String] = ["x", "z", "facing", "patrol"]

static func is_mission(id: String) -> bool:
	return IDS.has(id)

static func canonical_id(id: String) -> String:
	return "SH05" if id in ["SH05_PRECISION", "SH05_HIGH_INTENSITY"] else id

static func stable_hash(text: String) -> int:
	# Explicit UTF-8 FNV-1a32 avoids runtime hashes and platform RNG versions.
	var value: int = 2166136261
	for byte: int in text.to_utf8_buffer(): value = ((value ^ byte) * 16777619) & 0xffffffff
	return value

static func candidate_index(mission_id: String, enemy_id: String, seed: int, default_seed: int, count: int) -> int:
	if count <= 1 or seed == default_seed: return 0
	return stable_hash("%s:%d:%s" % [canonical_id(mission_id), seed, enemy_id]) % count

static func materialize(mission: Dictionary) -> Dictionary:
	var id: String = str(mission.get("id", ""))
	if not is_mission(id): return mission
	var result: Dictionary = mission.duplicate(true)
	var seed: int = int(result.get("seed", 42))
	var default_seed: int = int(result.get("default_seed", seed))
	for enemy: Dictionary in result.get("enemies", []):
		var candidates: Variant = enemy.get("spawns", [])
		if candidates is Array and not candidates.is_empty():
			var index: int = candidate_index(id, str(enemy.get("id", "")), seed, default_seed, candidates.size())
			var chosen: Variant = candidates[index]
			if chosen is Dictionary:
				for field: String in SPAWN_FIELDS:
					if chosen.has(field): enemy[field] = chosen[field]
		# The existing AI-RNG selector remains untouched and sees no P7 choices.
		enemy.erase("spawns")
	return result
