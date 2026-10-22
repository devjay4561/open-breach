class_name BreachLocomotionProfile
extends RefCounted
## Measured stance-foot travel per cycle, shared by animation
## sampling and footstep contacts. Changing a clip never leaves audio on an old
## generic stride. Contacts are measured from descending foot-height crossings
## over 120 samples per clip; see tests/cc0_motion_measure.gd.
## Stride = projected stance-foot travel / normalized stance duration.
## Simulation hearing keeps its own gameplay cadence in simulation.gd.
const STRIDES := {"RifleRun": 2.449252, "RifleRunBack": 2.500948, "RifleStrafeLeft": 2.363994, "RifleStrafeRight": 2.363994, "RifleWalk": 1.813598, "RifleWalkBack": 1.813598}
const CONTACT_PHASES := {"RifleRun": [0.441667, 0.958333], "RifleRunBack": [0.325, 0.808333], "RifleStrafeLeft": [0.0, 0.458333], "RifleStrafeRight": [0.0, 0.458333], "RifleWalk": [0.033333, 0.533333], "RifleWalkBack": [0.116667, 0.616667]}

static func base_clip(entity: Dictionary) -> String:
	var facing: float = float(entity.get("facing", 0.0))
	var relative: float = angle_difference(float(entity.get("body_facing", entity.get("aim_facing", facing))), float(entity.get("move_facing", facing)))
	if absf(relative) > PI * 0.75:
		return "RifleWalkBack"
	if absf(relative) > PI * 0.25:
		return "RifleStrafeRight" if relative > 0.0 else "RifleStrafeLeft"
	# Legacy replay/lab entities without a movement mode retain their authored
	# clip. New simulation actors explicitly select walk versus fast travel.
	if not entity.has("movement_mode"):
		return "RifleRun" if entity.get("kind", "") == "unit" else "RifleWalk"
	return "RifleRun" if entity.get("movement_mode", "normal") == "fast" and entity.get("stance", "standing") != "crouched" else "RifleWalk"

static func stride(entity: Dictionary, clip: String) -> float:
	return float(STRIDES.get(clip, STRIDES.RifleWalk)) * (0.72 if entity.get("stance", "standing") == "crouched" else 1.0)

static func contact_count(clip: String, distance: float, entity: Dictionary = {}) -> int:
	var cycle: float = maxf(0.0, distance) / stride(entity, clip)
	var phases: Array = CONTACT_PHASES.get(clip, CONTACT_PHASES.RifleWalk)
	return floori(cycle - float(phases[0]) + 0.000001) + floori(cycle - float(phases[1]) + 0.000001) + 2
