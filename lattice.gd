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
# How far the tiling extends (in cells) in each direction. radius=2 means
# the lattice grows to a 5×5×5 supercell (124 tile steps + the original cell).
# Each cell adds ~18 mesh instances after dedup; 5×5×5 stays comfortably
# under a few thousand draws. Raise carefully for VR — perf scales with cells³.
@export_range(1, 4, 1) var max_tile_radius: int = 2

var _step: int = 0
var _step_nodes: Array[Node3D] = []
var _atoms: Dictionary = {}
var _bonds_drawn: Dictionary = {}  # canonical bond key -> true, to dedupe
var _tile_offsets: Array[Vector3i] = []  # ordered list of cells to reveal

func _ready() -> void:
	_build_tile_sequence()
	if right_controller:
		right_controller.button_pressed.connect(_on_button)
	_advance()

# Enumerates all cells within ±max_tile_radius of the original, sorted so the
# closest cells in the +X+Y+Z octant come first (preserving the previous order
# of the 7 starter tiles), then expanding outward in concentric shells.
func _build_tile_sequence() -> void:
	_tile_offsets.clear()
	for i in range(-max_tile_radius, max_tile_radius + 1):
		for j in range(-max_tile_radius, max_tile_radius + 1):
			for k in range(-max_tile_radius, max_tile_radius + 1):
				if i == 0 and j == 0 and k == 0:
					continue
				_tile_offsets.append(Vector3i(i * CELL_SIZE, j * CELL_SIZE, k * CELL_SIZE))
	_tile_offsets.sort_custom(_compare_tile_offsets)

func _compare_tile_offsets(a: Vector3i, b: Vector3i) -> bool:
	# Chebyshev distance: cells inside a smaller bounding box come first.
	var cheby_a: int = maxi(maxi(absi(a.x), absi(a.y)), absi(a.z))
	var cheby_b: int = maxi(maxi(absi(b.x), absi(b.y)), absi(b.z))
	if cheby_a != cheby_b:
		return cheby_a < cheby_b
	# Within a shell: fewer negative coords first (so +X+Y+Z octant leads).
	var neg_a: int = int(a.x < 0) + int(a.y < 0) + int(a.z < 0)
	var neg_b: int = int(b.x < 0) + int(b.y < 0) + int(b.z < 0)
	if neg_a != neg_b:
		return neg_a < neg_b
	# Then Manhattan: faces, then edges, then corners.
	var manh_a: int = absi(a.x) + absi(a.y) + absi(a.z)
	var manh_b: int = absi(b.x) + absi(b.y) + absi(b.z)
	if manh_a != manh_b:
		return manh_a < manh_b
	# Lex tiebreak.
	if a.x != b.x: return a.x > b.x
	if a.y != b.y: return a.y > b.y
	return a.z > b.z

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
		if child.has_meta("bond_key"):
			_bonds_drawn.erase(child.get_meta("bond_key"))
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
		8: _spawn_cell_a_bonds(container, Vector3i.ZERO)
		_:
			if step >= 9 and step < 9 + _tile_offsets.size():
				_step_add_tile(container, step - 9)
			else:
				return false
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
# (toward the other interior B atoms), others hang out toward neighbouring cells —
# the boundary-dangler step will not redraw them thanks to bond dedup.
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

# Each press past step 8 adds one neighbouring unit cell, working outward in
# concentric shells. Each tile draws its own A-atom outward bonds, so the same
# dangler-and-link pattern repeats consistently from cell to cell.
func _step_add_tile(container: Node3D, idx: int) -> void:
	var offset: Vector3i = _tile_offsets[idx]
	_spawn_unit_cell(container, offset)
	_spawn_cell_a_bonds(container, offset)
	_spawn_cube(container, offset, COLOR_CELL_NEIGHBOR, 0.025)

# Draws all 4 tetrahedral bonds from every A atom in the unit cell at `offset`.
# Used both for the post-cube "preview" step and for each tile — dedup means
# bonds shared between cells collapse, bonds reaching outside the supercell
# remain as dangling stubs.
func _spawn_cell_a_bonds(container: Node3D, offset: Vector3i) -> void:
	for a in UNIT_CELL_A:
		var a_pos: Vector3i = a + offset
		for d in BONDS_A_TO_B:
			_spawn_bond(container, a_pos, a_pos + d)

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
	var key := _bond_key(qc_a, qc_b)
	if _bonds_drawn.has(key):
		return
	var mi := _make_segment(_qc_to_world(qc_a), _qc_to_world(qc_b), COLOR_BOND, BOND_RADIUS)
	if mi == null:
		return
	mi.set_meta("bond_key", key)
	_bonds_drawn[key] = true
	container.add_child(mi)

func _bond_key(qc_a: Vector3i, qc_b: Vector3i) -> String:
	# Canonical (unordered) key so a bond drawn from either side dedupes.
	var sa := "%d,%d,%d" % [qc_a.x, qc_a.y, qc_a.z]
	var sb := "%d,%d,%d" % [qc_b.x, qc_b.y, qc_b.z]
	if sa < sb:
		return sa + "|" + sb
	return sb + "|" + sa

func _spawn_edge(container: Node3D, qc_a: Vector3i, qc_b: Vector3i, color: Color, radius: float) -> void:
	_spawn_segment(container, _qc_to_world(qc_a), _qc_to_world(qc_b), color, radius)

func _spawn_segment(container: Node3D, a: Vector3, b: Vector3, color: Color, radius: float) -> void:
	var mi := _make_segment(a, b, color, radius)
	if mi:
		container.add_child(mi)

func _make_segment(a: Vector3, b: Vector3, color: Color, radius: float) -> MeshInstance3D:
	var length := a.distance_to(b)
	if length < 0.0001:
		return null
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
	return mi

func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	return mat
