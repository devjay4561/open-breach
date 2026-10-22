extends SceneTree
## P7 spawn choices own no random stream. Existing missions keep PCG behavior.
const Seed = preload("res://scripts/cqb_seed.gd")
const Simulation = preload("res://scripts/simulation.gd")
const STEP := 1.0 / 30.0
const STREAMS := ["_rng", "_hit_region_rng", "_breach_rng", "_surrender_rng"]
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(id: String = "SH01", seed: int = 42) -> Dictionary:
	return {"schema_version":6,"id":id,"title":"Seed fixture","seed":seed,"default_seed":42,"variant":"normal","roe":"precision",
		"bounds":[20.0,20.0],"rooms":[{"id":"room","x":10.0,"z":10.0,"w":18.0,"d":18.0}],"walls":[],"props":[],"civilians":[],
		"units":[{"id":"alpha","x":2.0,"z":2.0,"vision_range":1.0,"ammo":0,"reserve_ammo":0}],
		"doors":[{"id":"door","x":10.0,"z":10.0,"w":1.4,"d":0.2,"axis":"x","state":"CLOSED"}],
		"enemies":[{"id":"guard-a","x":16.0,"z":16.0,"facing":0.0,"vision_range":1.0,"hp":72.0,"ammo":0,
			"spawns":[{"x":16.0,"z":16.0,"facing":0.0},{"x":15.0,"z":16.0,"facing":1.0},{"x":16.0,"z":15.0,"facing":2.0,"patrol":[[15.0,15.0],[16.0,15.0]]}]}],
		"win":[{"type":"reach_zone","zone":[19.0,2.0,0.2,0.2]}],"fail":[]}

func run() -> void:
	if not (Simulation as Script).can_instantiate():
		check(false,"Actual simulation must compile before seed integration fixtures run")
		finish()
		return
	_test_fixed_hashes()
	_test_materialization()
	_test_legacy_selection()
	_test_seed_streams()
	finish()

