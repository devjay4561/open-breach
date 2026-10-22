extends SceneTree

const Actor = preload("res://scripts/actor_visual.gd")
const Contact = preload("res://scripts/pose_contact.gd")
var checks := 0
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
	return {"id":"alpha", "hp":100.0, "status":"READY", "weapon":"standard", "facing":0.0, "aim_facing":0.0, "move_facing":0.0, "travel_distance":0.0, "commands":[]}

func _legacy_sample(visual: Dictionary, clip: String, time: float, loop: bool) -> void:
	var animation: Animation = visual.player.get_animation(clip)
	visual.skeleton.reset_bone_poses()
	visual.player.play(clip)
	visual.player.seek(fposmod(time, animation.length) if loop else clampf(time, 0.0, animation.length - 0.0001), true)
	visual.player.advance(0.0)
	visual.skeleton.force_update_all_bone_transforms()

func _same_pose(a: Dictionary, b: Dictionary) -> bool:
	var sk_a: Skeleton3D = a.skeleton
	var sk_b: Skeleton3D = b.skeleton
	for bone: int in range(sk_a.get_bone_count()):
		if not sk_a.get_bone_pose(bone).is_equal_approx(sk_b.get_bone_pose(bone)) or not sk_a.get_bone_global_pose(bone).is_equal_approx(sk_b.get_bone_global_pose(bone)):
			return false
	return true

func _socket(visual: Dictionary, clip: String) -> void:
	var attachment: int = visual.left_wrist if clip.ends_with("RifleThrow") or clip.contains("DoorOpen") else visual.wrist
	var bind: Transform3D = visual.left_weapon_bind if attachment == visual.left_wrist else visual.weapon_bind
	visual.weapon.transform = visual.model.global_transform.affine_inverse() * visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(attachment) * bind

func _sample_equivalence() -> void:
	var legacy := _actor()
	var candidate := _actor()
	_check(legacy.skeleton.get_bone_count() == 62, "Sampling comparison covers every one of the 62 authored bones")
	var clips: PackedStringArray = legacy.player.get_animation_list()
	# Revisit clips in reverse order too, leaving the previous clip active.
	for pass_index: int in range(2):
		for index: int in range(clips.size()):
			var clip: String = clips[index if pass_index == 0 else clips.size() - index - 1]
			var animation: Animation = legacy.player.get_animation(clip)
			for loop: bool in [false, true]:
				for fraction: float in [-0.17, 0.0, 0.001, 0.13, 0.49, 0.87, 0.99999, 1.0, 1.37]:
					var sample: float = fraction * animation.length
					_legacy_sample(legacy, clip, sample, loop)
					Actor._sample(candidate.player, candidate.skeleton, clip, sample, loop)
					_socket(legacy, clip)
					_socket(candidate, clip)
					_check(_same_pose(legacy, candidate), "%s pass %d sample %.5f loop %s: seek(true) equals seek+advance for all local/global bones" % [clip, pass_index, fraction, loop])
					_check(legacy.muzzle.global_transform.is_equal_approx(candidate.muzzle.global_transform), "%s sample %.5f: seek-only preserves the animated muzzle" % [clip, fraction])
	# Alternate unrelated clips at every sample, rather than only at clip boundaries.
	for index: int in range(clips.size() * 3):
		var clip: String = clips[(index * 7) % clips.size()]
		var sample: float = (index % 5) * 0.21
		_legacy_sample(legacy, clip, sample, false)
		Actor._sample(candidate.player, candidate.skeleton, clip, sample, false)
		_socket(legacy, clip)
		_socket(candidate, clip)
		_check(_same_pose(legacy, candidate) and legacy.muzzle.global_transform.is_equal_approx(candidate.muzzle.global_transform), "Rapid clip switch %d preserves all bones and muzzle" % index)

