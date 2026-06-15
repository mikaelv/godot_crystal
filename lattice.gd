extends Node3D
class_name Lattice

## Procedural silicon diamond-cubic lattice, revealed step by step.
##
## Coordinates are in *quarter-cell units* (Vector3i), so the conventional
## cubic cell spans (0,0,0)–(4,4,4). Sublattice A: i+j+k ≡ 0 (mod 4) —
## corners and face centres. Sublattice B: i+j+k ≡ 3 (mod 4) — interior sites.
##
## The reveal centres on the interior B atom at (1,1,1), which is the centre
## of a perfect tetrahedron of A atoms — pedagogically the cleanest entry
## point for the 109.47° bond-angle insight.

const A: float = 4.0                          # lattice constant (scene units)
const CELL_SIZE: int = 4                      # in quarter-cell units
const ATOM_RADIUS: float = 0.45
const BOND_RADIUS: float = 0.10
const COLOR_A := Color(0.45, 0.65, 0.95)      # sublattice A (blue)
const COLOR_B := Color(0.95, 0.55, 0.40)      # sublattice B (orange)
const COLOR_BOND := Color(0.75, 0.75, 0.78)
const COLOR_CELL := Color(1.0, 0.95, 0.3)
const COLOR_CELL_NEIGHBOR := Color(0.55, 0.5, 0.2)

# Bond offsets from a sublattice-A atom. From a B atom the offsets are negated.
const BONDS_A_TO_B: Array[Vector3i] = [
	Vector3i( 1,  1,  1),
	Vector3i( 1, -1, -1),
	Vector3i(-1,  1, -1),
	Vector3i(-1, -1,  1),
]

# The B atom we radiate from — sits inside the unit cell.
const CENTRAL_B := Vector3i(1, 1, 1)
# Its 4 A neighbours, all inside the unit cell, forming a regular tetrahedron.
const TETRAHEDRON_A: Array[Vector3i] = [
	Vector3i(0, 0, 0),
	Vector3i(2, 2, 0),
	Vector3i(2, 0, 2),
	Vector3i(0, 2, 2),
]
# The 3 other interior B atoms of the unit cell.
const OTHER_INTERIOR_B: Array[Vector3i] = [
	Vector3i(3, 3, 1),
	Vector3i(3, 1, 3),
	Vector3i(1, 3, 3),
]
# The 4 corners that aren't reached by any of our cell's interior B atoms —
# they bond to B atoms in neighbouring cells.
const LONE_CORNERS: Array[Vector3i] = [
	Vector3i(4, 0, 0), Vector3i(0, 4, 0), Vector3i(0, 0, 4), Vector3i(4, 4, 4),
]

# All 18 atom positions of one complete unit cell, for the tiling step.
const UNIT_CELL_A: Array[Vector3i] = [
	Vector3i(0,0,0), Vector3i(4,0,0), Vector3i(0,4,0), Vector3i(0,0,4),
	Vector3i(4,4,0), Vector3i(4,0,4), Vector3i(0,4,4), Vector3i(4,4,4),
	Vector3i(2,2,0), Vector3i(2,0,2), Vector3i(0,2,2),
	Vector3i(4,2,2), Vector3i(2,4,2), Vector3i(2,2,4),
]
const UNIT_CELL_B: Array[Vector3i] = [
	Vector3i(1,1,1), Vector3i(3,3,1), Vector3i(3,1,3), Vector3i(1,3,3),
]

@export var right_controller: XRController3D
@export var advance_button: StringName = &"ax_button"
@export var retreat_button: StringName = &"by_button"

var _step: int = 0
var _step_nodes: Array[Node3D] = []
var _atoms: Dictionary = {}

func _ready() -> void:
	if right_controller:
		right_controller.button_pressed.connect(_on_button)
	_advance()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_advance()
		elif event.keycode == KEY_BACKSPACE:
			_retreat()

