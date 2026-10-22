class_name BreachActorVisual
extends RefCounted
## CC0 Quaternius/KayKit clips and original pose adaptations. Gameplay remains simulation-owned.
const MODEL = preload("res://assets/characters/combat-swat-gear.glb")
const EQUIPMENT_MODELS = {
 "standard":preload("res://assets/equipment/tern_c1.glb"), "suppressed":preload("res://assets/equipment/tern_c1.glb"),
 "light":preload("res://assets/equipment/mica_s2.glb"), "shotgun":preload("res://assets/equipment/flint_b1.glb"), "pico_p1":preload("res://assets/equipment/pico_p1.glb"),
 "veil_v1":preload("res://assets/equipment/veil_v1.glb"), "frame_v2":preload("res://assets/equipment/frame_v2.glb"), "swift_v3":preload("res://assets/equipment/swift_v3.glb"), "bastion_v4":preload("res://assets/equipment/bastion_v4.glb"),
 "mask_h0":preload("res://assets/equipment/mask_h0.glb"), "crown_h1":preload("res://assets/equipment/crown_h1.glb"), "crown_h2":preload("res://assets/equipment/crown_h2.glb"),
 "dot":preload("res://assets/equipment/dot.glb"), "scope":preload("res://assets/equipment/scope.glb"), "suppressor":preload("res://assets/equipment/suppressor.glb"), "extended_mag":preload("res://assets/equipment/extended_mag.glb"),
 "camera":preload("res://assets/equipment/probe_c1.glb"), "stun":preload("res://assets/equipment/flare_f1.glb"), "smoke":preload("res://assets/equipment/haze_s1.glb"), "breach":preload("res://assets/equipment/knock_b1.glb")
}
const MUZZLES = {"standard":Vector3(0.60050,0.10617,0.00028),"suppressed":Vector3(0.60050,0.10617,0.00028),"light":Vector3(0.32914,0.07326,-0.00050),"shotgun":Vector3(0.75955,0.03794,-0.00025),"pico_p1":Vector3(0.18334,0.06932,0.0)}
const WEAPON_LENGTHS = {"standard":0.86,"suppressed":0.86,"light":0.62,"shotgun":1.02,"pico_p1":0.23}
const HEAD_CENTER = Vector3(-0.0003438,1.587261,0.0430834)
const ARMOR_COLORS = {"veil_v1":Color("394b42"),"frame_v2":Color("383e3c"),"swift_v3":Color("85734f"),"bastion_v4":Color("53613e")}
const EquipmentCatalog = preload("res://scripts/equipment_catalog.gd")
const PoseContact = preload("res://scripts/pose_contact.gd")
const Gait = preload("res://scripts/locomotion_profile.gd")
const TURN_DURATION := 0.75
# Keep aligned with world_view.gd TRACER_TRAVEL; no runtime dependency.
const HIT_REACTION_DELAY := 0.05
# Measured from the original clip root displacement after retarget scale.
const STRIDES = Gait.STRIDES
const UPPER_ROOT := "Abdomen"