func _bone_caches() -> void:
	var visual := _actor()
	var sk: Skeleton3D = visual.skeleton
	var expected_upper: Array[int] = []
	var expected_lower: Array[int] = []
	var expected_door: Array[int] = []
	for bone: int in range(sk.get_bone_count()):
		var ancestor: int = bone
		while ancestor >= 0 and ancestor != sk.find_bone(Actor.UPPER_ROOT):
			ancestor = sk.get_bone_parent(ancestor)
		if ancestor == sk.find_bone(Actor.UPPER_ROOT):
			expected_upper.append(bone)
		else:
			expected_lower.append(bone)
		if bone in expected_lower or sk.get_bone_name(bone).ends_with(".L"):
			expected_door.append(bone)
	_check(visual.upper == expected_upper and visual.lower == expected_lower, "Cached layers partition every bone by its original upper-body ancestor")
	_check(visual.door_support_bones == expected_door, "Cached door support keeps the original lower-body and left-side rule")
	var uncached := _actor()
	for side: String in ["L", "R"]:
		_check(visual.arms[side] == PackedInt32Array([sk.find_bone("UpperArm." + side), sk.find_bone("LowerArm." + side), sk.find_bone("Wrist." + side)]), side + " cached arm indices match name lookups")
		for weight: float in [0.0, 0.2, 0.7, 1.0]:
			Actor._sample(visual.player, sk, visual.names.RifleIdle, weight, true)
			Actor._sample(uncached.player, uncached.skeleton, uncached.names.RifleIdle, weight, true)
			var target: Transform3D = sk.global_transform * sk.get_bone_global_pose(visual.arms[side][2])
			target.origin += Vector3(0.05, -0.02, 0.03)
			target.basis = Basis(Vector3.UP, 0.15) * target.basis
			var cached_error: float = Contact.reach_transform(sk, side, target, weight, visual.arms[side])
			var original_error: float = Contact.reach_transform(uncached.skeleton, side, target, weight)
			_check(is_equal_approx(cached_error, original_error) and _same_pose(visual, uncached), "%s weight %.1f: cached IK indices preserve all transforms and contact error" % [side, weight])
	_check(Contact.reach(sk, "L", Vector3.ZERO, 1.0, PackedInt32Array([-1, -1, -1])) == INF, "Missing cached bones preserve the existing invalid-rig result")

func _sync_pair(cached: Dictionary, uncached: Dictionary, entity: Dictionary, events: Array, clock: float, movement: float = 0.0, reduced_motion: bool = false, interaction: Dictionary = {}) -> void:
	# Recompute a second actor every time to exercise cache invalidation against
	# the same full pose path, including frozen frames and nested input mutations.
	uncached.erase("_settled_death_inputs")
	uncached.erase("_frozen_inputs")
	Actor.sync(cached, entity, events, clock, movement, reduced_motion, interaction)
	Actor.sync(uncached, entity, events, clock, movement, reduced_motion, interaction)
	_check(_same_pose(cached, uncached), "Cached and recomputed actors keep every local/global bone at clock %.3f" % clock)
	_check(cached.muzzle.global_transform.is_equal_approx(uncached.muzzle.global_transform) and cached.weapon.visible == uncached.weapon.visible, "Cached and recomputed actors keep muzzle and weapon visibility at clock %.3f" % clock)
	_check(cached.clip == uncached.clip and cached.base_clip == uncached.base_clip and cached.last_clock == uncached.last_clock and cached.death_time == uncached.death_time, "Pose reuse retains replay and clip metadata at clock %.3f" % clock)

