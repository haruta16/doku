## 富文本自适应：在给定宽度下测量 BBCode 内容高度，缩小字号以满足显式高度预算。
@tool
class_name AutoFitRichTextLabel
extends RichTextLabel

@export var max_font_size: int = 0: # 基准字号上限；0 表示读取主题 normal_font_size
	set(v):
		max_font_size = v
		_base_font_size = 0
		_queue_refit()

@export var min_font_size: int = 12: # 允许缩小到的最低字号，至少为 1
	set(v):
		min_font_size = maxi(1, v)
		_queue_refit()

@export var max_content_height: float = 0.0: # 内容高度预算（像素）；0 关闭缩小并恢复基准字号
	set(v):
		max_content_height = maxf(0.0, v)
		_queue_refit()

var _base_font_size: int = 0 # 本轮字号上限缓存；改变 max_font_size 时失效
var _fitting: bool = false # 本类回写字号/文本期间置 true，避免把缩放结果记成新的原文
var _refit_queued: bool = false # 是否已有尚未消费的延迟测量请求
var _probe: RichTextLabel = null # 隐藏排版探针；由当前节点持有和释放

var _source_text: String = "" # 调用方最近一次提供的原始 BBCode，保留各片段字号之间的比例

var _font_size_re: RegEx = null # 匹配 [font_size=整数] 的惰性正则缓存


## 启用 BBCode 和内容撑高，关闭内部滚动；尺寸变化后合并安排自适应。
func _ready() -> void:
	bbcode_enabled = true
	fit_content = true
	grow_vertical = Control.GROW_DIRECTION_BOTH
	scroll_active = false
	if not resized.is_connected(_queue_refit):
		resized.connect(_queue_refit)
	_queue_refit()


## 语言切换时排队重新测量；适配仍经过原文与隐藏富文本探针的同一条流程。
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_queue_refit()


## 记录调用方设置的原始 text；本类缩放 BBCode 时不反向覆盖原文，返回 false 让引擎继续赋值。
func _set(property: StringName, value: Variant) -> bool:
	if property == &"text":
		if _fitting:
			return false
		_source_text = str(value)
		_queue_refit()
	return false


## 清除排队标记并立即测量；尚未进树或正在回写时由计算入口拒绝重入。
func refit() -> void:
	_refit_queued = false
	_apply_fit()


## 把同一轮属性变化合并为一个延迟请求，等布局尺寸更新后再测量。
func _queue_refit() -> void:
	if _refit_queued:
		return
	_refit_queued = true
	call_deferred("_deferred_refit")


## 消费仍有效的排队请求；已被立即 refit 消费时不重复执行。
func _deferred_refit() -> void:
	if not _refit_queued:
		return
	_refit_queued = false
	_apply_fit()


## 按可用宽度和高度预算二分选择字号，并按比例缩放原文中的 [font_size]。
## 高度预算为 0 时恢复基准字号与原始字号标签；最小字号放不下时也不会继续缩小。
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
	# 单改 normal_font_size 不会缩小正文中显式指定字号的片段，因此两种字号需一起处理。
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

	# 每个候选字号都重新生成测量用 BBCode；隐藏探针的换行结果决定能否继续放大。
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


## 以原文为基准按比例改写数字形式的 [font_size=N]，保留其余 BBCode 和正文。
## 每次从 src 计算，避免对上一次缩小后的字符串再次缩小而产生累计误差。
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


## 惰性创建并复用字号标签正则；只识别非负整数字号，不负责解析全部 BBCode。
func _ensure_font_size_re() -> RegEx:
	if _font_size_re == null:
		_font_size_re = RegEx.new()
		_font_size_re.compile("\\[font_size=(\\d+)\\]")
	return _font_size_re


## 用父控件尺寸、横向锚点与偏移推算测量宽度，不依赖内容撑高后的自身尺寸。
func _content_width() -> float:
	var parent_size: Vector2 = Vector2.ZERO
	var pc := get_parent() as Control
	if pc != null:
		parent_size = pc.size
	return (anchor_right - anchor_left) * parent_size.x + (offset_right - offset_left)


## 让隐藏富文本探针使用同样字体、字号、行距和宽度，判断实际内容高度是否在预算内。
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


var _PROBE_NAME: StringName = &"_AutoFitRTLProbe" # 仅用于识别内部探针节点，不是产品场景路径


## 惰性创建并复用隐藏 RichTextLabel；真实富文本排版交给引擎，探针作为本节点子节点管理。
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


## 离树时释放测量探针并清引用，重新进入时可按需创建。
func _exit_tree() -> void:
	if _probe != null and is_instance_valid(_probe):
		_probe.queue_free()
		_probe = null
