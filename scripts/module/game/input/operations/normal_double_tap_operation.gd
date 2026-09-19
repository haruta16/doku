# 正常模式双击：非猫格产出 DOUBLE_TAP 动作，由页面判断该格是不是答案（是则落猫，否则记一次猜错）
class_name NormalDoubleTapOperation
extends BaseDoubleTapOperation


# 双击一格
func on_double_tap(r: int, c: int) -> Array[CellAction]:
	var out: Array[CellAction] = []
	# 已经是猫的格子不再双击
	if board.get_cell_state(r, c) == CellState.CAT:
		return out
	# 只发坐标，含义交给页面解释
	out.append(CellAction.double_tap(r, c))
	return out
