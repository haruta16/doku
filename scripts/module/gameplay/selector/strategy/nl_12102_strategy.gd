## 普通关卡策略 normal_level_12102：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12102Strategy
extends NL12100Strategy

const MIN_LEVEL: int = 51


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12102"


func _normal_level_override(ctx: LevelSelectContext) -> Dictionary:
	if ctx.level_num < MIN_LEVEL:
		return {}
	var verdict: int = _pass_time_verdict()
	var adjusted: int = PassTimeDda.adjusted_size(ctx.sz, verdict)
	if adjusted == ctx.sz:
		return {}
	return {"sz": adjusted}
