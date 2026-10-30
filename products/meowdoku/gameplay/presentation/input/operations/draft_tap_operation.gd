## 草稿点击适配：规则返回草稿目标，视图不承担草稿语义。
class_name DraftTapOperation
extends BaseTapOperation

func on_tap(r: int, c: int, stroke: BoardStrokeContext) -> Array[CellAction]:
	var out: Array[CellAction] = []
	var decision: Dictionary = DokuActionRules.tap(board.get_cell_state(r, c), true)
	if decision.allowed:
		stroke.target_pending = false
		stroke.target_state = decision.target
		out.append(CellAction.set_draft(r, c, decision.target))
	return out
