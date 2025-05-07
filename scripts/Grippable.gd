@tool
extends Node3D
class_name Grippable

## A script that makes an object grippable in VR
## Add this as a child to any object that should be grabbable

# Signals
signal grabbed(by_hand)
signal released(by_hand)
signal hovered(by_hand)
signal unhovered(by_hand)

# Properties
@export var enabled: bool = true

# Hand swapping options
enum SecondHandMode {
	IGNORE, # Ignore attempts by second hand to grab
	SWAP, # Release from first hand and grab with second
	BOTH # Allow both hands to grab (not fully implemented yet)
}
@export var second_hand_behavior: SecondHandMode = SecondHandMode.SWAP

# Highlight settings
@export var highlight_on_hover: bool = true
@export var highlight_mesh_instance: NodePath
@export var highlight_color: Color = Color(1.0, 0.9, 0.1, 0.3)
@export var normal_color: Color = Color(1.0, 1.0, 1.0, 1.0)

# Collision settings
@export var disable_collisions_when_grabbed: bool = false # Whether to disable collisions when grabbed
@export var retain_collision_with_hands: bool = true # Keep colliding with hands even when grabbed

# State tracking
var is_grabbed: bool = false
var grabbed_by = null # The hand currently grabbing this object
var hovering_hands = [] # All hands currently hovering over this object
var original_parent = null # Original parent before grabbed
var original_transform = Transform3D() # Original transform before grabbed
var original_collision_layer = 0 # Original collision layer before grabbed
var original_collision_mask = 0 # Original collision mask before grabbed
var active_grab_point = null # Currently active grab point
var secondary_hands = [] # For multi-hand grabbing

# Physics properties
@export var throw_impulse_factor: float = 1.5 # Factor for throwing velocity
@export var velocity_samples: int = 5 # Number of samples for velocity averaging

# Follow properties
@export var follow_speed: float = 20.0 # Speed at which object follows hand

# Internal variables
var _velocity_averager = null # Will be initialized in _ready

func _ready():
	# Initialize in editor mode check
	if Engine.is_editor_hint():
		return
	
	# Initialize velocity averager
	_velocity_averager = XRToolsVelocityAverager.new(velocity_samples)
	
	# Set up highlight mesh
	if highlight_on_hover and not highlight_mesh_instance.is_empty():
		var highlight_node = get_node_or_null(highlight_mesh_instance)
		if highlight_node and highlight_node is MeshInstance3D:
			# Initialize with highlight disabled
			_set_highlight(false)

# Physics update for smooth object following
func _physics_process(delta):
	if Engine.is_editor_hint():
		return
	
	if is_grabbed and is_instance_valid(grabbed_by):
		var grippable_object = get_parent()
		if not is_instance_valid(grippable_object):
			return
			
		# Update velocity tracking
		_velocity_averager.add_transform(delta, grippable_object.global_transform)
		
		 # Check if we have a second hand grabbing - if so, handle two-handed manipulation
		if second_hand_behavior == SecondHandMode.BOTH and secondary_hands.size() > 0:
			_handle_two_handed_manipulation(grippable_object)
			return
		
		# Apply different following behavior based on grab point
		if is_instance_valid(active_grab_point):
			 # Base the transform on the grabbing hand
			var hand_transform = grabbed_by.global_transform
			
			if active_grab_point.grab_mode == GrabPoint.GrabMode.SNAP:
				# SNAP mode - object's grab point snaps to hand position
				# Calculate the offset from the grab point to the object's origin
				var grab_point_local_transform = active_grab_point.transform
				
				# Create the target transform: place the grab point at the hand's position
				var target_transform = Transform3D()
				target_transform.basis = hand_transform.basis
				
				# Calculate the correct position by accounting for the grab point's offset
				# Need to rotate the offset by the basis of the hand
				var quat = target_transform.basis.get_rotation_quaternion()
				var offset = - grab_point_local_transform.origin
				
				# Apply rotation to the offset vector using basis
				offset = target_transform.basis * offset
				
				target_transform.origin = hand_transform.origin + offset
				
				# Apply the transform
				grippable_object.global_transform = target_transform
			else:
				# PRECISE mode - object maintains offset from hand
				var target_transform = grippable_object.global_transform
				
				# Apply drive settings
				if active_grab_point.drive_position > 0.0:
					target_transform.origin = target_transform.origin.lerp(
						hand_transform.origin,
						active_grab_point.drive_position)
				
				if active_grab_point.drive_rotation > 0.0:
					var current_quat = Quaternion(target_transform.basis)
					var hand_quat = Quaternion(hand_transform.basis)
					target_transform.basis = Basis(current_quat.slerp(hand_quat, active_grab_point.drive_rotation))
				
				if active_grab_point.drive_aim > 0.0:
					var hand_forward = - hand_transform.basis.z
					var current_forward = - target_transform.basis.z
					var axis = current_forward.cross(hand_forward).normalized()
					var angle = current_forward.angle_to(hand_forward) * active_grab_point.drive_aim
					if angle > 0.001 and axis.length() > 0.001:
						target_transform.basis = target_transform.basis.rotated(axis, angle)
				
				# Apply the transform
				grippable_object.global_transform = target_transform
		else:
			# No grab point, use default behavior - directly follow the hand
			grippable_object.global_transform = grabbed_by.global_transform

