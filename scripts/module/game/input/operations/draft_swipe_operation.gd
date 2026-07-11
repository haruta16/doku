class_name DraftSwipeOperation
extends BaseSwipeOperation


func on_paint(r: int, c: int, stroke: BoardStrokeContext, _is_current: bool) -> CellAction:
	var cur: int = board.get_cell_state(r, c)
	if not CellState.is_blank(cur):
		return null
	if cur == CellState.DRAFT_CAT:
		return null
	if cur == stroke.target_state:
		return null
	return CellAction.set_draft(r, c, stroke.target_state)
