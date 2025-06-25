# Complete example showing how to use the enhanced replay system
extends Node2D
class_name GameManager

@export_category("Managers")
@export var replay_manager: PlayerReplayManager
@export var audio_manager: AudioManager

@export_category("Characters")
@export var player: Node2D  # Your player node
@export var ghost: Node2D  # Your player node

@export_category("UI")
@export var ui_label: Label  # Optional status label
@export var timer: Timer # Timer for UI messages
@export var win_loose_canvas: CanvasLayer

@export_category("Time Reversal")
@export var reverse_time_effect: CanvasLayer
@export var reverse_timer: Timer
@export var reverse_timer_label: Label
@export var reverse_max_time:int = 3

@export_category("Environment Levels")
@export var level_holder: Node2D
@export var environments: Array[PackedScene]
@export var respawn_point: Node2D
var prev_level: Node2D
var current_level: Node2D

@export_category("Controls")
@export var time_key_controls: bool = false
var is_traversing_time:bool = false

@export var current_level_completed = 1

func _ready():
	# Make sure player is in the "player" group for auto-detection
	if player:
		player.add_to_group("player")
	
	# Connect to replay signals
	replay_manager.recording_started.connect(_on_recording_started)
	replay_manager.recording_stopped.connect(_on_recording_stopped)
	replay_manager.playback_started.connect(_on_playback_started)
	replay_manager.playback_stopped.connect(_on_playback_stopped)
	replay_manager.playback_paused.connect(_on_playback_paused)
	replay_manager.playback_resumed.connect(_on_playback_resumed)
	replay_manager.playback_position_changed.connect(_on_playback_position_changed)
	
	reverse_time_effect.hide()
	# Connect timer if available
	if timer:
		timer.timeout.connect(_on_timer_timeout)
	
	# Update UI
	_update_ui_status()
	
	load_levels(current_level_completed)

func _process(delta: float) -> void:
	update_traversal_label()
	switch_levels()
	is_player_dead()

func is_player_dead():
	if player.is_dead and respawn_point:
		player.global_position = respawn_point.global_position
	
		if is_traversing_time:
			toggle_playback()
			reverse_time_effect.hide()
		
		audio_manager.stop_clock()
		is_traversing_time = false
		player.is_dead = false
		
func load_levels(level: int):
	if level == 0:
		current_level = environments[level].instantiate()
		
		current_level.is_past = false
		
		respawn_point = current_level.respawn_point
		level_holder.add_child(current_level)
	else:
		prev_level = environments[level-1].instantiate()
		current_level = environments[level].instantiate()
		
		prev_level.is_past = true
		current_level.is_past = false
		
		respawn_point = current_level.respawn_point
		
		level_holder.add_child(prev_level)
		level_holder.add_child(current_level)
	
func switch_levels():
	if is_traversing_time:
		current_level.is_past = true
		prev_level.is_past = false
	else:
		current_level.is_past = false
		prev_level.is_past = true

func start_time_traversal():
	reverse_timer.wait_time = reverse_max_time
	reverse_timer.start()
	
func update_traversal_label():
	if reverse_timer_label:
		if is_traversing_time:
			reverse_timer_label.text = str(int(reverse_timer.time_left)+1)
		else:
			reverse_timer_label.text = "0"

func _input(event):
	if ghost and player:
		if Input.is_action_just_pressed("blink") and player.in_teleport_zone:
			traverse_time()
	
	if time_key_controls:
		if event.is_action_pressed("record"):
			toggle_recording()
		elif event.is_action_pressed("save_replay"):
			save_current_replay()
		elif event.is_action_pressed("play_pause_replay"):
			toggle_playback()
		elif event.is_action_pressed("stop_replay"):
			stop_playback()
		elif event.is_action_pressed("speed_up"):
			speed_up_playback()
		elif event.is_action_pressed("speed_down"):
			speed_down_playback()
		elif event.is_action_pressed("step_forward"):
			step_forward()
		elif event.is_action_pressed("step_back"):
			step_backward()
		elif event.is_action_pressed("loop_toggle"):
			toggle_loop()
		elif event.is_action_pressed("restart_playback"):
			restart_playback()

