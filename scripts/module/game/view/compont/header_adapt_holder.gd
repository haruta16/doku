## 顶部自适应容器：依据视口高度重新计算标题区尺寸，支持调试时即时重排。
@tool
extends Control

const _MIN_HEIGHT: float = 1920.0
const _MAX_HEIGHT: float = 2400.0
const _MIN_Y: float = 0.0
const _MAX_Y: float = 65.0

const _SAVE_BASELINE_Y: float = _MAX_Y


func _ready() -> void:
	_apply_adaptive_height()

	if not Engine.is_editor_hint():
		get_viewport().size_changed.connect(_apply_adaptive_height)


func debug_recompute() -> void:
	_apply_adaptive_height()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		custom_minimum_size.y = _SAVE_BASELINE_Y
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_apply_adaptive_height()


func _apply_adaptive_height() -> void:
	var view_h: float = _resolve_view_height()
	if view_h <= 0.0:
		return
	var t: float = clampf((view_h - _MIN_HEIGHT) / (_MAX_HEIGHT - _MIN_HEIGHT), 0.0, 1.0)
	custom_minimum_size.y = lerpf(_MIN_Y, _MAX_Y, t)


func _resolve_view_height() -> float:
	if Engine.is_editor_hint():
		return float(
			ProjectSettings.get_setting("display/window/size/viewport_height", _MIN_HEIGHT)
		)
	return get_viewport_rect().size.y
