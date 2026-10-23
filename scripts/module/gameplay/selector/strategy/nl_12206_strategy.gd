## 普通关卡策略 normal_level_12206：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12206Strategy
extends NL12100Strategy

const SMALL_SIZE: int = 8

const SMALL_SIZE_LEVEL_DIGIT: int = 6


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12206"


func _resolve_board_size(level_num: int) -> int:
	if _ctx.is_hard or _ctx.is_super_hard or LevelData.is_special_level(level_num):
		return _ctx.sz
	if level_num < SuperHardSchedule.MIN_LEVEL or level_num % 10 != SMALL_SIZE_LEVEL_DIGIT:
		return _ctx.sz
	if GameState.get_super_hard_anchor() <= 0:
		return _ctx.sz
	print(
		(
			"[Level.SuperHardNextSmall] %s level=%d size %d → %d"
			% [String(get_strategy_id()), level_num, _ctx.sz, SMALL_SIZE]
		)
	)
	return SMALL_SIZE