static func create(parent: Node3D, hostile: bool, _outline_color: Color = Color(0.0, 0.0, 0.0, 0.0)) -> Dictionary:
	var model: Node3D = MODEL.instantiate()
	parent.add_child(model)
	model.rotation.y = PI * 0.5
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var body_meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	var outline_rims: Array[StandardMaterial3D] = []
	var cloth_materials: Array = []
	var hit_materials: Array = []
	for mesh: MeshInstance3D in body_meshes:
		for surface: int in range(mesh.mesh.get_surface_count()):
			var source: Material = mesh.get_active_material(surface)
			if not source is StandardMaterial3D:
				continue
			var mat: StandardMaterial3D = source.duplicate()
			mat.roughness = 0.95
			mat.metallic = 0.0
			mat.albedo_color = mat.albedo_color.lerp(Color("74634f") if hostile else Color("51635e"), 0.42)
			mesh.set_surface_override_material(surface, mat)
			var entry := {"material":mat,"base":mat.albedo_color,"rest":mat.albedo_color}
			hit_materials.append(entry)
			if not mat.resource_name.to_lower().contains("skin") and not mat.resource_name.to_lower().contains("visor"):
				cloth_materials.append(entry)
	# Team discs carry identity; keep the recolor contract without a second skin pass.
	var names: Dictionary = {}
	for name: String in player.get_animation_list():
		names[name.get_slice("|", name.get_slice_count("|") - 1)] = name
	var upper: Array[int] = []
	var lower: Array[int] = []
	var door_support_bones: Array[int] = []
	var upper_root: int = skeleton.find_bone(UPPER_ROOT)
	for bone: int in range(skeleton.get_bone_count()):
		var ancestor := bone
		while ancestor >= 0 and ancestor != upper_root:
			ancestor = skeleton.get_bone_parent(ancestor)
		if ancestor == upper_root:
			upper.append(bone)
		else:
			lower.append(bone)
		if ancestor != upper_root or skeleton.get_bone_name(bone).ends_with(".L"):
			door_support_bones.append(bone)
	var arms: Dictionary = {}
	for side: String in ["L", "R"]:
		arms[side] = PackedInt32Array([skeleton.find_bone("UpperArm." + side), skeleton.find_bone("LowerArm." + side), skeleton.find_bone("Wrist." + side)])
	_sample(player, skeleton, names.get("RifleIdle", "RifleIdle"), 0.0, false)
	var weapon := Node3D.new()
	weapon.name = "EquippedWeapon"
	model.add_child(weapon)
	weapon.rotation.y = -PI * 0.5
	var wrist: int = skeleton.find_bone("Wrist.R")
	var bind: Transform3D = model.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(wrist)
	weapon.position = bind.origin + Vector3(0, 0.045, 0.0)
	var left_wrist: int = skeleton.find_bone("Wrist.L")
	var left_bind: Transform3D = model.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(left_wrist)
	var door_weapon_pose: Transform3D = weapon.transform
	door_weapon_pose.basis = Basis(Vector3.RIGHT, deg_to_rad(50.0)) * door_weapon_pose.basis
	door_weapon_pose.origin = left_bind.origin + Vector3(0.0, -0.14, -0.22)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.43, 0.035, 0.0)
	weapon.add_child(muzzle)
	var visual: Dictionary = {"model":model,"player":player,"skeleton":skeleton,"names":names,"upper":upper,"lower":lower,"upper_root":upper_root,"door_support_bones":door_support_bones,"arms":arms,"weapon":weapon,"muzzle":muzzle,"wrist":wrist,"weapon_bind":bind.affine_inverse()*weapon.transform,"left_wrist":left_wrist,"left_weapon_bind":left_bind.affine_inverse()*weapon.transform,"support_bind":weapon.transform.affine_inverse()*left_bind,"door_weapon_pose":door_weapon_pose,"contact_error":0.0,"support_error":0.0,"contact_weight":0.0,"last_throw":-100.0,"clip":"","base_clip":"","gait_phase":0.0,"last_clock":-1.0,"last_shot":-100.0,"last_hit":-100.0,"death_time":-1.0,"move_until":-1.0,"last_distance":0.0,"blend_from":[],"blend_start":-1.0,"lower_key":"","lower_from":[],"lower_start":-1.0,"lower_duration":0.12,"outline_rims":outline_rims,"cloth_materials":cloth_materials,"hostile":hostile,"default_support_bind":weapon.transform.affine_inverse()*left_bind}
	visual["hit_materials"] = hit_materials
	visual["last_hit_protection"] = ""
	visual["last_hit_direction"] = Vector3.ZERO
	_create_gear_mounts(visual)
	_sync_loadout(visual, {"weapon":"standard"})
	_sync_gear_pose(visual)
	return visual

static func _sync_events(visual: Dictionary, entity: Dictionary, events: Array, clock: float, rescan: bool) -> void:
	# Playback seq rows are immutable: live sends batches, settle/seek a window.
	# Match the consumed boundary by value so copied/sliding windows also work.
	# Frozen edits, rewind and an unmatchable/truncated stream use the old scan.
	var cursor: int = int(visual.get("_event_seq", -1))
	var start := 0
	if not rescan and cursor >= 0 and not events.is_empty() and events[0].has("seq") and events[-1].has("seq"):
		var lo := 0
		var hi := events.size()
		while lo < hi:
			var middle: int = (lo + hi) / 2
			if int(events[middle].get("seq", -1)) <= cursor:
				lo = middle + 1
			else:
				hi = middle
		if int(events[0].seq) > cursor:
			start = 0
		elif lo > 0 and int(events[lo - 1].get("seq", -1)) == cursor and hash(events[lo - 1]) == visual.get("_event_anchor"):
			start = lo
	if start == 0 and not events.is_empty(): cursor = -1
	var ordered := true
	var deferred := false
	var previous: int = int(events[start - 1].get("seq", -1)) if start > 0 else -1
	for index: int in range(start, events.size()):
		var event: Dictionary = events[index]
		var seq: int = int(event.get("seq", -1))
		ordered = ordered and seq > previous
		previous = seq
		var time := float(event.get("time", -100.0))
		if time > clock + 0.001:
			# Keep the cursor before the first future event, even in mixed batches.
			deferred = true
			continue
		if ordered and not deferred:
			cursor = seq
			visual["_event_anchor"] = hash(event)
		if event.get("type", "") == "SHOT":
			if event.get("attacker_id", "") == entity.id:
				visual.last_shot = maxf(visual.last_shot, time)
			if event.get("target_id", "") == entity.id and event.get("hit", false):
				if time >= float(visual.last_hit):
					visual.last_hit = time
					visual["hit_after_shot"] = true
					visual.last_hit_protection = str(event.get("protection", ""))
					visual.last_hit_direction = Vector3.ZERO
					var origin: Array = event.get("from", [])
					var target: Array = event.get("to", [])
					if origin.size() == 2 and target.size() == 2:
						visual.last_hit_direction = Vector3(float(target[0]) - float(origin[0]), 0.0, float(target[1]) - float(origin[1])).normalized()
		elif (event.get("type", "") in ["FLASH_RELEASE", "GRENADE_RELEASED"] or (event.get("type", "") == "STUN" and not event.has("projectile_id"))) and event.get("unit_id", "") == entity.id:
			visual.last_throw = maxf(visual.last_throw, time)
		elif event.get("type", "") == "INCAPACITATED" and event.get("entity_id", "") == entity.id:
			visual.death_time = time
	visual["_event_seq"] = cursor if ordered and (not rescan or not events.is_empty()) else -1

