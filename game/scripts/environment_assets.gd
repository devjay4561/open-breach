class_name BreachEnvironmentAssets
extends RefCounted
## CC0 Kenney Furniture Kit, visual presentation only.
## Mission rectangles remain the authority for collision, visibility and navigation.

const PROCEDURAL_TYPES: Array[String] = ["vehicle", "pillar"]
const ASSETS := {
	"table": preload("res://assets/environment/table.glb"),
	"desk": preload("res://assets/environment/desk.glb"),
	"sofa": preload("res://assets/environment/loungeSofa.glb"),
	"bed": preload("res://assets/environment/bedDouble.glb"),
	"cabinet": preload("res://assets/environment/bookcaseClosedDoors.glb"),
	"bookshelf": preload("res://assets/environment/bookcaseOpen.glb"),
	"plant": preload("res://assets/environment/pottedPlant.glb"),
	"chair": preload("res://assets/environment/chairCushion.glb"),
	"crate": preload("res://assets/environment/cardboardBoxClosed.glb"),
	"rug": preload("res://assets/environment/rugRectangle.glb"),
}
const HEIGHTS := {
	"table": 0.74, "desk": 0.74, "sofa": 0.86, "bed": 0.77,
	"cabinet": 1.30, "bookshelf": 1.30, "plant": 1.10,
	"chair": 0.92, "crate": 0.68, "rug": 0.025,
}
const PALETTE := {
	"wood": Color("746753"), "woodDark": Color("48473c"),
	"metal": Color("606d67"), "carpet": Color("495e52"),
	"carpetDarker": Color("34443b"), "carpetWhite": Color("9d9f90"),
	"plant": Color("496247"),
}
static var _materials: Dictionary = {}

## Returns false only for an unknown prop type, allowing the existing fallback.
## Bounding-box normalization keeps authored furniture inside its existing map footprint.
static func create_prop(parent: Node3D, prop: Dictionary, metre_scale: bool = false) -> bool:
	var kind := str(prop.get("type", "crate"))
	if not ASSETS.has(kind):
		return false
	var placement := Node3D.new()
	placement.name = "Furniture_" + kind
	placement.position = Vector3(float(prop.x), 0.2 + float(prop.get("base_height", 0.0)), float(prop.z))
	placement.rotation.y = float(prop.get("rotation", 0.0))
	parent.add_child(placement)
	var model := (ASSETS[kind] as PackedScene).instantiate() as Node3D
	placement.add_child(model)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	if meshes.is_empty():
		placement.queue_free()
		return false
	var bounds := _model_bounds(model, meshes)
	var target := Vector3(maxf(0.1, float(prop.get("w", 1.2))), maxf(0.001, float(prop.get("height", HEIGHTS[kind]))), maxf(0.1, float(prop.get("d", 1.0))))
	if metre_scale:
		# Special operations preserve the furniture's original proportions. The
		# footprint is a clearance envelope, never permission to stretch a chair.
		var uniform_scale := target.y / maxf(bounds.size.y, 0.001)
		if prop.has("w"):
			uniform_scale = minf(uniform_scale, target.x / maxf(bounds.size.x, 0.001))
		if prop.has("d"):
			uniform_scale = minf(uniform_scale, target.z / maxf(bounds.size.z, 0.001))
		model.scale = Vector3.ONE * uniform_scale
	else:
		model.scale = target / bounds.size.max(Vector3.ONE * 0.001)
	var center := bounds.get_center()
	model.position = -Vector3(center.x, bounds.position.y, center.z) * model.scale
	for mesh in meshes:
		# The original material names survive import, so individual surfaces retain
		# authored wood/fabric/metal separation with one shared matte palette.
		if not metre_scale:
			for surface in range(mesh.mesh.get_surface_count()):
				var original := mesh.mesh.surface_get_material(surface)
				var material_name := original.resource_name if original else "wood"
				mesh.set_surface_override_material(surface, _material(material_name))
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == "rug" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return true

static func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh:
		meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child, meshes)

static func _model_bounds(model: Node3D, meshes: Array[MeshInstance3D]) -> AABB:
	var model_inverse := model.global_transform.affine_inverse()
	var bounds := model_inverse * meshes[0].global_transform * meshes[0].get_aabb()
	for mesh in meshes.slice(1):
		bounds = bounds.merge(model_inverse * mesh.global_transform * mesh.get_aabb())
	return bounds

static func _material(material_name: String) -> StandardMaterial3D:
	if _materials.has(material_name):
		return _materials[material_name]
	var material := StandardMaterial3D.new()
	material.albedo_color = PALETTE.get(material_name, Color("7c8072"))
	material.roughness = 1.0
	material.metallic = 0.0
	_materials[material_name] = material
	return material
