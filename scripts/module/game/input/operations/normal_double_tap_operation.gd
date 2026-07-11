class_name NormalDoubleTapOperation
extends BaseDoubleTapOperation


func on_double_tap(r: int, c: int) -> Array[CellAction]:
	var out: Array[CellAction] = []
	if board.get_cell_state(r, c) == CellState.CAT:
		return out
	out.append(CellAction.double_tap(r, c))
	return out
