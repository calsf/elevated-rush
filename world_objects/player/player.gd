extends KinematicBody2D

const MAX_SPEED = 175
const RISE_SPEED = 2.75
const FALL_SPEED = 4
const MAX_HEIGHT = 44
const DECEL = 500
const SOUND_DELAY = .1
const INVULN_TIME = .2

# Move speed properties
var velocity = Vector2.ZERO
var curr_speed = MAX_SPEED

# Knockback properties
var knockback = Vector2.ZERO
var can_play = true
var last_area_hit = null
var curr_knockback_strength = 0

# Jumping and elevation properties
var change = 0
var grav = 0
var is_jumping = false
var is_falling = false
var has_double_jumped = false
var has_jumped = false
var is_tumbling = false		# For falling down a wall
var jump_height = MAX_HEIGHT	# The number of pixels to jump up (the target added_height will try to reach when is jumping)
var added_height = 0	# Current number of pixels above ground, grounded at 0
var elevations = [
	0, 
	Globals.ELEVATION_UNIT * 1, 
	Globals.ELEVATION_UNIT * 2, 
	Globals.ELEVATION_UNIT * 3, 
	Globals.ELEVATION_UNIT * 4,
	Globals.ELEVATION_UNIT * 5,
	Globals.ELEVATION_UNIT * 6,
	Globals.ELEVATION_UNIT * 7,
	Globals.ELEVATION_UNIT * 8,
	]
export var ground_elevation = Globals.ELEVATION_UNIT	# The elevation of height in which player is considered grounded

# Death
signal player_died
signal player_reset
var is_respawning = false

# Stop player input
var player_stopped = true

# Camera offset amount when elevation changes, will gradually return to 0
var cam_offset = 0

onready var start_elevation = ground_elevation
onready var player_shadow = $Shadow
onready var player_sprite = $PlayerSprite
onready var camera = $Camera2D
onready var collision_shape = $CollisionShape2D
onready var overlapping_wall_area = $OverlappingWallCheck
onready var detect_elev_area = $DetectElevArea
onready var hurtbox = $HurtboxArea2D
onready var hit_timer = $HurtboxArea2D/HitTimer
onready var invuln_timer = $HurtboxArea2D/InvulnTimer
onready var respawn_timer = $RespawnTimer
onready var animation_player = $AnimationPlayer
onready var animation_tree = $AnimationTree
onready var animation_state = animation_tree.get("parameters/playback")
onready var sounds = $Sounds

func _ready():
	animation_tree.set("parameters/Idle/blend_position", Vector2.DOWN)
	animation_tree.set("parameters/Move/blend_position", Vector2.DOWN)
	animation_tree.set("parameters/Jump/blend_position", Vector2.DOWN)
	animation_tree.set("parameters/DoubleJump/blend_position", Vector2.DOWN)
	animation_tree.set("parameters/Fall/blend_position", Vector2.DOWN)
	animation_tree.set("parameters/Death/blend_position", Vector2.DOWN)

