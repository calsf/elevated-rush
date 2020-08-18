extends KinematicBody2D

const MAX_SPEED = 200
const AIR_SPEED = 4
const MAX_HEIGHT = 44
const DECEL = 500
const INVULN_TIME = .1

var velocity = Vector2.ZERO
var curr_speed = MAX_SPEED
var is_jumping = false
var is_falling = false
var has_double_jumped = false
var has_jumped = false
var is_tumbling = false
var knockback = Vector2.ZERO
var last_area_hit = null
var curr_knockback_strength = 0

var jump_height = MAX_HEIGHT
var added_height = 0
var elevations = [0, GlobalConst.ELEVATION_UNIT * 1, GlobalConst.ELEVATION_UNIT * 2, GlobalConst.ELEVATION_UNIT * 3]
var ground_elevation = elevations[1]
var last_ground_elevation = elevations[1]

# when entered new elevation, waits to hit ground before assigning new ground elevation
# uses added_height to determine height until no longer awaiting_new_elevation
var awaiting_new_ground_elevation = false

onready var player_shadow = $Shadow
onready var player_sprite = $PlayerSprite
onready var collision_shape = $CollisionShape2D
onready var overlapping_wall_area = $OverlappingWallCheck
onready var hurtbox = $HurtboxArea2D
onready var timer = $HurtboxArea2D/Timer

func _physics_process(delta):
	# Applies falling effect to player if they are caught inside a wall
	# Provides more accurate drop off from elevations as well
	if is_tumbling and added_height <= 0:
		velocity.y += 25
		velocity = move_and_slide(velocity)
		check_overlapping_wall()
		return
		
	# Gradually decrease knockback value to 0 and apply current knockback
	knockback = knockback.move_toward(Vector2.ZERO, DECEL * delta)
	curr_knockback_strength -= clamp(DECEL * delta, 0, 9999)
	knockback = move_and_slide(knockback)
	
	# Only collide with world objects when in knockback state
	set_collision_mask_bit(0, knockback != Vector2.ZERO)
	
	# Get input vector
	# Allow player to slightly affect movement while in knockback
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	input_vector = input_vector.normalized()
		
	# Set velocity based on input_vector
	velocity = input_vector * curr_speed
		
	# Move and slide using current velocity, set velocity to maintain velocity after collision
	velocity = move_and_slide(velocity)
		
	# JUMPING AND FALLING MOVEMENT, ELSE PLAYER IS GROUNDED
	# STILL ENABLED DURING KNOCKBACK BUT PLAYER INPUT TO JUMP SHOULD BE DISABLED
	if is_jumping:
		# Increase added height until reaches jump height
		# Move player sprite up the same amount
		if added_height < jump_height:
			added_height += AIR_SPEED
			player_sprite.position.y -= AIR_SPEED
		else:
			is_falling = true	# Once jump_height is reached, set to falling state
			is_jumping = false	# No longer in jump state
	elif is_falling:
		# Subtract from added height until reaches 0 or less
		# Move player sprite down the same amount
		if added_height > 0:
			added_height -= AIR_SPEED
			player_sprite.position.y += AIR_SPEED
		else:
			# Reset jump related values
			jump_height = MAX_HEIGHT
			added_height = 0
			is_falling = false
			has_jumped = false
			has_double_jumped = false
			last_ground_elevation = ground_elevation # When grounded, can set last ground elevation to current ground elevation
			awaiting_new_ground_elevation = false	# No longer waiting for new ground elevation to be applied because player is grounded
	else:
		# When grounded, check if player ends up overlapping with a wall
		check_overlapping_wall()
	
	# Calculate current elevation and then set collision masks accordingly
	set_elevation_collisions(get_curr_elevation())
	
	# Maintain sprite positions when grounded
	if (added_height <= 0):
		player_sprite.position.y = -6
		player_shadow.position.y = 2
	
	# Change player sprite's z index based on current height
	player_sprite.z_index = (ground_elevation + added_height) / GlobalConst.ELEVATION_UNIT
	
	# Check for overlapping WorldObject layer areas in hurtbox and apply hit
	for area in hurtbox.get_overlapping_areas():
		if (area.get_owner() != self):
			var other_elev = area.get_owner().elevation
			if (last_area_hit != area and other_elev == get_curr_elevation()):
				# Init knockback vector to opposite of player input vector (current facing direction)
				var knockback_vector = -input_vector
				
				# Apply knockback on x or y axis
				# If player is farther from object's x position, player is at the side of object
				# If player is farther from object's y position, player is above/below object
				if (abs(global_position.x - area.get_owner().global_position.x) \
				> abs(global_position.y - area.get_owner().global_position.y)):
					knockback_vector.x = sign(global_position.x - area.get_owner().global_position.x)
				else:
					knockback_vector.y = sign(global_position.y - area.get_owner().global_position.y)
				
				# Use the higher knockback strength between current knockback strength and the area's knockback strength
				if (area.knockback_strength > curr_knockback_strength):
					curr_knockback_strength = area.knockback_strength
				knockback = knockback_vector.normalized() * curr_knockback_strength
				
				# Prevent getting knocked back by this same area within INVULN_TIME
				timer.start(INVULN_TIME)
				last_area_hit = area
				return
	
	#death_check()
	
