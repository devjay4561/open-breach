class_name BreachPoseContact
extends RefCounted
## Post-process authored poses without adding keyframes or changing limb lengths.

static func reach(sk: Skeleton3D, side: String, world_target: Vector3, weight: float = 1.0, bones: PackedInt32Array = PackedInt32Array()) -> float:
	var upper: int = bones[0] if bones.size() == 3 else sk.find_bone("UpperArm." + side)
	var lower: int = bones[1] if bones.size() == 3 else sk.find_bone("LowerArm." + side)
	var wrist: int = bones[2] if bones.size() == 3 else sk.find_bone("Wrist." + side)
	if upper < 0 or lower < 0 or wrist < 0:
		return INF
	var a: Transform3D = sk.get_bone_global_pose(upper)
	var b: Transform3D = sk.get_bone_global_pose(lower)
	var c: Transform3D = sk.get_bone_global_pose(wrist)
	var target: Vector3 = sk.global_transform.affine_inverse() * world_target
	target = c.origin.lerp(target, clampf(weight, 0.0, 1.0))
	var first: float = a.origin.distance_to(b.origin)
	var second: float = b.origin.distance_to(c.origin)
	var direction: Vector3 = (target - a.origin).normalized()
	var epsilon: float = (first + second) * 0.0001
	var distance: float = clampf(a.origin.distance_to(target), absf(first - second) + epsilon, first + second - epsilon)
	if first < 0.00000001 or second < 0.00000001 or direction.length_squared() < 0.1:
		return INF
	var bend: Vector3 = (b.origin - a.origin) - direction * (b.origin - a.origin).dot(direction)
	if bend.length_squared() < 0.000000000001:
		bend = direction.cross(Vector3.UP)
		if bend.length_squared() < 0.000000000001:
			bend = direction.cross(Vector3.RIGHT)
	var along: float = (first * first + distance * distance - second * second) / (2.0 * distance)
	var elbow: Vector3 = a.origin + direction * along + bend.normalized() * sqrt(maxf(0.0, first * first - along * along))
	var goal: Vector3 = a.origin + direction * distance
	var turn := Basis(Quaternion((b.origin - a.origin).normalized(), (elbow - a.origin).normalized()))
	a.basis = turn * a.basis
	sk.set_bone_global_pose(upper, a)
	sk.force_update_all_bone_transforms()
	b = sk.get_bone_global_pose(lower)
	c = sk.get_bone_global_pose(wrist)
	b.basis = Basis(Quaternion((c.origin - b.origin).normalized(), (goal - b.origin).normalized())) * b.basis
	sk.set_bone_global_pose(lower, b)
	sk.force_update_all_bone_transforms()
	return (sk.global_transform * sk.get_bone_global_pose(wrist).origin).distance_to(world_target)

static func reach_transform(sk: Skeleton3D, side: String, world_target: Transform3D, weight: float = 1.0, bones: PackedInt32Array = PackedInt32Array()) -> float:
	# Keep the supporting palm's authored grip relative to the gun. Position-only
	# IK rotates the forearm and otherwise leaves the palm peeling off the grip.
	var error: float = reach(sk, side, world_target.origin, weight, bones)
	var wrist: int = bones[2] if bones.size() == 3 else sk.find_bone("Wrist." + side)
	if wrist < 0 or not is_finite(error):
		return error
	var pose: Transform3D = sk.get_bone_global_pose(wrist)
	var target_basis: Basis = (sk.global_transform.basis.inverse() * world_target.basis).orthonormalized()
	var rotation: Quaternion = pose.basis.orthonormalized().get_rotation_quaternion().slerp(target_basis.get_rotation_quaternion(), clampf(weight, 0.0, 1.0))
	pose.basis = Basis(rotation).scaled(pose.basis.get_scale())
	sk.set_bone_global_pose(wrist, pose)
	sk.force_update_all_bone_transforms()
	return error
