extends Node3D
class_name Lattice

## Procedural silicon diamond-cubic lattice, revealed step by step.
##
## Coordinates are stored in *quarter-cell units* (Vector3i), so the 8 atoms
## of the conventional unit cell sit on the integer grid {0, 1, 2, 3, 4}.
## Sublattice A: i+j+k ≡ 0 (mod 4). Sublattice B: i+j+k ≡ 3 (mod 4).

const A: float = 4.0                  # lattice constant (scene units)
const ATOM_RADIUS: float = 0.45
const BOND_RADIUS: float = 0.10
const COLOR_A := Color(0.45, 0.65, 0.95)   # sublattice A (blue)
const COLOR_B := Color(0.95, 0.55, 0.40)   # sublattice B (orange)
const COLOR_BOND := Color(0.75, 0.75, 0.78)
const COLOR_CELL := Color(1.0, 0.95, 0.3)

# Four tetrahedral bond offsets from a sublattice-A atom (in quarter-cell units).
const BONDS_A_TO_B: Array[Vector3i] = [
	Vector3i( 1,  1,  1),
	Vector3i( 1, -1, -1),
	Vector3i(-1,  1, -1),
	Vector3i(-1, -1,  1),
]

@export var right_controller: XRController3D
@export var advance_button: StringName = &"ax_button"
@export var retreat_button: StringName = &"by_button"

var _step: int = 0
var _step_nodes: Array[Node3D] = []     # one container per step (for undo)
var _atoms: Dictionary = {}             # Vector3i -> MeshInstance3D

func _ready() -> void:
	if right_controller:
		right_controller.button_pressed.connect(_on_button)
	_advance()  # show step 1 immediately

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

# --- Step machinery -----------------------------------------------------------

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
		1: _add_central_atom(container)
		2: _add_central_bonds(container)
		3: _add_first_neighbors(container)
		4: _add_second_shell(container)
		5: _add_unit_cell_wireframe(container)
		_: return false
	return true

# --- Steps --------------------------------------------------------------------

func _add_central_atom(container: Node3D) -> void:
	_spawn_atom(container, Vector3i.ZERO, COLOR_A)

func _add_central_bonds(container: Node3D) -> void:
	for d in BONDS_A_TO_B:
		_spawn_bond(container, Vector3i.ZERO, d)

func _add_first_neighbors(container: Node3D) -> void:
	for d in BONDS_A_TO_B:
		_spawn_atom(container, d, COLOR_B)

func _add_second_shell(container: Node3D) -> void:
	# Each sublattice-B atom has 4 bonds: one back to centre, three outward.
	# Outward directions are the negation of BONDS_A_TO_B, minus the one
	# pointing back to the origin.
	for b in BONDS_A_TO_B:
		for d in BONDS_A_TO_B:
			var next := b - d   # subtract: from B atom, go in -d direction
			if next == Vector3i.ZERO:
				continue
			_spawn_bond(container, b, next)
			_spawn_atom(container, next, COLOR_A)

func _add_unit_cell_wireframe(container: Node3D) -> void:
	var n := 4   # one unit cell = 4 quarter-cells along each axis
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
		_spawn_edge(container, c[e[0]], c[e[1]], COLOR_CELL, 0.04)

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
	var a := _qc_to_world(qc_a)
	var b := _qc_to_world(qc_b)
	var length := a.distance_to(b)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _flat_material(color)
	mi.position = (a + b) * 0.5
	# CylinderMesh runs along +Y by default. Rotate so it points a → b.
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
