# 点赞式反馈实验：决定猫会做哪些「肯定」动作并给出优先级；0=全关 1~3=单选一种 4~9=按优先级组合，可追加纠错欢呼与漏猫提醒
extends AbConfigBase
class_name ThumbUpConfig

# ---- 分组取值 ----
const VALUE_DISABLE_ALL: int = 0 # 全部关闭
const VALUE_LIKE_ONLY: int = 1 # 只点赞
const VALUE_CLAP_ONLY: int = 2 # 只鼓掌
const VALUE_BLOW_TRUMPET_ONLY: int = 3 # 只吹号
const VALUE_ALL_BY_PRIORITY: int = 4 # 吹号 > 鼓掌 > 点赞
const VALUE_CORRECTION_CHEER: int = 5 # 再加纠错欢呼
const VALUE_MISSED_CAT: int = 6 # 再加漏猫提醒
const VALUE_HAWK_EYE: int = 7 # 漏猫提醒换成专属动画
const VALUE_ALL_FIVE: int = 8 # 五种反馈全开
const VALUE_ALL_FIVE_RELAXED: int = 9 # 全开，但点赞间隔放宽

# 反馈类型；枚举顺序即默认优先级
enum Feedback { BLOW_TRUMPET, CLAP, LIKE, CORRECTION_CHEER, MISSED_CAT }

# 档位 → 允许的反馈列表，列表顺序就是出场优先级；空列表表示全部关闭
const _PRIORITY_MAP: Dictionary = {
	0: [],
	1: [Feedback.LIKE],
	2: [Feedback.CLAP],
	3: [Feedback.BLOW_TRUMPET],
	4: [Feedback.BLOW_TRUMPET, Feedback.CLAP, Feedback.LIKE],
	5: [Feedback.CORRECTION_CHEER, Feedback.BLOW_TRUMPET, Feedback.CLAP, Feedback.LIKE],
	6: [Feedback.BLOW_TRUMPET, Feedback.CLAP, Feedback.LIKE, Feedback.MISSED_CAT],
	7: [Feedback.BLOW_TRUMPET, Feedback.CLAP, Feedback.LIKE, Feedback.MISSED_CAT],
	8:
	[
		Feedback.CORRECTION_CHEER,
		Feedback.BLOW_TRUMPET,
		Feedback.CLAP,
		Feedback.LIKE,
		Feedback.MISSED_CAT
	],
	9:
	[
		Feedback.CORRECTION_CHEER,
		Feedback.BLOW_TRUMPET,
		Feedback.CLAP,
		Feedback.LIKE,
		Feedback.MISSED_CAT
	],
}


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "thumb_up"
	default_value = VALUE_DISABLE_ALL # 默认档：全部关闭
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 取该档位的反馈优先级列表；未知档位返回空数组
func get_priority_list() -> Array:
	var v: int = value()
	if _PRIORITY_MAP.has(v):
		return _PRIORITY_MAP[v]
	return []


# 该反馈是否属于当前档位
func is_feedback_enabled(feedback: Feedback) -> bool:
	return get_priority_list().has(feedback)


# 取该反馈要播的动画编号；同一种反馈在不同档位下编号可能不同
func get_anim_id_for(feedback: Feedback) -> int:
	var v: int = value()
	match feedback:
		Feedback.LIKE:
			if v == VALUE_ALL_FIVE or v == VALUE_ALL_FIVE_RELAXED:
				return 3
			return 0
		Feedback.CLAP:
			return 1
		Feedback.BLOW_TRUMPET:
			return 2
		Feedback.CORRECTION_CHEER:
			return 4
		Feedback.MISSED_CAT:
			if v == VALUE_ALL_FIVE or v == VALUE_ALL_FIVE_RELAXED:
				return 0
			if v == VALUE_HAWK_EYE:
				return 5
			return 3
	return 0


# 点赞间隔覆盖值（秒）：仅档位 9 返回 20/30 秒，其余 -1 表示用默认间隔
func get_like_interval_override(board_size: int) -> float:
	if value() != VALUE_ALL_FIVE_RELAXED:
		return -1.0
	if board_size <= 7:
		return 20.0
	return 30.0


# 是否播放点赞
func should_play_like() -> bool:
	return is_feedback_enabled(Feedback.LIKE)


# 是否播放鼓掌
func should_play_clap() -> bool:
	return is_feedback_enabled(Feedback.CLAP)


# 是否播放吹号
func should_play_blow_trumpet() -> bool:
	return is_feedback_enabled(Feedback.BLOW_TRUMPET)
