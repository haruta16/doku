## 超难关上下文修饰器：固定十一阶棋盘，再根据超难题库当前位置同步策略与档位。
class_name SuperHardModifier
extends RefCounted

const SIZE: int = 11


## 按超难标记加载题库，再交给可注入题库的处理入口。
static func apply(ctx: LevelSelectContext, is_super_hard: bool, anchor_level: int) -> void:
	var bank: Array = BankData.get_all_super_hard_levels() if is_super_hard else []
	apply_with_bank(ctx, is_super_hard, anchor_level, bank)


## 强制层级时关闭超难标记，否则为超难关设置尺寸并从题库取难度。
static func apply_with_bank(
	ctx: LevelSelectContext, is_super_hard: bool, anchor_level: int, bank: Array
) -> void:
	if ctx.rank_override > 0 or not is_super_hard:
		ctx.is_super_hard = false
		return
	ctx.is_super_hard = true
	ctx.sz = SIZE
	_apply_difficulty_from_bank(ctx, anchor_level, bank)


## 按锚点计算超难题位置，将题目层级和档位还原成上下文策略。
static func _apply_difficulty_from_bank(
	ctx: LevelSelectContext, anchor_level: int, bank: Array
) -> void:
	var strategy: int = 4
	if not bank.is_empty():
		var pos: Dictionary = SuperHardSchedule.bank_pos(ctx.level_num, anchor_level, bank.size())
		var e: Dictionary = bank[int(pos.get("idx", 0))] as Dictionary

		strategy = LevelData.rank_tier_to_strategy(int(e.get("r", 4)), String(e.get("tier", "N")))
	ctx.strategy = strategy
	ctx.rank = LevelData.strategy_to_rank(strategy)
	ctx.tier = LevelData.strategy_to_tier(strategy)


## 返回超难关修饰器标识。
func get_modifier_id() -> StringName:
	return &"super_hard"
