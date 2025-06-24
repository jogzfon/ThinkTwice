extends Node2D
class_name PlayerAudioManager

# Audio players
@export var run_player: AudioStreamPlayer2D = null
@export var jump_player: AudioStreamPlayer2D = null
@export var dash_player: AudioStreamPlayer2D = null

# Audio arrays
@export var run_sounds: Array[AudioStream]
@export var jump_sounds: Array[AudioStream]
@export var dash_sounds: Array[AudioStream]

# Running footstep control
var footstep_timer: Timer
var is_running: bool = false
var running_interval: float = 0.3

func _ready():
	_validate_audio_players()
	_setup_footstep_timer()

func _validate_audio_players():
	# Create missing audio players if they don't exist
	if not run_player:
		run_player = AudioStreamPlayer2D.new()
		add_child(run_player)
		run_player.name = "RunPlayer"
	
	if not jump_player:
		jump_player = AudioStreamPlayer2D.new()
		add_child(jump_player)
		jump_player.name = "JumpPlayer"
	
	if not dash_player:
		dash_player = AudioStreamPlayer2D.new()
		add_child(dash_player)
		dash_player.name = "DashPlayer"

func _setup_footstep_timer():
	footstep_timer = Timer.new()
	add_child(footstep_timer)
	footstep_timer.wait_time = running_interval
	footstep_timer.timeout.connect(_on_footstep_timer_timeout)
	footstep_timer.one_shot = false

# Main audio functions
func start_running():
	if is_running:
		return
	
	is_running = true
	_play_run_sound()
	footstep_timer.start()

func stop_running():
	if not is_running:
		return
	
	is_running = false
	footstep_timer.stop()
	if run_player.is_playing():
		run_player.stop()

func play_jump():
	if jump_player and not jump_sounds.is_empty():
		_play_random_sound(jump_player, jump_sounds)

func play_dash():
	if dash_player and not dash_sounds.is_empty():
		_play_random_sound(dash_player, dash_sounds)

# Internal functions
func _on_footstep_timer_timeout():
	if is_running:
		_play_run_sound()

func _play_run_sound():
	if run_player and not run_sounds.is_empty():
		_play_random_sound(run_player, run_sounds)

func _play_random_sound(player: AudioStreamPlayer2D, sound_array: Array[AudioStream]):
	if not player or sound_array.is_empty():
		return
	
	var random_sound: AudioStream
	if sound_array.size() == 1:
		random_sound = sound_array[0]
	else:
		random_sound = sound_array[randi() % sound_array.size()]
	
	if not random_sound:
		return
	
	if player.is_playing():
		player.stop()
	
	player.stream = random_sound
	player.play()

# Utility functions
func stop_all_sounds():
	stop_running()
	if jump_player and jump_player.is_playing():
		jump_player.stop()
	if dash_player and dash_player.is_playing():
		dash_player.stop()

func set_running_interval(interval: float):
	running_interval = max(0.1, interval)
	footstep_timer.wait_time = running_interval
