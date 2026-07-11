extends AbConfigBase
class_name ProgressEmphasisConfig

const VALUE_DEFAULT: int = 0
const VALUE_PROGRESS_BAR: int = 1


func _init() -> void:
	key = "progress_emphasis"
	default_value = VALUE_DEFAULT
	timing = ABTestManager.TIMING_GAME_START


func is_progress_bar() -> bool:
	return value() == VALUE_PROGRESS_BAR
