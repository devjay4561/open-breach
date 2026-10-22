extends RefCounted
## Exact all-left JSON fixture from room_drill_replay_test.gd.
## This pure helper preserves the reproducer without creating a second SceneTree.
static func make(seed_value: int = 0) -> Dictionary:
	var units: Array = []
	for index: int in range(4):
		var id: String = ["alpha", "bravo", "charlie", "delta"][index]
		# Authored mission numbers use ordinary JSON decimals. Irrational
		# geometry remains in the generated macro, where round trips are tested.
		units.append({"id":id, "name":id.to_upper(), "role":"Assault", "weapon":"standard", "x":7.1, "z":9.5 + index * 0.7, "facing":-1.57})
	var mission := {"schema_version":3, "id":"ROOM_DRILL_REPLAY", "revision":1, "custom":true, "title":"Drill replay fixture", "seed":seed_value, "variant":"normal", "bounds":[16,16], "focus":[8,8], "rooms":[{"id":"room", "x":8.0, "z":6.0, "w":5.0, "d":5.0}, {"id":"hidden", "x":13.0, "z":3.0, "w":2.0, "d":2.0}], "walls":[{"id":"left", "x":5.4, "z":6.0, "w":0.2, "d":5.4}, {"id":"right", "x":10.6, "z":6.0, "w":0.2, "d":5.4}, {"id":"top", "x":8.0, "z":3.4, "w":5.4, "d":0.2}, {"id":"bottom_left", "x":6.15, "z":8.5, "w":1.3, "d":0.2}, {"id":"bottom_right", "x":9.85, "z":8.5, "w":1.3, "d":0.2}, {"id":"hidden_left", "x":11.9, "z":3.0, "w":0.2, "d":2.4}, {"id":"hidden_right", "x":14.1, "z":3.0, "w":0.2, "d":2.4}, {"id":"hidden_top", "x":13.0, "z":1.9, "w":2.4, "d":0.2}, {"id":"hidden_bottom_left", "x":12.1, "z":4.1, "w":0.4, "d":0.2}, {"id":"hidden_bottom_right", "x":13.9, "z":4.1, "w":0.4, "d":0.2}], "doors":[{"id":"door", "x":8.0, "z":8.5, "w":2.4, "d":0.24, "axis":"x", "state":"CLOSED", "hinge_side":-1.0, "swing_sign":-1.0, "locked":false}, {"id":"hidden_door", "x":13.0, "z":4.1, "w":1.4, "d":0.24, "axis":"x", "state":"CLOSED", "hinge_side":-1.0, "swing_sign":-1.0, "locked":false}], "props":[], "units":units, "enemies":[{"id":"hidden_enemy", "x":12.5, "z":2.7, "facing":0.0, "ammo":0, "training":true, "passive":true}], "civilians":[{"id":"hidden_civilian", "x":13.6, "z":3.2}], "objectives":["Enter the room"], "win":[{"type":"reach_zone", "zone":[15.0,15.0,0.2,0.2]}], "fail":[], "stars":[]}
	# Match the real mission-file path: JSON numbers load as floats, including
	# schema integers. This keeps strict Main plan equality about saved data.
	return JSON.parse_string(JSON.stringify(mission))