func finish() -> void:
	print("BREACH_CQB_SEED_RESULT checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_fixed_hashes() -> void:
	# Independently calculated by Node Buffer UTF-8 + Math.imul FNV-1a32.
	var oracle := {"":2166136261,"SH01:42:e1":1540358421,"SH05:2147483647:guard-a":2456487796,"CQB12:0:e8":3302359655,"공유 시드:42":1730508898}
	for value: String in oracle: check(Seed.stable_hash(value)==oracle[value],"Stable UTF-8 hash matches the independent Node oracle: "+value)
	check(Seed.IDS.size()==18 and Seed.SHOOT_HOUSE_IDS.size()==6 and Seed.PUZZLE_IDS.size()==12,"Only the six drills and twelve authored puzzles use the materializer")
	for id: String in ["M01","M01_PRECISION","H36","SH05","SH010","CQB00","CQB13","CQB01H"]:
		check(not Seed.is_mission(id),"Legacy and lookalike identity is excluded: "+id)
	check(Seed.canonical_id("SH05_PRECISION")=="SH05" and Seed.canonical_id("SH05_HIGH_INTENSITY")=="SH05","ROE comparison shares exactly one placement namespace")
	check(Seed.canonical_id("CQB05")=="CQB05","Distinct puzzles retain their separate placement namespace")
	check(Seed.candidate_index("SH01","e1",42,42,8)==0,"Default seed preserves the authored zero candidate")
	check(Seed.candidate_index("SH01","e1",2147483647,42,0)==0 and Seed.candidate_index("SH01","e1",7,42,1)==0,"Empty/single candidate collections cannot consume randomness")

func _test_materialization() -> void:
	var source: Dictionary = fixture()
	var before: Dictionary = source.duplicate(true)
	var result: Dictionary = Seed.materialize(source)
	check(source==before,"Materialization never mutates authored mission or spawn candidates")
	var expected: Dictionary = before.duplicate(true)
	expected.enemies[0].erase("spawns")
	check(result==expected,"Default materialization changes only removal of the consumed P7 candidate list")
	check(not result.enemies[0].has("spawns"),"Existing AI RNG selector receives no P7 candidate list")
	result.units[0].x=-900.0
	result.enemies[0].x=-800.0
	check(source==before,"Returned mission owns its actor and geometry dictionaries")
	var candidate: Dictionary = fixture("CQB01",7)
	var chosen: int = Seed.candidate_index(candidate.id,"guard-a",7,42,3)
	var positioned: Dictionary = Seed.materialize(candidate)
	for field: String in ["x","z","facing"]:
		check(positioned.enemies[0][field]==candidate.enemies[0].spawns[chosen][field],"Selected authored "+field+" is copied without Vector2 rounding")
	check(positioned.enemies[0].hp==72.0 and positioned.enemies[0].ammo==0 and positioned.units==candidate.units,"Seed materialization cannot change combat resources or own actors")
	var legacy: Dictionary = fixture("M01",7)
	check(is_same(Seed.materialize(legacy),legacy) and legacy.enemies[0].has("spawns"),"Legacy missions retain their original dictionary and AI-RNG candidates")
	var layouts: Dictionary = {}
	for seed: int in range(30):
		var precision: Dictionary = fixture("SH05_PRECISION",seed)
		var high: Dictionary = precision.duplicate(true)
		high.id="SH05_HIGH_INTENSITY"
		high.roe="high_intensity"
		high.civilians=[]
		var first: Dictionary = Seed.materialize(precision)
		var second: Dictionary = Seed.materialize(high)
		check(first.enemies==second.enemies,"ROE pair keeps identical seeded hostile coordinates and patrols")
		check(Seed.materialize(precision)==first,"Same seed and candidate mission gives the same detached materialization")
		layouts[str(first.enemies[0].x)+":"+str(first.enemies[0].z)]=true
	check(layouts.size()>1,"Nondefault seeds actually vary the authored placement")

func _test_legacy_selection() -> void:
	for seed: int in [7,42]:
		var source: Dictionary = fixture("LEGACY_SEED",seed)
		source.doors[0].initial_states=["CLOSED","OPEN"]
		var before: Dictionary = source.duplicate(true)
		var oracle := RandomNumberGenerator.new()
		oracle.seed=seed
		var index: int = 0
		var door_index: int = 0
		if seed!=42:
			index=oracle.randi_range(0,2)
			door_index=oracle.randi_range(0,1)
		var sim := Simulation.new()
		sim.load_mission(source)
		var chosen: Dictionary = source.enemies[0].spawns[index]
		check(sim.enemies[0].x==chosen.x and sim.enemies[0].z==chosen.z and sim.enemies[0].facing==chosen.facing,"Legacy enemy still consumes the original ordered PCG choice")
		check(sim.doors[0].state==source.doors[0].initial_states[door_index],"Legacy door state still follows the original enemy choice in the same stream")
		check(sim._rng.state==oracle.state,"Default/nondefault legacy spawn selection retains its exact AI RNG state")
		check(source==before and sim.mission.enemies[0].has("spawns"),"Legacy simulation mission and authoring contract stay unchanged")

func _test_seed_streams() -> void:
	for seed: int in range(30):
		var source: Dictionary = fixture("SH01",seed)
		var before: Dictionary = source.duplicate(true)
		var first := Simulation.new()
		first.load_mission(source)
		var repeated := Simulation.new()
		repeated.load_mission(source)
		var flat: Dictionary = Seed.materialize(source)
		flat.id="LEGACY_FLAT_CONTROL"
		var control := Simulation.new()
		control.load_mission(flat)
		check(first.enemies==repeated.enemies and first.units==repeated.units,"Repeated actual load preserves full entity values for seed %d"%seed)
		check(first.enemies==control.enemies and first.units==control.units and first.doors==control.doors,"Actual materialized loading equals an already authored placement for seed %d"%seed)
		for stream: String in STREAMS:
			check(first.get(stream).state==control.get(stream).state,"P7 placement does not consume "+stream+" for seed %d"%seed)
		for tick: int in range(6):
			first.step(STEP)
			repeated.step(STEP)
			control.step(STEP)
		check(first.enemies==repeated.enemies and first.units==repeated.units and first.enemies==control.enemies and first.units==control.units,"Fixed STEP keeps the same full runtime entity sequence")
		for stream: String in STREAMS:
			check(first.get(stream).state==control.get(stream).state,"Placement leaves later "+stream+" consumption identical")
		check(source==before and not first.mission.enemies[0].has("spawns"),"Actual P7 hook retains detached input and consumes candidates exactly once")