# Handle the case where two hands are manipulating an object
func _handle_two_handed_manipulation(grippable_object):
	if secondary_hands.size() == 0 or not is_instance_valid(secondary_hands[0]):
		return
		
	var primary_hand = grabbed_by
	var secondary_hand = secondary_hands[0]
	
	# Get the transforms of both hands
	var primary_transform = primary_hand.global_transform
	var secondary_transform = secondary_hand.global_transform
	
	# Calculate the midpoint between the two hands
	var midpoint = (primary_transform.origin + secondary_transform.origin) / 2.0
	
	# Calculate the direction vector from primary to secondary hand
	var direction = (secondary_transform.origin - primary_transform.origin).normalized()
	
	# Calculate the distance between hands
	var hand_distance = primary_transform.origin.distance_to(secondary_transform.origin)
	
	# Create a basis that points from primary to secondary hand
	var new_basis = Basis()
	
	# Staff/long object specific - align Y axis with the direction between hands
	new_basis.y = direction
	
	# Use primary hand's forward direction for Z axis
	var primary_forward = - primary_transform.basis.z
	
	# Make sure Z is perpendicular to Y by using cross product for X and then cross again for Z
	new_basis.x = new_basis.y.cross(primary_forward).normalized()
	new_basis.z = new_basis.x.cross(new_basis.y).normalized()
	
	# Construct the final transform
	var target_transform = Transform3D(new_basis, midpoint)
	
	# Apply the transform
	grippable_object.global_transform = target_transform

