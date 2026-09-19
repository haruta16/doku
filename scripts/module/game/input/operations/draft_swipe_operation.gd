# 草稿模式滑动：在空白格上刷草稿标记，正式标记与草稿猫都跳过
class_name DraftSwipeOperation
extends BaseSwipeOperation


# 滑动经过一格
func on_paint(r: int, c: int, stroke: BoardStrokeContext, _is_current: bool) -> CellAction:
	# 当前格状态
	var cur: int = board.get_cell_state(r, c)
	# 正式标记（猫、叉、错误、锁定叉）不动
	if not CellState.is_blank(cur):
		return null
	# 草稿猫要双击才能改，滑过时不碰
	if cur == CellState.DRAFT_CAT:
		return null
	# 已经是目标状态，不用改
	if cur == stroke.target_state:
		return null
	return CellAction.set_draft(r, c, stroke.target_state)
