extends CharacterBody2D

# Movement variables - refined for better feel
@export var speed: float = 220.0           # Slightly faster base speed
@export var jump_velocity: float = -320.0  # Higher jump for better platforming
@export var acceleration: float = 15.0     # Snappier acceleration
@export var friction: float = 18.0         # Better stopping
@export var air_acceleration: float = 10.0 # Better air control
@export var air_friction: float = 3.0      # Slight air friction for control

# Enhanced gravity system
@export var gravity_scale: float = 1.0
@export var fall_gravity_multiplier: float = 1.4  # Fall faster than rise
@export var max_fall_speed: float = 500.0
@export var fast_fall_multiplier: float = 2.0     # Hold down to fall faster

# Wall mechanics
@export var wall_slide_speed: float = 80.0
@export var wall_jump_velocity: Vector2 = Vector2(180, -280)
@export var wall_jump_push_time: float = 0.15     # Time before you can move back toward wall
@export var wall_check_distance: float = 6.0

# Jump enhancements
@export var coyote_time: float = 0.15
@export var jump_buffer_time: float = 0.2
@export var jump_cut_multiplier: float = 0.4      # More dramatic jump cutting
@export var max_jumps: int = 1                    # For double jump (set to 2 if wanted)

# Dash system - Hollow Knight style
@export var dash_speed: float = 600.0             # Much faster dash speed
@export var dash_duration: float = 0.25           # Longer duration for distance
@export var dash_cooldown: float = 0.6            # Quick recovery
@export var dash_ghost_time: float = 0.15         # Longer ghost time
@export var dash_end_speed_retention: float = 0.4  # Keep more speed after dash

# Landing and momentum
@export var landing_lag_time: float = 0.1         # Brief pause on hard landings
@export var momentum_preservation: float = 0.7    # Keep some speed when changing direction

@export_category("Requirements")
@export var player_animation: AnimationPlayer
@export var player_audio_manager: PlayerAudioManager

@export_category("FX")
@export var jump_fx: CPUParticles2D

# Enhanced state tracking
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var jumps_remaining: int = 0
var was_on_floor: bool = false
var is_wall_sliding: bool = false
var wall_normal: Vector2 = Vector2.ZERO
var wall_push_timer: float = 0.0

# Dash state
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var dash_ghost_timer: float = 0.0

# Landing system
var landing_lag_timer: float = 0.0
var last_y_velocity: float = 0.0

# Enhanced movement feel
var last_direction: int = 0
var direction_change_timer: float = 0.0

var in_teleport_zone: bool = false

# Audio state tracking
var was_moving: bool = false

# Get the gravity from the project settings
var base_gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var gravity: float

var is_dead = false

# Node references
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Player
@onready var collision_shape: CollisionShape2D = $PlayerCollision
var wall_checker_left: RayCast2D = null
var wall_checker_right: RayCast2D = null

func _ready():
	setup_wall_checkers()
	validate_nodes()
	gravity = base_gravity * gravity_scale
	jumps_remaining = max_jumps

func setup_wall_checkers():
	if not wall_checker_left:
		wall_checker_left = RayCast2D.new()
		add_child(wall_checker_left)
		wall_checker_left.name = "WallCheckerLeft"
	
	if not wall_checker_right:
		wall_checker_right = RayCast2D.new()
		add_child(wall_checker_right)
		wall_checker_right.name = "WallCheckerRight"
	
	# Position checkers slightly higher for better wall detection
	var check_offset = Vector2.ZERO
	if collision_shape and collision_shape.shape:
		# Handle different collision shape types
		if collision_shape.shape is RectangleShape2D:
			check_offset = Vector2(0, -collision_shape.shape.size.y * 0.2)
		elif collision_shape.shape is CapsuleShape2D:
			check_offset = Vector2(0, -collision_shape.shape.height * 0.2)
		elif collision_shape.shape is CircleShape2D:
			check_offset = Vector2(0, -collision_shape.shape.radius * 0.4)
		else:
			# Default offset for other shapes
			check_offset = Vector2(0, -10)
	
	wall_checker_left.position = check_offset
	wall_checker_right.position = check_offset
	wall_checker_left.target_position = Vector2(-wall_check_distance, 0)
	wall_checker_right.target_position = Vector2(wall_check_distance, 0)
	wall_checker_left.enabled = true
	wall_checker_right.enabled = true

