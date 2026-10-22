extends SceneTree
## Every exported clip, five phases, two orthographic views; usable before install.
const CLIPS = ["RifleIdle", "RifleWalk", "RifleWalkBack", "RifleRun", "RifleRunBack", "RifleStrafeLeft", "RifleStrafeRight", "RifleFire", "RifleHit", "RifleReload", "RifleThrow", "RifleTurnLeft", "RifleTurnRight", "DoorOpenOut", "Death"]
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(440, 440)
	var output := ProjectSettings.globalize_path("res://../build/cc0-motion/renders")
	DirAccess.make_dir_recursive_absolute(output)
	var scene := Node3D.new()
	root.add_child(scene)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var path := ProjectSettings.globalize_path("res://../build/cc0-motion/combat-swat.glb")
	assert(doc.append_from_file(path, state) == OK)
	var model := doc.generate_scene(state)
	scene.add_child(model)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var rifle: Node3D = load("res://assets/equipment/tern_c1.glb").instantiate()
	model.add_child(rifle)
	player.play("RifleIdle"); player.seek(0.0, true); player.advance(0.0)
	sk.force_update_all_bone_transforms()
	var wrist := sk.find_bone("Wrist.R")
	var left := sk.find_bone("Wrist.L")
	var bind: Transform3D = model.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(wrist)
	rifle.rotation.y = -PI * 0.5
	rifle.position = bind.origin + Vector3(0, 0.045, 0)
	var weapon_bind := bind.affine_inverse() * rifle.transform
	var left_bind: Transform3D = (model.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(left)).affine_inverse() * rifle.transform
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	camera.current = true
	var light := DirectionalLight3D.new()
	scene.add_child(light)
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.3
	var env := WorldEnvironment.new()
	scene.add_child(env)
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("53605d")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.65
	for view in ["top", "side"]:
		camera.position = Vector3(0, 0.85, 0) + Vector3(0, 34, 15.5).normalized() * 7 if view == "top" else Vector3(3.3, 2.4, 4)
		camera.look_at(Vector3(0, 0.85, 0))
		for clip in CLIPS:
			for i in range(5):
				sk.reset_bone_poses()
				player.play(clip)
				player.seek(player.get_animation(clip).length * float(i) / 4.0, true)
				player.advance(0.0)
				sk.force_update_all_bone_transforms()
				var carry: bool = clip in ["RifleThrow", "DoorOpenOut"]
				var socket: Transform3D = model.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(left if carry else wrist)
				rifle.transform = socket * (left_bind if carry else weapon_bind)
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output + "/" + view + "-" + clip + "-" + str(i) + ".png")
	print("CC0_PREVIEW_COMPLETE clips=15 views=2 phases=5")
	quit()
