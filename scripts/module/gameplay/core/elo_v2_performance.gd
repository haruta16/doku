## 第二版 Elo 表现分：分别根据通关用时与局内行为评分，再提供随局数递减的更新系数。
class_name EloV2Performance
extends RefCounted

const INITIAL_RATING: float = 1200.0


## 用时低于中位数的 80% 得 1 分，高于 120% 得 0 分；边界和中间区间得 0.5。
static func score_for_time(time_total: int, median_sec: int) -> float:
	if time_total < 0 or median_sec <= 0:
		push_error(
			"EloV2Performance: invalid time_total=%d median_sec=%d" % [time_total, median_sec]
		)
		return 0.5
	var scaled_time: int = time_total * 5
	if scaled_time < median_sec * 4:
		return 1.0
	if scaled_time > median_sec * 6:
		return 0.0
	return 0.5


## 有死亡得 0 分；无重开、道具和耗鱼且满血得 1 分，其余得 0.5。
static func score_for_behavior(
	restart_count: int, used_tool: bool, fish_consumed: int, death_count: int, full_hp: bool
) -> float:
	if death_count > 0:
		return 0.0
	if restart_count == 0 and not used_tool and fish_consumed == 0 and full_hp:
		return 1.0
	return 0.5


## 前十局、第二个十局和后续分别使用 48、32、16 的评分更新系数。
static func k_for_games(games_before: int) -> float:
	if games_before < 10:
		return 48.0
	return 32.0 if games_before < 20 else 16.0
