extends XROrigin3D

## Rig that supports both real XR (controllers + headset) and a desktop
## free-fly fallback (WASD + mouse) for development without a headset.

@export var move_speed: float = 4.0           # m/s — desktop and XR thumbstick
@export var look_sensitivity: float = 0.0025  # desktop mouse-look
@export var turn_speed: float = 1.5           # XR right-stick yaw

@onready var xr_camera: XRCamera3D = $XRCamera3D
@onready var left_controller: XRController3D = $LeftHand
@onready var right_controller: XRController3D = $RightHand

var _xr_active: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0

func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		get_viewport().use_xr = true
		_xr_active = true
		# AR: if the headset can do passthrough, switch the compositor to
		# alpha-blend so transparent pixels reveal the camera feed.
		if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in xr.get_supported_environment_blend_modes():
			xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
			get_viewport().transparent_bg = true
		return
	# Desktop free-fly: put the camera at eye height with no XR offset,
	# back the rig away from the lattice so we can see it on spawn.
	xr_camera.position = Vector3(0, 1.6, 0)
	xr_camera.current = true
	global_position = Vector3(0, 0, 6)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if _xr_active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * look_sensitivity
		_pitch = clamp(_pitch - event.relative.y * look_sensitivity, -PI * 0.49, PI * 0.49)
		xr_camera.rotation = Vector3(_pitch, _yaw, 0)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if _xr_active:
		_process_xr(delta)
	else:
		_process_desktop(delta)

func _process_desktop(delta: float) -> void:
	var input := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): input.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S): input.z += 1.0
	if Input.is_physical_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): input.x += 1.0
	if Input.is_physical_key_pressed(KEY_E): input.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q): input.y -= 1.0
	if input == Vector3.ZERO:
		return
	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 3.0
	# Camera-local input → world, so W follows where you're looking.
	var world_move := xr_camera.global_transform.basis * input.normalized()
	global_translate(world_move * speed * delta)

func _process_xr(delta: float) -> void:
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
		if turn.x != 0.0:
			rotate_y(-turn.x * turn_speed * delta)
