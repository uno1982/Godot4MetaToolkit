extends Node3D
var xr_interface: XRInterface

## XR frame rate
var xr_frame_rate : float = 0

## Physics rate multiplier compared to HMD frame rate
@export var physics_rate_multiplier : int = 1

## If non-zero, specifies the target refresh rate
@export var target_refresh_rate : float = 72

# Player scene paths
var vr_player_path = "res://scenes/players/VRPlayer.tscn"
var fps_player_path = "res://scenes/players/FPSPlayer.tscn"

# Reference to the current player instance
var current_player: Node3D

# Spawn position for the player
@export var player_spawn_path: NodePath

func _ready():
	xr_interface = XRServer.find_interface("OpenXR")
	
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR initialized successfully")
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		# Set the XR frame rate
		_set_xr_frame_rate()
		get_viewport().use_xr = true
		
		# Output the rendering scale to the logger
		var rendering_scale = get_viewport().scaling_3d_scale
		print("Current XR rendering scale: " + str(rendering_scale * 100) + "%")
		check_rendering_resolution()
		
		# Spawn VR player
		spawn_player(true)
	else:
		print("HMD Not Connected! Check Meta link or SteamVR connection")
		
		# Set up desktop mode with FPS player
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		
		# Spawn FPS player
		spawn_player(false)

# Set the XR frame rate to the configured value
func _set_xr_frame_rate() -> void:
	# Get the reported refresh rate
	xr_frame_rate = xr_interface.get_display_refresh_rate()
	if xr_frame_rate > 0:
		print("StartXR: Refresh rate reported as ", str(xr_frame_rate))
	else:
		print("StartXR: No refresh rate given by XR runtime")

	# Pick a desired refresh rate
	var desired_rate := target_refresh_rate if target_refresh_rate > 0 else xr_frame_rate
	var available_rates : Array = xr_interface.get_available_display_refresh_rates()
	if available_rates.size() == 0:
		print("StartXR: Target does not support refresh rate extension")
	elif available_rates.size() == 1:
		print("StartXR: Target supports only one refresh rate")
	elif desired_rate > 0:
		print("StartXR: Available refresh rates are ", str(available_rates))
		var rate = _find_closest(available_rates, desired_rate)
		if rate > 0:
			print("StartXR: Setting refresh rate to ", str(rate))
			xr_interface.set_display_refresh_rate(rate)
			xr_frame_rate = rate

	# Pick a physics rate
	var active_rate := xr_frame_rate if xr_frame_rate > 0 else 144.0
	var physics_rate := int(round(active_rate * physics_rate_multiplier))
	print("StartXR: Setting physics rate to ", physics_rate)
	Engine.physics_ticks_per_second = physics_rate

func check_rendering_resolution():
	var viewport = get_viewport()
	var size = viewport.get_visible_rect().size
	print("Rendering at: " + str(size.x) + "x" + str(size.y))
	
# Find the closest value in the array to the target
func _find_closest(values : Array, target : float) -> float:
	# Return 0 if no values
	if values.size() == 0:
		return 0.0

	# Find the closest value to the target
	var best : float = values.front()
	for v in values:
		if abs(target - v) < abs(target - best):
			best = v

	# Return the best value
	return best

func spawn_player(use_vr: bool):
	# Load the appropriate player scene
	var player_scene_path = vr_player_path if use_vr else fps_player_path
	var player_scene = load(player_scene_path)
	
	if player_scene:
		var player_instance = player_scene.instantiate()
		current_player = player_instance
		
		# Add to the main scene
		var main_scene = get_tree().current_scene
		main_scene.add_child(player_instance)
		
		# For desktop mode, ensure mouse capture
		if not use_vr:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		# Position the player at the spawn point if specified
		if not player_spawn_path.is_empty():
			var spawn_point = get_node_or_null(player_spawn_path)
			if spawn_point:
				player_instance.global_position = spawn_point.global_position
				player_instance.global_rotation = spawn_point.global_rotation
			else:
				# Fallback position if spawn point not found
				player_instance.global_position = Vector3(0, 1.7, 0)
		
		print("Spawned " + ("VR" if use_vr else "FPS") + " player")
	else:
		push_error("Failed to load player scene: " + player_scene_path)
