extends AbConfigBase
class_name ThumbUpConfig

const VALUE_DISABLE_ALL: int = 0
const VALUE_LIKE_ONLY: int = 1
const VALUE_CLAP_ONLY: int = 2
const VALUE_BLOW_TRUMPET_ONLY: int = 3
const VALUE_ALL_BY_PRIORITY: int = 4
const VALUE_CORRECTION_CHEER: int = 5
const VALUE_MISSED_CAT: int = 6
const VALUE_HAWK_EYE: int = 7
const VALUE_ALL_FIVE: int = 8
const VALUE_ALL_FIVE_RELAXED: int = 9

enum Feedback { BLOW_TRUMPET, CLAP, LIKE, CORRECTION_CHEER, MISSED_CAT }

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


func _init() -> void:
	key = "thumb_up"
	default_value = VALUE_DISABLE_ALL
	timing = ABTestManager.TIMING_GAME_START


func get_priority_list() -> Array:
	var v: int = value()
	if _PRIORITY_MAP.has(v):
		return _PRIORITY_MAP[v]
	return []


func is_feedback_enabled(feedback: Feedback) -> bool:
	return get_priority_list().has(feedback)


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


func get_like_interval_override(board_size: int) -> float:
	if value() != VALUE_ALL_FIVE_RELAXED:
		return -1.0
	if board_size <= 7:
		return 20.0
	return 30.0


func should_play_like() -> bool:
	return is_feedback_enabled(Feedback.LIKE)


func should_play_clap() -> bool:
	return is_feedback_enabled(Feedback.CLAP)


func should_play_blow_trumpet() -> bool:
	return is_feedback_enabled(Feedback.BLOW_TRUMPET)
