@tool
extends Node3D

@onready var world_environment = $WorldEnvironment
@onready var directional_light = $DirectionalLight3D

# Create noise texture at runtime to avoid file dependencies
var noise_texture: NoiseTexture2D

# Time of day control with inspector exposure
@export_range(0.0, 1.0, 0.01) var time_of_day: float = 0.5:  # Noon
	set(value):
		time_of_day = value
		# Update in editor mode
		if Engine.is_editor_hint():
			update_sun_position()
			update_shader_time()

@export_range(0.0, 0.01, 0.0001) var day_cycle_speed: float = 0.001  # Much slower default

# Time-related variables
@export var auto_cycle: bool = true

# Setup flag to track if we've initialized in editor
var _editor_setup_complete = false

func _ready():
	if Engine.is_editor_hint():
		# Don't repeat setup if already done
		if _editor_setup_complete:
			return
			
		# We need to ensure the node references are available in editor mode
		# They might not be ready yet via @onready, so we use get_node
		if not world_environment:
			world_environment = get_node_or_null("WorldEnvironment")
		if not directional_light:
			directional_light = get_node_or_null("DirectionalLight3D")
			
		# If nodes found, setup preview
		if world_environment and directional_light:
			create_noise_texture()
			setup_sky_shader()
			update_sun_position()
			_editor_setup_complete = true
	else:
		# Game runtime code
		create_noise_texture()
		setup_sky_shader()
		update_sun_position()

func _process(delta):
	if Engine.is_editor_hint():
		return # Don't run auto-cycle in editor
		
	if auto_cycle:
		# Update time of day with dramatically slower speed
		time_of_day = fmod(time_of_day + delta * day_cycle_speed, 1.0)
		update_shader_time()
		update_sun_position()

func update_shader_time():
	if not world_environment or not world_environment.environment or not world_environment.environment.sky:
		return
		
	var sky_material = world_environment.environment.sky.sky_material
	if sky_material:
		sky_material.set_shader_parameter("time_of_day", time_of_day)

func create_noise_texture():
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = randi()
	noise.frequency = 0.005
	
	noise_texture = NoiseTexture2D.new()
	noise_texture.width = 128
	noise_texture.height = 128
	noise_texture.seamless = true
	noise_texture.noise = noise

func setup_sky_shader():
	# Create shader material
	var sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://scenes/Sky/sky_shader.gdshader")  # Path to the shader
	
	# Create sky
	var sky = Sky.new()
	sky.sky_material = sky_material
	
	# Ensure the environment exists
	if world_environment.environment == null:
		world_environment.environment = Environment.new()
	
	# Set up environment
	var environment = world_environment.environment
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	
	# Set shader parameters
	sky_material.set_shader_parameter("cloud_noise_texture", noise_texture)
	sky_material.set_shader_parameter("time_of_day", time_of_day)
	sky_material.set_shader_parameter("cloud_coverage", cloud_coverage)
	sky_material.set_shader_parameter("cloud_edge_softness", cloud_edge_softness)
	sky_material.set_shader_parameter("cloud_speed", cloud_speed)
	sky_material.set_shader_parameter("sun_size", sun_size)
	sky_material.set_shader_parameter("sun_halo", sun_halo)
	sky_material.set_shader_parameter("moon_size", moon_size)
	sky_material.set_shader_parameter("moon_halo", moon_halo)
	sky_material.set_shader_parameter("use_moon_shadows", use_moon_shadows)
	sky_material.set_shader_parameter("horizon_blend", horizon_blend)
	
	# Set stars parameters
	sky_material.set_shader_parameter("use_stars", use_stars)
	sky_material.set_shader_parameter("stars_intensity", stars_intensity)
	sky_material.set_shader_parameter("stars_color", stars_color)
	
	# Set color uniforms
	sky_material.set_shader_parameter("day_top_color", Color(0.3, 0.5, 0.95))
	sky_material.set_shader_parameter("day_bottom_color", Color(0.6, 0.8, 1.0))
	sky_material.set_shader_parameter("sunset_top_color", Color(0.26, 0.24, 0.38))
	sky_material.set_shader_parameter("sunset_bottom_color", Color(0.95, 0.33, 0.15))
	sky_material.set_shader_parameter("night_top_color", Color(0.02, 0.02, 0.05))
	sky_material.set_shader_parameter("night_bottom_color", Color(0.05, 0.05, 0.1))
	
	# Fog setup
	environment.fog_enabled = fog_enabled
	environment.fog_light_color = Color(0.5, 0.5, 0.6, 0.1)  # Slightly blue-gray fog color
	environment.fog_density = fog_density
	
	# Store reference for updates
	world_environment.environment = environment

