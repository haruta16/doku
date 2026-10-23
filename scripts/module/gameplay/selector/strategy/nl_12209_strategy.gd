## 普通关卡策略 normal_level_12209：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12209Strategy
extends NL12100Strategy


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12209"


func select(request: LevelSelectRequest) -> Dictionary:
	HasAssistUserTag.refresh_async()
	return super.select(request)
