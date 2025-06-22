extends Node2D

# Replay system for recording and playing back player actions
class_name ReplayManager

# Recording settings
@export var record_fps: int = 60  # How many frames per second to record
@export var max_recording_time: float = 300.0  # 5 minutes max
@export var auto_start_recording: bool = true
@export var save_replay_on_level_complete: bool = true

# File paths
@export var replay_folder: String = "user://replays/"
@export var replay_file_prefix: String = "replay_"

# Replay data structure
class ReplayFrame:
	var timestamp: float
	var position: Vector2
	var velocity: Vector2
	var inputs: Dictionary
	var animation_state: String
	var facing_right: bool
	var custom_data: Dictionary = {}
	
	func _init(time: float, pos: Vector2, vel: Vector2, input_data: Dictionary, anim: String, facing: bool, extra: Dictionary = {}):
		timestamp = time
		position = pos
		velocity = vel
		inputs = input_data.duplicate()
		animation_state = anim
		facing_right = facing
		custom_data = extra.duplicate()

# Recording state
var is_recording: bool = false
var is_playing_back: bool = false
var replay_frames: Array[ReplayFrame] = []
var current_playback_index: int = 0
var recording_start_time: float = 0.0
var playback_start_time: float = 0.0

# Target references
var player: CharacterBody2D = null
var original_player_position: Vector2
var replay_ghost: Node2D = null

# Input actions to track - these are common Godot actions
var tracked_inputs: Array[String] = ["ui_left", "ui_right", "ui_up", "ui_down", "ui_accept"]

# Signals
signal recording_started
signal recording_stopped(replay_data: Array)
signal playback_started
signal playback_finished
signal replay_saved(file_path: String)

func _ready():
	# Create replay folder if it doesn't exist
	if not DirAccess.dir_exists_absolute(replay_folder):
		DirAccess.open("user://").make_dir_recursive(replay_folder)
	
	# Find player automatically (with delay to ensure scene is loaded)
	call_deferred("find_player")

func _process(delta):
	if is_recording and player:
		record_frame()
	elif is_playing_back:
		playback_frame(delta)

func find_player():
	# Wait a frame to ensure scene is fully loaded
	await get_tree().process_frame
	
	# Try to find player in scene using multiple methods
	# Method 1: Try "player" group
	var players_in_group = get_tree().get_nodes_in_group("player")
	if players_in_group.size() > 0:
		player = players_in_group[0]
		print("ReplayManager: Found player in 'player' group: ", player.name)
	
	# Method 2: Try "players" group (plural)
	if not player:
		players_in_group = get_tree().get_nodes_in_group("players")
		if players_in_group.size() > 0:
			player = players_in_group[0]
			print("ReplayManager: Found player in 'players' group: ", player.name)
	
	# Method 3: Search by common names in current scene
	if not player:
		var potential_names = ["Player", "player", "PlayerCharacter", "Character", "MainCharacter"]
		var current_scene = get_tree().current_scene
		
		for name in potential_names:
			var found = current_scene.find_child(name, true, false)
			if found and found is CharacterBody2D:
				player = found
				print("ReplayManager: Found player by name: ", player.name)
				break
	
	# Method 4: Search for any CharacterBody2D in scene
	if not player:
		var all_nodes = get_all_children(get_tree().current_scene)
		for node in all_nodes:
			if node is CharacterBody2D:
				player = node
				print("ReplayManager: Using first CharacterBody2D found: ", player.name)
				break
	
	if player:
		original_player_position = player.global_position
		print("ReplayManager: Player setup complete at position: ", original_player_position)
		
		# Auto-detect available input actions from InputMap
		detect_input_actions()
		
		if auto_start_recording:
			start_recording()
	else:
		push_warning("ReplayManager: Player not found! Please set player reference manually using set_player_reference()")

func get_all_children(node: Node) -> Array:
	var children = []
	children.append(node)
	for child in node.get_children():
		children.append_array(get_all_children(child))
	return children

func detect_input_actions():
	# Get all input actions and filter for likely movement actions
	var all_actions = InputMap.get_actions()
	tracked_inputs.clear()
	
	for action in all_actions:
		var action_str = str(action)
		# Include common movement and action inputs
		if (action_str.contains("left") or action_str.contains("right") or 
			action_str.contains("up") or action_str.contains("down") or
			action_str.contains("jump") or action_str.contains("dash") or
			action_str.contains("move") or action_str.begins_with("ui_")):
			tracked_inputs.append(action_str)
	
	print("ReplayManager: Tracking inputs: ", tracked_inputs)

