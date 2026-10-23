## 困难关修饰器：结合当前策略的关号规则，把困难关上下文切到 R5 普通档。
class_name HardLevelModifier
extends RefCounted


## 返回困难关修饰器的跟踪标识。
func get_modifier_id() -> StringName:
	return &"hard"


## 强制层级优先于困难关规则，否则按关号判定并改写 rank 与 tier。
static func apply(ctx: LevelSelectContext) -> void:
	if ctx.rank_override > 0:
		ctx.is_hard = false
		return
	ctx.is_hard = LevelSelector.is_hard_level(ctx.level_num)
	if ctx.is_hard:
		ctx.rank = 5
		ctx.tier = "N"
