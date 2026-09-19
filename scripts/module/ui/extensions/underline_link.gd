# 下划线链接文字（@tool）：把翻译 key 包成 [u] 居中显示，并按控件宽度自动降字号
@tool
class_name UnderlineLink
extends RichTextLabel

const _BASE_FONT_SIZE: int = 48 # 基准字号（像素）
const _MIN_FONT_SIZE: int = 26 # 最小字号（像素）

# ---- 运行时状态 ----
var _font_size_cap: int = 0 # 外部设的字号上限；0 表示不限制（用基准字号）

# ---- Inspector 参数 ----
# 翻译 key（不是最终文案）
@export var text_key: String = "":
	set(value):
		text_key = value
		_refresh()


# 进树：开 bbcode、关滚动、立即刷新一次
func _ready() -> void:
	bbcode_enabled = true
	scroll_active = false
	_refresh()


# 语言变化或尺寸变化都要重新渲染
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()
	elif what == NOTIFICATION_RESIZED:
		_refresh()


# 外部限制字号上限（0 = 不限制）
func set_font_size_cap(cap: int) -> void:
	_font_size_cap = maxi(0, cap)
	_refresh()


# 只算不改：返回当前宽度下能用的字号，供外部对齐布局
func measure_fit_font_size() -> int:
	return _compute_fit(_BASE_FONT_SIZE)


# 刷新：包上 [center][u] 并把算好的字号写进 normal_font_size
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


# 从 upper 起每次减 2 找能塞进可用宽度的字号，最低降到 _MIN_FONT_SIZE（右边留 20 像素）
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
