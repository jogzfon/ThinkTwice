extends Node2D
class_name PlayerReplayManager

# Recording settings
@export var record_fps: int = 60
@export var max_recording_time: float = 300.0
@export var auto_start_recording: bool = true

# Ghost settings
@export var ghost_y_offset: float = -50.0
@export var ghost_opacity: float = 0.7
@export var ghost_color: Color = Color(0.2, 0.8, 1.0, 0.7)

# Smoothing settings
@export var position_smoothing: bool = true
@export var position_smoothing_speed: float = 15.0
@export var rotation_smoothing: bool = true
@export var rotation_smoothing_speed: float = 10.0
@export var animation_transition_smoothing: bool = true

# File settings
@export var replay_folder: String = "user://replays/"

# References - These should be assigned in the editor
@export var game_manager: GameManager = null
@export var player: CharacterBody2D = null
@export var ghost_player: Node2D = null


# Enhanced replay frame structure with rotation and scale
class ReplayFrame:
	var time: float
	var pos: Vector2
	var vel: Vector2
	var rotation: float
	var scale: Vector2
	var inputs: Dictionary
	var facing_right: bool
	var animation_name: String = ""
	var animation_position: float = 0.0
	var animation_speed: float = 1.0
	var animation_playing: bool = false
	
	func _init(t: float, p: Vector2, v: Vector2, rot: float, sc: Vector2, inp: Dictionary, face: bool, anim: String = "", anim_pos: float = 0.0, anim_speed: float = 1.0, anim_playing: bool = false):
		time = t
		pos = p
		vel = v
		rotation = rot
		scale = sc
		inputs = inp.duplicate()
		facing_right = face
		animation_name = anim
		animation_position = anim_pos
		animation_speed = anim_speed
		animation_playing = anim_playing

# State variables
var is_recording: bool = false
var is_playing: bool = false
var is_playback_paused: bool = false
var current_frames: Array[ReplayFrame] = []
var previous_frames: Array[ReplayFrame] = []
var playback_index: int = 0
var record_start_time: float = 0.0
var playback_start_time: float = 0.0
var playback_speed: float = 1.0
var loop_playback: bool = true

# Smoothing variables
var ghost_target_position: Vector2 = Vector2.ZERO
var ghost_target_rotation: float = 0.0
var ghost_target_scale: Vector2 = Vector2.ONE
var last_frame_time: float = 0.0
var interpolation_alpha: float = 0.0

# References
var ghost_sprite: Sprite2D
var ghost_animated_sprite: AnimatedSprite2D

var player_animation_player: AnimationPlayer = null
var ghost_animation_player: AnimationPlayer = null

# Input tracking
var tracked_inputs: PackedStringArray = []

# Animation state tracking
var current_ghost_animation: String = ""
var animation_blend_time: float = 0.1

# Signals
signal recording_started
signal recording_stopped
signal playback_started
signal playback_stopped
signal playback_paused
signal playback_resumed
signal playback_position_changed(progress: float)

func _ready():
	_ensure_folder_exists()
	_setup_ghost_color()
	
	# Auto-setup if player is assigned
	if player:
		_setup_system()
		player_animation_player = player.player_animation
		if ghost_player:
			game_manager.ghost = ghost_player
			ghost_animation_player = ghost_player.ghost_animation

func _process(delta: float):
	if is_playing and ghost_player and not is_playback_paused:
		_smooth_ghost_movement(delta)

func _physics_process(_delta: float):
	if is_recording and player:
		_record_frame()
	
	if is_playing and ghost_player and not is_playback_paused:
		_update_playback()

# Setup functions
func _setup_system():
	if not player:
		push_error("PlayerReplayManager: Player not assigned!")
		return
	
	if not ghost_player:
		push_error("PlayerReplayManager: Ghost player not assigned!")
		return
	
	_detect_inputs()
	_setup_ghost()
	load_from_file()
	
	if auto_start_recording:
		start_recording()

func _ensure_folder_exists():
	if not DirAccess.dir_exists_absolute(replay_folder):
		DirAccess.open("user://").make_dir_recursive("replays")

func _setup_ghost_color():
	ghost_color.a = ghost_opacity

