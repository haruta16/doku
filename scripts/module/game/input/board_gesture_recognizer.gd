## 棋盘手势识别器：把按下、经过与抬起整理为点击或涂抹，并管理待决双击窗口。
class_name BoardGestureRecognizer
extends RefCounted

const DEFAULT_DOUBLE_TAP_SEC: float = 0.35

# ---- 依赖与手态势 ----
var board: BoardView # 棋盘视图：坐标换算与格子状态都问它
var active_scheme: BoardInputScheme # 当前生效的输入方案
var _stroke := BoardStrokeContext.new() # 这一笔的共享状态
var _last_tap_cell: Vector2i = Vector2i(-1, -1) # 上一次点击的格子，(-1,-1) 表示窗口已关闭

var _double_tap_window_generation: int = 0

var _drag_start_serial: int = 0

var _window_drag_start_serial: int = 0
var _started_on_cat: bool = false

var window_sec_provider: Callable = Callable()

var cross_pointer_double_tap_provider: Callable = Callable()

var promote_to_double_tap_provider: Callable = Callable()

var autofix_target_provider: Callable = Callable()

var last_double_tap_promoted: bool = false

var _last_window_sec: float = DEFAULT_DOUBLE_TAP_SEC

var _dbg_win_open_ms: int = -1
var _dbg_win_open_cell: Vector2i = Vector2i(-1, -1)


## 绑定棋盘视图
func _init(p_board: BoardView) -> void:
	board = p_board


func on_drag_start(pos: Vector2, is_physical_press_on_cell: bool = true) -> Array[CellAction]:
	_drag_start_serial += 1
	var cell: Vector2i = _resolve_cell(pos)
	var row: int = cell.y
	var col: int = cell.x
	_started_on_cat = (
		is_physical_press_on_cell
		and cell.x >= 0
		and board.get_cell_state(row, col) == CellState.CAT
		and board.is_cat_visual_revealed(row, col)
	)
	_log_double_tap_interval(row, col)

	last_double_tap_promoted = false

	if try_consume_pending_tap(row, col):
		_stroke.reset()
		return active_scheme.double_tap_op.on_double_tap(row, col)

	if cross_pointer_double_tap_provider.is_valid():
		var consumed_cross_pointer: bool = cross_pointer_double_tap_provider.call(self, row, col)
		if consumed_cross_pointer:
			_stroke.reset()
			return active_scheme.double_tap_op.on_double_tap(row, col)

	if (
		board.get_cell_state(row, col) != CellState.CAT
		and promote_to_double_tap_provider.is_valid()
		and promote_to_double_tap_provider.call(row, col)
	):
		_last_tap_cell = Vector2i(-1, -1)
		_stroke.reset()
		last_double_tap_promoted = true
		return active_scheme.double_tap_op.on_double_tap(row, col)

	if autofix_target_provider.is_valid():
		var fixed_cell: Vector2i = autofix_target_provider.call(row, col, pos)
		if fixed_cell.x >= 0:
			_last_tap_cell = Vector2i(-1, -1)
			_stroke.reset()
			last_double_tap_promoted = true
			return active_scheme.double_tap_op.on_double_tap(fixed_cell.x, fixed_cell.y)

	_stroke.reset()
	_stroke.start_cell = Vector2i(row, col)
	_stroke.last_cell = Vector2i(row, col)
	var actions: Array[CellAction] = active_scheme.tap_op.on_tap(row, col, _stroke)

	if not actions.is_empty():
		_open_double_tap_window(row, col)
	return actions


## 拖动中：补齐经过的格子并交给滑动操作逐格产出动作
func on_drag_over(pos: Vector2) -> Array[CellAction]:
	var out: Array[CellAction] = []
	# 没有起点（没在拖动）直接返回
	if not _stroke.is_active():
		return out
	var cell: Vector2i = _resolve_cell(pos)
	if cell.x < 0:
		return out
	var r: int = cell.y
	var c: int = cell.x
	# 还在同一格上，跳过
	if Vector2i(r, c) == _stroke.last_cell:
		return out

	# 与上一格之间按长边步数线性补插中间格，避免快速滑动漏格
	var last: Vector2i = _stroke.last_cell
	var dr: int = r - last.x
	var dc: int = c - last.y
	var steps: int = maxi(absi(dr), absi(dc))
	for i in range(1, steps):
		var ir: int = last.x + int(roundi(float(dr) * i / steps))
		var ic: int = last.y + int(roundi(float(dc) * i / steps))
		var mid: CellAction = active_scheme.swipe_op.on_paint(ir, ic, _stroke, false)
		if mid != null:
			out.append(mid)
	# 记下已移动，供 Operation 区分点击与滑动
	_stroke.last_cell = Vector2i(r, c)
	_stroke.had_move = true
	# 指针真正所在的格：is_current = true，会带回震动反馈
	var cur: CellAction = active_scheme.swipe_op.on_paint(r, c, _stroke, true)
	if cur != null:
		out.append(cur)
	return out


