class_name BreachMovementAudio
extends RefCounted
## Presentation-only contacts from observed movement. No hidden enemy state and
## no gameplay events are invented. Reset on explicit replay seeks and map load.

const Gait = preload("res://scripts/locomotion_profile.gd")
const MAX_TIME_GAP: float = 0.35
const MAX_MOVEMENT_SPEED: float = 8.0
const EPSILON: float = 0.000001

var _actors: Dictionary = {}
var _doors: Dictionary = {}
var _clock: float = -1.0
var _mode: String = ""
var _playing: bool = false
var _rooms: Array = []
var _interior_surface: String = "concrete"

func configure(mission: Dictionary) -> void:
	_rooms = mission.get("rooms", []).duplicate(true)
	_interior_surface = "wood" if str(mission.get("id", "")) == "M01" else "concrete"
	reset()

func reset() -> void:
	_actors.clear()
	_doors.clear()
	_clock = -1.0
	_mode = ""
	_playing = false

func collect(state: Dictionary, playing: bool, discontinuity: bool = false) -> Array[Dictionary]:
	var sounds: Array[Dictionary] = []
	var clock: float = float(state.get("presentation_time", state.get("time", 0.0)))
	var mode: String = str(state.get("presentation_mode", ""))
	# The first resumed frame refreshes the baseline before emitting contacts.
	if not playing and not _playing and not discontinuity and clock == _clock and mode == _mode:
		return sounds
	var delta: float = clock - _clock
	var continuous: bool = playing and _playing and not discontinuity and _clock >= 0.0 and delta > EPSILON and delta <= MAX_TIME_GAP and mode == _mode
	# A paused frame still refreshes the baseline. Resuming, first contact and
	# seeking never emit a burst of footsteps accumulated while sound was off.
	var next_actors: Dictionary = {}
	for group: String in ["units", "enemies", "civilians"]:
		for actor: Dictionary in state.get(group, []):
			if float(actor.get("hp", 100.0)) <= 0.0 or (group != "units" and not bool(actor.get("visible", false))):
				continue
			var id: String = str(actor.get("id", ""))
			var position := Vector2(float(actor.get("x", 0.0)), float(actor.get("z", 0.0)))
			var before: Dictionary = _actors.get(id, {})
			var position_delta: float = position.distance_to(before.get("position", position))
			var fallback_distance: float = float(before.get("distance", 0.0)) + position_delta
			var distance: float = float(actor.get("travel_distance", fallback_distance))
			var gait: String = Gait.base_clip(actor)
			var contact: int = Gait.contact_count(gait, distance, actor)
			next_actors[id] = {"position": position, "distance": distance, "contact": contact, "gait": gait}
			if not continuous or before.is_empty() or before.get("gait", "") != gait:
				continue
			var traveled: float = distance - float(before.distance)
			if traveled < 0.0 or traveled > MAX_MOVEMENT_SPEED * delta + 0.15 or position_delta > traveled + 0.25:
				continue
			if position_delta <= EPSILON or contact <= int(before.contact):
				continue
			# At most one contact per actor per render frame, even after a long
			# frame or fast replay. The original contact index drives variation.
			sounds.append({"name": "footstep_" + _surface(position), "point": [position.x, position.y], "event": {"seq": contact, "attacker_id": id}})
	_actors = next_actors
	var next_doors: Dictionary = {}
	for door: Dictionary in state.get("doors", []):
		var id: String = str(door.get("id", ""))
		var progress: float = clampf(float(door.get("progress", 0.0)), 0.0, 1.0)
		var before: float = float(_doors.get(id, progress))
		next_doors[id] = progress
		# Light latch/handle contact follows actual movement, not a queued
		# OPEN_DOOR intention or a waiting second operator. Final contact remains
		# tied to the simulation's existing DOOR_OPEN completion event.
		if continuous and _doors.has(id) and before <= 0.025 and progress > 0.025 and progress < 1.0:
			sounds.append({"name": "door_latch", "point": [float(door.get("x", 0.0)), float(door.get("z", 0.0))], "event": {"seq": roundi(clock * 30.0), "attacker_id": id}})
	_doors = next_doors
	_clock = clock
	_mode = mode
	_playing = playing
	return sounds

func _surface(point: Vector2) -> String:
	for room: Dictionary in _rooms:
		if absf(point.x - float(room.get("x", 0.0))) <= float(room.get("w", 0.0)) * 0.5 and absf(point.y - float(room.get("z", 0.0))) <= float(room.get("d", 0.0)) * 0.5:
			var surface: String = str(room.get("floor_surface", _interior_surface))
			return surface if surface in ["wood", "concrete"] else _interior_surface
	return "concrete"
