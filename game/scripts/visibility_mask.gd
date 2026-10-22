extends Node2D
## GPU coverage of continuous polygons; the history viewport retains its pixels.
var _mesh := ArrayMesh.new()

func set_polygons(polygons: Array[PackedVector2Array], scale_to_pixels: Vector2) -> ArrayMesh:
	var vertices := PackedVector2Array()
	for polygon: PackedVector2Array in polygons:
		for i in range(1, polygon.size() - 1):
			vertices.append(polygon[0] * scale_to_pixels)
			vertices.append(polygon[i] * scale_to_pixels)
			vertices.append(polygon[i + 1] * scale_to_pixels)
	_mesh.clear_surfaces()
	if not vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	queue_redraw()
	return _mesh

func set_mesh(mesh: ArrayMesh) -> void:
	_mesh = mesh
	queue_redraw()

func _draw() -> void:
	if _mesh.get_surface_count() > 0:
		draw_mesh(_mesh, null)
