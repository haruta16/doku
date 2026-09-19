# 手势识别器：把拖拽坐标翻译成格子坐标，交给当前方案的 Operation，产出 CellAction 列表
class_name BoardGestureRecognizer
extends RefCounted

# ---- 依赖与手态势 ----
var board: BoardView # 棋盘视图：坐标换算与格子状态都问它
var active_scheme: BoardInputScheme # 当前生效的输入方案
var _stroke := BoardStrokeContext.new() # 这一笔的共享状态
var _last_tap_cell: Vector2i = Vector2i(-1, -1) # 上一次点击的格子，(-1,-1) 表示窗口已关闭


# 绑定棋盘视图
func _init(p_board: BoardView) -> void:
	board = p_board


# ================= 拖拽入口（页面调用） =================
# 按下：同一格短时间内再次按下算双击，否则按点击处理
func on_drag_start(pos: Vector2) -> Array[CellAction]:
	var cell: Vector2i = _resolve_cell(pos)
	var r: int = cell.y
	var c: int = cell.x

	# 命中上一次点击的格子 → 判定双击，并关掉判定窗口
	if _last_tap_cell == Vector2i(r, c):
		_last_tap_cell = Vector2i(-1, -1)
		_stroke.reset()
		return active_scheme.double_tap_op.on_double_tap(r, c)

	# 新的一笔：记录起点
	_stroke.reset()
	_stroke.start_cell = Vector2i(r, c)
	_stroke.last_cell = Vector2i(r, c)
	var actions: Array[CellAction] = active_scheme.tap_op.on_tap(r, c, _stroke)

	# 只有点击真的产生动作时才开双击窗口，避免空点占位
	if not actions.is_empty():
		_open_double_tap_window(r, c)
	return actions


# 拖动中：补齐经过的格子并交给滑动操作逐格产出动作
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


# 抬手：把结束时机交给滑动操作，然后清空手势状态
func on_drag_end() -> void:
	active_scheme.swipe_op.on_end(_stroke)
	_stroke.reset()


# 切换 normal/draft 方案时调用：清掉未完成的手势与双击窗口
func reset_for_scheme_switch() -> void:
	_last_tap_cell = Vector2i(-1, -1)
	_stroke.reset()


# ================= 内部工具 =================
# 屏幕坐标 → 格子坐标；子类 SwipeGuardRecognizer 覆写它做轴向锁定
func _resolve_cell(pos: Vector2) -> Vector2i:
	return board.pointer_to_cell(pos.x, pos.y)


# 开启 0.35 秒双击窗口；超时没等到第二次按下就自动失效
func _open_double_tap_window(r: int, c: int) -> void:
	_last_tap_cell = Vector2i(r, c)
	board.get_tree().create_timer(0.35).timeout.connect(
		func() -> void:
			if _last_tap_cell == Vector2i(r, c):
				_last_tap_cell = Vector2i(-1, -1)
	)
