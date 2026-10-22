extends SceneTree
const Schema = preload("res://scripts/mission_schema.gd")
const Navigation = preload("res://scripts/navigation.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void:
	var mission := {"schema_version":2,"id":"WALL_PROXY_QA","revision":1,"seed":1,"title":"Collision proxy visibility","bounds":[32,32],"focus":[16,16],
		"rooms":[{"id":"ground","x":16.0,"z":16.0,"w":32.0,"d":32.0}],
		"walls":[{"id":"proxy","x":16.0,"z":16.0,"w":4.0,"d":4.0,"render":false}],"doors":[],"props":[],
		"units":[{"id":"alpha","name":"Alpha","role":"Assault","weapon":"standard","x":4.0,"z":4.0,"facing":0.0}],"enemies":[],"civilians":[],"objectives":["Reach destination"],"win":[{"type":"reach_zone","zone":[28,28,2,2]}]}
	check(bool(Schema.check(mission).ok),"V2 accepts an explicitly hidden wall proxy")
	var nav := Navigation.new()
	nav.build(mission,[])
	check(not nav.walkable(Vector2(16,16)),"Hidden wall proxy still blocks actor movement")
	check(not nav.segment_clear(Vector2(10,16),Vector2(22,16)),"Hidden wall proxy still occludes sight")
	check(not nav.shot_clear(Vector2(10,16),Vector2(22,16)),"Hidden wall proxy still blocks bullets")
	mission.walls[0].render = true
	check(bool(Schema.check(mission).ok),"V2 accepts an explicitly visible wall")
	mission.walls[0].render = 0
	check(not bool(Schema.check(mission).ok),"Render must be a Boolean")
	mission.walls[0].render = false
	mission.schema_version = 1
	check(not bool(Schema.check(mission).ok),"Legacy schema rejects the new render field")
	mission.walls[0].erase("render")
	check(bool(Schema.check(mission).ok),"Omitted render preserves legacy wall visibility")
	print("BREACH_WALL_RENDER_CONTRACT_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
