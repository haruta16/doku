## 普通关卡策略 normal_level_12106：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12106Strategy
extends NL12100Strategy

var _eased_this_select: bool = false


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12106"


func select(request: LevelSelectRequest) -> Dictionary:
	_eased_this_select = false
	var delivered: Dictionary = super.select(request)
	if _eased_this_select and delivered.has("entry"):
		var entry: Dictionary = delivered["entry"]
		entry[RetryPuzzleBuilder.ENTRY_KEY_HARD_NEIGHBOR_EASED] = true
	return delivered


func _normal_level_override(ctx: LevelSelectContext) -> Dictionary:
	if not _is_eased_neighbor(ctx.level_num):
		return {}
	var cap: int = _segment_strategy_cap(ctx.level_num)
	if ctx.strategy != cap:
		return {}
	_eased_this_select = true
	var eased: int = cap - 1
	print(
		(
			"[LEVEL.hard_neighbor_ease] %s lv=%d picked=R%d → eased=R%d"
			% [
				String(get_strategy_id()),
				ctx.level_num,
				LevelData.strategy_to_rank(ctx.strategy),
				LevelData.strategy_to_rank(eased)
			]
		)
	)
	return {"strategy": eased}


func _is_eased_neighbor(level_num: int) -> bool:
	return is_hard_level(level_num + 1) or is_super_hard_level(level_num + 1)
