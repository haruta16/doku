## 第二组通关统计面板：填充结果数据并调整条目居中布局。
class_name PassPageG2Board
extends PassPageG1Board

const _CELLS_WIDTH: float = 250.0
const _ICON_WIDTH: float = 100.0

@onready var _rate_icon: Control = $ContentGroup/Popup/InfoGroup/RateItem/Cells/CompletionRate
@onready var _rate_value: Label = $ContentGroup/Popup/InfoGroup/RateItem/Cells/ValueLabel
@onready var _error_icon: Control = $ContentGroup/Popup/InfoGroup/ErrorItem/Cells/ErrorCount
@onready var _error_value: Label = $ContentGroup/Popup/InfoGroup/ErrorItem/Cells/ValueLabel
@onready var _hint_icon: Control = $ContentGroup/Popup/InfoGroup/HintItem/Cells/HintCount
@onready var _hint_value: Label = $ContentGroup/Popup/InfoGroup/HintItem/Cells/ValueLabel


func _ready() -> void:
	_sprite2d_y_offset_from_popup = 54.0
	super._ready()


func populate(
	title_text: String,
	praise_bbcode: String,
	next_label: String,
	next_is_hard: bool,
	stats: Dictionary,
	is_next_golden: bool = false
) -> void:
	super.populate(title_text, praise_bbcode, next_label, next_is_hard, stats, is_next_golden)
	_rate_value.text = I18nFormat.percent(float(int(stats.get("completion_rate", 0))), 0)
	_error_value.text = "%d" % int(stats.get("mistake_count", 0))
	_hint_value.text = "%d" % int(stats.get("tools_used", 0))
	_center_item(_rate_icon, _rate_value)
	_center_item(_error_icon, _error_value)
	_center_item(_hint_icon, _hint_value)


func _center_item(icon: Control, value: Label) -> void:
	var font: Font = value.get_theme_font("font")
	var font_size: int = value.get_theme_font_size("font_size")
	var text_width: float = (
		font.get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	)
	var start_x: float = (_CELLS_WIDTH - _ICON_WIDTH - text_width) * 0.5
	icon.offset_left = start_x
	icon.offset_right = start_x + _ICON_WIDTH
	value.offset_left = start_x + _ICON_WIDTH
	value.offset_right = start_x + _ICON_WIDTH + text_width
