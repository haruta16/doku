## 实验配置 inter_prob：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name InterProbConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不做概率拦截
const VALUE_PROB_50_AT_3: int = 1 # 看过 3 次激励后，50% 概率放行
const VALUE_PROB_70_AT_2: int = 2 # 看过 2 次激励后，70% 概率放行
const VALUE_PROB_80_AT_1: int = 3 # 看过 1 次激励后，80% 概率放行
const VALUE_SESSION_HEAD_KEEP: int = 4
const VALUE_SESSION_EVEN: int = 5
const VALUE_SESSION_LIGHT: int = 6
const VALUE_SESSION_ANDROID_OPTIMIZED: int = 7
const VALUE_SESSION_ANDROID_LESS_CUT: int = 8
const VALUE_SESSION_ANDROID_DEEP_CUT: int = 9
const VALUE_SESSION_IOS_OPTIMIZED: int = 10
const VALUE_SESSION_IOS_LESS_CUT: int = 11
const VALUE_SESSION_IOS_DEEP_CUT: int = 12

const _LIVE_GROUPS: Array = [
	VALUE_PROB_80_AT_1,
	VALUE_SESSION_HEAD_KEEP,
	VALUE_SESSION_EVEN,
	VALUE_SESSION_LIGHT,
	VALUE_SESSION_ANDROID_OPTIMIZED,
	VALUE_SESSION_ANDROID_LESS_CUT,
	VALUE_SESSION_ANDROID_DEEP_CUT,
	VALUE_SESSION_IOS_OPTIMIZED,
	VALUE_SESSION_IOS_LESS_CUT,
	VALUE_SESSION_IOS_DEEP_CUT,
]

const _FALLBACK_GROUP: int = VALUE_PROB_80_AT_1

const REWARD_GATE_THRESHOLD: int = 1

const REWARD_GATE_PERCENT: int = 80

const PERCENT_NO_CUT: int = 100

const SESSION_CUT_END_DAY: int = 31

const _TIER_UPPERS: Array = [2, 4, 6, 9, 20, 50, 100]

const SHOW_PERCENT_BY_GROUP: Dictionary = {
	VALUE_SESSION_HEAD_KEEP: [100, 95, 90, 85, 82, 80, 78, 75],
	VALUE_SESSION_EVEN: [98, 96, 94, 92, 90, 85, 80, 75],
	VALUE_SESSION_LIGHT: [98, 97, 95, 92, 90, 88, 87, 85],
	VALUE_SESSION_ANDROID_OPTIMIZED: [99, 98, 97, 95, 94, 93, 92, 91],
	VALUE_SESSION_ANDROID_LESS_CUT: [99, 99, 98, 97, 96, 96, 95, 94],
	VALUE_SESSION_ANDROID_DEEP_CUT: [100, 100, 100, 100, 90, 85, 80, 75],
	VALUE_SESSION_IOS_OPTIMIZED: [100, 97, 94, 91, 89, 88, 86, 85],
	VALUE_SESSION_IOS_LESS_CUT: [99, 98, 97, 95, 94, 93, 92, 91],
	VALUE_SESSION_IOS_DEEP_CUT: [100, 100, 100, 100, 85, 80, 75, 75],
}


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "inter_prob"
	default_value = VALUE_PROB_80_AT_1


static func live_group_for(group: int) -> int:
	return group if group in _LIVE_GROUPS else _FALLBACK_GROUP


static func session_game_percent_for(
	group: int, session_game_count: int, living_days: int = 0
) -> int:
	if (
		has_post_gate_probability_for(group)
		and (living_days < 0 or living_days >= SESSION_CUT_END_DAY)
	):
		return PERCENT_NO_CUT
	var percents: Array = SHOW_PERCENT_BY_GROUP.get(live_group_for(group), [])
	if percents.is_empty():
		return PERCENT_NO_CUT
	for i in _TIER_UPPERS.size():
		if session_game_count <= int(_TIER_UPPERS[i]):
			return int(percents[i])
	return int(percents[_TIER_UPPERS.size()])


static func is_reward_gate_triggered_for(reward_view_count: int) -> bool:
	return reward_view_count >= REWARD_GATE_THRESHOLD


static func effective_percent_for(
	group: int, reward_view_count: int, session_game_count: int, living_days: int = 0
) -> int:
	var reward_percent: int = PERCENT_NO_CUT
	if is_reward_gate_triggered_for(reward_view_count):
		reward_percent = REWARD_GATE_PERCENT
	return mini(reward_percent, session_game_percent_for(group, session_game_count, living_days))


static func has_post_gate_probability_for(group: int, living_days: int = 0) -> bool:
	if living_days >= SESSION_CUT_END_DAY:
		return false
	return (
		live_group_for(group)
		in [
			VALUE_SESSION_ANDROID_OPTIMIZED,
			VALUE_SESSION_ANDROID_LESS_CUT,
			VALUE_SESSION_ANDROID_DEEP_CUT,
			VALUE_SESSION_IOS_OPTIMIZED,
			VALUE_SESSION_IOS_LESS_CUT,
			VALUE_SESSION_IOS_DEEP_CUT,
		]
	)


static func should_reset_cd_on_miss_for(
	group: int, reward_view_count: int, session_game_count: int, living_days: int = 0
) -> bool:
	if not has_post_gate_probability_for(group, living_days):
		return false
	var reward_percent: int = (
		REWARD_GATE_PERCENT if is_reward_gate_triggered_for(reward_view_count) else PERCENT_NO_CUT
	)
	return session_game_percent_for(group, session_game_count, living_days) < reward_percent


func has_post_gate_probability(living_days: int = 0) -> bool:
	return has_post_gate_probability_for(int(value()), living_days)


func live_group() -> int:
	return live_group_for(int(value()))


func has_session_game_gate() -> bool:
	return SHOW_PERCENT_BY_GROUP.has(live_group())


func session_game_percent(session_game_count: int, living_days: int = 0) -> int:
	return session_game_percent_for(int(value()), session_game_count, living_days)


func is_reward_gate_triggered(reward_view_count: int) -> bool:
	return is_reward_gate_triggered_for(reward_view_count)


func effective_percent(
	reward_view_count: int, session_game_count: int, living_days: int = 0
) -> int:
	return effective_percent_for(int(value()), reward_view_count, session_game_count, living_days)
