@tool
extends Node
class_name BoardContainerCell_01

enum ActiveGroup { NONE, GROUP_3 }

signal animation_finished

@export_group("目标 Target")
@export var board_view: Node:
	set(v):
		_disconnect_board_signals()
		board_view = v
		if not Engine.is_editor_hint() and auto_play:
			_connect_board_signals()

@export var auto_play: bool = true

@export var active_group: ActiveGroup = ActiveGroup.GROUP_3

@export_group("预览 Preview")
@export_tool_button("▶  Play") var _play_btn: Callable = func(): play()
@export_tool_button("↩  Reset") var _reset_btn: Callable = func(): reset()

@export_group("Group 3")

@export_subgroup("预设 Preset")
@export_file("*.cfg") var g3_preset_path: String = "":
	set(v):
		g3_preset_path = v.get_file() if not v.is_empty() else ""
@export_tool_button("📂 从预设加载") var _load_g3: Callable = func(): _load_from_file()

@export_subgroup("父级 — 通用")
@export var g3_list_delay: float = 0.0

@export_subgroup("父级 — 透明度 Alpha")
@export var g3_container_fade_enabled: bool = false
@export var g3_container_fade_duration: float = 0.5
@export var g3_container_fade_ease: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g3_container_fade_custom_curve: Curve

@export_subgroup("父级 — 缩放 Scale")
@export var g3_scale_enabled: bool = false
@export var g3_scale_duration: float = 0.5
@export var g3_scale_from: float = 0.85
@export var g3_scale_curve: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.BACK_OUT
@export var g3_scale_custom_curve: Curve

@export_subgroup("父级 — 位移 Translation")
@export var g3_translation_enabled: bool = false
@export var g3_translation_duration: float = 0.5
@export var g3_translation_offset_x: float = 0.0
@export var g3_translation_offset_y: float = 0.0
@export var g3_translation_curve_x: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g3_translation_custom_curve_x: Curve
@export var g3_translation_curve_y: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g3_translation_custom_curve_y: Curve

@export_subgroup("子集 — 通用")

@export var g3_diag_interval: float = 0.12

@export_subgroup("子集 — 透明度 Alpha")
@export var g3_cell_fade_duration: float = 0.3
@export var g3_fade_ease: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.SINE_OUT
@export var g3_fade_custom_curve: Curve

@export_subgroup("子集 — 缩放 Scale")
@export var g3_cell_scale_enabled: bool = false
@export var g3_cell_scale_duration: float = 0.3
@export var g3_cell_scale_from: float = 0.7
@export var g3_cell_scale_curve: AutoAnimCurve.EaseType = AutoAnimCurve.EaseType.BACK_OUT
@export var g3_cell_scale_custom_curve: Curve

@export_subgroup("应用")
@export_tool_button("💾 应用设置") var _apply_btn: Callable = func(): _apply_settings()
@export_tool_button("💾 应用设置(序号)") var _apply_n_btn: Callable = func(): _apply_settings_numbered()

const _PRESET_DIR := "res://assets/effect/effectscripts/AnimationTool/Script/BoardContainerCell_01"

var _cells: Array = []
var _rings: Array = []
var _elapsed: float = 0.0
var _origin_pos: Vector2 = Vector2.ZERO
var _param_hash: int = -1
var _play_scheduled: bool = false

var _animation_finished_emitted: bool = false


