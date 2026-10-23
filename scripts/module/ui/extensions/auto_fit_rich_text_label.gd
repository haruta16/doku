## 富文本自适应：测量带格式文本的宽高，调整字号以适应当前区域。
@tool
class_name AutoFitRichTextLabel
extends RichTextLabel

@export var max_font_size: int = 0:
	set(v):
		max_font_size = v
		_base_font_size = 0
		_queue_refit()

@export var min_font_size: int = 12:
	set(v):
		min_font_size = maxi(1, v)
		_queue_refit()

@export var max_content_height: float = 0.0:
	set(v):
		max_content_height = maxf(0.0, v)
		_queue_refit()

var _base_font_size: int = 0
var _fitting: bool = false
var _refit_queued: bool = false
var _probe: RichTextLabel = null

var _source_text: String = ""

var _font_size_re: RegEx = null


func _ready() -> void:
	bbcode_enabled = true
	fit_content = true
	grow_vertical = Control.GROW_DIRECTION_BOTH
	scroll_active = false
	if not resized.is_connected(_queue_refit):
		resized.connect(_queue_refit)
	_queue_refit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_queue_refit()


func _set(property: StringName, value: Variant) -> bool:
	if property == &"text":
		if _fitting:
			return false
		_source_text = str(value)
		_queue_refit()
	return false


func refit() -> void:
	_refit_queued = false
	_apply_fit()


func _queue_refit() -> void:
	if _refit_queued:
		return
	_refit_queued = true
	call_deferred("_deferred_refit")


func _deferred_refit() -> void:
	if not _refit_queued:
		return
	_refit_queued = false
	_apply_fit()


func _apply_fit() -> void:
	if _fitting or not is_inside_tree():
		return

	var src: String = _source_text if not _source_text.is_empty() else text
	if src.is_empty():
		return
	if _base_font_size <= 0:
		_base_font_size = (
			max_font_size if max_font_size > 0 else get_theme_font_size(&"normal_font_size")
		)
	if _base_font_size <= 0:
		return
	var has_inline: bool = src.contains("[font_size=")

	if max_content_height <= 0.0:
		_fitting = true
		add_theme_font_size_override(&"normal_font_size", _base_font_size)
		if has_inline and text != src:
			text = src
		_fitting = false
		return
	var width: float = _content_width()
	if width <= 0.0:
		return

	var lo: int = min(min_font_size, _base_font_size)
	var hi: int = _base_font_size
	var fs: int = lo
	while lo <= hi:
		var mid: int = (lo + hi) >> 1
		if _fits(width, _scaled_text(src, mid), mid):
			fs = mid
			lo = mid + 1
		else:
			hi = mid - 1
	_fitting = true
	add_theme_font_size_override(&"normal_font_size", fs)
	if has_inline:
		text = _scaled_text(src, fs)
	_fitting = false


func _scaled_text(src: String, fs: int) -> String:
	if fs == _base_font_size or _base_font_size <= 0 or not src.contains("[font_size="):
		return src
	var r: float = float(fs) / float(_base_font_size)
	var re: RegEx = _ensure_font_size_re()
	var out: String = ""
	var last: int = 0
	for m: RegExMatch in re.search_all(src):
		out += src.substr(last, m.get_start() - last)
		out += "[font_size=%d]" % maxi(1, int(round(float(int(m.get_string(1))) * r)))
		last = m.get_end()
	out += src.substr(last)
	return out


func _ensure_font_size_re() -> RegEx:
	if _font_size_re == null:
		_font_size_re = RegEx.new()
		_font_size_re.compile("\\[font_size=(\\d+)\\]")
	return _font_size_re


func _content_width() -> float:
	var parent_size: Vector2 = Vector2.ZERO
	var pc := get_parent() as Control
	if pc != null:
		parent_size = pc.size
	return (anchor_right - anchor_left) * parent_size.x + (offset_right - offset_left)


func _fits(width: float, measure_text: String, fs: int) -> bool:
	var p := _ensure_probe()
	var nf := get_theme_font(&"normal_font")
	if nf != null:
		p.add_theme_font_override(&"normal_font", nf)
	p.add_theme_font_size_override(&"normal_font_size", fs)
	p.add_theme_constant_override(&"line_separation", get_theme_constant(&"line_separation"))
	p.size = Vector2(width, 1.0)
	p.text = measure_text
	return p.get_content_height() <= max_content_height


var _PROBE_NAME: StringName = &"_AutoFitRTLProbe"


func _ensure_probe() -> RichTextLabel:
	if _probe != null and is_instance_valid(_probe) and _probe.get_parent() == self:
		return _probe
	_probe = RichTextLabel.new()
	_probe.name = _PROBE_NAME
	_probe.bbcode_enabled = true
	_probe.fit_content = true
	_probe.scroll_active = false
	_probe.visible = false
	_probe.top_level = true
	_probe.position = Vector2(-100000.0, -100000.0)
	add_child(_probe)
	return _probe


func _exit_tree() -> void:
	if _probe != null and is_instance_valid(_probe):
		_probe.queue_free()
		_probe = null
