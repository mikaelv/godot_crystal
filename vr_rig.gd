extends XROrigin3D

@export var move_speed: float = 50
@export var turn_speed: float = 1.5

@onready var xr_camera: XRCamera3D = $XRCamera3D
@onready var left_controller: XRController3D = $LeftHand
@onready var right_controller: XRController3D = $RightHand

func _ready():
	var xr_interface = XRServer.find_interface("OpenXR")
	if XrSimulator.enabled:
		if xr_interface and xr_interface.is_initialized():
			xr_interface.uninitialize()
		return
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true

func _process(delta: float) -> void:
	if left_controller:
		var move := left_controller.get_vector2("primary")
		if move != Vector2.ZERO:
			var forward := -xr_camera.global_transform.basis.z
			var right := xr_camera.global_transform.basis.x
			forward.y = 0
			right.y = 0
			forward = forward.normalized()
			right = right.normalized()
			global_translate((right * move.x + forward * move.y) * move_speed * delta)

	if right_controller:
		var turn := right_controller.get_vector2("primary")
		if turn.x != 0:
			rotate_y(-turn.x * turn_speed * delta)