func validate_nodes():
	if not animation_player:
		push_error("AnimationPlayer node not found! Make sure to add it as a child.")
	if not sprite:
		push_error("Sprite2D node not found! Make sure to add it as a child.")
	if not collision_shape:
		push_error("CollisionShape2D node not found! Make sure to add it as a child.")
	if not player_audio_manager:
		push_warning("PlayerAudioManager not assigned! Audio will not work.")

func _physics_process(delta):
	handle_dash(delta)
	
	if not is_dashing:
		handle_gravity(delta)
		handle_wall_sliding(delta)
		handle_input(delta)
		handle_movement(delta)
		handle_landing(delta)
	
	handle_animations()
	handle_audio()  # New audio handling
	move_and_slide()
	update_timers(delta)
	
	last_y_velocity = velocity.y

func handle_gravity(delta):
	if not is_on_floor() and not is_wall_sliding and not is_dashing:  # No gravity during dash
		var gravity_multiplier = 1.0
		
		# Enhanced gravity system
		if velocity.y > 0:  # Falling
			gravity_multiplier = fall_gravity_multiplier
			# Fast fall if holding down
			if Input.is_action_pressed("down"):
				gravity_multiplier *= fast_fall_multiplier
		
		# Reduced gravity during dash ghost time
		if dash_ghost_timer > 0:
			gravity_multiplier *= 0.3  # Even less gravity for floaty feeling
		
		velocity.y += gravity * gravity_multiplier * delta
		velocity.y = min(velocity.y, max_fall_speed)

func handle_wall_sliding(delta):
	var is_touching_wall_left = wall_checker_left.is_colliding()
	var is_touching_wall_right = wall_checker_right.is_colliding()
	
	is_wall_sliding = false
	wall_normal = Vector2.ZERO
	
	# Wall push timer prevents immediately grabbing wall after wall jump
	if wall_push_timer > 0:
		wall_push_timer -= delta
		return
	
	if not is_on_floor() and velocity.y > 0:
		if is_touching_wall_left and Input.is_action_pressed("left"):
			is_wall_sliding = true
			wall_normal = Vector2.RIGHT
			velocity.y = min(velocity.y, wall_slide_speed)
			# Reset jumps when wall sliding
			jumps_remaining = max_jumps
		elif is_touching_wall_right and Input.is_action_pressed("right"):
			is_wall_sliding = true
			wall_normal = Vector2.LEFT
			velocity.y = min(velocity.y, wall_slide_speed)
			jumps_remaining = max_jumps

func handle_input(delta):
	# Handle jump input with buffering
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	
	# Variable jump height - more responsive
	if Input.is_action_just_released("jump") and velocity.y < 0:
		velocity.y *= jump_cut_multiplier
	
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
	
	# Enhanced jump logic
	if jump_buffer_timer > 0 and landing_lag_timer <= 0:
		if is_on_floor() or coyote_timer > 0:
			perform_jump()
		elif is_wall_sliding:
			perform_wall_jump()
		elif jumps_remaining > 0 and max_jumps > 1:  # Double jump
			perform_air_jump()
	
	# Dash input
	if Input.is_action_just_pressed("dash") and can_dash():
		start_dash()

func perform_jump():
	jump_fx.emitting = true
	velocity.y = jump_velocity
	jump_buffer_timer = 0
	coyote_timer = 0
	jumps_remaining = max_jumps - 1
	is_wall_sliding = false
	
	# Play jump sound
	if player_audio_manager:
		player_audio_manager.play_jump()