func _on_button(p_name: String) -> void:
	if p_name == advance_button:
		_advance()
	elif p_name == retreat_button:
		_retreat()

func _advance() -> void:
	var container := Node3D.new()
	add_child(container)
	var ok := _run_step(_step + 1, container)
	if ok:
		_step_nodes.append(container)
		_step += 1
	else:
		container.queue_free()

func _retreat() -> void:
	if _step_nodes.is_empty():
		return
	var container: Node3D = _step_nodes.pop_back()
	for child in container.get_children():
		if child.has_meta("qc"):
			_atoms.erase(child.get_meta("qc"))
	container.queue_free()
	_step -= 1

func _run_step(step: int, container: Node3D) -> bool:
	match step:
		1: _spawn_atom(container, CENTRAL_B, COLOR_B)
		2: _step_central_bonds(container)
		3: _step_tetrahedron_atoms(container)
		4: _step_a_outward_bonds(container)
		5: _step_other_interior_b(container)
		6: _step_far_atoms_and_bonds(container)
		7: _spawn_cube(container, Vector3i.ZERO, COLOR_CELL, 0.04)
		8: _step_tile_supercell(container)
		_: return false
	return true

# --- Steps --------------------------------------------------------------------

# Step 2: 4 tetrahedral bonds from the central B atom (the 109.47° reveal).
func _step_central_bonds(container: Node3D) -> void:
	for d in BONDS_A_TO_B:
		_spawn_bond(container, CENTRAL_B, CENTRAL_B - d)
	_spawn_angle_indicator(container, BONDS_A_TO_B[0], BONDS_A_TO_B[1])

# Draws an arc between two of the central B atom's bonds and floats a
# "109.47°" label at the arc midpoint, anchoring the bond-angle insight.
func _spawn_angle_indicator(container: Node3D, d1: Vector3i, d2: Vector3i) -> void:
	var center := _qc_to_world(CENTRAL_B)
	# Bond directions from the B atom toward its A neighbours.
	var dir1 := -Vector3(d1).normalized()
	var dir2 := -Vector3(d2).normalized()
	var axis := dir1.cross(dir2).normalized()
	var total := dir1.angle_to(dir2)
	var arc_radius := 0.7
	var segments := 24
	var prev := center + dir1 * arc_radius
	for i in range(1, segments + 1):
		var t := float(i) / float(segments)
		var rotated := dir1.rotated(axis, total * t)
		var curr := center + rotated * arc_radius
		_spawn_segment(container, prev, curr, COLOR_CELL, 0.025)
		prev = curr
	var mid_dir := dir1.slerp(dir2, 0.5).normalized()
	var label := Label3D.new()
	label.text = "109.47°"
	label.font_size = 96
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = COLOR_CELL
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.outline_size = 12
	label.position = center + mid_dir * (arc_radius + 0.6)
	container.add_child(label)

# Step 3: the 4 A atoms forming the tetrahedron around the central B atom.
func _step_tetrahedron_atoms(container: Node3D) -> void:
	for a in TETRAHEDRON_A:
		_spawn_atom(container, a, COLOR_A)

# Step 4: each of those 4 A atoms has 3 more bonds. Some head into the cube
# (toward the other interior B atoms), others hang out toward neighbouring cells.
func _step_a_outward_bonds(container: Node3D) -> void:
	for a in TETRAHEDRON_A:
		for d in BONDS_A_TO_B:
			var target: Vector3i = a + d
			if target == CENTRAL_B:
				continue
			_spawn_bond(container, a, target)

# Step 5: the 3 remaining interior B atoms appear at the inward bond tips.
func _step_other_interior_b(container: Node3D) -> void:
	for b in OTHER_INTERIOR_B:
		_spawn_atom(container, b, COLOR_B)

