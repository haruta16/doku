## 返回与设置按钮容器：贴合屏幕边缘，统一注册回调和临时锁定。
@tool
class_name BackAndSettingHeader
extends Control

@export var show_back_btn: bool = true:
	set(value):
		show_back_btn = value
		if is_node_ready():
			$BackBtn.visible = value

@export var show_settings_btn: bool = true:
	set(value):
		show_settings_btn = value
		if is_node_ready():
			$SettingsBtn.visible = value

@onready var _back_btn: Button = $BackBtn
@onready var _settings_btn: Button = $SettingsBtn


func _ready() -> void:
	_back_btn.visible = show_back_btn
	_settings_btn.visible = show_settings_btn
	if not Engine.is_editor_hint():
		_adjust_to_screen_edges()

		UIHelper.bind_press_release_scale(_back_btn)
		UIHelper.bind_press_release_scale(_settings_btn)


func _adjust_to_screen_edges() -> void:
	await get_tree().process_frame
	var canvas_width := get_viewport_rect().size.x
	var left_margin := global_position.x
	var right_margin := canvas_width - (global_position.x + size.x)
	if left_margin > 0.5:
		_back_btn.offset_left -= left_margin
		_back_btn.offset_right -= left_margin
	if right_margin > 0.5:
		_settings_btn.offset_left += right_margin
		_settings_btn.offset_right += right_margin


func register_back_btn(callable: Callable) -> void:
	_back_btn.pressed.connect(callable)


func register_setting_btn(callable: Callable) -> void:
	_settings_btn.pressed.connect(callable)


func lock_buttons() -> void:
	_back_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE


func unlock_buttons() -> void:
	_back_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_btn.mouse_filter = Control.MOUSE_FILTER_STOP


func is_press_on_buttons(screen_pos: Vector2) -> bool:
	for btn: Button in [_back_btn, _settings_btn]:
		if btn.visible and not btn.disabled and btn.get_global_rect().has_point(screen_pos):
			return true
	return false
