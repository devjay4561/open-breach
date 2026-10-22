extends SceneTree
const LOOPS = ["RifleWalk", "RifleWalkBack", "RifleRun", "RifleRunBack", "RifleStrafeLeft", "RifleStrafeRight"]
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var installed := "--installed" in OS.get_cmdline_user_args()
	var model: Node3D
	if installed:
		model = load("res://assets/characters/combat-swat-gear.glb").instantiate()
	else:
		assert(doc.append_from_file(ProjectSettings.globalize_path("res://../build/cc0-motion/combat-swat.glb"), state) == OK)
		model = doc.generate_scene(state)
	root.add_child(model)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var result := {}
	for clip in LOOPS:
		var feet := {"L": [], "R": []}
		var bodies := []
		for i in range(120):
			sk.reset_bone_poses()
			player.play(clip)
			player.seek(player.get_animation(clip).length * float(i) / 120.0, true)
			player.advance(0.0)
			sk.force_update_all_bone_transforms()
			for side in feet:
				feet[side].append((sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Foot." + side))).origin)
			bodies.append((sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Body"))).origin)
		var contact := {}
		var stride_sum := 0.0
		var signed_sum := 0.0
		var segments := 0
		var axis := Vector3.RIGHT if clip.contains("Strafe") else Vector3.BACK
		for side in feet:
			var values: Array = feet[side]
			var lowest := INF
			var highest := -INF
			for point: Vector3 in values:
				lowest = minf(lowest, point.y)
				highest = maxf(highest, point.y)
			var threshold := lowest + minf(0.03, (highest - lowest) * 0.2)
			var phase := -1.0
			for i in range(120):
				var previous: Vector3 = values[(i + 119) % 120]
				var current: Vector3 = values[i]
				if previous.y > threshold and current.y <= threshold and phase < 0.0:
					phase = float(i) / 120.0
				if previous.y <= threshold and current.y <= threshold:
					stride_sum += absf((current - previous).dot(axis)) * 120.0
					signed_sum += (current - previous).dot(axis) * 120.0
					segments += 1
			assert(phase >= 0.0)
			contact[side] = phase
		var drift := 0.0
		var low := INF
		var high := -INF
		for point: Vector3 in bodies:
			drift = maxf(drift, Vector2(point.x - bodies[0].x, point.z - bodies[0].z).length())
			low = minf(low, point.y)
			high = maxf(high, point.y)
		assert(drift < 0.0001)
		assert(high - low > 0.005)
		assert(segments > 0)
		assert(signed_sum > 0.0 if clip in ["RifleWalkBack", "RifleRunBack", "RifleStrafeRight"] else signed_sum < 0.0)
		result[clip] = {"stride": stride_sum / segments, "signed_stance_travel": signed_sum / segments, "contacts": contact, "planar_root_drift": drift, "vertical_bob": high - low, "seconds": player.get_animation(clip).length, "stance_segments": segments}
		print("CC0_GAIT ", clip, " ", JSON.stringify(result[clip]))
	var file := FileAccess.open("res://../build/cc0-motion/gait-imported.json" if installed else "res://../build/cc0-motion/gait-measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  ") + "\n")
	print("CC0_GAIT_COMPLETE")
	quit()