func perform_wall_jump():
	velocity = Vector2(wall_normal.x * wall_jump_velocity.x, wall_jump_velocity.y)
	jump_buffer_timer = 0
	jumps_remaining = max_jumps - 1
	is_wall_sliding = false
	wall_push_timer = wall_jump_push_time  # Prevent immediate re-grab
	
	# Play jump sound
	if player_audio_manager:
		player_audio_manager.play_jump()

func perform_air_jump():
	velocity.y = jump_velocity * 0.9  # Slightly weaker air jump
	jump_buffer_timer = 0
	jumps_remaining -= 1
	
	# Play jump sound
	if player_audio_manager:
		player_audio_manager.play_jump()

func handle_movement(delta):
	var direction = Input.get_axis("left", "right")
	
	# Track direction changes for momentum preservation
	if direction != 0 and sign(direction) != last_direction:
		if last_direction != 0:  # We're changing direction, not starting from stop
			direction_change_timer = 0.1
		last_direction = sign(direction)
	elif direction == 0:
		last_direction = 0
	
	if direction != 0:
		var target_speed = direction * speed
		var accel = acceleration if is_on_floor() else air_acceleration
		
		# Preserve some momentum when changing direction quickly
		if direction_change_timer > 0 and sign(velocity.x) != sign(direction):
			target_speed = lerp(velocity.x, target_speed, momentum_preservation)
		
		velocity.x = move_toward(velocity.x, target_speed, accel * speed * delta)
		
		# Flip sprite
		if sprite:
			sprite.flip_h = direction < 0
	else:
		# Apply friction
		var friction_value = friction if is_on_floor() else air_friction
		velocity.x = move_toward(velocity.x, 0, friction_value * speed * delta)
	
	# Update direction change timer
	if direction_change_timer > 0:
		direction_change_timer -= delta

func handle_landing(delta):
	# Landing lag system for better game feel
	if was_on_floor == false and is_on_floor():
		# Hard landing detection
		if last_y_velocity > 300:
			landing_lag_timer = landing_lag_time
		
		# Reset jumps on landing
		jumps_remaining = max_jumps
	
	if landing_lag_timer > 0:
		landing_lag_timer -= delta
		# Reduce control during landing lag
		velocity.x *= 0.8

func can_dash() -> bool:
	return dash_cooldown_timer <= 0 and not is_dashing

func start_dash():
	var input_direction = Input.get_vector("left", "right", "up", "down")
	
	# Default to facing direction if no input
	if input_direction == Vector2.ZERO:
		var facing_direction = 1 if (sprite and sprite.flip_h) else -1
		input_direction = Vector2(facing_direction, 0)
	
	dash_direction = input_direction.normalized()
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	dash_ghost_timer = dash_ghost_time
	
	# Set dash velocity - maintain full speed throughout dash
	velocity = dash_direction * dash_speed
	
	# Optional: Reset jumps on dash for more mobility
	jumps_remaining = max_jumps
	
	# Play dash sound
	if player_audio_manager:
		player_audio_manager.play_dash()

func handle_dash(delta):
	if is_dashing:
		dash_timer -= delta
		
		# Maintain dash velocity throughout the dash duration
		velocity = dash_direction * dash_speed
		
		if dash_timer <= 0:
			is_dashing = false
			# Retain more momentum after dash ends (Hollow Knight style)
			var retained_speed = dash_speed * dash_end_speed_retention
			velocity = dash_direction * retained_speed
	
	# Dash ghost timer for reduced gravity
	if dash_ghost_timer > 0:
		dash_ghost_timer -= delta

func handle_audio():
	if not player_audio_manager:
		return
	
	# Handle running audio
	var is_moving = is_on_floor() and abs(velocity.x) > 20
	
	if is_moving and not was_moving:
		# Started moving
		player_audio_manager.start_running()
	elif not is_moving and was_moving:
		# Stopped moving
		player_audio_manager.stop_running()
	
	was_moving = is_moving

