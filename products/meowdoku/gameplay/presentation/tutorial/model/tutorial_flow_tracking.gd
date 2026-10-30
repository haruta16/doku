## 教程步骤统计：把屏幕步骤转换为完成事件编号，供教程流程记录。
extends RefCounted


static func finish_screen_step(is_new_guide_flow: bool, is_confirm_step_removed: bool) -> int:
	if is_new_guide_flow or is_confirm_step_removed:
		return -1
	return 8


static func completion_step(is_new_guide_flow: bool, _is_confirm_step_removed: bool) -> int:
	if is_new_guide_flow:
		return -1
	return 9
