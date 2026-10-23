## 滑动行列锁定的调试层：显示核心带、容错带和目标颜色保护范围，帮助核对 SwipeAxisGuard。
class_name SwipeZoneDebugOverlay
extends Control

const CELL_PX: int = 100

# ---- 布局参数（由 BoardView 注入，与棋盘同一套像素换算） ----
var _slot: int = 0 # 单格槽位边长（像素，含间隙，= BoardView.SLOT_PX）
var _padding: int = 0 # 棋盘四周留白（像素，= BoardView.BOARD_PADDING）
var _n: int = 0 # 棋盘边长（行列数）
# ---- 运行时状态 ----
var _enabled: bool = false # 是否显示（cheat 命令 toggle_swipe_zone_viz 切换）
var _lock: Dictionary = {} # 当前锁定带 {"axis","value","tol"}，空字典表示未锁定

var _regions: Array = []


## 进树即设成不吃鼠标、画在最上层：只负责显示，不参与输入
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE # 鼠标事件穿透
	z_index = 100 # 画在棋盘与格子之上


## 注入棋盘布局尺寸并清空旧锁定带（BoardView._ensure_zone_viz 调用）
func configure(slot_px: int, padding: int, puzzle_size: int) -> void:
	_slot = slot_px
	_padding = padding
	_n = puzzle_size
	_lock = {}
	queue_redraw()


## 保存区域图，为目标颜色保护带的绘制提供区域编号。
func set_regions(regions: Array) -> void:
	_regions = regions
	if _enabled:
		queue_redraw()


## 开关显示；不改变已有锁定数据
func set_enabled(on: bool) -> void:
	_enabled = on
	queue_redraw()


## 更新锁定带数据；关闭状态下只存不重绘
func set_zone(lock: Dictionary) -> void:
	_lock = lock
	if _enabled: # 只有显示中才需要重绘
		queue_redraw()


## 根据锁定轴绘制行带或列带，并可叠加相邻目标区域的额外保护。
func _draw() -> void:
	if not _enabled:
		return

	_draw_geometry_hud()
	if _lock.is_empty():
		return
	if not _lock.has("axis"):
		return
	var extent: float = _padding * 2 + _slot * _n
	var idx: int = _lock["value"]
	var tol: float = _lock["tol"]
	var core0: float = _padding + idx * _slot
	var core1: float = _padding + (idx + 1) * _slot
	var band0: float = core0 - tol
	var band1: float = core1 + tol
	var fill := Color(0.1, 0.9, 0.35, 0.16)
	var core := Color(0.1, 0.9, 0.35, 0.3)
	var edge := Color(0.1, 1.0, 0.45, 0.95)
	if _lock["axis"] == SwipeAxisGuard.Axis.ROW:
		draw_rect(Rect2(0.0, band0, extent, band1 - band0), fill)
		draw_rect(Rect2(0.0, core0, extent, core1 - core0), core)
		draw_line(Vector2(0.0, band0), Vector2(extent, band0), edge, 3.0)
		draw_line(Vector2(0.0, band1), Vector2(extent, band1), edge, 3.0)
	else:
		draw_rect(Rect2(band0, 0.0, band1 - band0, extent), fill)
		draw_rect(Rect2(core0, 0.0, core1 - core0, extent), core)
		draw_line(Vector2(band0, 0.0), Vector2(band0, extent), edge, 3.0)
		draw_line(Vector2(band1, 0.0), Vector2(band1, extent), edge, 3.0)

	if _lock.get("target_color_protection", false):
		_draw_target_color_bands(
			int(_lock.get("target_region", -1)),
			float(_lock.get("target_tol", tol)),
			core0,
			core1,
			_lock["axis"] == SwipeAxisGuard.Axis.ROW
		)


## 显示单格、槽位、容错距离及目标区域等当前调试参数。
func _draw_geometry_hud() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var font_size: int = 20
	var color := Color(1.0, 1.0, 1.0, 0.85)
	var bg := Color(0.0, 0.0, 0.0, 0.55)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("格子: %d px" % CELL_PX)
	lines.append("Slot: %d px" % _slot)
	var tol_str: String = "-"
	if not _lock.is_empty() and _lock.has("tol"):
		tol_str = "%.0f px" % float(_lock["tol"])
	lines.append("Tol : %s" % tol_str)

	if _lock.get("target_color_protection", false):
		var region_id: int = int(_lock.get("target_region", -2))
		var region_str: String = (
			"失效" if region_id == -1 else ("未定" if region_id < -1 else str(region_id))
		)
		lines.append("目标色: %s" % region_str)
		lines.append("T-Tol: %.0f px" % float(_lock.get("target_tol", 0.0)))

	var pad: float = 6.0
	var line_h: int = font_size + 4
	var max_w: float = 0.0
	for s: String in lines:
		var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if w > max_w:
			max_w = w
	var box := Rect2(8.0, 8.0, max_w + pad * 2.0, lines.size() * line_h + pad * 2.0)
	draw_rect(box, bg)
	for i: int in lines.size():
		var y: float = box.position.y + pad + (i + 1) * line_h - 6.0
		draw_string(
			font,
			Vector2(box.position.x + pad, y),
			lines[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color
		)


## 只在相邻行列中属于目标区域的格子旁绘制额外保护带。
func _draw_target_color_bands(
	target_region: int, target_tol: float, core0: float, core1: float, is_row_locked: bool
) -> void:
	if target_region < 0 or _regions.is_empty():
		return
	var fill := Color(0.15, 0.95, 0.95, 0.34)
	var edge := Color(0.35, 1.0, 1.0, 0.98)
	var locked_idx: int = int(_lock["value"])
	for neighbor: int in [locked_idx - 1, locked_idx + 1]:
		if neighbor < 0 or neighbor >= _n:
			continue
		var toward_neg: bool = neighbor < locked_idx

		var band_start: float = core0 - target_tol if toward_neg else core1
		var line_at: float = core0 - target_tol if toward_neg else core1 + target_tol
		for along: int in _n:
			if _region_of(neighbor, along, is_row_locked) != target_region:
				continue
			var a0: float = _padding + along * _slot
			if target_tol > 0.0:
				if is_row_locked:
					draw_rect(Rect2(a0, band_start, _slot, target_tol), fill)
				else:
					draw_rect(Rect2(band_start, a0, target_tol, _slot), fill)
			if is_row_locked:
				draw_line(Vector2(a0, line_at), Vector2(a0 + _slot, line_at), edge, 3.0)
			else:
				draw_line(Vector2(line_at, a0), Vector2(line_at, a0 + _slot), edge, 3.0)


## 根据锁定轴换算行列坐标，越界时返回无效区域编号。
func _region_of(neighbor: int, along: int, is_row_locked: bool) -> int:
	var row: int = neighbor if is_row_locked else along
	var col: int = along if is_row_locked else neighbor
	if row < 0 or row >= _regions.size():
		return -1
	var row_data: Array = _regions[row]
	if col < 0 or col >= row_data.size():
		return -1
	return int(row_data[col])
