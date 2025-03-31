@tool
extends Area3D
class_name VRHandCollider

## A sphere collider for VR hands that detects overlaps with specific objects

# Collision settings
@export var collision_radius: float = 0.05: set = set_collision_radius  # Size of the sphere collider
@export var show_debug_sphere: bool = true: set = set_show_debug_sphere  # Whether to show a visual representation
@export var debug_sphere_color: Color = Color(0.2, 0.8, 0.2, 0.4): set = set_debug_sphere_color  # Color of debug sphere

# Signals
signal object_hovered(object)
signal object_unhovered(object)
signal object_grabbed(object)
signal object_released(object)

# State tracking
var hovering_objects = []
var grabbed_object = null
var is_grabbing = false

# Editor nodes
var collision_shape: CollisionShape3D
var debug_mesh: MeshInstance3D

func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()
	
	# Check if we have a collision shape
	if not has_node("CollisionShape3D"):
		warnings.append("Missing CollisionShape3D child node.")
	elif not get_node("CollisionShape3D").shape is SphereShape3D:
		warnings.append("CollisionShape3D should have a SphereShape3D.")
	
	return warnings

func _ready():
	# Skip actual functionality in editor
	if Engine.is_editor_hint():
		return
	
	# Ensure we have the required nodes
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D")
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _enter_tree():
	# Set up the collision shape and debug visualization
	setup_collision()

func setup_collision():
	# Create or get the collision shape
	collision_shape = get_node_or_null("CollisionShape3D")
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		add_child(collision_shape)
		
		# Make it available in the editor
		if Engine.is_editor_hint():
			collision_shape.set_owner(get_tree().get_edited_scene_root())
	
	# Create or update sphere shape
	var sphere: SphereShape3D
	if collision_shape.shape is SphereShape3D:
		sphere = collision_shape.shape
	else:
		sphere = SphereShape3D.new()
	
	sphere.radius = collision_radius
	collision_shape.shape = sphere
	
	# Handle debug visualization
	update_debug_visualization()

func update_debug_visualization():
	# Remove existing debug mesh if it exists and we don't want to show it
	if not show_debug_sphere:
		if debug_mesh and is_instance_valid(debug_mesh):
			debug_mesh.queue_free()
			debug_mesh = null
		return
	
	# Create or get the debug mesh
	if not debug_mesh or not is_instance_valid(debug_mesh):
		debug_mesh = get_node_or_null("DebugMesh")
		if not debug_mesh:
			debug_mesh = MeshInstance3D.new()
			debug_mesh.name = "DebugMesh"
			add_child(debug_mesh)
			
			# Make it available in the editor
			if Engine.is_editor_hint():
				debug_mesh.set_owner(get_tree().get_edited_scene_root())
	
	# Create or update sphere mesh
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = collision_radius
	sphere_mesh.height = collision_radius * 2
	debug_mesh.mesh = sphere_mesh
	
	# Create or update material
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = debug_sphere_color
	debug_mesh.material_override = material

# Property setters for editor updates
func set_collision_radius(value):
	collision_radius = value
	if Engine.is_editor_hint() or is_inside_tree():
		if collision_shape and collision_shape.shape is SphereShape3D:
			collision_shape.shape.radius = value
		update_debug_visualization()

func set_show_debug_sphere(value):
	show_debug_sphere = value
	if Engine.is_editor_hint() or is_inside_tree():
		update_debug_visualization()

func set_debug_sphere_color(value):
	debug_sphere_color = value
	if (Engine.is_editor_hint() or is_inside_tree()) and debug_mesh and is_instance_valid(debug_mesh):
		# Create the material if it doesn't exist
		if not debug_mesh.material_override:
			var material = StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			debug_mesh.material_override = material
		
		# Now safely set the color
		debug_mesh.material_override.albedo_color = value

# Handle entering a physics body's collision
func _on_body_entered(body):
	if Engine.is_editor_hint():
		return
		
	if body.is_in_group("grabbable") or body.has_meta("grabbable"):
		if not hovering_objects.has(body):
			hovering_objects.append(body)
			emit_signal("object_hovered", body)
			print("Hovering over: ", body.name)

# Handle exiting a physics body's collision
func _on_body_exited(body):
	if Engine.is_editor_hint():
		return
		
	if hovering_objects.has(body):
		hovering_objects.erase(body)
		emit_signal("object_unhovered", body)
		print("No longer hovering: ", body.name)
		
		if grabbed_object == body:
			release_object()

# Handle entering another area's collision
func _on_area_entered(area):
	if Engine.is_editor_hint():
		return
		
	if area.is_in_group("grabbable") or area.has_meta("grabbable"):
		if not hovering_objects.has(area):
			hovering_objects.append(area)
			emit_signal("object_hovered", area)
			print("Hovering over area: ", area.name)

# Handle exiting another area's collision
func _on_area_exited(area):
	if Engine.is_editor_hint():
		return
		
	if hovering_objects.has(area):
		hovering_objects.erase(area)
		emit_signal("object_unhovered", area)
		print("No longer hovering area: ", area.name)
		
		if grabbed_object == area:
			release_object()

# Call this when the grab button is pressed
func try_grab():
	if Engine.is_editor_hint():
		return false
		
	if hovering_objects.size() > 0 and not is_grabbing:
		# Grab the first object (or you could implement priority logic)
		grabbed_object = hovering_objects[0]
		is_grabbing = true
		emit_signal("object_grabbed", grabbed_object)
		print("Grabbed: ", grabbed_object.name)
		return true
	return false

# Call this when the grab button is released
func release_object():
	if Engine.is_editor_hint():
		return false
		
	if is_grabbing and grabbed_object:
		var released = grabbed_object
		is_grabbing = false
		grabbed_object = null
		emit_signal("object_released", released)
		print("Released: ", released.name)
		return true
	return false

# Check if currently hovering over any objects
func is_hovering():
	return hovering_objects.size() > 0

# Get the currently hovered objects
func get_hovering_objects():
	return hovering_objects

# Get the currently grabbed object
func get_grabbed_object():
	return grabbed_object
