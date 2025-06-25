extends Node2D

@export var ghost_sprite: Sprite2D = null
@export var ghost_animation: AnimationPlayer = null
@export var jump_particle: CPUParticles2D = null

func jump():
	jump_particle.emitting = true
