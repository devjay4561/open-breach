extends SceneTree
const Lab = preload("res://scripts/presentation_lab.gd")
const Door = preload("res://scripts/door_geometry.gd")
const Contact = preload("res://scripts/pose_contact.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var lab = Lab.new()
	root.add_child(lab)
	lab.configure({"seek":0.84})
	var visual: Dictionary = lab.world._entity_nodes.lab_actor.visual
	check(visual.contact_error < 0.025, "Authored torso reach keeps the latch wrist within 2.5 cm")
	check(visual.support_error < 0.025, "Door carry keeps the supporting wrist within 2.5 cm of the rifle")
	var sk: Skeleton3D = visual.skeleton
	var bones: Array[Transform3D] = []
	for i in range(sk.get_bone_count()): bones.append(sk.get_bone_pose(i))
	lab.configure({"seek":2.9})
	lab.configure({"seek":0.84})
	for i in range(sk.get_bone_count()):
		check(bones[i].is_equal_approx(sk.get_bone_pose(i)), "Seeking restores bone " + sk.get_bone_name(i))
	lab.tick(0.05)
	check(is_equal_approx(lab.time,0.84), "Paused preview does not advance")
	lab.configure({"scene":"walk","seek":1.2})
	check(visual.base_clip == "RifleWalk", "Preview selects original walking clip")
	lab.configure({"scene":"side","seek":1.2})
	check(str(visual.base_clip).begins_with("RifleStrafe"), "Preview selects authored lateral gait")
	lab.configure({"scene":"back","seek":1.2})
	check(visual.base_clip == "RifleWalkBack", "Preview selects authored backward gait")
	lab.configure({"scene":"reload","seek":1.2})
	check(str(visual.clip).begins_with("RifleReload"), "Preview selects reload")
	lab.configure({"scene":"turn","seek":1.1})
	check(visual.base_clip == "RifleTurnRight", "Preview exposes authored stationary turn footwork")
	lab.configure({"scene":"transitions","seek":1.7})
	check(str(visual.base_clip).begins_with("RifleStrafe"), "Transition study includes side movement")
	lab.configure({"scene":"transitions","seek":2.6})
	check(visual.base_clip == "RifleWalkBack", "Transition study includes backward movement")
	for axis: String in ["x","z"]:
		var door := {"x":6.0,"z":4.0,"axis":axis,"w":1.6 if axis == "x" else 0.24,"d":0.24 if axis == "x" else 1.6,"swing_sign":-1.0}
		var authored_handle: Vector3 = Door.handle_world(door,0.6)
		for side: float in [-1.0,1.0]:
			var normal := Vector2(0,side) if axis == "x" else Vector2(side,0)
			var opener := Door.handle_floor(door) + normal * Door.APPROACH_DISTANCE
			door.swing_sign = Door.opening_sign(door,opener)
			var handle := Door.handle_world(door,0.6)
			check(handle.is_equal_approx(authored_handle), "Fixed hinge preserves authored swing from either operator side on " + axis)
			check(Door.handle_world(door,0.15).is_equal_approx(Door.handle_world(door,0.0)), "Latch phase precedes leaf rotation")
	# Solver must preserve limb length under the imported rig's 100x scale.
	lab.configure({"scene":"door","seek":0.0})
	var a := sk.find_bone("UpperArm.L")
	var b := sk.find_bone("LowerArm.L")
	var c := sk.find_bone("Wrist.L")
	var first := sk.get_bone_global_pose(a).origin.distance_to(sk.get_bone_global_pose(b).origin)
	var second := sk.get_bone_global_pose(b).origin.distance_to(sk.get_bone_global_pose(c).origin)
	var target := sk.global_transform * sk.get_bone_global_pose(c).origin + Vector3(0.01,0.01,0.01)
	check(Contact.reach(sk,"L",target) < 0.002, "Scaled rig reaches nearby support socket")
	check(is_equal_approx(first,sk.get_bone_global_pose(a).origin.distance_to(sk.get_bone_global_pose(b).origin)), "Upper arm length preserved")
	check(is_equal_approx(second,sk.get_bone_global_pose(b).origin.distance_to(sk.get_bone_global_pose(c).origin)), "Forearm length preserved")
	lab.queue_free()
	await process_frame
	await process_frame
	print("BREACH_LAB_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
