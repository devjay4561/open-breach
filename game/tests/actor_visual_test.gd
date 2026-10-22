extends SceneTree

const Actor = preload("res://scripts/actor_visual.gd")
const REQUIRED_CLIPS: Array[String] = ["RifleIdle", "RifleFire", "RifleHit", "RifleReload", "RifleWalk", "RifleWalkBack", "RifleStrafeLeft", "RifleStrafeRight", "RifleRun", "RifleThrow", "Death", "RifleTurnLeft", "RifleTurnRight", "DoorOpenOut"]
const LEG_BONES: Array[String] = ["Hips", "UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R", "Foot.L", "Foot.R"]
const ARM_BONES: Array[String] = ["Abdomen", "Torso", "Chest", "UpperArm.L", "LowerArm.L", "Wrist.L", "UpperArm.R", "LowerArm.R", "Wrist.R"]
var checks: int = 0
var failures: Array[String] = []
var bodies: Array[Node3D] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _actor() -> Dictionary:
	var body := Node3D.new()
	root.add_child(body)
	bodies.append(body)
	return Actor.create(body, false)

func _entity() -> Dictionary:
	return {"id": "alpha", "hp": 100.0, "status": "READY", "weapon": "standard", "facing": 0.0, "aim_facing": 0.0, "move_facing": 0.0, "travel_distance": 0.0, "commands": []}

func _poses(visual: Dictionary, names: Array[String] = []) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var sk: Skeleton3D = visual.skeleton
	if names.is_empty():
		for bone: int in range(sk.get_bone_count()):
			result.append(sk.get_bone_pose(bone))
	else:
		for name: String in names:
			var bone: int = sk.find_bone(name)
			if bone >= 0:
				result.append(sk.get_bone_pose(bone))
	return result

func _same(a: Array[Transform3D], b: Array[Transform3D]) -> bool:
	if a.size() != b.size():
		return false
	for index: int in range(a.size()):
		if not a[index].is_equal_approx(b[index]):
			return false
	return true

