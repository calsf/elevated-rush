extends Area2D

export var knockback_strength = 0
export var elevation = 0
var is_moving = false
var has_set_knockback = false

func _ready():
	# Set z index based on object elevation
	get_owner().z_index = elevation / (GlobalConst.ELEVATION_UNIT)