static func _sample(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, time: float, loop: bool) -> void:
	var animation: Animation = player.get_animation(clip)
	if animation == null:
		return
	skeleton.reset_bone_poses()
	player.play(clip)
	player.seek(fposmod(time, animation.length) if loop else clampf(time, 0.0, animation.length - 0.0001), true)
	skeleton.force_update_all_bone_transforms()

static func sync(visual: Dictionary, entity: Dictionary, events: Array, clock: float, movement: float, reduced_motion: bool, interaction: Dictionary = {}) -> void:
	# hash() includes nested values, so in-place command/event edits invalidate
	# a frozen pose without allocating a deep snapshot of every input each frame.
	if clock == float(visual.last_clock):
		var signature: int = hash([entity, events, interaction, movement, reduced_motion, visual.get("hit_delay"), visual.model.global_transform])
		if visual.get("_frozen_inputs", null) == signature:
			return
		visual["_frozen_inputs"] = signature
	else:
		visual.erase("_frozen_inputs")
	_sync_loadout(visual, entity)
	var player: AnimationPlayer = visual.player
	var sk: Skeleton3D = visual.skeleton
	var rewind: bool = clock < float(visual.last_clock)
	var reset_pose: bool = rewind or float(visual.last_clock) < 0.0
	if rewind:
		visual.last_shot = -100.0
		visual.last_hit = -100.0
		visual.erase("hit_after_shot")
		visual.last_hit_protection = ""
		visual.last_hit_direction = Vector3.ZERO
		visual.last_throw = -100.0
		visual.death_time = -1.0
		visual.clip = ""
		visual.move_until = -1.0
		visual.lower_key = ""
		visual.erase("_authored_pose")
	_sync_events(visual, entity, events, clock, reset_pose or clock == float(visual.last_clock))
	var feedback: Dictionary = entity.get("_feedback_hit", {})
	if not feedback.is_empty() and float(feedback.time) >= float(visual.last_hit):
		visual.last_hit = float(feedback.time)
		visual["hit_after_shot"] = bool(feedback.get("after_shot", false))
		visual.last_hit_protection = str(feedback.get("protection", ""))
		visual.last_hit_direction = Vector3.ZERO
	_sync_hit_feedback(visual, clock, reduced_motion)
	if movement > 0.0001 and clock > float(visual.last_clock):
		visual.move_until = clock + 0.1
	var moving: bool = clock < float(visual.move_until) or entity.get("status", "") in ["MOVING", "PATROL"]
	var distance := float(entity.get("travel_distance", float(visual.last_distance) + (movement if clock > float(visual.last_clock) else 0.0)))
	visual.last_distance = distance
	var base: String = Gait.base_clip(entity)
	visual.gait_phase = fposmod(distance / Gait.stride(entity, base), 1.0)
	var alive := float(entity.get("hp", 100.0)) > 0
	var hit_delay: float = _reaction_delay(visual, reduced_motion)
	var hit_age: float = clock - (float(visual.last_hit) + hit_delay)
	var turn_age: float = clock - float(entity.get("turn_started_at", -100.0))
	var turn_delta: float = float(entity.get("turn_delta", 0.0))
	var turning: bool = not moving and not reduced_motion and turn_age >= 0.0 and turn_age < TURN_DURATION and absf(turn_delta) >= deg_to_rad(5.0)
	var turn_clip: String = "RifleTurnRight" if turn_delta > 0.0 else "RifleTurnLeft"
	var clip := "RifleIdle"
	var sample := clock
	var loop := true
	var full_body := false
	var controlled: bool = entity.get("status", "") in ["SURRENDERED", "ARRESTED"]
	var stunned: bool = alive and not controlled and (float(entity.get("stunned", 0.0)) > 0.0 or entity.get("status", "") == "STUNNED")
	var status_pose: String = ("surrender" if controlled else "stun") if alive and (controlled or stunned) else ""
	if not alive:
		if visual.death_time < 0.0:
			visual.death_time = clock - 5.0
		clip = "Death"
		sample = maxf(0.0, clock - (float(visual.death_time) + (hit_delay if float(visual.last_hit) == float(visual.death_time) else 0.0)))
		loop = false
		full_body = true
	elif not status_pose.is_empty():
		# Status poses override weapon actions and use a stable, planted base.
		clip = "RifleIdle"
		sample = 0.0
		loop = false
		full_body = true
	elif entity.get("status", "") == "OPENING" and not interaction.is_empty():
		clip = "DoorOpenOut"
		sample = lerpf(0.10, 0.70, clampf(float(interaction.get("progress", 0.0)), 0.0, 1.0)) * player.get_animation(visual.names[clip]).length
		loop = false
		full_body = true
	elif entity.get("status", "") == "CAMERA":
		clip = "RifleReload"
		sample = 0.28 * player.get_animation(visual.names[clip]).length
		loop = false
		full_body = true
	elif entity.get("status", "") in ["RELOADING", "SWITCHING_WEAPON", "SWITCHING"]:
		clip = "RifleReload"
		loop = false
		full_body = true
		var default_duration: float = 1.4 if entity.get("weapon", "standard") == "light" else (2.4 if entity.get("weapon", "standard") == "shotgun" else (2.2 if entity.get("weapon", "standard") == "suppressed" else 1.8))
		var duration: float = maxf(0.01, float(entity.get("reload_duration", default_duration)))
		var remaining := float(entity.get("reload_remaining", duration))
		for command: Dictionary in entity.get("commands", []):
			if command.get("state", "") != "RUNNING":
				continue
			if command.get("type", "") == "RELOAD":
				remaining = float(command.get("remaining", duration))
			elif command.get("type", "") == "SWITCH_WEAPON":
				var destination: String = str(entity.get("sidearm","pico_p1")) if command.get("args",{}).get("slot","secondary") == "secondary" else str(entity.get("weapon","standard"))
				duration = float(EquipmentCatalog.weapon_stats(destination).get("switch_time",0.35)) * float(entity.get("action_multiplier",1.0))
				remaining = float(command.get("remaining",duration))
		var animation: Animation = player.get_animation(visual.names[clip])
		sample = lerpf(0.30,0.65,clampf(1.0-remaining/duration,0,1)) * animation.length if entity.get("status", "") in ["SWITCHING", "SWITCHING_WEAPON"] else clampf(1.0 - remaining / duration, 0.0, 1.0) * animation.length
	elif entity.get("status", "") == "THROWING" or clock - float(visual.last_throw) < 0.2:
		clip = "RifleThrow"
		full_body = true
		loop = false
		sample = lerpf(0.58, 0.88, clampf((clock - float(visual.last_throw)) / 0.2, 0.0, 1.0)) * player.get_animation(visual.names[clip]).length
		for command: Dictionary in entity.get("commands", []):
			if entity.get("status", "") == "THROWING" and command.get("type", "") in ["THROW_STUN", "THROW_SMOKE", "OPEN_AND_FLASH"] and command.get("state", "") == "RUNNING" and not command.has("projectile_id"):
				var prepare: float = 0.45 * float(entity.get("action_multiplier",1.0))
				if command.get("type", "") != "THROW_SMOKE": prepare *= 1.0+maxf(0.0,float(entity.get("weapon_length",0.86))-0.86)*0.35
				sample = lerpf(0.10, 0.58, clampf(1.0 - float(command.get("remaining", prepare)) / maxf(0.01,prepare), 0.0, 1.0)) * player.get_animation(visual.names[clip]).length
	elif hit_age >= 0.0 and hit_age < 0.30:
		clip = "RifleHit"
		sample = clampf(hit_age / 0.30, 0.0, 1.0) * player.get_animation(visual.names[clip]).length
		loop = false
	elif clock - float(visual.last_shot) < 0.22:
		clip = "RifleFire"
		sample = clampf((clock - float(visual.last_shot)) / 0.22, 0.0, 1.0) * player.get_animation(visual.names[clip]).length
		loop = false
	var lower_clip: String = base if moving and not reduced_motion else (turn_clip if turning else "")
	var death_complete: bool = clip == "Death" and sample >= player.get_animation(visual.names[clip]).length - 0.0001
	var death_inputs: Array = []
	if death_complete:
		death_inputs = [entity, interaction, movement, reduced_motion, visual.model.global_transform, float(visual.death_time), lower_clip]
		if not reset_pose and visual.get("_settled_death_inputs", []) == death_inputs:
			visual.last_clock = clock
			return
	visual.erase("_settled_death_inputs")
	# Authored arrays are replaced each frame; transition snapshots can share them.
	var prior: Array[Transform3D] = []
	if visual.has("_authored_pose"):
		prior = visual._authored_pose
	else:
		for bone: int in range(sk.get_bone_count()):
			prior.append(sk.get_bone_pose(bone))
	var lower: Array[Transform3D] = []
	if not full_body and not lower_clip.is_empty():
		var base_anim: Animation = player.get_animation(visual.names[lower_clip])
		var lower_time: float = float(visual.gait_phase) * base_anim.length if moving else (turn_age / TURN_DURATION) * base_anim.length
		_sample(player, sk, visual.names[lower_clip], lower_time, moving)
		for bone: int in visual.lower:
			lower.append(sk.get_bone_pose(bone))
	var door_support: Array[Transform3D] = []
	if clip.begins_with("DoorOpen"):
		_sample(player, sk, visual.names["RifleIdle"], 0.0, false)
		for bone: int in visual.door_support_bones:
			door_support.append(sk.get_bone_pose(bone))
	_sample(player, sk, visual.names[clip], sample, loop)
	if not door_support.is_empty():
		for index: int in range(visual.door_support_bones.size()):
			sk.set_bone_pose(visual.door_support_bones[index], door_support[index])
	if not lower.is_empty():
		for index: int in range(visual.lower.size()):
			sk.set_bone_pose(visual.lower[index], lower[index])
	if not status_pose.is_empty():
		_apply_status_pose(visual, status_pose, clock, reduced_motion, entity.get("stance", "standing") == "crouched")
	# A direction change must blend the legs too. Fire/hit transitions are a
	# separate layer, so shooting cannot restart or soften an established stride.
	var lower_key: String = "full:" + clip if full_body else (lower_clip if not lower_clip.is_empty() else "stand")
	if not status_pose.is_empty():
		lower_key += ":" + status_pose
	if visual.lower_key != lower_key:
		visual.lower_from = prior
		visual.lower_duration = 0.11 if lower_key == "stand" else 0.14
		visual.lower_start = clock - float(visual.lower_duration) if reset_pose else clock
		visual.lower_key = lower_key
	var key: String = clip + ":" + (lower_clip if not lower_clip.is_empty() else "stand")
	if not status_pose.is_empty():
		key += ":" + status_pose
	if visual.clip != key:
		visual.blend_from = prior
		visual.blend_start = clock - 0.065 if reset_pose else clock
		visual.clip = key
	visual.base_clip = lower_clip if not lower_clip.is_empty() else "RifleIdle"
	var blend := clampf((clock - float(visual.blend_start)) / 0.065, 0.0, 1.0)
	if blend < 1.0 and not rewind and float(visual.last_clock) >= 0.0:
		for bone: int in (range(sk.get_bone_count()) if full_body else visual.upper):
			# Fire/hit layers never reset or damp the locomotion phase.
			sk.set_bone_pose(bone, visual.blend_from[bone].interpolate_with(sk.get_bone_pose(bone), blend))
	if not full_body and not rewind and float(visual.last_clock) >= 0.0:
		var lower_blend: float = smoothstep(0.0, float(visual.lower_duration), clock - float(visual.lower_start))
		if lower_blend < 1.0:
			for bone: int in visual.lower:
				sk.set_bone_pose(bone, visual.lower_from[bone].interpolate_with(sk.get_bone_pose(bone), lower_blend))
	# Cache the pose before procedural stance/aim layers so a transition never
	# lowers an already crouched pelvis or applies yesterday's torso yaw twice.
	var authored_pose: Array[Transform3D] = []
	for bone: int in range(sk.get_bone_count()):
		authored_pose.append(sk.get_bone_pose(bone))
	visual["_authored_pose"] = authored_pose
	# The body catches up during an authored turn step while the upper body
	# remains aimed. All timing comes from replayed simulation metadata.
	var turn_correction: float = 0.0
	if turning and not full_body and not entity.has("body_facing"):
		turn_correction = clampf(turn_delta * (1.0 - smoothstep(0.0, TURN_DURATION, turn_age)), -PI * 0.42, PI * 0.42)
	visual.model.rotation.y = PI * 0.5 + turn_correction
	sk.force_update_all_bone_transforms()
	var relative_aim: float = angle_difference(float(entity.get("body_facing", entity.get("aim_facing", entity.get("facing", 0.0)))), float(entity.get("aim_facing", entity.get("facing", 0.0))))
	var upper_yaw: float = -relative_aim - turn_correction
	if absf(upper_yaw) > 0.00001 and not full_body:
		var upper_root: int = visual.upper_root
		var pose: Transform3D = sk.global_transform * sk.get_bone_global_pose(upper_root)
		pose.basis = Basis(Vector3.UP, upper_yaw) * pose.basis
		sk.set_bone_global_pose(upper_root, sk.global_transform.affine_inverse() * pose)
		sk.force_update_all_bone_transforms()
	if alive and entity.get("stance", "standing") == "crouched":
		_apply_crouched_pose(sk, float(entity.get("body_facing", entity.get("facing", 0.0))))
	# The authored grenade throw uses the right hand; the left supports the rifle.
	var free_right_hand: bool = stunned or clip == "RifleThrow" or clip.begins_with("DoorOpen") or bool(visual.get("camera_active",false))
	var attachment: int = int(visual.left_wrist) if free_right_hand else int(visual.wrist)
	var attachment_bind: Transform3D = visual.left_weapon_bind if free_right_hand else visual.weapon_bind
	var wrist_pose: Transform3D = visual.model.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(attachment)
	visual.weapon.transform = wrist_pose * attachment_bind
	visual.contact_error = 0.0
	visual.support_error = 0.0
	visual.contact_weight = 0.0
	if alive and status_pose.is_empty() and clip in ["RifleIdle", "RifleFire", "RifleHit"]:
		var support: Transform3D = visual.weapon.global_transform * visual.support_bind
		visual.contact_error = PoseContact.reach_transform(sk, "L", support, 1.0, visual.arms.L)
		visual.support_error = visual.contact_error
	if stunned:
		# Carry the rifle muzzle-down in the left hand; the right shields the head.
		var carried: Transform3D = visual.door_weapon_pose
		carried.origin = wrist_pose.origin - carried.basis * visual.support_bind.origin
		visual.weapon.transform = carried
		visual.support_error = PoseContact.reach_transform(sk, "L", visual.weapon.global_transform * visual.support_bind, 1.0, visual.arms.L)
	if clip.begins_with("DoorOpen") and interaction.has("handle"):
		var progress: float = float(interaction.get("progress", 0.0))
		# Keep the prop carried against the body while the authored right arm
		# reaches the latch; an unconstrained left wrist otherwise sweeps the rifle
		# above the head when the source door clip leans and twists the torso.
		var carry: float = smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.72, 0.98, progress))
		var carried: Transform3D = visual.door_weapon_pose
		# Every gun now has its own real foregrip socket. Keep that socket on
		# the authored supporting wrist as the torso leans, rather than using
		# the old rifle-center offset (which can exceed the arm's reach).
		carried.origin = wrist_pose.origin + Vector3(0.0,-0.14,-0.06) - carried.basis * visual.support_bind.origin
		visual.weapon.transform = visual.weapon.transform.interpolate_with(carried, carry)
		var support: Transform3D = visual.weapon.global_transform * visual.support_bind
		visual.support_error = PoseContact.reach_transform(sk, "L", support, 1.0, visual.arms.L)
		var contact_weight: float = smoothstep(0.0, 0.08, progress) * (1.0 - smoothstep(0.24, 0.40, progress))
		visual.contact_weight = contact_weight
		visual.contact_error = PoseContact.reach(sk, "R", interaction.handle, contact_weight, visual.arms.R) if contact_weight > 0.001 else 0.0
	visual.weapon.visible = not controlled
	_sync_gear_pose(visual)
	visual.last_clock = clock
	if death_complete and blend >= 1.0:
		death_inputs[4] = visual.model.global_transform
		visual["_settled_death_inputs"] = death_inputs.duplicate(true)

