## 公共加载页面：更新加载文字与省略号，并按视口变化重排。
extends UIFrameWindow

const _DEFAULT_TEXT_KEY: String = "COMMON_LOADING"

const _DOT: String = "."
const _DOT_MAX: int = 3
const _DOT_INTERVAL: float = 0.5

const _TEXT_BUDGET_W: float = 840.0
const _FONT_SIZE_MAX: int = 50
const _FONT_SIZE_MIN: int = 30

const _LINE_H: float = 75.0

@onready var _tips_label: Label = $Tips/TipsLabel

var _text_key: String = _DEFAULT_TEXT_KEY
var _base_text: String = ""

var _dots: int = 1

var _tick: Timer = null


func on_show(params: Dictionary = {}) -> void:
	var key: String = str(params.get("text", _DEFAULT_TEXT_KEY))
	if key.is_empty():
		key = _DEFAULT_TEXT_KEY
	_text_key = key
	_dots = 1
	_relayout()
	if _tick == null:
		_tick = create_tick(_DOT_INTERVAL, _on_dot_tick)

	_tick.start()


func on_escape() -> bool:
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_relayout()


func _on_dot_tick() -> void:
	_dots = _dots % _DOT_MAX + 1
	_apply_text()


func _relayout() -> void:
	_base_text = _strip_trailing_dots(tr(_text_key))
	var font: Font = _tips_label.get_theme_font(&"font")
	if font != null:
		var full: String = _base_text + _DOT.repeat(_DOT_MAX)
		var fs: int = _FONT_SIZE_MAX
		var w: float = font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > _TEXT_BUDGET_W:
			fs = maxi(_FONT_SIZE_MIN, int(floor(float(fs) * _TEXT_BUDGET_W / w)))
			w = font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

		_tips_label.add_theme_font_size_override(&"font_size", fs)
		_tips_label.custom_minimum_size = Vector2(ceilf(w), _LINE_H)

	_tips_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT if _tips_label.is_layout_rtl() else HORIZONTAL_ALIGNMENT_LEFT
	)
	_apply_text()


func _apply_text() -> void:
	_tips_label.text = _base_text + _DOT.repeat(_dots)


static func _strip_trailing_dots(s: String) -> String:
	var out: String = s.strip_edges()
	while out.ends_with(".") or out.ends_with("…"):
		out = out.substr(0, out.length() - 1).strip_edges()
	return out
