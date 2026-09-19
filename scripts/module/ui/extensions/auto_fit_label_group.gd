# 自适应字号的 VBox 组（@tool）：让组内所有 Label 共用同一个字号，整体高度塞进预算
@tool
class_name AutoFitLabelGroup
extends VBoxContainer

# ---- Inspector 参数 ----
@export var base_font_size: int = 0: # 字号上限；0 表示取第一个 Label 的主题字号
	set(v):
		base_font_size = v
		_resolved_base = 0
		_queue_fit()

@export var min_font_size: int = 38: # 字号下限（默认 38）
	set(v):
		min_font_size = maxi(1, v)
		_queue_fit()

@export var height_budget: float = 0.0: # 整组高度预算（像素）；0 表示用自身高度 offset_bottom - offset_top
	set(v):
		height_budget = v
		_queue_fit()

# ---- 运行时状态 ----
var _resolved_base: int = 0 # 解析后的上限字号缓存；0 表示还没解析

var _fitting: bool = false # 写字号覆盖时的重入保护
var _fit_queued: bool = false # 延迟合并标记

var _probe: Label = null # 隐藏探针 Label，用来量每个 Label 的高度


# ================= 生命周期 =================
# 进树后先排一次自适应
func _ready() -> void:
	_queue_fit()


# 语言切换后文案变化，重新算
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_queue_fit()


# ================= 自适应入口 =================
# 立即重算一次（外部也可以手动调）
func refit() -> void:
	_fit_queued = false
	_apply_fit()


# 合并式排队：同一帧多次请求只算一次
func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true

	call_deferred("_deferred_fit")


# 延迟执行入口：确认请求还有效再算
func _deferred_fit() -> void:
	if not _fit_queued:
		return
	_fit_queued = false
	_apply_fit()


# ================= 核心算法 =================
# 核心：收集组内 Label，二分找「所有 Label 高度 + 间距」不超预算的最大字号，再统一写入
func _apply_fit() -> void:
	if _fitting or not is_inside_tree():
		return
	var labels: Array[Node] = find_children("*", "Label", true, false) # 递归收集所有 Label 后代
	labels = labels.filter(func(n: Node) -> bool: return n != _probe) # 排除自己的探针
	if labels.is_empty():
		return

	if _resolved_base <= 0:
		var first := labels[0] as Label
		_resolved_base = (
			base_font_size if base_font_size > 0 else first.get_theme_font_size(&"font_size")
		)
	if _resolved_base <= 0:
		return

	var budget: float = height_budget if height_budget > 0.0 else (offset_bottom - offset_top) # 预算优先用导出值，否则用自身高度
	if budget <= 0.0:
		return

	var lo: int = min(min_font_size, _resolved_base) # 二分：候选区间 [lo, hi]，fs 记录目前能塞下的最大字号
	var hi: int = _resolved_base
	var fs: int = lo
	while lo <= hi:
		var mid: int = (lo + hi) >> 1
		if _group_fits(labels, mid, budget):
			fs = mid
			lo = mid + 1
		else:
			hi = mid - 1

	_fitting = true
	for n in labels:
		(n as Label).add_theme_font_size_override(&"font_size", fs)
	_fitting = false


# 试算：该字号下所有 Label 高度加 separation 的总和是否不超过预算
func _group_fits(labels: Array[Node], fs: int, budget: float) -> bool:
	var sep: int = get_theme_constant(&"separation")
	var total: float = float(sep * maxi(0, labels.size() - 1))
	for n in labels:
		total += _measure_label_height(n as Label, fs)
		if total > budget:
			return false
	return true


# 用探针按这个 Label 的换行宽度，量出它在指定字号下的高度
func _measure_label_height(label: Label, fs: int) -> float:
	var font: Font = label.get_theme_font(&"font")
	if font == null:
		return 0.0

	var wrap_w: float = label.size.x if label.size.x > 1.0 else label.custom_minimum_size.x # 换行宽度优先用实际宽度，还没布局时退到 custom_minimum_size
	if wrap_w <= 0.0:
		wrap_w = 1.0
	var probe := _ensure_probe()
	probe.add_theme_font_override(&"font", font)
	probe.add_theme_font_size_override(&"font_size", fs)
	probe.add_theme_constant_override(&"line_spacing", label.get_theme_constant(&"line_spacing"))
	probe.autowrap_mode = label.autowrap_mode

	probe.text = atr(label.text)
	probe.size = Vector2(wrap_w, 1.0)
	probe.update_minimum_size()
	return probe.get_minimum_size().y


# 惰性创建 / 复用探针
func _ensure_probe() -> Label:
	if _probe != null and is_instance_valid(_probe) and _probe.get_parent() == self:
		return _probe
	_probe = Label.new()
	_probe.name = &"_AutoFitGroupProbe"
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
