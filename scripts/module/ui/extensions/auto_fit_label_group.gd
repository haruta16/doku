@tool
class_name AutoFitLabelGroup
extends VBoxContainer

@export var base_font_size: int = 0:
	set(v):
		base_font_size = v
		_resolved_base = 0
		_queue_fit()

@export var min_font_size: int = 38:
	set(v):
		min_font_size = maxi(1, v)
		_queue_fit()

@export var height_budget: float = 0.0:
	set(v):
		height_budget = v
		_queue_fit()

var _resolved_base: int = 0

var _fitting: bool = false
var _fit_queued: bool = false

var _probe: Label = null


func _ready() -> void:
	_queue_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_queue_fit()


func refit() -> void:
	_fit_queued = false
	_apply_fit()


func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true

	call_deferred("_deferred_fit")


func _deferred_fit() -> void:
	if not _fit_queued:
		return
	_fit_queued = false
	_apply_fit()


func _apply_fit() -> void:
	if _fitting or not is_inside_tree():
		return
	var labels: Array[Node] = find_children("*", "Label", true, false)
	labels = labels.filter(func(n: Node) -> bool: return n != _probe)
	if labels.is_empty():
		return

	if _resolved_base <= 0:
		var first := labels[0] as Label
		_resolved_base = (
			base_font_size if base_font_size > 0 else first.get_theme_font_size(&"font_size")
		)
	if _resolved_base <= 0:
		return

	var budget: float = height_budget if height_budget > 0.0 else (offset_bottom - offset_top)
	if budget <= 0.0:
		return

	var lo: int = min(min_font_size, _resolved_base)
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


func _group_fits(labels: Array[Node], fs: int, budget: float) -> bool:
	var sep: int = get_theme_constant(&"separation")
	var total: float = float(sep * maxi(0, labels.size() - 1))
	for n in labels:
		total += _measure_label_height(n as Label, fs)
		if total > budget:
			return false
	return true


func _measure_label_height(label: Label, fs: int) -> float:
	var font: Font = label.get_theme_font(&"font")
	if font == null:
		return 0.0

	var wrap_w: float = label.size.x if label.size.x > 1.0 else label.custom_minimum_size.x
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


func _exit_tree() -> void:
	if _probe != null and is_instance_valid(_probe):
		_probe.queue_free()
		_probe = null