func handle_animations():
	if not animation_player:
		return
	
	var anim_to_play = "idle"
	
	if is_dashing:
		anim_to_play = "dash"
	elif landing_lag_timer > 0:
		anim_to_play = "landing"
	elif is_wall_sliding:
		anim_to_play = "wall_slide"
	elif not is_on_floor():
		if velocity.y < -50:
			anim_to_play = "jump"
		elif velocity.y > 50:
			anim_to_play = "fall"
		else:
			anim_to_play = "float"  # Peak of jump
	elif abs(velocity.x) > 20:
		anim_to_play = "run"
	
	play_animation(anim_to_play)

func play_animation(anim_name: String):
	if animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name)
	else:
		# Enhanced fallback system
		match anim_name:
			"dash":
				play_fallback_animation(["jump", "run", "idle"])
			"wall_slide":
				play_fallback_animation(["jump", "idle"])
			"landing":
				play_fallback_animation(["idle"])
			"float":
				play_fallback_animation(["jump", "idle"])
			_:
				play_fallback_animation(["idle"])

func play_fallback_animation(fallback_list: Array):
	for anim in fallback_list:
		if animation_player.has_animation(anim):
			if animation_player.current_animation != anim:
				animation_player.play(anim)
			return

func update_timers(delta):
	# Update coyote time
	if is_on_floor():
		coyote_timer = coyote_time
		was_on_floor = true
	elif was_on_floor:
		was_on_floor = false
	else:
		coyote_timer = max(0, coyote_timer - delta)
	
	# Update dash cooldown
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta

# Enhanced utility functions
func bounce(bounce_velocity: float):
	velocity.y = bounce_velocity
	jumps_remaining = max_jumps  # Reset jumps on bounce

func take_damage(knockback_force: Vector2 = Vector2.ZERO, damage_amount: int = 1):
	velocity += knockback_force
	is_dashing = false
	dash_timer = 0
	dash_ghost_timer = 0
	landing_lag_timer = 0
	
	# Stop audio when taking damage
	if player_audio_manager:
		player_audio_manager.stop_all_sounds()

func reset_position(new_position: Vector2):
	global_position = new_position
	velocity = Vector2.ZERO
	is_dashing = false
	dash_timer = 0
	dash_cooldown_timer = 0
	dash_ghost_timer = 0
	jumps_remaining = max_jumps
	landing_lag_timer = 0
	
	# Stop audio when resetting
	if player_audio_manager:
		player_audio_manager.stop_all_sounds()

func get_movement_state() -> String:
	if is_dashing:
		return "dashing"
	elif landing_lag_timer > 0:
		return "landing"
	elif is_wall_sliding:
		return "wall_sliding"
	elif not is_on_floor():
		if velocity.y < -50:
			return "jumping"
		elif velocity.y > 50:
			return "falling"
		else:
			return "floating"
	elif abs(velocity.x) > 20:
		return "running"
	else:
		return "idle"

# Enhanced getter functions
func get_dash_cooldown_percentage() -> float:
	return 1.0 - (dash_cooldown_timer / dash_cooldown)

func get_jumps_remaining() -> int:
	return jumps_remaining

func is_grounded() -> bool:
	return is_on_floor()

func is_moving() -> bool:
	return abs(velocity.x) > 20

func can_wall_jump() -> bool:
	return is_wall_sliding and wall_push_timer <= 0

# Signal handlers
func _on_danger_area_area_entered(area: Area2D) -> void:
	print("Player Dies")
	is_dead = true
	
	# Stop all audio when dying
	if player_audio_manager:
		player_audio_manager.stop_all_sounds()

func _on_teleport_zone_area_entered(area: Area2D) -> void:
	print("Entered: " + area.name)
	in_teleport_zone = true

func _on_teleport_zone_area_exited(area: Area2D) -> void:
	print("Exited: " + area.name)
	in_teleport_zone = false