func traverse_time():
	if not is_traversing_time and current_level_completed > 0:
		player.global_position = ghost.global_position
		if replay_manager.is_playing:
			toggle_playback()
			start_time_traversal()
		reverse_time_effect.show()
		is_traversing_time = true
		audio_manager.play_clock()

func toggle_recording():
	"""Toggle recording on/off using proper manager functions"""
	if replay_manager.is_recording:
		replay_manager.stop_recording()
		_show_message("Recording stopped")
	else:
		replay_manager.start_recording()
		_show_message("Recording started")

func toggle_playback():
	"""Smart playback toggle using the manager's toggle function"""
	if replay_manager.previous_frames.size() == 0:
		_show_message("No replay available!", Color.RED)
		return
	
	# Use the manager's built-in toggle function
	replay_manager.toggle_playback()
	
	# Update message based on current state
	if replay_manager.is_playing:
		if replay_manager.is_playback_paused:
			_show_message("Playback resumed")
		else:
			_show_message("Playback started")
	else:
		_show_message("Playback paused")

func stop_playback():
	"""Stop playback completely"""
	if replay_manager.is_playing:
		replay_manager.stop_playback()
		_show_message("Playback stopped")
	else:
		_show_message("No playback to stop", Color.YELLOW)

func restart_playback():
	"""Restart playback from the beginning"""
	if replay_manager.previous_frames.size() == 0:
		_show_message("No replay available!", Color.RED)
		return
	
	replay_manager.stop_playback()
	replay_manager.start_playback()
	_show_message("Playback restarted")

func speed_up_playback():
	"""Increase playback speed using manager's function"""
	var old_speed = replay_manager.playback_speed
	var new_speed = min(old_speed * 2.0, 6.0)  # Cap at 6x speed
	replay_manager.set_playback_speed(new_speed)
	_show_message("Speed: %.1fx" % replay_manager.playback_speed)

func speed_down_playback():
	"""Decrease playback speed using manager's function"""
	var old_speed = replay_manager.playback_speed
	var new_speed = max(old_speed / 2.0, 0.2)  # Minimum 0.2x speed
	replay_manager.set_playback_speed(new_speed)
	_show_message("Speed: %.1fx" % replay_manager.playback_speed)

func step_forward():
	"""Step forward one frame"""
	if replay_manager.previous_frames.size() == 0:
		_show_message("No replay available!", Color.RED)
		return
	
	# Ensure playback is active but paused for stepping
	if not replay_manager.is_playing:
		replay_manager.start_playback()
	
	replay_manager.step_forward()
	var progress = replay_manager.get_playback_progress()
	_show_message("Step Forward - Progress: %d%%" % (progress * 100))

func step_backward():
	"""Step backward one frame"""
	if replay_manager.previous_frames.size() == 0:
		_show_message("No replay available!", Color.RED)
		return
	
	# Ensure playback is active but paused for stepping
	if not replay_manager.is_playing:
		replay_manager.start_playback()
	
	replay_manager.step_backward()
	var progress = replay_manager.get_playback_progress()
	_show_message("Step Back - Progress: %d%%" % (progress * 100))

func toggle_loop():
	"""Toggle loop mode using manager's function"""
	replay_manager.set_loop_enabled(!replay_manager.loop_playback)
	_show_message("Loop: %s" % ("ON" if replay_manager.loop_playback else "OFF"))

func save_current_replay():
	"""Save current recording using manager's function"""
	if replay_manager.save_current_recording():
		_show_message("Replay saved!")
	else:
		_show_message("No recording to save!", Color.RED)

func clear_current_recording():
	"""Clear current recording"""
	replay_manager.clear_current_recording()
	_show_message("Current recording cleared!")

func set_playback_position_percent(percent: float):
	"""Set playback position by percentage (0-100)"""
	if replay_manager.previous_frames.size() == 0:
		_show_message("No replay available!", Color.RED)
		return
	
	var progress = clampf(percent / 100.0, 0.0, 1.0)
	replay_manager.set_playback_position(progress)
	_show_message("Jumped to %d%%" % percent)

