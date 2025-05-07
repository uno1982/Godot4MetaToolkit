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
@export var grab_offset: Vector3 = Vector3.ZERO # Offset position when grabbed
@export var grab_rotation: Vector3 = Vector3.ZERO # Offset rotation when grabbed

# State tracking
var is_grabbed: bool = false
var grabbed_by = null # The hand currently grabbing this object
var hovering_hands = [] # All hands currently hovering over this object
var original_parent = null # Original parent before grabbed
var original_transform = Transform3D() # Original transform before grabbed

# Constants for follow speed
var follow_speed: float = 20.0 # Speed at which object follows hand

func _ready():
	# Initialize in editor mode check
	if Engine.is_editor_hint():
		return

# Override _physics_process to update the object's position to follow the hand
func _physics_process(delta):
	if is_grabbed and is_instance_valid(grabbed_by):
		 # Update position based on hand movement with offset
		var target_position = grabbed_by.global_position + grabbed_by.global_transform.basis * grab_offset
		
		# Update rotation based on hand rotation with offset
		var target_rotation = Vector3(
			grabbed_by.global_rotation.x + deg_to_rad(grab_rotation.x),
			grabbed_by.global_rotation.y + deg_to_rad(grab_rotation.y),
			grabbed_by.global_rotation.z + deg_to_rad(grab_rotation.z)
		)
		
		# Smoothly move to target position and rotation
		global_position = global_position.lerp(target_position, delta * follow_speed)
		global_rotation.x = lerp_angle(global_rotation.x, target_rotation.x, delta * follow_speed)
		global_rotation.y = lerp_angle(global_rotation.y, target_rotation.y, delta * follow_speed)
		global_rotation.z = lerp_angle(global_rotation.z, target_rotation.z, delta * follow_speed)

# Called when this object is grabbed by a VRHandCollider
func grab(by_hand):
	if not enabled or is_grabbed:
		return false
		
	# Get the grippable object (our parent)
	var grippable_object = get_parent()
	if not grippable_object:
		push_error("Grippable has no parent object to grab")
		return false
	
	# Store original state
	is_grabbed = true
	grabbed_by = by_hand
	original_parent = grippable_object.get_parent()
	original_transform = grippable_object.transform
	
	# Remember the global transform before reparenting
	var world_transform = grippable_object.global_transform
	
	# Remove from original parent
	original_parent.remove_child(grippable_object)
	
	# Get the controller node
	var controller_node = by_hand.get_parent()
	if not controller_node or not controller_node is XRController3D:
		controller_node = by_hand
	
	# Add to controller
	controller_node.add_child(grippable_object)
	
	# Maintain world position
	grippable_object.global_transform = world_transform
	
	# Make physics objects behave properly when grabbed
	if grippable_object is RigidBody3D:
		var rigid_body = grippable_object as RigidBody3D
		rigid_body.freeze = true
		rigid_body.gravity_scale = 0.0
	
	# Emit the signal
	emit_signal("grabbed", by_hand)
	return true

# Called when this object is released by a VRHandCollider
func release(by_hand, throw_velocity = Vector3.ZERO, throw_angular_velocity = Vector3.ZERO):
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
	
	# Handle physics objects
	if grippable_object is RigidBody3D:
		var rigid_body = grippable_object as RigidBody3D
		rigid_body.freeze = false
		rigid_body.gravity_scale = 1.0
		
		 # Apply combined velocity (hand's calculated velocity + throw)
		rigid_body.linear_velocity = throw_velocity
		rigid_body.angular_velocity = throw_angular_velocity
	
	# Reset state
	is_grabbed = false
	grabbed_by = null
	
	# Emit the signal
	emit_signal("released", by_hand)
	return true

# Called when a hand hovers over this object
func hover_begin(by_hand):
	if by_hand not in hovering_hands:
		hovering_hands.append(by_hand)
		emit_signal("hovered", by_hand)

# Called when a hand stops hovering over this object
func hover_end(by_hand):
	if by_hand in hovering_hands:
		hovering_hands.erase(by_hand)
		emit_signal("unhovered", by_hand)

# Check if this object can be grabbed
func can_grab(by_hand):
	# The by_hand parameter is used for interface consistency and potential future use
	# for hand-specific grab conditions
	return enabled and not is_grabbed

# Check if this object is currently grabbed
func is_currently_grabbed():
	return is_grabbed

# Get the hand currently grabbing this object
func get_grabbed_by():
	return grabbed_by
