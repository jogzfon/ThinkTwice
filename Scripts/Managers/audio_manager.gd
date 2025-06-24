extends Node2D

class_name AudioManager

@export var tick_tock_audio: AudioStreamPlayer
@export var theme_audio: AudioStreamPlayer

func _ready() -> void:
	if theme_audio:
		play_theme()
		
func play_theme():
	theme_audio.play()

func play_clock():
	if tick_tock_audio:
		tick_tock_audio.play()
func stop_clock():
	if tick_tock_audio:
		tick_tock_audio.stop()

func _on_theme_finished() -> void:
	play_theme()