func _show_message(text: String, color: Color = Color.WHITE, duration: float = 2.0):
	"""Display a temporary message in the UI"""
	if ui_label:
		ui_label.text = text
		ui_label.modulate = color
		if timer:
			timer.start(duration)

func _on_timer_timeout():
	"""Reset UI to status display after message timeout"""
	if ui_label:
		_update_ui_status()

func _update_ui_status():
	"""Update UI with current replay manager status"""
	if not ui_label:
		return
	
	var stats = replay_manager.get_stats()
	var status = []
	
	# Recording status
	if stats.recording:
		status.append("[RECORDING]")
		status.append("Frames: %d" % stats.current_frames)
		status.append("Time: %.1fs" % stats.recording_duration)
	
	# Playback status
	if stats.playing:
		if stats.paused:
			status.append("[PAUSED]")
		else:
			status.append("[PLAYING]")
		status.append("Speed: %.1fx" % stats.speed)
		status.append("Progress: %d%%" % (stats.progress * 100))
		status.append("Loop: %s" % ("ON" if replay_manager.loop_playback else "OFF"))
	
	# Idle status
	if not stats.recording and not stats.playing:
		if stats.previous_frames > 0:
			status.append("[READY]")
			status.append("Last replay: %.1fs" % stats.playback_duration)
			status.append("Frames: %d" % stats.previous_frames)
		else:
			status.append("[NO REPLAYS]")
			status.append("Press Record to start")
	
	# Set appropriate color based on state
	if stats.recording:
		ui_label.modulate = Color.RED
	elif stats.playing:
		if stats.paused:
			ui_label.modulate = Color.ORANGE
		else:
			ui_label.modulate = Color.GREEN
	else:
		if stats.previous_frames > 0:
			ui_label.modulate = Color.WHITE
		else:
			ui_label.modulate = Color.GRAY
	
	ui_label.text = "\n".join(status)

# Signal handlers - These provide feedback when manager state changes
func _on_recording_started():
	print("Recording started!")
	_update_ui_status()

func _on_recording_stopped():
	print("Recording stopped. Frames: ", replay_manager.current_frames.size())
	_update_ui_status()

func _on_playback_started():
	print("Playback started!")
	_update_ui_status()

func _on_playback_stopped():
	print("Playback finished!")
	_update_ui_status()

func _on_playback_paused():
	print("Playback paused at frame ", replay_manager.playback_index)
	_update_ui_status()

func _on_playback_resumed():
	print("Playback resumed from frame ", replay_manager.playback_index)
	_update_ui_status()

func _on_playback_position_changed(progress: float):
	# This updates frequently during playback, so we only update UI if paused
	if replay_manager.is_playback_paused:
		_update_ui_status()

# Debug and utility functions
func print_replay_stats():
	"""Print detailed replay statistics"""
	var stats = replay_manager.get_stats()
	print("=== Replay Stats ===")
	for key in stats:
		print("%s: %s" % [key, stats[key]])
	print("==================")

func get_replay_info() -> Dictionary:
	"""Get comprehensive replay information"""
	return replay_manager.get_stats()

func set_ghost_appearance(opacity: float, color: Color = Color.CYAN):
	"""Customize ghost appearance"""
	replay_manager.set_ghost_opacity(opacity)
	# Note: Color customization would need to be added to PlayerReplayManager

func jump_to_time(time_seconds: float):
	"""Jump to a specific time in the replay"""
	if replay_manager.previous_frames.size() == 0:
		_show_message("No replay available!", Color.RED)
		return
	
	var duration = replay_manager.get_playback_duration()
	if time_seconds > duration:
		_show_message("Time exceeds replay duration!", Color.RED)
		return
	
	var progress = time_seconds / duration
	replay_manager.set_playback_position(progress)
	_show_message("Jumped to %.1fs" % time_seconds)


func _on_reverse_time_timer_timeout() -> void:
	if is_traversing_time:
		toggle_playback()
		reverse_time_effect.hide()
		is_traversing_time = false