func _detect_inputs():
	tracked_inputs.clear()
	for action in InputMap.get_actions():
		var action_str = str(action)
		if (action_str.contains("left") or action_str.contains("right") or 
			action_str.contains("up") or action_str.contains("down") or
			action_str.contains("jump") or action_str.contains("move") or
			action_str.contains("ui_")):
			tracked_inputs.append(action_str)

func _setup_ghost():
	if not ghost_player:
		push_error("PlayerReplayManager: Ghost player not assigned!")
		return
	
	# Find sprite components in ghost
	ghost_sprite = _find_sprite(ghost_player)
	ghost_animated_sprite = _find_animated_sprite(ghost_player)
	
	# Set up ghost appearance
	if ghost_sprite:
		ghost_sprite.modulate = ghost_color
		ghost_sprite.z_index = (player.z_index if player else 0) - 1
	
	if ghost_animated_sprite:
		ghost_animated_sprite.modulate = ghost_color
		ghost_animated_sprite.z_index = (player.z_index if player else 0) - 1
	
	# Initially hide ghost
	ghost_player.visible = false
	
	# Initialize smoothing targets
	ghost_target_position = ghost_player.global_position
	ghost_target_rotation = ghost_player.rotation
	ghost_target_scale = ghost_player.scale
	
	# Disable ghost physics/input if it has any
	if ghost_player.has_method("set_physics_process"):
		ghost_player.set_physics_process(false)
	if ghost_player.has_method("set_process_input"):
		ghost_player.set_process_input(false)

func _find_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node
	for child in node.get_children():
		var result = _find_sprite(child)
		if result:
			return result
	return null

func _find_animated_sprite(node: Node) -> AnimatedSprite2D:
	if node is AnimatedSprite2D:
		return node
	for child in node.get_children():
		var result = _find_animated_sprite(child)
		if result:
			return result
	return null

# Smoothing function for ghost movement
func _smooth_ghost_movement(delta: float):
	if not ghost_player:
		return
	
	# Smooth position interpolation
	if position_smoothing:
		ghost_player.global_position = ghost_player.global_position.lerp(
			ghost_target_position, 
			position_smoothing_speed * delta
		)
	else:
		ghost_player.global_position = ghost_target_position
	
	# Smooth rotation interpolation
	if rotation_smoothing:
		ghost_player.rotation = lerp_angle(
			ghost_player.rotation, 
			ghost_target_rotation, 
			rotation_smoothing_speed * delta
		)
	else:
		ghost_player.rotation = ghost_target_rotation
	
	# Smooth scale interpolation
	ghost_player.scale = ghost_player.scale.lerp(
		ghost_target_scale, 
		position_smoothing_speed * delta
	)

# Recording functions
func start_recording():
	if not player:
		push_error("PlayerReplayManager: No player reference for recording!")
		return
	
	if not is_recording:
		is_recording = true
		current_frames.clear()
		record_start_time = Time.get_ticks_msec() / 1000.0
		print("Recording started")
		recording_started.emit()

func stop_recording():
	if is_recording:
		is_recording = false
		print("Recording stopped - ", current_frames.size(), " frames recorded")
		recording_stopped.emit()

func _record_frame():
	if current_frames.size() >= max_recording_time * record_fps:
		stop_recording()
		return
	
	var current_time = (Time.get_ticks_msec() / 1000.0) - record_start_time
	var inputs = _capture_inputs()
	var facing = _get_facing_direction()
	var velocity = player.velocity if "velocity" in player else Vector2.ZERO
	var rotation = player.rotation
	var scale = player.scale
	var animation_data = _get_current_animation_state()
	
	var frame = ReplayFrame.new(
		current_time, 
		player.global_position, 
		velocity,
		rotation,
		scale,
		inputs, 
		facing, 
		animation_data.name,
		animation_data.position,
		animation_data.speed,
		animation_data.playing
	)
	current_frames.append(frame)

func _capture_inputs() -> Dictionary:
	var inputs = {}
	for action in tracked_inputs:
		if InputMap.has_action(action):
			inputs[action] = Input.is_action_pressed(action)
	return inputs

