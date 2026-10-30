## 棋盘网格自绘层：区分普通格线、区域边界和外框，并按统一时间播放生长入场动画。
@tool
class_name BoardGridOverlay
extends Control

const GRID_THIN_WIDTH: float = 3.0
const GRID_THICK_WIDTH: float = 5.0
const GRID_BORDER_WIDTH: float = 7.0

const GRID_FRAME_CORNER_RADIUS: int = 30

const GRID_THICK_CORNER_RADIUS: float = 0.1

const GRID_THIN_START: float = 0.1
const GRID_THIN_DUR: float = 0.75
const GRID_FRAME_DUR: float = 0.75
const GRID_FRAME_LEAD: float = 0.2

const GRID_THIN_COLOR := Color(0.41960785, 0.22352941, 0.22352941)
const GRID_THICK_COLOR := Color(0.41960785, 0.22352941, 0.22352941)

const _INTRO_STOP_MARGIN: float = 0.05

var board: BoardView = null

var _grid_elapsed: float = 99999.0
var _intro_active: bool = false

var _sync_total_dur: float = 0.0

var _regions: Array = []
var _puzzle_size: int = 0
var _pad: float = 0.0
var _slot: float = 100.0

var _thick_edge_segments: Array = []


## 接收区域图和棋盘尺寸，从 BoardView 读取布局参数并重建粗边界。
func configure(regions: Array, puzzle_size: int) -> void:
	_regions = regions
	_puzzle_size = puzzle_size
	if board != null and is_instance_valid(board):
		_pad = float(board._grid_padding)
		_slot = float(board._grid_slot)
	_rebuild_thick_edge_segments()
	queue_redraw()


## 重置入场计时并启用逐帧绘制；可指定与外部动画对齐的总时长。
func begin_grid_intro(sync_total_dur: float = 0.0) -> void:
	_sync_total_dur = maxf(sync_total_dur, 0.0)
	_grid_elapsed = 0.0
	_intro_active = true
	set_process(true)
	queue_redraw()


## 根据同步总时长推导格线生长时长，否则使用默认值。
func _line_dur() -> float:
	if _sync_total_dur > 0.0:
		return maxf(_sync_total_dur - GRID_THIN_START, 0.01)
	return GRID_THIN_DUR


## 根据同步总时长推导外框动画时长，否则使用默认值。
func _frame_dur() -> float:
	return (
		maxf(_sync_total_dur - GRID_FRAME_LEAD, 0.01) if _sync_total_dur > 0.0 else GRID_FRAME_DUR
	)


## 取格线与外框的最晚结束时间，并留少量停止余量。
func _intro_end() -> float:
	return maxf(GRID_THIN_START + _line_dur(), _frame_dur()) + _INTRO_STOP_MARGIN


## 直接显示完整网格，同时停止逐帧更新。
func set_terminal() -> void:
	_grid_elapsed = 99999.0
	_intro_active = false
	set_process(false)
	queue_redraw()


## 默认关闭逐帧处理，只有入场动画期间才开启。
func _ready() -> void:
	set_process(false)


## 推进动画时间并重绘；完整显示后关闭处理以减少空转。
func _process(delta: float) -> void:
	if not _intro_active:
		set_process(false)
		return
	_grid_elapsed += delta
	queue_redraw()
	if _grid_elapsed >= _intro_end():
		_grid_elapsed = 99999.0
		_intro_active = false
		set_process(false)


## 把当前动画进度交给统一的网格绘制流程。
func _draw() -> void:
	_paint_grid(self)


## 比较相邻格子的区域编号，缓存区域之间的横竖粗边界。
func _rebuild_thick_edge_segments() -> void:
	_thick_edge_segments.clear()
	var n: int = _puzzle_size
	if n == 0 or _regions.size() != n:
		return
	for row in _regions:
		if (row as Array).size() != n:
			return
	var x0b: float = _pad
	var y0b: float = _pad
	for r in range(n):
		for c in range(n):
			var rid: int = int(_regions[r][c])
			if c + 1 < n and int(_regions[r][c + 1]) != rid:
				var xr: float = x0b + float(c + 1) * _slot
				(
					_thick_edge_segments
					. append(
						{
							"a": Vector2(xr, y0b + float(r) * _slot),
							"b": Vector2(xr, y0b + float(r + 1) * _slot),
							"is_h": false,
						}
					)
				)
			if r + 1 < n and int(_regions[r + 1][c]) != rid:
				var yb: float = y0b + float(r + 1) * _slot
				(
					_thick_edge_segments
					. append(
						{
							"a": Vector2(x0b + float(c) * _slot, yb),
							"b": Vector2(x0b + float(c + 1) * _slot, yb),
							"is_h": true,
						}
					)
				)


