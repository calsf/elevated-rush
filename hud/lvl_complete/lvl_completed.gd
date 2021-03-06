extends Control

const BRONZE = preload("res://hud/player_time/time_icon_bronze.png")
const SILVER = preload("res://hud/player_time/time_icon_silver.png")
const GOLD = preload("res://hud/player_time/time_icon_gold.png")

export var unlock_all = false

onready var finish_flag = get_node("../../YSortWorldObjects/FinishFlag")
onready var exit_door = get_node("../../YSortWorldObjects/ExitDoor")
onready var player_time = get_node("../PlayerTime")
onready var new_best_time = $CenterContainer/VBoxContainer/NewBestTime
onready var finish_time = $CenterContainer/VBoxContainer/FinishTime/TimeText
onready var best_time = $CenterContainer/VBoxContainer/BestTime/TimeText
onready var press_key_label = $CenterContainer/VBoxContainer/PressAnyKeyLabel
onready var press_key_anim = $CenterContainer/VBoxContainer/PressAnyKeyLabel/AnimationPlayer
onready var save_load_manager = $SaveLoadManager
onready var save_data = save_load_manager.load_data()
onready var time_icon = $CenterContainer/VBoxContainer/BestTime/TimeIcon
export var level_num = 0
var best = 0
var best_minutes = 0
var best_seconds = 0.00
var can_return = false

func _ready():
	# When player enters flag area and triggers level_finished, get and check finish time
	finish_flag.connect("level_finished", self, "_check_time")
	
	# Set best time display
	_update_best_time()
	
	hide()

func _input(event):
	# When any key is pressed, use exit door's behaviour to leave scene
	if can_return and (event is InputEventKey or event is InputEventJoypadButton):
		if event.pressed:
			exit_door.start_leaving_scene()
	
# Display and check finish time for new best time
func _check_time():
	show()
	
	# Finished time
	var minutes = player_time.minutes
	var seconds = player_time.seconds
	var new_time = seconds + (minutes * 60)	# Convert minutes to seconds
	
	# Display finished time
	finish_time.text = str("%0*d" % [2, minutes], "." , "%0*.*f" % [5, 2, seconds])
	
	# Update save data with new file and level completed and then save
	if (new_time < best or best == 0):
		new_best_time.show()
		
		save_data[str("Level", level_num, "Time")] = new_time
		
		# If set to true, unlock all other levels upon completion
		if unlock_all:
			save_data[str("LevelsUnlocked")] = true
		
		save_load_manager.save_data(save_data)
		
		_update_best_time()	# Update best time display
	
	# Get requirements for each time ranking
	var silver_req = save_load_manager.time_req[str("Level", level_num, "Silver")]
	var gold_req =  save_load_manager.time_req[str("Level", level_num, "Gold")]
	
	# Assign appropriate icon to player's time
	if best <= gold_req:
		time_icon.texture = GOLD
	elif best <= silver_req:
		time_icon.texture = SILVER
	else:
		time_icon.texture = BRONZE
	
	# Wait then toggle can_return tp allow player to leave by pressing any key
	yield(get_tree().create_timer(1.5), "timeout")
	can_return = true
	press_key_label.show()

# Get current saved best time and update text display
func _update_best_time():
	# Saved best time
	best = save_data[str("Level", level_num, "Time")]	# Get current saved best time
	best_minutes = best / 60
	best_seconds = fmod(best, 60.0)
	
	# Display time
	best_time.text = str("%0*d" % [2, best_minutes], "." , "%0*.*f" % [5, 2, best_seconds])
	
