extends AbConfigBase
class_name FailTextConfig

const VALUE_CONTROL: int = 0
const VALUE_PROGRESS_TEXT: int = 1
const VALUE_REVIVE_PROMOTE: int = 2


func _init() -> void:
	key = "fail_text"
	default_value = VALUE_CONTROL
	timing = ABTestManager.TIMING_GAME_END


func should_show_encourage() -> bool:
	return value() >= VALUE_PROGRESS_TEXT


func should_show_revive_promote() -> bool:
	return value() == VALUE_REVIVE_PROMOTE