func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint():
		return
	_pre_hide_board()
	if auto_play:
		_connect_board_signals()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		var h := _get_param_hash()
		if h != _param_hash:
			play()
			return

	if active_group == ActiveGroup.NONE:
		set_process(false)
		return

	_elapsed += delta

	var fade_done := true
	var cell_scale_done := true
	for i in _cells.size():
		var cell: CanvasItem = _cells[i]
		if not is_instance_valid(cell):
			continue
		var t_start: float = g3_list_delay + _rings[i] * g3_diag_interval

		if _elapsed < t_start + g3_cell_fade_duration:
			fade_done = false
		var fp := clampf((_elapsed - t_start) / maxf(g3_cell_fade_duration, 0.001), 0.0, 1.0)
		_set_alpha(cell, _ease_t(fp, g3_fade_ease, g3_fade_custom_curve))

		if g3_cell_scale_enabled:
			if _elapsed < t_start + g3_cell_scale_duration:
				cell_scale_done = false
			var sp := clampf((_elapsed - t_start) / maxf(g3_cell_scale_duration, 0.001), 0.0, 1.0)
			var s := lerpf(
				g3_cell_scale_from,
				1.0,
				_ease_t(sp, g3_cell_scale_curve, g3_cell_scale_custom_curve)
			)
			_set_scale(cell, Vector2(s, s))

	var container_fade_done := true
	if g3_container_fade_enabled and board_view and is_instance_valid(board_view):
		var cf_el := maxf(_elapsed - g3_list_delay, 0.0)
		container_fade_done = cf_el >= g3_container_fade_duration
		var cfp := clampf(cf_el / maxf(g3_container_fade_duration, 0.001), 0.0, 1.0)
		_set_alpha(
			board_view as CanvasItem,
			_ease_t(cfp, g3_container_fade_ease, g3_container_fade_custom_curve)
		)

	var scale_done := true
	if g3_scale_enabled and board_view and is_instance_valid(board_view):
		var s_el := maxf(_elapsed - g3_list_delay, 0.0)
		scale_done = s_el >= g3_scale_duration
		var ts := clampf(s_el / maxf(g3_scale_duration, 0.001), 0.0, 1.0)
		var s := lerpf(g3_scale_from, 1.0, _ease_t(ts, g3_scale_curve, g3_scale_custom_curve))
		_set_scale(board_view, Vector2(s, s))

	var translation_done := true
	if g3_translation_enabled and board_view and is_instance_valid(board_view):
		var t_el := maxf(_elapsed - g3_list_delay, 0.0)
		translation_done = t_el >= g3_translation_duration
		var tx := clampf(t_el / maxf(g3_translation_duration, 0.001), 0.0, 1.0)
		_set_position(
			board_view,
			Vector2(
				lerpf(
					_origin_pos.x + g3_translation_offset_x,
					_origin_pos.x,
					_ease_t(tx, g3_translation_curve_x, g3_translation_custom_curve_x)
				),
				lerpf(
					_origin_pos.y + g3_translation_offset_y,
					_origin_pos.y,
					_ease_t(tx, g3_translation_curve_y, g3_translation_custom_curve_y)
				)
			)
		)

	if (
		not _animation_finished_emitted
		and fade_done
		and container_fade_done
		and scale_done
		and translation_done
	):
		_animation_finished_emitted = true
		animation_finished.emit()

	if fade_done and cell_scale_done and container_fade_done and scale_done and translation_done:
		set_process(false)


func set_auto_trigger(enabled: bool) -> void:
	if Engine.is_editor_hint():
		return
	if enabled:
		_connect_board_signals()
	else:
		_disconnect_board_signals()


func play() -> void:
	_animation_finished_emitted = false
	if active_group == ActiveGroup.NONE:
		_animation_finished_emitted = true
		animation_finished.emit()
		return
	_build_cells()
	if _cells.is_empty():
		push_warning("BoardContainerCell_01.play(): board_view 子树中无 CellView 节点。")
		_animation_finished_emitted = true
		animation_finished.emit()
		return
	_param_hash = _get_param_hash()
	if board_view and is_instance_valid(board_view):
		_origin_pos = _get_position(board_view)
	for cell in _cells:
		if not is_instance_valid(cell):
			continue
		_set_alpha(cell, 0.0)
		if g3_cell_scale_enabled:
			_set_scale(cell, Vector2(g3_cell_scale_from, g3_cell_scale_from))
	if board_view and is_instance_valid(board_view) and board_view is CanvasItem:
		_set_alpha(board_view as CanvasItem, 0.0 if g3_container_fade_enabled else 1.0)
	if g3_scale_enabled and board_view and is_instance_valid(board_view):
		_center_pivot(board_view)
		_set_scale(board_view, Vector2(g3_scale_from, g3_scale_from))
	if g3_translation_enabled and board_view and is_instance_valid(board_view):
		_set_position(
			board_view, _origin_pos + Vector2(g3_translation_offset_x, g3_translation_offset_y)
		)
	_elapsed = 0.0
	set_process(true)


func reset() -> void:
	set_process(false)
	_build_cells()
	for cell in _cells:
		if not is_instance_valid(cell):
			continue
		_set_alpha(cell, 1.0)
		if g3_cell_scale_enabled:
			_set_scale(cell, Vector2.ONE)
	if board_view and is_instance_valid(board_view) and board_view is CanvasItem:
		_set_alpha(board_view as CanvasItem, 1.0)
		_set_scale(board_view, Vector2.ONE)
		_set_position(board_view, _origin_pos)


