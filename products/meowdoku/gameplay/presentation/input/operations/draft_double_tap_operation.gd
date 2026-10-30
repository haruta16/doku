## 草稿双击适配：纯规则决定切换或拒绝。
class_name DraftDoubleTapOperation
extends BaseDoubleTapOperation

func on_double_tap(r: int, c: int) -> Array[CellAction]:
	var out: Array[CellAction] = []
	var decision: Dictionary = DokuActionRules.draft_double_tap(board.get_cell_state(r, c))
	if decision.allowed:
		out.append(CellAction.set_draft(r, c, decision.target))
	return out
