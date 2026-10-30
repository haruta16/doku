## 草稿划动适配：正式标记和草稿猫的保护规则由纯模块定义。
class_name DraftSwipeOperation
extends BaseSwipeOperation

func on_paint(r: int, c: int, stroke: BoardStrokeContext, _is_current: bool) -> CellAction:
	var decision: Dictionary = DokuActionRules.swipe(board.get_cell_state(r, c), true, stroke.target_state, false)
	return CellAction.set_draft(r, c, decision.target) if decision.allowed else null
