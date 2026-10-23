## 实验配置 cat_toast：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name CatToastConfig

const VALUE_OFF: int = 0

const VALUE_PHRASE: int = 1

const VALUE_WORD: int = 2

const VALUE_FIXED: int = 3

const MIN_BOARD_SIZE: int = 6

const MAX_TABLE_SIZE: int = 12

const FIXED_FIRST_CAT_SEC: float = 3.0

const FIXED_FIRST_CAT_STEPS: int = 4

const FIXED_SLOW_PLACE_SEC: float = 35.0

const FIXED_MANY_STEPS: int = 8

const THRESHOLDS_BY_SIZE: Dictionary = {
	6: [3.0, 3, 25.0, 6],
	7: [3.0, 4, 25.0, 6],
	8: [6.0, 4, 25.0, 6],
	9: [6.0, 4, 35.0, 8],
	10: [6.0, 5, 35.0, 8],
	11: [8.0, 5, 45.0, 9],
	12: [8.0, 5, 45.0, 9],
}

const IDX_FIRST_CAT_SEC: int = 0
const IDX_FIRST_CAT_STEPS: int = 1
const IDX_SLOW_PLACE_SEC: int = 2
const IDX_MANY_STEPS: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "cat_toast"
	default_value = VALUE_OFF


static func is_enabled_for(group: int) -> bool:
	return group == VALUE_PHRASE or group == VALUE_WORD or group == VALUE_FIXED


static func is_word_style_for(group: int) -> bool:
	return group == VALUE_WORD or group == VALUE_FIXED


static func is_fixed_text_for(group: int) -> bool:
	return group == VALUE_FIXED


static func is_fast_first_cat_for(
	group: int, board_size: int, elapsed_sec: float, steps: int
) -> bool:
	if not _is_size_eligible_for(group, board_size):
		return false
	if is_fixed_text_for(group):
		return elapsed_sec <= FIXED_FIRST_CAT_SEC or steps <= FIXED_FIRST_CAT_STEPS
	var row: Array = _row_for(board_size)
	return elapsed_sec <= float(row[IDX_FIRST_CAT_SEC]) or steps <= int(row[IDX_FIRST_CAT_STEPS])


static func is_slow_place_for(group: int, board_size: int, elapsed_sec: float) -> bool:
	if not _is_size_eligible_for(group, board_size):
		return false
	if is_fixed_text_for(group):
		return elapsed_sec >= FIXED_SLOW_PLACE_SEC
	var row: Array = _row_for(board_size)
	return elapsed_sec >= float(row[IDX_SLOW_PLACE_SEC])


static func is_many_steps_for(group: int, board_size: int, steps: int) -> bool:
	if not _is_size_eligible_for(group, board_size):
		return false
	if is_fixed_text_for(group):
		return steps >= FIXED_MANY_STEPS
	var row: Array = _row_for(board_size)
	return steps >= int(row[IDX_MANY_STEPS])


static func is_streak_eligible_for(group: int, board_size: int) -> bool:
	return _is_size_eligible_for(group, board_size)


static func _is_size_eligible_for(group: int, board_size: int) -> bool:
	return is_enabled_for(group) and board_size >= MIN_BOARD_SIZE


static func _row_for(board_size: int) -> Array:
	return THRESHOLDS_BY_SIZE[mini(board_size, MAX_TABLE_SIZE)]


func is_enabled() -> bool:
	return is_enabled_for(int(value()))


func is_word_style() -> bool:
	return is_word_style_for(int(value()))


func is_fixed_text() -> bool:
	return is_fixed_text_for(int(value()))


func is_fast_first_cat(board_size: int, elapsed_sec: float, steps: int) -> bool:
	return is_fast_first_cat_for(int(value()), board_size, elapsed_sec, steps)


func is_slow_place(board_size: int, elapsed_sec: float) -> bool:
	return is_slow_place_for(int(value()), board_size, elapsed_sec)


func is_many_steps(board_size: int, steps: int) -> bool:
	return is_many_steps_for(int(value()), board_size, steps)


func is_streak_eligible(board_size: int) -> bool:
	return is_streak_eligible_for(int(value()), board_size)