## 按棋盘布局绘制细线、区域粗线与圆角外框，并补偿棋盘缩放后的线宽。
func _paint_grid(canvas: CanvasItem) -> void:
	if _puzzle_size == 0 or board == null or not is_instance_valid(board):
		return
	var s: float = board.scale.x if board.scale.x > 0.0 else 1.0

	var bg_origin: Vector2 = Vector2.ZERO
	if Engine.is_editor_hint():
		var intrinsic: Vector2 = BoardView.intrinsic_size_for(_puzzle_size)
		bg_origin = Vector2(
			maxf(0.0, (board.size.x - intrinsic.x) * 0.5),
			maxf(0.0, (board.size.y - intrinsic.y) * 0.5),
		)
	var n: int = _puzzle_size
	var x0: float = bg_origin.x + _pad
	var y0: float = bg_origin.y + _pad
	var span: float = float(n) * _slot
	var grid_rect: Rect2 = Rect2(Vector2(x0, y0), Vector2(span, span))
	var left: float = x0
	var right: float = x0 + span
	var top: float = y0
	var bottom: float = y0 + span
	var ring_max: float = float(2 * (n - 1))
	var thin_prog: float = clampf(
		(_grid_elapsed - GRID_THIN_START) / maxf(_line_dur(), 0.0001), 0.0, 1.0
	)
	var front: float = thin_prog * (ring_max + 1.0)

	var regions_ok: bool = _regions.size() == n
	if regions_ok:
		for row in _regions:
			if (row as Array).size() != n:
				regions_ok = false
				break
	if regions_ok:
		var thin_w: float = GRID_THIN_WIDTH / s

		for k in range(1, n):
			var p: float = float(k) * _slot
			_draw_grow_line(
				canvas,
				Vector2(x0 + p, top),
				Vector2(x0 + p, bottom),
				GRID_THIN_COLOR,
				thin_w,
				front,
				x0,
				y0,
				n
			)
			_draw_grow_line(
				canvas,
				Vector2(left, y0 + p),
				Vector2(right, y0 + p),
				GRID_THIN_COLOR,
				thin_w,
				front,
				x0,
				y0,
				n
			)

		var thick_w: float = GRID_THICK_WIDTH / s
		var seg_ts: Array = []
		var seg_root_a: Array = []
		seg_ts.resize(_thick_edge_segments.size())
		seg_root_a.resize(_thick_edge_segments.size())
		for i in _thick_edge_segments.size():
			var sdi0: Dictionary = _thick_edge_segments[i]
			var pa0: Vector2 = sdi0["a"]
			var pb0: Vector2 = sdi0["b"]
			var ring_a: float = (pa0.x - x0) / _slot - (pa0.y - y0) / _slot + float(n - 1)
			var ring_b: float = (pb0.x - x0) / _slot - (pb0.y - y0) / _slot + float(n - 1)
			var r_lo: float = minf(ring_a, ring_b)
			var r_hi: float = maxf(ring_a, ring_b)
			seg_root_a[i] = ring_a <= ring_b
			seg_ts[i] = clampf((front - r_lo) / maxf(r_hi - r_lo, 0.0001), 0.0, 1.0)

		for i in _thick_edge_segments.size():
			var seg_t: float = seg_ts[i]
			if seg_t <= 0.0:
				continue
			var sd: Dictionary = _thick_edge_segments[i]
			var a: Vector2 = (sd["a"] as Vector2) + bg_origin
			var b: Vector2 = (sd["b"] as Vector2) + bg_origin
			var root_end: Vector2 = a if seg_root_a[i] else b
			var far_end: Vector2 = b if seg_root_a[i] else a
			if seg_t >= 1.0:
				canvas.draw_line(root_end, far_end, GRID_THICK_COLOR, thick_w, true)
			else:
				canvas.draw_line(
					root_end, root_end.lerp(far_end, seg_t), GRID_THICK_COLOR, thick_w, true
				)

	var frame_prog: float = clampf(_grid_elapsed / maxf(_frame_dur(), 0.0001), 0.0, 1.0)

	_draw_grow_frame(
		canvas, grid_rect, float(GRID_FRAME_CORNER_RADIUS) / s, GRID_BORDER_WIDTH / s, frame_prog
	)


