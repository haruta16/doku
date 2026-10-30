## 普通关卡策略 normal_level_12205：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12205Strategy
extends NL12100Strategy

const SUPER_HARD_MIN_LEVEL: int = 55


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12205"


func is_super_hard_level(level_num: int) -> bool:
	return level_num >= SUPER_HARD_MIN_LEVEL and super.is_super_hard_level(level_num)
