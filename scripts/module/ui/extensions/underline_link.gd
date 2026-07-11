@tool
class_name UnderlineLink
extends RichTextLabel

const _BASE_FONT_SIZE: int = 48
const _MIN_FONT_SIZE: int = 26

var _font_size_cap: int = 0

@export var text_key: String = "":
	set(value):
		text_key = value
		_refresh()


func _ready() -> void:
	bbcode_enabled = true
	scroll_active = false
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()
	elif what == NOTIFICATION_RESIZED:
		_refresh()


func set_font_size_cap(cap: int) -> void:
	_font_size_cap = maxi(0, cap)
	_refresh()


func measure_fit_font_size() -> int:
	return _compute_fit(_BASE_FONT_SIZE)


func _refresh() -> void:
	if text_key.is_empty():
		return
	bbcode_enabled = true
	var display: String = tr(text_key)

	var upper: int = (
		mini(_font_size_cap, _BASE_FONT_SIZE) if _font_size_cap > 0 else _BASE_FONT_SIZE
	)
	add_theme_font_size_override("normal_font_size", _compute_fit(upper))
	text = "[center][u]%s[/u][/center]" % display


func _compute_fit(upper: int) -> int:
	var display: String = tr(text_key)
	var font: Font = get_theme_font("normal_font")

	var avail_w: float = size.x if size.x > 0.0 else (offset_right - offset_left)
	var fs: int = upper
	if font != null and avail_w > 0.0:
		while fs > _MIN_FONT_SIZE:
			if font.get_string_size(display, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= avail_w - 20.0:
				break
			fs -= 2
	return fs
