class_name BreachSpatialProfile
extends RefCounted
## Simulation dimensions. Rendering reads these values; imported skeletons do
## not decide whether an actor can observe or fire through an obstacle.
const SHOULDER_HALF_WIDTH := 0.17
const MAX_PEEK_LEAN := 0.35

static func floor_base_at(rooms: Array, point: Vector2) -> float:
	# One walkable surface per horizontal position. This supplies a cabin's
	# measured floor height; it does not introduce stacked navigation layers.
	var base := 0.0
	for room: Dictionary in rooms:
		if not room.has("base_height"): continue
		if absf(point.x - float(room.x)) <= float(room.w) * 0.5 and absf(point.y - float(room.z)) <= float(room.d) * 0.5:
			base = maxf(base, float(room.base_height))
	return base

static func prop_height(kind: String, cover: String = "none") -> float:
	match kind:
		"desk", "table": return 0.74
		"sofa": return 0.86
		"bed": return 0.77
		"cabinet", "bookshelf": return 1.30
		"plant": return 1.10
		"chair": return 0.92
		"box", "crate": return 0.68
		"rug": return 0.025
		"pillar": return 2.60
		"vehicle": return 1.50
	return 0.8 if cover == "low" else 2.0

static func prop_material(kind: String) -> String:
	match kind:
		"sofa", "bed", "rug": return "fabric"
		"vehicle": return "metal"
		"pillar": return "concrete"
		"plant": return "foliage"
	return "wood"

static func crouched(entity: Dictionary) -> bool:
	return str(entity.get("stance", "standing")) == "crouched"

static func body_height(entity: Dictionary) -> float:
	return maxf(0.1, float(entity.get("body_height", 1.18 if crouched(entity) else 1.75)))

static func eye_height(entity: Dictionary) -> float:
	return float(entity.get("base_height", 0.0)) + clampf(float(entity.get("eye_height", 1.02 if crouched(entity) else 1.62)), 0.05, body_height(entity))

static func weapon_height(entity: Dictionary) -> float:
	var height: float = 0.90 if crouched(entity) else 1.35
	if _catalog_weapon(entity):
		var id: String = str(entity.get("current_weapon",entity.get("weapon","standard")))
		height = float({"standard":1.53608,"suppressed":1.53608,"light":1.50317,"shotgun":1.46785,"pico_p1":1.49923}.get(id,1.53608)) - (0.46 if crouched(entity) else 0.0)
	return float(entity.get("base_height", 0.0)) + clampf(float(entity.get("weapon_height", height)), 0.05, body_height(entity))

static func target_height(entity: Dictionary) -> float:
	return float(entity.get("base_height", 0.0)) + body_height(entity) * 0.68

static func position(entity: Dictionary) -> Vector2:
	return Vector2(float(entity.get("x", 0.0)), float(entity.get("z", 0.0)))

static func weapon_origin(entity: Dictionary) -> Vector2:
	var aim: float = float(entity.get("aim_facing", entity.get("facing", 0.0)))
	return position(entity) + Vector2.from_angle(aim) * weapon_forward_offset(entity) + Vector2.from_angle(aim + PI * 0.5) * (0.11562 if _catalog_weapon(entity) else 0.0)

static func _catalog_weapon(entity: Dictionary) -> bool:
	return entity.get("kind", "") == "unit" and entity.has("weapon_length")

static func weapon_forward_offset(entity: Dictionary) -> float:
	# Measured grip and barrel sockets from the normalized CC0 models in the
	# authored idle pose. Legacy/enemy geometry keeps its existing dimensions.
	if not _catalog_weapon(entity):
		return 0.32
	var id: String = str(entity.get("current_weapon",entity.get("weapon","standard")))
	var base_length: float = float({"standard":0.86,"suppressed":0.86,"light":0.62,"shotgun":1.02,"pico_p1":0.23}.get(id,0.86))
	var forward: float = float({"standard":0.79557,"suppressed":0.79557,"light":0.52421,"shotgun":0.95462,"pico_p1":0.37841}.get(id,0.79557))
	return clampf(forward + maxf(0.0,float(entity.weapon_length)-base_length),0.10,1.35)

static func samples(entity: Dictionary) -> Array:
	var center := position(entity)
	var side := Vector2.from_angle(float(entity.get("body_facing", entity.get("facing", 0.0))) + PI * 0.5) * SHOULDER_HALF_WIDTH
	var base := float(entity.get("base_height", 0.0))
	var height := body_height(entity)
	return [
		{"point": center, "height": base + height * 0.92, "weight": 0.18, "region":"head"},
		{"point": center - side, "height": base + height * 0.68, "weight": 0.275, "region":"torso"},
		{"point": center + side, "height": base + height * 0.68, "weight": 0.275, "region":"torso"},
		{"point": center, "height": base + height * 0.39, "weight": 0.27, "region":"limb"},
	]
