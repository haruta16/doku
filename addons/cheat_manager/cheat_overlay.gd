class_name CheatOverlay
extends CanvasLayer

@onready var _fps_button: FpsButton = $FpsButton
@onready var _cheat_panel: CheatPanel = $CheatPanel

func _ready() -> void :
    _fps_button.toggle_panel_requested.connect(_cheat_panel.toggle)