# Called when this object is grabbed by a VRHandCollider
func grab(by_hand):
	if not enabled:
		return false
	
	# Get the grippable object (our parent)
	var grippable_object = get_parent()
	if not grippable_object:
		push_error("Grippable has no parent object to grab")
		return false
	
	# Find the best grab point for this hand
	var best_grab_point = _find_best_grab_point(by_hand)
	
	# Handle already grabbed object based on second hand behavior
	if is_grabbed:
		match second_hand_behavior:
			SecondHandMode.IGNORE:
				# Ignore second hand grab attempts
				print("Object already grabbed, ignoring second hand")
				return false
				
			SecondHandMode.SWAP:
				# Release from first hand and allow second hand to grab
				print("Swapping to second hand")
				var previous_hand = grabbed_by
				var world_transform = grippable_object.global_transform
				
				# Force release from current hand (with zero velocity to avoid throwing)
				if is_instance_valid(grabbed_by):
					release(grabbed_by, Vector3.ZERO, Vector3.ZERO)
				
				# Use the best grab point we found
				active_grab_point = best_grab_point
				
				# The release resets grab state, now we can continue with normal grab
				
			SecondHandMode.BOTH:
				# For now, just add to secondary hands
				print("Adding second hand")
				if by_hand not in secondary_hands:
					secondary_hands.append(by_hand)
				
				# If we have a grab point, notify it
				if best_grab_point and best_grab_point.has_method("grabbed"):
					best_grab_point.grabbed()
					
				return true
	
	# Store original state if not already grabbed
	if not is_grabbed:
		original_parent = grippable_object.get_parent()
		original_transform = grippable_object.transform
		
		# Store original collision settings if this is a CollisionObject
		if grippable_object is CollisionObject3D:
			original_collision_layer = grippable_object.collision_layer
			original_collision_mask = grippable_object.collision_mask
	
	# Update grab state
	is_grabbed = true
	grabbed_by = by_hand
	
	# Remember the global transform before reparenting
	var world_transform = grippable_object.global_transform
	
	# Remove from current parent (could be original parent or previous hand's controller)
	var current_parent = grippable_object.get_parent()
	if current_parent:
		current_parent.remove_child(grippable_object)
	
	# If no specific grab point was found, use the first compatible one or null
	if not is_instance_valid(active_grab_point):
		active_grab_point = best_grab_point
	
	# Notify the active grab point it was grabbed
	if active_grab_point and active_grab_point.has_method("grabbed"):
		active_grab_point.grabbed()
		
	# Hide other grab points' visuals
	for grab_point in _get_grab_points():
		if grab_point != active_grab_point and grab_point.has_method("set_ring_visible"):
			grab_point.set_ring_visible(false)
	
	# Get the controller node
	var controller_node = by_hand.get_parent()
	if not controller_node or not controller_node is XRController3D:
		controller_node = by_hand
	
	# Add to controller
	controller_node.add_child(grippable_object)
	
	# Maintain world position
	grippable_object.global_transform = world_transform
	
	# Handle collision layers for the grabbed object
	if grippable_object is CollisionObject3D:
		# Store original collision settings
		original_collision_layer = grippable_object.collision_layer
		original_collision_mask = grippable_object.collision_mask
	
		if disable_collisions_when_grabbed:
			if retain_collision_with_hands:
				# Always make the object visible to BOTH hands (layers 3+4) plus player body (layer 2)
				# This fixes the issue where held objects weren't visible to the other hand
				# Set layer to BOTH left and right hand layers (8+4=12) to be visible to all hand colliders
				grippable_object.collision_layer = 12 # Layers 3+4 (binary: 00001100)
				# Allow object to see both hands and the player body
				grippable_object.collision_mask = 14 # Layers 2+3+4 (binary: 00001110)
				
				# Completely disable all collisions
				grippable_object.collision_layer = 0
				grippable_object.collision_mask = 0
		else:
			# Not disabling collisions, but ensure hand collision is set up properly
			if by_hand is Area3D and retain_collision_with_hands:
				# Always add both hands' layers
				grippable_object.collision_mask |= 12 # Layers 3+4 (binary: 00001100)
				
	
	# Make physics objects behave properly when grabbed
	if grippable_object is RigidBody3D:
		var rigid_body = grippable_object as RigidBody3D
		rigid_body.freeze = true
		rigid_body.gravity_scale = 0.0
	
	# Turn off highlight when grabbed
	if highlight_on_hover:
		_set_highlight(false)
	
	# Emit the signal
	emit_signal("grabbed", by_hand)
	return true

# Called when this object is released by a VRHandCollider
func release(by_hand, throw_velocity = Vector3.ZERO, throw_angular_velocity = Vector3.ZERO):
	# Check if this is a secondary hand
	if by_hand in secondary_hands:
		secondary_hands.erase(by_hand)
		return true
	
	if not is_grabbed or grabbed_by != by_hand:
		return false
		
	# Get the grippable object
	var grippable_object = get_parent()
	if not grippable_object:
		push_error("Grippable has no parent object to release")
		return false
	
	# Remember the global transform before reparenting
	var world_transform = grippable_object.global_transform
	
	# Remove from current parent
	var current_parent = grippable_object.get_parent()
	if current_parent:
		current_parent.remove_child(grippable_object)
	
	# Add back to original parent
	original_parent.add_child(grippable_object)
	
	# Keep the world position after reparenting
	grippable_object.global_transform = world_transform
	
	# Restore original collision settings
	if grippable_object is CollisionObject3D:
		grippable_object.collision_layer = original_collision_layer
		grippable_object.collision_mask = original_collision_mask
	
	# Calculate proper throw velocity
	var final_throw_velocity = throw_velocity
	var final_angular_velocity = throw_angular_velocity
	
	# If we have our own velocity tracking, use that instead
	if _velocity_averager and grippable_object is RigidBody3D:
		final_throw_velocity = _velocity_averager.linear_velocity() * throw_impulse_factor
		final_angular_velocity = _velocity_averager.angular_velocity()
	
	# Handle physics objects
	if grippable_object is RigidBody3D:
		var rigid_body = grippable_object as RigidBody3D
		rigid_body.freeze = false
		rigid_body.gravity_scale = 1.0
		
		 # Apply combined velocity
		rigid_body.linear_velocity = final_throw_velocity
		rigid_body.angular_velocity = final_angular_velocity
	
	# Notify the active grab point it was released
	if active_grab_point and active_grab_point.has_method("released"):
		active_grab_point.released()
		
	# Show other grab points' visuals again
	for grab_point in _get_grab_points():
		if grab_point != active_grab_point and grab_point.has_method("set_ring_visible"):
			grab_point.set_ring_visible(true)
	
	# Reset state
	is_grabbed = false
	grabbed_by = null
	active_grab_point = null
	
	# Emit the signal
	emit_signal("released", by_hand)
	return true

