class_name BreachHistoricalAssets
extends RefCounted
## Source-controlled registry of metre-authored environment models.
## No mission may supply a path. Logical collision is always mission geometry.

const REGISTRY_PATH := "res://assets/historical/registry.json"
static var _registry: Dictionary = {}
static var _registry_loaded := false
static var _scenes: Dictionary = {}

static func registry() -> Dictionary:
	if not _registry_loaded:
		_registry_loaded = true
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH)) if FileAccess.file_exists(REGISTRY_PATH) else null
		if data is Dictionary:
			_registry = data
	return _registry

static func create_scenery(parent: Node3D, scenery: Dictionary) -> bool:
	var asset_id := str(scenery.get("asset", ""))
	var entries := registry()
	if not entries.has(asset_id) or not _safe_id(asset_id):
		return false
	var entry: Dictionary = entries[asset_id]
	# Models are already exported in metres. Scaling is a single scalar, so a
	# 145.5m ship can never become a stretched 30m token or change its beam.
	var factor := clampf(float(scenery.get("scale", 1.0)), 0.1, 8.0)
	if not _scenes.has(asset_id):
		var path := "res://assets/historical/" + asset_id + ".glb"
		if not ResourceLoader.exists(path):
			return false
		var resource := load(path)
		if not resource is PackedScene:
			return false
		_scenes[asset_id] = resource
	var placement := Node3D.new()
	placement.name = "Historical_" + str(scenery.get("id", asset_id))
	placement.position = Vector3(float(scenery.get("x", 0.0)), float(entry.get("floor_offset", 0.2)) + float(scenery.get("height", 0.0)), float(scenery.get("z", 0.0)))
	placement.rotation.y = float(scenery.get("rotation", 0.0))
	placement.scale = Vector3.ONE * factor
	placement.set_meta("asset_id", asset_id)
	placement.set_meta("metre_authored", true)
	placement.set_meta("dimensions_m", entry.get("dimensions_m", []))
	parent.add_child(placement)
	var model := (_scenes[asset_id] as PackedScene).instantiate() as Node3D
	placement.add_child(model)
	_prepare_model(model, entry, bool(scenery.get("cutaway", true)))
	return true

static func _safe_id(asset_id: String) -> bool:
	if asset_id.is_empty():
		return false
	for character in asset_id:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true

static func _prepare_model(node: Node, entry: Dictionary, cutaway: bool = true) -> void:
	if node is MeshInstance3D:
		# Preserve the original surfaces/PBR; observation is a separate overlay.
		# Roof/upper-shell meshes are authored separately to keep the usable
		# interior visible while maintaining the exterior's metre proportions.
		var mesh_name := str(node.name)
		if cutaway and (mesh_name.begins_with("Roof") or mesh_name.begins_with("UpperShell") or mesh_name.begins_with("UpperFloor") or mesh_name.begins_with("CabinSeats") or mesh_name in entry.get("cutaway_hide_meshes", [])):
			node.visible = false
		node.set_meta("physical_scale_preserved", true)
	for child in node.get_children():
		_prepare_model(child, entry, cutaway)
