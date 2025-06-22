extends AnimationPlayer

# Animation state tracking
var current_state: String = ""
var previous_state: String = ""
var is_transitioning: bool = false

# Animation settings
@export var enable_animation_events: bool = true
@export var blend_time: float = 0.1

# Particle effects (optional - assign in inspector)
@export var dust_particles: GPUParticles2D
@export var jump_particles: GPUParticles2D
@export var land_particles: GPUParticles2D

# Sound effects (optional - assign in inspector)
@export var jump_sound: AudioStreamPlayer2D
@export var land_sound: AudioStreamPlayer2D
@export var step_sound: AudioStreamPlayer2D

# Parent and sprite references
var player: CharacterBody2D
var sprite: Sprite2D

func _ready():
	# Get parent player reference
	player = get_parent() as CharacterBody2D
	
	# Get sprite reference (assuming it's a sibling)
	sprite = get_parent().get_node("Player") as Sprite2D
	
	# Connect animation signals
	if enable_animation_events:
		animation_finished.connect(_on_animation_finished)
		animation_started.connect(_on_animation_started)
	
	# Check for required animations
	check_required_animations()
	
	# Start with idle animation
	play_animation("idle")

func check_required_animations():
	"""Check if required animations exist"""
	var required_animations = ["idle", "run", "jump", "fall"]
	
	for anim_name in required_animations:
		if not has_animation(anim_name):
			push_warning("Required animation '" + anim_name + "' not found in AnimationPlayer")

func play_animation(anim_name: String, force: bool = false, custom_blend: float = -1.0):
	"""Play an animation with state tracking and blending"""
	if current_state == anim_name and not force:
		return
	
	if not has_animation(anim_name):
		push_warning("Animation '" + anim_name + "' not found")
		return
	
	# Store previous state
	previous_state = current_state
	current_state = anim_name
	
	# Handle animation transition effects
	handle_animation_transition(previous_state, current_state)
	
	# Use custom blend time if provided, otherwise use default
	var blend_duration = custom_blend if custom_blend >= 0 else blend_time
	
	# Play with blending if blend time > 0
	if blend_duration > 0 and current_animation != "":
		is_transitioning = true
		play(anim_name, blend_duration)
	else:
		play(anim_name)
	
	# Reset transition flag after blend
	if blend_duration > 0:
		get_tree().create_timer(blend_duration).timeout.connect(func(): is_transitioning = false)

func handle_animation_transition(from_state: String, to_state: String):
	"""Handle special effects when transitioning between animations"""
	
	# Landing effect
	if from_state in ["fall", "jump"] and to_state in ["idle", "run"]:
		trigger_land_effect()
	
	# Jump effect
	if to_state == "jump" and from_state != "jump":
		trigger_jump_effect()
	
	# Running dust effect
	if to_state == "run" and from_state != "run":
		trigger_run_start_effect()
	
	# Stop running effects when stopping
	if from_state == "run" and to_state != "run":
		stop_run_effects()

func trigger_jump_effect():
	"""Trigger jump visual and audio effects"""
	if jump_particles:
		jump_particles.restart()
	
	if jump_sound:
		jump_sound.play()

func trigger_land_effect():
	"""Trigger landing visual and audio effects"""
	if land_particles:
		land_particles.restart()
	
	if land_sound:
		land_sound.play()
	
	# Simple screen shake
	trigger_screen_shake(3.0, 0.15)

func trigger_run_start_effect():
	"""Trigger running start effects"""
	if dust_particles:
		dust_particles.emitting = true

func stop_run_effects():
	"""Stop running particle effects"""
	if dust_particles:
		dust_particles.emitting = false

func trigger_screen_shake(intensity: float, duration: float):
	"""Simple screen shake effect"""
	if not player:
		return
		
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return
	
	var tween = create_tween()
	var original_offset = camera.offset
	var shake_count = int(duration * 60)
	
	for i in shake_count:
		var shake_offset = Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		tween.tween_callback(func(): camera.offset = original_offset + shake_offset)
		tween.tween_delay(1.0 / 60.0)
	
	tween.tween_callback(func(): camera.offset = original_offset)

func _on_animation_started(anim_name: StringName):
	"""Handle animation started events"""
	match anim_name:
		"run":
			# Start footstep timer for running animation
			start_footstep_timer()

func _on_animation_finished(anim_name: StringName):
	"""Handle animation finished events"""
	match anim_name:
		"jump":
			# Jump animation finished, check if should transition to fall
			if player and not player.is_on_floor() and player.velocity.y > 0:
				play_animation("fall")
		"land":
			# Land animation finished, transition based on movement
			if player:
				if abs(player.velocity.x) > 10:
					play_animation("run")
				else:
					play_animation("idle")

func start_footstep_timer():
	"""Start timer for footstep sounds during running"""
	if current_state != "run":
		return
	
	if step_sound:
		step_sound.pitch_scale = randf_range(0.9, 1.1)
		step_sound.play()
	
	# Schedule next footstep
	var step_interval = 0.3 # Adjust based on your run animation speed
	get_tree().create_timer(step_interval).timeout.connect(start_footstep_timer)

# Animation control methods
func pause_animation():
	"""Pause the current animation"""
	pause()

func resume_animation():
	"""Resume the current animation"""
	play()

func set_animation_speed(speed: float):
	"""Set the playback speed of animations"""
	speed_scale = speed

func get_current_animation_name() -> String:
	"""Get the current animation state"""
	return current_state

func is_animation_playing(anim_name: String) -> bool:
	"""Check if a specific animation is currently playing"""
	return current_state == anim_name and is_playing()

func get_animation_progress() -> float:
	"""Get the current animation progress (0.0 to 1.0)"""
	if current_animation_length > 0:
		return current_animation_position / current_animation_length
	return 0.0

func set_animation_progress(progress: float):
	"""Set the animation to a specific progress point"""
	if current_animation_length > 0:
		seek(progress * current_animation_length)

# Advanced animation methods
func queue_animation(anim_name: String, delay: float = 0.0):
	"""Queue an animation to play after a delay"""
	if delay > 0:
		get_tree().create_timer(delay).timeout.connect(func(): play_animation(anim_name))
	else:
		queue(anim_name)

func blend_to_animation(anim_name: String, custom_blend_time: float = 0.3):
	"""Smoothly blend to another animation with custom blend time"""
	play_animation(anim_name, false, custom_blend_time)

func stop_all_effects():
	"""Stop all particle effects and sounds"""
	if dust_particles:
		dust_particles.emitting = false
	if jump_particles:
		jump_particles.emitting = false
	if land_particles:
		land_particles.emitting = false
	
	if step_sound and step_sound.playing:
		step_sound.stop()
	if jump_sound and jump_sound.playing:
		jump_sound.stop()
	if land_sound and land_sound.playing:
		land_sound.stop()

# Animation event system
signal animation_event(event_name: String, data: Dictionary)

func trigger_animation_event(event_name: String, data: Dictionary = {}):
	"""Trigger a custom animation event"""
	animation_event.emit(event_name, data)

# Call this from animation tracks to trigger events
func _on_animation_event(event_name: String, data: Dictionary = {}):
	"""Handle animation track events"""
	match event_name:
		"footstep":
			if step_sound:
				step_sound.pitch_scale = randf_range(0.9, 1.1)
				step_sound.play()
		"dust_puff":
			if dust_particles:
				dust_particles.restart()
		"impact":
			trigger_screen_shake(2.0, 0.1)
		_:
			# Forward unknown events
			trigger_animation_event(event_name, data)
