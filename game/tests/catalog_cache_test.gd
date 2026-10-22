extends SceneTree
const Catalog = preload("res://scripts/mission_catalog.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	var parsed: Dictionary = {}
	var base: Dictionary = Catalog._load_data("M01", parsed)
	var variant: Dictionary = Catalog._load_data("M01_HOSTAGE", parsed)
	check(parsed.size() == 1, "Variants reuse one parsed floorplan")
	var original_x: float = float(base.units[0].x)
	base.units[0].x = -999.0
	check(float(variant.units[0].x) == original_x, "Each mission owns its nested actor data")
	check(float(parsed.house.units[0].x) == original_x, "Mission changes do not mutate the parsed source")
	var catalog: Dictionary = Catalog.missions()
	check(catalog.size() == Catalog.MAPS.size(), "The complete catalog remains available")
	for id: String in Catalog.MAPS:
		check(catalog[id] == Catalog.load(id), id + " cache preserves mission behavior")
	var briefings: Array = Catalog.briefings(catalog)
	check(briefings.size() == Catalog.MAPS.size() - 3, "Briefings hide only the legacy arrest operations")
	var entry: Dictionary = briefings.filter(func(item: Dictionary) -> bool: return item.id == "M01")[0]
	entry.units[0].x = -888.0
	entry.objectives.append("Changed briefing")
	check(float(catalog.M01.units[0].x) == original_x, "Briefing actors are independent of the runtime catalog")
	check(not catalog.M01.objectives.has("Changed briefing"), "Briefing objectives are independent of the runtime catalog")
	check(Catalog.load("M01") == catalog.M01, "A fresh load cannot retain caller mutations")
	print("BREACH_CATALOG_CACHE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
