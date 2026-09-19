# 自适应字号 Label（@tool）：用二分查找在 [最小字号, 基准字号] 里找「塞得进自身矩形」的最大字号
@tool
class_name AutoFitLabel
extends Label

# ---- Inspector 参数 ----
@export var max_font_size: int = 0: # 字号上限；0 表示用主题里的 font_size
	set(v): # setter：上限变了，缓存的基准字号作废并排一次重算
		max_font_size = v
		_base_font_size = 0
		_queue_refit()

@export var min_font_size: int = 12: # 字号下限，至少 1（默认 12）
	set(v): # setter：下限变了也排一次重算
		min_font_size = maxi(1, v)
		_queue_refit()

# ---- 运行时状态 ----
var _base_font_size: int = 0 # 缓存的基准（上限）字号；0 表示还没解析过

var _fitting: bool = false # 正在写 font_size 时的重入保护（写字号会触发 resized）
var _refit_queued: bool = false # 已排队标记：把同一帧的多次请求合并成一次 call_deferred


# ================= 生命周期 =================
# 进树：尺寸变化与首次排版都触发一次自适应
func _ready() -> void:
	resized.connect(_queue_refit)
	_queue_refit()


# 语言切换后文案变了，重新自适应
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_queue_refit()


# 拦截 text 赋值：改了文案就重新自适应（返回 false，不接管赋值）
func _set(property: StringName, value: Variant) -> bool:
	if property == &"text":
		_queue_refit()
	return false


# ================= 自适应入口 =================
# 立即重算一次（不排队）；外部改完文本可以手动调
func refit() -> void:
	_refit_queued = false
	_apply_fit()


# 合并式排队：同一帧内多次请求只延迟执行一次
func _queue_refit() -> void:
	if _refit_queued:
		return
	_refit_queued = true

	call_deferred("_deferred_refit")


# 延迟执行入口：确认请求还有效再算
func _deferred_refit() -> void:
	if not _refit_queued:
		return
	_refit_queued = false
	_apply_fit()


# ================= 核心算法 =================
# 核心：先定可用矩形与基准字号，再二分找能塞下的最大字号并写进主题覆盖
func _apply_fit() -> void:
	if _fitting or not is_inside_tree(): # 重入中、或还没进树：直接跳过
		return
	var box: Vector2 = _layout_box()
	if box.x <= 0.0 or box.y <= 0.0: # 还没有尺寸（布局没跑）时算不了
		return
	var display_text: String = _resolve_display_text()
	if display_text.is_empty():
		return
	var font: Font = get_theme_font(&"font")
	if font == null:
		return

	if _base_font_size <= 0:
		_base_font_size = max_font_size if max_font_size > 0 else get_theme_font_size(&"font_size") # 优先级：max_font_size > 0 就用它，否则用主题字号
	if _base_font_size <= 0:
		return

	var wrap: bool = autowrap_mode != TextServer.AUTOWRAP_OFF # 开了自动换行就得按换行后的高度判断，不能只量一行宽度

	var lo_fs: int = min(min_font_size, _base_font_size) # 二分：候选区间 [lo_fs, hi_fs]，fs 记录目前能塞下的最大字号
	var hi_fs: int = _base_font_size
	var fs: int = lo_fs
	while lo_fs <= hi_fs:
		var mid: int = (lo_fs + hi_fs) >> 1
		if _text_fits(font, display_text, box, mid, wrap):
			fs = mid
			lo_fs = mid + 1
		else:
			hi_fs = mid - 1

	_fitting = true
	add_theme_font_size_override(&"font_size", fs)
	_fitting = false


# 取真正要测量的文案（走翻译）；子类可覆写
func _resolve_display_text() -> String:
	return atr(text)


# 用锚点 + 偏移自己算可用矩形，不依赖 size（布局可能还没跑）
func _layout_box() -> Vector2:
	var parent_size: Vector2 = Vector2.ZERO
	var pc := get_parent() as Control
	if pc != null:
		parent_size = pc.size
	var w: float = (anchor_right - anchor_left) * parent_size.x + (offset_right - offset_left)
	var h: float = (anchor_bottom - anchor_top) * parent_size.y + (offset_bottom - offset_top)
	return Vector2(w, h)


# 判断某字号塞不塞得下：换行时用隐藏探针量高度，不换行时直接量文本尺寸
func _text_fits(font: Font, txt: String, box: Vector2, fs: int, wrap: bool) -> bool:
	if wrap:
		var probe: Label = _ensure_probe()
		probe.add_theme_font_override(&"font", font)
		probe.add_theme_font_size_override(&"font_size", fs)
		probe.add_theme_constant_override(&"line_spacing", get_theme_constant(&"line_spacing"))
		probe.autowrap_mode = autowrap_mode
		probe.text = txt
		probe.size = Vector2(box.x, 1.0)
		probe.update_minimum_size()
		if probe.get_minimum_size().y > box.y:
			return false

		if autowrap_mode == TextServer.AUTOWRAP_WORD: # AUTOWRAP_WORD 下还要确认没有单个单词比框还宽
			for word: String in txt.split(" ", false):
				if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x > box.x:
					return false
		return true
	var s: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	return s.x <= box.x and s.y <= box.y


# ---- 测量用隐藏节点 ----
var _probe: Label = null # 隐藏探针 Label：挂在自身下、扔到屏幕外，只用来量文本


# 惰性创建 / 复用探针
func _ensure_probe() -> Label:
	if _probe != null and is_instance_valid(_probe) and _probe.get_parent() == self:
		return _probe
	_probe = Label.new()
	_probe.name = &"_AutoFitProbe"
	_probe.visible = false
	_probe.top_level = true
	_probe.position = Vector2(-100000.0, -100000.0)
	add_child(_probe)
	return _probe


# 出树时释放探针
func _exit_tree() -> void:
	if _probe != null and is_instance_valid(_probe):
		_probe.queue_free()
		_probe = null
