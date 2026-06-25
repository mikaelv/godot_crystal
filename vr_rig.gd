extends XROrigin3D

## Rig that supports three flavours of XR/non-XR:
## - Real OpenXR (Windows/Linux desktop with a PCVR headset): auto-starts.
## - WebXR (browser, e.g. Quest browser): requires a user click on the
##   "Enter VR" button, since browsers disallow auto-starting immersive
##   sessions. Until the user clicks, the page behaves as desktop free-fly.
## - Desktop free-fly fallback (WASD + mouse): for development without a
##   headset, also the default state of the web build before clicking VR.

@export var move_speed: float = 4.0           # m/s — desktop and XR thumbstick
@export var look_sensitivity: float = 0.0025  # desktop mouse-look
@export var turn_speed: float = 1.5           # XR right-stick yaw

@onready var xr_camera: XRCamera3D = $XRCamera3D
@onready var left_controller: XRController3D = $LeftHand
@onready var right_controller: XRController3D = $RightHand

var _xr_active: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0

var _webxr_interface: WebXRInterface
var _enter_vr_button: Button

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
	# WebXR (web export only — XRServer doesn't expose this interface on
	# desktop). We can't initialize the session until the user clicks, so
	# wire signals and show a button; meanwhile run the desktop fallback.
	_webxr_interface = XRServer.find_interface("WebXR") as WebXRInterface
	if _webxr_interface:
		_webxr_interface.session_supported.connect(_on_webxr_session_supported)
		_webxr_interface.session_started.connect(_on_webxr_session_started)
		_webxr_interface.session_ended.connect(_on_webxr_session_ended)
		_webxr_interface.session_failed.connect(_on_webxr_session_failed)
		_webxr_interface.is_session_supported("immersive-vr")
		_setup_enter_vr_button()
	# Desktop free-fly: put the camera at eye height with no XR offset,
	# back the rig away from the lattice so we can see it on spawn.
	xr_camera.position = Vector3(0, 1.6, 0)
	xr_camera.current = true
	global_position = Vector3(0, 0, 6)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Tiny on-screen button shown only when the browser reports an immersive-vr
# session is available. Clicking it triggers initialize() from inside the
# user gesture, which is the only context browsers allow it from.
func _setup_enter_vr_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 101
	add_child(layer)
	_enter_vr_button = Button.new()
	_enter_vr_button.text = "  Enter VR  "
	_enter_vr_button.add_theme_font_size_override("font_size", 28)
	_enter_vr_button.position = Vector2(20, 80)
	_enter_vr_button.visible = false
	_enter_vr_button.pressed.connect(_enter_webxr)
	layer.add_child(_enter_vr_button)

func _on_webxr_session_supported(session_mode: String, supported: bool) -> void:
	if session_mode == "immersive-vr" and supported and _enter_vr_button:
		_enter_vr_button.visible = true

func _enter_webxr() -> void:
	if _webxr_interface == null:
		return
	_webxr_interface.session_mode = "immersive-vr"
	_webxr_interface.requested_reference_space_types = "local-floor, local"
	_webxr_interface.required_features = "local-floor"
	_webxr_interface.optional_features = "bounded-floor"
	if not _webxr_interface.initialize():
		push_warning("WebXR initialize() returned false")

func _on_webxr_session_started() -> void:
	get_viewport().use_xr = true
	_xr_active = true
	if _enter_vr_button:
		_enter_vr_button.visible = false

func _on_webxr_session_ended() -> void:
	_xr_active = false
	get_viewport().use_xr = false
	if _enter_vr_button:
		_enter_vr_button.visible = true

func _on_webxr_session_failed(message: String) -> void:
	push_warning("WebXR session failed: %s" % message)
	if _enter_vr_button:
		_enter_vr_button.visible = true

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
		var move := _stick(left_controller)
		if move != Vector2.ZERO:
			var forward := -xr_camera.global_transform.basis.z
			var right := xr_camera.global_transform.basis.x
			forward.y = 0
			right.y = 0
			forward = forward.normalized()
			right = right.normalized()
			global_translate((right * move.x + forward * move.y) * move_speed * delta)
	if right_controller:
		var turn := _stick(right_controller)
		if turn.x != 0.0:
			rotate_y(-turn.x * turn_speed * delta)
		if turn.y != 0.0:
			global_translate(Vector3.UP * -turn.y * move_speed * delta)

# OpenXR exposes the thumbstick under the action-map name "primary"; WebXR
# uses the standard Gamepad mapping name "thumbstick" instead. Try both.
func _stick(controller: XRController3D) -> Vector2:
	var v := controller.get_vector2("primary")
	if v == Vector2.ZERO:
		v = controller.get_vector2("thumbstick")
	return v
