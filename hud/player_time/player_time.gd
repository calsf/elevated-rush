extends Control


var seconds = 0
var minutes = 0
var is_stopped = true
onready var time_text = $HBoxContainer/TimeText
onready var player = get_node("../../YSortWorldObjects/Player")
onready var finish_flag = get_node("../../YSortWorldObjects/FinishFlag")

func _ready():
	# When player_died signal is emitted, will reset stop recording time
	player.connect("player_died", self, "_stop_time")
	# When player_reset signal is emitted, will reset time values
	player.connect("player_reset", self, "_reset_time")
	# When player enters flag area and triggers level_finished, stop time
	finish_flag.connect("level_finished", self, "_stop_time")

func _process(delta):
	# Do not record time if time is stopped
	if (is_stopped):
		return
	
	seconds += delta
	if (seconds > 60):
		minutes += 1
		seconds = 0
	
	# Cap at 99 minutes
	if minutes == 99:
		is_stopped = true
		
	# minutes.seconds.milliseconds
	time_text.text = str("%0*d" % [2, minutes], "." , "%0*.*f" % [5, 2, seconds])

# Reset time values
func _reset_time():
	is_stopped = false
	seconds = 0
	minutes = 0

# Stop time
func _stop_time():
	is_stopped = true