# Recording functions
func start_recording():
	if not player:
		push_error("ReplayManager: Cannot start recording without player reference!")
		return
	
	is_recording = true
	is_playing_back = false
	replay_frames.clear()
	recording_start_time = Time.get_ticks_msec() / 1000.0
	original_player_position = player.global_position
	
	print("ReplayManager: Started recording at position: ", original_player_position)
	recording_started.emit()

func stop_recording():
	if not is_recording:
		return
	
	is_recording = false
	print("ReplayManager: Stopped recording. Frames recorded: ", replay_frames.size())
	recording_stopped.emit(replay_frames)

func record_frame():
	if not player or not is_instance_valid(player):
		print("ERROR: Player reference invalid during recording!")
		stop_recording()
		return
		
	if replay_frames.size() >= max_recording_time * record_fps:
		print("WARNING: Max recording time reached!")
		stop_recording()
		return
	
	var current_time = (Time.get_ticks_msec() / 1000.0) - recording_start_time
	
	# Capture input state
	var input_data = {}
	for action in tracked_inputs:
		if InputMap.has_action(action):
			input_data[str(action) + "_pressed"] = Input.is_action_pressed(action)
			input_data[str(action) + "_just_pressed"] = Input.is_action_just_pressed(action)
			input_data[str(action) + "_just_released"] = Input.is_action_just_released(action)
	
	# Get animation state
	var anim_state = "idle"
	var anim_player = find_animation_player(player)
	if anim_player and anim_player.current_animation != "":
		anim_state = anim_player.current_animation
	elif player.has_method("get_current_animation"):
		anim_state = player.get_current_animation()
	
	# Get facing direction
	var facing_right = true
	var sprite = find_sprite(player)
	if sprite and "flip_h" in sprite:
		facing_right = not sprite.flip_h
	elif player.has_method("is_facing_right"):
		facing_right = player.is_facing_right()
	
	# Get velocity safely
	var current_velocity = Vector2.ZERO
	if "velocity" in player:
		current_velocity = player.velocity
	elif player.has_method("get_velocity"):
		current_velocity = player.get_velocity()
	
	# Create frame
	var frame = ReplayFrame.new(
		current_time,
		player.global_position,
		current_velocity,
		input_data,
		anim_state,
		facing_right,
		{}
	)
	
	replay_frames.append(frame)

func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var result = find_animation_player(child)
		if result:
			return result
	
	return null

func find_sprite(node: Node) -> Node:
	if node is Sprite2D:
		return node
		
	for child in node.get_children():
		if child is Sprite2D:
			return child
		var result = find_sprite(child)
		if result:
			return result
	
	return null

# Playback functions
func start_playback(replay_data: Array[ReplayFrame] = []):
	if replay_data.size() > 0:
		replay_frames = replay_data
	
	if replay_frames.size() == 0:
		push_warning("ReplayManager: No replay data to play back!")
		return
	
	is_playing_back = true
	is_recording = false
	current_playback_index = 0
	playback_start_time = Time.get_ticks_msec() / 1000.0
	
	setup_replay_ghost()
	
	print("ReplayManager: Started playback with ", replay_frames.size(), " frames")
	playback_started.emit()

func stop_playback():
	if not is_playing_back:
		return
	
	is_playing_back = false
	cleanup_replay_ghost()
	
	print("ReplayManager: Stopped playback")
	playback_finished.emit()

func playback_frame(delta):
	if current_playback_index >= replay_frames.size():
		stop_playback()
		return
	
	var current_time = (Time.get_ticks_msec() / 1000.0) - playback_start_time
	
	# Find the appropriate frame for current time
	while (current_playback_index < replay_frames.size() and 
		   replay_frames[current_playback_index].timestamp <= current_time):
		
		var target_frame = replay_frames[current_playback_index]
		apply_frame_to_ghost(target_frame)
		current_playback_index += 1

func setup_replay_ghost():
	if not player:
		return
	
	# Create a simple ghost representation
	replay_ghost = Node2D.new()
	replay_ghost.name = "ReplayGhost"
	get_tree().current_scene.add_child(replay_ghost)
	
	# Copy the player's sprite
	var player_sprite = find_sprite(player)
	if player_sprite:
		var ghost_sprite = player_sprite.duplicate()
		replay_ghost.add_child(ghost_sprite)
		ghost_sprite.modulate = Color(0, 1, 1, 0.7)  # Cyan semi-transparent
		ghost_sprite.z_index = player.z_index - 1
	else:
		# Create a simple colored rectangle as fallback
		var ghost_sprite = ColorRect.new()
		ghost_sprite.size = Vector2(32, 32)
		ghost_sprite.color = Color(0, 1, 1, 0.7)
		ghost_sprite.position = Vector2(-16, -16)  # Center it
		replay_ghost.add_child(ghost_sprite)
	
	# Set initial position
	if replay_frames.size() > 0:
		replay_ghost.global_position = replay_frames[0].position

