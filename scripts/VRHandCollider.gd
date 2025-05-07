@tool
extends Area3D
class_name VRHandCollider

## A sphere collider for VR hands that detects overlaps with specific objects

# Collision settings
@export var collision_radius: float = 0.05: set = set_collision_radius # Size of the sphere collider
@export var show_debug_sphere: bool = true: set = set_show_debug_sphere # Whether to show a visual representation
@export var debug_sphere_color: Color = Color(0.2, 0.8, 0.2, 0.4): set = set_debug_sphere_color # Color of debug sphere

# Hand settings
@export var hand_controller_path: NodePath # Path to XR controller node
@export var grip_action: String = "grip" # Input action for grabbing objects
@export var grip_threshold: float = 0.6 # Threshold for grab detection
@export var throw_impulse_factor: float = 1.5 # Factor for throwing velocity

# Debug settings
@export var debug_mode: bool = true # Enable detailed debug output

# Signals
signal object_hovered(object)
signal object_unhovered(object)
signal object_grabbed(object)
signal object_released(object)

# State tracking
var hovering_objects = []
var grabbed_object = null
var is_grabbing = false
var hand_controller = null # Reference to the controller node
var grip_value = 0.0 # Current grip value

# Physics tracking for throws
var velocity_averager = [] # Stores position history for velocity calculation
var max_velocity_samples = 10 # Number of samples for velocity averaging
var last_transform = Transform3D() # Last transform of hand for velocity calculation

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
	
	# Check if controller path is set
	if hand_controller_path.is_empty():
		warnings.append("No XR controller specified. Set the hand_controller_path.")
	
	return warnings

func _ready():
	# Skip actual functionality in editor
	if Engine.is_editor_hint():
		return
	
	# Get reference to controller
	if not hand_controller_path.is_empty():
		hand_controller = get_node(hand_controller_path)
		if not hand_controller:
			push_warning("VRHandCollider: Could not find controller at specified path")
	
	# Ensure we have the required nodes
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D")
	
	
	if debug_mode:
		print("VRHandCollider initialized - layer: " + str(collision_layer) + ", mask: " + str(collision_mask))
		print("Active collision layers: " + str(_get_active_layers(collision_layer)))
		print("Active collision mask: " + str(_get_active_layers(collision_mask)))
		print("Current collision shape: " + str(collision_shape))
		print("Parent controller: " + str(get_parent().name))
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	
	# Initialize transform tracking for velocity calculation
	last_transform = global_transform
	for i in range(max_velocity_samples):
		velocity_averager.append(Vector3.ZERO)

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

func _process(delta):
	if Engine.is_editor_hint() or not hand_controller:
		return
	
	# Update grip value and check for grab/release
	if hand_controller.has_method("get_float"):
		grip_value = hand_controller.get_float(grip_action)
		
		# Check for grab action
		if not is_grabbing and grip_value >= grip_threshold:
			is_grabbing = true
			try_grab()
		elif is_grabbing and grip_value < grip_threshold:
			is_grabbing = false
			release_object()
	
	# Update velocity tracking for throwing
	update_velocity_tracking(delta)

func _physics_process(_delta):
	if Engine.is_editor_hint():
		return
		
	# Update the position of any grabbed object to follow the hand
	if grabbed_object and is_instance_valid(grabbed_object):
		# Special case handling already happens in the Grippable component
		pass

# Handle entering a physics body's collision
func _on_body_entered(body):
	if Engine.is_editor_hint():
		return
	
	if debug_mode:
		print("\n==== HAND COLLIDER DETECTED BODY ====")
		print("Hand: " + name + " detected body: " + body.name)
		print("Body collision layer: " + str(body.collision_layer))
		print("Hand collision mask: " + str(collision_mask))
		print("Parent hierarchy of body:")
		_print_hierarchy(body)
		print("======================================\n")
	
	# Check for several cases:
	# 1. Body has Grippable component
	# 2. Body has grippable as child
	# 3. Body is in grabbable group
	
	var grippable = null
	
	# Case 1: Direct Grippable component
	if body.get_script() == Grippable:
		grippable = body
	
	# Case 2: Has Grippable as child
	if not grippable:
		for child in body.get_children():
			if child is Grippable:
				grippable = child
				break
	
	# Case 3: Body is in grabbable group or has meta
	if not grippable and (body.is_in_group("grabbable") or body.has_meta("grabbable")):
		if not hovering_objects.has(body):
			hovering_objects.append(body)
			emit_signal("object_hovered", body)
			print("Hovering over: ", body.name)
	
	# Handle grippable object
	if grippable and not hovering_objects.has(grippable):
		hovering_objects.append(grippable)
		grippable.hover_begin(self)
		emit_signal("object_hovered", grippable)
		print("Hovering over grippable: ", grippable.name)

