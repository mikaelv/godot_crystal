extends Node

@onready var rig: XROrigin3D = $"../VRRig"
@onready var camera: XRCamera3D = $"../VRRig/XRCamera3D"
@onready var left_controller: XRController3D = $"../VRRig/LeftHand"
@onready var lattice: Node3D = $"../Lattice"

# Desktop/web flat view: 2D overlay.
var _layer: CanvasLayer
var _label_2d: Label

# XR: a head-locked Label3D, since CanvasLayer doesn't render in stereo.
var _label_3d: Label3D

var _visible: bool = true

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_label_2d = Label.new()
	_label_2d.add_theme_font_size_override("font_size", 18)
	_label_2d.add_theme_color_override("font_color", Color.WHITE)
	_label_2d.add_theme_color_override("font_outline_color", Color.BLACK)
	_label_2d.add_theme_constant_override("outline_size", 4)
	_label_2d.position = Vector2(12, 12)
	_layer.add_child(_label_2d)

	_label_3d = Label3D.new()
	_label_3d.pixel_size = 0.002
	_label_3d.font_size = 32
	_label_3d.outline_size = 6
	_label_3d.modulate = Color.WHITE
	_label_3d.outline_modulate = Color.BLACK
	_label_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label_3d.no_depth_test = true
	_label_3d.render_priority = 1
	_label_3d.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# 2.5 m in front of the head, slightly below-left of eye-line.
	_label_3d.position = Vector3(-1.0, -0.4, -2.5)
	if camera:
		camera.add_child(_label_3d)

	if left_controller:
		left_controller.button_pressed.connect(_on_left_button)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_visible = not _visible

func _on_left_button(name: String) -> void:
	if name == "by_button":
		_visible = not _visible

func _process(_delta: float) -> void:
	var xr := get_viewport().use_xr
	_layer.visible = _visible and not xr
	_label_3d.visible = _visible and xr
	if not _visible:
		return
	var lines := PackedStringArray()
	if xr:
		lines.append("Left Y = hide/show HUD")
		lines.append("Left stick = move   Right stick X = turn   Y = up/down")
		lines.append("Right A = step+   Right B = step-")
		lines.append("Right grip + A/B = shell +/-")
		lines.append("Left X = space-filling")
	else:
		lines.append("H = hide/show HUD")
		lines.append("WASD = move   Q/E = down/up   Shift = sprint")
		lines.append("Mouse = look   Esc = release mouse")
		lines.append("Space/Backspace = step   Tab/Shift+Tab = shell   B = space-filling")
		lines.append("1 corners (green)  2 faces (blue)  3 B atoms (orange)  4 cubes  5 bonds")
	lines.append("")
	if not xr:
		lines.append("Mouse: %s" % _mouse_mode_name())
	if camera:
		lines.append("Camera pos: %s" % _fmt_v3(camera.global_position))
	if lattice:
		var fill := "space-filling (transparent)" if lattice.get("_space_filling") else "ball-and-stick"
		lines.append("Lattice step: %s    View: %s" % [lattice.get("_step"), fill])
	var text := "\n".join(lines)
	if xr:
		_label_3d.text = text
	else:
		_label_2d.text = text

func _fmt_v3(v: Vector3) -> String:
	return "(%+.2f, %+.2f, %+.2f)" % [v.x, v.y, v.z]

func _mouse_mode_name() -> String:
	match Input.mouse_mode:
		Input.MOUSE_MODE_VISIBLE: return "VISIBLE  (click window to recapture)"
		Input.MOUSE_MODE_CAPTURED: return "CAPTURED"
		Input.MOUSE_MODE_HIDDEN: return "HIDDEN"
		Input.MOUSE_MODE_CONFINED: return "CONFINED"
		_: return str(Input.mouse_mode)
