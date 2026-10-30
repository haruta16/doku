## 正常划动适配：规则只接收值，当前指针格的震动由输入层选择。
class_name NormalSwipeOperation
extends BaseSwipeOperation

func on_paint(r: int, c: int, stroke: BoardStrokeContext, is_current: bool) -> CellAction:
	var decision: Dictionary = DokuActionRules.swipe(board.get_cell_state(r, c), false, stroke.target_state, stroke.target_pending)
	if decision.has("target"):
		stroke.target_state = decision.target
		stroke.target_pending = decision.pending
	if not decision.allowed:
		return null
	return CellAction.set_cell(r, c, decision.before, decision.target, VibrateManager.Level.LEVEL2 if is_current else -1)
