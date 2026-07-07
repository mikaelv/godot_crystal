extends MeshInstance3D

@export var grid_size: int = 80
@export var grid_step: float = 1.0
@export var grid_y_offset: float = 0.01
@export var grid_color: Color = Color(0.2, 0.65, 1.0, 0.35)

func _ready() -> void:
	var grid := MeshInstance3D.new()
	grid.name = "GridLines"
	grid.mesh = _make_grid_mesh()
	grid.material_override = _make_grid_material()
	add_child(grid)

func _make_grid_mesh() -> ImmediateMesh:
	var half_size := grid_size * 0.5
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var line_count := int(grid_size / grid_step)
	for i in range(line_count + 1):
		var offset := -half_size + i * grid_step
		mesh.surface_add_vertex(Vector3(offset, grid_y_offset, -half_size))
		mesh.surface_add_vertex(Vector3(offset, grid_y_offset, half_size))
		mesh.surface_add_vertex(Vector3(-half_size, grid_y_offset, offset))
		mesh.surface_add_vertex(Vector3(half_size, grid_y_offset, offset))
	mesh.surface_end()
	return mesh

func _make_grid_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = grid_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