func on_drag_end() -> void:
	active_scheme.swipe_op.on_end(_stroke)
	_stroke.reset()
	_started_on_cat = false


func finish_drag(release_pos: Vector2) -> bool:
	var release_cell: Vector2i = board.pointer_to_cell(release_pos.x, release_pos.y)
	var release_row_col := Vector2i(release_cell.y, release_cell.x)
	var start_cell: Vector2i = _stroke.start_cell
	var is_cat_click: bool = (
		_stroke.is_active()
		and release_cell.x >= 0
		and start_cell == release_row_col
		and _started_on_cat
	)
	on_drag_end()
	return is_cat_click


func reset_for_scheme_switch() -> void:
	_double_tap_window_generation += 1
	_last_tap_cell = Vector2i(-1, -1)
	_stroke.reset()
	_started_on_cat = false
	last_double_tap_promoted = false

	ABTestManager.doubletap_protect.reset_high_freq_state()
	_dbg_win_open_ms = -1
	_dbg_win_open_cell = Vector2i(-1, -1)


# ================= 内部工具 =================
## 屏幕坐标 → 格子坐标；子类 SwipeGuardRecognizer 覆写它做轴向锁定
func _resolve_cell(pos: Vector2) -> Vector2i:
	return board.pointer_to_cell(pos.x, pos.y)


func get_last_window_sec() -> float:
	return _last_window_sec


func has_pending_tap(r: int, c: int) -> bool:
	return _last_tap_cell == Vector2i(r, c)


func get_pending_tap_cell() -> Vector2i:
	return _last_tap_cell


func is_window_from_latest_drag_start() -> bool:
	return _last_tap_cell.x >= 0 and _window_drag_start_serial == _drag_start_serial


func try_consume_pending_tap(r: int, c: int) -> bool:
	if _last_tap_cell != Vector2i(r, c):
		return false

	_log_double_tap_interval(r, c)
	_clear_pending_tap()
	return true


func _open_double_tap_window(r: int, c: int) -> void:
	_double_tap_window_generation += 1
	var generation: int = _double_tap_window_generation
	_window_drag_start_serial = _drag_start_serial
	_last_tap_cell = Vector2i(r, c)

	var sec: float = DEFAULT_DOUBLE_TAP_SEC
	if window_sec_provider.is_valid():
		sec = window_sec_provider.call(r, c)
	_last_window_sec = sec
	_dbg_win_open_ms = Time.get_ticks_msec()
	_dbg_win_open_cell = Vector2i(r, c)
	board.get_tree().create_timer(sec).timeout.connect(
		func() -> void:
			if generation != _double_tap_window_generation:
				return
			if _last_tap_cell == Vector2i(r, c):
				_last_tap_cell = Vector2i(-1, -1)
	)


func _clear_pending_tap() -> void:
	_last_tap_cell = Vector2i(-1, -1)
	_dbg_win_open_ms = -1
	_dbg_win_open_cell = Vector2i(-1, -1)


func _log_double_tap_interval(r: int, c: int) -> void:
	if c < 0 or OS.has_feature("rel"):
		return
	if _dbg_win_open_ms < 0 or _dbg_win_open_cell != Vector2i(r, c):
		return
	var interval: int = Time.get_ticks_msec() - _dbg_win_open_ms
	var hit: bool = _last_tap_cell == Vector2i(r, c)
	print(
		(
			"[doubletap] cell=(%d,%d) interval=%dms window=%dms → %s"
			% [r, c, interval, int(round(_last_window_sec * 1000.0)), "HIT" if hit else "MISS"]
		)
	)

	_dbg_win_open_ms = -1
	_dbg_win_open_cell = Vector2i(-1, -1)
