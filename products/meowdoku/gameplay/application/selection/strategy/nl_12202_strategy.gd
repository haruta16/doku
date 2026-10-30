## 普通关卡策略 normal_level_12202：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12202Strategy
extends NL12201Strategy


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12202"


func _style_filter_active() -> bool:
	return false
