@tool
extends Node
class_name VRLocomotion

## A custom node for VR thumbstick locomotion that can be attached to an XROrigin3D

# Movement settings
@export var speed = 2.0  # Movement speed
@export var smooth_turn_speed = 45.0  # Degrees per second for smooth turning
@export var snap_turn_degrees = 30.0  # Degrees per snap turn
@export var use_smooth_turning = false  # Set to true for smooth turning, false for snap turning
@export var deadzone = 0.2  # Ignore small thumbstick movements

# Controller paths (update these if your controller nodes have different names)
@export_node_path("XRController3D") var left_controller_path: NodePath = "../LeftController"
@export_node_path("XRController3D") var right_controller_path: NodePath = "../RightController" 
@export_node_path("XRCamera3D") var camera_path: NodePath = "../XRCamera3D"

# Node references
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var left_controller: XRController3D
var right_controller: XRController3D

# Variables for snap turning cooldown
var can_snap_turn = true
var snap_turn_cooldown = 0.25  # Seconds
var snap_timer = 0.0

# Direction vectors
var forward_direction = Vector3()
var right_direction = Vector3()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()
	
	# Check if we're attached to an XROrigin3D
	if not get_parent() is XROrigin3D:
		warnings.append("VRLocomotion should be a child of an XROrigin3D node.")
	
	# Check if controller paths are valid
	if left_controller_path.is_empty() or not get_node_or_null(left_controller_path):
		warnings.append("Left controller path is invalid or empty.")
	
	if right_controller_path.is_empty() or not get_node_or_null(right_controller_path):
		warnings.append("Right controller path is invalid or empty.")
	
	if camera_path.is_empty() or not get_node_or_null(camera_path):
		warnings.append("Camera path is invalid or empty.")
		
	return warnings

func _ready():
	if Engine.is_editor_hint():
		return
		
	# Get node references
	xr_origin = get_parent() as XROrigin3D
	
	if not xr_origin:
		push_error("VRLocomotion must be a child of an XROrigin3D node")
		return
	
	xr_camera = get_node(camera_path) as XRCamera3D
	left_controller = get_node(left_controller_path) as XRController3D
	right_controller = get_node(right_controller_path) as XRController3D
	
	if not xr_camera or not left_controller or not right_controller:
		push_error("VRLocomotion: Could not find required XR nodes")
		return
	
	# Initialize controller input
	left_controller.button_pressed.connect(_on_controller_button_pressed.bind(left_controller))
	right_controller.button_pressed.connect(_on_controller_button_pressed.bind(right_controller))
	left_controller.button_released.connect(_on_controller_button_released.bind(left_controller))
	right_controller.button_released.connect(_on_controller_button_released.bind(right_controller))
	left_controller.input_vector2_changed.connect(_on_controller_input_vector2_changed.bind(left_controller))
	right_controller.input_vector2_changed.connect(_on_controller_input_vector2_changed.bind(right_controller))

func _process(delta):
	if Engine.is_editor_hint():
		return
		
	update_direction_vectors()
	
	# Handle snap turn cooldown
	if not can_snap_turn:
		snap_timer += delta
		if snap_timer >= snap_turn_cooldown:
			can_snap_turn = true
			snap_timer = 0.0

func _physics_process(delta):
	if Engine.is_editor_hint():
		return
		
	if not xr_origin or not xr_camera or not left_controller or not right_controller:
		return
		
	# Apply movement based on thumbstick input
	var movement = Vector3.ZERO
	
	# Get the left thumbstick input for movement
	var left_thumbstick = Vector2.ZERO
	if left_controller.is_button_pressed("primary"):
		left_thumbstick = left_controller.get_vector2("primary")
	
	# Apply deadzone
	if left_thumbstick.length() < deadzone:
		left_thumbstick = Vector2.ZERO
	
	# Calculate movement direction based on camera orientation
	# Corrected: Y-axis is no longer inverted for forward/backward movement
	if left_thumbstick != Vector2.ZERO:
		movement += forward_direction * left_thumbstick.y
		movement += right_direction * left_thumbstick.x
		
		# Normalize to prevent diagonal movement from being faster
		if movement.length() > 1.0:
			movement = movement.normalized()
		
		# Apply speed
		movement *= speed * delta
		
		# Move the XR origin
		xr_origin.global_translate(movement)
	
	# Handle rotation with right thumbstick
	var right_thumbstick = Vector2.ZERO
	if right_controller.is_button_pressed("primary"):
		right_thumbstick = right_controller.get_vector2("primary")
	
	# Apply deadzone
	if abs(right_thumbstick.x) < deadzone:
		right_thumbstick.x = 0
	
	if right_thumbstick.x != 0:
		if use_smooth_turning:
			# Smooth turning (corrected direction)
			var rotation_amount = -right_thumbstick.x * smooth_turn_speed * delta
			rotate_player(rotation_amount)
		else:
			# Snap turning (corrected direction)
			if can_snap_turn:
				var direction = -sign(right_thumbstick.x)
				rotate_player(snap_turn_degrees * direction)
				can_snap_turn = false

func update_direction_vectors():
	if not xr_camera:
		return
		
	# Get the camera's forward and right directions, but remove vertical component
	var camera_transform = xr_camera.global_transform
	
	# Forward direction (z-axis) without vertical component
	forward_direction = -camera_transform.basis.z
	forward_direction.y = 0
	forward_direction = forward_direction.normalized()
	
	# Right direction (x-axis) without vertical component
	right_direction = camera_transform.basis.x
	right_direction.y = 0
	right_direction = right_direction.normalized()

func rotate_player(degrees):
	if not xr_origin:
		return
		
	# Rotate the XR origin around the vertical axis
	xr_origin.rotate_y(deg_to_rad(degrees))

func _on_controller_button_pressed(name, controller):
	# You can override this method to add additional button controls
	pass

func _on_controller_button_released(name, controller):
	# You can override this method to add additional button controls
	pass

func _on_controller_input_vector2_changed(name, vector, controller):
	# You can override this method to handle thumbstick input changes
	pass