func update_sun_position():
	if not directional_light:
		return
	
	# Calculate sun position based on time of day
	var sun_angle = time_of_day * TAU - PI/2
	
	# Create rotation to make sun rise in east (negative X) and set in west (positive X)
	var sun_height = sin(sun_angle)
	var sun_direction = Vector3(cos(sun_angle), sun_height, 0).normalized()
	
	# Determine if it's night
	var is_night = time_of_day < 0.25 or time_of_day > 0.75
	
	# During night, we want to point the light in the opposite direction
	if is_night:
		sun_direction = -sun_direction
	
	# Update directional light orientation
	directional_light.look_at_from_position(Vector3.ZERO, -sun_direction, Vector3.UP)
	
	# Pass light direction to shader if in game mode
	if not Engine.is_editor_hint():
		if world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("LIGHT0_DIRECTION", -directional_light.global_transform.basis.z)
	
	# Adjust light color and energy based on time of day
	var light_energy = max(0.05, abs(sun_height) * .8)  # Minimum light at night
	directional_light.light_energy = light_energy
	directional_light.shadow_enabled = true
	# Change light color based on time of day
	if is_night:  # Night
		directional_light.light_color = Color(0.6, 0.6, 1.0)  # Blueish
		directional_light.light_energy = .05
		if use_moon_shadows:
			directional_light.shadow_enabled = true
		else:
			directional_light.shadow_enabled = false
	elif time_of_day < 0.3 or time_of_day > 0.7:  # Sunrise/Sunset
		directional_light.light_color = Color(1.0, 0.8, 0.5)  # Orange
	else:  # Day
		directional_light.light_color = Color(1.0, 1.0, 1.0)  # White

# Exposed shader parameters for tweaking in the inspector
@export_group("Cloud Settings")
@export_range(0.0, 1.0, 0.01) var cloud_coverage: float = 0.5:
	set(value):
		cloud_coverage = value
		if Engine.is_editor_hint() and world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("cloud_coverage", value)

@export_range(0.0, 1.0, 0.01) var cloud_edge_softness: float = 0.1:
	set(value):
		cloud_edge_softness = value
		if Engine.is_editor_hint() and world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("cloud_edge_softness", value)

@export_range(0.0, 1.0, 0.001) var cloud_speed: float = 0.01:
	set(value):
		cloud_speed = value
		if Engine.is_editor_hint() and world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("cloud_speed", value)

@export_group("Stars")
@export var use_stars: bool = false:
	set(value):
		use_stars = value
		if Engine.is_editor_hint() and world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("use_stars", value)

@export_range(0.0, 5.0, 0.1) var stars_intensity: float = 1.0:
	set(value):
		stars_intensity = value
		if Engine.is_editor_hint() and world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("stars_intensity", value)

@export var stars_color: Color = Color(1.0, 1.0, 1.0):
	set(value):
		stars_color = value
		if Engine.is_editor_hint() and world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("stars_color", value)

@export_group("Sun Settings")
@export_range(0.001, 0.5, 0.001) var sun_size: float = 0.01:
	set(value):
		sun_size = value
		if world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			sky_material.set_shader_parameter("sun_size", value)

@export_range(0.0, 1.0, 0.01) var sun_halo: float = 0.2:
	set(value):
		sun_halo = value
		if Engine.is_editor_hint() and world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("sun_halo", value)
				
@export_group("Moon Settings")
@export_range(0.001, 0.5, 0.001) var moon_size: float = 0.01:
	set(value):
		moon_size = value
		if world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			sky_material.set_shader_parameter("moon_size", value)

@export_range(0.0, 1.0, 0.01) var moon_halo: float = 0.2:
	set(value):
		moon_halo = value
		if Engine.is_editor_hint() and world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("moon_halo", value)

@export var use_moon_shadows: bool = false:
	set(value):
		use_moon_shadows = value
		if world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("use_moon_shadows", value)

@export_group("Horizon Settings")
@export_range(0.0, 1.0, 0.01) var horizon_blend: float = 0.1:
	set(value):
		horizon_blend = value
		if Engine.is_editor_hint() and world_environment and world_environment.environment and world_environment.environment.sky:
			var sky_material = world_environment.environment.sky.sky_material
			if sky_material:
				sky_material.set_shader_parameter("horizon_blend", value)

# Fog related exports for inspector tweaking
@export_group("Fog Settings")
@export_range(0.0, 1.0, 0.001) var fog_density: float = 0.01:
	set(value):
		fog_density = value
		if world_environment and world_environment.environment:
			world_environment.environment.fog_density = value

@export var fog_color: Color = Color(0.5, 0.5, 0.6):
	set(value):
		fog_color = value
		if world_environment and world_environment.environment:
			world_environment.environment.fog_light_color = value

@export var fog_enabled: bool = true:
	set(value):
		fog_enabled = value
		if world_environment and world_environment.environment:
			world_environment.environment.fog_enabled = value

# Preset functions that work in editor or runtime
@export_group("Presets")
@export var dawn_preset: bool = false:
	set(value):
		if value:
			dawn_preset = false
			time_of_day = 0.25
			use_stars = false

@export var noon_preset: bool = false:
	set(value):
		if value:
			noon_preset = false
			time_of_day = 0.5
			use_stars = false

@export var sunset_preset: bool = false:
	set(value):
		if value:
			sunset_preset = false
			time_of_day = 0.75
			use_stars = false

@export var night_preset: bool = false:
	set(value):
		if value:
			night_preset = false
			time_of_day = 0.0
			use_stars = true
			stars_intensity = 2.0