static func _reaction_delay(visual: Dictionary, reduced_motion: bool) -> float:
	return float(visual.get("hit_delay", HIT_REACTION_DELAY * (0.7 if reduced_motion else 1.0))) if bool(visual.get("hit_after_shot", true)) else 0.0

static func _sync_hit_feedback(visual: Dictionary, clock: float, reduced_motion: bool) -> void:
	var delay: float = _reaction_delay(visual, reduced_motion)
	var age: float = clock - (float(visual.last_hit) + delay)
	var weight: float = 1.0 - clampf(age / 0.08, 0.0, 1.0) if age >= 0.0 else 0.0
	weight *= 0.10 if reduced_motion else 0.85
	var punch: float = pow(1.0 - clampf(age / 0.10, 0.0, 1.0), 2.0) if age >= 0.0 and not reduced_motion else 0.0
	var previous: Dictionary = visual.get("_hit_feedback", {"weight":0.0,"punch":0.0})
	if weight == 0.0 and punch == 0.0 and float(previous.weight) == 0.0 and float(previous.punch) == 0.0:
		return
	var tint := Color("eef7ff") if bool(visual.hostile) else Color("ffb0a3")
	if visual.last_hit_protection == "blocked": tint = Color("8faec5")
	if weight != float(previous.weight) or (weight > 0.0 and tint != previous.get("tint")):
		for entry: Dictionary in visual.hit_materials:
			entry.material.albedo_color = entry.rest.lerp(tint, weight)
	visual["_hit_feedback"] = {"weight":weight,"tint":tint,"punch":punch}
	var direction: Vector3 = visual.last_hit_direction
	var parent: Node3D = visual.model.get_parent()
	visual.model.position = parent.global_basis.inverse() * direction * (0.055 * punch)

