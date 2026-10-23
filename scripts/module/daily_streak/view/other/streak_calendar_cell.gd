## 打卡月历格：按日期与已签到标记刷新单日样式。
@tool
extends Control

@export var unchecked_visual: Control
@export var checked_visual: Control
@export var unchecked_label: Label
@export var checked_label: Label
@export var checked_background: Control
@export var checked_shadow: Control

var _background_base_width: float = 0.0
var _shadow_right_margin: float = 0.0


func render_day(
	day: int, checked: bool, show_segment_background: bool = true, segment_width: float = 0.0
) -> void:
	if (
		unchecked_visual == null
		or checked_visual == null
		or unchecked_label == null
		or checked_label == null
		or checked_background == null
		or checked_shadow == null
	):
		push_error("StreakCalendarCell: missing scene bindings")
		return
	if _background_base_width <= 0.0:
		_background_base_width = checked_background.offset_right - checked_background.offset_left
		_shadow_right_margin = checked_shadow.offset_right - checked_background.offset_right
	var background_width: float = maxf(_background_base_width, segment_width)
	checked_background.offset_right = checked_background.offset_left + background_width
	checked_shadow.offset_right = checked_background.offset_right + _shadow_right_margin
	visible = true
	unchecked_visual.visible = day > 0 and not checked
	checked_visual.visible = day > 0 and checked
	checked_background.visible = checked_visual.visible and show_segment_background
	checked_shadow.visible = checked_background.visible
	var day_text: String = str(day) if day > 0 else ""
	unchecked_label.text = day_text
	checked_label.text = day_text
