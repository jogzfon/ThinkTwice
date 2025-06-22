# Simple example showing how to use the fixed replay system
extends Node2D

@onready var replay_manager = $ReplayManager
@onready var player = $Player  # Your player node
@onready var ui_label = $UI/Label  # Optional status label

func _ready():
	# Make sure player is in the "player" group for auto-detection
	if player:
		player.add_to_group("player")
	
	# Or manually set the player reference
	# replay_manager.set_player_reference(player)
	
	# Connect to replay signals
	replay_manager.recording_started.connect(_on_recording_started)
	replay_manager.recording_stopped.connect(_on_recording_stopped)
	replay_manager.playback_started.connect(_on_playback_started)
	replay_manager.playback_finished.connect(_on_playback_finished)
	replay_manager.replay_saved.connect(_on_replay_saved)

func _input(event):
	# Simple controls for testing
	if event.is_action_pressed("record"):  # Enter key
		toggle_recording()
	elif event.is_action_pressed("save"):  # Space key
		save_current_replay()
	elif event.is_action_pressed("replay"):  # Escape key
		play_last_replay()

func toggle_recording():
	if replay_manager.is_recording:
		replay_manager.stop_recording()
	else:
		replay_manager.start_recording()

func save_current_replay():
	if replay_manager.replay_frames.size() > 0:
		var filename = "test_replay_" + str(Time.get_unix_time_from_system()) + ".json"
		replay_manager.save_replay(filename)
		
		if ui_label:
			ui_label.text = "RECORDING SAVED"
			ui_label.modulate = Color.GREEN
	else:
		print("No replay data to save!")

func play_last_replay():
	var available_replays = replay_manager.get_available_replays()
	if available_replays.size() > 0:
		var latest_replay = available_replays[-1]
		var full_path = replay_manager.replay_folder + latest_replay
		if replay_manager.load_replay(full_path):
			replay_manager.start_playback()
			print("Playing: ", latest_replay)
		else:
			print("Failed to load replay")
	else:
		print("No replays found!")

# Signal handlers
func _on_recording_started():
	print("Recording started!")
	if ui_label:
		ui_label.text = "RECORDING..."
		ui_label.modulate = Color.RED

func _on_recording_stopped(replay_data):
	print("Recording stopped. Frames: ", replay_data.size())
	if ui_label:
		ui_label.text = "Stopped - Frames: " + str(replay_data.size())
		ui_label.modulate = Color.WHITE

func _on_playback_started():
	print("Playback started!")
	if ui_label:
		ui_label.text = "PLAYING REPLAY..."
		ui_label.modulate = Color.GREEN

func _on_playback_finished():
	print("Playback finished!")
	if ui_label:
		ui_label.text = "Replay finished"
		ui_label.modulate = Color.WHITE

func _on_replay_saved(file_path):
	print("Replay saved: ", file_path)