func _apply_settings() -> void:
	if active_group == ActiveGroup.NONE:
		push_warning("BoardContainerCell_01._apply_settings(): active_group 为 NONE。")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_PRESET_DIR))
	var fname := (
		g3_preset_path if not g3_preset_path.is_empty() else "BoardContainerCell_01_Group3.cfg"
	)
	_save_cfg(fname)


func _apply_settings_numbered() -> void:
	if active_group == ActiveGroup.NONE:
		push_warning("BoardContainerCell_01._apply_settings_numbered(): active_group 为 NONE。")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_PRESET_DIR))
	var next_n := 1
	var dir := DirAccess.open(_PRESET_DIR)
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.begins_with("BoardContainerCell_01_Group3_") and f.ends_with(".cfg"):
				var num_str := f.trim_prefix("BoardContainerCell_01_Group3_").trim_suffix(".cfg")
				if num_str.is_valid_int():
					next_n = max(next_n, num_str.to_int() + 1)
			f = dir.get_next()
		dir.list_dir_end()
	_save_cfg("BoardContainerCell_01_Group3_%03d.cfg" % next_n)


func _save_cfg(fname: String) -> void:
	var s := "Group3"
	var cfg := ConfigFile.new()
	cfg.set_value(s, "list_delay", g3_list_delay)
	cfg.set_value(s, "container_fade_enabled", g3_container_fade_enabled)
	cfg.set_value(s, "container_fade_duration", g3_container_fade_duration)
	cfg.set_value(s, "container_fade_ease", int(g3_container_fade_ease))
	cfg.set_value(s, "scale_enabled", g3_scale_enabled)
	cfg.set_value(s, "scale_duration", g3_scale_duration)
	cfg.set_value(s, "scale_from", g3_scale_from)
	cfg.set_value(s, "scale_curve", int(g3_scale_curve))
	cfg.set_value(s, "translation_enabled", g3_translation_enabled)
	cfg.set_value(s, "translation_duration", g3_translation_duration)
	cfg.set_value(s, "translation_offset_x", g3_translation_offset_x)
	cfg.set_value(s, "translation_offset_y", g3_translation_offset_y)
	cfg.set_value(s, "translation_curve_x", int(g3_translation_curve_x))
	cfg.set_value(s, "translation_curve_y", int(g3_translation_curve_y))
	cfg.set_value(s, "diag_interval", g3_diag_interval)
	cfg.set_value(s, "cell_fade_duration", g3_cell_fade_duration)
	cfg.set_value(s, "fade_ease", int(g3_fade_ease))
	cfg.set_value(s, "cell_scale_enabled", g3_cell_scale_enabled)
	cfg.set_value(s, "cell_scale_duration", g3_cell_scale_duration)
	cfg.set_value(s, "cell_scale_from", g3_cell_scale_from)
	cfg.set_value(s, "cell_scale_curve", int(g3_cell_scale_curve))

	var base := fname.trim_suffix(".cfg")
	_cfg_save_curve(cfg, s, base, "container_fade_custom_curve", g3_container_fade_custom_curve)
	_cfg_save_curve(cfg, s, base, "scale_custom_curve", g3_scale_custom_curve)
	_cfg_save_curve(cfg, s, base, "translation_custom_curve_x", g3_translation_custom_curve_x)
	_cfg_save_curve(cfg, s, base, "translation_custom_curve_y", g3_translation_custom_curve_y)
	_cfg_save_curve(cfg, s, base, "fade_custom_curve", g3_fade_custom_curve)
	_cfg_save_curve(cfg, s, base, "cell_scale_custom_curve", g3_cell_scale_custom_curve)
	var save_path := _PRESET_DIR + "/" + fname
	var err := cfg.save(save_path)
	if err == OK:
		g3_preset_path = fname
		print("BoardContainerCell_01: 参数已保存至 %s" % save_path)
	else:
		push_error("BoardContainerCell_01: 保存失败，错误码 %d" % err)


