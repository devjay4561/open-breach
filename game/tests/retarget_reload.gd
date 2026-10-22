extends SceneTree
const BONE_MAP: Dictionary = {
	"Hips": "pelvis", "Abdomen": "spine_01", "Torso": "spine_03",
	"Neck": "neck_01", "Head_2": "Head",
	"Shoulder.L": "clavicle_l", "UpperArm.L": "upperarm_l", "LowerArm.L": "lowerarm_l", "Index1.L": "index_01_l",
	"Shoulder.R": "clavicle_r", "UpperArm.R": "upperarm_r", "LowerArm.R": "lowerarm_r", "Index1.R": "index_01_r"
}
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var source = load("res://assets/characters/ual-source.glb").instantiate()
	var target = load("res://assets/characters/soldier.glb").instantiate()
	root.add_child(source)
	root.add_child(target)
	var src: Skeleton3D = source.find_child("Skeleton3D", true, false)
	var dst: Skeleton3D = target.find_child("Skeleton3D", true, false)
	var src_player: AnimationPlayer = source.find_child("AnimationPlayer", true, false)
	var dst_player: AnimationPlayer = target.find_child("AnimationPlayer", true, false)
	src_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	dst_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	print("SOURCE BONES ", src.get_concatenated_bone_names())
	var clip := Animation.new()
	var src_name := ""
	for name: String in src_player.get_animation_list():
		if name.ends_with("Pistol_Reload"):
			src_name = name
	assert(not src_name.is_empty())
	clip.length = src_player.get_animation(src_name).length
	var tracks: Dictionary = {}
	for bone: String in BONE_MAP:
		if src.find_bone(BONE_MAP[bone]) < 0 or dst.find_bone(bone) < 0:
			continue
		var track: int = clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("RootNode/CharacterArmature/Skeleton3D:" + bone))
		tracks[bone] = track
	assert(tracks.size() >= 10)
	for frame: int in range(ceili(clip.length * 30.0) + 1):
		var time: float = minf(float(frame) / 30.0, clip.length)
		src.reset_bone_poses()
		src_player.play(src_name)
		src_player.seek(time, true)
		src.force_update_all_bone_transforms()
		dst.reset_bone_poses()
		dst_player.play("CharacterArmature|Idle_Shoot")
		dst_player.seek(0.0, true)
		dst.force_update_all_bone_transforms()
		for bone: String in tracks:
			var si: int = src.find_bone(BONE_MAP[bone])
			var di: int = dst.find_bone(bone)
			var source_rest: Basis = (src.global_transform * src.get_bone_global_rest(si)).basis.orthonormalized()
			var source_pose: Basis = (src.global_transform * src.get_bone_global_pose(si)).basis.orthonormalized()
			var dest_rest: Basis = (dst.global_transform * dst.get_bone_global_rest(di)).basis.orthonormalized()
			var desired: Basis = source_pose * source_rest.inverse() * dest_rest
			var parent: int = dst.get_bone_parent(di)
			var parent_basis: Basis = dst.global_transform.basis.orthonormalized()
			if parent >= 0:
				parent_basis = (dst.global_transform * dst.get_bone_global_pose(parent)).basis.orthonormalized()
			var rotation: Quaternion = (parent_basis.inverse() * desired).get_rotation_quaternion()
			dst.set_bone_pose_rotation(di, rotation)
			dst.force_update_all_bone_transforms()
			clip.rotation_track_insert_key(int(tracks[bone]), time, rotation)
	ResourceSaver.save(clip, "res://assets/characters/reload.tres")
	print("RELOAD_RETARGET tracks=",tracks.size()," seconds=",clip.length)
	source.queue_free()
	target.queue_free()
	quit()
