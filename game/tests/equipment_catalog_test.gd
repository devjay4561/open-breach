extends SceneTree
const Equipment = preload("res://scripts/equipment_catalog.gd")
const Schema = preload("res://scripts/mission_schema.gd")
var checks: int = 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _initialize() -> void:
	var legacy: Dictionary = Equipment.resolve_loadout({"weapon":"light","equipment":["stun","breach"]})
	check(legacy.weapon == "light" and legacy.sidearm == "none" and legacy.armor == "none" and legacy.helmet == "none","Legacy loadout acquired protection or lost weapon")
	check(legacy.equipment == {"stun":1,"breach":1},"Legacy tools changed")
	var fresh: Dictionary = Equipment.resolve_loadout({},true)
	check(fresh.armor == "frame_v2" and fresh.sidearm == "pico_p1","New profile defaults missing")
	var extended: Dictionary = Equipment.weapon_stats("light",["extended_mag","dot"])
	check(extended.ammo == 40 and is_equal_approx(float(extended.reload),1.61),"Magazine final stats wrong")
	check(is_equal_approx(float(extended.accuracy),0.96) and is_equal_approx(float(extended.aim_time),0.221),"Sight final stats wrong")
	check(Equipment.weapon_stats("suppressed",["suppressor"]).sound == 3,"Built-in suppressor double counted")
	check(not Equipment.loadout_error({"weapon":"shotgun","attachments":["scope"]}).is_empty(),"Incompatible attachment accepted")
	check(not Equipment.loadout_error({"attachments":["dot","scope"]}).is_empty(),"Optic duplicate accepted")
	check(not Equipment.loadout_error({"appearance":{"patch":"other_game_logo"}}).is_empty(),"Unknown patch accepted")
	check(Equipment.loadout_error({"appearance":{"name":"나의 대원","callsign":"RAVEN","color":"#123aBc","patch":"shield"}}).is_empty(),"Valid identity rejected")
	check(Equipment.equipment_error({"stun":2,"breach":1}).is_empty(),"New small/large slots rejected")
	check(Equipment.equipment_error({"breach":2}).is_empty(),"Legacy two breach charges lost")
	check(not Equipment.equipment_error({"stun":2,"probe_c1":1}).is_empty(),"Three small tools accepted")
	var front: Dictionary = Equipment.protection({"armor":"swift_v3"},"torso",0,22)
	var side: Dictionary = Equipment.protection({"armor":"swift_v3"},"torso",PI/2,22)
	check(front.protected and is_equal_approx(front.reduction,0.66) and not side.protected,"Directional panel protection wrong")
	check(Equipment.protection({"armor":"swift_v3"},"torso",PI,22).protected,"Rear plate wrapping wrong")
	check(not Equipment.protection({"armor":"bastion_v4"},"limb",0,12).protected,"Armor covered unprotected limb")
	check(not Equipment.protection({"armor":"veil_v1"},"torso",0,22).protected,"Rifle did not penetrate soft armor")
	check(Equipment.protection({"helmet":"crown_h2"},"head",0,22).protected,"Helmet missing head protection")
	check(not Equipment.protection({},"torso",0,1).protected,"Legacy actor gained armor")
	var stats: Dictionary = Equipment.loadout_stats({"weapon":"standard","armor":"bastion_v4","helmet":"crown_h2"})
	check(is_equal_approx(stats.movement_multiplier,0.8428) and is_equal_approx(stats.action_multiplier,1.1536),"Armor/helmet movement penalties do not compose")
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tutorial.json"))
	map.loadout = {"alpha":{"weapon":"light","equipment":{"stun":2,"breach":1},"sidearm":"pico_p1","armor":"swift_v3","helmet":"crown_h2","attachments":["dot","extended_mag"],"appearance":{"callsign":"NOVA","name":"새 대원","color":"#123456","patch":"arrow"},"preset":"custom"}}
	check(Schema.check(map).ok,"Schema rejected full customization loadout")
	map.loadout.alpha.attachments = ["dot","scope"]
	check(not Schema.check(map).ok,"Schema allowed incompatible duplicate optic")
	print("BREACH_EQUIPMENT_CATALOG_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