func _get_facing_direction() -> bool:
	# Try AnimatedSprite2D first, then Sprite2D
	if ghost_animated_sprite:
		var player_animated_sprite = _find_animated_sprite(player)
		if player_animated_sprite:
			return not player_animated_sprite.flip_h
	
	var sprite = _find_sprite(player)
	if sprite:
		return not sprite.flip_h
	return true

func _get_current_animation_state() -> Dictionary:
	var animation_data = {
		"name": "",
		"position": 0.0,
		"speed": 1.0,
		"playing": false
	}
	
	# Check AnimationPlayer first
	if player_animation_player and player_animation_player.is_playing():
		animation_data.name = player_animation_player.current_animation
		animation_data.position = player_animation_player.current_animation_position
		animation_data.speed = player_animation_player.speed_scale
		animation_data.playing = true
	else:
		# Check AnimatedSprite2D
		var player_animated_sprite = _find_animated_sprite(player)
		if player_animated_sprite:
			animation_data.name = player_animated_sprite.animation
			animation_data.position = player_animated_sprite.frame_progress if player_animated_sprite.sprite_frames else 0.0
			animation_data.speed = player_animated_sprite.speed_scale
			animation_data.playing = player_animated_sprite.is_playing()
	
	return animation_data

# Playback functions
func start_playback():
	if previous_frames.is_empty():
		print("No previous frames to play back")
		return
		
	if not ghost_player:
		print("Ghost player not assigned!")
		return
	
	if not is_playing:
		is_playing = true
		is_playback_paused = false
		playback_index = 0
		playback_start_time = Time.get_ticks_msec() / 1000.0
		last_frame_time = 0.0
		ghost_player.visible = true
		
		# Initialize ghost position to first frame
		if not previous_frames.is_empty():
			var first_frame = previous_frames[0]
			ghost_target_position = Vector2(first_frame.pos.x, first_frame.pos.y + ghost_y_offset)
			ghost_target_rotation = first_frame.rotation
			ghost_target_scale = first_frame.scale
			ghost_player.global_position = ghost_target_position
			ghost_player.rotation = ghost_target_rotation
			ghost_player.scale = ghost_target_scale
		
		print("Playback started with ", previous_frames.size(), " frames")
		playback_started.emit()

func stop_playback():
	if is_playing:
		is_playing = false
		is_playback_paused = false
		if ghost_player:
			ghost_player.visible = false
		# Stop ghost animations
		if ghost_animation_player:
			ghost_animation_player.stop()
		if ghost_animated_sprite:
			ghost_animated_sprite.stop()
		print("Playback stopped")
		playback_stopped.emit()

func toggle_playback():
	if is_playing:
		if is_playback_paused:
			resume_playback()
		else:
			pause_playback()
	else:
		start_playback()

func pause_playback():
	if is_playing and not is_playback_paused:
		is_playback_paused = true
		# Pause ghost animations
		if ghost_animation_player and ghost_animation_player.is_playing():
			ghost_animation_player.pause()
		playback_paused.emit()

func resume_playback():
	if is_playing and is_playback_paused:
		is_playback_paused = false
		# Adjust start time to account for pause duration
		playback_start_time = Time.get_ticks_msec() / 1000.0 - (previous_frames[playback_index].time / playback_speed)
		playback_resumed.emit()

func _update_playback():
	if previous_frames.is_empty():
		return
	
	var current_time = (Time.get_ticks_msec() / 1000.0 - playback_start_time) * playback_speed
	
	# Find the current and next frames for interpolation
	var current_frame: ReplayFrame = null
	var next_frame: ReplayFrame = null
	
	# Find appropriate frames
	while playback_index < previous_frames.size() and previous_frames[playback_index].time <= current_time:
		playback_index += 1
	
	if playback_index >= previous_frames.size():
		if loop_playback:
			playback_index = 0
			playback_start_time = Time.get_ticks_msec() / 1000.0
			current_time = 0.0
		else:
			stop_playback()
		return
	
	# Get frames for interpolation
	if playback_index == 0:
		current_frame = previous_frames[0]
		next_frame = previous_frames[min(1, previous_frames.size() - 1)]
		interpolation_alpha = 0.0
	else:
		current_frame = previous_frames[playback_index - 1]
		next_frame = previous_frames[playback_index]
		
		# Calculate interpolation alpha
		var frame_duration = next_frame.time - current_frame.time
		if frame_duration > 0:
			interpolation_alpha = (current_time - current_frame.time) / frame_duration
			interpolation_alpha = clampf(interpolation_alpha, 0.0, 1.0)
		else:
			interpolation_alpha = 0.0
	
	_apply_interpolated_frame_to_ghost(current_frame, next_frame, interpolation_alpha)
	playback_position_changed.emit(get_playback_progress())

