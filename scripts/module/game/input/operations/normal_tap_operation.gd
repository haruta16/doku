# 正常模式点击：空白/草稿 → 打叉，已有叉 → 取消，猫与错误叉、锁定叉不响应
class_name NormalTapOperation
extends BaseTapOperation


# 单击一格，返回最多一个改状态动作
func on_tap(r: int, c: int, stroke: BoardStrokeContext) -> Array[CellAction]:
	var out: Array[CellAction] = []

	# 先读当前状态，产物与 before 都以它为准
	var cur: int = board.get_cell_state(r, c)

	# 猫、错误叉、锁定叉都不可改：冻结目标状态，避免随后的滑动误改
	if cur == CellState.CAT or cur == CellState.ERROR or cur == CellState.LOCKED_MARK:
		stroke.target_pending = true
		stroke.target_state = CellState.EMPTY
		return out
	# 空白（含草稿）→ 打叉；已有叉 → 清空
	stroke.target_pending = false
	stroke.target_state = CellState.MARK if CellState.is_blank(cur) else CellState.EMPTY

	# 空白首格：写下叉（草稿格也按 EMPTY 记录 before）
	if CellState.is_blank(cur):
		out.append(
			CellAction.set_cell(r, c, CellState.EMPTY, CellState.MARK, VibrateManager.Level.LEVEL2)
		)
	# 已有叉：取消
	elif cur == CellState.MARK:
		out.append(
			CellAction.set_cell(r, c, CellState.MARK, CellState.EMPTY, VibrateManager.Level.LEVEL2)
		)
	return out