# Set collision masks for collisions with elevation boundary and walls
func set_elevation_collisions(curr_elevation):
	# boundary mask layer of elevation 1
	set_collision_mask_bit(3, curr_elevation < elevations[1] and ground_elevation < elevations[1])
	# boundary mask layer of elevation 2
	set_collision_mask_bit(7, curr_elevation < elevations[2] and ground_elevation < elevations[2])
	# boundary mask layer of elevation 3
	set_collision_mask_bit(11, curr_elevation < elevations[3] and ground_elevation < elevations[3])
	
	# wall mask layer of elevation 1
	set_collision_mask_bit(4, get_collision_mask_bit(3))
	# wall mask layer of elevation 2
	set_collision_mask_bit(8, get_collision_mask_bit(7))
	# wall mask layer of elevation 2
	set_collision_mask_bit(12, get_collision_mask_bit(11))

# Check if player is overlapping a wall and set tumbling state and collision shape accordingly
func check_overlapping_wall():
	# get if player area is overlapping a wall, if it is, tumble down
	# isTumbling will disable player input
	if overlapping_wall_area.get_overlapping_bodies().size() > 0:
		print("OVERLAPPING WALL")
		collision_shape.disabled = true
		is_tumbling = true
	else:
		collision_shape.disabled = false
		is_tumbling = false	

# Check if player is dead
func death_check():
	# PLAYER DEATH CHECK (ELEVATION 0 and not in air)
	if ground_elevation == 0 and added_height <= 0:
		position = Vector2.ZERO
		print("DEAD")
		ground_elevation = 32
		
func get_curr_elevation():
	# Calculate current elevation and then set collision masks accordingly
	var curr_elevation = added_height
	if !awaiting_new_ground_elevation:
		# Use current ground elevation is grounded and not waiting for new ground elevation
		curr_elevation += ground_elevation
	else:
		# Use last ground elevation if waiting for player to be grounded to set new ground elevation
		curr_elevation += last_ground_elevation
	return curr_elevation


# Listen for button press
func _input(event):
	# If in knockback, do not listen for inputs
	if (knockback > Vector2.ZERO):
		return
			
	# Perform normal jump or double jump when button is pressed
	if Input.is_action_just_pressed("jump") and !has_jumped:
		has_jumped = true
		is_jumping = true
		is_falling = false
	elif Input.is_action_just_pressed("jump") and has_jumped and !has_double_jumped:
		has_double_jumped = true
		jump_height = added_height + MAX_HEIGHT
		is_jumping = true
		is_falling = false
		
# Detect elevation entry
func _on_DetectElevEntry_area_entered(area):
	var area_elev = area.get_owner().elevation	# Get elevation of entered area
	# Check for player elevation before allowing entry into new elevation
	# Only enter elevations that are higher than current ground elevation
	if ground_elevation < area_elev:
		# When player enters elevation area, they may still be in air and thus awaiting for new ground elevation
		# Player elevation should use last ground elevation instead of current ground elevation if awaiting new elevation 
		if (awaiting_new_ground_elevation and last_ground_elevation + added_height >= area_elev or 
		!awaiting_new_ground_elevation and ground_elevation + added_height >= area_elev):
			# Set new ground elevation to the entered elevation
			ground_elevation = area_elev
			
			# Create illusion of entering higher elevation
			added_height -= GlobalConst.ELEVATION_UNIT
			player_sprite.position.y += GlobalConst.ELEVATION_UNIT
			position.y -= GlobalConst.ELEVATION_UNIT
			
			# Entering new elevation must await for new ground elevation which will be set to false when player is grounded
			awaiting_new_ground_elevation = true

# Detect elevation area exit
func _on_DetectElevArea_area_exited(area):
	var area_elev = area.get_owner().elevation	# Get elevation of exited area
	if (ground_elevation == area_elev):
		# Create illusion of dropping down one elevation
		added_height += GlobalConst.ELEVATION_UNIT
		player_sprite.position.y -= GlobalConst.ELEVATION_UNIT
		position.y += GlobalConst.ELEVATION_UNIT
		ground_elevation -= GlobalConst.ELEVATION_UNIT
		
		# Set falling state to true
		is_falling = true

# Reset last area hit after timer
func _on_Timer_timeout():
	last_area_hit = null
