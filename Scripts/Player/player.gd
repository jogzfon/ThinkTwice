extends CharacterBody2D

# Movement variables - optimized values
@export var speed: float = 200.0
@export var jump_velocity: float = -300.0
@export var acceleration: float = 12.0     # More reasonable acceleration
@export var friction: float = 15.0         # Better stopping control
@export var air_acceleration: float = 8.0  # Separate air control
@export var air_friction: float = 2.0      # Minimal air friction

# Advanced movement features
@export var max_fall_speed: float = 400.0
@export var wall_slide_speed: float = 60.0
@export var wall_jump_velocity: Vector2 = Vector2(150, -250)
@export var dash_speed: float = 400.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 1.0

# Coyote time and jump buffering
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.15
@export var jump_cut_multiplier: float = 0.5  # Variable jump height

# Wall detection
@export var wall_check_distance: float = 5.0

# Internal variables
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var was_on_floor: bool = false
var is_wall_sliding: bool = false
var wall_normal: Vector2 = Vector2.ZERO

# Dash variables
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO

# Get the gravity from the project settings
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# Node references
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Player
@onready var collision_shape: CollisionShape2D = $PlayerCollision
var wall_checker_left: RayCast2D = null
var wall_checker_right: RayCast2D = null

func _ready():
	setup_wall_checkers()
	validate_nodes()

func setup_wall_checkers():
	# Create wall checkers if they don't exist
	if not wall_checker_left:
		wall_checker_left = RayCast2D.new()
		add_child(wall_checker_left)
		wall_checker_left.name = "WallCheckerLeft"
	
	if not wall_checker_right:
		wall_checker_right = RayCast2D.new()
		add_child(wall_checker_right)
		wall_checker_right.name = "WallCheckerRight"
	
	# Configure wall checkers
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

func _physics_process(delta):
	handle_dash(delta)
	
	if not is_dashing:
		handle_gravity(delta)
		handle_wall_sliding(delta)
		handle_input(delta)
		handle_movement(delta)
	
	handle_animations()
	move_and_slide()
	update_timers(delta)

func handle_gravity(delta):
	if not is_on_floor() and not is_wall_sliding:
		velocity.y += gravity * delta
		# Cap fall speed
		velocity.y = min(velocity.y, max_fall_speed)

func handle_wall_sliding(delta):
	# Check for walls
	var is_touching_wall_left = wall_checker_left.is_colliding()
	var is_touching_wall_right = wall_checker_right.is_colliding()
	
	is_wall_sliding = false
	wall_normal = Vector2.ZERO
	
	if not is_on_floor() and velocity.y > 0:
		if is_touching_wall_left and Input.is_action_pressed("left"):
			is_wall_sliding = true
			wall_normal = Vector2.RIGHT
			velocity.y = min(velocity.y, wall_slide_speed)
		elif is_touching_wall_right and Input.is_action_pressed("right"):
			is_wall_sliding = true
			wall_normal = Vector2.LEFT
			velocity.y = min(velocity.y, wall_slide_speed)

func handle_input(delta):
	# Handle jump input with buffering
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	
	# Variable jump height - cut jump short if button released
	if Input.is_action_just_released("jump") and velocity.y < 0:
		velocity.y *= jump_cut_multiplier
	
	# Decrease jump buffer timer
	if jump_buffer_timer > 0:
		jump_buffer_timer -= delta
	
	# Jump logic
	if jump_buffer_timer > 0:
		if is_on_floor() or coyote_timer > 0:
			# Normal jump
			perform_jump()
		elif is_wall_sliding:
			# Wall jump
			perform_wall_jump()
	
	# Dash input
	if Input.is_action_just_pressed("dash") and can_dash():
		start_dash()

func perform_jump():
	velocity.y = jump_velocity
	jump_buffer_timer = 0
	coyote_timer = 0
	is_wall_sliding = false

func perform_wall_jump():
	velocity = Vector2(wall_normal.x * wall_jump_velocity.x, wall_jump_velocity.y)
	jump_buffer_timer = 0
	is_wall_sliding = false

func handle_movement(delta):
	var direction = Input.get_axis("left", "right")
	
	if direction != 0:
		var target_speed = direction * speed
		var accel = acceleration if is_on_floor() else air_acceleration
		
		# Use move_toward with delta for frame-rate independent movement
		velocity.x = move_toward(velocity.x, target_speed, accel * speed * delta)
		
		# Flip sprite
		if sprite:
			sprite.flip_h = direction > 0
	else:
		# Apply friction
		var friction_value = friction if is_on_floor() else air_friction
		velocity.x = move_toward(velocity.x, 0, friction_value * speed * delta)

func can_dash() -> bool:
	return dash_cooldown_timer <= 0 and not is_dashing

func start_dash():
	var input_direction = Input.get_vector("left", "right", "up", "down")
	
	# Default to facing direction if no input
	if input_direction == Vector2.ZERO:
		var facing_direction = -1 if (sprite and sprite.flip_h) else 1
		input_direction = Vector2(facing_direction, 0)
	
	dash_direction = input_direction.normalized()
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	
	# Set dash velocity
	velocity = dash_direction * dash_speed

func handle_dash(delta):
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			# Reduce velocity after dash
			velocity *= 0.5

func handle_animations():
	if not animation_player:
		return
	
	var anim_to_play = "idle"
	
	if is_dashing:
		anim_to_play = "dash"
	elif is_wall_sliding:
		anim_to_play = "wall_slide"
	elif not is_on_floor():
		anim_to_play = "jump" if velocity.y < 0 else "fall"
	elif abs(velocity.x) > 10:
		anim_to_play = "run"
	
	play_animation(anim_to_play)

func play_animation(anim_name: String):
	if animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name)
	else:
		# Fallback animations
		match anim_name:
			"dash", "wall_slide":
				if animation_player.has_animation("jump"):
					if animation_player.current_animation != "jump":
						animation_player.play("jump")
			_:
				if animation_player.has_animation("idle"):
					if animation_player.current_animation != "idle":
						animation_player.play("idle")

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

# Utility functions
func bounce(bounce_velocity: float):
	velocity.y = bounce_velocity

func take_damage(knockback_force: Vector2 = Vector2.ZERO, damage_amount: int = 1):
	velocity += knockback_force
	# Reset dash state on damage
	is_dashing = false
	dash_timer = 0

func reset_position(new_position: Vector2):
	global_position = new_position
	velocity = Vector2.ZERO
	is_dashing = false
	dash_timer = 0
	dash_cooldown_timer = 0

func get_movement_state() -> String:
	if is_dashing:
		return "dashing"
	elif is_wall_sliding:
		return "wall_sliding"
	elif not is_on_floor():
		return "jumping" if velocity.y < 0 else "falling"
	elif abs(velocity.x) > 10:
		return "running"
	else:
		return "idle"

# Getter functions for debugging/UI
func get_dash_cooldown_percentage() -> float:
	return 1.0 - (dash_cooldown_timer / dash_cooldown)

func is_grounded() -> bool:
	return is_on_floor()

func is_moving() -> bool:
	return abs(velocity.x) > 10
