extends SceneTree
const Actor = preload("res://scripts/actor_visual.gd")
const Spatial = preload("res://scripts/spatial_profile.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
func _run() -> void:
	var holders: Array[Node3D] = []
	for weapon: String in ["standard","light","shotgun","suppressed","pico_p1"]:
		var holder := Node3D.new()
		root.add_child(holder)
		holders.append(holder)
		var visual: Dictionary = Actor.create(holder,false)
		var entity := {"id":"test","hp":100.0,"weapon":"standard","current_weapon":weapon,"active_weapon":"secondary" if weapon == "pico_p1" else "primary","armor":"bastion_v4","helmet":"crown_h2","attachments":["dot","extended_mag"],"appearance":{"color":"#876842","patch":"FOX"},"commands":[],"facing":0.0,"aim_facing":0.0,"kind":"unit","weapon_length":float(Actor.WEAPON_LENGTHS[weapon])+(0.20 if weapon=="suppressed" else 0.0)}
		Actor.sync(visual,entity,[],0.0,0.0,false)
		check(Vector2(visual.muzzle.global_position.x,visual.muzzle.global_position.z).distance_to(Spatial.weapon_origin(entity)) < 0.002,"Physical muzzle agrees with measured rendered barrel: "+weapon)
		check(absf(visual.muzzle.global_position.y-Spatial.weapon_height(entity))<0.002,"Physical muzzle height agrees with rendered barrel: "+weapon)
		check(visual.equipped_weapon == weapon,"Current weapon selects the actual model: "+weapon)
		check(visual.weapon.get_node_or_null(NodePath(weapon)) != null,"Weapon prop exists: "+weapon)
		check(visual.gear_mounts.armor.node.get_node_or_null("bastion_v4") != null,"Heavy armor model is equipped")
		check(visual.gear_mounts.helmet.node.get_node_or_null("crown_h2") != null,"Heavy helmet model is equipped")
		check(visual.gear_mounts.armor.node.get_node("PatchMark").text == "FOX","Original identification patch uses personal mark")
		check(visual.gear_mounts.helmet.node.global_position.y > 1.3,"Detached helmet stays at animated head")
		check(visual.muzzle.position.x >= float(Actor.MUZZLES[weapon].x),"Muzzle preserves physical barrel reach")
		check(visual.weapon.get_node_or_null("dot") == null if weapon == "pico_p1" else visual.weapon.get_node_or_null("dot") != null,"Primary attachments do not appear on secondary weapon")
		check(visual.muzzle.position.x > Actor.MUZZLES.suppressed.x + 0.19 if weapon == "suppressed" else true,"Built-in suppressor moves barrel socket")
		var head_before: Transform3D = visual.gear_mounts.helmet.node.global_transform
		entity.status = "RELOADING"
		entity.commands = [{"type":"RELOAD","state":"RUNNING","remaining":0.7}]
		Actor.sync(visual,entity,[],0.4,0.0,false)
		Actor.sync(visual,entity,[],0.6,0.0,false)
		check(not head_before.is_equal_approx(visual.gear_mounts.helmet.node.global_transform),"Helmet follows authored motion")
		entity.armor = "swift_v3"
		entity.helmet = "crown_h1"
		entity.appearance.patch = "OWL"
		Actor.sync(visual,entity,[],0.6,0.0,false)
		check(visual.equipped_armor == "swift_v3" and visual.equipped_helmet == "crown_h1","Same-clock gear changes invalidate paused pose cache")
		check(visual.gear_mounts.armor.node.get_node("PatchMark").text == "OWL","Same-clock personal patch change updates")
		entity.status = "READY"
		entity.commands = []
		Actor.sync(visual,entity,[],0.0,0.0,false)
		check(visual.gear_mounts.helmet.node.global_transform.is_equal_approx(head_before),"Replay rewind restores gear attachment pose")
		if weapon == "standard":
			entity.armor = "none"
			entity.helmet = "none"
			entity.status = "READY"
			Actor.sync(visual,entity,[],0.2,0.0,false)
			check(visual.gear_mounts.armor.node.get_node_or_null("frame_v2") == null,"Explicit no-armor profile has no extra ballistic carrier")
			check(visual.gear_mounts.helmet.node.get_node_or_null("mask_h0") != null,"Explicit no-helmet profile has actual unarmored head")
			entity.status = "THROWING"
			entity.commands = [{"type":"OPEN_AND_FLASH","state":"RUNNING","remaining":.25}]
			Actor.sync(visual,entity,[],1.0,0.0,false)
			check(visual.hand_tool.visible,"Grenade is held during preparation")
			check(visual.hand_tool.global_basis.get_scale().is_equal_approx(Vector3.ONE),"Held grenade keeps meter scale instead of inheriting the imported wrist's 100x scale")
			for mesh: MeshInstance3D in visual.hand_tool.find_children("*","MeshInstance3D",true,false):
				var size: Vector3 = (mesh.global_transform * mesh.get_aabb()).size
				check(maxf(size.x,maxf(size.y,size.z)) < 0.3,"Held grenade fits within 30cm throughout its authored pose")
			entity.status = "WAITING"
			entity.commands[0]["projectile_id"] = "flash-1"
			var release: Array = [{"type":"FLASH_RELEASE","unit_id":"test","time":1.1,"projectile_id":"flash-1"}]
			Actor.sync(visual,entity,release,1.15,0.0,false)
			check(not visual.hand_tool.visible and str(visual.clip).begins_with("RifleThrow:"),"Released grenade leaves the hand while authored follow-through continues")
			Actor.sync(visual,entity,release+[{"type":"STUN","unit_id":"test","time":1.5,"projectile_id":"flash-1"}],1.6,0.0,false)
			check(not str(visual.clip).begins_with("RifleThrow:"),"Explosion does not replay the completed throw")
			entity.status = "CAMERA"
			entity.equipment = {"probe_c1":1}
			entity.commands = [{"type":"PEEK_CAMERA","state":"RUNNING","remaining":.4}]
			Actor.sync(visual,entity,[],2.0,0.0,false)
			check(visual.hand_tool.visible and visual.hand_tool.get_node_or_null("camera") != null,"Observation command holds the original camera model")
			check(visual.hand_tool.global_basis.get_scale().is_equal_approx(Vector3.ONE),"Held camera also keeps meter scale at the animated wrist")
			var left_hand: Transform3D = visual.skeleton.global_transform*visual.skeleton.get_bone_global_pose(int(visual.left_wrist))
			check((left_hand*visual.left_weapon_bind).is_equal_approx(visual.weapon.global_transform),"Camera hand is free while the left hand carries the primary")
	check(Spatial.weapon_forward_offset({}) == 0.32,"Legacy unrecorded weapons retain muzzle reach")
	check(Spatial.weapon_forward_offset({"kind":"unit","weapon_length":1.06}) > Spatial.weapon_forward_offset({"kind":"unit","weapon_length":.86}),"Suppressed weapon extends physical muzzle reach")
	check(Spatial.weapon_forward_offset({"kind":"unit","current_weapon":"pico_p1","weapon_length":.23}) < Spatial.weapon_forward_offset({"kind":"unit","current_weapon":"light","weapon_length":.62}),"Sidearm reach is shorter than SMG reach")
	var samples := Spatial.samples({"hp":100,"stance":"standing"})
	check(samples[0].region == "head" and samples[1].region == "torso" and samples[3].region == "limb","Body samples carry armor hit regions")
	_test_door_carry()
	for holder: Node3D in holders:holder.queue_free()
	for failure: String in failures:print("FAIL ",failure)
	print("BREACH_OPERATOR_VISUAL_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_door_carry() -> void:
	for weapon: String in ["standard","light","shotgun","suppressed","pico_p1"]:
		var holder := Node3D.new()
		root.add_child(holder)
		var visual: Dictionary = Actor.create(holder,false)
		var entity := {"id":"door_test","hp":100.0,"status":"OPENING","weapon":"standard","current_weapon":weapon,"commands":[],"facing":0.0,"aim_facing":0.0}
		for progress: float in [0.0,0.05,0.15,0.3,0.6,0.8,0.95,1.0]:
			visual.last_clock = -1.0
			visual.clip = ""
			Actor.sync(visual,entity,[],progress+1.0,0.0,false,{"progress":progress,"handle":Vector3(.55,1.15,0)})
			check(float(visual.support_error)<0.025,"Door carry keeps %s support grip within 2.5cm at %.2f" % [weapon,progress])
			var left: Transform3D = visual.skeleton.global_transform*visual.skeleton.get_bone_global_pose(int(visual.left_wrist))
			var grip: Transform3D = visual.weapon.global_transform*visual.support_bind
			check(left.origin.distance_to(grip.origin)<0.025,"Door carry measured wrist agrees with grip on "+weapon)
		holder.queue_free()
