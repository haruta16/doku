## 正常点击适配：纯规则决定目标，输入层保留手势上下文和震动意图。
class_name NormalTapOperation
extends BaseTapOperation

func on_tap(r: int, c: int, stroke: BoardStrokeContext) -> Array[CellAction]:
	var out: Array[CellAction] = []
	var decision: Dictionary = DokuActionRules.tap(board.get_cell_state(r, c), false)
	stroke.target_pending = decision.pending
	stroke.target_state = decision.target
	if decision.allowed:
		out.append(CellAction.set_cell(r, c, decision.before, decision.target, VibrateManager.Level.LEVEL2))
	return out
