## 策略层级修饰器：结合玩家存档、关号上限和随机范围，得到本次选题层级。
class_name StrategyModifier
extends RefCounted


## 返回策略层级修饰器标识。
func get_modifier_id() -> StringName:
	return &"strategy"


## 把显式覆盖值写进策略、题库层级与档位。
static func apply_override(ctx: LevelSelectContext) -> void:
	ctx.strategy = ctx.rank_override
	ctx.rank = ctx.rank_override
	ctx.tier = LevelData.strategy_to_tier(ctx.rank_override)


## 按关段约束玩家策略，较高策略在 R2 至上限间抽取；必要时把最低策略修正写回存档。
static func apply_normal(ctx: LevelSelectContext) -> int:
	var cur: int = GameState.get_current_strategy()
	if ctx.level_num >= 51 and cur < 2:
		GameState.set_current_strategy(2)
	var strategy: int = LevelData.resolve_strategy(
		ctx.level_num, GameState.get_current_strategy(), 5
	)

	if ctx.level_num >= 51:
		strategy = mini(strategy, 4)
	elif ctx.level_num >= 21:
		strategy = mini(strategy, 3)
	else:
		strategy = mini(strategy, 2)

	var strategy_after_cap: int = strategy
	if strategy >= 3:
		strategy = LevelSelectionRandom.pick_in_range(2, strategy)

	ctx.strategy = strategy
	ctx.rank = LevelData.strategy_to_rank(strategy)
	ctx.tier = LevelData.strategy_to_tier(strategy)
	return strategy_after_cap