func _load_from_file() -> void:
	if g3_preset_path.is_empty():
		push_warning("BoardContainerCell_01: 请先在「预设 Preset」中填写文件名。")
		return
	var full_path := _PRESET_DIR + "/" + g3_preset_path
	var cfg := ConfigFile.new()
	var err := cfg.load(full_path)
	if err != OK:
		push_error("BoardContainerCell_01: 加载预设失败（错误码 %d）：%s" % [err, full_path])
		return
	var s := "Group3"
	g3_list_delay = cfg.get_value(s, "list_delay", g3_list_delay)
	g3_container_fade_enabled = cfg.get_value(
		s, "container_fade_enabled", g3_container_fade_enabled
	)
	g3_container_fade_duration = cfg.get_value(
		s, "container_fade_duration", g3_container_fade_duration
	)
	g3_container_fade_ease = (
		cfg.get_value(s, "container_fade_ease", int(g3_container_fade_ease))
		as AutoAnimCurve.EaseType
	)
	g3_scale_enabled = cfg.get_value(s, "scale_enabled", g3_scale_enabled)
	g3_scale_duration = cfg.get_value(s, "scale_duration", g3_scale_duration)
	g3_scale_from = cfg.get_value(s, "scale_from", g3_scale_from)
	g3_scale_curve = cfg.get_value(s, "scale_curve", int(g3_scale_curve)) as AutoAnimCurve.EaseType
	g3_translation_enabled = cfg.get_value(s, "translation_enabled", g3_translation_enabled)
	g3_translation_duration = cfg.get_value(s, "translation_duration", g3_translation_duration)
	g3_translation_offset_x = cfg.get_value(s, "translation_offset_x", g3_translation_offset_x)
	g3_translation_offset_y = cfg.get_value(s, "translation_offset_y", g3_translation_offset_y)
	g3_translation_curve_x = (
		cfg.get_value(s, "translation_curve_x", int(g3_translation_curve_x))
		as AutoAnimCurve.EaseType
	)
	g3_translation_curve_y = (
		cfg.get_value(s, "translation_curve_y", int(g3_translation_curve_y))
		as AutoAnimCurve.EaseType
	)
	g3_diag_interval = cfg.get_value(s, "diag_interval", g3_diag_interval)
	g3_cell_fade_duration = cfg.get_value(s, "cell_fade_duration", g3_cell_fade_duration)
	g3_fade_ease = cfg.get_value(s, "fade_ease", int(g3_fade_ease)) as AutoAnimCurve.EaseType
	g3_cell_scale_enabled = cfg.get_value(s, "cell_scale_enabled", g3_cell_scale_enabled)
	g3_cell_scale_duration = cfg.get_value(s, "cell_scale_duration", g3_cell_scale_duration)
	g3_cell_scale_from = cfg.get_value(s, "cell_scale_from", g3_cell_scale_from)
	g3_cell_scale_curve = (
		cfg.get_value(s, "cell_scale_curve", int(g3_cell_scale_curve)) as AutoAnimCurve.EaseType
	)

	g3_container_fade_custom_curve = _cfg_load_curve(
		cfg, s, "container_fade_custom_curve", g3_container_fade_custom_curve
	)
	g3_scale_custom_curve = _cfg_load_curve(cfg, s, "scale_custom_curve", g3_scale_custom_curve)
	g3_translation_custom_curve_x = _cfg_load_curve(
		cfg, s, "translation_custom_curve_x", g3_translation_custom_curve_x
	)
	g3_translation_custom_curve_y = _cfg_load_curve(
		cfg, s, "translation_custom_curve_y", g3_translation_custom_curve_y
	)
	g3_fade_custom_curve = _cfg_load_curve(cfg, s, "fade_custom_curve", g3_fade_custom_curve)
	g3_cell_scale_custom_curve = _cfg_load_curve(
		cfg, s, "cell_scale_custom_curve", g3_cell_scale_custom_curve
	)
	notify_property_list_changed()
	print("BoardContainerCell_01: 已从预设加载 %s" % full_path)


func _connect_board_signals() -> void:
	if not board_view or not is_instance_valid(board_view):
		return
	_connect_one(board_view)
	for child in board_view.get_children():
		_connect_one(child)


func _disconnect_board_signals() -> void:
	if not board_view or not is_instance_valid(board_view):
		return
	_disconnect_one(board_view)
	for child in board_view.get_children():
		_disconnect_one(child)


func _connect_one(node: Node) -> void:
	if (
		node
		and is_instance_valid(node)
		and not node.child_order_changed.is_connected(_on_board_changed)
	):
		node.child_order_changed.connect(_on_board_changed)


