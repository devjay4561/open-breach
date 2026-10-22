class_name BreachDoorGeometry
extends RefCounted
## Shared placement for the authored cutaway leaf and its interaction socket.
const LEAF = preload("res://assets/environment/doorLeaf.glb")
const HANDLE_FRACTION := 0.84
const HANDLE_HEIGHT := 0.96
const APPROACH_DISTANCE := 0.40

static func width(door: Dictionary) -> float:
	return float(door.get("w", 1.6) if door.get("axis", "x") == "x" else door.get("d", 1.6))

## Authored doorway plane, independent of the moving leaf. Depth is per side.
static func funnel_rect(door: Dictionary, depth: float = 1.2) -> Rect2:
	var size := Vector2(width(door), depth * 2.0) if door.get("axis", "x") == "x" else Vector2(depth * 2.0, width(door))
	return Rect2(Vector2(float(door.x), float(door.z)) - size * 0.5, size)

static func handle_floor(door: Dictionary) -> Vector2:
	var across: Vector2 = Vector2.RIGHT if door.get("axis", "x") == "x" else Vector2.DOWN
	return Vector2(float(door.x), float(door.z)) - across * hinge_side(door) * width(door) * (HANDLE_FRACTION - 0.5)

static func hinge_side(door: Dictionary) -> float:
	return 1.0 if float(door.get("hinge_side", -1.0)) > 0.0 else -1.0

static func hinge_transform(door: Dictionary, progress: float) -> Transform3D:
	var across_x: bool = door.get("axis", "x") == "x"
	var side: float = hinge_side(door)
	var offset := Vector3(side * width(door) * 0.5, 0, 0) if across_x else Vector3(0, 0, side * width(door) * 0.5)
	var closed_angle: float = (0.0 if across_x else -PI * 0.5) + (PI if side > 0.0 else 0.0)
	return Transform3D(Basis(Vector3.UP, opening_sign(door, Vector2.ZERO) * leaf_progress(progress) * PI * 0.49 + closed_angle), Vector3(float(door.x), 0.2 + float(door.get("base_height", 0.0)), float(door.z)) + offset)

static func handle_world(door: Dictionary, progress: float) -> Vector3:
	return hinge_transform(door, progress) * Vector3(width(door) * HANDLE_FRACTION, HANDLE_HEIGHT, 0)

static func opening_sign(door: Dictionary, _opener: Vector2) -> float:
	# A real hinge has an authored direction, independent of the approaching side.
	return 1.0 if float(door.get("swing_sign", -1.0)) > 0.0 else -1.0

static func leaf_progress(progress: float) -> float:
	return smoothstep(0.22, 1.0, progress)

# Imported leaf bounds including the existing handle: local Z ±0.11269 m.
const LEAF_HALF_DEPTH := 0.113

static func leaf_obstacle(door: Dictionary, progress: float = -1.0) -> Dictionary:
	if bool(door.get("destroyed", false)):
		return {}
	var value := progress if progress >= 0.0 else (1.0 if door.get("state", "CLOSED") == "OPEN" else float(door.get("progress", 0.0)))
	var pose := hinge_transform(door, value)
	var center := pose * Vector3(width(door) * 0.5, 0, 0)
	var along := pose.basis * Vector3.RIGHT
	var obstacle: Dictionary = {"x":center.x, "z":center.z, "w":width(door), "d":LEAF_HALF_DEPTH * 2.0, "leaf_angle":atan2(along.z, along.x), "height":float(door.get("height", 2.1)), "base_height":float(door.get("base_height", 0.0)), "material":str(door.get("material", "wood"))}
	for key: String in ["opacity", "resistance", "opaque", "penetration_resistance"]:
		if door.has(key): obstacle[key] = door[key]
	return obstacle

static func movement_obstacle(door: Dictionary, progress: float = -1.0) -> Dictionary:
	# Compatibility name: movement and zero-radius visibility share one leaf.
	return leaf_obstacle(door, progress)

static func ray_distance(door: Dictionary, origin: Vector2, direction: Vector2, max_distance: float, progress: float = -1.0) -> float:
	if direction.length_squared() <= 0.00000001 or max_distance <= 0.0:
		return maxf(0.0, max_distance)
	var obstacle := leaf_obstacle(door, progress)
	if obstacle.is_empty():
		return max_distance
	var local_origin := local_point(obstacle, origin)
	var local_direction := direction.normalized().rotated(-float(obstacle.leaf_angle))
	var rect := local_rect(obstacle)
	var near_distance := 0.0
	var far_distance := max_distance
	for axis: int in range(2):
		if absf(local_direction[axis]) < 0.000001:
			if local_origin[axis] < rect.position[axis] or local_origin[axis] > rect.end[axis]:
				return max_distance
		else:
			var first: float = (rect.position[axis] - local_origin[axis]) / local_direction[axis]
			var last: float = (rect.end[axis] - local_origin[axis]) / local_direction[axis]
			near_distance = maxf(near_distance, minf(first, last))
			far_distance = minf(far_distance, maxf(first, last))
			if near_distance > far_distance:
				return max_distance
	return near_distance

static func local_point(obstacle: Dictionary, point: Vector2) -> Vector2:
	return (point - Vector2(float(obstacle.x), float(obstacle.z))).rotated(-float(obstacle.leaf_angle))

static func local_rect(obstacle: Dictionary, padding: float = 0.0) -> Rect2:
	return Rect2(-float(obstacle.w)*0.5-padding, -float(obstacle.d)*0.5-padding, float(obstacle.w)+padding*2.0, float(obstacle.d)+padding*2.0)

static func overlaps_actor(door: Dictionary, progress: float, point: Vector2, radius: float) -> bool:
	return obstacle_overlaps_actor(movement_obstacle(door, progress), point, radius)

static func obstacle_overlaps_actor(obstacle: Dictionary, point: Vector2, radius: float) -> bool:
	if obstacle.is_empty():
		return false
	# Conservative circle rejects distant actors before rotated rectangle math.
	var half := Vector2(float(obstacle.w) * 0.5 + radius, float(obstacle.d) * 0.5 + radius)
	var reach := half.length() + 0.00001 # Retain included corners through float32 rotation rounding.
	if point.distance_squared_to(Vector2(float(obstacle.x), float(obstacle.z))) > reach * reach:
		return false
	return local_rect(obstacle, radius).has_point(local_point(obstacle, point))
