# 正常模式滑动：沿路打叉或擦叉，目标状态由起始格定下后整笔沿用
class_name NormalSwipeOperation
extends BaseSwipeOperation


# 滑动经过一格
func on_paint(r: int, c: int, stroke: BoardStrokeContext, is_current: bool) -> CellAction:
	# 当前格状态
	var state: int = board.get_cell_state(r, c)

	# 猫、错误叉、锁定叉挡路：这一格跳过
	if state == CellState.CAT or state == CellState.ERROR or state == CellState.LOCKED_MARK:
		return null

	# 起始格定调：空白就整笔画叉，已有叉就整笔擦叉
	if stroke.target_pending:
		stroke.target_state = CellState.MARK if CellState.is_blank(state) else CellState.EMPTY
		stroke.target_pending = false
	# 与目标状态相同，不用改
	if state == stroke.target_state:
		return null
	# 只有指针实际所在的格才震动，补插的中间格不震
	var vib: int = VibrateManager.Level.LEVEL2 if is_current else -1
	return CellAction.set_cell(r, c, state, stroke.target_state, vib)
