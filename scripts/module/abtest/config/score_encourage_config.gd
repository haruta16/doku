## 实验配置 score_encourage：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ScoreEncourageConfig

const VALUE_DISABLED: int = 0
const VALUE_FLY_EFFECT: int = 1
const VALUE_NON_ROUND: int = 2
const VALUE_MULTIPLIER: int = 3
const VALUE_SKILL_SCORE: int = 4
const VALUE_DEDUCTION: int = 5
const VALUE_LIFE_BONUS: int = 6
const VALUE_MULTIPLIER_SCROLL: int = 7
const VALUE_STEP_TIER_LARGE: int = 8
const VALUE_STEP_TIER_MID: int = 9
const VALUE_STEP_TIER_SMALL: int = 10

enum Tier { INSTANT, FAST, NORMAL, SLOWISH, SLOW, NONE }

const _TIER_MAX: Dictionary = {
	6: [1, 2, 3, 4],
	7: [1, 2, 3, 5],
	8: [1, 2, 4, 6],
	9: [2, 3, 5, 7],
	10: [2, 3, 5, 8],
	11: [2, 4, 6, 9],
	12: [2, 4, 6, 10],
}

const _TIER_BONUS: Dictionary = {
	VALUE_STEP_TIER_LARGE: [768, 512, 256, 128, 0],
	VALUE_STEP_TIER_MID: [512, 256, 128, 64, 0],
	VALUE_STEP_TIER_SMALL: [256, 128, 64, 0, 0],
}


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "score_encourage"
	default_value = VALUE_NON_ROUND


static func gain_for_combo(combo_count: int) -> int:
	var base: int = 576
	var step: int = 96
	var cap: int = 1440
	return mini(base + maxi(0, combo_count - 1) * step, cap)


func calc_gain(combo_count: int) -> int:
	return gain_for_combo(combo_count)


static func is_step_tier_group_for(group_value: int) -> bool:
	return group_value >= VALUE_STEP_TIER_LARGE and group_value <= VALUE_STEP_TIER_SMALL


func is_step_tier_group() -> bool:
	return is_step_tier_group_for(int(value()))


static func tier_of(board_size: int, step_delta: int) -> int:
	if step_delta <= 0:
		return Tier.NONE
	if not _TIER_MAX.has(board_size):
		return Tier.NONE
	var bounds: Array = _TIER_MAX[board_size]
	for i in bounds.size():
		if step_delta <= int(bounds[i]):
			return i
	return Tier.SLOW


static func tier_bonus_for(group_value: int, board_size: int, step_delta: int) -> int:
	if not is_step_tier_group_for(group_value):
		return 0
	var tier: int = tier_of(board_size, step_delta)
	if tier == Tier.NONE:
		return 0
	var bonus_table: Array = _TIER_BONUS[group_value]
	return int(bonus_table[tier])


func calc_step_tier_bonus(board_size: int, step_delta: int) -> int:
	return tier_bonus_for(int(value()), board_size, step_delta)


static func amortized_step(total_step: int, correct_cat_count: int) -> int:
	if correct_cat_count <= 0:
		return -1
	return maxi(1, roundi(total_step / float(correct_cat_count)))


static func tier_name(tier: int) -> String:
	match tier:
		Tier.INSTANT:
			return "INSTANT"
		Tier.FAST:
			return "FAST"
		Tier.NORMAL:
			return "NORMAL"
		Tier.SLOWISH:
			return "SLOWISH"
		Tier.SLOW:
			return "SLOW"
		Tier.NONE:
			return "NONE"
	return "UNKNOWN(%d)" % tier
