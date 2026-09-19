# 草稿模式点击：空格画草稿叉，已有草稿清空，正式标记不响应
class_name DraftTapOperation
extends BaseTapOperation


# 单击一格，返回最多一个改草稿动作
func on_tap(r: int, c: int, stroke: BoardStrokeContext) -> Array[CellAction]:
	var out: Array[CellAction] = []
	# 只处理空白格（含草稿），猫与正式叉不响应
	var cur: int = board.get_cell_state(r, c)
	if not CellState.is_blank(cur):
		return out
	# 目标状态与本次动作保持一致，供随后的滑动沿用
	stroke.target_pending = false
	# 空格 → 画草稿叉
	if cur == CellState.EMPTY:
		stroke.target_state = CellState.DRAFT_CROSS
		out.append(CellAction.set_draft(r, c, CellState.DRAFT_CROSS))
	# 已有草稿（叉或猫）→ 清掉
	else:
		stroke.target_state = CellState.EMPTY
		out.append(CellAction.set_draft(r, c, CellState.EMPTY))
	return out