func _disconnect_one(node: Node) -> void:
	if (
		node
		and is_instance_valid(node)
		and node.child_order_changed.is_connected(_on_board_changed)
	):
		node.child_order_changed.disconnect(_on_board_changed)


func _on_board_changed() -> void:
	if not Engine.is_editor_hint() and auto_play and active_group != ActiveGroup.NONE:
		_pre_hide_board()
	if _play_scheduled:
		return
	_play_scheduled = true
	call_deferred("_deferred_try_play")


func _deferred_try_play() -> void:
	_play_scheduled = false
	var n: int = _count_cells()
	if n > 0:
		play()


func _count_cells() -> int:
	if not board_view or not is_instance_valid(board_view):
		return 0
	var result: Array = []
	_collect_cells_recursive(board_view, result)
	return result.size()


func _build_cells() -> void:
	_cells.clear()
	_rings.clear()
	if not board_view or not is_instance_valid(board_view):
		return
	var cell_list: Array = []
	_collect_cells_recursive(board_view, cell_list)
	var count := cell_list.size()
	if count == 0:
		return
	var n := int(round(sqrt(float(count))))
	if n * n != count:
		push_warning("BoardContainerCell_01: 格子数 %d 不是完全平方数。" % count)
		return
	for i in count:
		_cells.append(cell_list[i] as CanvasItem)

	_cells.sort_custom(
		func(a: CanvasItem, b: CanvasItem) -> bool:
			var pa: Vector2 = _get_position(a)
			var pb: Vector2 = _get_position(b)
			if absf(pa.y - pb.y) > 1.0:
				return pa.y < pb.y
			return pa.x < pb.x
	)

	for i in count:
		var r: int = i / n
		var c: int = i % n
		_rings.append(c + (n - 1 - r))

	var extras_provider: Node = _find_extras_provider(board_view)
	if extras_provider != null:
		var extras: Array = extras_provider.call("get_intro_extra_nodes", n)
		for entry in extras:
			var node: CanvasItem = entry.get("node") as CanvasItem
			if node != null and is_instance_valid(node):
				_cells.append(node)
				_rings.append(int(entry.get("ring", 0)))


func _find_extras_provider(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if node.has_method("get_intro_extra_nodes"):
		return node
	for child in node.get_children():
		var found: Node = _find_extras_provider(child)
		if found != null:
			return found
	return null


func _collect_cells_recursive(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child is CellView:
			result.append(child)
		else:
			_collect_cells_recursive(child, result)


func _get_param_hash() -> int:
	if active_group == ActiveGroup.NONE:
		return hash([0])
	return hash(
		[
			g3_list_delay,
			g3_diag_interval,
			g3_cell_fade_duration,
			int(g3_fade_ease),
			g3_cell_scale_enabled,
			g3_cell_scale_duration,
			g3_cell_scale_from,
			int(g3_cell_scale_curve),
			g3_container_fade_enabled,
			g3_container_fade_duration,
			int(g3_container_fade_ease),
			g3_scale_enabled,
			g3_scale_duration,
			g3_scale_from,
			int(g3_scale_curve),
			g3_translation_enabled,
			g3_translation_duration,
			g3_translation_offset_x,
			g3_translation_offset_y,
			int(g3_translation_curve_x),
			int(g3_translation_curve_y),
		]
	)


func _pre_hide_board() -> void:
	if not (board_view and is_instance_valid(board_view)) or board_view.is_queued_for_deletion():
		return
	if board_view is CanvasItem:
		_set_alpha(board_view as CanvasItem, 0.0)
	var cells: Array = []
	_collect_cells_recursive(board_view, cells)
	for cell in cells:
		if is_instance_valid(cell) and not cell.is_queued_for_deletion():
			_set_alpha(cell as CanvasItem, 0.0)


func _set_alpha(node: CanvasItem, alpha: float) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	var col := node.modulate
	col.a = alpha
	node.modulate = col


func _set_scale(node: Node, scl: Vector2) -> void:
	if node is Node2D:
		(node as Node2D).scale = scl
	elif node is Control:
		(node as Control).scale = scl


func _center_pivot(node: Node) -> void:
	if node is Control:
		var c := node as Control
		c.pivot_offset = c.size / 2.0


func _get_position(node: Node) -> Vector2:
	if node is Node2D:
		return (node as Node2D).position
	elif node is Control:
		return (node as Control).position
	return Vector2.ZERO


func _set_position(node: Node, pos: Vector2) -> void:
	if node is Node2D:
		(node as Node2D).position = pos
	elif node is Control:
		(node as Control).position = pos


func _cfg_save_curve(
	cfg: ConfigFile, section: String, preset_base: String, key: String, curve: Curve
) -> void:
	if curve == null:
		return
	var path := curve.resource_path
	if path.is_empty():
		path = _PRESET_DIR + "/" + preset_base + "_" + key + ".tres"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_PRESET_DIR))
		ResourceSaver.save(curve, path)
	cfg.set_value(section, key + "_path", path)


