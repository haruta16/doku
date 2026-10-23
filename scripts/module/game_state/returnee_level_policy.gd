## 回流降难度的纯规则：判断触发资格、扣减次数，以及降低策略段位。
class_name ReturneeLevelPolicy
extends RefCounted


## 要求离线达到指定天数、命中回流实验组，并且本次冷启动还未触发。
static func can_start(
	gap_days: int, group: int, started_this_cold_start: bool, required_days: int = 3
) -> bool:
	return (
		gap_days >= required_days
		and (group == 12001 or group == 12002)
		and not started_this_cold_start
	)


## 普通题交付后消耗一次回流额度；固定特殊题不消耗。
static func remaining_after_delivery(remaining: int, is_fixed_sp: bool) -> int:
	return maxi(0, remaining - (0 if is_fixed_sp else 1))


## 把区间上界降一级，但不低于原下界。
static func easier_upper(lower: int, upper: int) -> int:
	return maxi(lower, upper - 1)


## 把策略段位降一级，并守住调用方给出的最低段位。
static func new_easier_rank(old_rank: int, minimum: int) -> int:
	return maxi(minimum, old_rank - 1)
