extends Node2D

@export var colliders: Array[CollisionShape2D]
@export var sprites: Array[Sprite2D]
@export var respawn_point: Node2D

var is_past:bool = false

func _process(delta: float) -> void:
	toggle_mesh_colliders()

func toggle_mesh_colliders():
	if not is_past:
		for collider in colliders:
			collider.disabled = false
		
		for sprite in sprites:
			sprite.modulate = Color.WHITE
	else:
		for collider in colliders:
			collider.disabled = true
		
		for sprite in sprites:
			sprite.modulate = Color(Color.DARK_CYAN, 100)
