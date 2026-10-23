## 普通关卡策略 LevelSelectionStrategy：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name LevelSelectionStrategy
extends RefCounted


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &""


## 声明策略实现版本，和实验组标识一起描述当前选题规则。
func get_strategy_version() -> int:
	return 1


func select(_request: LevelSelectRequest) -> Dictionary:
	return {}


func on_delivery(_entry: Dictionary) -> void:
	pass


func on_level_won_settlement(_ctx: LevelSettlementContext) -> void:
	pass


func elo_v2_performance_score(_facts: Dictionary) -> float:
	return -1.0


func is_hard_level(level_num: int) -> bool:
	return level_num >= 21 and level_num % 10 == 0


func is_super_hard_level(_level_num: int) -> bool:
	return false


func max_strategy_at(level_num: int) -> int:
	if level_num >= 201:
		return 6
	if level_num >= 101:
		return 5
	if level_num >= 51:
		return 4
	if level_num >= 21:
		return 3
	return 2
