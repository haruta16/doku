class_name DraftDoubleTapOperation
extends BaseDoubleTapOperation





func on_double_tap(r: int, c: int) -> Array[CellAction]:
    var out: Array[CellAction] = []
    var cur: int = board.get_cell_state(r, c)
    if not CellState.is_blank(cur):
        return out
    if cur == CellState.DRAFT_CAT:
        out.append(CellAction.set_draft(r, c, CellState.EMPTY))
    else:
        out.append(CellAction.set_draft(r, c, CellState.DRAFT_CAT))
    return out
