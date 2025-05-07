@tool
extends Node3D
class_name GrabPoint

## A grab point for VR hands
## Add this as a child to any Grippable object to define specific grab positions

# Enumerations
enum HandType {
	ANY, # Can be grabbed by either hand
	LEFT, # Can only be grabbed by left hand
	RIGHT # Can only be grabbed by right hand
}

enum GrabMode {
	SNAP, # Hand snaps to this point
	PRECISE # Hand follows precise motion from this point
}

# Properties
@export var hand_type: HandType = HandType.ANY: set = _set_hand_type
@export var grab_mode: GrabMode = GrabMode.SNAP
@export var hand_pose: Resource = null # Optional custom hand pose resource

# Positioning settings
@export var drive_position: float = 0.0 # How much the object follows hand position (0-1)
@export var drive_rotation: float = 0.0 # How much the object follows hand rotation (0-1)
@export var drive_aim: float = 0.0 # How much the object aligns with hand aim direction (0-1)

# Visual settings for the ring
@export var show_ring: bool = true: set = _set_show_ring
@export var ring_size: float = 0.2: set = _set_ring_size
@export var ring_color: Color = Color(1.0, 0.8, 0.2, 0.8): set = _set_ring_color
@export var pulse_effect: bool = false: set = _set_pulse_effect
@export var use_hand_colors: bool = true: set = _set_use_hand_colors

# Pre-defined colors for hands
const LEFT_HAND_COLOR = Color(0.2, 0.4, 1.0, 0.8) # Blue
const RIGHT_HAND_COLOR = Color(1.0, 0.2, 0.2, 0.8) # Red
const ANY_HAND_COLOR = Color(1.0, 0.8, 0.2, 0.8) # Yellow (default)

# Billboard node
var _ring_billboard: Sprite3D
var _pulse_time: float = 0.0

func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()
	
	# Check if we're a child of a node with a Grippable component
	var parent = get_parent()
	var has_grippable = false
	
	while parent and not has_grippable:
		if parent.get_script() == Grippable:
			has_grippable = true
			break
		if parent is Node3D and parent.has_node("Grippable"):
			has_grippable = true
			break
		parent = parent.get_parent()
	
	if not has_grippable:
		warnings.append("GrabPoint should be a child of an object with a Grippable component.")
	
	return warnings

func _ready():
	# If we're using hand colors, apply them
	if use_hand_colors:
		_set_hand_type(hand_type)
		
	# Create the ring billboard
	_create_ring_billboard()

# Create a billboard sprite for the ring
func _create_ring_billboard():
	if not show_ring:
		if _ring_billboard and is_instance_valid(_ring_billboard):
			_ring_billboard.queue_free()
			_ring_billboard = null
		return
		
	if not _ring_billboard:
		_ring_billboard = Sprite3D.new()
		_ring_billboard.name = "RingBillboard"
		add_child(_ring_billboard)
		
	# Configure the billboard properties
	_ring_billboard.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_ring_billboard.transparent = true
	_ring_billboard.no_depth_test = true
	_ring_billboard.pixel_size = 0.001 # Small pixel size for higher resolution
	_ring_billboard.scale = Vector3(ring_size, ring_size, ring_size)
	
	# Load the ring texture
	var texture = load("res://assets/textures/ring.png")
	if texture:
		_ring_billboard.texture = texture
	else:
		push_error("GrabPoint: Failed to load ring texture at res://assets/textures/ring.png")
		
	# Set the color and modulate
	_ring_billboard.modulate = ring_color

func _process(delta):
	if _ring_billboard and is_instance_valid(_ring_billboard) and pulse_effect:
		# Simple pulse animation
		_pulse_time += delta * 2.0
		var pulse = (sin(_pulse_time) * 0.2) + 0.8
		_ring_billboard.scale = Vector3(ring_size * pulse, ring_size * pulse, ring_size * pulse)
		
		# Also pulse the opacity
		var color = ring_color
		color.a = ring_color.a * pulse
		_ring_billboard.modulate = color

# Property setter for show_ring
func _set_show_ring(value):
	show_ring = value
	if is_inside_tree():
		_create_ring_billboard()

# Property setter for ring_size
func _set_ring_size(value):
	ring_size = value
	if is_inside_tree() and _ring_billboard and is_instance_valid(_ring_billboard):
		_ring_billboard.scale = Vector3(ring_size, ring_size, ring_size)

# Property setter for ring_color
func _set_ring_color(value):
	ring_color = value
	if is_inside_tree() and _ring_billboard and is_instance_valid(_ring_billboard):
		_ring_billboard.modulate = value

# Property setter for pulse effect
func _set_pulse_effect(value):
	pulse_effect = value
	# Reset the pulse time when turning on
	if value:
		_pulse_time = 0.0

# Property setter for hand_type
func _set_hand_type(value):
	hand_type = value
	if use_hand_colors:
		match hand_type:
			HandType.LEFT:
				ring_color = LEFT_HAND_COLOR
			HandType.RIGHT:
				ring_color = RIGHT_HAND_COLOR
			_:
				ring_color = ANY_HAND_COLOR
		if is_inside_tree() and _ring_billboard and is_instance_valid(_ring_billboard):
			_ring_billboard.modulate = ring_color

# Property setter for use_hand_colors
func _set_use_hand_colors(value):
	use_hand_colors = value
	if use_hand_colors:
		_set_hand_type(hand_type)

# Check if this grab point is compatible with the given hand
func can_be_grabbed_by(hand_collider):
	# If hand_collider has hand_type property
	var hand_side = HandType.ANY
	
	if hand_collider.has_meta("hand_type"):
		hand_side = hand_collider.get_meta("hand_type")
	elif hand_collider.name.to_lower().contains("left"):
		hand_side = HandType.LEFT
	elif hand_collider.name.to_lower().contains("right"):
		hand_side = HandType.RIGHT
	
	# Check compatibility
	if hand_type == HandType.ANY:
		return true
	elif hand_type == HandType.LEFT and hand_side == HandType.LEFT:
		return true
	elif hand_type == HandType.RIGHT and hand_side == HandType.RIGHT:
		return true
	
	return false

# Show or hide the ring visual
func set_ring_visible(visible: bool):
	if _ring_billboard and is_instance_valid(_ring_billboard):
		_ring_billboard.visible = visible

# Called when object is grabbed - hide the ring
func grabbed():
	set_ring_visible(false)

# Called when object is released - show the ring again
func released():
	set_ring_visible(show_ring)
