# 草稿模式双击：在空白格上切换草稿猫，正式标记不响应
class_name DraftDoubleTapOperation
extends BaseDoubleTapOperation


# 双击一格
func on_double_tap(r: int, c: int) -> Array[CellAction]:
	var out: Array[CellAction] = []
	# 只处理空白格（含草稿）
	var cur: int = board.get_cell_state(r, c)
	if not CellState.is_blank(cur):
		return out
	# 已是草稿猫 → 取消
	if cur == CellState.DRAFT_CAT:
		out.append(CellAction.set_draft(r, c, CellState.EMPTY))
	# 空格或草稿叉 → 画草稿猫
	else:
		out.append(CellAction.set_draft(r, c, CellState.DRAFT_CAT))
	return out