func _physics_process(delta):
	# Wait for respawn timer to finish and reset is_respawning
	if (is_respawning):
		return
	
	# Perform normal jump or double jump when button is pressed
	# If player is stopped, do not listen for inputs
	if (!player_stopped):
		if Input.is_action_just_pressed("jump") and !has_jumped:
			animation_state.travel("Jump")
			grav = 0
			has_jumped = true
			jump_height = MAX_HEIGHT + added_height
			is_jumping = true
			is_falling = false
			sounds.play("Jump")
		elif Input.is_action_just_pressed("jump") and has_jumped and !has_double_jumped:
			animation_state.travel("DoubleJump")
			grav = 0
			has_double_jumped = true
			jump_height = MAX_HEIGHT + added_height	# Increase target jump height by MAX_HEIGHT
			is_jumping = true
			is_falling = false
			sounds.play("Jump")

	# Gradually decrease knockback value and knockback strength to 0 and apply current knockback
	# The knockback and curr_knockback_strength should be equal or decreasing at same rate
	knockback = knockback.move_toward(Vector2.ZERO, DECEL * delta)
	curr_knockback_strength = clamp(curr_knockback_strength - (DECEL * delta), 0, 9999)
	knockback = move_and_slide(knockback)
	
	# Applies falling effect to player if they are caught inside a wall
	# Provides more accurate drop off from elevations as well
	if is_tumbling and added_height <= 0:
		velocity.y += MAX_SPEED * delta
		velocity = move_and_slide(velocity)
		_check_overlapping_wall()
		return
	
	# Only collide with world objects when in knockback state
	set_collision_mask_bit(0, knockback != Vector2.ZERO)
	
	# Get input vector
	# Allow player to slightly affect movement while in knockback
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	input_vector = input_vector.normalized()
		
	# Set velocity and animation state based on input_vector
	if (!player_stopped and input_vector != Vector2.ZERO):
		# Only set blend positions when input vector is not zero
		animation_tree.set("parameters/Idle/blend_position", input_vector)
		animation_tree.set("parameters/Move/blend_position", input_vector)
		animation_tree.set("parameters/DoubleJump/blend_position", input_vector)
		animation_tree.set("parameters/Jump/blend_position", input_vector)
		animation_tree.set("parameters/Fall/blend_position", input_vector)
		animation_tree.set("parameters/Death/blend_position", input_vector)
		
		if (!is_jumping and !is_falling):
			animation_state.travel("Move")
		
		velocity = input_vector * curr_speed
	else:
		if (!is_jumping and !is_falling):
			animation_state.travel("Idle")
		velocity = Vector2.ZERO
		
	# Move and slide using current velocity, set velocity to maintain velocity after collision
	velocity = move_and_slide(velocity)
		
	# JUMPING AND FALLING MOVEMENT, ELSE PLAYER IS GROUNDED
	# STILL ENABLED DURING KNOCKBACK BUT PLAYER INPUT TO JUMP SHOULD BE DISABLED
	if is_jumping:
		# Increase added height until reaches jump height
		# Move player sprite up the same amount
		if added_height < jump_height:
			grav += .025 # Apply increasing rise speed
			# Avoid jumping above jump height
			change = min(RISE_SPEED + grav, jump_height - added_height)
			
			added_height += change
			player_sprite.position.y -= change
		else:
			grav = 0
			is_falling = true	# Once jump_height is reached, set to falling state
			is_jumping = false	# No longer in jump state
	elif is_falling:
		animation_state.travel("Fall")
		
		# Subtract from added height until reaches 0 or less
		# Move player sprite down the same amount
		if added_height > 0:
			grav += .025	# Apply increasing gravity force
			change = FALL_SPEED + grav
			# Avoid added_height going below 0
			if added_height - change < 0:
				change = added_height
			
			added_height -= change
			player_sprite.position.y += change
		else:
			# Reset jump related values
			jump_height = MAX_HEIGHT
			added_height = 0
			grav = 0 	# Reset gravity
			is_falling = false
			has_jumped = false
			has_double_jumped = false
	else:
		# When grounded, check if player ends up overlapping with a wall
		_check_overlapping_wall()
	
	# Calculate current elevation and then set collision masks accordingly
	_set_elevation_collisions(get_curr_elevation())
	
	# Maintain sprite positions when grounded
	if (added_height <= 0):
		player_sprite.position.y = -7
		player_shadow.position.y = 1
	
	# Change player sprite's z index based on current height
	player_sprite.z_index = (ground_elevation + added_height) / Globals.ELEVATION_UNIT
	# Change player shadow z index based on ground elevation only
	player_shadow.z_index = (ground_elevation) / Globals.ELEVATION_UNIT
	
	# Check for overlapping WorldObject layer areas in hurtbox and apply hit
	for area in hurtbox.get_overlapping_areas():
		if (area.get_owner() != self):
			var other_elev = area.elevation
			if (last_area_hit != area and other_elev == get_curr_elevation() and other_elev == ground_elevation
			or area.cover_all_elev and get_curr_elevation() < area.elevation + area.extra_coverage and get_curr_elevation() > area.elevation):
				# Init knockback vector to opposite of player input vector (current facing direction)
				var knockback_vector = -input_vector
				
				# If area has set knockback, always apply set knockback if it exists
				# Else if no set knockback, check if player is not moving or if player already in knockback state
				# Do not let player alter knockback direction with input if already in a knockback state
				if (area.has_set_knockback):
					knockback_vector = area.get_owner().knockback_vector
				elif (input_vector == Vector2.ZERO or knockback != Vector2.ZERO):
					# Always apply other object's moving knockback vector if player is not moving
					# If player is not moving, there is no way for them to collide with the moving object in the wrong direction
					if (area.is_moving):
						knockback_vector = area.get_owner().knockback_vector
					else:
						# Other object is not moving, has no set knockback, and player not moving
						knockback_vector = global_position - area.get_owner().global_position
				
				# Use the higher knockback strength between current knockback strength and the area's knockback strength
				if (area.knockback_strength > curr_knockback_strength):
					curr_knockback_strength = area.knockback_strength
				knockback = knockback_vector.normalized() * curr_knockback_strength
				
				# If there is an animation for when player enters area, play it
				if (area.has_anim):
					area.get_owner().play_anim()
				
				# Delay before playing hit sound again
				if (can_play):
					can_play = false
					hit_timer.start(SOUND_DELAY)
					sounds.play("Hit")
				
				# Avoid hitting same area within INVULN_TIME
				last_area_hit = area
				invuln_timer.start(INVULN_TIME)
				return	
				
	_death_check()
	
	# Smooth camera when it gets offset by elevation changes
	# Do not move camera down when jumping to prevent jarring camera movement when jumping between high elevations
	if (cam_offset < 0):
		camera.global_position.y -= FALL_SPEED
		cam_offset += FALL_SPEED
	elif (cam_offset > 0 and !is_jumping):
		camera.global_position.y += FALL_SPEED
		cam_offset -= FALL_SPEED
	
	# Scale shadow to be smaller the higher player is above ground
	var scale_mult = (added_height / 8) / 100
	player_shadow.scale = Vector2(1.5, 1.5) * (Vector2(1 - scale_mult, 1 - scale_mult))

