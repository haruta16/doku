## 普通模式涂抹操作：接收手势识别器的经过格子，在正式棋盘上执行标记规则。
class_name NormalSwipeOperation
extends BaseSwipeOperation


func on_paint(r: int, c: int, stroke: BoardStrokeContext, is_current: bool) -> CellAction:
	var state: int = board.get_cell_state(r, c)

	if state == CellState.CAT or state == CellState.ERROR:
		return null

	if stroke.target_pending:
		stroke.target_state = CellState.MARK if CellState.is_blank(state) else CellState.EMPTY
		stroke.target_pending = false
	if state == stroke.target_state:
		return null
	var vib: int = VibrateManager.Level.LEVEL2 if is_current else -1
	return CellAction.set_cell(r, c, state, stroke.target_state, vib)