func _apply_interpolated_frame_to_ghost(current_frame: ReplayFrame, next_frame: ReplayFrame, alpha: float):
	if not ghost_player:
		return
	
	# Interpolate position
	var interpolated_pos = current_frame.pos.lerp(next_frame.pos, alpha)
	ghost_target_position = Vector2(interpolated_pos.x, interpolated_pos.y + ghost_y_offset)
	
	# Interpolate rotation
	ghost_target_rotation = lerp_angle(current_frame.rotation, next_frame.rotation, alpha)
	
	# Interpolate scale
	ghost_target_scale = current_frame.scale.lerp(next_frame.scale, alpha)
	
	# Set facing direction (use next frame's direction when alpha > 0.5)
	var use_next_facing = alpha > 0.5
	var facing = next_frame.facing_right if use_next_facing else current_frame.facing_right
	
	if ghost_sprite:
		ghost_sprite.flip_h = not facing
	
	if ghost_animated_sprite:
		ghost_animated_sprite.flip_h = not facing
	
	# Apply animation state (prefer next frame for smoother transitions)
	var animation_frame = next_frame if alpha > 0.3 else current_frame
	_apply_animation_state_to_ghost(animation_frame, alpha)

func _apply_animation_state_to_ghost(frame: ReplayFrame, blend_alpha: float = 1.0):
	# Apply AnimationPlayer state if available
	if ghost_animation_player and frame.animation_name != "":
		if ghost_animation_player.has_animation(frame.animation_name):
			# Smooth animation transitions
			if animation_transition_smoothing and current_ghost_animation != frame.animation_name:
				current_ghost_animation = frame.animation_name
				# Use crossfade if available
				if ghost_animation_player.has_method("play_with_capture"):
					ghost_animation_player.play_with_capture(frame.animation_name, animation_blend_time)
				else:
					ghost_animation_player.play(frame.animation_name)
			elif not ghost_animation_player.is_playing() or ghost_animation_player.current_animation != frame.animation_name:
				ghost_animation_player.play(frame.animation_name)
				current_ghost_animation = frame.animation_name
			
			# Set animation position and speed with smoothing
			ghost_animation_player.speed_scale = frame.animation_speed
			if frame.animation_playing:
				# Smooth seek to position
				var current_pos = ghost_animation_player.current_animation_position
				var target_pos = frame.animation_position
				var smooth_pos = lerp(current_pos, target_pos, blend_alpha * 0.5 + 0.5)
				ghost_animation_player.seek(smooth_pos, true)
			else:
				ghost_animation_player.pause()
				ghost_animation_player.seek(frame.animation_position, true)
	
	# Apply AnimatedSprite2D state if available
	if ghost_animated_sprite and frame.animation_name != "":
		if ghost_animated_sprite.sprite_frames and ghost_animated_sprite.sprite_frames.has_animation(frame.animation_name):
			# Smooth animation transitions
			if ghost_animated_sprite.animation != frame.animation_name:
				ghost_animated_sprite.animation = frame.animation_name
				current_ghost_animation = frame.animation_name
			
			# Set speed and playing state
			ghost_animated_sprite.speed_scale = frame.animation_speed
			
			if frame.animation_playing:
				if not ghost_animated_sprite.is_playing():
					ghost_animated_sprite.play()
				# Set frame based on position with smoothing
				var total_frames = ghost_animated_sprite.sprite_frames.get_frame_count(frame.animation_name)
				if total_frames > 0:
					var target_frame_index = int(frame.animation_position * total_frames) % total_frames
					# Smooth frame transitions for better visual flow
					if abs(ghost_animated_sprite.frame - target_frame_index) <= 1 or total_frames <= 2:
						ghost_animated_sprite.frame = target_frame_index
					else:
						# Gradual frame adjustment for smoother playback
						var frame_diff = target_frame_index - ghost_animated_sprite.frame
						if abs(frame_diff) > total_frames / 2:
							# Handle wrap-around
							ghost_animated_sprite.frame = target_frame_index
						else:
							ghost_animated_sprite.frame = ghost_animated_sprite.frame + sign(frame_diff)
			else:
				ghost_animated_sprite.stop()
				# Set frame for paused state
				var total_frames = ghost_animated_sprite.sprite_frames.get_frame_count(frame.animation_name)
				if total_frames > 0:
					var frame_index = int(frame.animation_position * total_frames) % total_frames
					ghost_animated_sprite.frame = frame_index

