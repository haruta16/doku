class_name DraftTapOperation
extends BaseTapOperation


func on_tap(r: int, c: int, stroke: BoardStrokeContext) -> Array[CellAction]:
	var out: Array[CellAction] = []
	var cur: int = board.get_cell_state(r, c)
	if not CellState.is_blank(cur):
		return out
	stroke.target_pending = false
	if cur == CellState.EMPTY:
		stroke.target_state = CellState.DRAFT_CROSS
		out.append(CellAction.set_draft(r, c, CellState.DRAFT_CROSS))
	else:
		stroke.target_state = CellState.EMPTY
		out.append(CellAction.set_draft(r, c, CellState.EMPTY))
	return out