func _cfg_load_curve(cfg: ConfigFile, section: String, key: String, default: Curve) -> Curve:
	var path: String = cfg.get_value(section, key + "_path", "")
	if path.is_empty():
		return default
	if ResourceLoader.exists(path):
		return load(path) as Curve
	push_warning("BoardContainerCell_01: Curve 文件不存在：%s" % path)
	return default


func _ease_t(t: float, ease_type: AutoAnimCurve.EaseType, custom_curve: Curve) -> float:
	if ease_type == AutoAnimCurve.EaseType.CUSTOM and custom_curve != null:
		return custom_curve.sample(t)
	if ease_type == AutoAnimCurve.EaseType.LINEAR:
		return t
	return Tween.interpolate_value(0.0, 1.0, t, 1.0, _get_trans(ease_type), _get_ease(ease_type))


func _get_trans(ease_type: AutoAnimCurve.EaseType) -> Tween.TransitionType:
	match ease_type:
		AutoAnimCurve.EaseType.SINE_IN, AutoAnimCurve.EaseType.SINE_OUT, AutoAnimCurve.EaseType.SINE_IN_OUT:
			return Tween.TRANS_SINE
		AutoAnimCurve.EaseType.QUAD_IN, AutoAnimCurve.EaseType.QUAD_OUT, AutoAnimCurve.EaseType.QUAD_IN_OUT:
			return Tween.TRANS_QUAD
		AutoAnimCurve.EaseType.CUBIC_IN, AutoAnimCurve.EaseType.CUBIC_OUT, AutoAnimCurve.EaseType.CUBIC_IN_OUT:
			return Tween.TRANS_CUBIC
		AutoAnimCurve.EaseType.QUART_IN, AutoAnimCurve.EaseType.QUART_OUT, AutoAnimCurve.EaseType.QUART_IN_OUT:
			return Tween.TRANS_QUART
		AutoAnimCurve.EaseType.QUINT_IN, AutoAnimCurve.EaseType.QUINT_OUT, AutoAnimCurve.EaseType.QUINT_IN_OUT:
			return Tween.TRANS_QUINT
		AutoAnimCurve.EaseType.EXPO_IN, AutoAnimCurve.EaseType.EXPO_OUT, AutoAnimCurve.EaseType.EXPO_IN_OUT:
			return Tween.TRANS_EXPO
		AutoAnimCurve.EaseType.CIRC_IN, AutoAnimCurve.EaseType.CIRC_OUT, AutoAnimCurve.EaseType.CIRC_IN_OUT:
			return Tween.TRANS_CIRC
		AutoAnimCurve.EaseType.BACK_IN, AutoAnimCurve.EaseType.BACK_OUT, AutoAnimCurve.EaseType.BACK_IN_OUT:
			return Tween.TRANS_BACK
		AutoAnimCurve.EaseType.ELASTIC_IN, AutoAnimCurve.EaseType.ELASTIC_OUT, AutoAnimCurve.EaseType.ELASTIC_IN_OUT:
			return Tween.TRANS_ELASTIC
		AutoAnimCurve.EaseType.BOUNCE_IN, AutoAnimCurve.EaseType.BOUNCE_OUT, AutoAnimCurve.EaseType.BOUNCE_IN_OUT:
			return Tween.TRANS_BOUNCE
	return Tween.TRANS_LINEAR


func _get_ease(ease_type: AutoAnimCurve.EaseType) -> Tween.EaseType:
	var offset := (ease_type - AutoAnimCurve.EaseType.SINE_IN) % 3
	match offset:
		1:
			return Tween.EASE_OUT
		2:
			return Tween.EASE_IN_OUT
		_:
			return Tween.EASE_IN
