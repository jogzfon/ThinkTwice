extends Node2D
@export var colliders: Array[TileMapLayer]
@export var respawn_point: Node2D
var is_past: bool = false

func _process(delta: float) -> void:
	toggle_mesh_colliders()

func toggle_mesh_colliders():
	if not is_past:
		for collider in colliders:
			collider.collision_enabled = true
			collider.modulate = Color.WHITE
	else:
		for collider in colliders:
			collider.collision_enabled = false
			collider.modulate = Color(Color.DARK_CYAN, 0.39) # Using alpha value 0-1 range