static func _apply_status_pose(visual: Dictionary, pose_name: String, clock: float, reduced_motion: bool, crouched: bool) -> void:
	var sk: Skeleton3D = visual.skeleton
	var model: Node3D = visual.model
	if pose_name == "stun":
		var forward: Vector3 = model.global_transform.basis * Vector3.BACK
		if not crouched:
			_apply_crouched_pose(sk, atan2(forward.z, forward.x), 0.14)
		var abdomen: int = int(visual.upper_root)
		var torso: Transform3D = sk.global_transform * sk.get_bone_global_pose(abdomen)
		var sway: float = 0.0 if reduced_motion else sin(clock * 5.0) * 0.035
		torso.basis = Basis(forward.normalized(), sway) * Basis((model.global_transform.basis * Vector3.RIGHT).normalized(), 0.45) * torso.basis
		sk.set_bone_global_pose(abdomen, sk.global_transform.affine_inverse() * torso)
		sk.force_update_all_bone_transforms()
		var head: Vector3 = model.to_local(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin)
		var shoulder: Vector3 = model.to_local(sk.global_transform * sk.get_bone_global_pose(visual.arms.L[0]).origin)
		PoseContact.reach(sk, "R", model.to_global(head + Vector3(-0.16, 0.02, 0.08)), 1.0, visual.arms.R)
		PoseContact.reach(sk, "L", model.to_global(shoulder + Vector3(0.10, -0.34, 0.05)), 1.0, visual.arms.L)
	else:
		# Model-local left is +X. Keep each hand on its own side and above the head.
		for side: String in ["L", "R"]:
			var shoulder: Vector3 = model.to_local(sk.global_transform * sk.get_bone_global_pose(visual.arms[side][0]).origin)
			var target: Vector3 = shoulder + Vector3(0.12 if side == "L" else -0.12, 0.34, 0.04)
			PoseContact.reach(sk, side, model.to_global(target), 1.0, visual.arms[side])

