extends AbConfigBase
class_name SingleRegionNumConfig

const VALUE_DEFAULT: int = 0
const VALUE_LIMITED: int = 1
const VALUE_STRICT: int = 2


func _init() -> void:
	key = "single_region_num"
	default_value = VALUE_DEFAULT
	timing = ABTestManager.TIMING_GAME_START_NORMAL


func is_single_region_limited() -> bool:
	return value() == VALUE_LIMITED


func is_strict_limited_at(level_num: int) -> bool:
	return value() == VALUE_STRICT and level_num >= 21