# Handle exiting a physics body's collision
func _on_body_exited(body):
	if Engine.is_editor_hint():
		return
		
	# Similar check as body_entered but for exit
	var grippable = null
	
	if body.get_script() == Grippable:
		grippable = body
	
	if not grippable:
		for child in body.get_children():
			if child is Grippable:
				grippable = child
				break
	
	# Handle standard objects
	if hovering_objects.has(body):
		hovering_objects.erase(body)
		emit_signal("object_unhovered", body)
		print("No longer hovering: ", body.name)
		
		if grabbed_object == body:
			release_object()
	
	# Handle grippable
	if grippable and hovering_objects.has(grippable):
		hovering_objects.erase(grippable)
		grippable.hover_end(self)
		emit_signal("object_unhovered", grippable)
		print("No longer hovering grippable: ", grippable.name)

# Handle entering another area's collision
func _on_area_entered(area):
	if Engine.is_editor_hint():
		return
		
	# Similar logic as body_entered for areas
	var grippable = null
	
	if area.get_script() == Grippable:
		grippable = area
	
	if not grippable:
		for child in area.get_children():
			if child is Grippable:
				grippable = child
				break
	
	if not grippable and (area.is_in_group("grabbable") or area.has_meta("grabbable")):
		if not hovering_objects.has(area):
			hovering_objects.append(area)
			emit_signal("object_hovered", area)
			print("Hovering over area: ", area.name)
	
	if grippable and not hovering_objects.has(grippable):
		hovering_objects.append(grippable)
		grippable.hover_begin(self)
		emit_signal("object_hovered", grippable)
		print("Hovering over grippable area: ", grippable.name)

# Handle exiting another area's collision
func _on_area_exited(area):
	if Engine.is_editor_hint():
		return
		
	# Similar logic as body_exited for areas
	var grippable = null
	
	if area.get_script() == Grippable:
		grippable = area
	
	if not grippable:
		for child in area.get_children():
			if child is Grippable:
				grippable = child
				break
	
	if hovering_objects.has(area):
		hovering_objects.erase(area)
		emit_signal("object_unhovered", area)
		print("No longer hovering area: ", area.name)
		
		if grabbed_object == area:
			release_object()
	
	if grippable and hovering_objects.has(grippable):
		hovering_objects.erase(grippable)
		grippable.hover_end(self)
		emit_signal("object_unhovered", grippable)
		print("No longer hovering grippable area: ", grippable.name)


# Update velocity tracking for throwing
func update_velocity_tracking(delta):
	# Store current position and rotation for velocity calculations
	var current_transform = global_transform
	
	# Shift values in the array
	for i in range(max_velocity_samples - 1, 0, -1):
		velocity_averager[i] = velocity_averager[i - 1]
	
	# Calculate current velocity and store at index 0
	if delta > 0:
		velocity_averager[0] = (current_transform.origin - last_transform.origin) / delta
	
	# Update last transform
	last_transform = current_transform

# Get average velocity for throwing objects
func get_average_velocity():
	var avg = Vector3.ZERO
	var count = 0
	
	for vel in velocity_averager:
		avg += vel
		count += 1
	
	if count > 0:
		avg /= count
	
	return avg * throw_impulse_factor

# Get average angular velocity for throwing objects
func get_average_angular_velocity():
	# A simple approximation - could be improved for more realistic throwing
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.5

