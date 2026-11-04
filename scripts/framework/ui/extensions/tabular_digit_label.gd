## 等宽数字标签：按数字网格测量整块宽度，兼顾字号适配和像素对齐。
class_name TabularDigitLabel
extends Label

const _UNIFORM_EPS: float = 0.01 # 数字最大/最小宽度差小于此像素阈值时，认为字体本身等宽

@export var min_font_size: int = 12: # 非 Container 布局允许缩小到的字号下限，至少为 1
	set(v):
		min_font_size = maxi(1, v)
		_invalidate()

var _cache_key: String = "" # 数字归零后的文本形状 + 基准字号 + 整数控件宽度；空值表示需重测

var _fit_size: int = 0 # 本次使用的字号；0 表示缓存无效

var _slot_digit: float = 0.0 # 所有数字共用的槽宽，取当前字号下 0..9 的最大推进宽度

var _block_w: float = 0.0 # 最后一次测得的整串宽度，供对齐和父容器最小尺寸使用

var _uniform_digits: bool = false # 最近一次测量是否确认字体的 0..9 本身等宽

var _in_container: bool = false # ready 时记录父节点是否负责排版；决定缩字号还是报告最小宽度

var _watched_font: Font = null # 当前已订阅 changed 的字体资源；替换时断开旧订阅


## 关闭内置字形显示并开启裁剪；若父节点是 Container，先计算最小宽度供父级排版。
func _ready() -> void:
	visible_characters = 0

	clip_text = true
	_in_container = get_parent() is Container
	if _in_container:
		_ensure_metrics()


## 主题或尺寸变化会影响字体与可用宽度，清测量缓存并请求重绘。
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		_invalidate()


## text 变化时请求重绘；测量缓存按数字形状复用，实际文本赋值仍由引擎完成。
func _set(property: StringName, value: Variant) -> bool:
	if property == &"text":
		queue_redraw()
	return false


## 只返回最近一次缓存的整块宽度，不触发测量；需要当前值时调用 ensure_block_width。
func get_block_width() -> float:
	return _block_w


## 先保证当前字体和文本已测量，再返回整块宽度；文本/字体无效时返回 0。
func ensure_block_width() -> float:
	if not _ensure_metrics():
		return 0.0
	return _block_w


## 返回最近一次适配字号；0 表示尚未测量或缓存已失效。
func get_fit_font_size() -> int:
	return _fit_size


## 查询最近测量结果是否需要人工数字槽；字体的 0..9 本身等宽时不用逐字网格。
func is_using_grid() -> bool:
	return not _uniform_digits


## 检查文本和字体，更新字体监听及测量缓存；只有取得正的适配字号才返回 true。
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


## 本身等宽的数字字体整串画；否则将每个数字居中放入统一槽位，非数字仍按实际宽度推进。
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

	# 每个数字在统一槽内居中；冒号等非数字保持真实宽度，避免计时文本因 1/8 宽度差左右抖动。
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


## 在同一基线先画可见描边再画字身；run 可以是整串，也可以是网格中的单个字符。
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


## 把逻辑绘制坐标取到最近整数像素，减少相邻数字边缘的模糊差异。
func _snap(value: float) -> float:
	return floorf(value + 0.5)


## 根据水平对齐把整块文字放入控件；使用统一块宽，数字替换时起点保持稳定。
func _block_origin_x() -> float:
	match horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return (size.x - _block_w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			return size.x - _block_w
		_:
			return 0.0


## 用 TextLine 取得 ascent 和行高，把顶部/居中/底部对齐转换为实际绘制基线。
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


## 测量字符或字符串在指定字号下的水平推进宽度，单位为逻辑像素。
func _char_width(font: Font, ch: String, fs: int) -> float:
	return font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x


## 这里只把 ASCII 0..9 视为固定槽数字；标点和其他字符仍按原宽度处理。
func _is_digit(ch: String) -> bool:
	return ch.length() == 1 and ch >= "0" and ch <= "9"


## 测量 0..9 的最小、最大宽度，返回 (最小, 最大)，供等宽判断与槽宽计算。
func _digit_extent(font: Font, fs: int) -> Vector2:
	var lo: float = 99999.0
	var hi: float = 0.0
	for d: String in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		var advance: float = _char_width(font, d, fs)
		lo = minf(lo, advance)
		hi = maxf(hi, advance)
	return Vector2(lo, hi)


## 试算整块宽度：数字统一按槽宽，其他字符按实际宽度；已等宽字体用数字归零后的形状测量。
func _measure_block(font: Font, txt: String, fs: int) -> float:
	var ext: Vector2 = _digit_extent(font, fs)
	if ext.y - ext.x < _UNIFORM_EPS:
		return _char_width(font, _shape(txt), fs)
	var total: float = 0.0
	for i in txt.length():
		var ch: String = txt[i]
		total += ext.y if _is_digit(ch) else _char_width(font, ch, fs)
	return total


## 按文本形状、字号和可用宽度缓存测量；普通父节点下二分缩字号，Container 下维持基准字号并报告最小宽度。
func _refresh_metrics(font: Font, base_size: int, txt: String) -> void:
	# 换数字而不换位数/分隔符时可复用宽度；字体资源变化由 _watch_font 的 changed 另行失效。
	var key: String = "%s|%d|%d" % [_shape(txt), base_size, int(size.x)]
	if key == _cache_key and _fit_size > 0:
		return
	_cache_key = key

	var fs: int = base_size
	# 父容器应依据文本最小宽度分配空间；若这里又按它刚分配的宽度缩字，会形成相互影响。
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


## 把每个 ASCII 数字替换成 0，只保留位数和非数字布局；如 12:34 与 98:76 共用同一测量键。
func _shape(txt: String) -> String:
	var out: String = ""
	for i in txt.length():
		out += "0" if _is_digit(txt[i]) else txt[i]
	return out


## 更换字体时断开旧字体的 changed 信号，再订阅新字体；同一字体不重复连接。
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


## 字体资源内容变化时主动失效缓存，即使字号、文本形状和控件宽度都没有变化。
func _on_font_changed() -> void:
	_invalidate()


## 清除测量键与字号/槽宽缓存并请求重绘；整块宽度在下一次成功测量时更新。
func _invalidate() -> void:
	_cache_key = ""
	_fit_size = 0
	_slot_digit = 0.0
	queue_redraw()