static func _apply_crouched_pose(sk: Skeleton3D, body_facing: float, depth: float = 0.46) -> void:
	# Lower the pelvis and solve the legs back to their authored foot contacts.
	# This is a visual pose layer; simulation heights remain in SpatialProfile.
	var hips: int = sk.find_bone("Hips")
	if hips < 0:
		return
	var feet: Dictionary = {}
	for side: String in ["L", "R"]:
		var foot: int = sk.find_bone("Foot." + side)
		if foot >= 0:
			feet[side] = sk.global_transform * sk.get_bone_global_pose(foot)
	var pose: Transform3D = sk.global_transform * sk.get_bone_global_pose(hips)
	pose.origin.y -= depth
	sk.set_bone_global_pose(hips, sk.global_transform.affine_inverse() * pose)
	sk.force_update_all_bone_transforms()
	var forward := Vector3(cos(body_facing), 0.0, sin(body_facing))
	for side: String in feet:
		_plant_crouched_foot(sk, side, feet[side], forward)

static func _plant_crouched_foot(sk: Skeleton3D, side: String, world_target: Transform3D, forward: Vector3) -> void:
	var upper: int = sk.find_bone("UpperLeg." + side)
	var lower: int = sk.find_bone("LowerLeg." + side)
	var foot: int = sk.find_bone("Foot." + side)
	if upper < 0 or lower < 0 or foot < 0:
		return
	var a: Transform3D = sk.get_bone_global_pose(upper)
	var b: Transform3D = sk.get_bone_global_pose(lower)
	var c: Transform3D = sk.get_bone_global_pose(foot)
	var target: Vector3 = sk.global_transform.affine_inverse() * world_target.origin
	var first: float = a.origin.distance_to(b.origin)
	var second: float = b.origin.distance_to(c.origin)
	var direction: Vector3 = (target - a.origin).normalized()
	var distance: float = clampf(a.origin.distance_to(target), absf(first - second) + (first + second) * 0.0001, (first + second) * 0.9999)
	if first <= 0.000001 or second <= 0.000001:
		return
	var local_forward: Vector3 = sk.global_transform.basis.inverse() * forward
	var bend: Vector3 = local_forward - direction * local_forward.dot(direction)
	if bend.length_squared() < 0.000001:
		bend = direction.cross(Vector3.RIGHT)
	var along: float = (first * first + distance * distance - second * second) / (2.0 * distance)
	var knee: Vector3 = a.origin + direction * along + bend.normalized() * sqrt(maxf(0.0, first * first - along * along))
	a.basis = Basis(Quaternion((b.origin - a.origin).normalized(), (knee - a.origin).normalized())) * a.basis
	sk.set_bone_global_pose(upper, a)
	sk.force_update_all_bone_transforms()
	b = sk.get_bone_global_pose(lower)
	c = sk.get_bone_global_pose(foot)
	b.basis = Basis(Quaternion((c.origin - b.origin).normalized(), (target - b.origin).normalized())) * b.basis
	sk.set_bone_global_pose(lower, b)
	sk.force_update_all_bone_transforms()
	c = sk.get_bone_global_pose(foot)
	c.basis = sk.global_transform.basis.inverse() * world_target.basis
	sk.set_bone_global_pose(foot, c)
	sk.force_update_all_bone_transforms()

