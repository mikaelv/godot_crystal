extends Node

@export var rig: XROrigin3D
@export var camera: XRCamera3D
@export var lattice: Node3D

var _label: Label

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.position = Vector2(12, 12)
	layer.add_child(_label)

func _process(_delta: float) -> void:
	var lines := PackedStringArray()
	lines.append("WASD = move    Q/E = down/up    Shift = sprint    mouse = look    Esc = release mouse")
	lines.append("Space = next lattice step    Backspace = previous step")
	lines.append("")
	lines.append("Mouse: %s" % _mouse_mode_name())
	if camera:
		lines.append("Camera pos: %s" % _fmt_v3(camera.global_position))
	if lattice:
		lines.append("Lattice step: %s" % lattice.get("_step"))
	_label.text = "\n".join(lines)

func _fmt_v3(v: Vector3) -> String:
	return "(%+.2f, %+.2f, %+.2f)" % [v.x, v.y, v.z]

func _mouse_mode_name() -> String:
	match Input.mouse_mode:
		Input.MOUSE_MODE_VISIBLE: return "VISIBLE  (click window to recapture)"
		Input.MOUSE_MODE_CAPTURED: return "CAPTURED"
		Input.MOUSE_MODE_HIDDEN: return "HIDDEN"
		Input.MOUSE_MODE_CONFINED: return "CONFINED"
		_: return str(Input.mouse_mode)
