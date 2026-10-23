## 等宽数字标签：按数字网格测量整块宽度，兼顾字号适配和像素对齐。
class_name TabularDigitLabel
extends Label

const _UNIFORM_EPS: float = 0.01

@export var min_font_size: int = 12:
	set(v):
		min_font_size = maxi(1, v)
		_invalidate()

var _cache_key: String = ""

var _fit_size: int = 0

var _slot_digit: float = 0.0

var _block_w: float = 0.0

var _uniform_digits: bool = false

var _in_container: bool = false

var _watched_font: Font = null


func _ready() -> void:
	visible_characters = 0

	clip_text = true
	_in_container = get_parent() is Container
	if _in_container:
		_ensure_metrics()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		_invalidate()


func _set(property: StringName, value: Variant) -> bool:
	if property == &"text":
		queue_redraw()
	return false


func get_block_width() -> float:
	return _block_w


func ensure_block_width() -> float:
	if not _ensure_metrics():
		return 0.0
	return _block_w


func get_fit_font_size() -> int:
	return _fit_size


func is_using_grid() -> bool:
	return not _uniform_digits


func _ensure_metrics() -> bool:
	if text.is_empty():
		return false
	var font: Font = get_theme_font(&"font")
	if font == null:
		return false
	var base_size: int = get_theme_font_size(&"font_size")
	if base_size <= 0:
		return false
	_watch_font(font)
	_refresh_metrics(font, base_size, text)
	return _fit_size > 0


func _draw() -> void:
	if not _ensure_metrics():
		return
	var txt: String = text
	var font: Font = get_theme_font(&"font")

	var col: Color = get_theme_color(&"font_color")
	var outline_size: int = get_theme_constant(&"outline_size")
	var outline_col: Color = get_theme_color(&"font_outline_color")
	var ci: RID = get_canvas_item()
	var x0: float = _block_origin_x()
	var y0: float = _baseline_y(font, txt)

	if _uniform_digits:
		_draw_run(ci, Vector2(x0, y0), txt, font, col, outline_size, outline_col)
		return

	var pen_x: float = _snap(x0)
	var pen_y: float = _snap(y0)
	for i in txt.length():
		var ch: String = txt[i]
		var slot: float = _slot_digit if _is_digit(ch) else _char_width(font, ch, _fit_size)
		var glyph_w: float = _char_width(font, ch, _fit_size)
		_draw_run(
			ci,
			Vector2(_snap(pen_x + (slot - glyph_w) * 0.5), pen_y),
			ch,
			font,
			col,
			outline_size,
			outline_col
		)
		pen_x += slot


func _draw_run(
	ci: RID,
	pos: Vector2,
	run: String,
	font: Font,
	col: Color,
	outline_size: int,
	outline_col: Color
) -> void:
	if outline_size > 0 and outline_col.a > 0.0:
		font.draw_string_outline(
			ci, pos, run, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _fit_size, outline_size, outline_col
		)
	font.draw_string(ci, pos, run, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _fit_size, col)


func _snap(value: float) -> float:
	return floorf(value + 0.5)


func _block_origin_x() -> float:
	match horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return (size.x - _block_w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			return size.x - _block_w
		_:
			return 0.0


func _baseline_y(font: Font, txt: String) -> float:
	var tl: TextLine = TextLine.new()
	tl.add_string(txt, font, _fit_size)
	var asc: float = tl.get_line_ascent()
	var line_h: float = tl.get_size().y
	match vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			return (size.y - line_h) * 0.5 + asc
		VERTICAL_ALIGNMENT_BOTTOM:
			return size.y - line_h + asc
		_:
			return asc


func _char_width(font: Font, ch: String, fs: int) -> float:
	return font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x


func _is_digit(ch: String) -> bool:
	return ch.length() == 1 and ch >= "0" and ch <= "9"


func _digit_extent(font: Font, fs: int) -> Vector2:
	var lo: float = 99999.0
	var hi: float = 0.0
	for d: String in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		var advance: float = _char_width(font, d, fs)
		lo = minf(lo, advance)
		hi = maxf(hi, advance)
	return Vector2(lo, hi)


func _measure_block(font: Font, txt: String, fs: int) -> float:
	var ext: Vector2 = _digit_extent(font, fs)
	if ext.y - ext.x < _UNIFORM_EPS:
		return _char_width(font, _shape(txt), fs)
	var total: float = 0.0
	for i in txt.length():
		var ch: String = txt[i]
		total += ext.y if _is_digit(ch) else _char_width(font, ch, fs)
	return total


func _refresh_metrics(font: Font, base_size: int, txt: String) -> void:
	var key: String = "%s|%d|%d" % [_shape(txt), base_size, int(size.x)]
	if key == _cache_key and _fit_size > 0:
		return
	_cache_key = key

	var fs: int = base_size
	if not _in_container:
		var box_w: float = size.x
		var lo: int = mini(min_font_size, base_size)
		var hi: int = base_size
		fs = lo
		while lo <= hi:
			var mid: int = (lo + hi) >> 1
			if box_w <= 0.0 or _measure_block(font, txt, mid) <= box_w:
				fs = mid
				lo = mid + 1
			else:
				hi = mid - 1

	var ext: Vector2 = _digit_extent(font, fs)
	_uniform_digits = ext.y - ext.x < _UNIFORM_EPS
	_slot_digit = ext.y
	_fit_size = fs
	_block_w = _measure_block(font, txt, fs)

	if _in_container:
		custom_minimum_size.x = _block_w


func _shape(txt: String) -> String:
	var out: String = ""
	for i in txt.length():
		out += "0" if _is_digit(txt[i]) else txt[i]
	return out


func _watch_font(font: Font) -> void:
	if _watched_font == font:
		return
	if (
		_watched_font != null
		and is_instance_valid(_watched_font)
		and _watched_font.changed.is_connected(_on_font_changed)
	):
		_watched_font.changed.disconnect(_on_font_changed)
	_watched_font = font
	if not font.changed.is_connected(_on_font_changed):
		font.changed.connect(_on_font_changed)


func _on_font_changed() -> void:
	_invalidate()


func _invalidate() -> void:
	_cache_key = ""
	_fit_size = 0
	_slot_digit = 0.0
	queue_redraw()