# Playback navigation
func step_forward():
	if not is_playing or previous_frames.is_empty():
		return
	
	pause_playback()
	playback_index = min(playback_index + 1, previous_frames.size() - 1)
	_apply_interpolated_frame_to_ghost(previous_frames[playback_index], previous_frames[playback_index], 1.0)
	playback_position_changed.emit(get_playback_progress())

func step_backward():
	if not is_playing or previous_frames.is_empty():
		return
	
	pause_playback()
	playback_index = max(playback_index - 1, 0)
	_apply_interpolated_frame_to_ghost(previous_frames[playback_index], previous_frames[playback_index], 1.0)
	playback_position_changed.emit(get_playback_progress())

func set_playback_position(progress: float):
	if not is_playing or previous_frames.is_empty():
		return
	
	progress = clampf(progress, 0.0, 1.0)
	playback_index = int(progress * (previous_frames.size() - 1))
	_apply_interpolated_frame_to_ghost(previous_frames[playback_index], previous_frames[playback_index], 1.0)
	
	# Adjust start time so playback continues from this position
	if not is_playback_paused:
		playback_start_time = Time.get_ticks_msec() / 1000.0 - (previous_frames[playback_index].time / playback_speed)
	
	playback_position_changed.emit(progress)

# Speed control
func set_playback_speed(speed: float):
	playback_speed = clampf(speed, 0.25, 6.0)
	if is_playing and playback_index < previous_frames.size():
		playback_start_time = Time.get_ticks_msec() / 1000.0 - (previous_frames[playback_index].time / playback_speed)

# Replay management
func save_current_recording():
	if current_frames.is_empty():
		print("No current recording to save")
		return false
	
	# Save current recording as previous frames
	previous_frames = current_frames.duplicate()
	current_frames.clear()
	_save_to_file()
	
	print("Recording saved with ", previous_frames.size(), " frames")
	return true

func clear_current_recording():
	current_frames.clear()
	if is_recording:
		stop_recording()

# File operations
func _save_to_file():
	var file_path = replay_folder + "replay_previous.json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("PlayerReplayManager: Failed to create save file: " + file_path)
		return
	
	var data = {
		"version": "3.0",  # Updated version for smoothing data
		"frames": []
	}
	
	for frame in previous_frames:
		data.frames.append({
			"time": frame.time,
			"pos": {"x": frame.pos.x, "y": frame.pos.y},
			"vel": {"x": frame.vel.x, "y": frame.vel.y},
			"rotation": frame.rotation,
			"scale": {"x": frame.scale.x, "y": frame.scale.y},
			"inputs": frame.inputs,
			"facing": frame.facing_right,
			"animation": frame.animation_name,
			"animation_position": frame.animation_position,
			"animation_speed": frame.animation_speed,
			"animation_playing": frame.animation_playing
		})
	
	file.store_string(JSON.stringify(data))
	file.close()

