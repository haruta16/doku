## 排行榜在线标签；根据显示状态设置文本与字号，容纳本地化的最近活跃时间。

extends Panel

const _COLOR_ONLINE: Color = Color(0.196078, 0.65098, 0.223529, 0.7)
const _COLOR_OFFLINE: Color = Color(0.772549, 0.6, 0.482353, 0.7)

const _PAD_H: float = 18.0
const _TAG_HEIGHT: float = 44.0
const _BASE_FONT_SIZE: int = 30
const _MIN_FONT_SIZE: int = 18

const _SEC_PER_MIN: int = 60
const _SEC_PER_HOUR: int = 3600
const _SEC_PER_DAY: int = 86400

@onready var _text: Label = $Text

var _style: StyleBoxFlat = null


func _ready() -> void:
	var shared: StyleBox = get_theme_stylebox(&"panel")
	if shared is StyleBoxFlat:
		_style = (shared as StyleBoxFlat).duplicate()
		add_theme_stylebox_override(&"panel", _style)


func apply(
	is_online: bool,
	idle_sec: int,
	max_width: float,
	is_self: bool = false,
	self_offline: bool = false
) -> void:
	var label: Label = _text if _text != null else get_node_or_null("Text") as Label
	if label == null:
		visible = true
		return
	label.text = _state_text(is_online, idle_sec, is_self, self_offline)
	if _style != null:
		_style.bg_color = (
			_COLOR_ONLINE if ((is_online or is_self) and not self_offline) else _COLOR_OFFLINE
		)
	var font: Font = label.get_theme_font(&"font")
	if font == null:
		visible = true
		return
	var font_size: int = _BASE_FONT_SIZE
	var text_width: float = 0.0
	while true:
		text_width = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		if text_width + _PAD_H * 2.0 <= max_width or font_size <= _MIN_FONT_SIZE:
			break
		font_size -= 1
	label.add_theme_font_size_override(&"font_size", font_size)

	size = Vector2(minf(text_width + _PAD_H * 2.0, max_width), _TAG_HEIGHT)
	visible = true


func _state_text(
	is_online: bool, idle_sec: int, is_self: bool, self_offline: bool = false
) -> String:
	if self_offline:
		return tr("RANK_STATE_OFFLINE_NOW")
	if is_self:
		return tr("RANK_STATE_ONLINE_NOW")
	if is_online:
		return tr("RANK_STATE_PLAYING_NOW")
	var safe_sec: int = maxi(0, idle_sec)
	if safe_sec < _SEC_PER_HOUR:
		return tr("RANK_STATE_MINUTES_AGO") % maxi(1, safe_sec / _SEC_PER_MIN)
	if safe_sec < _SEC_PER_DAY:
		return (
			tr("RANK_STATE_HOURS_AGO")
			% [safe_sec / _SEC_PER_HOUR, (safe_sec % _SEC_PER_HOUR) / _SEC_PER_MIN]
		)
	return (
		tr("RANK_STATE_DAYS_AGO")
		% [safe_sec / _SEC_PER_DAY, (safe_sec % _SEC_PER_DAY) / _SEC_PER_HOUR]
	)
