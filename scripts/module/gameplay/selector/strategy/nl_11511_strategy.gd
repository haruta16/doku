## 普通关卡策略 normal_level_11511：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL11511Strategy
extends LevelSelectionStrategy

var _control: NLControlStrategy


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_11511"


## 声明策略实现版本，和实验组标识一起描述当前选题规则。
func get_strategy_version() -> int:
	return 1


func select(request: LevelSelectRequest) -> Dictionary:
	if _control == null:
		_control = NLControlStrategy.new()
	return _control.select(request)
