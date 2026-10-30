## 调试覆盖层：响应开关请求，协调悬浮入口与命令面板。
class_name CheatOverlay
extends CanvasLayer

signal commands_requested

@onready var _fps_button: FpsButton = $FpsButton
@onready var _cheat_panel: CheatPanel = $CheatPanel


func _ready() -> void:
	_fps_button.toggle_panel_requested.connect(_on_toggle_requested)


func _on_toggle_requested() -> void:
	commands_requested.emit()
	_cheat_panel.toggle()


func request_commands() -> void:
	commands_requested.emit()