func load_from_file():
	var file_path = replay_folder + "replay_previous.json"
	if not FileAccess.file_exists(file_path):
		print("No previous replay file found")
		return
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("PlayerReplayManager: Failed to open replay file: " + file_path)
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		push_error("PlayerReplayManager: Failed to parse JSON: " + json.get_error_message())
		return
	
	var data = json.data
	if not data.has("frames"):
		push_error("PlayerReplayManager: Invalid replay file format")
		return
	
	previous_frames.clear()
	for frame_data in data.frames:
		var pos = Vector2(frame_data.pos.x, frame_data.pos.y)
		var vel = Vector2(frame_data.vel.x, frame_data.vel.y)
		var rotation = frame_data.get("rotation", 0.0)
		var scale = Vector2(
			frame_data.get("scale", {"x": 1.0, "y": 1.0}).get("x", 1.0),
			frame_data.get("scale", {"x": 1.0, "y": 1.0}).get("y", 1.0)
		)
		var animation = frame_data.get("animation", "")
		var animation_position = frame_data.get("animation_position", 0.0)
		var animation_speed = frame_data.get("animation_speed", 1.0)
		var animation_playing = frame_data.get("animation_playing", false)
		
		var frame = ReplayFrame.new(
			frame_data.time, 
			pos, 
			vel,
			rotation,
			scale,
			frame_data.inputs, 
			frame_data.facing, 
			animation,
			animation_position,
			animation_speed,
			animation_playing
		)
		previous_frames.append(frame)
	
	print("Loaded ", previous_frames.size(), " frames from file")

# Public API - Enhanced with smoothing controls
func set_player_and_ghost(player_node: CharacterBody2D, ghost_node: CharacterBody2D):
	player = player_node
	ghost_player = ghost_node
	_setup_system()

func set_ghost_offset(offset: float):
	ghost_y_offset = offset

func set_ghost_opacity(opacity: float):
	ghost_opacity = clampf(opacity, 0.0, 1.0)
	ghost_color.a = ghost_opacity
	_setup_ghost_color()
	
	if ghost_sprite:
		ghost_sprite.modulate = ghost_color
	if ghost_animated_sprite:
		ghost_animated_sprite.modulate = ghost_color

func set_loop_enabled(enabled: bool):
	loop_playback = enabled

func set_position_smoothing(enabled: bool, speed: float = 15.0):
	position_smoothing = enabled
	position_smoothing_speed = clampf(speed, 1.0, 50.0)

func set_rotation_smoothing(enabled: bool, speed: float = 10.0):
	rotation_smoothing = enabled
	rotation_smoothing_speed = clampf(speed, 1.0, 50.0)

func set_animation_smoothing(enabled: bool, blend_time: float = 0.1):
	animation_transition_smoothing = enabled
	animation_blend_time = clampf(blend_time, 0.0, 1.0)

# Status functions
func get_recording_duration() -> float:
	return current_frames[-1].time if not current_frames.is_empty() else 0.0

func get_playback_duration() -> float:
	return previous_frames[-1].time if not previous_frames.is_empty() else 0.0

func get_playback_progress() -> float:
	if not is_playing or previous_frames.is_empty():
		return 0.0
	return float(playback_index) / float(previous_frames.size() - 1)

func get_stats() -> Dictionary:
	return {
		"recording": is_recording,
		"playing": is_playing,
		"paused": is_playback_paused,
		"current_frames": current_frames.size(),
		"previous_frames": previous_frames.size(),
		"speed": playback_speed,
		"progress": get_playback_progress(),
		"recording_duration": get_recording_duration(),
		"playback_duration": get_playback_duration(),
		"has_player": player != null,
		"has_ghost": ghost_player != null,
		"position_smoothing": position_smoothing,
		"rotation_smoothing": rotation_smoothing,
		"animation_smoothing": animation_transition_smoothing,
		"interpolation_alpha": interpolation_alpha
	}

# Debug functions
func print_debug_info():
	print("=== PlayerReplayManager Debug Info ===")
	print("Player assigned: ", player != null)
	print("Ghost assigned: ", ghost_player != null)
	print("Is recording: ", is_recording)
	print("Is playing: ", is_playing)
	print("Current frames: ", current_frames.size())
	print("Previous frames: ", previous_frames.size())
	print("Tracked inputs: ", tracked_inputs)
	print("Player AnimationPlayer: ", player_animation_player != null)
	print("Ghost AnimationPlayer: ", ghost_animation_player != null)
	print("Position smoothing: ", position_smoothing, " (", position_smoothing_speed, ")")
	print("Rotation smoothing: ", rotation_smoothing, " (", rotation_smoothing_speed, ")")
	print("Animation smoothing: ", animation_transition_smoothing, " (", animation_blend_time, ")")
	print("Interpolation alpha: ", interpolation_alpha)
	print("=====================================")
