extends RefCounted
## P4 communication uses authoritative own-unit body poses. Callers resolve
## IDs against the live own roster and supply the actual can_act predicate;
## camera, leaning/peek origins and sensory memories are never consulted.
const Spatial = preload("res://scripts/spatial_profile.gd")
const FLOOR_EPSILON: float = 0.0001
const MODES: Array[String] = ["verbal", "hand_signals"]

static func discipline(mission: Dictionary) -> String:
	# Defaults are runtime reads, not authoring migrations: injecting this key
	# into a v1-v4 source would invalidate its strict schema/replay contract.
	var value: Variant = mission.get("noise_discipline", "verbal")
	return value if value is String and MODES.has(value) else ""

static func can_receive(sender: Dictionary, receiver: Dictionary, navigation: BreachNavigation, mode: String = "verbal", smoke_zones: Array = []) -> bool:
	if not MODES.has(mode) or not _eligible(sender) or not _eligible(receiver): return false
	if sender.id == receiver.id: return true
	# Spoken communication retains the existing logical own-team broadcast.
	# Its 6m acoustic stimulus is emitted separately by the simulation once.
	if mode == "verbal": return true
	if navigation == null or absf(float(sender.get("base_height", 0.0)) - float(receiver.get("base_height", 0.0))) > FLOOR_EPSILON: return false
	return _body_sees(sender, receiver, navigation, smoke_zones) and _body_sees(receiver, sender, navigation, smoke_zones)

static func delivery(sender: Dictionary, receivers: Array, navigation: BreachNavigation, mode: String = "verbal", smoke_zones: Array = []) -> Dictionary:
	var source_id: String = str(sender.get("id", "")) if sender.get("id", "") is String else ""
	var delivered: Array[String] = []
	var blocked: Array[String] = []
	var seen: Dictionary = {}
	var complete: bool = not receivers.is_empty() and _eligible(sender) and MODES.has(mode)
	for value: Variant in receivers:
		if not value is Dictionary:
			complete = false
			continue
		var receiver: Dictionary = value
		var id: String = str(receiver.get("id", "")) if receiver.get("id", "") is String else ""
		if id.is_empty():
			complete = false
			continue
		if seen.has(id): continue
		seen[id] = true
		if can_receive(sender, receiver, navigation, mode, smoke_zones):
			delivered.append(id)
		else:
			blocked.append(id)
			complete = false
	# These are deterministic diagnostic results, not the public occurrence
	# bundle. Simulation adds signal_mode/signal_radius and excludes blocked IDs.
	delivered.sort()
	blocked.sort()
	return {"source_unit_id":source_id, "receiver_unit_ids":delivered, "blocked_unit_ids":blocked, "complete":complete}

static func _eligible(unit: Dictionary) -> bool:
	if unit.get("kind", "") != "unit" or not unit.get("id", "") is String or str(unit.get("id", "")).is_empty(): return false
	if not unit.get("can_act") is bool or unit.get("can_act") != true: return false
	if not _number(unit.get("x")) or not _number(unit.get("z")): return false
	for field: String in ["facing", "base_height", "fov", "vision_range", "effective_vision_range", "eye_height", "body_height", "hp", "stunned", "_flash_recover"]:
		if unit.has(field) and not _number(unit[field]): return false
	if float(unit.get("hp", 1.0)) <= 0.0 or float(unit.get("stunned", 0.0)) > 0.0 or float(unit.get("_flash_recover", 0.0)) > 0.0: return false
	if unit.get("surrendered", false) == true or unit.get("arrested", false) == true: return false
	if unit.get("stance", "standing") not in ["standing", "crouched"]: return false
	if float(unit.get("fov", 110.0)) < 0.0 or float(unit.get("fov", 110.0)) > 360.0: return false
	if float(unit.get("vision_range", 10.0)) < 0.0 or float(unit.get("effective_vision_range", 0.0)) < 0.0: return false
	return float(unit.get("body_height", 1.18 if Spatial.crouched(unit) else 1.75)) > 0.0 and float(unit.get("eye_height", 1.02 if Spatial.crouched(unit) else 1.62)) > 0.0

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _body_sees(observer: Dictionary, subject: Dictionary, navigation: BreachNavigation, smoke_zones: Array) -> bool:
	var origin := Spatial.position(observer)
	var destination := Spatial.position(subject)
	var offset := destination - origin
	var vision_range: float = float(observer.effective_vision_range) if observer.has("effective_vision_range") else navigation.effective_vision_range(observer)
	if offset.length() > vision_range: return false
	if offset.length_squared() > 0.02 and absf(angle_difference(float(observer.get("facing", 0.0)), offset.angle())) > deg_to_rad(float(observer.get("fov", 110.0))) * 0.5: return false
	if _smoke_blocks(origin, destination, smoke_zones): return false
	return navigation.sight_clear_height(origin, destination, Spatial.eye_height(observer), Spatial.eye_height(subject))

static func _smoke_blocks(origin: Vector2, destination: Vector2, smoke_zones: Array) -> bool:
	# Same segment/circle test as Simulation._smoke_blocks. The caller supplies
	# current active zones; this helper does not advance or expire their timers.
	for value: Variant in smoke_zones:
		if not value is Dictionary: continue
		var zone: Dictionary = value
		if not _number(zone.get("x")) or not _number(zone.get("z")) or not _number(zone.get("radius")): continue
		var center := Vector2(float(zone.x), float(zone.z))
		if Geometry2D.get_closest_point_to_segment(center, origin, destination).distance_to(center) < float(zone.radius): return true
	return false