## FUNCTIONS ##

# Set collision masks for collisions with elevation boundary and walls
# Wall collision should match boundary collision
func _set_elevation_collisions(curr_elevation):
	# Boundary mask layer of elevation 1
	set_collision_mask_bit(3, curr_elevation < elevations[1] and ground_elevation < elevations[1])
	# Boundary mask layer of elevation 2
	set_collision_mask_bit(5, curr_elevation < elevations[2] and ground_elevation < elevations[2])
	# Boundary mask layer of elevation 3
	set_collision_mask_bit(7, curr_elevation < elevations[3] and ground_elevation < elevations[3])
	# Boundary mask layer of elevation 4
	set_collision_mask_bit(9, curr_elevation < elevations[4] and ground_elevation < elevations[4])
	# Boundary mask layer of elevation 5
	set_collision_mask_bit(11, curr_elevation < elevations[5] and ground_elevation < elevations[5])
	# Boundary mask layer of elevation 6
	set_collision_mask_bit(13, curr_elevation < elevations[6] and ground_elevation < elevations[6])
	# Boundary mask layer of elevation 7
	set_collision_mask_bit(15, curr_elevation < elevations[7] and ground_elevation < elevations[7])
	# Boundary mask layer of elevation 8
	set_collision_mask_bit(17, curr_elevation < elevations[8] and ground_elevation < elevations[8])
	
	# Wall mask layer of elevation 1
	set_collision_mask_bit(4, get_collision_mask_bit(3))
	# Wall mask layer of elevation 2
	set_collision_mask_bit(6, get_collision_mask_bit(5))
	# Wall mask layer of elevation 3
	set_collision_mask_bit(8, get_collision_mask_bit(7))
	# Wall mask layer of elevation 4
	set_collision_mask_bit(10, get_collision_mask_bit(9))
	# Wall mask layer of elevation 5
	set_collision_mask_bit(12, get_collision_mask_bit(11))
	# Wall mask layer of elevation 6
	set_collision_mask_bit(14, get_collision_mask_bit(13))
	# Wall mask layer of elevation 7
	set_collision_mask_bit(16, get_collision_mask_bit(15))
	# Wall mask layer of elevation 8
	set_collision_mask_bit(18, get_collision_mask_bit(17))

# Check if player is overlapping a wall and set tumbling state and collision shape accordingly
func _check_overlapping_wall():
	# get if player area is overlapping a wall, if it is, tumble down
	# isTumbling will disable player input
	if overlapping_wall_area.get_overlapping_bodies().size() > 0:
		#collision_shape.disabled = true
		is_tumbling = true
	else:
		#collision_shape.disabled = false
		is_tumbling = false	