static func _create_gear_mounts(visual: Dictionary) -> void:
	var sk: Skeleton3D = visual.skeleton
	visual["gear_mounts"] = {}
	for spec: Array in [["helmet","Head",HEAD_CENTER],["armor","Chest",Vector3(0.0,1.24,0.05)],["holster","Hips",Vector3(-0.22,0.88,0.03)],["tool","Hips",Vector3(0.22,0.99,0.07)]]:
		var node := Node3D.new()
		node.name = str(spec[0]).capitalize() + "Mount"
		visual.model.add_child(node)
		var bone: int = sk.find_bone(str(spec[1]))
		var rest: Transform3D = visual.model.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_rest(bone)
		var desired := Transform3D(Basis.IDENTITY, spec[2])
		visual.gear_mounts[spec[0]] = {"node":node,"bone":bone,"bind":rest.affine_inverse()*desired}
	var prop := Node3D.new()
	prop.name = "HandTool"
	visual.model.add_child(prop)
	visual["hand_tool"] = prop

static func _clear_prop(node: Node3D, keep: Node = null) -> void:
	for child: Node in node.get_children():
		if child == keep:
			continue
		node.remove_child(child)
		child.queue_free()

static func _prop(parent: Node3D, id: String) -> Node3D:
	var resource: PackedScene = EQUIPMENT_MODELS.get(id, EQUIPMENT_MODELS.standard)
	var result: Node3D = resource.instantiate()
	result.name = id
	parent.add_child(result)
	return result