func _run() -> void:
	_test_no_outline_pass()
	_test_assets_and_stationary_feedback()
	_test_continuous_gait_under_fire()
	_test_directional_locomotion()
	_test_reload_death_and_rewind()
	_test_weapon_socket()
	_test_throw_segment()
	_test_gait_transition_and_seek_resume()
	_test_support_orientation()
	_test_stationary_turn()
	_test_frozen_input_changes()
	_test_stun_and_surrender_poses()
	for body: Node3D in bodies:
		body.queue_free()
	# Finish skeleton modifiers and release all render RIDs before the dummy
	# renderer exits. This also catches lifecycle errors hidden by immediate quit.
	await process_frame
	await process_frame
	print("BREACH_ACTOR_VISUAL_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_no_outline_pass() -> void:
	var body := Node3D.new()
	root.add_child(body)
	bodies.append(body)
	var visual: Dictionary = Actor.create(body, false, Color.CYAN)
	_check(visual.outline_rims.is_empty() and visual.outline_rims.get_typed_builtin() == TYPE_OBJECT and visual.outline_rims.get_typed_class_name() == &"StandardMaterial3D", "Friendly recoloring retains an empty typed material array")
	var surfaces := 0
	for mesh: MeshInstance3D in visual.model.find_children("*", "MeshInstance3D", true, false):
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(surface)
			if material != null:
				surfaces += 1
				_check(material.next_pass == null, "Friendly surface has no extra outline draw pass")
	_check(surfaces > 0, "Outline absence is checked on real imported surfaces")

func _test_assets_and_stationary_feedback() -> void:
	var visual: Dictionary = _actor()
	var entity: Dictionary = _entity()
	for clip: String in REQUIRED_CLIPS:
		_check(visual.names.has(clip), "Imported combat asset contains authored " + clip)
		if visual.names.has(clip):
			var animation: Animation = visual.player.get_animation(visual.names[clip])
			_check(animation.length > 0.1 and animation.get_track_count() > 10, clip + " contains timed skeletal tracks")
	for bone: String in LEG_BONES + ARM_BONES:
		_check(visual.skeleton.find_bone(bone) >= 0, "Combat rig provides required bone " + bone)
	Actor.sync(visual, entity, [], 0.0, 0.0, false)
	var idle: Array[Transform3D] = _poses(visual, ARM_BONES)
	var shot: Array = [{"seq": 1, "type": "SHOT", "attacker_id": "alpha", "time": 0.1}]
	Actor.sync(visual, entity, shot, 0.1, 0.0, false)
	Actor.sync(visual, entity, shot, 0.22, 0.0, false)
	_check(str(visual.clip).begins_with("RifleFire:"), "Observed shot selects authored rifle firing motion")
	_check(not _same(idle, _poses(visual, ARM_BONES)), "Rifle firing changes upper-body pose after transition")
	var fired: Array[Transform3D] = _poses(visual)
	var muzzle_before: Vector3 = visual.muzzle.global_position
	Actor.sync(visual, entity, shot, 0.22, 0.0, false)
	_check(_same(fired, _poses(visual)), "Pausing on a shot freezes every bone")
	_check(muzzle_before.is_equal_approx(visual.muzzle.global_position), "Pausing also freezes the weapon socket")
	Actor.sync(visual, entity, [], 0.7, 0.0, false)
	var miss: Array = [{"seq": 2, "type": "SHOT", "target_id": "alpha", "hit": false, "time": 0.8}]
	Actor.sync(visual, entity, miss, 0.8, 0.0, false)
	_check(not str(visual.clip).begins_with("RifleHit:"), "Missed shots do not trigger a body hit reaction")
	var hit: Array = [{"seq": 3, "type": "SHOT", "target_id": "alpha", "hit": true, "time": 1.0}]
	Actor.sync(visual, entity, hit, 1.0, 0.0, false)
	Actor.sync(visual, entity, hit, 1.12, 0.0, false)
	_check(str(visual.clip).begins_with("RifleHit:"), "Confirmed hit selects authored rifle hit reaction")
	_check(not _same(idle, _poses(visual, ARM_BONES)), "Hit reaction produces a distinct upper-body pose")
	var fresh: Dictionary = _actor()
	Actor.sync(fresh, entity, [{"type": "SHOT", "attacker_id": "alpha", "time": 2.0}], 1.0, 0.0, false)
	_check(str(fresh.clip).begins_with("RifleIdle:") and float(fresh.last_shot) < 0.0, "Future events cannot start a shot before presentation time")

func _test_continuous_gait_under_fire() -> void:
	var walking: Dictionary = _actor()
	var firing: Dictionary = _actor()
	var entity: Dictionary = _entity()
	entity.status = "MOVING"
	Actor.sync(walking, entity, [], 0.0, 0.0, false)
	Actor.sync(firing, entity, [], 0.0, 0.0, false)
	var first_legs: Array[Transform3D] = _poses(walking, LEG_BONES)
	var upper_changed: bool = false
	for index: int in range(10):
		var time: float = 0.3 + index * 0.27
		var event: Array = [{"seq": index + 1, "type": "SHOT", "attacker_id": "alpha", "time": time}]
		entity.travel_distance = 0.12 + index * 0.21
		Actor.sync(walking, entity, [], time, 0.1, false)
		Actor.sync(firing, entity, event, time, 0.1, false)
		entity.travel_distance += 0.07
		Actor.sync(walking, entity, [], time + 0.09, 0.07, false)
		Actor.sync(firing, entity, event, time + 0.09, 0.07, false)
		_check(_same(_poses(walking, LEG_BONES), _poses(firing, LEG_BONES)), "Shot %d preserves all lower-body bones at the same traveled distance" % (index + 1))
		_check(is_equal_approx(float(walking.gait_phase), float(firing.gait_phase)), "Shot %d does not restart the gait phase" % (index + 1))
		upper_changed = upper_changed or not _same(_poses(walking, ARM_BONES), _poses(firing, ARM_BONES))
	_check(not _same(first_legs, _poses(walking, LEG_BONES)), "Distance-driven locomotion actually advances leg poses")
	_check(upper_changed, "Moving shot layers visibly alter the upper body while preserving gait")

func _test_directional_locomotion() -> void:
	var visual: Dictionary = _actor()
	var entity: Dictionary = _entity()
	entity.status = "MOVING"
	var angles: Array[float] = [0.0, PI * 0.5, -PI * 0.5, PI]
	var clips: Array[String] = ["RifleWalk", "RifleStrafeRight", "RifleStrafeLeft", "RifleWalkBack"]
	for index: int in range(angles.size()):
		entity.move_facing = angles[index]
		entity.travel_distance = 0.37
		Actor.sync(visual, entity, [], float(index), 0.0, false)
		_check(visual.base_clip == clips[index], "Travel relative to aim selects authored " + clips[index])
	entity.aim_facing = PI * 0.5
	entity.move_facing = PI * 0.5
	Actor.sync(visual, entity, [], 5.0, 0.0, false)
	_check(visual.base_clip == "RifleWalk", "Locomotion direction is relative to aim rather than world axes")

func _test_reload_death_and_rewind() -> void:
	var visual: Dictionary = _actor()
	var entity: Dictionary = _entity()
	Actor.sync(visual, entity, [], 0.0, 0.0, false)
	var idle: Array[Transform3D] = _poses(visual)
	entity.status = "RELOADING"
	entity.commands = [{"type": "RELOAD", "state": "RUNNING", "remaining": 1.8}]
	Actor.sync(visual, entity, [], 0.5, 0.0, false)
	entity.commands[0].remaining = 1.2
	Actor.sync(visual, entity, [], 0.6, 0.0, false)
	var early_reload: Array[Transform3D] = _poses(visual, ARM_BONES)
	_check(str(visual.clip).begins_with("RifleReload:"), "Reload uses the authored rifle-specific animation")
	_check(not _same(idle, _poses(visual)), "Reload does not simply hold the idle pose")
	entity.commands[0].remaining = 0.4
	Actor.sync(visual, entity, [], 0.8, 0.0, false)
	_check(not _same(early_reload, _poses(visual, ARM_BONES)), "Reload command progress moves the authored arms and hands")
	var reloading: Array[Transform3D] = _poses(visual)
	Actor.sync(visual, entity, [], 0.8, 0.0, false)
	_check(_same(reloading, _poses(visual)), "Reload stays stable while command time is paused")
	entity.hp = 0.0
	entity.status = "INCAPACITATED"
	entity.commands = []
	var death: Array = [{"type": "INCAPACITATED", "entity_id": "alpha", "time": 1.0}]
	Actor.sync(visual, entity, death, 1.0, 0.0, false)
	Actor.sync(visual, entity, death, 1.2, 0.0, false)
	_check(str(visual.clip).begins_with("Death:"), "Incapacitation starts authored full-body death motion")
	_check(not _same(idle, _poses(visual)), "Death visibly differs from a standing idle pose")
	Actor.sync(visual, entity, death, 7.0, 0.0, false)
	var final_pose: Array[Transform3D] = _poses(visual)
	Actor.sync(visual, entity, [], 8.0, 0.0, false)
	_check(_same(final_pose, _poses(visual)), "Death keeps its last pose after the event leaves the recent queue")
	entity = _entity()
	Actor.sync(visual, entity, [], 0.0, 0.0, false)
	_check(str(visual.clip).begins_with("RifleIdle:") and float(visual.last_hit) < 0.0 and float(visual.last_shot) < 0.0, "Replay rewind clears stale feedback layers")
	_check(_same(idle, _poses(visual)), "Rewind restores the original authored pose without residual blending")
	var already_dead: Dictionary = _actor()
	entity.hp = 0.0
	Actor.sync(already_dead, entity, [], 20.0, 0.0, false)
	_check(_same(final_pose, _poses(already_dead)), "Seeking directly to a dead actor with no retained death event shows its final pose")

func _test_weapon_socket() -> void:
	var visual: Dictionary = _actor()
	var entity: Dictionary = _entity()
	Actor.sync(visual, entity, [], 0.0, 0.0, false)
	var muzzle_before: Vector3 = visual.muzzle.global_position
	_check(visual.muzzle.get_parent() == visual.weapon, "Muzzle is attached to the animated rifle rather than a world offset")
	var body: Node3D = visual.model.get_parent()
	body.position = Vector3(3.0, 0.0, -2.0)
	body.rotation.y = PI * 0.5
	var expected: Vector3 = body.global_transform * muzzle_before
	_check(expected.is_equal_approx(visual.muzzle.global_position), "Muzzle follows unit translation and facing exactly")
	var weapon_idle: Transform3D = visual.weapon.transform
	entity.status = "RELOADING"
	entity.commands = [{"type": "RELOAD", "state": "RUNNING", "remaining": 1.8}]
	Actor.sync(visual, entity, [], 1.0, 0.0, false)
	entity.commands[0].remaining = 0.8
	Actor.sync(visual, entity, [], 1.2, 0.0, false)
	_check(not weapon_idle.is_equal_approx(visual.weapon.transform), "Rifle and muzzle follow animated wrist motion during reload")
	var sk: Skeleton3D = visual.skeleton
	var wrist_world: Transform3D = sk.global_transform * sk.get_bone_global_pose(int(visual.wrist))
	_check((wrist_world * visual.weapon_bind).is_equal_approx(visual.weapon.global_transform), "Rifle attachment preserves its bind transform relative to the firing wrist")

func _test_throw_segment() -> void:
	var visual: Dictionary = _actor()
	var entity: Dictionary = _entity()
	entity.status = "THROWING"
	entity.commands = [{"type":"THROW_STUN","state":"RUNNING","remaining":0.45}]
	Actor.sync(visual, entity, [], 1.0, 0.0, false)
	var prepared := _poses(visual)
	entity.commands[0].remaining = 0.10
	Actor.sync(visual, entity, [], 1.35, 0.0, false)
	_check(not _same(prepared, _poses(visual)), "Throw winds up during the actual 0.45 second command")
	var sk: Skeleton3D = visual.skeleton
	var left_world: Transform3D = sk.global_transform * sk.get_bone_global_pose(int(visual.left_wrist))
	_check((left_world * visual.left_weapon_bind).is_equal_approx(visual.weapon.global_transform), "Throw keeps rifle in the supporting hand")
	var paused := _poses(visual)
	Actor.sync(visual, entity, [], 1.35, 0.0, false)
	_check(_same(paused, _poses(visual)), "Paused throw pose remains frozen")
	entity.status = "READY"
	entity.commands = []
	Actor.sync(visual, entity, [{"type":"STUN","unit_id":"alpha","time":1.45}], 1.50, 0.0, false)
	_check(str(visual.clip).begins_with("RifleThrow:"), "Throw follow-through matches its effect event")
	Actor.sync(visual, entity, [], 1.75, 0.0, false)
	_check(str(visual.clip).begins_with("RifleIdle:"), "Throw returns to rifle stance after follow-through")

func _test_gait_transition_and_seek_resume() -> void:
	var visual: Dictionary = _actor()
	var entity: Dictionary = _entity()
	entity.status = "MOVING"
	entity.travel_distance = 0.42
	Actor.sync(visual, entity, [], 1.0, 0.0, false)
	var before := _poses(visual, LEG_BONES)
	entity.move_facing = PI * 0.5
	Actor.sync(visual, entity, [], 1.0, 0.0, false)
	_check(_same(before, _poses(visual, LEG_BONES)), "Direction switch retains the previous leg pose at transition start")
	entity.travel_distance = 0.57
	Actor.sync(visual, entity, [], 1.2, 0.15, false)
	var settled: Dictionary = _actor()
	Actor.sync(settled, entity, [], 1.2, 0.0, false)
	_check(_same(_poses(visual, LEG_BONES), _poses(settled, LEG_BONES)), "Directional transition settles to the distance-driven authored gait")
	before = _poses(visual, LEG_BONES)
	entity.status = "READY"
	Actor.sync(visual, entity, [], 1.4, 0.0, false)
	_check(_same(before, _poses(visual, LEG_BONES)), "Stopping blends feet out of the prior stride rather than snapping to idle")
	entity.status = "MOVING"
	entity.move_facing = 0.0
	entity.travel_distance = 0.20
	Actor.sync(visual, entity, [], 0.4, 0.0, false)
	entity.travel_distance = 0.226
	Actor.sync(visual, entity, [], 0.416, 0.026, false)
	var fresh: Dictionary = _actor()
	Actor.sync(fresh, entity, [], 0.416, 0.0, false)
	_check(_same(_poses(visual), _poses(fresh)), "Resuming after rewind does not blend old future poses back into the actor")

func _test_support_orientation() -> void:
	var visual: Dictionary = _actor()
	var entity: Dictionary = _entity()
	var shot: Array = [{"type":"SHOT","attacker_id":"alpha","time":0.0}]
	Actor.sync(visual, entity, shot, 0.12, 0.0, false)
	var sk: Skeleton3D = visual.skeleton
	var actual: Transform3D = sk.global_transform * sk.get_bone_global_pose(int(visual.left_wrist))
	var support: Transform3D = visual.weapon.global_transform * visual.support_bind
	_check(actual.origin.distance_to(support.origin) < 0.002, "Firing keeps the supporting wrist on its weapon socket")
	_check(actual.basis.orthonormalized().get_rotation_quaternion().angle_to(support.basis.orthonormalized().get_rotation_quaternion()) < 0.002, "Supporting palm orientation follows the grip after the arm IK solve")

func _test_frozen_input_changes() -> void:
	var visual: Dictionary = _actor()
	var entity: Dictionary = _entity()
	var events: Array = []
	for i in range(4):
		Actor.sync(visual, entity, events, 1.0, 0.0, false)
	var paused := _poses(visual)
	Actor.sync(visual, entity, events, 1.0, 0.0, false)
	_check(_same(paused, _poses(visual)), "Repeated frozen frames preserve the complete pose")
	events.append({"type":"SHOT", "attacker_id":"alpha", "time":1.0})
	Actor.sync(visual, entity, events, 1.0, 0.0, false)
	_check(str(visual.clip).begins_with("RifleFire:"), "New event at the same clock invalidates the frozen pose")
	entity.status = "ARRESTED"
	Actor.sync(visual, entity, events, 1.0, 0.0, false)
	_check(not visual.weapon.visible, "In-place entity edits at the same clock update the weapon")
	entity.status = "READY"
	entity.turn_started_at = 0.9
	entity.turn_delta = PI * 0.5
	Actor.sync(visual, entity, [], 1.0, 0.0, false)
	Actor.sync(visual, entity, [], 1.0, 0.0, false)
	Actor.sync(visual, entity, [], 1.0, 0.0, true)
	_check(is_equal_approx(visual.model.rotation.y, PI * 0.5), "Reduced-motion changes at the same clock release turn correction")
	Actor.sync(visual, entity, [], 0.2, 0.0, false)
	_check(float(visual.last_shot) < 0.0 and visual.weapon.visible, "Rewind clears frozen feedback and reconstructs the actor")
	Actor.sync(visual, entity, [], 0.3, 0.0, false)
	_check(not _same(paused, _poses(visual)), "Resumed time continues animation after frozen frames")
	entity.status = "RELOADING"
	entity.commands = [{"type":"RELOAD", "state":"RUNNING", "remaining":1.2}]
	Actor.sync(visual, entity, [], 2.0, 0.0, false)
	Actor.sync(visual, entity, [], 2.2, 0.0, false)
	Actor.sync(visual, entity, [], 2.2, 0.0, false)
	paused = _poses(visual)
	entity.commands[0].remaining = 0.2
	Actor.sync(visual, entity, [], 2.2, 0.0, false)
	_check(not _same(paused, _poses(visual)), "Editing a nested reload command at a frozen clock invalidates the pose hash")

func _test_stationary_turn() -> void:
	var visual: Dictionary = _actor()
	var entity: Dictionary = _entity()
	entity.turn_started_at = 1.0
	entity.turn_delta = PI * 0.5
	Actor.sync(visual, entity, [], 1.15, 0.0, false)
	_check(visual.base_clip == "RifleTurnRight", "Stationary signed turn selects the authored right-turn footwork")
	var aim_reference: Dictionary = _actor()
	var reference_entity: Dictionary = _entity()
	Actor.sync(aim_reference, reference_entity, [], 1.15, 0.0, false)
	var turn_direction: Vector3 = (visual.weapon.global_basis * Vector3.RIGHT).normalized()
	var aim_direction: Vector3 = (aim_reference.weapon.global_basis * Vector3.RIGHT).normalized()
	_check(turn_direction.dot(aim_direction) > cos(deg_to_rad(8.0)), "Turning feet keep the rifle aligned with the target aim")
	var early := _poses(visual, LEG_BONES)
	var early_correction: float = visual.model.rotation.y - PI * 0.5
	Actor.sync(visual, entity, [], 1.5, 0.0, false)
	_check(not _same(early, _poses(visual, LEG_BONES)), "Stationary turning advances authored leg poses without translation")
	_check(absf(visual.model.rotation.y - PI * 0.5) < absf(early_correction), "Lower body catches up to aim over the replayable turn window")
	var paused := _poses(visual)
	Actor.sync(visual, entity, [], 1.5, 0.0, false)
	_check(_same(paused, _poses(visual)), "Paused turn freezes upper-body aim and stepping legs")
	Actor.sync(visual, entity, [], 1.15, 0.0, false)
	var fresh: Dictionary = _actor()
	Actor.sync(fresh, entity, [], 1.15, 0.0, false)
	_check(_same(_poses(visual), _poses(fresh)), "Turn metadata reconstructs the same pose on replay seek")
	entity.status = "MOVING"
	entity.travel_distance = 0.4
	Actor.sync(visual, entity, [], 1.2, 0.1, false)
	_check(visual.base_clip == "RifleWalk" and is_equal_approx(visual.model.rotation.y, PI * 0.5), "Translation overrides stationary footwork and releases body correction")

func _bone_position(visual: Dictionary, name: String) -> Vector3:
	var sk: Skeleton3D = visual.skeleton
	return visual.model.to_local(sk.global_transform * sk.get_bone_global_pose(sk.find_bone(name)).origin)

func _test_stun_and_surrender_poses() -> void:
	var visual: Dictionary = _actor()
	var entity: Dictionary = _entity()
	Actor.sync(visual, entity, [], 0.0, 0.0, false)
	var standing_head: Vector3 = _bone_position(visual, "Head")
	var feet: Array[Vector3] = [_bone_position(visual, "Foot.L"), _bone_position(visual, "Foot.R")]
	entity.status = "STUNNED"
	entity.stunned = 2.0
	var shot: Array = [{"type":"SHOT", "attacker_id":"alpha", "time":1.0}]
	Actor.sync(visual, entity, shot, 1.0, 0.0, false)
	Actor.sync(visual, entity, shot, 1.15, 0.0, false)
	_check(_bone_position(visual, "Head").y < standing_head.y - 0.18, "Stun visibly bends the body instead of retaining the armed idle")
	_check(_bone_position(visual, "Wrist.R").distance_to(_bone_position(visual, "Head")) < 0.25, "Stunned actor shields the head with the right hand despite a recent shot")
	_check(visual.weapon.visible and (visual.weapon.global_basis * Vector3.RIGHT).normalized().y < -0.5, "Stunned actor carries the weapon muzzle-down")
	_check(float(visual.support_error) < 0.005, "Stunned actor's left hand stays on the rifle grip")
	for index: int in range(2):
		_check(_bone_position(visual, "Foot." + ["L", "R"][index]).distance_to(feet[index]) < 0.005, "Stun keeps the authored foot contact planted")
	var paused := _poses(visual)
	Actor.sync(visual, entity, shot, 1.15, 0.0, false)
	_check(_same(paused, _poses(visual)), "Pausing freezes the stunned pose and sway")
	Actor.sync(visual, entity, [], 1.5, 0.0, false)
	_check(not _same(paused, _poses(visual)), "Stun adds restrained sway while simulation time advances")
	Actor.sync(visual, entity, [], 1.15, 0.0, false)
	var fresh: Dictionary = _actor()
	Actor.sync(fresh, entity, [], 1.15, 0.0, false)
	_check(_same(_poses(visual), _poses(fresh)), "Replay seeking reconstructs the same stunned pose")
	Actor.sync(visual, entity, [], 2.0, 0.0, true)
	var reduced := _poses(visual)
	Actor.sync(visual, entity, [], 2.5, 0.0, true)
	_check(_same(reduced, _poses(visual)), "Reduced motion retains the stun posture without sway")
	entity.status = "SURRENDERED"
	Actor.sync(visual, entity, [], 3.0, 0.0, false)
	Actor.sync(visual, entity, [], 3.2, 0.0, false)
	_check(not visual.weapon.visible, "Surrender removes the weapon even while a stun timer remains")
	var head: Vector3 = _bone_position(visual, "Head")
	var left: Vector3 = _bone_position(visual, "Wrist.L")
	var right: Vector3 = _bone_position(visual, "Wrist.R")
	_check(left.y > head.y + 0.1 and right.y > head.y + 0.1, "Both surrender hands are clearly above the head")
	_check(left.x > head.x + 0.15 and right.x < head.x - 0.15, "Surrender arms stay on their own sides instead of crossing")
	entity.status = "READY"
	entity.stunned = 0.0
	Actor.sync(visual, entity, [], 4.0, 0.0, false)
	Actor.sync(visual, entity, [], 4.2, 0.0, false)
	var normal: Dictionary = _actor()
	Actor.sync(normal, entity, [], 4.2, 0.0, false)
	_check(visual.weapon.visible and _same(_poses(visual), _poses(normal)), "Recovery restores the normal armed pose without accumulated offsets")
	entity.status = "STUNNED"
	entity.stunned = 1.0
	entity.hp = 0.0
	Actor.sync(visual, entity, [], 5.0, 0.0, false)
	_check(str(visual.clip).begins_with("Death:"), "Incapacitation overrides a remaining stun timer")