# Step 6: bonds from the 3 new B atoms reach the far face centres and corners,
# completing the unit cell's atom content. Four corner atoms whose bonds all
# leave the cell are added explicitly so the cube isn't missing corners.
func _step_far_atoms_and_bonds(container: Node3D) -> void:
	for b in OTHER_INTERIOR_B:
		for d in BONDS_A_TO_B:
			var target: Vector3i = b - d
			if target in TETRAHEDRON_A:
				continue
			_spawn_bond(container, b, target)
			_spawn_atom(container, target, COLOR_A)
	for corner in LONE_CORNERS:
		_spawn_atom(container, corner, COLOR_A)

# Step 8: tile our cell into a 2×2×2 supercell — 7 more cells at offsets in {0, 4}^3.
func _step_tile_supercell(container: Node3D) -> void:
	for ox in [0, CELL_SIZE]:
		for oy in [0, CELL_SIZE]:
			for oz in [0, CELL_SIZE]:
				if ox == 0 and oy == 0 and oz == 0:
					continue
				var off := Vector3i(ox, oy, oz)
				_spawn_unit_cell(container, off)
				_spawn_cube(container, off, COLOR_CELL_NEIGHBOR, 0.025)

# --- Helpers ------------------------------------------------------------------

func _spawn_unit_cell(container: Node3D, offset: Vector3i) -> void:
	for a in UNIT_CELL_A:
		_spawn_atom(container, a + offset, COLOR_A)
	for b in UNIT_CELL_B:
		_spawn_atom(container, b + offset, COLOR_B)
		for d in BONDS_A_TO_B:
			_spawn_bond(container, b + offset, b + offset - d)

func _spawn_cube(container: Node3D, offset: Vector3i, color: Color, radius: float) -> void:
	var n := CELL_SIZE
	var c := [
		Vector3i(0,0,0), Vector3i(n,0,0), Vector3i(0,n,0), Vector3i(n,n,0),
		Vector3i(0,0,n), Vector3i(n,0,n), Vector3i(0,n,n), Vector3i(n,n,n),
	]
	var edges := [
		[0,1],[0,2],[1,3],[2,3],
		[4,5],[4,6],[5,7],[6,7],
		[0,4],[1,5],[2,6],[3,7],
	]
	for e in edges:
		_spawn_edge(container, c[e[0]] + offset, c[e[1]] + offset, color, radius)

# --- Primitives ---------------------------------------------------------------

func _qc_to_world(qc: Vector3i) -> Vector3:
	return Vector3(qc) * (A / 4.0)

func _spawn_atom(container: Node3D, qc: Vector3i, color: Color) -> void:
	if _atoms.has(qc):
		return
	var mesh := SphereMesh.new()
	mesh.radius = ATOM_RADIUS
	mesh.height = ATOM_RADIUS * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _flat_material(color)
	mi.position = _qc_to_world(qc)
	mi.set_meta("qc", qc)
	container.add_child(mi)
	_atoms[qc] = mi

func _spawn_bond(container: Node3D, qc_a: Vector3i, qc_b: Vector3i) -> void:
	_spawn_edge(container, qc_a, qc_b, COLOR_BOND, BOND_RADIUS)

func _spawn_edge(container: Node3D, qc_a: Vector3i, qc_b: Vector3i, color: Color, radius: float) -> void:
	_spawn_segment(container, _qc_to_world(qc_a), _qc_to_world(qc_b), color, radius)

func _spawn_segment(container: Node3D, a: Vector3, b: Vector3, color: Color, radius: float) -> void:
	var length := a.distance_to(b)
	if length < 0.0001:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _flat_material(color)
	mi.position = (a + b) * 0.5
	var dir := (b - a).normalized()
	var up := Vector3.UP
	var dot := up.dot(dir)
	if dot < 0.9999 and dot > -0.9999:
		mi.basis = Basis(up.cross(dir).normalized(), up.angle_to(dir))
	elif dot < 0.0:
		mi.basis = Basis(Vector3.RIGHT, PI)
	container.add_child(mi)

func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	return mat
