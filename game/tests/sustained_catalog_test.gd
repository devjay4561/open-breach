extends SceneTree
const Catalog = preload("res://scripts/mission_catalog.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	call_deferred("run")
func reject(data: Dictionary, label: String) -> void:
	check(not bool(Catalog.validate_custom(data).get("ok",false)),label)
func run() -> void:
	check(Catalog.BASE_IDS.all(func(id: String) -> bool: return Catalog.FILES.has(id) and Catalog.FILES.has(id+"H")),"all authored floor plans have normal and challenge catalog entries")
	check(Catalog.MAPS.size() == Catalog.FILES.size()+15,"operation variants extend the authored catalog")
	check(Catalog.briefings().size() == Catalog.MAPS.size()-3,"menu hides three legacy arrest operations")
	for id: String in Catalog.MAPS:
		var mission: Dictionary = Catalog.load(id)
		check(str(mission.id) == id,id+" identity")
		check(mission.win.size() > 0 and mission.fail.size() > 0,id+" explicit conditions")
		var answer: Dictionary = Catalog.validate_custom(mission)
		check(bool(answer.get("ok",false)),id+" runtime schema/geometry: "+str(answer.get("message","")))
		for enemy: Dictionary in mission.enemies:
			if enemy.has("spawns"):
				check(enemy.spawns[0].x == enemy.x and enemy.spawns[0].z == enemy.z and enemy.spawns[0].get("patrol",[]) == enemy.get("patrol",[]),id+" fixed candidate "+str(enemy.id))
		if id.ends_with("_HOSTAGE"):
			check(mission.win[0].type == "secure_all_civilians",id+" hostage objective")
			for civilian: Dictionary in mission.civilians:
				var nearby: bool = false
				for enemy: Dictionary in mission.enemies:
					if enemy.enemy_type == "hostage_taker" and Vector2(float(enemy.x),float(enemy.z)).distance_to(Vector2(float(civilian.x),float(civilian.z))) <= 2.0: nearby = true
				check(nearby,id+" hostage tether")
		if id.ends_with("_ESCORT"): check(mission.win[0].type == "escort_to_zone",id+" escort objective")
		if id.ends_with("_INFILTRATION"): check(mission.win[0].type == "reach_zone" and mission.fail[1].type == "before_alert",id+" alert failure")
		if id.ends_with("_TIMED"): check(mission.win[0].type == "reach_zone" and mission.fail[1].seconds == 25.0,id+" timed deadline")
		if id.ends_with("_ARREST"): check(mission.win[0].type == "neutralize_all" and not mission.stars.any(func(star: Dictionary) -> bool: return star.get("stat", "") == "kills"),id+" legacy arrest load omits impossible no-kills medal")
	var source: Dictionary = Catalog.load("T01")
	var malformed: Dictionary = source.duplicate(true)
	malformed.win = [{"type":"mystery"}]
	reject(malformed,"unknown rule rejected")
	malformed = source.duplicate(true)
	malformed.win = [{"type":"reach_zone","zone":[2,2,-1,1]}]
	reject(malformed,"invalid zone rejected")
	malformed = source.duplicate(true)
	malformed.fail = [{"type":"time_limit","seconds":0}]
	reject(malformed,"invalid time rejected")
	malformed = source.duplicate(true)
	malformed.enemies[0].enemy_type = "super_enemy"
	reject(malformed,"unknown enemy type rejected")
	malformed = source.duplicate(true)
	malformed.props[0].cover = "invisible"
	reject(malformed,"unknown cover rejected")
	malformed = source.duplicate(true)
	malformed.walls[0].thin = "true"
	reject(malformed,"thin wall requires boolean")
	malformed = source.duplicate(true)
	malformed.units[1].id = malformed.units[0].id
	reject(malformed,"duplicate entity ID rejected")
	malformed = source.duplicate(true)
	malformed.enemies[0].spawns = [{"x":malformed.enemies[0].x,"z":malformed.enemies[0].z,"facing":malformed.enemies[0].facing},{"x":source.units[0].x,"z":source.units[0].z,"facing":0}]
	reject(malformed,"secondary candidate actor overlap rejected")
	malformed = source.duplicate(true)
	malformed.enemies[0].spawns = [{"x":malformed.enemies[0].x,"z":malformed.enemies[0].z,"facing":malformed.enemies[0].facing},{"x":3.0,"z":10.0,"facing":0}]
	reject(malformed,"secondary candidate blocked spawn rejected")
	malformed = source.duplicate(true)
	malformed.enemies[0].spawns = [{"x":malformed.enemies[0].x+1,"z":malformed.enemies[0].z,"facing":malformed.enemies[0].facing}]
	reject(malformed,"default candidate preservation")
	malformed = source.duplicate(true)
	malformed.id = "EDIT_CUSTOM"
	malformed.custom = true
	malformed.variant = "standard"
	malformed.loadout = {"alpha":{"weapon":"suppressed","equipment":{"smoke":1}}}
	malformed.roster = [{"id":"raven","base_id":"alpha","name":"레이븐","trait":"breacher"}]
	check(bool(Catalog.validate_custom(malformed).get("ok",false)),"custom ID accepted with geometry: "+str(Catalog.validate_custom(malformed)))
	var configured: Dictionary = Catalog.load("M01")
	configured.modifiers = ["night","low_ammo","fast_reaction","no_stun"]
	var modified: Dictionary = Catalog.apply_modifiers(configured)
	check(modified.environment.time_of_day == "night" and modified.environment.lighting == 0.25 and modified.units[0].ammo == 12 and modified.units[0].reserve_ammo == 36 and modified.units[0].stuns == 0,"combined lighting and equipment modifiers")
	check(Catalog.rules_for(configured).reaction_max == Catalog.CHALLENGE.reaction_max,"fast reaction modifier")
	check(Catalog.rules_for(Catalog.load("M01H")).enemy_opens_doors and Catalog.rules_for(Catalog.load("M01")).enemy_opens_doors,"challenge door rule")
	check(not Catalog.load("M01").units[0].has("ammo"),"modifier copy does not mutate authored units")
	for kind: String in Catalog.COVER_DEFAULTS: check(Catalog.cover_default(kind) in ["none","low","full"],kind+" furniture cover default")
	print("BREACH_SUSTAINED_CATALOG_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