static func _sync_loadout(visual: Dictionary, entity: Dictionary) -> void:
	var primary: String = str(entity.get("weapon", "standard"))
	var current: String = str(entity.get("current_weapon", "pico_p1" if entity.get("active_weapon", "primary") == "secondary" else primary))
	if not MUZZLES.has(current):
		current = "standard"
	var armor: String = str(entity.get("armor", "frame_v2"))
	if armor != "none" and not ARMOR_COLORS.has(armor):
		armor = "frame_v2"
	var helmet: String = str(entity.get("helmet", "crown_h1"))
	if helmet not in ["none", "crown_h1", "crown_h2"]:
		helmet = "crown_h1"
	var attachments: Array = entity.get("attachments", [])
	var appearance: Dictionary = entity.get("appearance", {})
	var tool_value: Variant = entity.get("equipment", "stun")
	var tool: String = "stun"
	if tool_value is String:
		tool = tool_value
	elif tool_value is Dictionary:
		for candidate: String in ["probe_c1", "breach", "smoke", "stun"]:
			if int(tool_value.get(candidate,0)) > 0:
				tool = "camera" if candidate == "probe_c1" else candidate
				break
	if tool not in ["stun", "smoke", "breach", "camera"]:
		tool = "stun"
	visual["hand_tool_active"] = _preparing_throw(entity)
	visual["camera_active"] = entity.get("status", "") == "CAMERA"
	var signature: Array = [primary,current,armor,helmet,attachments,appearance,tool,entity.get("sidearm", "pico_p1"),entity.get("status", "") == "CAMERA",_throwing_smoke(entity)]
	if visual.get("gear_signature", []) == signature:
		return
	visual["gear_signature"] = signature.duplicate(true)
	visual["equipped_weapon"] = current
	visual["equipped_armor"] = armor
	visual["equipped_helmet"] = helmet
	_clear_prop(visual.weapon, visual.muzzle)
	_prop(visual.weapon, current)
	visual.muzzle.position = MUZZLES[current]
	var effective_attachments: Array = attachments.duplicate() if current != "pico_p1" else []
	if current == "suppressed" and not effective_attachments.has("suppressor"):
		effective_attachments.append("suppressor")
	for item: String in effective_attachments:
		if item not in ["dot", "scope", "suppressor", "extended_mag"]:
			continue
		var attachment := _prop(visual.weapon, item)
		match item:
			"suppressor":
				attachment.position = MUZZLES[current]
				visual.muzzle.position.x += 0.20
			"dot": attachment.position = Vector3(0.02,0.13,0)
			"scope": attachment.position = Vector3(0.06,0.13,0)
			"extended_mag": attachment.position = Vector3(-0.005,-0.035,0)
	var support: Transform3D = visual.default_support_bind
	support.origin = Vector3(float(MUZZLES[current].x)*0.30, float(MUZZLES[current].y)-0.045,0.0)
	if current == "pico_p1":
		support.origin = Vector3(-0.016,-0.015,0.024)
	visual.support_bind = support
	for id: String in ["armor", "helmet", "holster", "tool"]:
		_clear_prop(visual.gear_mounts[id].node)
	if armor != "none":
		var carrier := _prop(visual.gear_mounts.armor.node, armor)
		_tint_equipment(carrier,ARMOR_COLORS[armor])
	_prop(visual.gear_mounts.helmet.node, "mask_h0" if helmet == "none" else helmet)
	# Show the inactive sidearm at the hip, and carry the primary on the back
	# during a pistol switch. Replayed current_weapon drives the same change.
	if not str(entity.get("sidearm", "pico_p1")).is_empty():
		var holstered := _prop(visual.gear_mounts.holster.node, "pico_p1" if current != "pico_p1" else primary)
		holstered.rotation.z = -PI * 0.5
		if current == "pico_p1":
			holstered.position = Vector3(0.10,0.10,-0.15)
	_prop(visual.gear_mounts.tool.node, tool)
	_clear_prop(visual.hand_tool)
	_prop(visual.hand_tool, "camera" if entity.get("status", "") == "CAMERA" else ("smoke" if str(entity.get("status", "")) == "THROWING" and _throwing_smoke(entity) else "stun"))
	visual["camera_active"] = entity.get("status", "") == "CAMERA"
	var color := Color.from_string(str(appearance.get("color", "#51635e")), Color("51635e"))
	if bool(visual.hostile):
		color = Color("74634f")
	for entry: Dictionary in visual.cloth_materials:
		var base: Color = entry.base
		entry.material.albedo_color = base.lerp(color, 0.60)
		entry.rest = entry.material.albedo_color
	visual["_hit_feedback"] = {"weight":-1.0,"punch":1.0}
	# An original flat identification patch moves with the selected carrier.
	var patch := MeshInstance3D.new()
	patch.name = "IdentityPatch"
	var box := BoxMesh.new()
	box.size = Vector3(0.09,0.052,0.005)
	patch.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color.lightened(0.20)
	material.roughness = 1.0
	patch.material_override = material
	patch.position = Vector3(0.11,0.065,0.211)
	visual.gear_mounts.armor.node.add_child(patch)
	var label := Label3D.new()
	label.name = "PatchMark"
	label.text = str(appearance.get("patch", "PB")).left(4).to_upper()
	label.font_size = 32
	label.pixel_size = 0.00045
	label.modulate = Color("f2efe2")
	label.outline_size = 0
	label.position = patch.position + Vector3(0,0,0.004)
	label.no_depth_test = false
	visual.gear_mounts.armor.node.add_child(label)

static func _sync_gear_pose(visual: Dictionary) -> void:
	var sk: Skeleton3D = visual.skeleton
	for mount: Dictionary in visual.gear_mounts.values():
		var pose: Transform3D = visual.model.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(int(mount.bone))
		mount.node.transform = pose * mount.bind
	var hand: Transform3D = visual.model.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(int(visual.wrist))
	# Hand props are authored in meters; the imported rig's wrist carries 100x scale.
	hand.basis = hand.basis.orthonormalized()
	visual.hand_tool.transform = hand
	visual.hand_tool.visible = bool(visual.get("hand_tool_active",false)) or bool(visual.get("camera_active",false))

static func _throwing_smoke(entity: Dictionary) -> bool:
	for command: Dictionary in entity.get("commands", []):
		if command.get("state", "") == "RUNNING" and command.get("type", "") == "THROW_SMOKE": return true
	return false

static func _tint_equipment(prop: Node3D, color: Color) -> void:
	for mesh: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		for surface: int in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.get_active_material(surface)
			if original is StandardMaterial3D:
				var material: StandardMaterial3D = original.duplicate()
				var shade: float = 0.82 if material.resource_name.to_lower().contains("plate") else 1.0
				material.albedo_color = Color(color.r*shade,color.g*shade,color.b*shade)
				material.roughness = 0.95
				mesh.set_surface_override_material(surface,material)

static func _preparing_throw(entity: Dictionary) -> bool:
	if entity.get("status", "") != "THROWING": return false
	for command: Dictionary in entity.get("commands", []):
		if command.get("state", "") == "RUNNING" and command.get("type", "") in ["THROW_STUN","THROW_SMOKE","OPEN_AND_FLASH"]: return not command.has("projectile_id")
	return false