# Called when a hand hovers over this object
func hover_begin(by_hand):
	if by_hand not in hovering_hands:
		hovering_hands.append(by_hand)
		emit_signal("hovered", by_hand)
		
		# Show highlight when hovered
		if highlight_on_hover:
			_set_highlight(true)

# Called when a hand stops hovering over this object
func hover_end(by_hand):
	if by_hand in hovering_hands:
		hovering_hands.erase(by_hand)
		emit_signal("unhovered", by_hand)
		
		# Hide highlight when not hovered
		if highlight_on_hover and hovering_hands.size() == 0:
			_set_highlight(false)

# Check if this object can be grabbed
func can_grab(by_hand):
	# If not enabled at all, can't be grabbed
	if not enabled:
		return false
		
	# If not currently grabbed, can be grabbed
	if not is_grabbed:
		# Check if any grab point is compatible with this hand
		var has_compatible_grab_point = false
		var grab_points = _get_grab_points()
		
		if grab_points.size() > 0:
			for grab_point in grab_points:
				if grab_point.can_be_grabbed_by(by_hand):
					has_compatible_grab_point = true
					break
			
			return has_compatible_grab_point
		
		# No grab points defined, allow grab by any hand
		return true
		
	# If already grabbed, check second-hand behavior
	match second_hand_behavior:
		SecondHandMode.IGNORE:
			# Can't grab if we're ignoring second hand
			return false
			
		SecondHandMode.SWAP, SecondHandMode.BOTH:
			# Can grab if we allow swapping or both hands
			return true
			
	return false

# Find the best grab point for a particular hand
func _find_best_grab_point(hand):
	var grab_points = _get_grab_points()
	if grab_points.size() == 0:
		return null
	
	var best_grab_point = null
	var best_distance = 10000.0
	
	for grab_point in grab_points:
		if grab_point.can_be_grabbed_by(hand):
			var distance = hand.global_position.distance_to(grab_point.global_position)
			if distance < best_distance:
				best_distance = distance
				best_grab_point = grab_point
	
	return best_grab_point

# Get all grab points on this object
func _get_grab_points():
	var grab_points = []
	var grippable_object = get_parent()
	
	if grippable_object:
		for child in grippable_object.get_children():
			if child is GrabPoint:
				grab_points.append(child)
	
	return grab_points

# Set highlight on or off
func _set_highlight(enabled):
	if not highlight_mesh_instance.is_empty():
		var highlight_node = get_node_or_null(highlight_mesh_instance)
		if highlight_node and highlight_node is MeshInstance3D:
			if enabled:
				# Enable highlight effect
				if highlight_node.material_override:
					highlight_node.material_override.emission_enabled = true
					highlight_node.material_override.emission_energy = 1.0
			else:
				# Disable highlight effect
				if highlight_node.material_override:
					highlight_node.material_override.emission_enabled = false

# Check if this object is currently grabbed
func is_currently_grabbed():
	return is_grabbed

# Get the hand currently grabbing this object
func get_grabbed_by():
	return grabbed_by