## 将外框拆成两条路径，按同一进度绘制两侧生长。
func _draw_grow_frame(
	canvas: CanvasItem, rect: Rect2, rf: float, width: float, progress: float
) -> void:
	if progress <= 0.0:
		return
	var paths: Array = _frame_half_paths(rect, rf)
	_draw_polyline_grow(canvas, paths[0], width, progress)
	_draw_polyline_grow(canvas, paths[1], width, progress)


## 从左下侧出发构造绕外框的两条圆角路径。
func _frame_half_paths(rect: Rect2, rf: float) -> Array:
	var x0f: float = rect.position.x
	var y0f: float = rect.position.y
	var x1f: float = rect.position.x + rect.size.x
	var y1f: float = rect.position.y + rect.size.y
	var arc_steps: int = 90
	var _arc_pts := func(cx: float, cy: float, a_from: float, a_to: float) -> PackedVector2Array:
		var out: PackedVector2Array = PackedVector2Array()
		for k in range(arc_steps + 1):
			var t: float = float(k) / float(arc_steps)
			var ang: float = lerpf(a_from, a_to, t)
			out.append(Vector2(cx + cos(ang) * rf, cy + sin(ang) * rf))
		return out
	var path_a: PackedVector2Array = PackedVector2Array()
	path_a.append_array(_arc_pts.call(x0f + rf, y1f - rf, PI, PI * 0.5))
	path_a.append(Vector2(x1f - rf, y1f))
	path_a.append_array(_arc_pts.call(x1f - rf, y1f - rf, PI * 0.5, 0.0))
	path_a.append(Vector2(x1f, y0f + rf))
	path_a.append_array(_arc_pts.call(x1f - rf, y0f + rf, 0.0, -PI * 0.5))
	var path_b: PackedVector2Array = PackedVector2Array()
	path_b.append(Vector2(x0f, y1f - rf))
	path_b.append(Vector2(x0f, y0f + rf))
	path_b.append_array(_arc_pts.call(x0f + rf, y0f + rf, -PI, -PI * 0.5))
	path_b.append(Vector2(x1f - rf, y0f))
	return [path_a, path_b]


## 按路径总长度截取当前进度，允许最后一段只绘制一部分。
func _draw_polyline_grow(
	canvas: CanvasItem, pts: PackedVector2Array, width: float, progress: float
) -> void:
	if pts.size() < 2 or progress <= 0.0:
		return
	var total: float = 0.0
	for k in range(1, pts.size()):
		total += pts[k].distance_to(pts[k - 1])
	if total <= 0.0:
		return
	var draw_len: float = progress * total
	var acc: float = 0.0
	for k in range(1, pts.size()):
		var p0: Vector2 = pts[k - 1]
		var p1: Vector2 = pts[k]
		var seg: float = p0.distance_to(p1)
		if seg <= 0.0001:
			continue
		if acc + seg <= draw_len:
			canvas.draw_line(p0, p1, GRID_THICK_COLOR, width, true)
		else:
			var remain: float = draw_len - acc
			if remain > 0.0:
				canvas.draw_line(p0, p0.lerp(p1, remain / seg), GRID_THICK_COLOR, width, true)
			break
		acc += seg


## 按 x−y 方向的推进前沿裁切线段，使格线从同一方向逐步显现。
func _draw_grow_line(
	canvas: CanvasItem,
	a: Vector2,
	b: Vector2,
	color: Color,
	width: float,
	front: float,
	x0: float,
	y0: float,
	n: int
) -> void:
	var ring_a: float = (a.x - x0) / _slot - (a.y - y0) / _slot + float(n - 1)
	var ring_b: float = (b.x - x0) / _slot - (b.y - y0) / _slot + float(n - 1)
	var pa: Vector2 = a
	var pb: Vector2 = b
	var ra: float = ring_a
	var rb: float = ring_b
	if ra > rb:
		pa = b
		pb = a
		ra = ring_b
		rb = ring_a
	if front <= ra:
		return
	if front >= rb:
		canvas.draw_line(pa, pb, color, width, true)
		return
	var t: float = (front - ra) / maxf(rb - ra, 0.0001)
	canvas.draw_line(pa, pa.lerp(pb, t), color, width, true)
