# 带防误滑的手势识别器：在父类基础上用 SwipeAxisGuard 锁死这一笔的行/列，避免手抖把线画歪
class_name SwipeGuardRecognizer
extends BoardGestureRecognizer

# ---- 防误滑判定器 ----
var _guard := SwipeAxisGuard.new() # 轴向锁定器：判断这一笔沿行还是沿列


# ================= 覆写父类的手势入口 =================
# 按下：先初始化判定器，再走父类的双击/点击逻辑，最后同步保护参数
func on_drag_start(pos: Vector2) -> Array[CellAction]:
	# 用当前棋盘几何与原始起点格初始化（起点不受锁定影响）
	_guard.begin(
		board.get_puzzle_size(),
		BoardView.SLOT_PX,
		BoardView.BOARD_PADDING,
		BoardView.CELL_PX,
		board.pointer_to_cell(pos.x, pos.y)
	)
	# 判定是否该锁定，并把锁定状态推给棋盘做调试显示
	var actions: Array[CellAction] = super(pos)
	_configure_guard()
	_push_zone()
	return actions


# 拖动中：先让父类处理，再在目标状态刚确定时重新评估锁定
func on_drag_over(pos: Vector2) -> Array[CellAction]:
	# target_pending 刚被消费 → 这一笔的目标状态已定，此时才知道要不要保护
	var was_pending: bool = _stroke.target_pending
	var actions: Array[CellAction] = super(pos)
	if was_pending and not _stroke.target_pending:
		_guard.set_active(_guard_active_now())
	_push_zone()
	return actions


# 抬手：父类收尾 + 解除锁定 + 清掉棋盘的调试显示
func on_drag_end() -> void:
	super()
	_guard.end()
	board.update_swipe_protection_zone({})


# ================= 判定与调试 =================
# 覆写坐标换算：先过判定器，把坐标吸附到锁定的行/列上
func _resolve_cell(pos: Vector2) -> Vector2i:
	return _guard.process(pos.x, pos.y)


# 现在是否该锁定：AB 开关开着 + 尺寸达标 + 目标状态已定且非空
func _guard_active_now() -> bool:
	return (
		_swipe_guard_enabled_for_level()
		and not _stroke.target_pending
		and _stroke.target_state != CellState.EMPTY
	)


# 当前关卡是否启用防误滑（AB 分组 + 棋盘尺寸下限）
func _swipe_guard_enabled_for_level() -> bool:
	var cfg: SwipeProtectConfig = ABTestManager.swipe_protect
	return cfg.is_enabled() and board.get_puzzle_size() >= cfg.min_size()


# 把 AB 配置换算成判定器的参数
func _configure_guard() -> void:
	var cfg: SwipeProtectConfig = ABTestManager.swipe_protect
	var n: int = board.get_puzzle_size()
	var threshold: int = cfg.threshold_for(n)
	var tol_px: float = cfg.tolerance_pct() * BoardView.CELL_PX
	_guard.configure(_guard_active_now(), threshold, tol_px)


# 把锁定状态推给棋盘，用于调试可视化
func _push_zone() -> void:
	board.update_swipe_protection_zone(_guard.get_debug_lock())
