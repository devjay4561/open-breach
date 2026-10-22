class_name BreachPresentationLab
extends Node3D
## A deterministic asset preview. No combat simulation or scoring runs here.
const World = preload("res://scripts/world_view.gd")
const Door = preload("res://scripts/door_geometry.gd")
var world: Node3D
var time := 0.0
var playing := true
var scene_name := "door"
var view_name := "detail"
var mission: Dictionary

func _ready() -> void:
	mission = {"id":"LAB", "bounds":[12,9], "focus":[6,4.5],
		"rooms":[{"id":"room","label":"MOTION STUDY", "x":6,"z":4.5,"w":10,"d":7,"color":"#69756c"}],
		"walls":[{"x":3.1,"z":4,"w":4.2,"d":0.22},{"x":8.9,"z":4,"w":4.2,"d":0.22}],
		"doors":[{"id":"lab_door","x":6,"z":4,"w":1.6,"d":0.22,"axis":"x","state":"CLOSED","progress":0.0,"swing_sign":1.0}],
		"props":[{"type":"desk","x":3,"z":2.5,"w":1.4,"d":0.7,"solid":true},{"type":"chair","x":3,"z":3.25,"w":0.6,"d":0.6,"solid":true},{"type":"plant","x":9,"z":2,"w":0.55,"d":0.55,"solid":false}],
		"units":[{"x":6.544,"z":4.4}],"enemies":[],"civilians":[]}
	world = World.new()
	add_child(world)
	world.build(mission)
	world.set_settings({"fov":false})
	tick(0.0)

func tick(delta: float) -> void:
	if playing:
		time = fposmod(time + minf(delta, 0.1), 4.0)
	var unit: Dictionary = {"id":"lab_actor", "name":"동작 검증", "kind":"unit", "x":6.544,"z":4.4,"hp":100,"weapon":"standard","facing":-PI*0.5,"aim_facing":-PI*0.5,"move_facing":-PI*0.5,"travel_distance":0.0,"status":"READY","commands":[]}
	var door: Dictionary = mission.doors[0].duplicate(true)
	if scene_name == "door":
		door.owner_id = "lab_actor"
		door.progress = clampf((time - 0.6) / 1.6, 0.0, 1.0)
		door.state = "OPEN" if time >= 2.2 else ("OPENING" if time >= 0.6 else "CLOSED")
		if time >= 0.6 and time < 2.2:
			unit.status = "OPENING"
			unit.commands = [{"type":"OPEN_DOOR","state":"RUNNING","args":{"door_id":"lab_door"},"remaining":(1.0-door.progress)*0.8}]
	elif scene_name in ["walk","side","back"]:
		unit.x = 4.8 + time * 0.65
		unit.z = 5.5
		unit.kind = "enemy" # Select the authored walk cadence, without creating a threat.
		unit.status = "MOVING"
		unit.travel_distance = time * 0.65
		unit.move_facing = 0.0
		unit.aim_facing = 0.0 if scene_name == "walk" else (PI if scene_name == "back" else -PI*0.5)
	elif scene_name == "turn":
		unit.x = 6.2
		unit.z = 5.5
		if time >= 0.8:
			unit.facing = 0.0
			unit.aim_facing = 0.0
			unit.turn_started_at = 0.8
			unit.turn_delta = PI * 0.5 if time < 1.55 else 0.0
	elif scene_name == "transitions":
		unit.kind = "enemy"
		unit.x = 5.0
		unit.z = 5.5
		unit.facing = 0.0
		unit.aim_facing = 0.0
		unit.move_facing = 0.0
		unit.travel_distance = clampf(time - 0.45, 0.0, 2.7) * 0.65
		unit.x += clampf(time - 0.45, 0.0, 0.9) * 0.65
		unit.z += clampf(time - 1.35, 0.0, 0.9) * 0.65
		unit.x -= clampf(time - 2.25, 0.0, 0.9) * 0.65
		if time >= 0.45 and time < 3.15:
			unit.status = "MOVING"
			unit.move_facing = 0.0 if time < 1.35 else (PI * 0.5 if time < 2.25 else PI)
		if time >= 3.25:
			unit.facing = PI * 0.5
			unit.aim_facing = PI * 0.5
			unit.turn_started_at = 3.25
			unit.turn_delta = PI * 0.5
	elif scene_name == "reload":
		unit.x = 6.2
		unit.z = 5.5
		unit.status = "RELOADING"
		unit.commands = [{"type":"RELOAD","state":"RUNNING","remaining":1.8*(1.0-time/4.0)}]
	var state := {"time":time,"presentation_time":time,"tick":int(time*30),"presentation_paused":not playing,"units":[unit],"enemies":[],"civilians":[],"doors":[door],"events":[],"settings":{"fov":false}}
	world.display(state, "", false, delta)
	for entry: Dictionary in world._entity_nodes.values():
		for key: String in ["label", "status", "ring", "selection", "arrow"]:
			entry[key].hide()
	for entry: Dictionary in world._door_nodes.values():
		entry.label.hide()
	_camera()

func configure(data: Dictionary) -> void:
	if data.get("scene", "") in ["door","walk","side","back","reload","turn","transitions"]:
		scene_name = data.scene
		time = 0.0
	if data.get("view", "") in ["detail","top","side"]:
		view_name = data.view
	if data.get("toggle", false):
		playing = not playing
	if data.has("seek") and (data.seek is float or data.seek is int) and is_finite(float(data.seek)):
		time = clampf(float(data.seek), 0.0, 3.999)
		playing = false
	if data.has("seek") or data.has("scene"):
		for entry: Dictionary in world._entity_nodes.values():
			entry.last_time = -1.0
			entry.visual.last_clock = -1.0
			entry.visual.move_until = -1.0
			entry.visual.clip = ""
			entry.visual.lower_key = ""
	tick(0.0)

func _camera() -> void:
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var focus := Vector3(6.3,0.8,4.5)
	if view_name == "top":
		world.camera.size = 7.0
		world.camera.position = Vector3(6.3,10,7.0)
	elif view_name == "side":
		world.camera.size = 3.5
		world.camera.position = Vector3(11,2.5,5.1)
	else:
		world.camera.size = 4.6
		world.camera.position = Vector3(9.5,5.0,9.0)
	world.camera.look_at(focus)

func payload() -> Dictionary:
	return {"type":"state","mode":"LAB","time":time,"scene":scene_name,"view":view_name,"playing":playing,"duration":4.0}
