extends AbConfigBase
class_name DailyFirstLevelDifficultyConfig

const VALUE_CONTROL: int = 0
const VALUE_REDUCE_ONE: int = 1


func _init() -> void:
	key = "daily_first_level_difficulty"
	default_value = VALUE_CONTROL
	timing = ABTestManager.TIMING_APP_START


func is_enabled() -> bool:
	return value() == VALUE_REDUCE_ONE
