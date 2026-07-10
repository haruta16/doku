@tool
class_name AnimPreset
extends Resource



enum PlayMode{SEQUENTIAL, PARALLEL, STAGGER}

@export var preset_name: String = "Preset"
@export var play_mode: PlayMode = PlayMode.SEQUENTIAL
@export var duration: float = 0.5
