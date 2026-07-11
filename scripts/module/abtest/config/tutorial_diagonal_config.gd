extends AbConfigBase
class_name TutorialDiagonalConfig

const VALUE_ADJACENT: int = 0
const VALUE_DIAGONAL: int = 2


func _init() -> void:
	key = "tutorial_diagonal"
	default_value = VALUE_ADJACENT
	timing = ABTestManager.TIMING_APP_START


func is_diagonal_copy() -> bool:
	return value() == VALUE_DIAGONAL