# Check if player is dead
func _death_check():
	# Player is dead if elevation is 0 and player is not in air
	if !is_respawning and ground_elevation == 0 and added_height <= 0:
		is_respawning = true
		animation_state.travel("Death")
		player_shadow.visible = false
		emit_signal("player_died")
		respawn_timer.start(1)
		sounds.play("Splash")

# Get current elevation of player
func get_curr_elevation():
	# Calculate current elevation and then set collision masks accordingly
	var curr_elevation = added_height + ground_elevation
	return curr_elevation

# Resets player properties to default, as if player first started level
func reset_player():
	ground_elevation = start_elevation
	_set_elevation_collisions(get_curr_elevation())
	camera.smoothing_enabled = false	# Need to turn off smoothing so camera snaps
	global_position = Vector2.ZERO
	can_play = true
	is_jumping = false
	is_falling = false
	has_double_jumped = false
	has_jumped = false
	is_tumbling = false
	jump_height = MAX_HEIGHT
	velocity = Vector2.ZERO
	knockback = Vector2.ZERO
	curr_knockback_strength = 0
	player_sprite.z_index = 1
	player_shadow.visible = true
	animation_tree.set("parameters/Idle/blend_position", Vector2.DOWN)
	animation_tree.set("parameters/Move/blend_position", Vector2.DOWN)
	animation_tree.set("parameters/DoubleJump/blend_position", Vector2.DOWN)
	animation_tree.set("parameters/Jump/blend_position", Vector2.DOWN)
	animation_tree.set("parameters/Fall/blend_position", Vector2.DOWN)
	animation_tree.set("parameters/Death/blend_position", Vector2.DOWN)
	animation_state.travel("Respawn")	# Travel to respawn animation

# Sorts areas elevation in ascending order
func _sort_overlapping_elevs_ascending(a, b):
	if (a.get_owner().elevation < b.get_owner().elevation):
		return true
	return false
	
## SIGNALS ##
		
# Detect elevation entry
func _on_DetectElevEntry_area_entered(area):
	var area_elev = area.get_owner().elevation	# Get elevation of entered area
	# Check for player elevation before allowing entry into new elevation
	# Only enter elevations that are higher than current ground elevation
	if ground_elevation < area_elev:
		if (ground_elevation + added_height >= area_elev):
			# Get distance to move up
			var move_up = area_elev - ground_elevation
			
			# Set new ground elevation to the entered elevation
			ground_elevation = area_elev
			
			# Create illusion of going up elevation
			jump_height -= move_up
			added_height -= move_up
			player_sprite.position.y += move_up
			position.y -= move_up
			
			# Maintain camera position and change offset amount
			camera.global_position.y += move_up
			cam_offset -= move_up

# Detect elevation area exit
func _on_DetectElevArea_area_exited(area):
	var area_elev = area.get_owner().elevation	# Get elevation of exited area
	if (ground_elevation == area_elev):
		# Get distance to drop down using the overlapping area's elevation difference
		var overlapping_elevs = detect_elev_area.get_overlapping_areas()
		overlapping_elevs.sort_custom(Area2D, "_sort_overlapping_elevs_ascending")
		var drop_down = (ground_elevation - overlapping_elevs[0].get_owner().elevation)
		
		# If drop down is 0, then there is no other elevation area upon exit
		# Should then drop down all the way to 0 ground elevation
		if (drop_down == 0):
			drop_down = ground_elevation
		
		# Create illusion of dropping down elevation
		jump_height += drop_down
		added_height += drop_down
		player_sprite.position.y -= drop_down
		position.y += drop_down
		ground_elevation -= drop_down
		
		# Set falling state to true
		is_falling = true
		
		# Maintain camera position and change offset amount
		camera.global_position.y -= drop_down
		cam_offset += drop_down

# Reset can play hit sound after timer
func _on_Timer_timeout():
	can_play = true

# Reset last area hit after timer
func _on_InvulnTimer_timeout():
	last_area_hit = null

# Reset player properties and respawn player after timer
func _on_RespawnTimer_timeout():
	reset_player()
	
	# Block execution until reset, also waits for Respawn animation to finish
	yield(get_tree().create_timer(.9), "timeout")
	camera.smoothing_enabled = true	# Re-enable camera smoothing
	emit_signal("player_reset")	# Emit player reset signal
	is_respawning = false



