## 每日首局降难度修饰器：只作用于没有强制层级的普通关，并消费 GameState 中的当日资格。
class_name DailyFirstEasyModifier
extends RefCounted


## 返回选题跟踪使用的每日首局修饰器标识。
func get_modifier_id() -> StringName:
	return &"daily_first_easy"


## 满足当日资格且策略高于一时降一级，消费并标记资格后同步层级和档位。
static func apply(ctx: LevelSelectContext) -> void:
	if ctx.rank_override > 0 or ctx.is_hard or ctx.is_super_hard:
		return
	if not GameState.is_daily_first_easy_available():
		return
	if ctx.strategy <= 1:
		return
	ctx.strategy -= 1
	GameState.consume_daily_first_easy_and_mark()
	ctx.rank = LevelData.strategy_to_rank(ctx.strategy)
	ctx.tier = LevelData.strategy_to_tier(ctx.strategy)