# Call this when the grab button is pressed
func try_grab():
	if Engine.is_editor_hint():
		return false
		
	if hovering_objects.size() > 0:
		# Get the closest object
		var closest_object = get_closest_hovering_object()
		
		# Try to grab it
		if closest_object:
			# Check if it's a Grippable object
			if closest_object is Grippable:
				 # If the object is already grabbed by another hand, we'll let the Grippable handle it
				if closest_object.is_grabbed and closest_object.grabbed_by != self:
					print("Attempting to grab object held by another hand")
					
				# Use the Grippable's grab method
				if closest_object.grab(self):
					grabbed_object = closest_object
					emit_signal("object_grabbed", grabbed_object)
					print("Grabbed grippable: ", grabbed_object.name)
					return true
			
			 # Don't allow grabbing non-Grippable objects that we already have
			elif grabbed_object == closest_object:
				return false
				
			# Handle legacy or custom grabbable objects
			else:
				grabbed_object = closest_object
				
				# If the object has custom grab handling
				if grabbed_object.has_method("on_grab"):
					grabbed_object.on_grab(self)
				
				# Basic parent-child grab for other objects
				elif grabbed_object.get_parent():
					var original_parent = grabbed_object.get_parent()
					original_parent.remove_child(grabbed_object)
					add_child(grabbed_object)
					grabbed_object.transform = Transform3D() # Reset local transform
				
				emit_signal("object_grabbed", grabbed_object)
				print("Grabbed: ", grabbed_object.name)
				return true
	return false

# Find the closest object in the hovering list
func get_closest_hovering_object():
	var closest = null
	var closest_distance = 9999999.0
	
	for obj in hovering_objects:
		if obj is Grippable:
			if obj.can_grab(self):
				var dist = global_position.distance_to(obj.global_position)
				if dist < closest_distance:
					closest_distance = dist
					closest = obj
		else:
			# For non-grippable objects, just check distance
			var dist = global_position.distance_to(obj.global_position)
			if dist < closest_distance:
				closest_distance = dist
				closest = obj
	
	return closest

# Call this when the grab button is released
func release_object():
	if Engine.is_editor_hint():
		return false
		
	if grabbed_object:
		# Get the throw velocity
		var throw_velocity = get_average_velocity()
		var throw_angular_velocity = get_average_angular_velocity()
		
		# Check if it's a Grippable object
		if grabbed_object is Grippable:
			# Use the Grippable's release method
			if grabbed_object.release(self, throw_velocity, throw_angular_velocity):
				emit_signal("object_released", grabbed_object)
				grabbed_object = null
				return true
		
		# Handle legacy or custom grabbable objects
		if grabbed_object.has_method("on_release"):
			# If the object has custom release handling
			grabbed_object.on_release(self, throw_velocity, throw_angular_velocity)
		elif grabbed_object.get_parent() == self:
			# Basic release for objects we're directly parenting
			remove_child(grabbed_object)
			get_tree().current_scene.add_child(grabbed_object)
			
			# Apply physics if it's a RigidBody
			if grabbed_object is RigidBody3D:
				grabbed_object.linear_velocity = throw_velocity
				grabbed_object.angular_velocity = throw_angular_velocity
		
		emit_signal("object_released", grabbed_object)
		print("Released: ", grabbed_object.name)
		
		grabbed_object = null
		return true
	return false

# Remove an object from the hovering list
func remove_hovering_object(object):
	if hovering_objects.has(object):
		hovering_objects.erase(object)
		emit_signal("object_unhovered", object)

# Check if currently hovering over any objects
func is_hovering():
	return hovering_objects.size() > 0

# Get the currently hovered objects
func get_hovering_objects():
	return hovering_objects

# Get the currently grabbed object
func get_grabbed_object():
	return grabbed_object

# Helper function to print node hierarchy
func _print_hierarchy(node, indent = ""):
	if node == null:
		return
	
	print(indent + "- " + node.name + " [" + node.get_class() + "]")
	
	# Print collision info if available
	if node is CollisionObject3D:
		print(indent + "  Layer: " + str(node.collision_layer) + ", Mask: " + str(node.collision_mask))
	
	if node.get_parent():
		_print_hierarchy(node.get_parent(), indent + "  ")

# Helper function to convert bit mask to array of active layers
func _get_active_layers(bitmask: int) -> Array:
	var active_layers = []
	for i in range(32): # Godot supports up to 32 physics layers
		if bitmask & (1 << i):
			active_layers.append(i + 1) # Layer numbers are 1-based in the editor
	return active_layers
