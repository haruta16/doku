## 滑动保护识别器：结合经过区域与保护窗口，决定本次涂抹是否允许修改格子。
class_name SwipeGuardRecognizer
extends BoardGestureRecognizer

const LOCK_THRESHOLD: int = 4

# ---- 防误滑判定器 ----
var _guard := SwipeAxisGuard.new() # 轴向锁定器：判断这一笔沿行还是沿列


func on_drag_start(pos: Vector2, is_physical_press_on_cell: bool = true) -> Array[CellAction]:
	_guard.begin(
		board.get_puzzle_size(),
		board.get_grid_slot(),
		board.get_grid_padding(),
		BoardView.CELL_PX,
		board.pointer_to_cell(pos.x, pos.y)
	)

	var actions: Array[CellAction] = super(pos, is_physical_press_on_cell)

	_configure_guard()
	_push_zone()
	return actions


## 拖动中：先让父类处理，再在目标状态刚确定时重新评估锁定
func on_drag_over(pos: Vector2) -> Array[CellAction]:
	# target_pending 刚被消费 → 这一笔的目标状态已定，此时才知道要不要保护
	var was_pending: bool = _stroke.target_pending

	var actions: Array[CellAction] = super(pos)
	if was_pending and not _stroke.target_pending:
		_guard.set_active(_guard_active_now())
	_push_zone()
	return actions


## 抬手：父类收尾 + 解除锁定 + 清掉棋盘的调试显示
func on_drag_end() -> void:
	super()
	_guard.end()

	board.update_swipe_protection_zone({})


# ================= 判定与调试 =================
## 覆写坐标换算：先过判定器，把坐标吸附到锁定的行/列上
func _resolve_cell(pos: Vector2) -> Vector2i:
	return _guard.process(pos.x, pos.y)


func _guard_active_now() -> bool:
	return not _stroke.target_pending and _stroke.target_state != CellState.EMPTY


func _can_paint_cell(cell: Vector2i) -> bool:
	var state: int = board.get_cell_state(cell.y, cell.x)
	if state == CellState.CAT or state == CellState.ERROR:
		return false
	return state != _stroke.target_state


func _configure_guard() -> void:
	var cfg: SwipeProtectConfig = ABTestManager.swipe_protect
	_guard.configure(
		_guard_active_now(), LOCK_THRESHOLD, SwipeProtectConfig.HOTZONE_TOL_PCT * BoardView.CELL_PX
	)

	if cfg.has_target_color_protection():
		_guard.configure_target_color(
			true,
			cfg.target_color_tol_pct() * BoardView.CELL_PX,
			_can_paint_cell,
			board.get_regions()
		)


## 把锁定状态推给棋盘，用于调试可视化
func _push_zone() -> void:
	board.update_swipe_protection_zone(_guard.get_debug_lock())
