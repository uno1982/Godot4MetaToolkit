@tool
extends MeshInstance3D

# Cloud appearance parameters
@export_group("Cloud Appearance")
@export var cloud_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.1, 1.0, 0.01) var cloud_density: float = 0.4
@export_range(0.0, 1.0, 0.01) var cloud_softness: float = 0.7
@export_range(0.0, 1.0, 0.01) var cloud_coverage: float = 0.6

# Animation parameters
@export_group("Cloud Animation")
@export_range(0.0, 0.05, 0.001) var cloud_speed: float = 0.005
@export var animate_in_editor: bool = false

# Shader settings
@export_group("Shader Settings")
@export var noise_texture: Texture2D
@export var apply_shader: bool = false:
	set(value):
		apply_shader = false
		_setup_material()

# Private variables
var cloud_material: ShaderMaterial
var time: float = 0.0

func _ready():
	# Make sure the cloud layer stays fixed at world origin
	global_position = Vector3.ZERO
	_setup_material()

func _process(delta):
	# Keep position fixed
	if global_position != Vector3.ZERO:
		global_position = Vector3.ZERO
	
	# Update time for animation
	if Engine.is_editor_hint() and not animate_in_editor:
		return
		
	time += delta
	
	# Update shader parameters
	if cloud_material:
		cloud_material.set_shader_parameter("time", time)

func _setup_material():
	# Create new shader material
	cloud_material = ShaderMaterial.new()
	
	# Load shader
	var shader = load("res://scenes/sky/clouds.gdshader")
	if not shader:
		print("Error: Could not load cloud shader!")
		return
	
	cloud_material.shader = shader
	
	# Set shader parameters
	cloud_material.set_shader_parameter("cloud_color", cloud_color)
	cloud_material.set_shader_parameter("cloud_density", cloud_density)
	cloud_material.set_shader_parameter("cloud_softness", cloud_softness)
	cloud_material.set_shader_parameter("cloud_coverage", cloud_coverage)
	cloud_material.set_shader_parameter("cloud_speed", cloud_speed)
	cloud_material.set_shader_parameter("time", time)
	
	if noise_texture:
		cloud_material.set_shader_parameter("noise_texture", noise_texture)
	
	# Apply material
	material_override = cloud_material

func update_shader_parameters():
	if cloud_material:
		cloud_material.set_shader_parameter("cloud_color", cloud_color)
		cloud_material.set_shader_parameter("cloud_density", cloud_density)
		cloud_material.set_shader_parameter("cloud_softness", cloud_softness)
		cloud_material.set_shader_parameter("cloud_coverage", cloud_coverage)
		cloud_material.set_shader_parameter("cloud_speed", cloud_speed)
		
		if noise_texture:
			cloud_material.set_shader_parameter("noise_texture", noise_texture)

# Call this whenever shader parameters change in the Inspector
func _on_property_changed():
	update_shader_parameters()

# Property setters to detect changes
func _set(property, value):
	if property.begins_with("cloud_") or property == "noise_texture":
		set(property, value)
		update_shader_parameters()
		return true
	return false
