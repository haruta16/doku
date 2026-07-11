extends AbConfigBase
class_name GoalEmphasisConfig

const VALUE_CONTROL: int = 0
const VALUE_SPLIT_BY_LEVEL: int = 1

const LEVEL_THRESHOLD: int = 10


func _init() -> void:
	key = "goal_emphasis"
	default_value = VALUE_CONTROL

	timing = ABTestManager.TIMING_GAME_START_NORMAL_11


func should_emphasize_cat_score(level: int) -> bool:
	return value() == VALUE_SPLIT_BY_LEVEL and level > LEVEL_THRESHOLD
