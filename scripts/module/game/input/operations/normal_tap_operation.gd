## 普通模式点击操作：把一次确定的点击转为正式格子的状态变更。
class_name NormalTapOperation
extends BaseTapOperation


func on_tap(r: int, c: int, stroke: BoardStrokeContext) -> Array[CellAction]:
	var out: Array[CellAction] = []

	var cur: int = board.get_cell_state(r, c)

	if cur == CellState.CAT:
		stroke.target_pending = true
		stroke.target_state = CellState.EMPTY
		return out
	stroke.target_pending = false
	stroke.target_state = CellState.MARK if CellState.is_blank(cur) else CellState.EMPTY

	if CellState.is_blank(cur):
		out.append(
			CellAction.set_cell(r, c, CellState.EMPTY, CellState.MARK, VibrateManager.Level.LEVEL2)
		)
	elif cur == CellState.MARK:
		out.append(
			CellAction.set_cell(r, c, CellState.MARK, CellState.EMPTY, VibrateManager.Level.LEVEL2)
		)
	return out