func _settled_death() -> void:
	var cached := _actor()
	var uncached := _actor()
	var entity := _entity()
	var events: Array = [{"type":"INCAPACITATED", "entity_id":"alpha", "time":0.0}]
	_sync_pair(cached, uncached, entity, [], 0.0)
	entity.hp = 0.0
	entity.status = "INCAPACITATED"
	_sync_pair(cached, uncached, entity, events, 0.1)
	_sync_pair(cached, uncached, entity, events, 0.3)
	var animation: Animation = cached.player.get_animation(cached.names.Death)
	var end: float = animation.length + 1.0
	_sync_pair(cached, uncached, entity, events, end)
	var saved: Array[Transform3D] = cached._authored_pose
	for offset: float in [0.1, 0.2, 0.5, 1.0]:
		_sync_pair(cached, uncached, entity, [], end + offset)
		_check(is_same(saved, cached._authored_pose), "Completed death keeps the existing authored snapshot while the clock advances")
	# Values are intentionally changed in place, including nested dictionaries.
	entity.commands.append({"type":"WAIT", "remaining":1.0})
	_sync_pair(cached, uncached, entity, [], end + 1.1)
	_check(not is_same(saved, cached._authored_pose), "A nested entity mutation invalidates the completed pose")
	saved = cached._authored_pose
	entity.commands[0].remaining = 0.5
	_sync_pair(cached, uncached, entity, [], end + 1.2)
	_check(not is_same(saved, cached._authored_pose), "Editing a nested command does not compare only dictionary identity")
	entity.status = "ARRESTED"
	_sync_pair(cached, uncached, entity, [], end + 1.2)
	_check(not cached.weapon.visible, "Controlled status at a frozen clock still hides the weapon")
	entity.status = "INCAPACITATED"
	_sync_pair(cached, uncached, entity, [], end + 1.2)
	_check(cached.weapon.visible, "Leaving controlled status at the same clock restores the weapon")
	var body: Node3D = cached.model.get_parent()
	var reference_body: Node3D = uncached.model.get_parent()
	body.position = Vector3(2.0, 0.4, -3.0)
	body.rotation.y = 0.63
	body.scale = Vector3(1.1, 0.9, 1.2)
	reference_body.transform = body.transform
	_sync_pair(cached, uncached, entity, [], end + 1.3)
	_sync_pair(cached, uncached, entity, [], end + 1.4)
	var interaction: Dictionary = {"handle":Vector3(1.0, 1.1, 2.0), "progress":0.3}
	_sync_pair(cached, uncached, entity, [], end + 1.5, 0.0, false, interaction)
	interaction.progress = 0.8
	_sync_pair(cached, uncached, entity, [], end + 1.5, 0.0, false, interaction)
	_sync_pair(cached, uncached, entity, [], end + 1.6, 0.1, true)
	_sync_pair(cached, uncached, entity, [], end + 1.8)
	events[0].time = end + 1.75
	_sync_pair(cached, uncached, entity, events, end + 1.8)
	_check(not cached.has("_settled_death_inputs"), "A changed incapacitation event resumes the unfinished death clip")
	entity.hp = 100.0
	entity.status = "READY"
	entity.commands = []
	_sync_pair(cached, uncached, entity, [], 0.0)
	_check(not cached.has("_settled_death_inputs") and cached.death_time < 0.0, "Rewind and revival clear the completed death cache")
	_sync_pair(cached, uncached, entity, [], 0.1)
	entity.hp = 0.0
	entity.status = "INCAPACITATED"
	_sync_pair(cached, uncached, entity, [], end + 3.0)
	_sync_pair(cached, uncached, entity, [], end + 3.1)
	_sync_pair(cached, uncached, entity, [], end + 3.2)
	_check(cached.has("_settled_death_inputs"), "Seeking to an already-dead actor can settle and reuse the final pose")
	entity.hp = 100.0
	entity.status = "READY"
	_sync_pair(cached, uncached, entity, [], end + 3.3)
	_check(not cached.has("_settled_death_inputs"), "Forward-time revival clears the cache before the actor animates again")

func _transition_snapshots() -> void:
	var visual := _actor()
	var entity := _entity()
	Actor.sync(visual, entity, [], 0.0, 0.0, false)
	var prior: Array[Transform3D] = visual._authored_pose
	var snapshot: Array[Transform3D] = prior.duplicate()
	entity.status = "MOVING"
	entity.travel_distance = 0.4
	Actor.sync(visual, entity, [], 0.2, 0.1, false)
	_check(is_same(prior, visual.blend_from) and is_same(prior, visual.lower_from), "Upper and lower transitions share the immutable previous authored array")
	entity.travel_distance = 0.45
	entity.stance = "crouched"
	entity.body_facing = 0.0
	entity.aim_facing = 0.2
	Actor.sync(visual, entity, [], 0.23, 0.05, false)
	_check(prior == snapshot and visual.blend_from == snapshot and visual.lower_from == snapshot, "Subsequent sampling, crouch and aim never mutate shared transition snapshots")

func _run() -> void:
	_sample_equivalence()
	_bone_caches()
	_settled_death()
	_transition_snapshots()
	for body: Node3D in bodies:
		body.queue_free()
	await process_frame
	await process_frame
	print("BREACH_RENDER_POSE_OPTIMIZATION_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