func apply_frame_to_ghost(frame: ReplayFrame):
	if not replay_ghost or not is_instance_valid(replay_ghost):
		return
	
	# Update position
	replay_ghost.global_position = frame.position
	
	# Update facing direction
	var ghost_sprite = find_sprite(replay_ghost)
	if ghost_sprite and "flip_h" in ghost_sprite:
		ghost_sprite.flip_h = not frame.facing_right
	
	# Update animation if available
	var ghost_anim = find_animation_player(replay_ghost)
	if ghost_anim and ghost_anim.has_animation(frame.animation_state):
		if ghost_anim.current_animation != frame.animation_state:
			ghost_anim.play(frame.animation_state)

func cleanup_replay_ghost():
	if replay_ghost and is_instance_valid(replay_ghost):
		replay_ghost.queue_free()
		replay_ghost = null

# File operations
func save_replay(filename: String = ""):
	if replay_frames.size() == 0:
		print("ERROR: No replay data to save!")
		return ""
	
	# Ensure replay folder exists
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(replay_folder.trim_prefix("user://")):
		var result = dir.make_dir_recursive(replay_folder.trim_prefix("user://"))
		print("Created replay folder, result: ", result)
	
	if filename.is_empty():
		var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		filename = replay_file_prefix + timestamp + ".json"
	
	var file_path = replay_folder + filename
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if not file:
		print("ERROR: Failed to open file for writing: ", file_path)
		return ""
	
	var replay_data = {
		"version": "1.0",
		"level_name": get_tree().current_scene.scene_file_path,
		"player_start_position": {"x": original_player_position.x, "y": original_player_position.y},
		"total_frames": replay_frames.size(),
		"frames": []
	}
	
	for frame in replay_frames:
		var frame_data = {
			"timestamp": frame.timestamp,
			"position": {"x": frame.position.x, "y": frame.position.y},
			"velocity": {"x": frame.velocity.x, "y": frame.velocity.y},
			"inputs": frame.inputs,
			"animation_state": frame.animation_state,
			"facing_right": frame.facing_right,
			"custom_data": frame.custom_data
		}
		replay_data.frames.append(frame_data)
	
	var json_string = JSON.stringify(replay_data)
	file.store_string(json_string)
	file.close()
	
	print("SUCCESS: Replay saved to ", file_path)
	replay_saved.emit(file_path)
	return file_path

func load_replay(file_path: String) -> bool:
	if not FileAccess.file_exists(file_path):
		push_error("ReplayManager: Replay file does not exist: " + file_path)
		return false
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("ReplayManager: Failed to open replay file: " + file_path)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("ReplayManager: Failed to parse replay file: " + file_path)
		return false
	
	var replay_data = json.data
	replay_frames.clear()
	
	for frame_data in replay_data.frames:
		var position = Vector2(frame_data.position.x, frame_data.position.y)
		var velocity = Vector2(frame_data.velocity.x, frame_data.velocity.y)
		
		var frame = ReplayFrame.new(
			frame_data.timestamp,
			position,
			velocity,
			frame_data.inputs,
			frame_data.animation_state,
			frame_data.facing_right,
			frame_data.get("custom_data", {})
		)
		replay_frames.append(frame)
	
	print("ReplayManager: Loaded replay with ", replay_frames.size(), " frames")
	return true

func get_available_replays() -> Array:
	var replays = []
	var dir = DirAccess.open(replay_folder)
	
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if file_name.ends_with(".json"):
				replays.append(file_name)
			file_name = dir.get_next()
	
	return replays

# Public API functions
func set_player_reference(player_node: CharacterBody2D):
	player = player_node
	if player:
		original_player_position = player.global_position
		detect_input_actions()
		print("ReplayManager: Player reference set manually to ", player.name)
		
		if auto_start_recording and not is_recording:
			start_recording()

func get_recording_duration() -> float:
	if replay_frames.size() == 0:
		return 0.0
	return replay_frames[-1].timestamp

func get_playback_progress() -> float:
	if not is_playing_back or replay_frames.size() == 0:
		return 0.0
	return float(current_playback_index) / float(replay_frames.size())
