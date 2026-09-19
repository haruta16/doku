# V0（对照组）：不产出任何通关文案，等价于基类默认实现
class_name PassTextStrategyV0
extends PassTextStrategy


# 恒返回空结果；shown_percent=-1 表示本次不产出击败百分比
func get_win_text(_level_config: Dictionary) -> Dictionary:
	return {"title": "", "body": "", "shown_percent": -1.0}
